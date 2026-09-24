import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_radius.dart';
import '../app_typography.dart';

enum SetuIncidentState {
  pending,
  relaying,
  stored,
  delivered,
  failed,
  resolved,
}

class SetuIncidentStatusBadge extends StatelessWidget {
  final SetuIncidentState state;
  final String? customLabel;

  const SetuIncidentStatusBadge({
    super.key,
    required this.state,
    this.customLabel,
  });

  factory SetuIncidentStatusBadge.fromString(String rawStatus) {
    final lower = rawStatus.toLowerCase().trim();
    if (lower.contains('deliver') || lower.contains('sent') || lower.contains('ack')) {
      return const SetuIncidentStatusBadge(state: SetuIncidentState.delivered);
    } else if (lower.contains('relay')) {
      return const SetuIncidentStatusBadge(state: SetuIncidentState.relaying);
    } else if (lower.contains('stor') || lower.contains('queue')) {
      return const SetuIncidentStatusBadge(state: SetuIncidentState.stored);
    } else if (lower.contains('fail') || lower.contains('error')) {
      return const SetuIncidentStatusBadge(state: SetuIncidentState.failed);
    } else if (lower.contains('resolv') || lower.contains('close')) {
      return const SetuIncidentStatusBadge(state: SetuIncidentState.resolved);
    }
    return const SetuIncidentStatusBadge(state: SetuIncidentState.pending);
  }

  ({Color color, Color containerColor, String label, IconData icon}) get _spec {
    switch (state) {
      case SetuIncidentState.pending:
        return (
          color: AppColors.warning,
          containerColor: AppColors.warningContainer,
          label: 'PENDING',
          icon: Icons.hourglass_top_rounded,
        );
      case SetuIncidentState.relaying:
        return (
          color: AppColors.relay,
          containerColor: AppColors.offlineContainer,
          label: 'RELAYING',
          icon: Icons.sync_rounded,
        );
      case SetuIncidentState.stored:
        return (
          color: AppColors.accent,
          containerColor: AppColors.offlineContainer,
          label: 'STORED IN MESH',
          icon: Icons.inventory_2_outlined,
        );
      case SetuIncidentState.delivered:
        return (
          color: AppColors.success,
          containerColor: AppColors.successContainer,
          label: 'DELIVERED',
          icon: Icons.check_circle_rounded,
        );
      case SetuIncidentState.failed:
        return (
          color: AppColors.emergency,
          containerColor: AppColors.emergencyContainer,
          label: 'FAILED',
          icon: Icons.cancel_rounded,
        );
      case SetuIncidentState.resolved:
        return (
          color: AppColors.textSecondary,
          containerColor: AppColors.bgSurfaceAlt,
          label: 'RESOLVED',
          icon: Icons.task_alt_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final spec = _spec;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? spec.containerColor : spec.color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillRadius,
        border: Border.all(
          color: spec.color.withValues(alpha: isDark ? 0.4 : 0.25),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(spec.icon, size: 12, color: spec.color),
          const SizedBox(width: 4),
          Text(
            customLabel ?? spec.label,
            style: AppTypography.metadata.copyWith(
              color: isDark ? AppColors.textPrimary : spec.color,
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
