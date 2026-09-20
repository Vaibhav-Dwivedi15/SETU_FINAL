package com.setu.setu_app

import android.content.Intent
import android.view.KeyEvent
import com.setu.setu_app.handlers.DirectSmsChannelHandler
import com.setu.setu_app.handlers.MeshChannelHandler
import com.setu.setu_app.handlers.RadioStateChannelHandler
import com.setu.setu_app.handlers.VolumeKeyChannelHandler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

// =====================================================
// SETU Project — merged MainActivity (Section 8b)
// =====================================================
//
// Hosts all channels used across the app. Each channel's logic lives
// in its own handler class under handlers/ -- this file only wires
// them up and forwards the Activity lifecycle callbacks a handler
// needs.
//
// Channels:
//   setu/volume_keys        - Sudheer, volume-button SOS shortcut
//   setu/direct_sms         - Sudheer, native silent SMS send
//   setu/radio_state        - Aug 5 2026, Bluetooth/Wi-Fi radio ON/OFF
//                             check + prompt -- version-proof: works
//                             the same way regardless of which Android
//                             version a given user's phone runs, since
//                             it checks/prompts the actual radio state
//                             rather than relying on permission_handler's
//                             OS-version-dependent runtime permission
//                             model (which only exists at all on
//                             Android 12+ for Bluetooth).
//   com.setu.mesh/methods   - Vaibhav, mesh originate()
//   com.setu.mesh/events    - Vaibhav, mesh peer/payload events
class MainActivity : FlutterActivity() {

    private var volumeKeyHandler: VolumeKeyChannelHandler? = null
    private var directSmsHandler: DirectSmsChannelHandler? = null
    private var meshHandler: MeshChannelHandler? = null
    private var radioStateHandler: RadioStateChannelHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        volumeKeyHandler = VolumeKeyChannelHandler(messenger)
        directSmsHandler = DirectSmsChannelHandler(this, messenger)
        meshHandler = MeshChannelHandler(this, messenger)
        radioStateHandler = RadioStateChannelHandler(this, messenger)
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        radioStateHandler?.onActivityResult(requestCode, resultCode)
    }

    override fun onDestroy() {
        meshHandler?.stop()
        super.onDestroy()
    }
}
