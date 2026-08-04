// =====================================================
// SETU Project
// Module : Onboarding / Mesh Permission Gate
// =====================================================
//
// Added Aug 4 2026 -- see mesh_permission_service.dart docstring for
// why this needs to exist. Shown once, right after login, before the
// stealth-mode / home redirect in app_router.dart. If the user already
// granted everything on a previous run, app_router.dart's redirect
// skips this screen entirely -- it's not shown on every launch.
//
// Aug 4 2026 dark-mode fix (two separate bugs found here):
// 1. Scaffold backgroundColor was hardcoded to AppColors.lightBackground
//    -- this screen never respected dark mode at all, unlike the rest
//    of the app which correctly uses Theme.of(context).scaffoldBackgroundColor.
// 2. The "permanently denied" banner uses emergencyContainer, a FIXED
//    light pink that never changes with theme -- its text was inheriting
//    theme-driven color (light in dark mode), making it invisible
//    against the fixed light pink box. Same root cause as the OTP
//    screen's demo banner bug. Fix: explicit dark text color on that
//    banner specifically, since its background is intentionally fixed.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/app_button.dart';
import 'package:setu_app/features/onboarding/data/services/mesh_permission_service.dart';

class PermissionGateScreen extends StatefulWidget {
  const PermissionGateScreen({super.key});

  @override
  State<PermissionGateScreen> createState() => _PermissionGateScreenState();
}

class _PermissionGateScreenState extends State<PermissionGateScreen> {
  final MeshPermissionService _permissionService = const MeshPermissionService();

  bool _isRequesting = false;
  bool _permanentlyDenied = false;

  Future<void> _requestPermissions() async {
    setState(() => _isRequesting = true);

    final stillMissing = await _permissionService.requestAll();
    final permanentlyDenied = await _permissionService.anyPermanentlyDenied();

    if (!mounted) return;

    if (stillMissing.isEmpty) {
      context.go('/');
      return;
    }

    setState(() {
      _isRequesting = false;
      _permanentlyDenied = permanentlyDenied;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.wifi_tethering, size: 64, color: AppColors.primary),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'SETU needs a few permissions',
                style: AppTypography.headline,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Bluetooth, Wi-Fi and location let your phone relay '
                'emergency messages for others nearby -- even with no '
                'signal. This only works if every nearby SETU phone '
                'has these on.',
                style: AppTypography.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              if (_permanentlyDenied) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.emergencyContainer,
                    borderRadius: AppRadius.mdRadius,
                  ),
                  child: Text(
                    'Some permissions were permanently denied. Open '
                    'settings to turn them on manually.',
                    style: AppTypography.body.copyWith(color: AppColors.neutral900),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'Open settings',
                  onPressed: () => _permissionService.openSettings(),
                ),
              ] else
                AppButton(
                  label: _isRequesting ? 'Requesting...' : 'Allow permissions',
                  onPressed: _isRequesting ? null : _requestPermissions,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Convenience used by app_router.dart's redirect chain.
Future<bool> hasMeshPermissions() => const MeshPermissionService().hasAll();
