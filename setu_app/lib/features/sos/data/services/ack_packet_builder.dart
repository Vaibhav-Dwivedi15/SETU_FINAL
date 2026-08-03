import 'dart:math';

import 'package:setu_app/mesh/models/ack_packet.dart';
import 'package:setu_app/mesh/services/identity_service.dart';
import 'package:setu_app/mesh/services/signing_service.dart';
import 'package:setu_app/security/security_constants.dart';

/// Builds a signed AckPacket, exact same pattern as
/// EmergencyPacketBuilder -- see that file for the reasoning on why
/// sign-after-fields-fixed matters.
class AckPacketBuilder {
  AckPacketBuilder({SigningService? signingService})
      : _signing = signingService ?? SigningService() {
    _identity = IdentityService(_signing);
  }

  final SigningService _signing;
  late final IdentityService _identity;

  Future<AckPacket> buildAckPacket({
    required String originalPacketId,
    required String emergencyId,
  }) async {
    final senderId = await _identity.getOrCreateSenderId();
    final packetId = _generatePacketId(senderId);
    final nonce = _generateNonce();
    final timestamp = DateTime.now().toUtc();

    final unsigned = AckPacket(
      packetId: packetId,
      senderId: senderId,
      timestamp: timestamp,
      nonce: nonce,
      ttl: SecurityConstants.defaultTTL,
      hopCount: 0,
      signature: '',
      originalPacketId: originalPacketId,
      emergencyId: emergencyId,
    );

    final signature = await _signing.sign(unsigned.signaturePayload);
    return unsigned.copyWith(signature: signature);
  }

  String _generatePacketId(String senderId) {
    final shortSender = senderId.length >= 8 ? senderId.substring(0, 8) : senderId;
    return 'ack-$shortSender-${DateTime.now().microsecondsSinceEpoch}';
  }

  String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
