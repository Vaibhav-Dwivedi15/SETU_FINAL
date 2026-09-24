// =====================================================
// SETU Project
// Module : Readiness Check Screen (Redesign)
// =====================================================

import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';

import '../../data/models/readiness_status.dart';
import '../../data/repositories/readiness_repository.dart';

class ReadinessCheckScreen extends StatefulWidget {
  const ReadinessCheckScreen({super.key});

  @override
  State<ReadinessCheckScreen> createState() => _ReadinessCheckScreenState();
}

class _ReadinessCheckScreenState extends State<ReadinessCheckScreen> {
  final ReadinessRepository _repository = const ReadinessRepository();
  ReadinessStatus? _status;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _runCheck();
  }

  Future<void> _runCheck() async {
    setState(() => _checking = true);
    final status = await _repository.check();
    if (!mounted) return;
    setState(() {
      _status = status;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgApp : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Device Readiness Diagnostic'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _checking ? null : _runCheck,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Re-run Diagnostic',
          ),
        ],
      ),
      body: _checking || status == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _runCheck,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  _buildOverallBanner(status.ready, isDark),
                  const SizedBox(height: AppSpacing.lg),
                  const SetuSectionHeader(
                    title: 'Hardware & Radios',
                    subtitle: 'Requirements for off-grid hop-by-hop relaying',
                    padding: EdgeInsets.only(bottom: AppSpacing.sm),
                  ),
                  _buildCheckCard(
                    icon: Icons.security_rounded,
                    label: 'Emergency Permissions',
                    ok: status.permissionsGranted,
                    detail: status.permissionsGranted
                        ? 'Bluetooth and Location permissions active'
                        : 'Permissions missing — open Settings to allow relaying',
                    isDark: isDark,
                  ),
                  _buildCheckCard(
                    icon: Icons.bluetooth_rounded,
                    label: 'Bluetooth Radio',
                    ok: status.bluetoothEnabled,
                    detail: status.bluetoothEnabled
                        ? 'Enabled — ready to discover nearby peers'
                        : 'Disabled — turn on Bluetooth for local mesh networking',
                    isDark: isDark,
                  ),
                  _buildCheckCard(
                    icon: Icons.wifi_rounded,
                    label: 'Wi-Fi Adapter',
                    ok: status.wifiEnabled,
                    detail: status.wifiEnabled
                        ? 'Enabled — high-bandwidth Wi-Fi Direct links available'
                        : 'Disabled — turn on Wi-Fi for multi-peer clusters',
                    isDark: isDark,
                  ),
                  _buildCheckCard(
                    icon: Icons.hub_rounded,
                    label: 'Active Mesh Peers',
                    ok: true,
                    neutral: true,
                    detail: status.connectedPeers == 0
                        ? 'No devices nearby right now (normal if isolated)'
                        : '${status.connectedPeers} nearby SETU relay device(s) active',
                    isDark: isDark,
                  ),
                  _buildCheckCard(
                    icon: Icons.battery_charging_full_rounded,
                    label: 'Power Budget',
                    ok: status.batteryLevel > 20 || status.batteryLevel == 0,
                    detail: status.batteryLevel > 0
                        ? '${status.batteryLevel}% remaining'
                        : 'Battery level reading unavailable',
                    isDark: isDark,
                  ),
                  if (status.problems.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const SetuSectionHeader(
                      title: 'Action Items',
                      subtitle: 'Resolve these issues to enable full mesh coverage',
                      padding: EdgeInsets.only(bottom: AppSpacing.sm),
                    ),
                    SetuCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      backgroundColor: isDark
                          ? AppColors.emergencyContainer
                          : const Color(0xFFFEE2E2),
                      borderColor: AppColors.emergency.withValues(alpha: 0.3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: status.problems
                            .map(
                              (problem) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('• ', style: TextStyle(color: AppColors.emergency, fontWeight: FontWeight.bold)),
                                    Expanded(
                                      child: Text(
                                        problem,
                                        style: AppTypography.body.copyWith(
                                          color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildOverallBanner(bool ready, bool isDark) {
    final color = ready ? AppColors.success : AppColors.warning;
    final containerColor = ready
        ? (isDark ? AppColors.successContainer : const Color(0xFFDCFCE7))
        : (isDark ? AppColors.warningContainer : const Color(0xFFFEF3C7));

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: AppRadius.mdRadius,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            ready ? Icons.verified_rounded : Icons.warning_amber_rounded,
            color: color,
            size: 28,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ready
                      ? "Device Ready for Off-Grid Relay"
                      : "Device Partially Configured",
                  style: AppTypography.cardTitle.copyWith(
                    color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ready
                      ? "Bluetooth, Wi-Fi, and permissions are optimal for emergency mesh communications."
                      : "Some features are restricted. Review items below for full preparedness.",
                  style: AppTypography.caption.copyWith(
                    color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckCard({
    required IconData icon,
    required String label,
    required bool ok,
    required String detail,
    required bool isDark,
    bool neutral = false,
  }) {
    final statusColor = neutral
        ? AppColors.accent
        : (ok ? AppColors.success : AppColors.emergency);

    final statusIcon = neutral
        ? Icons.info_outline_rounded
        : (ok ? Icons.check_circle_rounded : Icons.cancel_rounded);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: SetuCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: AppRadius.smRadius,
              ),
              child: Icon(icon, size: 20, color: statusColor),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.cardTitle.copyWith(
                      color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: AppTypography.caption.copyWith(
                      color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(statusIcon, color: statusColor, size: 20),
          ],
        ),
      ),
    );
  }
}
