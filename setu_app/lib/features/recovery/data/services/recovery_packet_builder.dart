import 'dart:math';

import 'package:setu_app/mesh/models/emergency_packet.dart';
import 'package:setu_app/mesh/services/identity_service.dart';
import 'package:setu_app/mesh/services/signing_service.dart';
import 'package:setu_app/security/security_constants.dart';

import '../models/recovery_report_type.dart';

// =====================================================
// SETU Project
// Module : Recovery report -> signed EmergencyPacket bridge
// Priority 8 (AFTER-disaster)
// =====================================================
//
// Deliberately the same shape as EmergencyPacketBuilder (SOS ->
// EmergencyPacket) -- a recovery report IS an EmergencyPacket, just
// with a lower-urgency priority and a machine-parseable prefix on the
// message. ttl/hop_count/protocol_version are excluded from the signed
// payload exactly as they are for a live SOS (see
// EmergencyPacket.signaturePayload); this file does not touch that.
class RecoveryPacketBuilder {
  RecoveryPacketBuilder({SigningService? signingService})
      : _signing = signingService ?? SigningService() {
    _identity = IdentityService(_signing);
  }

  final SigningService _signing;
  late final IdentityService _identity;

  Future<EmergencyPacket> buildRecoveryPacket({
    required RecoveryReportType type,
    required double latitude,
    required double longitude,
    required String message,
  }) async {
    final senderId = await _identity.getOrCreateSenderId();
    final packetId = _generatePacketId(senderId);
    final nonce = _generateNonce();
    final timestamp = DateTime.now().toUtc();

    final unsigned = EmergencyPacket(
      packetId: packetId,
      senderId: senderId,
      timestamp: timestamp,
      nonce: nonce,
      ttl: SecurityConstants.defaultTTL,
      hopCount: 0,
      signature: '',
      emergencyId: packetId,
      latitude: latitude,
      longitude: longitude,
      message: '${type.messagePrefix} $message'.trim(),
      priority: type.priority,
    );

    final signature = await _signing.sign(unsigned.signaturePayload);
    return unsigned.copyWith(signature: signature);
  }

  String _generatePacketId(String senderId) {
    final shortSender = senderId.length >= 8 ? senderId.substring(0, 8) : senderId;
    return '$shortSender-${DateTime.now().microsecondsSinceEpoch}';
  }

  String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
