import 'package:setu_app/mesh/enums/emergency_priority.dart';

import 'recovery_enums.dart';
import 'recovery_record.dart';
import 'recovery_report_type.dart';
import 'report_status.dart';

class DamageReport extends RecoveryRecord {
  const DamageReport({
    required super.id,
    required super.status,
    required super.createdAt,
    required super.updatedAt,
    super.location,
    super.latitude,
    super.longitude,
    super.emergencyId,
    super.lastError,
    this.category,
    this.severity,
    this.description = '',
  });

  final DamageCategory? category;
  final DamageSeverity? severity;
  final String description;

  @override
  RecoveryReportType get type => RecoveryReportType.damage;

  @override
  String get headline => '${category?.label ?? 'Damage'} damage';

  @override
  String? get priorityLabel => severity?.label;

  @override
  bool get isBlank =>
      category == null &&
      severity == null &&
      description.trim().isEmpty &&
      location.trim().isEmpty;

  @override
  Map<String, String> validate() {
    final errors = <String, String>{};
    if (category == null) errors['category'] = 'Choose a damage category.';
    if (severity == null) errors['severity'] = 'Choose a severity.';
    if (location.trim().length < 3) {
      errors['location'] = 'Describe where the damage is (at least 3 characters).';
    }
    if (description.trim().length < 10) {
      errors['description'] = 'Describe the damage (at least 10 characters).';
    }
    return errors;
  }

  @override
  String toPacketMessage() => RecoveryRecord.clip(
        '${category?.label} | ${severity?.label} | ${location.trim()} | '
        '${description.trim()}',
        480,
      );

  @override
  EmergencyPriority get packetPriority =>
      (severity == DamageSeverity.high || severity == DamageSeverity.critical)
          ? EmergencyPriority.medium
          : EmergencyPriority.low;

  DamageReport copyWith({
    DamageCategory? category,
    DamageSeverity? severity,
    String? description,
    String? location,
    double? latitude,
    double? longitude,
  }) =>
      DamageReport(
        id: id,
        status: status,
        createdAt: createdAt,
        updatedAt: updatedAt,
        location: location ?? this.location,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        emergencyId: emergencyId,
        lastError: lastError,
        category: category ?? this.category,
        severity: severity ?? this.severity,
        description: description ?? this.description,
      );

  @override
  DamageReport withMeta({
    ReportStatus? status,
    DateTime? updatedAt,
    String? emergencyId,
    String? lastError,
    bool clearError = false,
  }) =>
      DamageReport(
        id: id,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        location: location,
        latitude: latitude,
        longitude: longitude,
        emergencyId: emergencyId ?? this.emergencyId,
        lastError: clearError ? null : (lastError ?? this.lastError),
        category: category,
        severity: severity,
        description: description,
      );

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'category': category?.name,
        'severity': severity?.name,
        'description': description,
      };

  factory DamageReport.fromJson(Map<String, dynamic> json) => DamageReport(
        id: json['id'] as String,
        status: parseStatus(json['status']),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        location: json['location'] as String? ?? '',
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        emergencyId: json['emergencyId'] as String?,
        lastError: json['lastError'] as String?,
        category: parseEnum(DamageCategory.values, json['category']),
        severity: parseEnum(DamageSeverity.values, json['severity']),
        description: json['description'] as String? ?? '',
      );
}
