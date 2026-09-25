import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';
import 'package:setu_app/core/widgets/theme_colors.dart';

import '../../../location/data/services/location_service.dart';
import '../../data/models/recovery_record.dart';
import '../../data/models/recovery_report_type.dart';
import '../../data/models/report_status.dart';
import '../../data/repositories/recovery_repository.dart';
import 'report_status_chip.dart';

/// Base for the three report form screens (damage, missing person, help
/// request). A form screen only declares its fields; loading a draft,
/// saving a draft, validating, submitting and the honest confirmation
/// messages live here once.
abstract class ReportFormScreen extends StatefulWidget {
  const ReportFormScreen({
    super.key,
    this.draftId,
    this.repository,
    this.locationService,
  });

  /// Id of an existing draft or failed report to edit; null for a new one.
  final String? draftId;

  /// Injection points for tests.
  final RecoveryRepository? repository;
  final LocationService? locationService;
}

abstract class ReportFormState<W extends ReportFormScreen> extends State<W> {
  late final RecoveryRepository repository = widget.repository ?? RecoveryRepository();
  late final LocationService _locationService = widget.locationService ?? LocationService();

  final TextEditingController locationController = TextEditingController();
  double? latitude;
  double? longitude;

  RecoveryRecord? _record;
  bool _loading = true;
  bool _busy = false;
  bool _locating = false;
  Map<String, String> errors = {};

  RecoveryReportType get type;
  String get screenTitle;
  String get locationLabel => 'Location';

  /// Copy a stored record into the field controllers.
  void applyRecord(RecoveryRecord record);

  /// Build a record from the current field values on top of [base].
  RecoveryRecord readRecord(RecoveryRecord base);

  List<Widget> buildFields(BuildContext context);

  void disposeFields();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    RecoveryRecord? existing;
    final id = widget.draftId;
    if (id != null) {
      final stored = await repository.get(id);
      if (stored != null && stored.type == type && stored.status.isEditable) {
        existing = stored;
      }
    }
    final record = existing ?? repository.newDraft(type);
    if (existing != null) {
      applyRecord(existing);
      locationController.text = existing.location;
      latitude = existing.latitude;
      longitude = existing.longitude;
    }
    if (!mounted) return;
    setState(() {
      _record = record;
      _loading = false;
    });
  }

  @override
  void dispose() {
    locationController.dispose();
    disposeFields();
    super.dispose();
  }

  RecoveryRecord _read() {
    final base = _record!;
    return readRecord(base);
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.emergency : AppColors.success,
    ));
  }

  Future<void> _saveDraft() async {
    setState(() {
      _busy = true;
    });
    try {
      final saved = await repository.saveDraft(_read());
      if (!mounted) return;
      setState(() {
      _record = saved;
    });
      _snack('Draft saved on this device.');
      Navigator.of(context).pop(true);
    } on RecoveryValidationException catch (e) {
      if (mounted) _snack(e.toString(), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    final built = _read();
    final found = built.validate();
    setState(() => errors = found);
    if (found.isNotEmpty) {
      _snack('Please fix the highlighted fields.', error: true);
      return;
    }

    setState(() {
      _busy = true;
    });
    try {
      final result = await repository.submit(built);
      if (!mounted) return;
      if (result.status == ReportStatus.failed) {
        _snack('Sync failed. Report remains saved locally.', error: true);
      } else {
        _snack('Report saved. It will sync when connectivity is available.');
      }
      context.pushReplacement('/recovery/reports/${result.id}');
    } on RecoveryValidationException catch (e) {
      if (mounted) setState(() => errors = e.errors);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _useLocation() async {
    setState(() {
      _locating = true;
    });
    try {
      final fix = await _locationService.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        latitude = fix.latitude;
        longitude = fix.longitude;
      });
    } catch (e) {
      if (mounted) {
        _snack(
          'Could not get your location. ${e.toString().replaceFirst('Exception: ', '')}',
          error: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _locating = false;
        });
      }
    }
  }

  /// A labelled text input with inline validation, shared by every form.
  Widget textField({
    required String label,
    required TextEditingController controller,
    String? errorKey,
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboardType,
    String? hint,
    bool optional = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        minLines: maxLines > 1 ? 3 : 1,
        maxLength: maxLength,
        keyboardType: keyboardType,
        textCapitalization: TextCapitalization.sentences,
        style: AppTypography.body.copyWith(color: context.textPrimaryColor),
        decoration: InputDecoration(
          labelText: optional ? '$label (optional)' : label,
          hintText: hint,
          errorText: errorKey == null ? null : errors[errorKey],
          errorMaxLines: 3,
        ),
      ),
    );
  }

  Widget locationField() {
    final hasFix = latitude != null && longitude != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        textField(
          label: locationLabel,
          controller: locationController,
          errorKey: 'location',
          hint: 'Street, landmark, village or area',
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _locating ? null : _useLocation,
                icon: _locating
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(hasFix ? Icons.check_rounded : Icons.my_location_rounded),
                label: Text(hasFix ? 'GPS attached' : 'Use my GPS location'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              ),
              if (hasFix) ...[
                const SizedBox(width: AppSpacing.sm),
                TextButton(
                  onPressed: () => setState(() {
                    latitude = null;
                    longitude = null;
                  }),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: const Text('Remove'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: context.screenBackground,
        appBar: AppBar(title: Text(screenTitle), centerTitle: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final status = _record!.status;

    return Scaffold(
      backgroundColor: context.screenBackground,
      appBar: AppBar(title: Text(screenTitle), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SetuCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                accentBorderLeft: AppColors.accent,
                child: Row(
                  children: [
                    Icon(Icons.cloud_off_rounded, color: AppColors.accent, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Works offline. Your report is saved on this device and '
                        'sent when a route is available.',
                        style: AppTypography.caption.copyWith(color: context.textSecondaryColor),
                      ),
                    ),
                  ],
                ),
              ),
              if (status != ReportStatus.draft || widget.draftId != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Align(alignment: Alignment.centerLeft, child: ReportStatusChip(status: status)),
                if (_record!.lastError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text('Last attempt: ${_record!.lastError}',
                        style: AppTypography.caption.copyWith(color: AppColors.emergencyBright)),
                  ),
              ],
              const SizedBox(height: AppSpacing.lg),
              ...buildFields(context),
              const SizedBox(height: AppSpacing.sm),
              SetuButton(
                label: 'Submit report',
                icon: Icons.save_rounded,
                onPressed: _busy ? null : _submit,
                isLoading: _busy,
                size: SetuButtonSize.lg,
              ),
              const SizedBox(height: AppSpacing.sm),
              SetuButton(
                label: 'Save as draft',
                icon: Icons.edit_note_rounded,
                variant: SetuButtonVariant.outlined,
                onPressed: _busy ? null : _saveDraft,
                size: SetuButtonSize.lg,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
