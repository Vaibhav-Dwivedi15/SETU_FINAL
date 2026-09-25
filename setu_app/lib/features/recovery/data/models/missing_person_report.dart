import 'package:setu_app/mesh/enums/emergency_priority.dart';

import 'recovery_record.dart';
import 'recovery_report_type.dart';
import 'report_status.dart';

/// A missing-person report. [location] holds the last known location.
class MissingPersonReport extends RecoveryRecord {
  const MissingPersonReport({
    required super.id,
    required super.status,
    required super.createdAt,
    required super.updatedAt,
    super.location,
    super.latitude,
    super.longitude,
    super.emergencyId,
    super.lastError,
    this.name = '',
    this.approximateAge,
    this.description = '',
    this.identifyingInfo = '',
  });

  final String name;
  final int? approximateAge;
  final String description;
  final String identifyingInfo;

  @override
  RecoveryReportType get type => RecoveryReportType.missingPerson;

  @override
  String get headline => name.trim().isEmpty ? 'Missing person' : name.trim();

  @override
  String? get priorityLabel => null;

  @override
  bool get isBlank =>
      name.trim().isEmpty &&
      approximateAge == null &&
      description.trim().isEmpty &&
      identifyingInfo.trim().isEmpty &&
      location.trim().isEmpty;

  @override
  Map<String, String> validate() {
    final errors = <String, String>{};
    if (name.trim().length < 2) errors['name'] = 'Enter the person\'s name.';
    final age = approximateAge;
    if (age == null || age < 0 || age > 120) {
      errors['age'] = 'Enter an approximate age between 0 and 120.';
    }
    if (location.trim().length < 3) {
      errors['location'] = 'Enter the last known location (at least 3 characters).';
    }
    if (description.trim().length < 10) {
      errors['description'] =
          'Describe the person, such as clothing and height (at least 10 characters).';
    }
    return errors;
  }

  @override
  String toPacketMessage() {
    final extra = identifyingInfo.trim();
    return RecoveryRecord.clip(
      '${name.trim()} | age ~$approximateAge | last seen ${location.trim()} | '
      '${description.trim()}${extra.isEmpty ? '' : ' | $extra'}',
      480,
    );
  }

  @override
  EmergencyPriority get packetPriority => EmergencyPriority.high;

  MissingPersonReport copyWith({
    String? name,
    int? approximateAge,
    String? description,
    String? identifyingInfo,
    String? location,
    double? latitude,
    double? longitude,
  }) =>
      MissingPersonReport(
        id: id,
        status: status,
        createdAt: createdAt,
        updatedAt: updatedAt,
        location: location ?? this.location,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        emergencyId: emergencyId,
        lastError: lastError,
        name: name ?? this.name,
        approximateAge: approximateAge ?? this.approximateAge,
        description: description ?? this.description,
        identifyingInfo: identifyingInfo ?? this.identifyingInfo,
      );

  @override
  MissingPersonReport withMeta({
    ReportStatus? status,
    DateTime? updatedAt,
    String? emergencyId,
    String? lastError,
    bool clearError = false,
  }) =>
      MissingPersonReport(
        id: id,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        location: location,
        latitude: latitude,
        longitude: longitude,
        emergencyId: emergencyId ?? this.emergencyId,
        lastError: clearError ? null : (lastError ?? this.lastError),
        name: name,
        approximateAge: approximateAge,
        description: description,
        identifyingInfo: identifyingInfo,
      );

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'name': name,
        'approximateAge': approximateAge,
        'description': description,
        'identifyingInfo': identifyingInfo,
      };

  factory MissingPersonReport.fromJson(Map<String, dynamic> json) =>
      MissingPersonReport(
        id: json['id'] as String,
        status: parseStatus(json['status']),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        location: json['location'] as String? ?? '',
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        emergencyId: json['emergencyId'] as String?,
        lastError: json['lastError'] as String?,
        name: json['name'] as String? ?? '',
        approximateAge: json['approximateAge'] as int?,
        description: json['description'] as String? ?? '',
        identifyingInfo: json['identifyingInfo'] as String? ?? '',
      );
}
