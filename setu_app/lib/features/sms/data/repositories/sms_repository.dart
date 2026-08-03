// =====================================================
// SETU Project
// Module : SMS
// Owner  : Sudheer
// =====================================================
//
// Direct/silent send, take 2. flutter_sms (composer, manual
// tap) is replaced with a native MethodChannel
// ("setu/direct_sms") calling Android's SmsManager directly
// from MainActivity.kt — NOT the telephony package.
//
// Why this avoids the earlier failure: telephony 0.2.0 broke
// the build via its own Gradle/Kotlin config (missing
// namespace -> JVM target mismatch -> deprecated APIs). This
// approach adds zero new Gradle dependencies — it's just a
// MethodChannel to code already living in our own
// MainActivity.kt, so that whole failure class doesn't apply.
//
// Permission (SEND_SMS) is requested natively on first send
// if not already granted — see MainActivity.kt. If the user
// denies it, sendSingleSMS throws and the caller (SosRepository)
// records the failure in History as before.
//
// Numbers are sent one at a time in sendBulkSMS (a loop of
// native calls), not a single native "send to N recipients"
// call — this keeps the existing per-number retry logic intact
// and means one bad number doesn't block the rest.

import 'package:flutter/services.dart';

class SmsRepository {
  static const int _maxRetry = 3;

  static const MethodChannel _channel = MethodChannel('setu/direct_sms');

  Future<String> sendSingleSMS({
    required String message,
    required String phoneNumber,
  }) async {
    int attempt = 0;

    while (attempt < _maxRetry) {
      try {
        await _channel.invokeMethod('sendSms', {
          'phoneNumber': phoneNumber,
          'message': message,
        });

        return "Sent";
      } on PlatformException catch (e) {
        attempt++;

        if (e.code == 'PERMISSION_DENIED' || attempt >= _maxRetry) {
          rethrow;
        }

        await Future.delayed(const Duration(seconds: 1));
      }
    }

    throw Exception("Unable to send SMS.");
  }

  Future<String> sendBulkSMS({
    required String message,
    required List<String> phoneNumbers,
  }) async {
    final failures = <String>[];

    for (final phoneNumber in phoneNumbers) {
      try {
        await sendSingleSMS(message: message, phoneNumber: phoneNumber);
      } catch (e) {
        failures.add(phoneNumber);
      }
    }

    if (failures.isNotEmpty && failures.length == phoneNumbers.length) {
      throw Exception("Unable to send SMS to any contact.");
    }

    if (failures.isNotEmpty) {
      throw Exception(
        "SMS failed for ${failures.length} of ${phoneNumbers.length} contacts.",
      );
    }

    return "Sent";
  }
}
