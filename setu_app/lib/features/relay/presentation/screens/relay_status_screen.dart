// =====================================================
// SETU Project
// Module : Relay Status Screen (Redesign)
// =====================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';
import 'package:setu_app/core/services/connectivity_mesh_controller.dart';
import 'package:setu_app/features/relay/presentation/widgets/relay_trace_indicator.dart';
import 'package:setu_app/mesh/services/mesh_metrics.dart';

class RelayStatusScreen extends StatefulWidget {
  const RelayStatusScreen({super.key});

  @override
  State<RelayStatusScreen> createState() => _RelayStatusScreenState();
}

class _RelayStatusScreenState extends State<RelayStatusScreen> {
  StreamSubscription<void>? _metricsSub;
  StreamSubscription<NetworkStatus>? _statusSub;
  NetworkStatus _networkStatus = ConnectivityMeshController.instance.currentStatus;

  @override
  void initState() {
    super.initState();
    _metricsSub = MeshMetrics.instance.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _statusSub = ConnectivityMeshController.instance.statusStream.listen((status) {
      if (mounted) setState(() => _networkStatus = status);
    });
  }

  @override
  void dispose() {
    _metricsSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  Widget _metricCard({
    required IconData icon,
    required Color color,
    required String label,
    required int value,
    required String sublabel,
    required bool isDark,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SetuCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        accentBorderLeft: color,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: AppRadius.smRadius,
                  ),
                  child: Icon(icon, color: color, size: 22),
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
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sublabel,
                        style: AppTypography.caption.copyWith(
                          color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$value',
                  style: AppTypography.headline.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (trailing != null) ...[
              const SizedBox(height: AppSpacing.sm),
              trailing,
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metrics = MeshMetrics.instance;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOffline = _networkStatus == NetworkStatus.offline;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgApp : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Mesh Relay Diagnostics'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Permanent Relay Log',
            onPressed: () => context.push('/relay/history'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // Mesh Node Role Banner
            SetuCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              backgroundColor: isDark ? AppColors.bgSurfaceAlt : AppColors.lightSurface,
              accentBorderLeft: AppColors.relay,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.hub_rounded, color: AppColors.relay, size: 24),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Decentralized Emergency Node',
                          style: AppTypography.cardTitle.copyWith(
                            color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Even with complete telecommunications blackout, this phone automatically relays authenticated emergency distress packets for people in your vicinity.',
                    style: AppTypography.body.copyWith(
                      color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SetuStatusIndicator(
                    status: isOffline ? SetuStatusType.meshActive : SetuStatusType.online,
                    labelOverride: isOffline
                        ? 'Offline · Hop-by-Hop Relaying Active'
                        : 'Online · Serving as Exit Gateway',
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            const SetuSectionHeader(
              title: 'Live Session Metrics',
              subtitle: 'Packet counts since current application launch',
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
            ),

            _metricCard(
              icon: Icons.send_rounded,
              color: AppColors.emergency,
              label: 'Distress Beacons Sent',
              value: metrics.sent,
              sublabel: 'Packets originated by you',
              isDark: isDark,
            ),

            _metricCard(
              icon: Icons.call_received_rounded,
              color: AppColors.accent,
              label: 'Packets Received',
              value: metrics.received,
              sublabel: 'Picked up from nearby mesh nodes',
              isDark: isDark,
            ),

            _metricCard(
              icon: Icons.sync_rounded,
              color: AppColors.relay,
              label: 'Packets Relayed',
              value: metrics.relayed,
              sublabel: 'Carried forward on behalf of others',
              isDark: isDark,
              trailing: RelayTraceIndicator(relayedCount: metrics.relayed),
            ),

            _metricCard(
              icon: Icons.cloud_upload_rounded,
              color: AppColors.success,
              label: 'Gateways Uploaded',
              value: metrics.uploaded,
              sublabel: 'Delivered to central responders as exit node',
              isDark: isDark,
            ),

            _metricCard(
              icon: Icons.block_rounded,
              color: isDark ? AppColors.textDim : AppColors.lightTextDim,
              label: 'Filtered / Dropped',
              value: metrics.dropped,
              sublabel: 'Duplicates, replays, or expired TTL',
              isDark: isDark,
            ),

            const SizedBox(height: AppSpacing.md),

            SetuButton(
              label: 'VIEW PERSISTENT RELAY HISTORY',
              icon: Icons.history_rounded,
              onPressed: () => context.push('/relay/history'),
              variant: SetuButtonVariant.secondary,
              size: SetuButtonSize.md,
            ),
          ],
        ),
      ),
    );
  }
}
