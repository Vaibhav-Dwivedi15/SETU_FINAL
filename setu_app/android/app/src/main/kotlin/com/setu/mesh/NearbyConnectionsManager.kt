package com.setu.mesh

import android.content.Context
import android.util.Log
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.*
import java.util.Collections

class NearbyConnectionsManager(
    private val context: Context,
    private val listener: Listener,
    private val serviceId: String = "com.setu.mesh.SERVICE",
) {
    private val connectionsClient = Nearby.getConnectionsClient(context)
    private val strategy = Strategy.P2P_CLUSTER
    // Block 1: was "setu-" + a 4-digit number (9000 values), so two
    // devices picked the same name roughly 1 time in 9000 and, with the
    // name-ordered tie-break below, neither would ever initiate. 32 random
    // bits make that negligible. Lowercase hex sorts consistently.
    private val localEndpointName: String = "setu-" + String.format(
        "%08x", java.security.SecureRandom().nextInt()
    )

    // Sep 21 2026 (Vib, native-mesh hardening pass): Nearby Connections
    // callbacks are not guaranteed by the API contract to all fire on one
    // thread, and nothing here previously asserted that -- these were
    // plain mutableSetOf()/mutableMapOf() before. Collections.synchronized*
    // makes individual get/add/remove calls safe; broadcastBytes() below
    // additionally synchronizes on connectedEndpoints for the duration of
    // its iteration, since the java.util docs are explicit that even a
    // synchronized wrapper needs external synchronization while iterating.
    // No behavior change -- same set/map contents, same eviction, just
    // safe under concurrent callback delivery.
    val connectedEndpoints: MutableSet<String> = Collections.synchronizedSet(mutableSetOf())

    // =====================================================
    // PRIORITY 1 -- discovery / connection latency
    // =====================================================
    //
    // These two stages are owned entirely by this class: Dart only ever
    // sees the resulting PeerConnected event, so without measuring here
    // they cannot be measured at all and would have to be reported as
    // "not measured" forever.
    //
    // Both are recorded as the latency of the FIRST peer found/connected
    // after a discovery start, which is the number that actually matters
    // in an emergency: how long from switching the mesh on to having
    // somebody to relay through. Later peers in the same session do not
    // overwrite it.
    //
    // 0 means "never measured" and is reported to Dart as null, never as
    // a real zero-millisecond measurement.
    @Volatile
    var discoveryLatencyMicros: Long = 0L
        private set

    @Volatile
    var connectionLatencyMicros: Long = 0L
        private set

    /** Nanotime at which the current discovery session started. */
    private var discoveryStartedAtNanos: Long = 0L

    /** endpointId -> nanotime at which we requested/accepted a connection. */
    private val connectionStartedAtNanos: MutableMap<String, Long> = Collections.synchronizedMap(mutableMapOf())

    // =====================================================
    // Sep 21 2026 (Vib, Bulk Sprint 3) -- bounded reconnection backoff
    // =====================================================
    //
    // Scoped narrowly on purpose. This only backs off the case that's
    // unambiguous from source review: a connection attempt WE initiated
    // (the tie-break "we go first" branch below) that Nearby Connections
    // itself reports as failed (onConnectionResult, non-OK status) --
    // e.g. the peer moved out of range mid-handshake, or the handshake
    // simply timed out. Repeatedly retrying that exact case with no
    // delay is the clearest flapping-storm risk this file has.
    //
    // Deliberately NOT covered this pass: a connection that succeeds and
    // then disconnects quickly afterward (onDisconnected). Distinguishing
    // "flapping" from "a normal, useful, but short-lived relay contact"
    // would need a real duration threshold, and picking one without any
    // device to observe actual real-world connection durations against
    // is exactly the kind of arbitrary-value guess this sprint's rules
    // say not to make. Left as a documented gap, not silently ignored --
    // see NATIVE_FAILURE_MATRIX.md row 7.
    //
    // Values below (initial delay, multiplier, ceiling) are a reasonable
    // starting point, not a validated one -- this sandbox has no hardware
    // to observe real reconnection timing against. They intentionally:
    //   - never delay a FIRST attempt to a newly-discovered endpoint
    //     (failure count starts at 0 -- "do not sacrifice emergency
    //     connectivity" from a device we've never even tried yet), and
    //   - reset to zero the moment a connection actually succeeds, so a
    //     peer that reconnects cleanly is never penalized for an old,
    //     unrelated failure.
    // Needs real-device validation before the specific numbers are
    // trusted -- flagged explicitly in the final report, not claimed as
    // tested.
    // Block 1: bookkeeping lives in ConnectionBackoff (JVM-testable).
    private val backoff = ConnectionBackoff()

    interface Listener {
        fun onPeerConnected(endpointId: String)
        fun onPeerDisconnected(endpointId: String)
        fun onPayloadReceived(endpointId: String, bytes: ByteArray)
    }

    fun startAdvertising() {
        val options = AdvertisingOptions.Builder().setStrategy(strategy).build()
        connectionsClient
            .startAdvertising(localEndpointName, serviceId, connectionLifecycleCallback, options)
            .addOnSuccessListener { Log.i(TAG, "Advertising started as $localEndpointName") }
            .addOnFailureListener { e -> logStartFailure("Advertising", e) }
    }

    fun startDiscovery() {
        // Only stamp the first start of a discovery session -- duty
        // cycling restarts discovery every burst, and restamping would
        // silently turn "time to find a peer" into "time since the last
        // burst", which is a different and much flattering number.
        if (discoveryStartedAtNanos == 0L) discoveryStartedAtNanos = System.nanoTime()
        val options = DiscoveryOptions.Builder().setStrategy(strategy).build()
        connectionsClient
            .startDiscovery(serviceId, endpointDiscoveryCallback, options)
            .addOnSuccessListener { Log.i(TAG, "Discovery started") }
            .addOnFailureListener { e -> logStartFailure("Discovery", e) }
    }

    // Block 1: the duty cycle and radio-resume both call start*() again on
    // a session that may already be running. "Already advertising /
    // discovering" is the expected, harmless answer there and should not
    // read as an error in logcat.
    private fun logStartFailure(what: String, e: Exception) {
        val code = (e as? com.google.android.gms.common.api.ApiException)?.statusCode
        if (code == ConnectionsStatusCodes.STATUS_ALREADY_ADVERTISING ||
            code == ConnectionsStatusCodes.STATUS_ALREADY_DISCOVERING
        ) {
            Log.i(TAG, "$what already running (no-op restart)")
        } else {
            Log.e(TAG, "$what failed (code=$code)", e)
        }
    }

    /** Added for MARK II battery-tiered duty cycling. Pauses advertising
     * and discovery for the "off" portion of a duty cycle WITHOUT calling
     * stopAllEndpoints() -- devices already connected as active relay
     * peers stay connected; we're just not looking for NEW peers during
     * this window. This is the key difference from stopAll(), which is
     * only for full service shutdown (onDestroy). */
    fun stopAdvertisingAndDiscovery() {
        connectionsClient.stopAdvertising()
        connectionsClient.stopDiscovery()
    }

    fun stopAll() {
        connectionsClient.stopAdvertising()
        connectionsClient.stopDiscovery()
        connectionsClient.stopAllEndpoints()
        connectedEndpoints.clear()
        connectionStartedAtNanos.clear()
        backoff.clear()
        // Full shutdown ends the measurement session: the next
        // startDiscovery() begins timing a genuinely new one.
        discoveryStartedAtNanos = 0L
    }

    fun sendBytes(endpointId: String, bytes: ByteArray) {
        connectionsClient.sendPayload(endpointId, Payload.fromBytes(bytes))
    }

    fun broadcastBytes(bytes: ByteArray) {
        // Manual synchronization required while iterating even a
        // Collections.synchronizedSet -- see the field's own comment.
        synchronized(connectedEndpoints) {
            connectedEndpoints.forEach { endpointId -> sendBytes(endpointId, bytes) }
        }
    }

    private val endpointDiscoveryCallback = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
            Log.i(TAG, "Found endpoint: $endpointId (${info.endpointName})")

            // Sep 21 2026 (Vib): guard against re-requesting an endpoint
            // we're already connected to. Duty-cycling stops/restarts
            // discovery every burst while a connection persists, so
            // Nearby Connections re-firing onEndpointFound for an
            // already-connected peer is a real, reachable case, not a
            // hypothetical -- previously nothing here checked for it
            // before calling requestConnection again. Nearby Connections
            // itself generally no-ops or rejects a redundant request
            // gracefully, but there is no reason to rely on that silently
            // when the check is one line.
            if (connectedEndpoints.contains(endpointId)) {
                Log.i(TAG, "Ignoring rediscovery of already-connected endpoint: $endpointId")
                return
            }

            if (discoveryLatencyMicros == 0L && discoveryStartedAtNanos != 0L) {
                discoveryLatencyMicros = (System.nanoTime() - discoveryStartedAtNanos) / 1_000L
                Log.i(TAG, "Discovery latency: ${discoveryLatencyMicros / 1000}ms")
            }
            connectionStartedAtNanos[endpointId] = System.nanoTime()

            // TIE-BREAKER: without this, both devices request a connection
            // to each other simultaneously the moment they discover one
            // another, and Nearby Connections silently drops both requests
            // — this is exactly what was happening (endpoints found, then
            // "Lost endpoint" with no connection ever completing). Only
            // the device whose name sorts first initiates; the other side
            // just waits to accept.
            if (localEndpointName < info.endpointName) {
                if (!backoff.canAttempt(endpointId)) {
                    Log.i(TAG, "Backoff active for $endpointId (failure #${backoff.failureCount(endpointId)}, wait ${backoff.delayMsFor(endpointId)}ms) -- skipping connection attempt this discovery cycle")
                    return
                }
                backoff.markAttempt(endpointId)
                Log.i(TAG, "Requesting connection to $endpointId (we go first: $localEndpointName < ${info.endpointName})")
                connectionsClient
                    .requestConnection(localEndpointName, endpointId, connectionLifecycleCallback)
                    .addOnFailureListener { e ->
                        // Block 1: previously unobserved -- a failed
                        // request (radio error, endpoint gone, already
                        // connecting) neither counted toward backoff nor
                        // cleared its latency stamp.
                        connectionStartedAtNanos.remove(endpointId)
                        val code = (e as? com.google.android.gms.common.api.ApiException)?.statusCode
                        if (code == ConnectionsStatusCodes.STATUS_ALREADY_CONNECTED_TO_ENDPOINT) {
                            Log.i(TAG, "requestConnection: already connected to $endpointId")
                        } else {
                            val failures = backoff.recordFailure(endpointId)
                            Log.w(TAG, "requestConnection to $endpointId failed (code=$code, failure #$failures)")
                        }
                    }
            } else if (localEndpointName == info.endpointName) {
                Log.w(TAG, "Endpoint $endpointId advertises OUR name ($localEndpointName); cannot break the tie -- ignoring")
            } else {
                Log.i(TAG, "Waiting to be connected to by $endpointId (they go first: ${info.endpointName} < $localEndpointName)")
            }
        }

        override fun onEndpointLost(endpointId: String) {
            Log.i(TAG, "Lost endpoint: $endpointId")
            // Block 1: drop the pending latency stamp for a handshake that
            // will now never complete. Backoff history is deliberately
            // kept (bounded by ConnectionBackoff.MAX_TRACKED) so a peer
            // that flaps in and out of range stays paced.
            if (!connectedEndpoints.contains(endpointId)) {
                connectionStartedAtNanos.remove(endpointId)
            }
        }
    }

    private val connectionLifecycleCallback = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
            Log.i(TAG, "Connection initiated with $endpointId, auto-accepting")
            connectionsClient.acceptConnection(endpointId, payloadCallback)
        }

        override fun onConnectionResult(endpointId: String, result: ConnectionResolution) {
            if (result.status.statusCode == com.google.android.gms.nearby.connection.ConnectionsStatusCodes.STATUS_OK) {
                connectedEndpoints.add(endpointId)
                val startedAt = connectionStartedAtNanos.remove(endpointId)
                if (connectionLatencyMicros == 0L && startedAt != null) {
                    connectionLatencyMicros = (System.nanoTime() - startedAt) / 1_000L
                    Log.i(TAG, "Connection establishment latency: ${connectionLatencyMicros / 1000}ms")
                }
                // Block 1: success no longer clears backoff (see
                // ConnectionBackoff) -- only a connection that stays up
                // does, in onDisconnected below.
                backoff.recordConnected(endpointId)
                Log.i(TAG, "Connected to $endpointId")
                listener.onPeerConnected(endpointId)
            } else {
                connectionStartedAtNanos.remove(endpointId)
                val failures = backoff.recordFailure(endpointId)
                Log.w(TAG, "Connection to $endpointId failed: ${result.status} (failure #$failures, next retry backoff ~${backoff.delayMsFor(endpointId)}ms)")
            }
        }

        override fun onDisconnected(endpointId: String) {
            connectedEndpoints.remove(endpointId)
            connectionStartedAtNanos.remove(endpointId)
            val flapped = backoff.recordDisconnected(endpointId)
            Log.i(TAG, "Disconnected from $endpointId" + if (flapped) " (short-lived -- counted toward backoff)" else "")
            listener.onPeerDisconnected(endpointId)
        }
    }

    private val payloadCallback = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            if (payload.type == Payload.Type.BYTES) {
                payload.asBytes()?.let { listener.onPayloadReceived(endpointId, it) }
            }
        }

        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) {}
    }

    companion object {
        private const val TAG = "NearbyConnectionsManager"
    }
}
