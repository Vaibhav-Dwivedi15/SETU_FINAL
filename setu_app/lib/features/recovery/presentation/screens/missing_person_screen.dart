import 'package:flutter/material.dart';

import '../../data/models/missing_person_report.dart';
import '../../data/models/recovery_record.dart';
import '../../data/models/recovery_report_type.dart';
import '../widgets/report_form_base.dart';

class MissingPersonScreen extends ReportFormScreen {
  const MissingPersonScreen({super.key, super.draftId, super.repository, super.locationService});

  @override
  State<MissingPersonScreen> createState() => _MissingPersonScreenState();
}

class _MissingPersonScreenState extends ReportFormState<MissingPersonScreen> {
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _description = TextEditingController();
  final _identifying = TextEditingController();

  @override
  RecoveryReportType get type => RecoveryReportType.missingPerson;

  @override
  String get screenTitle => 'Missing person';

  @override
  String get locationLabel => 'Last known location';

  @override
  void applyRecord(RecoveryRecord record) {
    final r = record as MissingPersonReport;
    _name.text = r.name;
    _age.text = r.approximateAge?.toString() ?? '';
    _description.text = r.description;
    _identifying.text = r.identifyingInfo;
  }

  @override
  RecoveryRecord readRecord(RecoveryRecord base) {
    final report = base as MissingPersonReport;
    final age = int.tryParse(_age.text.trim());
    return MissingPersonReport(
      id: report.id,
      status: report.status,
      createdAt: report.createdAt,
      updatedAt: report.updatedAt,
      emergencyId: report.emergencyId,
      lastError: report.lastError,
      location: locationController.text,
      latitude: latitude,
      longitude: longitude,
      name: _name.text,
      // A non-numeric age is kept as null so validation reports it.
      approximateAge: age,
      description: _description.text,
      identifyingInfo: _identifying.text,
    );
  }

  @override
  void disposeFields() {
    _name.dispose();
    _age.dispose();
    _description.dispose();
    _identifying.dispose();
  }

  @override
  List<Widget> buildFields(BuildContext context) => [
        textField(label: 'Name', controller: _name, errorKey: 'name'),
        textField(
          label: 'Approximate age',
          controller: _age,
          errorKey: 'age',
          keyboardType: TextInputType.number,
          maxLength: 3,
        ),
        locationField(),
        textField(
          label: 'Description',
          controller: _description,
          errorKey: 'description',
          maxLines: 4,
          maxLength: 300,
          hint: 'Height, clothing, what they were doing',
        ),
        textField(
          label: 'Additional identifying information',
          controller: _identifying,
          maxLines: 3,
          maxLength: 150,
          optional: true,
        ),
      ];
}
