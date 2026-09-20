import 'package:flutter_test/flutter_test.dart';
import 'package:setu_app/security/replay_protection_service.dart';
import 'package:setu_app/security/security_exceptions.dart';

void main() {
  group('ReplayProtectionService', () {
    late ReplayProtectionService service;

    setUp(() {
      service = ReplayProtectionService();
    });

    test('validate() passes for a fresh timestamp + unseen nonce', () {
      final result = service.validate(
        timestamp: DateTime.now().toUtc(),
        nonce: 'nonce-fresh-1',
      );
      expect(result, isTrue);
    });

    test('validate() throws DuplicateNonceException on a repeated nonce', () {
      final ts = DateTime.now().toUtc();
      service.validate(timestamp: ts, nonce: 'nonce-repeat');
      expect(
        () => service.validate(timestamp: DateTime.now().toUtc(), nonce: 'nonce-repeat'),
        throwsA(isA<DuplicateNonceException>()),
      );
    });

    test('validate() throws ExpiredPacketException for an old timestamp, even with a fresh nonce', () {
      final old = DateTime.now().toUtc().subtract(const Duration(minutes: 10));
      expect(
        () => service.validate(timestamp: old, nonce: 'nonce-old-ts'),
        throwsA(isA<ExpiredPacketException>()),
      );
    });

    test('isNonceSeen() reflects prior validate() calls', () {
      expect(service.isNonceSeen('nonce-check'), isFalse);
      service.validate(timestamp: DateTime.now().toUtc(), nonce: 'nonce-check');
      expect(service.isNonceSeen('nonce-check'), isTrue);
    });

    test('clearCache() resets nonce tracking', () {
      service.validate(timestamp: DateTime.now().toUtc(), nonce: 'nonce-clear');
      expect(service.isCacheEmpty, isFalse);
      service.clearCache();
      expect(service.isCacheEmpty, isTrue);
      expect(service.cachedNonceCount, 0);
    });

    test('cachedNonceCount increases as distinct nonces are validated', () {
      service.validate(timestamp: DateTime.now().toUtc(), nonce: 'n1');
      service.validate(timestamp: DateTime.now().toUtc(), nonce: 'n2');
      expect(service.cachedNonceCount, 2);
    });
  });
}
