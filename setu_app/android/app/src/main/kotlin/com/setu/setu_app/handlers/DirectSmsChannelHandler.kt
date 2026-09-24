package com.setu.setu_app.handlers

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel

// =====================================================
// SETU Project
// Module : Direct/Silent SMS Send (native, no plugin)
// Owner  : Sudheer
// =====================================================
//
// Aug 5 2026 fix: SmsManager.getDefault() is known to fail silently
// or throw on dual-SIM MIUI devices (confirmed test device: Redmi 8A
// Dual) when there's no explicit default SMS subscription resolved.
// Now explicitly resolves the active/default subscription ID via
// SubscriptionManager and gets a subscription-specific SmsManager,
// falling back to getDefault() only if that resolution fails for any
// reason. Also logs the FULL exception (not just e.message, which can
// be null for some SecurityExceptions) so real failures are visible.
//
// IMPORTANT DEVICE-SPECIFIC NOTE: on MIUI, granting the standard
// Android SEND_SMS runtime permission is NOT always sufficient --
// MIUI has its own separate permission layer under
// Settings > Apps > [app] > Other permissions > "Send SMS", which
// must ALSO be manually enabled by the user. This is outside any
// app's control; if this handler still fails after the subscription
// fix below, check that MIUI setting on the physical device.
class DirectSmsChannelHandler(
    private val activity: Activity,
    binaryMessenger: io.flutter.plugin.common.BinaryMessenger
) {

    companion object {
        const val CHANNEL_NAME = "setu/direct_sms"
        const val SMS_PERMISSION_REQUEST_CODE = 7001
        const val TAG = "DirectSmsHandler"
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingPhoneNumber: String? = null
    private var pendingMessage: String? = null

    init {
        MethodChannel(binaryMessenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendSms" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")
                    val message = call.argument<String>("message")

                    if (phoneNumber.isNullOrEmpty() || message.isNullOrEmpty()) {
                        result.error(
                            "INVALID_ARGS",
                            "phoneNumber and message are required",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    if (hasSmsPermission()) {
                        sendSmsNow(phoneNumber, message, result)
                    } else {
                        pendingResult = result
                        pendingPhoneNumber = phoneNumber
                        pendingMessage = message
                        ActivityCompat.requestPermissions(
                            activity,
                            arrayOf(Manifest.permission.SEND_SMS),
                            SMS_PERMISSION_REQUEST_CODE
                        )
                    }
                }
                "hasSmsPermission" -> {
                    result.success(hasSmsPermission())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasSmsPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED
    }

    /** Resolves the SmsManager to actually use. Prefers the device's
     * default SMS subscription (handles dual-SIM correctly); falls
     * back to SmsManager.getDefault() if subscription resolution
     * fails for any reason (single-SIM devices, older API levels,
     * permission issues reading subscription info, etc.). */
    private fun resolveSmsManager(): SmsManager {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                val defaultSubId = SubscriptionManager.getDefaultSmsSubscriptionId()
                Log.i(TAG, "Default SMS subscription ID: $defaultSubId")
                if (defaultSubId != SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
                    return SmsManager.getSmsManagerForSubscriptionId(defaultSubId)
                }
                Log.w(TAG, "No default SMS subscription set -- falling back to SmsManager.getDefault()")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to resolve subscription-specific SmsManager: ${e.javaClass.simpleName}")
        }
        return SmsManager.getDefault()
    }

    /** Block 3: logs carry only the last two digits of a destination number. */
    private fun maskNumber(number: String): String {
        val digits = number.filter { it.isDigit() }
        return if (digits.length >= 2) "***" + digits.takeLast(2) else "***"
    }

    private fun sendSmsNow(phoneNumber: String, message: String, result: MethodChannel.Result) {
        try {
            val smsManager = resolveSmsManager()
            val parts = smsManager.divideMessage(message)
            smsManager.sendMultipartTextMessage(
                phoneNumber,
                null,
                parts,
                null,
                null
            )
            Log.i(TAG, "SMS handed to radio for ${maskNumber(phoneNumber)} (${parts.size} part(s))")
            result.success(true)
        } catch (e: Exception) {
            // e.message can be null for some SecurityExceptions on MIUI
            // (the OEM-level "Other permissions" block) -- log the full
            // exception class + toString so the real cause is visible
            // even when .message is empty.
            // Block 3: exception text (and stack) can echo the destination number -- log only the class.
            Log.e(TAG, "SMS send FAILED for ${maskNumber(phoneNumber)}: ${e.javaClass.name}")
            result.error("SEND_FAILED", "${e.javaClass.simpleName}: ${e.message ?: e.toString()}", null)
        }
    }

    /** Call from MainActivity.onRequestPermissionsResult(). Returns true if this handler consumed the request code. */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != SMS_PERMISSION_REQUEST_CODE) return false

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED

        val result = pendingResult
        val phoneNumber = pendingPhoneNumber
        val message = pendingMessage

        pendingResult = null
        pendingPhoneNumber = null
        pendingMessage = null

        if (result == null) return true

        if (granted && phoneNumber != null && message != null) {
            sendSmsNow(phoneNumber, message, result)
        } else {
            result.error(
                "PERMISSION_DENIED",
                "SEND_SMS permission was not granted",
                null
            )
        }
        return true
    }
}
