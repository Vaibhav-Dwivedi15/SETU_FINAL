import 'package:flutter/material.dart';

import '../../data/models/damage_report.dart';
import '../../data/models/recovery_enums.dart';
import '../../data/models/recovery_record.dart';
import '../../data/models/recovery_report_type.dart';
import '../widgets/enum_choice_field.dart';
import '../widgets/report_form_base.dart';

class DamageReportScreen extends ReportFormScreen {
  const DamageReportScreen({super.key, super.draftId, super.repository, super.locationService});

  @override
  State<DamageReportScreen> createState() => _DamageReportScreenState();
}

class _DamageReportScreenState extends ReportFormState<DamageReportScreen> {
  final _description = TextEditingController();
  DamageCategory? _category;
  DamageSeverity? _severity;

  @override
  RecoveryReportType get type => RecoveryReportType.damage;

  @override
  String get screenTitle => 'Damage report';

  @override
  String get locationLabel => 'Location of damage';

  @override
  void applyRecord(RecoveryRecord record) {
    final r = record as DamageReport;
    _category = r.category;
    _severity = r.severity;
    _description.text = r.description;
  }

  @override
  RecoveryRecord readRecord(RecoveryRecord base) => (base as DamageReport).copyWith(
        category: _category,
        severity: _severity,
        description: _description.text,
        location: locationController.text,
        latitude: latitude,
        longitude: longitude,
      );

  @override
  void disposeFields() => _description.dispose();

  @override
  List<Widget> buildFields(BuildContext context) => [
        EnumChoiceField<DamageCategory>(
          label: 'Damage category',
          values: DamageCategory.values,
          labelOf: (v) => v.label,
          selected: _category,
          onChanged: (v) => setState(() => _category = v),
          errorText: errors['category'],
        ),
        EnumChoiceField<DamageSeverity>(
          label: 'Severity',
          values: DamageSeverity.values,
          labelOf: (v) => v.label,
          selected: _severity,
          onChanged: (v) => setState(() => _severity = v),
          errorText: errors['severity'],
        ),
        locationField(),
        textField(
          label: 'Description',
          controller: _description,
          errorKey: 'description',
          maxLines: 5,
          maxLength: 400,
          hint: 'What is damaged and how?',
        ),
      ];
}
