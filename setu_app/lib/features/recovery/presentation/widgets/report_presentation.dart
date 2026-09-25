import '../../data/models/damage_report.dart';
import '../../data/models/missing_person_report.dart';
import '../../data/models/recovery_record.dart';
import '../../data/models/resource_request.dart';

/// Local date/time such as "12 Sep 2026, 14:05" (no intl dependency).
String formatDateTime(DateTime value) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final local = value.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month - 1]} ${local.year}, $hh:$mm';
}

/// Label/value pairs shown on the report detail screen, per report kind.
List<(String, String)> detailFields(RecoveryRecord record) {
  final fields = <(String, String)>[];
  final r = record;
  if (r is DamageReport) {
    fields
      ..add(('Category', r.category?.label ?? '—'))
      ..add(('Severity', r.severity?.label ?? '—'))
      ..add(('Location', r.location))
      ..add(('Description', r.description));
  } else if (r is MissingPersonReport) {
    fields
      ..add(('Name', r.name))
      ..add(('Approximate age', r.approximateAge?.toString() ?? '—'))
      ..add(('Last known location', r.location))
      ..add(('Description', r.description));
    if (r.identifyingInfo.trim().isNotEmpty) {
      fields.add(('Identifying information', r.identifyingInfo));
    }
  } else if (r is ResourceRequest) {
    fields
      ..add(('Request', r.resourceType?.label ?? '—'))
      ..add(('Urgency', r.urgency?.label ?? '—'))
      ..add(('Location', r.location))
      ..add(('Description', r.description));
  }
  if (record.latitude != null && record.longitude != null) {
    fields.add((
      'GPS',
      '${record.latitude!.toStringAsFixed(5)}, ${record.longitude!.toStringAsFixed(5)}'
    ));
  }
  return fields;
}
