// =====================================================
// SETU Project
// Module : Confirmation / Alert Mode Selection
// Owner  : Sudheer
// =====================================================
//
// Design System v1 pass. Color semantics: mode selection is
// a *choice*, not the alarm itself, so it stays in Primary
// Blue (trust). The CONTINUE button is the entry point into
// the actual SOS-firing flow, so it uses the Emergency
// (reserved red) button variant — the one visual "this is
// serious" cue on this screen, matching the design brief's
// "red should be rare and mean something" rule.
//
// Aug 5 2026: _triggerSOS() now pushes SosProgressOverlay right
// before calling SosRepository.triggerSOS(), and pops it right after
// -- this is the "beautiful reassuring animation" from the product
// vision (network check -> mesh activation -> relay search ->
// forwarding, or the shorter online-path sequence). The overlay is
// purely a display layer reading SosRepository.progressStream; the
// actual triggerSOS() call sequence below is UNCHANGED from before.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/app_button.dart';

import 'package:setu_app/features/sos/data/models/alert_mode.dart';
import 'package:setu_app/features/sos/data/models/emergency_category.dart';
import 'package:setu_app/features/sos/data/repositories/sos_repository.dart';
import 'package:setu_app/features/sos/presentation/widgets/countdown_widget.dart';
import 'package:setu_app/features/sos/presentation/widgets/emergency_category_selector.dart';
import 'package:setu_app/features/sos/presentation/widgets/sos_progress_overlay.dart';
import 'package:setu_app/features/settings/data/repositories/settings_repository.dart';

class ConfirmationScreen extends StatefulWidget {
  const ConfirmationScreen({super.key});

  @override
  State<ConfirmationScreen> createState() => _ConfirmationScreenState();
}

class _ConfirmationScreenState extends State<ConfirmationScreen> {
  final SosRepository _sosRepository = SosRepository();
  final SettingsRepository _settingsRepository = SettingsRepository();

  bool _isSending = false;

  AlertMode _selectedMode = AlertMode.private;

  // Still NOT wired into EmergencyPacket/mesh packet fields —
  // only changes the SMS message text (see emergency_category.dart).
  EmergencyCategory _selectedCategory = EmergencyCategory.generalSos;

  int _countdownSeconds = 5;

  @override
  void initState() {
    super.initState();
    _loadCountdownSetting();
  }

  Future<void> _loadCountdownSetting() async {
    final settings = await _settingsRepository.getSettings();
    if (!mounted) return;
    setState(() {
      _countdownSeconds = settings.sosCountdown;
    });
  }

  Future<void> _triggerSOS() async {
    Navigator.pop(context);

    setState(() {
      _isSending = true;
    });

    // Aug 5 2026: push the reassuring progress overlay right before
    // starting the actual SOS. Not awaited -- it stays on screen
    // reacting to SosRepository.progressStream until explicitly popped
    // below, regardless of how long triggerSOS() takes.
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SosProgressOverlay()),
      ),
    );

    try {
      await _sosRepository.triggerSOS(
        alertMode: _selectedMode,
        category: _selectedCategory,
      );

      if (!mounted) return;

      // Pop the progress overlay now that triggerSOS has resolved.
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("SOS Sent Successfully"),
          backgroundColor: AppColors.success,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      // Pop the progress overlay on failure too -- SosRepository already
      // emits SosProgress.failed before this catch runs, so the overlay
      // briefly shows the failure state before this removes it.
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.emergency,
          content: Text(e.toString().replaceFirst("Exception: ", "")),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  void _startCountdown() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CountdownWidget(
        durationSeconds: _countdownSeconds,
        onFinished: _triggerSOS,
        onCancel: () {
          Navigator.pop(context);
        },
      ),
    );
  }

  Widget _modeCard({
    required AlertMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _selectedMode == mode;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: selected
            ? (isDark
                ? AppColors.primary.withValues(alpha: 0.22)
                : AppColors.primaryContainer)
            : theme.cardColor,
        borderRadius: AppRadius.lgRadius,
        border: Border.all(
          color: selected ? AppColors.primary : theme.dividerColor,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.lgRadius,
        child: InkWell(
          borderRadius: AppRadius.lgRadius,
          onTap: () {
            setState(() {
              _selectedMode = mode;
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  height: 44,
                  width: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTypography.subtitle),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTypography.caption.copyWith(
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle, color: AppColors.success),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Choose Alert Mode")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _modeCard(
              mode: AlertMode.private,
              icon: Icons.lock,
              title: "Private SOS",
              subtitle: "Emergency Contacts + Government (Future Integration)",
            ),

            const SizedBox(height: AppSpacing.md),

            _modeCard(
              mode: AlertMode.public,
              icon: Icons.public,
              title: "Public SOS",
              subtitle:
                  "Emergency Contacts + Nearby Users + Government (Future)",
            ),

            const SizedBox(height: AppSpacing.lg),

            Text("What's happening?", style: AppTypography.subtitle),
            const SizedBox(height: AppSpacing.xs),
            Text(
              "This customizes the message sent to your contacts.",
              style: AppTypography.caption.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            EmergencyCategorySelector(
              selected: _selectedCategory,
              onChanged: (category) {
                setState(() {
                  _selectedCategory = category;
                });
              },
            ),

            const SizedBox(height: AppSpacing.xl),

            AppButton(
              label: _isSending ? "Sending..." : "Continue",
              icon: _isSending ? null : Icons.arrow_forward,
              onPressed: _isSending ? null : _startCountdown,
              variant: AppButtonVariant.emergency,
            ),
          ],
        ),
      ),
    );
  }
}
