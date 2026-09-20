// =====================================================
// SETU Project
// Module : SOS / Countdown
// Owner  : Sudheer
// =====================================================
//
// Design System v1 pass. This is the moment right before
// SOS actually fires — the single most emergency-critical
// screen in the app — so unlike most of the UI (which is
// Primary Blue), this one deliberately uses the reserved
// Emergency Red gradient throughout. Circular progress ring
// + a light haptic tick each second, unchanged from before.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';

class CountdownWidget extends StatefulWidget {
  final VoidCallback onFinished;
  final VoidCallback onCancel;
  final int durationSeconds;

  const CountdownWidget({
    super.key,
    required this.onFinished,
    required this.onCancel,
    this.durationSeconds = 5,
  });

  @override
  State<CountdownWidget> createState() => _CountdownWidgetState();
}

class _CountdownWidgetState extends State<CountdownWidget> {
  late int seconds;
  late final int totalSeconds;
  Timer? timer;

  @override
  void initState() {
    super.initState();

    seconds = widget.durationSeconds;
    totalSeconds = widget.durationSeconds;

    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (seconds == 1) {
        t.cancel();
        HapticFeedback.heavyImpact();
        widget.onFinished();
      } else {
        HapticFeedback.lightImpact();
        setState(() {
          seconds--;
        });
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = seconds / totalSeconds;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.xlRadius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 56,
              width: 56,
              decoration: const BoxDecoration(
                gradient: AppColors.emergencyGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              "Sending SOS in",
              style: AppTypography.subtitle.copyWith(
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: 130,
              width: 130,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: 130,
                    width: 130,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 9,
                      backgroundColor: theme.brightness == Brightness.dark
                          ? Colors.white12
                          : AppColors.neutral100,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.emergency,
                      ),
                    ),
                  ),
                  Text(
                    "$seconds",
                    style: AppTypography.displayLarge.copyWith(
                      fontSize: 48,
                      color: AppColors.emergency,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(
                    color: AppColors.emergency,
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.mdRadius,
                  ),
                ),
                onPressed: () {
                  timer?.cancel();
                  widget.onCancel();
                },
                child: Text(
                  "Cancel",
                  style: AppTypography.bodyStrong.copyWith(
                    color: AppColors.emergency,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
