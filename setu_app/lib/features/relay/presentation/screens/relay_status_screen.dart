// =====================================================
// SETU Project
// Module : Relay Status Screen
// =====================================================
//
// Aug 6 2026: the "Relayed" metric card now also shows a RelayTrace
// node-chain visualization (see relay_trace_indicator.dart) below the
// count -- mirrors the dashboard's signature Relay Trace component so
// both products share one visual language for "this device's actual
// mesh relay activity" instead of it just being a plain number here
// and a chain-of-nodes there.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_elevation.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/status_chip.dart';
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
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: AppRadius.lgRadius,
        boxShadow: Theme.of(context).brightness == Brightness.dark
            ? null
            : AppElevation.level1,
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: Theme.of(context).dividerColor)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: AppRadius.mdRadius,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTypography.subtitle),
                    const SizedBox(height: 2),
                    Text(
                      sublabel,
                      style: AppTypography.caption.copyWith(color: AppColors.neutral500),
                    ),
                  ],
                ),
              ),
              Text(
                '$value',
                style: AppTypography.headline.copyWith(color: color),
              ),
            ],
          ),
          if (trailing != null) ...[
            const SizedBox(height: AppSpacing.sm),
            trailing,
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metrics = MeshMetrics.instance;
    final isOffline = _networkStatus == NetworkStatus.offline;

    return Scaffold(
      appBar: AppBar(title: const Text('Relay Status')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: AppRadius.xlRadius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.hub, color: Colors.white, size: 28),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Your phone is part of the mesh',
                        style: AppTypography.subtitle.copyWith(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Even with no internet, your device helps carry emergency '
                  'messages for people nearby.',
                  style: AppTypography.body.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: AppSpacing.md),
                StatusChip(
                  kind: isOffline ? StatusChipKind.meshActive : StatusChipKind.connected,
                  labelOverride: isOffline ? 'Offline · Relaying for others' : 'Online · Can upload',
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          Text('THIS DEVICE\'S ACTIVITY',
              style: AppTypography.label.copyWith(color: AppColors.neutral500)),
          const SizedBox(height: AppSpacing.sm),

          _metricCard(
            icon: Icons.send,
            color: AppColors.emergency,
            label: 'Sent',
            value: metrics.sent,
            sublabel: 'Your own SOS packets originated',
          ),
          const SizedBox(height: AppSpacing.sm),
          _metricCard(
            icon: Icons.call_received,
            color: AppColors.primary,
            label: 'Received',
            value: metrics.received,
            sublabel: 'Packets picked up from nearby devices',
          ),
          const SizedBox(height: AppSpacing.sm),
          _metricCard(
            icon: Icons.sync,
            color: AppColors.info,
            label: 'Relayed',
            value: metrics.relayed,
            sublabel: 'Carried forward for someone else',
            trailing: RelayTraceIndicator(relayedCount: metrics.relayed),
          ),
          const SizedBox(height: AppSpacing.sm),
          _metricCard(
            icon: Icons.cloud_upload,
            color: AppColors.success,
            label: 'Uploaded',
            value: metrics.uploaded,
            sublabel: 'Delivered to the backend as exit node',
          ),
          const SizedBox(height: AppSpacing.sm),
          _metricCard(
            icon: Icons.block,
            color: AppColors.neutral500,
            label: 'Dropped',
            value: metrics.dropped,
            sublabel: 'Duplicates or invalid (correctly filtered)',
          ),

          const SizedBox(height: AppSpacing.lg),
          Text(
            'These numbers update live as your device participates in the '
            'mesh. A high "Relayed" count means you\'ve helped others reach '
            'help.',
            style: AppTypography.caption.copyWith(color: AppColors.neutral500),
          ),
        ],
      ),
    );
  }
}
