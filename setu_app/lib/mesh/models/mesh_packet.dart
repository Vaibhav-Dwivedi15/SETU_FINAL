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

  MeshPacket withRelayHop();
}