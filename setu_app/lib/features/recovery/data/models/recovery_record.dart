import 'package:setu_app/mesh/enums/emergency_priority.dart';

import 'recovery_report_type.dart';
import 'report_status.dart';

/// Fields shared by every citizen recovery report. The three concrete
/// kinds ([DamageReport], [MissingPersonReport], [ResourceRequest]) add
/// their own fields and validation; storage, history, filtering and
/// dispatch only ever deal with this base type.
abstract class RecoveryRecord {
  const RecoveryRecord({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.location = '',
    this.latitude,
    this.longitude,
    this.emergencyId,
    this.lastError,
  });

  /// Human-quotable report ID (e.g. DMG-K3F9Q2).
  final String id;
  final ReportStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Free-text place description entered by the user.
  final String location;

  /// Optional GPS fix, only if the user tapped "Use my location".
  final double? latitude;
  final double? longitude;

  /// The emergencyId of the signed packet this report was dispatched as;
  /// used to match a returning acknowledgement. Null until dispatched.
  final String? emergencyId;

  /// Reason the last dispatch attempt failed, for the failed state.
  final String? lastError;

  RecoveryReportType get type;

  /// One-line title for lists.
  String get headline;

  /// Severity / urgency text for lists, or null (missing person).
  String? get priorityLabel;

  /// Field name -> error message. Empty means the report can be submitted.
  Map<String, String> validate();

  /// True if the user has entered nothing at all (not worth saving as a
  /// draft).
  bool get isBlank;

  /// Human-readable body carried inside the signed packet. Kept compact.
  String toPacketMessage();

  /// Packet priority. Never [EmergencyPriority.critical]: that tier is
  /// reserved for live emergencies so recovery traffic can never bury a
  /// real SOS in the relay queue.
  EmergencyPriority get packetPriority;

  /// Same record with lifecycle metadata replaced (content unchanged).
  RecoveryRecord withMeta({
    ReportStatus? status,
    DateTime? updatedAt,
    String? emergencyId,
    String? lastError,
    bool clearError = false,
  });

  Map<String, dynamic> toJson();

  Map<String, dynamic> baseJson() => {
        'id': id,
        'type': type.name,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'location': location,
        'latitude': latitude,
        'longitude': longitude,
        'emergencyId': emergencyId,
        'lastError': lastError,
      };

  /// Truncates to [max] characters, marking the cut.
  static String clip(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max - 1)}…';

  static String? optionalText(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Shared parsing helpers for the concrete records' fromJson.
ReportStatus parseStatus(Object? name) => ReportStatus.values.firstWhere(
      (s) => s.name == name,
      orElse: () => ReportStatus.failed,
    );

T? parseEnum<T extends Enum>(List<T> values, Object? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}
