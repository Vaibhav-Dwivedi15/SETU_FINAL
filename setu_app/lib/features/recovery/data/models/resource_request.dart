import 'package:setu_app/mesh/enums/emergency_priority.dart';

import 'recovery_enums.dart';
import 'recovery_record.dart';
import 'recovery_report_type.dart';
import 'report_status.dart';

class ResourceRequest extends RecoveryRecord {
  const ResourceRequest({
    required super.id,
    required super.status,
    required super.createdAt,
    required super.updatedAt,
    super.location,
    super.latitude,
    super.longitude,
    super.emergencyId,
    super.lastError,
    this.resourceType,
    this.urgency,
    this.description = '',
  });

  final ResourceType? resourceType;
  final RequestUrgency? urgency;
  final String description;

  @override
  RecoveryReportType get type => RecoveryReportType.resourceRequest;

  @override
  String get headline => '${resourceType?.label ?? 'Help'} request';

  @override
  String? get priorityLabel => urgency?.label;

  @override
  bool get isBlank =>
      resourceType == null &&
      urgency == null &&
      description.trim().isEmpty &&
      location.trim().isEmpty;

  @override
  Map<String, String> validate() {
    final errors = <String, String>{};
    if (resourceType == null) errors['resourceType'] = 'Choose what you need.';
    if (urgency == null) errors['urgency'] = 'Choose an urgency.';
    if (location.trim().length < 3) {
      errors['location'] = 'Describe where help is needed (at least 3 characters).';
    }
    if (description.trim().length < 10) {
      errors['description'] = 'Describe what you need (at least 10 characters).';
    }
    return errors;
  }

  @override
  String toPacketMessage() => RecoveryRecord.clip(
        '${resourceType?.label} | ${urgency?.label} | ${location.trim()} | '
        '${description.trim()}',
        480,
      );

  @override
  EmergencyPriority get packetPriority {
    switch (urgency) {
      case RequestUrgency.critical:
        return EmergencyPriority.high;
      case RequestUrgency.urgent:
        return EmergencyPriority.medium;
      case RequestUrgency.normal:
      case null:
        return EmergencyPriority.low;
    }
  }

  ResourceRequest copyWith({
    ResourceType? resourceType,
    RequestUrgency? urgency,
    String? description,
    String? location,
    double? latitude,
    double? longitude,
  }) =>
      ResourceRequest(
        id: id,
        status: status,
        createdAt: createdAt,
        updatedAt: updatedAt,
        location: location ?? this.location,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        emergencyId: emergencyId,
        lastError: lastError,
        resourceType: resourceType ?? this.resourceType,
        urgency: urgency ?? this.urgency,
        description: description ?? this.description,
      );

  @override
  ResourceRequest withMeta({
    ReportStatus? status,
    DateTime? updatedAt,
    String? emergencyId,
    String? lastError,
    bool clearError = false,
  }) =>
      ResourceRequest(
        id: id,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        location: location,
        latitude: latitude,
        longitude: longitude,
        emergencyId: emergencyId ?? this.emergencyId,
        lastError: clearError ? null : (lastError ?? this.lastError),
        resourceType: resourceType,
        urgency: urgency,
        description: description,
      );

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'resourceType': resourceType?.name,
        'urgency': urgency?.name,
        'description': description,
      };

  factory ResourceRequest.fromJson(Map<String, dynamic> json) => ResourceRequest(
        id: json['id'] as String,
        status: parseStatus(json['status']),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        location: json['location'] as String? ?? '',
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        emergencyId: json['emergencyId'] as String?,
        lastError: json['lastError'] as String?,
        resourceType: parseEnum(ResourceType.values, json['resourceType']),
        urgency: parseEnum(RequestUrgency.values, json['urgency']),
        description: json['description'] as String? ?? '',
      );
}
