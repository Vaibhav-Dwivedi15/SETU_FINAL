import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setu_app/mesh/services/signing_service.dart';

/// SigningService reads/writes via flutter_secure_storage, which needs a
/// real platform (Android Keystore) to function. These tests mock that
/// channel with an in-memory map so the actual Ed25519 sign/verify LOGIC
/// can be tested on the VM. This does NOT verify real Keystore-backed
/// persistence behavior on a device -- that would need an integration
/// test running on an emulator/real device, which is a separate,
/// still-open item, not covered here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> fakeSecureStorage = {};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    fakeSecureStorage.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      switch (call.method) {
        case 'write':
          final key = call.arguments['key'] as String;
          final value = call.arguments['value'] as String?;
          if (value == null) {
            fakeSecureStorage.remove(key);
          } else {
            fakeSecureStorage[key] = value;
          }
          return null;
        case 'read':
          final key = call.arguments['key'] as String;
          return fakeSecureStorage[key];
        case 'delete':
          final key = call.arguments['key'] as String;
          fakeSecureStorage.remove(key);
          return null;
        case 'readAll':
          return fakeSecureStorage;
        case 'deleteAll':
          fakeSecureStorage.clear();
          return null;
        case 'containsKey':
          final key = call.arguments['key'] as String;
          return fakeSecureStorage.containsKey(key);
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('SigningService', () {
    test('getOrCreatePublicKeyHex() returns a 64-char hex string (32-byte Ed25519 key)', () async {
      final service = SigningService();
      final pubKeyHex = await service.getOrCreatePublicKeyHex();
      expect(pubKeyHex.length, 64);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(pubKeyHex), isTrue);
    });

    test('getOrCreatePublicKeyHex() returns the same key on repeated calls', () async {
      final service = SigningService();
      final first = await service.getOrCreatePublicKeyHex();
      final second = await service.getOrCreatePublicKeyHex();
      expect(first, second);
    });

    test('getOrCreatePublicKeyHex() persists the key across service instances', () async {
      final service1 = SigningService();
      final key1 = await service1.getOrCreatePublicKeyHex();

      final service2 = SigningService();
      final key2 = await service2.getOrCreatePublicKeyHex();

      expect(key1, key2);
    });

    test('sign() throws StateError if called before getOrCreatePublicKeyHex()', () async {
      final service = SigningService();
      expect(() => service.sign('payload'), throwsA(isA<StateError>()));
    });

    test('sign() then verify() round-trip succeeds with the correct key', () async {
      final service = SigningService();
      final pubKeyHex = await service.getOrCreatePublicKeyHex();
      const payload = 'test-payload-123';

      final signature = await service.sign(payload);
      final isValid = await service.verify(payload, pubKeyHex, signature);

      expect(isValid, isTrue);
    });

    test('verify() fails if the payload was tampered with after signing', () async {
      final service = SigningService();
      final pubKeyHex = await service.getOrCreatePublicKeyHex();
      final signature = await service.sign('original-payload');

      final isValid = await service.verify('tampered-payload', pubKeyHex, signature);
      expect(isValid, isFalse);
    });

    test('verify() fails against a different device\'s key', () async {
      fakeSecureStorage.clear();
      final serviceA = SigningService();
      final pubKeyA = await serviceA.getOrCreatePublicKeyHex();

      fakeSecureStorage.clear(); // simulate a second, independent device
      final serviceB = SigningService();
      final pubKeyB = await serviceB.getOrCreatePublicKeyHex();

      expect(pubKeyA, isNot(equals(pubKeyB)));

      const payload = 'shared-payload';
      final signatureFromA = await serviceA.sign(payload);

      final isValid = await serviceB.verify(payload, pubKeyB, signatureFromA);
      expect(isValid, isFalse);
    });

    test('verify() returns false (never throws) for malformed hex input', () async {
      final service = SigningService();
      await service.getOrCreatePublicKeyHex();

      final result = await service.verify('payload', 'not-valid-hex!!', 'also-not-hex');
      expect(result, isFalse);
    });
  });
}
