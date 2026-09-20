import 'dart:math';

import 'package:setu_app/mesh/enums/emergency_priority.dart';
import 'package:setu_app/mesh/models/emergency_packet.dart';
import 'package:setu_app/mesh/services/identity_service.dart';
import 'package:setu_app/mesh/services/signing_service.dart';
import 'package:setu_app/security/security_constants.dart';

import '../models/emergency_category.dart';

// =====================================================
// SETU Project
// Module : SOS -> signed EmergencyPacket bridge
// =====================================================
//
// Converts a UI-side SOS trigger into a fully signed EmergencyPacket,
// ready for MeshServiceImpl.originate(). ttl/hop_count/protocol_version
// are deliberately excluded from the signed payload (see EmergencyPacket
// .signaturePayload) — that's unchanged, this file just builds the
// packet and signs it in the correct order (sign AFTER packetId/nonce/
// timestamp are fixed, since those ARE part of the signed payload).
class EmergencyPacketBuilder {
  EmergencyPacketBuilder({SigningService? signingService})
      : _signing = signingService ?? SigningService() {
    _identity = IdentityService(_signing);
  }

  final SigningService _signing;
  late final IdentityService _identity;

  Future<EmergencyPacket> buildEmergencyPacket({
    required double latitude,
    required double longitude,
    required String message,
    required EmergencyCategory category,
  }) async {
    final senderId = await _identity.getOrCreateSenderId();
    final packetId = _generatePacketId(senderId);
    final nonce = _generateNonce();
    final timestamp = DateTime.now().toUtc();
    final priority = _priorityForCategory(category);

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
      message: message,
      priority: priority,
    );

    final signature = await _signing.sign(unsigned.signaturePayload);
    return unsigned.copyWith(signature: signature);
  }

  // EmergencyPriority confirmed: low, medium, high, critical.
  // Keyword match on category.name so this doesn't break if
  // emergency_category.dart's exact member names differ slightly
  // (e.g. buildingCollapse vs building_collapse) — adjust the keyword
  // lists below if a category is landing in the wrong bucket.
  EmergencyPriority _priorityForCategory(EmergencyCategory category) {
    final name = category.name.toLowerCase();

    const criticalKeywords = ['fire', 'collapse', 'earthquake'];
    const highKeywords = ['medical', 'accident', 'flood', 'women', 'safety'];

    if (criticalKeywords.any(name.contains)) return EmergencyPriority.critical;
    if (highKeywords.any(name.contains)) return EmergencyPriority.high;
    return EmergencyPriority.medium; // generalSos and anything unmatched
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
