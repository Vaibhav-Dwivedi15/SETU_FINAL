// =====================================================
// SETU Project
// Module : Email OTP Service
// =====================================================
//
// Replaces the demo local OTP (see login_screen.dart / otp_screen.dart
// header comments — both were honest about being non-functional demos).
// Hits the backend's real email verification endpoints:
//   POST /auth/request-otp
//   POST /auth/verify-otp
//
// See docs/MOBILE_BACKEND_CONTRACT.md for the full contract. The one
// thing that matters most here: `delivered` can be false on a 200
// response. That means the backend generated a code but the email did
// NOT go out (SMTP unconfigured on the server, or the send failed).
// Callers MUST surface `detail` to the user in that case rather than
// claiming success — showing "code sent!" over an email that went
// nowhere is exactly the kind of thing this project's honesty rules
// exist to prevent.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

class OtpRequestResult {
  final bool delivered;
  final String detail;
  final int expiresInMinutes;

  const OtpRequestResult({
    required this.delivered,
    required this.detail,
    required this.expiresInMinutes,
  });
}

class OtpVerifyResult {
  final bool verified;
  final String detail;
  final String? senderId;

  const OtpVerifyResult({
    required this.verified,
    required this.detail,
    this.senderId,
  });
}

class EmailOtpService {
  EmailOtpService({this.baseUrl = 'https://setu-backend-cy78.onrender.com'});

  final String baseUrl;

  /// Requests a code for [email]. Optionally binds it to this device's
  /// [senderId] (hex Ed25519 public key) so a verified email can be tied
  /// to the existing keypair identity in one step.
  ///
  /// Network/parse failures are reported as a non-delivered result with
  /// a user-facing explanation rather than thrown — a login screen
  /// should always have something sensible to show, never an unhandled
  /// exception.
  Future<OtpRequestResult> requestOtp({
    required String email,
    String? senderId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/request-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              if (senderId != null) 'sender_id': senderId,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        developer.log(
          'OTP request rejected: ${response.statusCode} ${response.body}',
          name: 'EmailOtpService',
        );
        final detail = _extractDetail(response.body) ??
            'Could not request a verification code (server error ${response.statusCode}).';
        return OtpRequestResult(delivered: false, detail: detail, expiresInMinutes: 10);
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return OtpRequestResult(
        delivered: decoded['delivered'] as bool? ?? false,
        detail: decoded['detail'] as String? ?? '',
        expiresInMinutes: decoded['expires_in_minutes'] as int? ?? 10,
      );
    } catch (e) {
      developer.log('OTP request failed: $e', name: 'EmailOtpService');
      return const OtpRequestResult(
        delivered: false,
        detail: 'Could not reach the server. Check your connection and try again.',
        expiresInMinutes: 10,
      );
    }
  }

  /// Verifies [code] for [email]. A correct code is single-use on the
  /// backend — a second verify attempt with the same code will fail.
  Future<OtpVerifyResult> verifyOtp({
    required String email,
    required String code,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/verify-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'code': code}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = _extractDetail(response.body) ?? 'That code is incorrect.';
        developer.log(
          'OTP verify rejected: ${response.statusCode} $detail',
          name: 'EmailOtpService',
        );
        return OtpVerifyResult(verified: false, detail: detail);
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return OtpVerifyResult(
        verified: decoded['verified'] as bool? ?? false,
        detail: decoded['detail'] as String? ?? '',
        senderId: decoded['sender_id'] as String?,
      );
    } catch (e) {
      developer.log('OTP verify failed: $e', name: 'EmailOtpService');
      return const OtpVerifyResult(
        verified: false,
        detail: 'Could not reach the server. Check your connection and try again.',
      );
    }
  }

  /// FastAPI's HTTPException responses put the message under "detail".
  /// Returns null (rather than a confusing raw-JSON string) if the body
  /// isn't shaped that way, so callers fall back to their own generic
  /// message instead of showing something like '{"detail":...}' raw.
  String? _extractDetail(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded['detail'] is String) {
        return decoded['detail'] as String;
      }
    } catch (_) {
      // Not JSON — nothing sensible to extract.
    }
    return null;
  }
}
