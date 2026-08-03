// =====================================================
// SETU Project
// Module : SOS / Tap-to-Confirm Trigger
// Owner  : Sudheer
// =====================================================
//
// Alternative to HoldToConfirmSosButton, chosen via Settings
// > SOS Trigger Style. A single tap navigates straight to
// ConfirmationScreen, where the existing mode/category
// selection + countdown dialog (using the SOS Countdown
// setting) is the "wait and cancel" safety window instead of
// a physical hold gesture.
//
// Design System v1 pass: emergency-red gradient + reserved
// sosButton type style (the one screen in the app allowed to
// break from the standard type scale, per the design brief).
// The looping "radar ping" pulse behind the button is purely
// decorative — no state change until actually tapped.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';

class TapToConfirmSosButton extends StatefulWidget {
  final VoidCallback onConfirmed;

  const TapToConfirmSosButton({super.key, required this.onConfirmed});

  @override
  State<TapToConfirmSosButton> createState() => _TapToConfirmSosButtonState();
}

class _TapToConfirmSosButtonState extends State<TapToConfirmSosButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 92,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final t = _pulseController.value;
              return Opacity(
                opacity: (1 - t) * 0.35,
                child: Transform.scale(
                  scale: 1 + (t * 0.12),
                  child: Container(
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.emergency,
                      borderRadius: AppRadius.lgRadius,
                    ),
                  ),
                ),
              );
            },
          ),
          SizedBox(
            width: double.infinity,
            height: 80,
            child: Material(
              borderRadius: AppRadius.lgRadius,
              elevation: 6,
              shadowColor: AppColors.emergency.withValues(alpha: 0.5),
              child: InkWell(
                borderRadius: AppRadius.lgRadius,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  widget.onConfirmed();
                },
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: AppColors.emergencyGradient,
                    borderRadius: AppRadius.lgRadius,
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          "SEND SOS",
                          style: AppTypography.sosButton.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
