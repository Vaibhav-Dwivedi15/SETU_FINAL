import 'package:flutter_test/flutter_test.dart';
import 'package:setu_app/security/packet_validator.dart';
import 'package:setu_app/security/security_exceptions.dart';

void main() {
  group('PacketValidator', () {
    late PacketValidator validator;

    setUp(() {
      validator = PacketValidator();
    });

    test('validate() passes for a fully valid packet (version=1, ttl in 1-5, fresh timestamp+nonce)', () {
      final result = validator.validate(
        packetVersion: 1,
        ttl: 5,
        timestamp: DateTime.now().toUtc(),
        nonce: 'pv-nonce-1',
      );
      expect(result, isTrue);
    });

    test('validate() throws UnsupportedPacketVersionException for a wrong protocol version', () {
      expect(
        () => validator.validate(
          packetVersion: 2,
          ttl: 5,
          timestamp: DateTime.now().toUtc(),
          nonce: 'pv-nonce-2',
        ),
        throwsA(isA<UnsupportedPacketVersionException>()),
      );
    });

    test('validate() throws InvalidTTLException for ttl below minimum (0)', () {
      expect(
        () => validator.validate(
          packetVersion: 1,
          ttl: 0,
          timestamp: DateTime.now().toUtc(),
          nonce: 'pv-nonce-3',
        ),
        throwsA(isA<InvalidTTLException>()),
      );
    });

    test('validate() throws InvalidTTLException for ttl above maximum (6)', () {
      expect(
        () => validator.validate(
          packetVersion: 1,
          ttl: 6,
          timestamp: DateTime.now().toUtc(),
          nonce: 'pv-nonce-4',
        ),
        throwsA(isA<InvalidTTLException>()),
      );
    });

    test('validate() throws ExpiredPacketException for a stale timestamp, even with valid version/ttl', () {
      expect(
        () => validator.validate(
          packetVersion: 1,
          ttl: 5,
          timestamp: DateTime.now().toUtc().subtract(const Duration(minutes: 10)),
          nonce: 'pv-nonce-5',
        ),
        throwsA(isA<ExpiredPacketException>()),
      );
    });

    test('validate() throws DuplicateNonceException on a replayed nonce', () {
      final nonce = 'pv-nonce-replay';
      validator.validate(
        packetVersion: 1,
        ttl: 5,
        timestamp: DateTime.now().toUtc(),
        nonce: nonce,
      );
      expect(
        () => validator.validate(
          packetVersion: 1,
          ttl: 5,
          timestamp: DateTime.now().toUtc(),
          nonce: nonce,
        ),
        throwsA(isA<DuplicateNonceException>()),
      );
    });

    test('clearReplayCache() resets nonce tracking through the validator', () {
      validator.validate(
        packetVersion: 1,
        ttl: 5,
        timestamp: DateTime.now().toUtc(),
        nonce: 'pv-nonce-clear',
      );
      expect(validator.cachedNonceCount, greaterThan(0));
      validator.clearReplayCache();
      expect(validator.cachedNonceCount, 0);
    });
  });
}
