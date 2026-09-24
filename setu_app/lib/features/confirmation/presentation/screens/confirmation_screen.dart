// =====================================================
// SETU Project
// Module : Confirmation / Alert Mode Selection (Redesign)
// =====================================================

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';

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
    Navigator.pop(context); // Close countdown dialog

    setState(() {
      _isSending = true;
    });

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
      Navigator.pop(context); // Pop progress overlay

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Emergency SOS Sent Successfully"),
          backgroundColor: AppColors.success,
        ),
      );

      Navigator.pop(context); // Return to home
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Pop progress overlay on failure

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final selectedBg = isDark
        ? AppColors.bgSurfaceAlt
        : AppColors.lightBackground;
    final unselectedBg = isDark ? AppColors.bgSurface : AppColors.lightSurface;
    final borderColor = selected
        ? AppColors.accent
        : (isDark ? AppColors.borderSubtle : AppColors.lightBorder);

    return SetuCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      backgroundColor: selected ? selectedBg : unselectedBg,
      borderColor: borderColor,
      accentBorderLeft: selected ? AppColors.accent : null,
      onTap: () {
        setState(() {
          _selectedMode = mode;
        });
      },
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.18)
                  : (isDark ? AppColors.bgInput : AppColors.lightBackground),
              borderRadius: AppRadius.smRadius,
            ),
            child: Icon(
              icon,
              color: selected
                  ? AppColors.accent
                  : (isDark ? AppColors.textSecondary : AppColors.lightTextSecondary),
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.cardTitle.copyWith(
                    color: isDark
                        ? AppColors.textPrimary
                        : AppColors.lightTextPrimary,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.caption.copyWith(
                    color: isDark
                        ? AppColors.textSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (selected)
            const Icon(Icons.check_circle_rounded, color: AppColors.accent, size: 22),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgApp : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text("Confirm SOS Alert"),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Notice banner
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.emergencyContainer : const Color(0xFFFEE2E2),
                  borderRadius: AppRadius.mdRadius,
                  border: Border.all(
                    color: AppColors.emergency.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.emergency,
                      size: 22,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Select recipient scope and emergency category before sending distress packet.',
                        style: AppTypography.caption.copyWith(
                          color: isDark
                              ? AppColors.textPrimary
                              : AppColors.lightTextPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              const SetuSectionHeader(
                title: 'Broadcast Scope',
                subtitle: 'Who will receive this emergency signal',
                padding: EdgeInsets.only(bottom: AppSpacing.sm),
              ),

              _modeCard(
                mode: AlertMode.private,
                icon: Icons.lock_outline_rounded,
                title: "Private SOS (Direct Relays)",
                subtitle: "Emergency contacts & central responders via mesh",
              ),

              const SizedBox(height: AppSpacing.sm),

              _modeCard(
                mode: AlertMode.public,
                icon: Icons.public_rounded,
                title: "Public SOS (Broadcast)",
                subtitle: "Nearby SETU devices & emergency contacts",
              ),

              const SizedBox(height: AppSpacing.lg),

              const SetuSectionHeader(
                title: 'Emergency Category',
                subtitle: 'Helps responders prioritize necessary equipment',
                padding: EdgeInsets.only(bottom: AppSpacing.sm),
              ),

              EmergencyCategorySelector(
                selected: _selectedCategory,
                onChanged: (category) {
                  setState(() {
                    _selectedCategory = category;
                  });
                },
              ),

              const SizedBox(height: AppSpacing.xl),

              SetuButton(
                label: _isSending ? "Transmitting..." : "DISPATCH SOS BEACON",
                icon: Icons.emergency_rounded,
                onPressed: _isSending ? null : _startCountdown,
                variant: SetuButtonVariant.emergency,
                isLoading: _isSending,
                size: SetuButtonSize.lg,
              ),

              const SizedBox(height: AppSpacing.sm),

              Center(
                child: Text(
                  'A $_countdownSeconds-second countdown will start before transmission.',
                  style: AppTypography.caption.copyWith(
                    color: isDark ? AppColors.textDim : AppColors.lightTextDim,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
