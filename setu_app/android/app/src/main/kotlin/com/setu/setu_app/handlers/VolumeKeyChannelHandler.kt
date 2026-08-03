package com.setu.setu_app.handlers

import android.view.KeyEvent
import io.flutter.plugin.common.MethodChannel

// =====================================================
// SETU Project
// Module : Volume-Button SOS Shortcut (Block 29)
// Owner  : Sudheer
// =====================================================
//
// Extracted from setu_sos_app's MainActivity during the
// mesh/UI merge (Section 8b). No logic changed — dispatch()
// must be called from MainActivity.dispatchKeyEvent().
class VolumeKeyChannelHandler(binaryMessenger: io.flutter.plugin.common.BinaryMessenger) {

    companion object {
        const val CHANNEL_NAME = "setu/volume_keys"
    }

    private val channel = MethodChannel(binaryMessenger, CHANNEL_NAME)

    /** Call from MainActivity.dispatchKeyEvent(). Returns true if the event was consumed. */
    fun dispatch(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    channel.invokeMethod("volumeDownPressed", null)
                }
                KeyEvent.KEYCODE_VOLUME_UP -> {
                    channel.invokeMethod("volumeUpPressed", null)
                }
            }
        }
        return false // don't consume; let the system also adjust volume as before
    }
}
