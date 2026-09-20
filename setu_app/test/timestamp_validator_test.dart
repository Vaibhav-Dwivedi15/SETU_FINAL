import 'package:flutter_test/flutter_test.dart';
import 'package:setu_app/security/timestamp_validator.dart';
import 'package:setu_app/security/security_exceptions.dart';

void main() {
  group('TimestampValidator', () {
    const validator = TimestampValidator();

    test('validate() passes for a current timestamp', () {
      final now = DateTime.now().toUtc();
      expect(validator.validate(now), isTrue);
    });

    test('validate() passes for a timestamp slightly in the past', () {
      final recent = DateTime.now().toUtc().subtract(const Duration(minutes: 2));
      expect(validator.validate(recent), isTrue);
    });

    test('validate() throws ExpiredPacketException when older than maxPacketAge (5 min)', () {
      final old = DateTime.now().toUtc().subtract(const Duration(minutes: 6));
      expect(() => validator.validate(old), throwsA(isA<ExpiredPacketException>()));
    });

    test('validate() passes for a timestamp within allowed clock skew (30s future)', () {
      final slightlyFuture = DateTime.now().toUtc().add(const Duration(seconds: 10));
      expect(validator.validate(slightlyFuture), isTrue);
    });

    test('validate() throws InvalidTimestampException when too far in the future', () {
      final tooFarFuture = DateTime.now().toUtc().add(const Duration(minutes: 5));
      expect(() => validator.validate(tooFarFuture), throwsA(isA<InvalidTimestampException>()));
    });

    test('isExpired() reflects packet age correctly', () {
      final old = DateTime.now().toUtc().subtract(const Duration(minutes: 10));
      final fresh = DateTime.now().toUtc();
      expect(validator.isExpired(old), isTrue);
      expect(validator.isExpired(fresh), isFalse);
    });

    test('packetAge() returns a duration close to the actual elapsed time', () {
      final threeMinAgo = DateTime.now().toUtc().subtract(const Duration(minutes: 3));
      final age = validator.packetAge(threeMinAgo);
      expect(age.inMinutes, 3);
    });
  });
}
