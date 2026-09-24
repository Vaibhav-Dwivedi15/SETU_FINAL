import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_colors.dart';
import '../app_typography.dart';

enum SetuEmergencyTriggerStyle {
  tap,
  hold,
}

class SetuEmergencyButton extends StatefulWidget {
  final VoidCallback onTriggered;
  final SetuEmergencyTriggerStyle triggerStyle;
  final Duration holdDuration;
  final String? subtitle;

  const SetuEmergencyButton({
    super.key,
    required this.onTriggered,
    this.triggerStyle = SetuEmergencyTriggerStyle.tap,
    this.holdDuration = const Duration(seconds: 3),
    this.subtitle,
  });

  @override
  State<SetuEmergencyButton> createState() => _SetuEmergencyButtonState();
}

class _SetuEmergencyButtonState extends State<SetuEmergencyButton>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _holdController;
  bool _isHolding = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _holdController = AnimationController(
      vsync: this,
      duration: widget.holdDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_completed) {
          _fire();
        }
      });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _holdController.dispose();
    super.dispose();
  }

  void _fire() {
    _completed = true;
    HapticFeedback.heavyImpact();
    widget.onTriggered();
  }

  void _onTapDown() {
    if (widget.triggerStyle == SetuEmergencyTriggerStyle.hold) {
      _completed = false;
      setState(() => _isHolding = true);
      HapticFeedback.selectionClick();
      _holdController.forward(from: 0);
    }
  }

  void _onTapUp() {
    if (widget.triggerStyle == SetuEmergencyTriggerStyle.hold) {
      setState(() => _isHolding = false);
      if (!_completed) {
        _holdController.reverse();
      }
    }
  }

  void _onTapCancel() {
    if (widget.triggerStyle == SetuEmergencyTriggerStyle.hold) {
      setState(() => _isHolding = false);
      if (!_completed) {
        _holdController.reverse();
      }
    }
  }

  void _onTap() {
    if (widget.triggerStyle == SetuEmergencyTriggerStyle.tap) {
      HapticFeedback.heavyImpact();
      widget.onTriggered();
    }
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final isHold = widget.triggerStyle == SetuEmergencyTriggerStyle.hold;

    final subLabel = widget.subtitle ??
        (isHold ? 'HOLD 3 SECONDS' : 'TAP TO CONFIRM');

    return Semantics(
      button: true,
      label: 'Emergency SOS button',
      hint: isHold
          ? 'Press and hold for 3 seconds to trigger emergency distress signal'
          : 'Tap to trigger emergency distress signal',
      onTap: _fire,
      onLongPress: isHold ? _fire : null,
      child: Center(
        child: GestureDetector(
          onTapDown: (_) => _onTapDown(),
          onTapUp: (_) => _onTapUp(),
          onTapCancel: _onTapCancel,
          onTap: _onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedBuilder(
            animation: Listenable.merge([_pulseController, _holdController]),
            builder: (context, child) {
              final pulseValue = disableAnimations ? 0.0 : _pulseController.value;
              final ringSize = 190.0 + (pulseValue * 14.0);

              return SizedBox(
                width: 210,
                height: 210,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer subtle breathing ring
                    Container(
                      width: ringSize,
                      height: ringSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.emergency.withValues(
                          alpha: _isHolding ? 0.25 : 0.08 + (pulseValue * 0.08),
                        ),
                      ),
                    ),
                    // Hold progress indicator ring
                    if (isHold)
                      SizedBox(
                        width: 176,
                        height: 176,
                        child: CircularProgressIndicator(
                          value: _holdController.value,
                          strokeWidth: 4.5,
                          backgroundColor: AppColors.borderSubtle.withValues(alpha: 0.3),
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    // Main Tactile Button
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.emergencyGradient,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.emergency.withValues(
                              alpha: _isHolding ? 0.6 : 0.4,
                            ),
                            blurRadius: _isHolding ? 28 : 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.emergency_rounded,
                            size: 32,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'SOS',
                            style: AppTypography.sosButton,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              subLabel,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
