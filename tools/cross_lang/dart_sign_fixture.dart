// SETU — Cross-language Ed25519 signature fixture generator (Dart side)
// Sep 21 2026 (Vib, Bulk Sprint 5, Phase 4).
//
// STATUS: written, NOT executed. The Dart SDK is not available anywhere in
// the sandbox this was authored in (confirmed again this sprint: `dart`/
// `flutter` are not on PATH and no Flutter/Dart SDK directory exists
// anywhere on the filesystem). This script is a ready-to-run handoff for
// whoever next has a real Flutter/Dart environment — see
// docs/mesh/CROSS_LANGUAGE_SIGNATURE_VALIDATION.md for exact run
// instructions and what to do with its output.
//
// WHAT THIS DOES: uses the exact same `package:cryptography` `Ed25519()`
// algorithm object that `lib/mesh/services/signing_service.dart`'s
// `SigningService.sign()` calls internally (`_algorithm.sign(...)`), with a
// FIXED, deterministic 32-byte seed (bytes 0x00..0x1f — a test fixture, not
// a production key), over a FIXED signaturePayload string built to exactly
// match `EmergencyPacket.signaturePayload`'s real field order (see
// `lib/mesh/models/emergency_packet.dart`), and prints the public key,
// signature, and payload as hex/plain text.
//
// WHY NOT CALL `SigningService.sign()` DIRECTLY: `SigningService` also owns
// `FlutterSecureStorage`, which needs a real Flutter engine (platform
// channels) to run — it cannot be instantiated from a plain `dart run`
// script outside a full Flutter app/test harness. This script uses the
// same underlying `Ed25519()` primitive `SigningService` delegates to,
// which IS plain, platform-independent Dart, so it faithfully exercises
// the real signing algorithm without needing a full Flutter runtime. This
// is stated explicitly so nobody mistakes this for "ran SigningService
// itself" — it did not, and does not need to, since the byte-level signing
// operation is identical either way (`SigningService.sign()` is a thin
// wrapper: `_algorithm.sign(utf8.encode(payload), keyPair: _keyPair!)`,
// nothing more).
//
// RUN (from a machine/CI with Flutter installed):
//   cd setu_app
//   dart run ../tools/cross_lang/dart_sign_fixture.dart
//
// (This script imports `package:cryptography` directly, the same
// dependency already declared in setu_app/pubspec.yaml — no extra
// dependency needed, but it must be run with `setu_app` as the working
// directory, or with `dart run` pointed at a context where `flutter pub
// get` has already resolved that package, since this script is not itself
// inside `setu_app/lib` or `setu_app/test`.)

import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

Uint8List hexToBytes(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (int i = 0; i < hex.length; i += 2) {
    result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }
  return result;
}

String bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Future<void> main() async {
  final algorithm = Ed25519();

  // Fixed, deterministic 32-byte seed -- test fixture ONLY, never a
  // production key. Same seed bytes as tools/Ed25519VectorTest.java's
  // fixture, chosen specifically so the two vectors are directly
  // comparable if both are ever run (they use different key-derivation
  // internals -- BouncyCastle's Ed25519PrivateKeyParameters vs Dart's
  // cryptography package's newKeyPairFromSeed -- so an identical seed does
  // NOT guarantee an identical public key; that is itself part of what
  // this fixture would reveal if run).
  final seed = Uint8List.fromList(List<int>.generate(32, (i) => i));

  final keyPair = await algorithm.newKeyPairFromSeed(seed);
  final publicKey = await keyPair.extractPublicKey();
  final senderIdHex = bytesToHex(publicKey.bytes);

  // EXACT field order from EmergencyPacket.signaturePayload
  // (lib/mesh/models/emergency_packet.dart) -- copied here as literal
  // string construction, not re-derived, so there is no risk of silently
  // drifting from the real getter's field order.
  const packetIdSuffix = '-1767225600000000'; // fixed fake micros, matches Ed25519VectorTest.java's fixture
  final packetId = '${senderIdHex.substring(0, 8)}$packetIdSuffix';
  const nonce = '000102030405060708090a0b0c0d0e0f';
  const timestamp = '2026-01-01T00:00:00.000Z';
  final emergencyId = packetId;
  const latitude = '12.9716';
  const longitude = '77.5946';
  const message = 'Test SOS message';
  const priority = 'critical';

  final payload = '$packetId|$senderIdHex|emergency|$timestamp|'
      '$nonce|$emergencyId|$latitude|$longitude|$message|$priority';

  final signature = await algorithm.sign(utf8.encode(payload), keyPair: keyPair);
  final signatureHex = bytesToHex(signature.bytes);

  print('seed_hex=${bytesToHex(seed)}');
  print('sender_id(public_key_hex)=$senderIdHex');
  print('sender_id_length=${senderIdHex.length}');
  print('');
  print('payload_string=$payload');
  print('payload_utf8_byte_length=${utf8.encode(payload).length}');
  print('');
  print('signature_hex=$signatureHex');
  print('signature_length=${signatureHex.length}');

  // Self-check: verify with the SAME Dart algorithm object before anyone
  // even copies this into the Kotlin side -- if this ever prints false,
  // something is wrong with THIS script, not with Kotlin.
  final selfCheckPublicKey = SimplePublicKey(hexToBytes(senderIdHex), type: KeyPairType.ed25519);
  final selfCheckSignature = Signature(hexToBytes(signatureHex), publicKey: selfCheckPublicKey);
  final selfCheckOk = await algorithm.verify(utf8.encode(payload), signature: selfCheckSignature);
  print('');
  print('dart_self_verify=$selfCheckOk (expected true)');
}
