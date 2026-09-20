import 'package:flutter_test/flutter_test.dart';
import 'package:setu_app/security/nonce_cache.dart';
import 'package:setu_app/security/security_exceptions.dart';

void main() {
  group('NonceCache', () {
    late NonceCache cache;

    setUp(() {
      cache = NonceCache();
    });

    test('validate() returns true for a new nonce', () {
      expect(cache.validate('nonce-1'), isTrue);
    });

    test('validate() throws DuplicateNonceException on repeat', () {
      cache.validate('nonce-1');
      expect(() => cache.validate('nonce-1'), throwsA(isA<DuplicateNonceException>()));
    });

    test('contains() checks without storing', () {
      expect(cache.contains('nonce-2'), isFalse);
      cache.add('nonce-2');
      expect(cache.contains('nonce-2'), isTrue);
    });

    test('add() stores manually without throwing on repeat', () {
      cache.add('nonce-3');
      cache.add('nonce-3'); // should not throw, unlike validate()
      expect(cache.contains('nonce-3'), isTrue);
    });

    test('clear() empties the cache', () {
      cache.add('nonce-4');
      expect(cache.isNotEmpty, isTrue);
      cache.clear();
      expect(cache.isEmpty, isTrue);
      expect(cache.size, 0);
    });

    test('size reflects number of stored nonces', () {
      cache.add('a');
      cache.add('b');
      cache.add('c');
      expect(cache.size, 3);
    });

    test('cache trims when it exceeds maxNonceCacheSize', () {
      // SecurityConstants.maxNonceCacheSize = 500 -- add past that and
      // confirm the cache never grows unbounded.
      for (var i = 0; i < 600; i++) {
        cache.add('nonce-bulk-$i');
      }
      expect(cache.size, lessThanOrEqualTo(500));
    });

    test('different nonces do not collide', () {
      expect(cache.validate('x'), isTrue);
      expect(cache.validate('y'), isTrue);
      expect(cache.validate('z'), isTrue);
    });
  });
}
