import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';
import 'package:setu_app/core/widgets/theme_colors.dart';

import '../../data/models/emergency_plan.dart';
import '../../data/repositories/emergency_plan_repository.dart';

/// The family emergency plan: two contacts, a meeting point and notes,
/// stored only on this device. Collects nothing beyond that.
class EmergencyPlanScreen extends StatefulWidget {
  const EmergencyPlanScreen({super.key, this.repository});

  final EmergencyPlanRepository? repository;

  @override
  State<EmergencyPlanScreen> createState() => _EmergencyPlanScreenState();
}

class _EmergencyPlanScreenState extends State<EmergencyPlanScreen> {
  late final EmergencyPlanRepository _repository = widget.repository ?? EmergencyPlanRepository();
  final _primaryName = TextEditingController();
  final _primaryPhone = TextEditingController();
  final _secondaryName = TextEditingController();
  final _secondaryPhone = TextEditingController();
  final _meetingPoint = TextEditingController();
  final _notes = TextEditingController();

  bool _loading = true;
  bool _hasSavedPlan = false;
  Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final plan = await _repository.load();
    if (!mounted) return;
    _apply(plan);
    setState(() {
      _hasSavedPlan = !plan.isEmpty;
      _loading = false;
    });
  }

  void _apply(EmergencyPlan plan) {
    _primaryName.text = plan.primaryName;
    _primaryPhone.text = plan.primaryPhone;
    _secondaryName.text = plan.secondaryName;
    _secondaryPhone.text = plan.secondaryPhone;
    _meetingPoint.text = plan.meetingPoint;
    _notes.text = plan.notes;
  }

  EmergencyPlan _read() => EmergencyPlan(
        primaryName: _primaryName.text.trim(),
        primaryPhone: _primaryPhone.text.trim(),
        secondaryName: _secondaryName.text.trim(),
        secondaryPhone: _secondaryPhone.text.trim(),
        meetingPoint: _meetingPoint.text.trim(),
        notes: _notes.text.trim(),
      );

  Future<void> _save() async {
    final plan = _read();
    final errors = plan.validate();
    setState(() {
      _errors = errors;
    });
    if (errors.isNotEmpty) return;
    await _repository.save(plan);
    if (!mounted) return;
    setState(() {
      _hasSavedPlan = !plan.isEmpty;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Plan saved on this device.'), backgroundColor: AppColors.success),
    );
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear emergency plan?'),
        content: const Text('All plan details will be removed from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.clear();
    if (!mounted) return;
    _apply(EmergencyPlan.empty);
    setState(() {
      _hasSavedPlan = false;
      _errors = {};
    });
  }

  @override
  void dispose() {
    for (final c in [_primaryName, _primaryPhone, _secondaryName, _secondaryPhone, _meetingPoint, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(String label, TextEditingController c,
      {String? errorKey, TextInputType? type, int lines = 1, int? max}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextField(
        controller: c,
        keyboardType: type,
        maxLines: lines,
        minLines: lines > 1 ? 3 : 1,
        maxLength: max,
        textCapitalization: TextCapitalization.sentences,
        style: AppTypography.body.copyWith(color: context.textPrimaryColor),
        decoration: InputDecoration(
          labelText: label,
          errorText: errorKey == null ? null : _errors[errorKey],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.screenBackground,
      appBar: AppBar(title: const Text('Emergency plan'), centerTitle: true),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Stored only on this device. Share the plan with your family.',
                      style: AppTypography.caption.copyWith(color: context.textSecondaryColor),
                    ),
                    const SetuSectionHeader(title: 'Primary emergency contact'),
                    _field('Name', _primaryName),
                    _field('Phone number', _primaryPhone,
                        errorKey: 'primaryPhone', type: TextInputType.phone),
                    const SetuSectionHeader(title: 'Secondary emergency contact'),
                    _field('Name', _secondaryName),
                    _field('Phone number', _secondaryPhone,
                        errorKey: 'secondaryPhone', type: TextInputType.phone),
                    const SetuSectionHeader(title: 'Family meeting point'),
                    _field('Where will you meet?', _meetingPoint, max: 120),
                    const SetuSectionHeader(title: 'Important notes'),
                    _field('Notes', _notes, lines: 4, max: 300),
                    const SizedBox(height: AppSpacing.sm),
                    SetuButton(
                      label: _hasSavedPlan ? 'Update plan' : 'Save plan',
                      icon: Icons.save_rounded,
                      onPressed: _save,
                      size: SetuButtonSize.lg,
                    ),
                    if (_hasSavedPlan) ...[
                      const SizedBox(height: AppSpacing.sm),
                      SetuButton(
                        label: 'Clear plan',
                        icon: Icons.delete_outline_rounded,
                        variant: SetuButtonVariant.outlined,
                        onPressed: _clear,
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
