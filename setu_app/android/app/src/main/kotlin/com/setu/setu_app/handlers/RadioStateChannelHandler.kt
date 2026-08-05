package com.setu.setu_app.handlers

import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.MethodChannel

// =====================================================
// SETU Project
// Module : Radio State (Bluetooth/Wi-Fi ON-OFF check + prompt)
// Owner  : Vaibhav
// =====================================================
//
// Added Aug 5 2026. WHY THIS EXISTS: permission_handler's Bluetooth
// runtime-permission model (BLUETOOTH_SCAN/ADVERTISE/CONNECT) only
// exists at all on Android 12+ -- on older OS versions those
// permissions are install-time and always report "granted" with no
// dialog ever shown, which is CORRECT Android behavior but means the
// app can look like it's "not asking for Bluetooth" on older devices,
// with no visible confirmation that Bluetooth is actually usable.
//
// This channel checks and prompts for the thing that actually matters
// on EVERY Android version, regardless of API level: is the Bluetooth
// radio physically ON, and is Wi-Fi ON. A permission being "granted"
// says nothing about whether the user has the radio switched on at
// all -- this is a genuinely separate, version-proof check that
// behaves identically whether the phone is running Android 9 or
// Android 15, so the team doesn't need to know in advance which OS
// version a given user's device has.
//
// Bluetooth: can be enabled directly via a system dialog
// (BluetoothAdapter.ACTION_REQUEST_ENABLE) on every supported version.
// Wi-Fi: Android 10+ blocks apps from directly toggling Wi-Fi
// programmatically (WifiManager.setWifiEnabled() is a silent no-op
// there) -- the correct, version-safe action is opening the system
// Wi-Fi settings panel so the user can toggle it themselves.
class RadioStateChannelHandler(
    private val activity: Activity,
    binaryMessenger: io.flutter.plugin.common.BinaryMessenger
) {

    companion object {
        const val CHANNEL_NAME = "setu/radio_state"
        const val REQUEST_ENABLE_BT = 8001
        const val TAG = "RadioStateHandler"
    }

    private var pendingBluetoothResult: MethodChannel.Result? = null

    init {
        MethodChannel(binaryMessenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "isBluetoothEnabled" -> {
                    result.success(isBluetoothEnabled())
                }
                "requestEnableBluetooth" -> {
                    if (isBluetoothEnabled()) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    pendingBluetoothResult = result
                    try {
                        val enableBtIntent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
                        activity.startActivityForResult(enableBtIntent, REQUEST_ENABLE_BT)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to launch Bluetooth enable dialog: $e", e)
                        pendingBluetoothResult = null
                        result.success(false)
                    }
                }
                "isWifiEnabled" -> {
                    result.success(isWifiEnabled())
                }
                "openWifiSettings" -> {
                    try {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            Intent(Settings.Panel.ACTION_WIFI)
                        } else {
                            Intent(Settings.ACTION_WIFI_SETTINGS)
                        }
                        activity.startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to open Wi-Fi settings: $e", e)
                        result.error("OPEN_SETTINGS_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isBluetoothEnabled(): Boolean {
        return try {
            val manager = activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            manager?.adapter?.isEnabled == true
        } catch (e: Exception) {
            Log.w(TAG, "Could not read Bluetooth adapter state: $e")
            false
        }
    }

    private fun isWifiEnabled(): Boolean {
        return try {
            val manager = activity.applicationContext
                .getSystemService(Context.WIFI_SERVICE) as? WifiManager
            manager?.isWifiEnabled == true
        } catch (e: Exception) {
            Log.w(TAG, "Could not read Wi-Fi state: $e")
            false
        }
    }

    /** Call from MainActivity.onActivityResult(). */
    fun onActivityResult(requestCode: Int, resultCode: Int) {
        if (requestCode != REQUEST_ENABLE_BT) return
        val result = pendingBluetoothResult
        pendingBluetoothResult = null
        // resultCode == Activity.RESULT_OK means the user tapped
        // "Allow" on the system Bluetooth-enable dialog.
        result?.success(resultCode == Activity.RESULT_OK)
    }
}
