// =====================================================
// SETU Project
// Module : SOS Progress Overlay
// =====================================================
//
// Aug 5 2026: built to satisfy the product vision's explicit request
// for a "beautiful reassuring animation" during SOS transmission.
// Listens to SosRepository.progressStream. Purely a display layer --
// does NOT change what triggerSOS() actually does, only what the user
// sees while it happens.
//
// Aug 5 2026 update: added SosProgress.backendConfirmed (new state
// from the online-path awaited-upload fix in sos_repository.dart) --
// every enum value MUST have an entry here or the map lookup below
// throws a null-check error the first time that state fires.

import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/features/sos/data/repositories/sos_repository.dart';

class _ProgressStep {
  final IconData icon;
  final String message;
  const _ProgressStep(this.icon, this.message);
}

const _stepsByProgress = <SosProgress, _ProgressStep>{
  SosProgress.checkingNetwork: _ProgressStep(
    Icons.wifi_find_rounded,
    'Checking connection...',
  ),
  SosProgress.networkUnavailable: _ProgressStep(
    Icons.signal_wifi_off_rounded,
    'Network unavailable.',
  ),
  SosProgress.activatingMesh: _ProgressStep(
    Icons.hub_rounded,
    'Activating SETU Mesh...',
  ),
  SosProgress.searchingRelayDevices: _ProgressStep(
    Icons.radar_rounded,
    'Searching nearby relay devices...',
  ),
  SosProgress.forwarding: _ProgressStep(
    Icons.send_rounded,
    'Your emergency message is being forwarded.',
  ),
  SosProgress.onlineSending: _ProgressStep(
    Icons.wifi_rounded,
    'Connected — sending your alert...',
  ),
  SosProgress.backendConfirmed: _ProgressStep(
    Icons.cloud_done_rounded,
    'Backend confirmed — help is being notified.',
  ),
  SosProgress.notifyingContacts: _ProgressStep(
    Icons.contact_phone_rounded,
    'Notifying your emergency contacts...',
  ),
  SosProgress.delivered: _ProgressStep(
    Icons.check_circle_rounded,
    'Help is on the way.',
  ),
  SosProgress.failed: _ProgressStep(
    Icons.error_outline_rounded,
    'Something went wrong.',
  ),
};

class SosProgressOverlay extends StatefulWidget {
  const SosProgressOverlay({super.key});

  @override
  State<SosProgressOverlay> createState() => _SosProgressOverlayState();
}

class _SosProgressOverlayState extends State<SosProgressOverlay>
    with SingleTickerProviderStateMixin {
  SosProgress _current = SosProgress.checkingNetwork;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    SosRepository.progressStream.listen((progress) {
      if (!mounted) return;
      setState(() => _current = progress);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = _stepsByProgress[_current]!;
    final isFailed = _current == SosProgress.failed;
    final isDelivered = _current == SosProgress.delivered;
    final iconColor = isFailed
        ? AppColors.emergency
        : (isDelivered ? AppColors.success : AppColors.primary);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final animate = !isFailed && !isDelivered;
                      final scale = animate ? 1 + (_pulseController.value * 0.15) : 1.0;
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(step.icon, size: 48, color: iconColor),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: Text(
                      step.message,
                      key: ValueKey(_current),
                      style: AppTypography.headline,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (!isFailed && !isDelivered)
                    Text(
                      'Please keep the app open.',
                      style: AppTypography.caption.copyWith(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
