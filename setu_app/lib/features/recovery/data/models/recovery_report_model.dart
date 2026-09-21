import 'recovery_report_type.dart';

/// Local-only record of a recovery report this device sent -- a
/// "Recovery" analogue of HistoryModel, kept separate rather than
/// bolted onto HistoryModel because that model's shape (recipients,
/// mapsLink, SMS-oriented fields) is specific to the SOS/SMS flow and
/// doesn't fit a mesh-only recovery report. Persisted via
/// RecoveryLogService (SharedPreferences), same pattern as
/// RelayLogService.
class RecoveryReportModel {
  final String id;
  final RecoveryReportType type;
  final String message;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  /// Set once MeshServiceImpl.originate() returns without throwing --
  /// mirrors the "Sent" status HistoryModel uses. Updated to
  /// 'Delivered' when a real AckPacket for this report's emergencyId
  /// arrives -- see emergencyId below and MeshLocator's acknowledgments
  /// listener, which now updates recovery entries the same way it
  /// already updated SOS history entries (previously this was a
  /// documented Phase 8 cut; closed as an additive, backend-only
  /// change that doesn't touch the mesh/packet layer).
  final String status;

  /// Same emergencyId the signed EmergencyPacket this report was sent
  /// as carries (see RecoveryPacketBuilder -- it sets
  /// `emergencyId: packetId`). This is what MeshLocator's ack listener
  /// matches against to know "is this ack for a recovery report I
  /// originated", mirroring HistoryModel.emergencyId exactly. Defaults
  /// to `id` for backward compatibility with log entries written
  /// before this field existed, since `id` was always set to the same
  /// packetId anyway (see RecoveryRepository.submitReport).
  final String emergencyId;

  const RecoveryReportModel({
    required this.id,
    required this.type,
    required this.message,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.status = 'Sent',
    String? emergencyId,
  }) : emergencyId = emergencyId ?? id;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'message': message,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toIso8601String(),
        'status': status,
        'emergencyId': emergencyId,
      };

  factory RecoveryReportModel.fromJson(Map<String, dynamic> json) {
    return RecoveryReportModel(
      id: json['id'],
      // Falls back to communityUpdate for any type value this build
      // doesn't recognize (e.g. an older/newer log entry format),
      // rather than throwing and losing the whole persisted list.
      type: RecoveryReportType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => RecoveryReportType.communityUpdate,
      ),
      message: json['message'] ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
      status: json['status'] ?? 'Sent',
      // Falls back to id (not '') for entries written before this
      // field existed -- unlike HistoryModel's '' fallback, we know
      // the correct value here: id was always the packetId/emergencyId.
      emergencyId: json['emergencyId'] ?? json['id'],
    );
  }

  RecoveryReportModel copyWith({
    String? id,
    RecoveryReportType? type,
    String? message,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    String? status,
    String? emergencyId,
  }) {
    return RecoveryReportModel(
      id: id ?? this.id,
      type: type ?? this.type,
      message: message ?? this.message,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      emergencyId: emergencyId ?? this.emergencyId,
    );
  }
}
