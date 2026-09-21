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
  /// mirrors the "Sent" status HistoryModel uses; this module does not
  /// yet track delivery acks the way SOS does (see module docstring in
  /// recovery_repository.dart for why that's a reasonable Phase 8 cut).
  final String status;

  const RecoveryReportModel({
    required this.id,
    required this.type,
    required this.message,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.status = 'Sent',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'message': message,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toIso8601String(),
        'status': status,
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
    );
  }
}
