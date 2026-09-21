import '../enums/packet_type.dart';
import 'mesh_packet.dart';

/// Signed packet that closes an active emergency.
///
/// SECURITY NOTE — sender_id vs responder_id (resolved, don't relitigate):
/// Authorization for whether a termination is honored is checked ONLY
/// against `senderId` (inherited from MeshPacket, the Ed25519 key that
/// actually signed this packet — see MeshServiceImpl._handlePayload,
/// which calls ResponderRegistry.instance.checkResponder(packet.senderId)).
///
/// `responderId` below is informational/display metadata only (e.g. a
/// badge number or backend-issued responder record ID for the dashboard)
/// and is NEVER used for authorization. It cannot be, safely: an attacker
/// signing with their own key could put any responder's ID into this
/// field, so trusting it for auth would let anyone impersonate any
/// responder without needing that responder's private key. Only a valid
/// signature over senderId proves the sender actually holds that key.
///
/// If a future design needs a responder to act on another responder's
/// behalf (e.g. relaying/co-signing), that needs a real delegation
/// mechanism (e.g. a backend-issued, signed delegation token) — not a
/// plain unauthenticated field like this one. Don't wire responderId into
/// checkResponder() without adding that.
class TerminationPacket extends MeshPacket {
  final String emergencyId;

  /// Informational only — see class-level note. NOT used for
  /// authorization. Authorization uses `senderId` (inherited).
  final String responderId;

  const TerminationPacket({
    required super.packetId,
    required super.senderId,
    required super.timestamp,
    required super.nonce,
    required super.ttl,
    required super.hopCount,
    required super.signature,
    required this.emergencyId,
    required this.responderId,
  }) : super(type: PacketType.termination);

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'emergency_id': emergencyId,
      'responder_id': responderId,
    };
  }

  factory TerminationPacket.fromJson(Map<String, dynamic> json) {
    return TerminationPacket(
      packetId: json['packet_id'],
      senderId: json['sender_id'],
      timestamp: DateTime.parse(json['timestamp']),
      nonce: json['nonce'],
      ttl: json['ttl'],
      hopCount: json['hop_count'],
      signature: json['signature'],
      emergencyId: json['emergency_id'],
      responderId: json['responder_id'],
    );
  }

  TerminationPacket copyWith({
    String? packetId,
    String? senderId,
    DateTime? timestamp,
    String? nonce,
    int? ttl,
    int? hopCount,
    String? signature,
    String? emergencyId,
    String? responderId,
  }) {
    return TerminationPacket(
      packetId: packetId ?? this.packetId,
      senderId: senderId ?? this.senderId,
      timestamp: timestamp ?? this.timestamp,
      nonce: nonce ?? this.nonce,
      ttl: ttl ?? this.ttl,
      hopCount: hopCount ?? this.hopCount,
      signature: signature ?? this.signature,
      emergencyId: emergencyId ?? this.emergencyId,
      responderId: responderId ?? this.responderId,
    );
  }

  @override
  MeshPacket withRelayHop({int? ttlOverride}) =>
      copyWith(ttl: ttlOverride ?? ttl - 1, hopCount: hopCount + 1);

  @override
  String get signaturePayload =>
      '$packetId|$senderId|${type.name}|${timestamp.toIso8601String()}|'
      '$nonce|$emergencyId|$responderId';
}