// =====================================================
// SETU Project
// Module : SOS / Hold-to-Confirm Trigger
// Owner  : Sudheer
// =====================================================
//
// Implements the original spec item: "SOS trigger screen —
// large touch target, high contrast, haptic feedback,
// 3-second hold-to-confirm (avoid accidental triggers under
// panic)."
//
// Releasing before completion cancels and resets — nothing
// fires. On completion this only calls onConfirmed(); it does
// NOT send the SOS itself. The existing mode/category
// selection + countdown-dialog flow on ConfirmationScreen
// still runs after this, as a second layer of confirmation.
//
// ACCESSIBILITY NOTE: TalkBack/VoiceOver users can't perform
// a sustained 3-second physical hold reliably. Semantics below
// exposes a "long press" custom action that fires immediately
// on invocation.
//
// Design System v1 pass: emergency-red gradient (reserved
// color, correct here since this literally is the SOS-firing
// gesture) + reserved sosButton type style.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';

class HoldToConfirmSosButton extends StatefulWidget {
  final VoidCallback onConfirmed;
  final Duration duration;

  const HoldToConfirmSosButton({
    super.key,
    required this.onConfirmed,
    this.duration = const Duration(seconds: 3),
  });

  @override
  State<HoldToConfirmSosButton> createState() =>
      _HoldToConfirmSosButtonState();
}

class _HoldToConfirmSosButtonState extends State<HoldToConfirmSosButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _completed = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: widget.duration);

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_completed) {
        _fire();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _fire() {
    _completed = true;
    HapticFeedback.heavyImpact();
    widget.onConfirmed();
  }

  void _onPressStart() {
    _completed = false;
    HapticFeedback.selectionClick();
    _controller.forward(from: 0);
  }

  void _onPressEnd() {
    if (!_completed) {
      _controller.reverse();
    }
  }

  void _onAccessibilityLongPress() {
    if (!_completed) {
      _fire();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          'Hold for ${widget.duration.inSeconds} seconds to send emergency S O S',
      onLongPress: _onAccessibilityLongPress,
      child: GestureDetector(
        onLongPressStart: (_) => _onPressStart(),
        onLongPressEnd: (_) => _onPressEnd(),
        onLongPressCancel: _onPressEnd,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final progress = _controller.value;

            return Container(
              width: double.infinity,
              height: 80,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                gradient: AppColors.emergencyGradient,
                borderRadius: AppRadius.lgRadius,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.emergency.withValues(alpha: 0.5),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: Container(color: Colors.white24),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        progress == 0
                            ? 'HOLD FOR SOS (${widget.duration.inSeconds}s)'
                            : 'KEEP HOLDING...',
                        style: AppTypography.sosButton.copyWith(
                          color: Colors.white,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
