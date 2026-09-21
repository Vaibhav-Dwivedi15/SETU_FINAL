import '../enums/packet_type.dart';

abstract class MeshPacket {
  final String packetId;
  final String senderId;
  final PacketType type;
  final DateTime timestamp;
  final String nonce;
  final int ttl;
  final int hopCount;
  final int protocolVersion;
  final String signature;

  const MeshPacket({
    required this.packetId,
    required this.senderId,
    required this.type,
    required this.timestamp,
    required this.nonce,
    required this.ttl,
    required this.hopCount,
    required this.signature,
    this.protocolVersion = 1,
  });

  Map<String, dynamic> toJson() {
    return {
      'packet_id': packetId,
      'sender_id': senderId,
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'nonce': nonce,
      'ttl': ttl,
      'hop_count': hopCount,
      'protocol_version': protocolVersion,
      'signature': signature,
    };
  }

  String get signaturePayload;

  /// Copy of this packet as it should go out on the next hop.
  ///
  /// [ttlOverride] was added for adaptive TTL (see
  /// mesh/services/adaptive_ttl.dart): callers that pass nothing keep the
  /// original flat `ttl - 1` behaviour exactly, so every existing call
  /// site is unaffected. AdaptiveTtl.nextTtl() guarantees any value
  /// passed here is <= SecurityConstants.maxTTL and strictly less than
  /// the current ttl.
  ///
  /// Safe by construction: none of the four packet types include `ttl` or
  /// `hop_count` in signaturePayload, so changing them on relay does not
  /// invalidate the originator's signature.
  MeshPacket withRelayHop({int? ttlOverride});
}