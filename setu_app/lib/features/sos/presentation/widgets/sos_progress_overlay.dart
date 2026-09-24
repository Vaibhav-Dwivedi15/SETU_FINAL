// =====================================================
// SETU Project
// Module : SOS Progress Overlay (Emergency-First Redesign)
// =====================================================

import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/features/sos/data/repositories/sos_repository.dart';

class _ProgressStep {
  final IconData icon;
  final String title;
  final String details;
  const _ProgressStep(this.icon, this.title, this.details);
}

const _stepsByProgress = <SosProgress, _ProgressStep>{
  SosProgress.checkingNetwork: _ProgressStep(
    Icons.wifi_find_rounded,
    'Checking Connection...',
    'Assessing internet and cellular availability.',
  ),
  SosProgress.networkUnavailable: _ProgressStep(
    Icons.signal_wifi_off_rounded,
    'No Internet Connection',
    'Switching to offline mesh relay. Keep SETU open.',
  ),
  SosProgress.activatingMesh: _ProgressStep(
    Icons.hub_rounded,
    'Activating SETU Mesh...',
    'Broadcasting over Bluetooth Low Energy & Wi-Fi Aware.',
  ),
  SosProgress.searchingRelayDevices: _ProgressStep(
    Icons.radar_rounded,
    'Searching Nearby Devices...',
    'Looking for neighboring SETU phones to relay packet.',
  ),
  SosProgress.forwarding: _ProgressStep(
    Icons.send_rounded,
    'Relaying Emergency Signal...',
    'Your distress packet is being carried hop-by-hop.',
  ),
  SosProgress.onlineSending: _ProgressStep(
    Icons.wifi_rounded,
    'Transmitting Alert...',
    'Sending distress beacon directly to response center.',
  ),
  SosProgress.backendConfirmed: _ProgressStep(
    Icons.cloud_done_rounded,
    'Alert Confirmed',
    'Response operations has registered your distress beacon.',
  ),
  SosProgress.notifyingContacts: _ProgressStep(
    Icons.contact_phone_rounded,
    'Notifying Emergency Contacts...',
    'Sending emergency SMS with Google Maps location.',
  ),
  SosProgress.delivered: _ProgressStep(
    Icons.check_circle_rounded,
    'Help is On the Way',
    'Emergency alert successfully delivered to responders.',
  ),
  SosProgress.failed: _ProgressStep(
    Icons.error_outline_rounded,
    'Transmission Issue',
    'Ensure Bluetooth and Location permissions are enabled.',
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
      duration: const Duration(milliseconds: 1600),
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
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    final iconColor = isFailed
        ? AppColors.emergency
        : (isDelivered ? AppColors.success : AppColors.accent);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bgApp,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final animate = !isFailed && !isDelivered && !disableAnimations;
                      final scale = animate ? 1.0 + (_pulseController.value * 0.12) : 1.0;
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: Container(
                      width: 108,
                      height: 108,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: iconColor.withValues(alpha: 0.35),
                          width: 2,
                        ),
                      ),
                      child: Icon(step.icon, size: 52, color: iconColor),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xxl),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Column(
                      key: ValueKey(_current),
                      children: [
                        Text(
                          step.title,
                          style: AppTypography.headline.copyWith(
                            color: AppColors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: Text(
                            step.details,
                            style: AppTypography.body.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  if (!isFailed && !isDelivered)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface,
                        borderRadius: AppRadius.pillRadius,
                        border: Border.all(color: AppColors.borderSubtle, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Keep app open — mesh relay active',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textDim,
                            ),
                          ),
                        ],
                      ),
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
