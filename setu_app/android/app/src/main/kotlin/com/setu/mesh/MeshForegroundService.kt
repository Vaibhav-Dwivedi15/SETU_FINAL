package com.setu.mesh

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Owns the mesh transport + native relay engine, and survives independent
 * of MainActivity's lifecycle. This is what makes a bystander's phone an
 * actual silent carrier — not just "works while the app is open on screen."
 */
class MeshForegroundService : Service(), NearbyConnectionsManager.Listener {

    private lateinit var connectionsManager: NearbyConnectionsManager
    private lateinit var relayEngine: PacketRelayEngine
    private lateinit var stateStore: MeshStateStore
    private val binder = LocalBinder()

    /** Set by MeshChannelHandler when attached, cleared when detached.
     * Returns true only if the event was actually handed to a live Dart
     * listener; false means "nobody is listening right now", in which
     * case payload events are held in the bounded pending buffer below
     * (Block 1) instead of being dropped. */
    @Volatile
    var eventForwarder: ((Map<String, Any?>) -> Boolean)? = null

    // =====================================================
    // Block 1 (mesh-stability) -- bounded native -> Dart handoff buffer
    // =====================================================
    //
    // PacketRelayEngine marks a packet "seen" the moment it is verified,
    // so a payload forwarded while Dart is not listening (Activity not
    // yet created, app swiped away with this service still running, or
    // the brief window before the event-channel subscription exists)
    // would otherwise be lost for good: it was never uploaded and a later
    // copy would be filtered as a duplicate. Such payloads are queued
    // here, FIFO, and flushed in order once a listener attaches.
    //
    // This does NOT delay dedup or relaying -- both happen in
    // PacketRelayEngine.process() before this point, exactly as before.
    // It only holds the Dart-bound copy. In-memory only: a process kill
    // loses it (documented limitation). Bounded: when full, the OLDEST
    // pending event is discarded (and counted).
    private val handoff = HandoffBuffer<Map<String, Any?>>(MAX_PENDING_EVENTS)

    private fun deliverToDart(event: Map<String, Any?>) {
        if (!handoff.deliver(event, eventForwarder)) {
            if (handoff.dropped > 0 && handoff.size >= MAX_PENDING_EVENTS) {
                Log.w(TAG, "Pending Dart-handoff buffer full -- oldest events dropped (total dropped=${handoff.dropped})")
            }
        }
    }

    /** Called when a Dart listener attaches (or the forwarder is set). */
    fun flushPendingEvents() {
        val flushed = handoff.flush(eventForwarder)
        if (flushed > 0) Log.i(TAG, "Flushed $flushed buffered payload event(s) to Dart")
    }

    fun pendingEventCount(): Int = handoff.size

    /** Dart accepted a termination from an authorized responder. */
    fun markEmergencyClosed(emergencyId: String) {
        relayEngine.markEmergencyClosed(emergencyId)
    }

    inner class LocalBinder : Binder() {
        fun getService(): MeshForegroundService = this@MeshForegroundService
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        connectionsManager = NearbyConnectionsManager(applicationContext, this)
        relayEngine = PacketRelayEngine()
        stateStore = MeshStateStore(applicationContext)

        // Sep 21 2026 (Vib, Bulk Sprint 3): restore last-known policy and
        // dedup cache BEFORE starting discovery, so a START_STICKY restart
        // doesn't briefly run at full power / with an empty seen-cache
        // while waiting for Dart to reattach. See NATIVE_MESH_AUDIT.md §16
        // and NATIVE_FAILURE_MATRIX.md row 17 for the gap this closes.
        // If nothing was ever persisted (fresh install, or a build
        // predating this change), loadPolicy() returns null and the
        // pre-existing hardcoded defaults below are used unchanged.
        val persistedPolicy = stateStore.loadPolicy()
        if (persistedPolicy != null) {
            currentDiscoveryIntervalMs = persistedPolicy.discoveryIntervalMs
            currentAllowRelay = persistedPolicy.allowRelay
            Log.i(TAG, "Restored persisted mesh policy: discoveryIntervalMs=$currentDiscoveryIntervalMs allowRelay=$currentAllowRelay")
        }
        relayEngine.restoreSeen(stateStore.loadSeenIds())

        // Block 1: the persisted policy above is only a FALLBACK. If the
        // real battery level is readable, it wins -- otherwise a
        // power-saver policy persisted at <20% would keep relay disabled
        // after the phone was charged until Dart happened to re-sync.
        readBatteryPercent()?.let { applyBatteryLevel(it, restartDutyCycle = false) }

        startForegroundWithNotification()
        startDutyCycle()
        startStatePersistenceTimer()
        registerRadioStateReceiver()
        registerBatteryReceiver()
    }

    // =====================================================
    // Sep 21 2026 (Vib, Bulk Sprint 3) -- Bluetooth / Wi-Fi resume
    // =====================================================
    //
    // PRIOR BEHAVIOR (confirmed by source review, not assumed): startAdvertising()/
    // startDiscovery() attach only addOnFailureListener { Log.e(...) } --
    // if Bluetooth or Wi-Fi is off when these are called, or gets turned
    // off afterward, the failure is logged and NOTHING resumes advertising/
    // discovery automatically once the radio comes back on. The mesh
    // would stay silently inactive until the app/service was manually
    // restarted (e.g. by the user re-opening the app) -- a real gap for
    // exactly the scenario this app exists for (a bystander whose
    // Bluetooth happened to be off, or who toggled airplane mode and back).
    //
    // FIX: a BroadcastReceiver for both radios' state-changed broadcasts,
    // registered once in onCreate() and unregistered in onDestroy() (no
    // duplicate registration risk -- this service has exactly one
    // instance per process, and onCreate()/onDestroy() are each called
    // at most once per instance). On a transition to Bluetooth STATE_ON
    // or Wi-Fi WIFI_STATE_ENABLED, restart the duty cycle -- this is
    // exactly what startDutyCycle() already does on every policy update,
    // so no new advertising/discovery logic was written, only a new
    // trigger for calling the existing one.
    //
    // Scoped narrowly: this does NOT attempt to distinguish "radio came
    // back on because the user re-enabled it" from "radio came back on
    // for some other reason" -- any transition to ON is treated the same
    // way calling startDutyCycle() already is idempotent-safe to call
    // (STATUS_ALREADY_ADVERTISING is already handled by the existing
    // "don't double start in full-power tier" logic). No permission
    // beyond what Nearby Connections already requires is needed to
    // listen for these two system broadcasts.
    private var radioStateReceiver: BroadcastReceiver? = null

    private fun registerRadioStateReceiver() {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    BluetoothAdapter.ACTION_STATE_CHANGED -> {
                        val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1)
                        if (state == BluetoothAdapter.STATE_ON) {
                            Log.i(TAG, "Bluetooth turned back on -- resuming duty cycle")
                            scheduleRadioResume()
                        }
                    }
                    WifiManager.WIFI_STATE_CHANGED_ACTION -> {
                        val state = intent.getIntExtra(WifiManager.EXTRA_WIFI_STATE, -1)
                        if (state == WifiManager.WIFI_STATE_ENABLED) {
                            Log.i(TAG, "Wi-Fi turned back on -- resuming duty cycle")
                            scheduleRadioResume()
                        }
                    }
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(WifiManager.WIFI_STATE_CHANGED_ACTION)
        }
        registerSystemReceiver(receiver, filter)
        radioStateReceiver = receiver
    }

    private fun registerSystemReceiver(receiver: BroadcastReceiver, filter: IntentFilter) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
    }

    // Block 1: Bluetooth and Wi-Fi commonly come back on within the same
    // moment (airplane mode off). Coalesce them into ONE duty-cycle
    // restart instead of two back-to-back startAdvertising/startDiscovery
    // rounds.
    private val radioResumeRunnable = Runnable { startDutyCycle() }

    private fun scheduleRadioResume() {
        dutyCycleHandler.removeCallbacks(radioResumeRunnable)
        dutyCycleHandler.postDelayed(radioResumeRunnable, RADIO_RESUME_DEBOUNCE_MS)
    }

    // =====================================================
    // Block 1 (mesh-stability) -- native battery tier
    // =====================================================
    private var batteryReceiver: BroadcastReceiver? = null
    private var currentBatteryTier: String? = null

    private fun readBatteryPercent(): Int? {
        return try {
            val sticky = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) ?: return null
            val level = sticky.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = sticky.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            if (level < 0 || scale <= 0) null else (level * 100) / scale
        } catch (e: Exception) {
            null
        }
    }

    /** Applies the tier for [percent] if it differs from the one in force. */
    private fun applyBatteryLevel(percent: Int, restartDutyCycle: Boolean) {
        val tier = BatteryPolicy.forLevel(percent)
        if (tier.name == currentBatteryTier) return
        currentBatteryTier = tier.name
        currentDiscoveryIntervalMs = tier.discoveryIntervalMs
        currentAllowRelay = tier.allowRelay
        Log.i(TAG, "Battery tier -> ${tier.name} (level=$percent%) discoveryIntervalMs=${tier.discoveryIntervalMs} allowRelay=${tier.allowRelay}")
        if (::stateStore.isInitialized) stateStore.savePolicy(tier.discoveryIntervalMs, tier.allowRelay)
        if (restartDutyCycle) startDutyCycle()
    }

    // ACTION_BATTERY_CHANGED is a sticky system broadcast the OS already
    // sends on every level change; listening costs no polling.
    private fun registerBatteryReceiver() {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: return
                val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                if (level < 0 || scale <= 0) return
                applyBatteryLevel((level * 100) / scale, restartDutyCycle = true)
            }
        }
        registerSystemReceiver(receiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        batteryReceiver = receiver
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    private fun startForegroundWithNotification() {
        val channelId = "setu_mesh_channel"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "SETU Mesh", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }

        val notification: Notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("SETU active")
            .setContentText("Protecting nearby devices — relay running in background")
            .setSmallIcon(android.R.drawable.ic_dialog_info) // TODO: swap for real app icon later
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(1, notification)
        }
    }

    /** Called by MainActivity when the user originates a new packet (SOS). */
    fun originate(bytes: ByteArray, packetId: String) {
        relayEngine.rememberOriginated(packetId)
        connectionsManager.broadcastBytes(bytes)
    }

    // Added Aug 4 2026: last known position, fed in from Dart's existing
    // GPS reading (see MeshChannelHandler's "updateLocation" case) so
    // PacketRelayEngine can tell whether THIS device has moved since it
    // last saw a given packet -- see PacketRelayEngine.kt for why that
    // matters. No native location API added; this just caches what Dart
    // already has.
    private var lastKnownLat: Double? = null
    private var lastKnownLon: Double? = null

    fun updateDeviceLocation(lat: Double, lon: Double) {
        lastKnownLat = lat
        lastKnownLon = lon
    }

    // =====================================================
    // MARK II — battery-tiered duty cycling
    // =====================================================
    //
    // Nearby Connections (the underlying Android API) does NOT expose a
    // "use BLE only" vs "use Wi-Fi Direct" switch -- Strategy controls
    // connection TOPOLOGY, not which radio gets used, and the library
    // picks the radio internally. That means there is no code-level way
    // to force a bystander's phone to stay on cheap BLE-only scanning.
    //
    // The real, honest lever available here is DUTY CYCLING: how much of
    // the time advertising+discovery are actually running vs stopped.
    // This mirrors what MeshPolicy already expresses in Dart
    // (scanInterval/discoveryInterval: 5s full, 15s balanced, 30s power
    // saver) but which, before this change, was never actually consumed
    // natively -- advertising/discovery just ran continuously regardless
    // of battery level.
    //
    // Trade-off, stated plainly for docs/pitch: in power-saver mode a
    // relay-only device is only discoverable for a fraction of each
    // cycle, which increases the latency for it to pick up a nearby SOS
    // (worst case, up to one full off-window). This is the correct
    // trade for extending a bystander's battery life, and should be
    // described as "reduced discovery duty cycle under low battery",
    // not "radios turn off" -- the notification/foreground service stays
    // running throughout; only the advertise/discover burst timing
    // changes.
    private val dutyCycleHandler = Handler(Looper.getMainLooper())
    private var dutyCycleRunnable: Runnable? = null

    /** How long each advertising/discovery burst stays on, regardless of
     * tier. Kept short and fixed so connection handshakes (which need
     * both sides advertising+discovering at the same moment) still have
     * a real chance to overlap even in power saver mode. */
    private val burstOnMs = 5_000L

    private var currentDiscoveryIntervalMs = 5_000L
    private var currentAllowRelay = true

    /** Called from MeshChannelHandler's "updateMeshPolicy" case whenever
     * Dart's PowerMode changes. Restarts the duty cycle with the new
     * timing immediately rather than waiting for the current cycle to
     * finish, so a battery drop is reflected right away. */
    fun updateMeshPolicy(scanIntervalMs: Long, discoveryIntervalMs: Long, allowRelay: Boolean, dartMaxTtl: Int? = null) {
        currentDiscoveryIntervalMs = discoveryIntervalMs
        currentAllowRelay = allowRelay
        Log.i(TAG, "Mesh policy updated: discoveryIntervalMs=$discoveryIntervalMs allowRelay=$allowRelay")
        startDutyCycle()
        // Persist immediately on an explicit policy change (a real
        // battery-tier transition) rather than waiting for the next
        // periodic tick -- this is a low-frequency event (Dart only calls
        // this on an actual PowerMode change), so writing right away is
        // cheap and means a restart moments after a battery-tier drop
        // still restores the CORRECT tier, not a stale one.
        stateStore.savePolicy(currentDiscoveryIntervalMs, currentAllowRelay)

        // Sep 21 2026 (Vib, Bulk Sprint 3) -- MAX_TTL drift check.
        // PacketRelayEngine.MAX_TTL and Dart's SecurityConstants.maxTTL
        // are two separately-maintained constants with no shared source
        // of truth (see docs/mesh/TTL.md). This does NOT change TTL
        // behavior or enforce anything -- it only makes a future drift
        // impossible to miss in logs, which is strictly better than the
        // previous silent-drift-risk state without inventing shared-
        // constant build infrastructure this sprint has no safe way to
        // validate (no working build in this environment).
        if (dartMaxTtl != null && dartMaxTtl != PacketRelayEngine.MAX_TTL) {
            Log.e(
                TAG,
                "MAX_TTL MISMATCH: Dart SecurityConstants.maxTTL=$dartMaxTtl but native " +
                    "PacketRelayEngine.MAX_TTL=${PacketRelayEngine.MAX_TTL}. These must be kept " +
                    "equal by hand until a shared source of truth exists -- see docs/mesh/TTL.md."
            )
        }
    }

    // =====================================================
    // Sep 21 2026 (Vib, Bulk Sprint 3) — bounded state persistence
    // =====================================================
    //
    // Periodically (not per-packet -- see MeshStateStore's own doc
    // comment for why) snapshots the dedup cache to SharedPreferences so
    // a START_STICKY restart has something better than an empty cache to
    // start from. 30s chosen to match the existing cadence already used
    // elsewhere in this codebase for periodic background work (Dart's
    // own upload-retry timer), not derived from any measurement -- a
    // reasonable default, not a tuned one; if real-device battery
    // measurements (see MULTI_DEVICE_TEST_PLAN.md's future performance
    // work) ever show this write cadence matters, it should change based
    // on that data, not be re-guessed again.
    private val statePersistenceHandler = Handler(Looper.getMainLooper())
    private var statePersistenceRunnable: Runnable? = null
    private val statePersistenceIntervalMs = 30_000L

    private fun startStatePersistenceTimer() {
        val runnable = object : Runnable {
            override fun run() {
                persistSeenSnapshot()
                statePersistenceHandler.postDelayed(this, statePersistenceIntervalMs)
            }
        }
        statePersistenceRunnable = runnable
        statePersistenceHandler.postDelayed(runnable, statePersistenceIntervalMs)
    }

    private fun persistSeenSnapshot() {
        stateStore.saveSeenIds(relayEngine.snapshotSeen())
    }

    private fun startDutyCycle() {
        dutyCycleRunnable?.let { dutyCycleHandler.removeCallbacks(it) }

        val offMs = (currentDiscoveryIntervalMs - burstOnMs).coerceAtLeast(0L)

        // Full-power tier (discoveryInterval <= burstOnMs, offMs == 0):
        // no duty cycling at all -- start once and leave it running
        // continuously, matching the old always-on behavior. Calling
        // startAdvertising()/startDiscovery() again on an already-running
        // session throws STATUS_ALREADY_ADVERTISING -- this was the bug.
        if (offMs == 0L) {
            connectionsManager.startAdvertising()
            connectionsManager.startDiscovery()
            dutyCycleRunnable = null
            return
        }

        val runnable = object : Runnable {
            var burstIsOn = true

            override fun run() {
                if (burstIsOn) {
                    connectionsManager.startAdvertising()
                    connectionsManager.startDiscovery()
                    burstIsOn = false
                    dutyCycleHandler.postDelayed(this, burstOnMs)
                } else {
                    connectionsManager.stopAdvertisingAndDiscovery()
                    burstIsOn = true
                    dutyCycleHandler.postDelayed(this, offMs)
                }
            }
        }

        dutyCycleRunnable = runnable
        dutyCycleHandler.post(runnable)
    }

    @Volatile
    private var peerConnectsTotal = 0L

    @Volatile
    private var peerDisconnectsTotal = 0L

    @Volatile
    private var relaysSent = 0L

    override fun onPeerConnected(endpointId: String) {
        eventForwarder?.invoke(mapOf("type" to "peer_connected", "endpointId" to endpointId))
        peerConnectsTotal++
    }

    override fun onPeerDisconnected(endpointId: String) {
        eventForwarder?.invoke(mapOf("type" to "peer_disconnected", "endpointId" to endpointId))
        peerDisconnectsTotal++
    }

    override fun onPayloadReceived(endpointId: String, bytes: ByteArray) {
        // Sep 21 2026 (Vib, Bulk Sprint 5, Phase 12 — observability):
        // PacketRelayEngine.process() itself deliberately has NO
        // android.util.Log import (that independence from the Android SDK
        // is exactly what let its real, unmodified source compile and run
        // outside Gradle this sprint — see
        // docs/mesh/SPRINT5_INTEGRATION_VALIDATION.md §11 for why that
        // matters and stays that way). Before this sprint, a signature
        // rejection was observable ONLY by polling relayStats()'s
        // signatureFailures counter -- there was no logcat line at all, so
        // a rejection happening right now was invisible without actively
        // watching a counter delta. This delta check adds exactly that
        // visibility, here in the service (which already owns Log/TAG),
        // without adding any Android dependency to the engine itself.
        // Deliberately logs only packetId and the fixed reason string --
        // never the raw signature, public key, or packet message/location
        // content, per the "no verbose sensitive logging" rule.
        val signatureFailuresBefore = relayEngine.signatureFailures
        val result = relayEngine.process(bytes, lastKnownLat, lastKnownLon)
        if (relayEngine.signatureFailures > signatureFailuresBefore) {
            Log.w(TAG, "signature verification failed packet_id=${result.packetId ?: "unknown"} reason=INVALID_SIGNATURE")
        }
        if (!result.isNew) return // duplicate — native engine already filtered it

        // Hand the packet to Dart/UI for display + eventual backend upload.
        deliverToDart(mapOf("type" to "payload_received", "endpointId" to endpointId, "bytes" to bytes))

        // Battery-aware relay guard, native side: mirrors
        // MeshService._relayPacket's allowRelay check in Dart. Only
        // gates RELAYING OTHER DEVICES' traffic onward -- this device's
        // own SOS still always goes out via originate(), unaffected.
        if (!currentAllowRelay) {
            Log.i(TAG, "Relay skipped — power saver mode active (native duty-cycle guard)")
            return
        }

        val relayBytes = result.relayBytes ?: return
        scheduleRelay(relayBytes, result.packetId, result.isCritical)
    }

    // =====================================================
    // PRIORITY 4 — duplicate-storm protection
    // =====================================================
    //
    // The problem this solves, concretely: 8 phones standing in a group
    // all receive the same SOS in the same instant. Dedup already stops
    // any ONE of them relaying it twice, but it does nothing about all 8
    // rebroadcasting it simultaneously — 8 copies on the air, each of
    // which every other device must receive, parse, verify the signature
    // of, and then discard as a duplicate. That is the storm: wasted
    // radio time and wasted battery on exactly the devices you most need
    // still working an hour later.
    //
    // The fix is the classic bounded flooding suppression, and it is
    // deliberately small — it does not touch the seen-cache, does not
    // replace dedup, and adds no state beyond a pending-relay set:
    //
    //   1. Wait a short RANDOM delay before rebroadcasting. Random is
    //      the point: it de-synchronises devices that received the
    //      packet at the same moment, so they stop transmitting on top
    //      of each other.
    //   2. During that delay, count how many copies of the same packet
    //      arrive from OTHER peers (PacketRelayEngine.recentEchoCount).
    //   3. If enough neighbours have already rebroadcast it, our own
    //      copy would reach devices that have demonstrably already been
    //      reached — so skip it and count the suppression.
    //
    // Two safety properties, because getting this wrong loses packets:
    //
    //   * CRITICAL packets are never suppressed and get a much shorter
    //      jitter. Saving radio time is not worth risking an SOS.
    //   * Suppression requires having HEARD the echoes. A device at the
    //      edge of the cluster hears nobody, suppresses nothing, and
    //      relays normally — which is exactly the device that carries
    //      the packet to the next cluster. Genuine multi-hop delivery
    //      is therefore unaffected.
    private val relayHandler = Handler(Looper.getMainLooper())
    private val pendingRelayIds = mutableSetOf<String>()

    /** Max jitter for routine traffic. One burst's worth, no more. */
    private val relayJitterMaxMs = 400L

    /** Critical traffic still gets a little jitter (collisions help
     * nobody) but an order of magnitude less. */
    private val criticalRelayJitterMaxMs = 40L

    /** How many neighbours must have already rebroadcast before we skip
     * our own copy. 2 rather than 1 so a single echo — which could be
     * the original sender's own retransmission — is never enough. */
    private val echoSuppressionThreshold = 2

    private fun scheduleRelay(relayBytes: ByteArray, packetId: String?, isCritical: Boolean) {
        if (packetId == null) {
            connectionsManager.broadcastBytes(relayBytes)
            relaysSent++
            return
        }
        // Already have a rebroadcast pending for this packet; a second
        // scheduling would defeat the suppression it is waiting for.
        if (!pendingRelayIds.add(packetId)) return

        val jitterCeiling = if (isCritical) criticalRelayJitterMaxMs else relayJitterMaxMs
        val delay = (0..jitterCeiling).random()

        relayHandler.postDelayed({
            pendingRelayIds.remove(packetId)

            val echoes = relayEngine.recentEchoCount(packetId)
            if (!isCritical && echoes >= echoSuppressionThreshold) {
                relayEngine.noteSuppressedRelay()
                Log.i(TAG, "Relay suppressed for $packetId — $echoes neighbour(s) already flooded it")
                return@postDelayed
            }

            // Re-check the battery policy: power saver may have engaged
            // while this relay sat in its jitter window.
            if (!currentAllowRelay) {
                Log.i(TAG, "Relay dropped at dispatch — power saver engaged during jitter window")
                return@postDelayed
            }

            connectionsManager.broadcastBytes(relayBytes)
            relaysSent++
        }, delay)
    }

    /** Counters + native-only timings, read by Dart's MeshMetrics through
     * MeshChannelHandler's "getRelayStats". Read-only snapshot. */
    fun relayStats(): Map<String, Any?> = mapOf(
        "totalProcessed" to relayEngine.totalProcessed.toInt(),
        "duplicatesFiltered" to relayEngine.duplicatesFiltered.toInt(),
        "relaySuppressed" to relayEngine.relaySuppressed.toInt(),
        // Sep 21 2026 (Vib, Bulk Sprint 4): packets rejected by native
        // Ed25519 verification -- see PacketRelayEngine.signatureFailures.
        "signatureFailures" to relayEngine.signatureFailures.toInt(),
        // Block 1 observability: every guard in process() is counted.
        "oversizedDropped" to relayEngine.oversizedDropped.toInt(),
        "staleDropped" to relayEngine.staleDropped.toInt(),
        "ttlDropped" to relayEngine.ttlDropped.toInt(),
        "closedEmergencyDropped" to relayEngine.closedEmergencyDropped.toInt(),
        "relaysSent" to relaysSent.toInt(),
        "pendingEvents" to pendingEventCount(),
        "pendingDropped" to handoff.dropped.toInt(),
        "peerConnects" to peerConnectsTotal.toInt(),
        "peerDisconnects" to peerDisconnectsTotal.toInt(),
        "batteryTier" to currentBatteryTier,
        "allowRelay" to currentAllowRelay,
        "discoveryLatencyMicros" to connectionsManager.discoveryLatencyMicros.toInt(),
        "connectionLatencyMicros" to connectionsManager.connectionLatencyMicros.toInt(),
        "connectedPeers" to connectionsManager.connectedEndpoints.size
    )

    override fun onDestroy() {
        dutyCycleRunnable?.let { dutyCycleHandler.removeCallbacks(it) }
        relayHandler.removeCallbacksAndMessages(null)
        statePersistenceRunnable?.let { statePersistenceHandler.removeCallbacks(it) }
        radioStateReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: IllegalArgumentException) {
                // Already unregistered (or never successfully registered) --
                // not a real error, nothing else to clean up.
            }
        }
        radioStateReceiver = null
        batteryReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: IllegalArgumentException) {
                // Already unregistered -- nothing to do.
            }
        }
        batteryReceiver = null
        dutyCycleHandler.removeCallbacks(radioResumeRunnable)
        // Best-effort final save on a graceful stop -- explicitly NOT
        // relied upon as the only persistence path, since an abrupt
        // OOM-kill does not guarantee onDestroy() runs at all. The
        // periodic timer above is the real safety net; this just shaves
        // the worst-case staleness down to whatever's changed since the
        // last tick, for the common case of a clean stop/restart.
        if (::stateStore.isInitialized && ::relayEngine.isInitialized) {
            persistSeenSnapshot()
        }
        pendingRelayIds.clear()
        handoff.clear()
        connectionsManager.stopAll()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "MeshForegroundService"

        /** Max payload events held while Dart is not listening. 64 x
         * <=4096 B is at most ~256 KB. */
        private const val MAX_PENDING_EVENTS = 64

        private const val RADIO_RESUME_DEBOUNCE_MS = 500L
    }
}
