import '../enums/packet_type.dart';
import 'mesh_packet.dart';

/// Confirms to the ORIGINAL sender that their emergency packet actually
/// reached an internet-connected exit node and was accepted by the
/// backend -- not just "queued locally", which is all SosRepository can
/// currently promise (see sos_repository.dart's optimistic "Delivered"
/// status).
///
/// FLOW: the exit node (Pn) that successfully uploads an EmergencyPacket
/// to the backend originates one of these, addressed back to the
/// original emergencyId. It travels the mesh the same way any other
/// packet does -- there's no separate "reverse path" mechanism, it's
/// just a normal packet that happens to matter to whichever device
/// recognizes its own emergencyId.
///
/// STILL NEEDED BEFORE THIS IS FUNCTIONAL (not done in this change):
/// 1. Backend: POST /ingest needs to signal "this was a first-time
///    accept" back to whichever service originates the ack (currently
///    it only returns {accepted, rejected} -- see ingest.py). Simplest
///    version: the exit node's own app originates the AckPacket
///    client-side, the moment its own upload call succeeds -- no
///    backend change required for a first version of this.
/// 2. MeshServiceImpl._handleNearbyEvent (mesh_service.dart) needs a
///    case for PacketType.ack: if emergencyId matches something this
///    device originated, surface it to the UI (replace the optimistic
///    "Delivered" history entry with a real confirmed state) instead
///    of just relaying it onward like other packet types.
/// 3. Relay of an AckPacket should NOT go through
///    ResponderRegistry.checkResponder() (that's for termination
///    packets only) -- acks aren't a privileged action, any device can
///    relay one.
class AckPacket extends MeshPacket {
  /// The packetId of the original EmergencyPacket this is confirming.
  final String originalPacketId;

  /// Same emergencyId the original EmergencyPacket carried -- this is
  /// what a relaying/receiving device matches against to know "is this
  /// ack for something I originated".
  final String emergencyId;

  const AckPacket({
    required super.packetId,
    required super.senderId,
    required super.timestamp,
    required super.nonce,
    required super.ttl,
    required super.hopCount,
    required super.signature,
    required this.originalPacketId,
    required this.emergencyId,
  }) : super(type: PacketType.ack);

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'original_packet_id': originalPacketId,
      'emergency_id': emergencyId,
    };
  }

  factory AckPacket.fromJson(Map<String, dynamic> json) {
    return AckPacket(
      packetId: json['packet_id'],
      senderId: json['sender_id'],
      timestamp: DateTime.parse(json['timestamp']),
      nonce: json['nonce'],
      ttl: json['ttl'],
      hopCount: json['hop_count'],
      signature: json['signature'],
      originalPacketId: json['original_packet_id'],
      emergencyId: json['emergency_id'],
    );
  }

  AckPacket copyWith({
    String? packetId,
    String? senderId,
    DateTime? timestamp,
    String? nonce,
    int? ttl,
    int? hopCount,
    String? signature,
    String? originalPacketId,
    String? emergencyId,
  }) {
    return AckPacket(
      packetId: packetId ?? this.packetId,
      senderId: senderId ?? this.senderId,
      timestamp: timestamp ?? this.timestamp,
      nonce: nonce ?? this.nonce,
      ttl: ttl ?? this.ttl,
      hopCount: hopCount ?? this.hopCount,
      signature: signature ?? this.signature,
      originalPacketId: originalPacketId ?? this.originalPacketId,
      emergencyId: emergencyId ?? this.emergencyId,
    );
  }

  @override
  MeshPacket withRelayHop() => copyWith(ttl: ttl - 1, hopCount: hopCount + 1);

  @override
  String get signaturePayload =>
      '$packetId|$senderId|${type.name}|${timestamp.toIso8601String()}|'
      '$nonce|$originalPacketId|$emergencyId';
}
