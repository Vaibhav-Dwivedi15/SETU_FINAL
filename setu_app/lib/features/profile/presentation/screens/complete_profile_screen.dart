// =====================================================
// SETU Project
// Module : Complete Your Profile (Block 31)
// Owner  : Sudheer
// =====================================================
//
// Shown once, right after OTP verification — skippable.
// Reachable again later from Settings > Profile if the person
// wants to fill it in afterward.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/app_button.dart';
import 'package:setu_app/features/settings/data/repositories/settings_repository.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _settingsRepository = SettingsRepository();
  final _bloodGroupController = TextEditingController();
  final _medicalNoteController = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final settings = await _settingsRepository.getSettings();
    if (!mounted) return;
    _bloodGroupController.text = settings.bloodGroup;
    _medicalNoteController.text = settings.medicalNote;
  }

  @override
  void dispose() {
    _bloodGroupController.dispose();
    _medicalNoteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    final settings = await _settingsRepository.getSettings();
    await _settingsRepository.saveSettings(
      settings.copyWith(
        bloodGroup: _bloodGroupController.text.trim(),
        medicalNote: _medicalNoteController.text.trim(),
      ),
    );

    if (!mounted) return;
    context.go('/');
  }

  void _skip() => context.go('/');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Your Profile'),
        actions: [
          TextButton(onPressed: _skip, child: const Text('Skip')),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This helps responders act fast if your device is ever '
                'found. Everything here is optional.',
                style: AppTypography.body.copyWith(color: AppColors.neutral500),
              ),

              const SizedBox(height: AppSpacing.xl),

              Text('Blood Group', style: AppTypography.subtitle),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _bloodGroupController,
                decoration: const InputDecoration(hintText: 'e.g. O+'),
              ),

              const SizedBox(height: AppSpacing.md),

              Text('Medical Note', style: AppTypography.subtitle),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _medicalNoteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Allergies, conditions, medications, etc.',
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              AppButton(
                label: _isSaving ? 'Saving...' : 'Save & Continue',
                onPressed: _isSaving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
