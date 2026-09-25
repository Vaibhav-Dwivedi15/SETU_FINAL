import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:setu_app/services/email_otp_service.dart';

Future<T> _withBackend<T>(
  http.Response Function(http.Request) handler,
  Future<T> Function() body,
) {
  return http.runWithClient(body, () => MockClient((r) async => handler(r)));
}

http.Response _json(int status, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  final service = EmailOtpService(baseUrl: 'http://test');

  group('requestOtp', () {
    test('real email delivered -> proceeds, no demo code', () async {
      final r = await _withBackend(
        (_) => _json(200, {
          'delivered': true,
          'detail': 'sent',
          'expires_in_minutes': 10,
        }),
        () => service.requestOtp(email: 'a@b.com'),
      );
      expect(r.delivered, isTrue);
      expect(r.demoCode, isNull);
      expect(r.canProceed, isTrue);
    });

    test('demo mode: not delivered but demo code -> proceeds', () async {
      final r = await _withBackend(
        (_) => _json(200, {
          'delivered': false,
          'detail': 'Demo mode',
          'expires_in_minutes': 10,
          'demo_code': '482913',
        }),
        () => service.requestOtp(email: 'a@b.com'),
      );
      expect(r.delivered, isFalse);
      expect(r.demoCode, '482913');
      expect(r.canProceed, isTrue);
    });

    test('production failure: no delivery, no demo code -> blocked', () async {
      final r = await _withBackend(
        (_) => _json(200, {
          'delivered': false,
          'detail': 'Could not send the verification email. Please try again later.',
          'expires_in_minutes': 10,
        }),
        () => service.requestOtp(email: 'a@b.com'),
      );
      expect(r.canProceed, isFalse);
      expect(r.detail, isNot(contains('SMTP')));
    });
  });

  group('verifyOtp', () {
    test('correct code verifies', () async {
      final r = await _withBackend(
        (_) => _json(200, {'verified': true, 'detail': 'ok'}),
        () => service.verifyOtp(email: 'a@b.com', code: '482913'),
      );
      expect(r.verified, isTrue);
    });

    test('incorrect code fails with backend reason', () async {
      final r = await _withBackend(
        (_) => _json(400, {'detail': 'That code is incorrect.'}),
        () => service.verifyOtp(email: 'a@b.com', code: '000000'),
      );
      expect(r.verified, isFalse);
      expect(r.detail, 'That code is incorrect.');
    });
  });
}
