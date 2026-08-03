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
        val options = DiscoveryOptions.Builder().setStrategy(strategy).build()
        connectionsClient
            .startDiscovery(serviceId, endpointDiscoveryCallback, options)
            .addOnSuccessListener { Log.i(TAG, "Discovery started") }
            .addOnFailureListener { e -> Log.e(TAG, "Discovery failed", e) }
    }

    fun stopAll() {
        connectionsClient.stopAdvertising()
        connectionsClient.stopDiscovery()
        connectionsClient.stopAllEndpoints()
        connectedEndpoints.clear()
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
                Log.i(TAG, "Connected to $endpointId")
                listener.onPeerConnected(endpointId)
            } else {
                Log.w(TAG, "Connection to $endpointId failed: ${result.status}")
            }
        }

        override fun onDisconnected(endpointId: String) {
            connectedEndpoints.remove(endpointId)
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