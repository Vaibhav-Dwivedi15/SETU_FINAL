import 'package:flutter/material.dart';

import '../../data/models/recovery_enums.dart';
import '../../data/models/recovery_record.dart';
import '../../data/models/recovery_report_type.dart';
import '../../data/models/resource_request.dart';
import '../widgets/enum_choice_field.dart';
import '../widgets/report_form_base.dart';

class ResourceRequestScreen extends ReportFormScreen {
  const ResourceRequestScreen({super.key, super.draftId, super.repository, super.locationService});

  @override
  State<ResourceRequestScreen> createState() => _ResourceRequestScreenState();
}

class _ResourceRequestScreenState extends ReportFormState<ResourceRequestScreen> {
  final _description = TextEditingController();
  ResourceType? _resourceType;
  RequestUrgency? _urgency;

  @override
  RecoveryReportType get type => RecoveryReportType.resourceRequest;

  @override
  String get screenTitle => 'Help / resource request';

  @override
  String get locationLabel => 'Where help is needed';

  @override
  void applyRecord(RecoveryRecord record) {
    final r = record as ResourceRequest;
    _resourceType = r.resourceType;
    _urgency = r.urgency;
    _description.text = r.description;
  }

  @override
  RecoveryRecord readRecord(RecoveryRecord base) => (base as ResourceRequest).copyWith(
        resourceType: _resourceType,
        urgency: _urgency,
        description: _description.text,
        location: locationController.text,
        latitude: latitude,
        longitude: longitude,
      );

  @override
  void disposeFields() => _description.dispose();

  @override
  List<Widget> buildFields(BuildContext context) => [
        EnumChoiceField<ResourceType>(
          label: 'What do you need?',
          values: ResourceType.values,
          labelOf: (v) => v.label,
          selected: _resourceType,
          onChanged: (v) => setState(() => _resourceType = v),
          errorText: errors['resourceType'],
        ),
        EnumChoiceField<RequestUrgency>(
          label: 'Urgency',
          values: RequestUrgency.values,
          labelOf: (v) => v.label,
          selected: _urgency,
          onChanged: (v) => setState(() => _urgency = v),
          errorText: errors['urgency'],
        ),
        locationField(),
        textField(
          label: 'Description',
          controller: _description,
          errorKey: 'description',
          maxLines: 5,
          maxLength: 400,
          hint: 'How many people, and what exactly is needed?',
        ),
      ];
}
