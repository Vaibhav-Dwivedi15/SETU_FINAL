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
// Aug 5 2026 fix #1: numbers normalized to E.164 (+91XXXXXXXXXX)
// before being handed to SmsManager -- see _normalizePhoneNumber.
//
// Aug 5 2026 fix #2: added developer.log around the actual
// PlatformException so the real native error (e.code/e.message
// from SmsManager, e.g. RESULT_ERROR_GENERIC_FAILURE,
// RESULT_ERROR_RADIO_OFF, RESULT_ERROR_NULL_PDU) is visible in
// the Flutter console instead of being silently swallowed into a
// generic "SMS failed for N of M contacts" message. This was
// needed because the real cause was invisible with the fix #1
// change alone still failing -- can't diagnose further without
// seeing what the native side is actually reporting.
import 'dart:developer' as developer;

import 'package:flutter/services.dart';

class SmsRepository {
  static const int _maxRetry = 3;
  static const MethodChannel _channel = MethodChannel('setu/direct_sms');

  String _normalizePhoneNumber(String rawPhone) {
    final trimmed = rawPhone.trim();
    if (trimmed.startsWith('+')) return trimmed;
    if (RegExp(r'^[6-9]\d{9}$').hasMatch(trimmed)) {
      return '+91$trimmed';
    }
    return trimmed;
  }

  Future<String> sendSingleSMS({
    required String message,
    required String phoneNumber,
  }) async {
    final normalizedNumber = _normalizePhoneNumber(phoneNumber);
    developer.log('Attempting SMS to $normalizedNumber (original: $phoneNumber)', name: 'SmsRepository');
    int attempt = 0;
    while (attempt < _maxRetry) {
      try {
        await _channel.invokeMethod('sendSms', {
          'phoneNumber': normalizedNumber,
          'message': message,
        });
        developer.log('SMS sent successfully to $normalizedNumber', name: 'SmsRepository');
        return "Sent";
      } on PlatformException catch (e) {
        attempt++;
        developer.log(
          'SMS attempt $attempt/$_maxRetry FAILED for $normalizedNumber -- code=${e.code} message=${e.message} details=${e.details}',
          name: 'SmsRepository',
          error: e,
        );
        if (e.code == 'PERMISSION_DENIED' || attempt >= _maxRetry) {
          rethrow;
        }
        await Future.delayed(const Duration(seconds: 1));
      } catch (e, stack) {
        // Catch anything non-PlatformException too -- if the channel
        // call itself is malformed or missing, we want to see that,
        // not have it disappear into a generic failure.
        developer.log(
          'SMS attempt $attempt/$_maxRetry UNEXPECTED ERROR for $normalizedNumber: $e',
          name: 'SmsRepository',
          error: e,
          stackTrace: stack,
        );
        attempt++;
        if (attempt >= _maxRetry) rethrow;
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
