package com.setu.setu_app.handlers

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.telephony.SmsManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel

// =====================================================
// SETU Project
// Module : Direct/Silent SMS Send (native, no plugin)
// Owner  : Sudheer
// =====================================================
//
// Extracted from setu_sos_app's MainActivity during the
// mesh/UI merge (Section 8b). No logic changed. Deliberately
// native SmsManager instead of a third-party plugin (telephony
// was tried and abandoned — AGP/Kotlin JVM target
// incompatibilities, see sms_repository.dart).
//
// requestPermissionsResult() must be called from
// MainActivity.onRequestPermissionsResult() so the pending
// MethodChannel result can be resolved once the permission
// dialog returns.
class DirectSmsChannelHandler(
    private val activity: Activity,
    binaryMessenger: io.flutter.plugin.common.BinaryMessenger
) {

    companion object {
        const val CHANNEL_NAME = "setu/direct_sms"
        const val SMS_PERMISSION_REQUEST_CODE = 7001
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

    private fun sendSmsNow(phoneNumber: String, message: String, result: MethodChannel.Result) {
        try {
            val smsManager = SmsManager.getDefault()
            val parts = smsManager.divideMessage(message)
            smsManager.sendMultipartTextMessage(
                phoneNumber,
                null,
                parts,
                null,
                null
            )
            result.success(true)
        } catch (e: Exception) {
            result.error("SEND_FAILED", e.message, null)
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
