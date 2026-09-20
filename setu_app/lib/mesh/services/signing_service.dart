import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Owns this device's Ed25519 keypair: generates it once, persists the
/// private key in Android Keystore-backed secure storage, and signs /
/// verifies packet payloads.
///
/// The public key (hex-encoded) doubles as this device's senderId — a
/// self-certifying identity, so any receiver can verify a signature
/// without a separate key-exchange step.
class SigningService {
  static const _privateKeySeedKey = 'setu_signing_private_key_seed';

  final _algorithm = Ed25519();
  final _secureStorage = const FlutterSecureStorage();

  SimpleKeyPair? _keyPair;
  String? _publicKeyHex;

  Future<String> getOrCreatePublicKeyHex() async {
    if (_publicKeyHex != null) return _publicKeyHex!;

    final existingSeedHex = await _secureStorage.read(key: _privateKeySeedKey);
    if (existingSeedHex != null) {
      _keyPair = await _algorithm.newKeyPairFromSeed(_hexToBytes(existingSeedHex));
    } else {
      _keyPair = await _algorithm.newKeyPair();
      final seed = await _keyPair!.extractPrivateKeyBytes();
      await _secureStorage.write(key: _privateKeySeedKey, value: _bytesToHex(seed));
    }

    final publicKey = await _keyPair!.extractPublicKey();
    _publicKeyHex = _bytesToHex(publicKey.bytes);
    return _publicKeyHex!;
  }

  /// Signs a string payload (typically MeshPacket.signaturePayload).
  Future<String> sign(String payload) async {
    if (_keyPair == null) {
      throw StateError('Call getOrCreatePublicKeyHex() before sign().');
    }
    final signature = await _algorithm.sign(utf8.encode(payload), keyPair: _keyPair!);
    return _bytesToHex(signature.bytes);
  }

  /// Verifies a signature against a claimed sender's public key (hex).
  /// Proves integrity + genuine origin from that key — does NOT prove the
  /// key belongs to an authorized responder. That's a separate,
  /// backend-side registry check.
  Future<bool> verify(String payload, String senderPublicKeyHex, String signatureHex) async {
    try {
      final publicKey = SimplePublicKey(_hexToBytes(senderPublicKeyHex), type: KeyPairType.ed25519);
      final signature = Signature(_hexToBytes(signatureHex), publicKey: publicKey);
      return await _algorithm.verify(utf8.encode(payload), signature: signature);
    } catch (e) {
      return false; // malformed key/signature — invalid, not a crash
    }
  }

  static String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}
