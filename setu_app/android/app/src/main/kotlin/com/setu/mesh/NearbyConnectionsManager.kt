package com.setu.mesh

import android.content.Context
import android.util.Log
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.*

class NearbyConnectionsManager(
    private val context: Context,
    private val listener: Listener,
    private val serviceId: String = "com.setu.mesh.SERVICE",
) {
    private val connectionsClient = Nearby.getConnectionsClient(context)
    private val strategy = Strategy.P2P_CLUSTER
    private val localEndpointName: String = "setu-" + (1000..9999).random()

    val connectedEndpoints: MutableSet<String> = mutableSetOf()

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
    private val connectionStartedAtNanos = mutableMapOf<String, Long>()

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
            .addOnFailureListener { e -> Log.e(TAG, "Advertising failed", e) }
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
            .addOnFailureListener { e -> Log.e(TAG, "Discovery failed", e) }
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
        // Full shutdown ends the measurement session: the next
        // startDiscovery() begins timing a genuinely new one.
        discoveryStartedAtNanos = 0L
    }

    fun sendBytes(endpointId: String, bytes: ByteArray) {
        connectionsClient.sendPayload(endpointId, Payload.fromBytes(bytes))
    }

    fun broadcastBytes(bytes: ByteArray) {
        connectedEndpoints.forEach { endpointId -> sendBytes(endpointId, bytes) }
    }

    private val endpointDiscoveryCallback = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
            Log.i(TAG, "Found endpoint: $endpointId (${info.endpointName})")

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
                Log.i(TAG, "Requesting connection to $endpointId (we go first: $localEndpointName < ${info.endpointName})")
                connectionsClient.requestConnection(localEndpointName, endpointId, connectionLifecycleCallback)
            } else {
                Log.i(TAG, "Waiting to be connected to by $endpointId (they go first: ${info.endpointName} < $localEndpointName)")
            }
        }

        override fun onEndpointLost(endpointId: String) {
            Log.i(TAG, "Lost endpoint: $endpointId")
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
                Log.i(TAG, "Connected to $endpointId")
                listener.onPeerConnected(endpointId)
            } else {
                connectionStartedAtNanos.remove(endpointId)
                Log.w(TAG, "Connection to $endpointId failed: ${result.status}")
            }
        }

        override fun onDisconnected(endpointId: String) {
            connectedEndpoints.remove(endpointId)
            connectionStartedAtNanos.remove(endpointId)
            Log.i(TAG, "Disconnected from $endpointId")
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
