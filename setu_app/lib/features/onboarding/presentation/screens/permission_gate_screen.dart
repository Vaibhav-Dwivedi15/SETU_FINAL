// =====================================================
// SETU Project
// Module : Onboarding / Mesh Permission Gate
// =====================================================
//
// Added Aug 4 2026. Aug 5 2026: added radio-state checks (Bluetooth/
// Wi-Fi actually ON) after standard permission grants -- these run on
// EVERY Android version identically, unlike the runtime permission
// dialogs which only exist as a concept on certain API levels. This
// is what makes the gate screen's behavior consistent regardless of
// which Android version a future user's device happens to run.

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/app_button.dart';
import 'package:setu_app/core/services/connectivity_mesh_controller.dart';
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
  String? _radioWarning;

  Future<void> _requestPermissions() async {
    developer.log('Allow permissions button tapped', name: 'MeshPermission');
    setState(() {
      _isRequesting = true;
      _radioWarning = null;
    });

    final stillMissing = await _permissionService.requestAll();
    final permanentlyDenied = await _permissionService.anyPermanentlyDenied();

    developer.log(
      'After requestAll(): stillMissing=$stillMissing permanentlyDenied=$permanentlyDenied',
      name: 'MeshPermission',
    );

    if (!mounted) return;

    if (stillMissing.isNotEmpty) {
      developer.log(
        'Still missing ${stillMissing.length} permission(s) -- staying on gate screen',
        name: 'MeshPermission',
      );
      setState(() {
        _isRequesting = false;
        _permanentlyDenied = permanentlyDenied;
      });
      return;
    }

    // Aug 5 2026: standard permissions are all granted -- now check
    // the ACTUAL radio state, which behaves the same way regardless of
    // Android version. If Bluetooth is off, prompt the system "Turn on
    // Bluetooth?" dialog (available on every Android version SETU
    // supports). If the user declines, don't hard-block navigation --
    // the mesh simply won't discover peers until they turn it on
    // manually later, same as any BLE app.
    final bluetoothOn = await _permissionService.isBluetoothEnabled();
    if (!bluetoothOn) {
      developer.log('Bluetooth is off -- prompting to enable', name: 'MeshPermission');
      await _permissionService.promptEnableBluetooth();
    }

    final wifiOn = await _permissionService.isWifiEnabled();
    if (!mounted) return;

    if (!wifiOn) {
      // Wi-Fi can't be toggled programmatically on Android 10+ --
      // surface a clear message and a button to open system settings,
      // rather than silently proceeding with Wi-Fi off.
      setState(() {
        _isRequesting = false;
        _radioWarning = 'Wi-Fi is off. Turn it on for the best mesh range '
            '(Bluetooth alone still works, just at shorter range).';
      });
    }

    developer.log('Proceeding to home', name: 'MeshPermission');
    unawaited(ConnectivityMeshController.instance.enableAutoMode());
    context.go('/');
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
              if (_radioWarning != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.warningContainer,
                    borderRadius: AppRadius.mdRadius,
                  ),
                  child: Text(
                    _radioWarning!,
                    style: AppTypography.body.copyWith(color: AppColors.neutral900),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'Open Wi-Fi settings',
                  onPressed: () => _permissionService.openWifiSettings(),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
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
              ] else if (_radioWarning == null)
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
