import 'signing_service.dart';

/// This device's persistent sender identity — literally the device's
/// Ed25519 public key (hex-encoded). Self-certifying: receivers verify
/// signatures directly against this value, no separate identity lookup.
class IdentityService {
  IdentityService(this._signing);

  final SigningService _signing;

  Future<String> getOrCreateSenderId() => _signing.getOrCreatePublicKeyHex();
}