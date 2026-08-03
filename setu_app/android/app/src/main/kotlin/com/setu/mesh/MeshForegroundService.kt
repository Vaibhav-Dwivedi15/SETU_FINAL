package com.setu.mesh

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
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
        connectionsManager.startAdvertising()
        connectionsManager.startDiscovery()
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

        result.relayBytes?.let { connectionsManager.broadcastBytes(it) }
    }

    override fun onDestroy() {
        connectionsManager.stopAll()
        super.onDestroy()
    }
}