package com.setu.setu_app.handlers

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Build
import android.os.IBinder
import com.setu.mesh.MeshForegroundService
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// =====================================================
// SETU Project
// Module : Mesh MethodChannel/EventChannel bridge
// Owner  : Vaibhav
// =====================================================
//
// Extracted from setu_app's original MainActivity during the
// mesh/UI merge (Section 8b). No logic changed. start()/stop()
// binds the Foreground Service exactly as before; MainActivity
// must call stop() from its onDestroy().
class MeshChannelHandler(
    private val activity: Activity,
    binaryMessenger: io.flutter.plugin.common.BinaryMessenger
) {

    companion object {
        const val METHOD_CHANNEL = "com.setu.mesh/methods"
        const val EVENT_CHANNEL = "com.setu.mesh/events"
    }

    private var meshService: MeshForegroundService? = null
    private var eventSink: EventChannel.EventSink? = null

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val localBinder = binder as MeshForegroundService.LocalBinder
            meshService = localBinder.getService()
            meshService?.eventForwarder = { event -> activity.runOnUiThread { eventSink?.success(event) } }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            meshService = null
        }
    }

    private fun start(binaryMessenger: io.flutter.plugin.common.BinaryMessenger) {
        startForegroundServiceIntent()
        activity.bindService(serviceIntent(), connection, Context.BIND_AUTO_CREATE)

        MethodChannel(binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "originate" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val packetId = call.argument<String>("packetId")
                    if (bytes != null && packetId != null) {
                        meshService?.originate(bytes, packetId)
                        result.success(null)
                    } else {
                        result.error("BAD_ARGS", "Missing bytes or packetId", null)
                    }
                }
                // Added Aug 4 2026 for ConnectivityMeshController (Dart side) --
                // lets connectivity changes actually control the native
                // service instead of it only ever starting once at launch
                // and running unconditionally forever.
                "startMesh" -> {
                    startForegroundServiceIntent()
                    if (meshService == null) {
                        activity.bindService(serviceIntent(), connection, Context.BIND_AUTO_CREATE)
                    }
                    result.success(null)
                }
                "stopMesh" -> {
                    activity.stopService(serviceIntent())
                    meshService = null
                    result.success(null)
                }
                // Feeds the device's own current position into the native
                // relay engine so PacketRelayEngine can decide whether a
                // previously-seen packet is now arriving at a meaningfully
                // different location (see PacketRelayEngine.kt's
                // seenAtLocation map) -- Dart already has fresh GPS via
                // LocationService for the SOS packet itself, so this just
                // forwards the same reading rather than adding a second
                // native location source.
                "updateLocation" -> {
                    val lat = call.argument<Double>("latitude")
                    val lon = call.argument<Double>("longitude")
                    if (lat != null && lon != null) {
                        meshService?.updateDeviceLocation(lat, lon)
                        result.success(null)
                    } else {
                        result.error("BAD_ARGS", "Missing latitude or longitude", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) { eventSink = sink }
                override fun onCancel(args: Any?) { eventSink = null }
            }
        )
    }

    private fun serviceIntent() = Intent(activity, MeshForegroundService::class.java)

    private fun startForegroundServiceIntent() {
        val serviceIntent = serviceIntent()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.startForegroundService(serviceIntent)
        } else {
            activity.startService(serviceIntent)
        }
    }

    /** Call from MainActivity.onDestroy(). */
    fun stop() {
        activity.unbindService(connection)
    }

    init {
        start(binaryMessenger)
    }
}
