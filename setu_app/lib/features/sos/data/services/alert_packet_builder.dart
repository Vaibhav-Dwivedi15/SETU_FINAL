import 'dart:math';

import 'package:setu_app/mesh/models/alert_packet.dart';
import 'package:setu_app/mesh/services/identity_service.dart';
import 'package:setu_app/mesh/services/signing_service.dart';
import 'package:setu_app/security/security_constants.dart';

/// Builds a signed AlertPacket (community broadcast), same pattern as
/// EmergencyPacketBuilder / AckPacketBuilder.
class AlertPacketBuilder {
  AlertPacketBuilder({SigningService? signingService})
      : _signing = signingService ?? SigningService() {
    _identity = IdentityService(_signing);
  }

  final SigningService _signing;
  late final IdentityService _identity;

  Future<AlertPacket> buildAlertPacket({
    required String incidentType,
    required double latitude,
    required double longitude,
    int radiusMeters = 1000,
  }) async {
    final senderId = await _identity.getOrCreateSenderId();
    final packetId = _generatePacketId(senderId);
    final nonce = _generateNonce();
    final timestamp = DateTime.now().toUtc();

    final unsigned = AlertPacket(
      packetId: packetId,
      senderId: senderId,
      timestamp: timestamp,
      nonce: nonce,
      ttl: SecurityConstants.defaultTTL,
      hopCount: 0,
      signature: '',
      incidentType: incidentType,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );

    final signature = await _signing.sign(unsigned.signaturePayload);
    return unsigned.copyWith(signature: signature);
  }

  String _generatePacketId(String senderId) {
    final shortSender = senderId.length >= 8 ? senderId.substring(0, 8) : senderId;
    return 'alert-$shortSender-${DateTime.now().microsecondsSinceEpoch}';
  }

  String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
