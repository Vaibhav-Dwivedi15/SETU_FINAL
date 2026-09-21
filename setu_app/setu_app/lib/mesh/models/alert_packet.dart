import '../enums/packet_type.dart';
import 'mesh_packet.dart';

/// Broadcasts "an emergency is happening near here, go help if you can"
/// to nearby SETU users -- this is what community_demo_screen.dart's UI
/// currently mocks with hardcoded data (see that file's own comment:
/// "Preview only -- mock data, no real backend or radius logic"). This
/// packet is the real mechanism that screen should eventually consume.
///
/// DELIBERATELY MESH-ONLY, NOT PUSH-NOTIFICATION-BASED: this only
/// reaches SETU users who are within relay range and currently
/// BLE/Wi-Fi Direct connected -- the same population already carrying
/// the original EmergencyPacket. That means NO new dependency is
/// needed (no firebase_messaging, no server-side push) -- it reuses
/// the exact same relay engine, TTL, and dedup as every other packet
/// type. The tradeoff: someone with the SETU app open but currently
/// out of mesh range won't get this. Reaching that wider population
/// would need real push notifications, which is a genuinely separate
/// piece of work (see the team chat's tech-gap plan).
///
/// PRIVACY: deliberately carries NOTHING that identifies the original
/// sender -- no senderId of the emergency's origin, no emergencyId, no
/// contact info. Just incident type + approximate location + a radius.
/// A community alert should never let a receiving device correlate
/// back to who specifically is in trouble; that stays backend-only,
/// same principle as why /ingest's response never includes emergency
/// contacts (see ProfileOut vs IncidentOut split, backend schemas).
///
/// STILL NEEDED BEFORE THIS IS FUNCTIONAL (not done in this change):
/// 1. MeshServiceImpl needs to originate one of these alongside the
///    EmergencyPacket when alertMode == AlertMode.public (see the
///    existing TODO comment in sos_repository.dart: "Public Mode ->
///    Notify Nearby SETU Users" -- this packet IS that).
/// 2. A receiving screen/notification needs to actually display it --
///    community_demo_screen.dart is the obvious home for this, once
///    it's wired to a real incoming-packet stream instead of mockAlert.
class AlertPacket extends MeshPacket {
  final String incidentType;
  final double latitude;
  final double longitude;

  /// Meters -- how far from (latitude, longitude) this alert is
  /// considered relevant. Purely advisory for the receiving UI to
  /// decide whether to surface it; not enforced by the relay engine
  /// itself (TTL already bounds how far a packet physically travels).
  final int radiusMeters;

  const AlertPacket({
    required super.packetId,
    required super.senderId,
    required super.timestamp,
    required super.nonce,
    required super.ttl,
    required super.hopCount,
    required super.signature,
    required this.incidentType,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 1000,
  }) : super(type: PacketType.alert);

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'incident_type': incidentType,
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
    };
  }

  factory AlertPacket.fromJson(Map<String, dynamic> json) {
    return AlertPacket(
      packetId: json['packet_id'],
      senderId: json['sender_id'],
      timestamp: DateTime.parse(json['timestamp']),
      nonce: json['nonce'],
      ttl: json['ttl'],
      hopCount: json['hop_count'],
      signature: json['signature'],
      incidentType: json['incident_type'],
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusMeters: json['radius_meters'] ?? 1000,
    );
  }

  AlertPacket copyWith({
    String? packetId,
    String? senderId,
    DateTime? timestamp,
    String? nonce,
    int? ttl,
    int? hopCount,
    String? signature,
    String? incidentType,
    double? latitude,
    double? longitude,
    int? radiusMeters,
  }) {
    return AlertPacket(
      packetId: packetId ?? this.packetId,
      senderId: senderId ?? this.senderId,
      timestamp: timestamp ?? this.timestamp,
      nonce: nonce ?? this.nonce,
      ttl: ttl ?? this.ttl,
      hopCount: hopCount ?? this.hopCount,
      signature: signature ?? this.signature,
      incidentType: incidentType ?? this.incidentType,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
    );
  }

  @override
  MeshPacket withRelayHop({int? ttlOverride}) =>
      copyWith(ttl: ttlOverride ?? ttl - 1, hopCount: hopCount + 1);

  @override
  String get signaturePayload =>
      '$packetId|$senderId|${type.name}|${timestamp.toIso8601String()}|'
      '$nonce|$incidentType|$latitude|$longitude|$radiusMeters';
}
