import 'damage_report.dart';
import 'missing_person_report.dart';
import 'recovery_record.dart';
import 'recovery_report_type.dart';
import 'resource_request.dart';

/// Decodes a stored record by its `type` discriminator. Returns null for
/// an unknown type so one unreadable entry cannot lose the whole list.
RecoveryRecord? decodeRecoveryRecord(Map<String, dynamic> json) {
  final type = parseEnum(RecoveryReportType.values, json['type']);
  switch (type) {
    case RecoveryReportType.damage:
      return DamageReport.fromJson(json);
    case RecoveryReportType.missingPerson:
      return MissingPersonReport.fromJson(json);
    case RecoveryReportType.resourceRequest:
      return ResourceRequest.fromJson(json);
    case null:
      return null;
  }
}
