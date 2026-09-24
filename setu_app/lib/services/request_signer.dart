import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../mesh/services/signing_service.dart';

/// Signs non-mesh backend requests with the device's EXISTING Ed25519 identity
/// key (Block 2). Mirrors Backend/app/services/request_auth.py exactly:
///
///   canonical = "setu-req-v1|METHOD|/path|senderId|timestamp|nonce|part|part..."
///
/// Headers produced: X-Setu-Sender / X-Setu-Timestamp / X-Setu-Nonce /
/// X-Setu-Signature. `parts` bind the request content (see the backend module
/// docstring for what each endpoint signs). Always sign the RAW strings/bytes
/// that go on the wire.
///
/// No private key ever leaves SigningService; nothing new is stored.
class RequestSigner {
  RequestSigner({SigningService? signing}) : _signing = signing ?? SigningService();

  final SigningService _signing;

  static const String domain = 'setu-req-v1';

  static String canonicalString({
    required String method,
    required String path,
    required String senderId,
    required String timestamp,
    required String nonce,
    List<String> parts = const [],
  }) =>
      [domain, method.toUpperCase(), path, senderId, timestamp, nonce, ...parts].join('|');

  static Future<String> sha256Hex(List<int> bytes) async {
    final hash = await Sha256().hash(bytes);
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String newNonce() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Future<String> senderId() => _signing.getOrCreatePublicKeyHex();

  /// [timestamp] / [nonce] are injectable for deterministic tests only.
  Future<Map<String, String>> headersFor({
    required String method,
    required String path,
    List<String> parts = const [],
    String? timestamp,
    String? nonce,
  }) async {
    final sender = await _signing.getOrCreatePublicKeyHex();
    final ts = timestamp ?? DateTime.now().toUtc().toIso8601String();
    final n = nonce ?? newNonce();
    final signature = await _signing.sign(
      canonicalString(method: method, path: path, senderId: sender, timestamp: ts, nonce: n, parts: parts),
    );
    return {
      'X-Setu-Sender': sender,
      'X-Setu-Timestamp': ts,
      'X-Setu-Nonce': n,
      'X-Setu-Signature': signature,
    };
  }

  /// Convenience for JSON-body endpoints (register, respond): the signature
  /// covers sha256 of the exact body bytes that are sent.
  Future<Map<String, String>> headersForBody({
    required String method,
    required String path,
    required List<int> bodyBytes,
  }) async =>
      headersFor(method: method, path: path, parts: [await sha256Hex(bodyBytes)]);
}

/// Utility used by the tests to keep the utf8 round trip explicit.
List<int> jsonBodyBytes(Object payload) => utf8.encode(jsonEncode(payload));
