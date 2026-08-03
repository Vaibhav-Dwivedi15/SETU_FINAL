package com.setu.setu_app

import android.view.KeyEvent
import com.setu.setu_app.handlers.DirectSmsChannelHandler
import com.setu.setu_app.handlers.MeshChannelHandler
import com.setu.setu_app.handlers.VolumeKeyChannelHandler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

// =====================================================
// SETU Project — merged MainActivity (Section 8b)
// =====================================================
//
// Hosts all 4 native channels used across the app. Each
// channel's logic lives in its own handler class under
// handlers/ — this file only wires them up and forwards the
// two Activity lifecycle callbacks (dispatchKeyEvent,
// onRequestPermissionsResult, onDestroy) that a handler needs.
//
// Channels:
//   setu/volume_keys        - Sudheer, volume-button SOS shortcut
//   setu/direct_sms         - Sudheer, native silent SMS send
//   com.setu.mesh/methods   - Vaibhav, mesh originate()
//   com.setu.mesh/events    - Vaibhav, mesh peer/payload events
class MainActivity : FlutterActivity() {

    private var volumeKeyHandler: VolumeKeyChannelHandler? = null
    private var directSmsHandler: DirectSmsChannelHandler? = null
    private var meshHandler: MeshChannelHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        volumeKeyHandler = VolumeKeyChannelHandler(messenger)
        directSmsHandler = DirectSmsChannelHandler(this, messenger)
        meshHandler = MeshChannelHandler(this, messenger)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        volumeKeyHandler?.dispatch(event)
        return super.dispatchKeyEvent(event)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        directSmsHandler?.onRequestPermissionsResult(requestCode, grantResults)
    }

    override fun onDestroy() {
        meshHandler?.stop()
        super.onDestroy()
    }
}
