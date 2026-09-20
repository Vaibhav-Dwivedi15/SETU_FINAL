import '../enums/emergency_priority.dart';
import '../enums/packet_type.dart';
import 'mesh_packet.dart';

class EmergencyPacket extends MeshPacket {
  final String emergencyId;
  final double latitude;
  final double longitude;
  final String message;
  final EmergencyPriority priority;

  const EmergencyPacket({
    required super.packetId,
    required super.senderId,
    required super.timestamp,
    required super.nonce,
    required super.ttl,
    required super.hopCount,
    required super.signature,
    required this.emergencyId,
    required this.latitude,
    required this.longitude,
    required this.message,
    required this.priority,
  }) : super(type: PacketType.emergency);

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'emergency_id': emergencyId,
      'latitude': latitude,
      'longitude': longitude,
      'message': message,
      'priority': priority.name,
    };
  }

  factory EmergencyPacket.fromJson(Map<String, dynamic> json) {
    return EmergencyPacket(
      packetId: json['packet_id'],
      senderId: json['sender_id'],
      timestamp: DateTime.parse(json['timestamp']),
      nonce: json['nonce'],
      ttl: json['ttl'],
      hopCount: json['hop_count'],
      signature: json['signature'],
      emergencyId: json['emergency_id'],
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      message: json['message'],
      priority: EmergencyPriority.values.byName(json['priority']),
    );
  }

  EmergencyPacket copyWith({
    String? packetId,
    String? senderId,
    DateTime? timestamp,
    String? nonce,
    int? ttl,
    int? hopCount,
    String? signature,
    String? emergencyId,
    double? latitude,
    double? longitude,
    String? message,
    EmergencyPriority? priority,
  }) {
    return EmergencyPacket(
      packetId: packetId ?? this.packetId,
      senderId: senderId ?? this.senderId,
      timestamp: timestamp ?? this.timestamp,
      nonce: nonce ?? this.nonce,
      ttl: ttl ?? this.ttl,
      hopCount: hopCount ?? this.hopCount,
      signature: signature ?? this.signature,
      emergencyId: emergencyId ?? this.emergencyId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      message: message ?? this.message,
      priority: priority ?? this.priority,
    );
  }

  @override
  MeshPacket withRelayHop() => copyWith(ttl: ttl - 1, hopCount: hopCount + 1);

  @override
  String get signaturePayload =>
      '$packetId|$senderId|${type.name}|${timestamp.toIso8601String()}|'
      '$nonce|$emergencyId|$latitude|$longitude|$message|${priority.name}';
}
