package com.setu.mesh

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
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
    private val binder = LocalBinder()

    /** Set by MainActivity when attached, cleared when detached — events
     * only get forwarded to Dart/UI when someone's actually looking. */
    var eventForwarder: ((Map<String, Any?>) -> Unit)? = null

    inner class LocalBinder : Binder() {
        fun getService(): MeshForegroundService = this@MeshForegroundService
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        connectionsManager = NearbyConnectionsManager(applicationContext, this)
        relayEngine = PacketRelayEngine()
        startForegroundWithNotification()
        startDutyCycle()
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
    fun updateMeshPolicy(scanIntervalMs: Long, discoveryIntervalMs: Long, allowRelay: Boolean) {
        currentDiscoveryIntervalMs = discoveryIntervalMs
        currentAllowRelay = allowRelay
        Log.i(TAG, "Mesh policy updated: discoveryIntervalMs=$discoveryIntervalMs allowRelay=$allowRelay")
        startDutyCycle()
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

    override fun onPeerConnected(endpointId: String) {
        eventForwarder?.invoke(mapOf("type" to "peer_connected", "endpointId" to endpointId))
    }

    override fun onPeerDisconnected(endpointId: String) {
        eventForwarder?.invoke(mapOf("type" to "peer_disconnected", "endpointId" to endpointId))
    }

    override fun onPayloadReceived(endpointId: String, bytes: ByteArray) {
        val result = relayEngine.process(bytes, lastKnownLat, lastKnownLon)
        if (!result.isNew) return // duplicate — native engine already filtered it

        // Hand the packet to Dart/UI for display + eventual backend upload.
        eventForwarder?.invoke(mapOf("type" to "payload_received", "endpointId" to endpointId, "bytes" to bytes))

        // Battery-aware relay guard, native side: mirrors
        // MeshService._relayPacket's allowRelay check in Dart. Only
        // gates RELAYING OTHER DEVICES' traffic onward -- this device's
        // own SOS still always goes out via originate(), unaffected.
        if (!currentAllowRelay) {
            Log.i(TAG, "Relay skipped — power saver mode active (native duty-cycle guard)")
            return
        }

        result.relayBytes?.let { connectionsManager.broadcastBytes(it) }
    }

    override fun onDestroy() {
        dutyCycleRunnable?.let { dutyCycleHandler.removeCallbacks(it) }
        connectionsManager.stopAll()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "MeshForegroundService"
    }
}
