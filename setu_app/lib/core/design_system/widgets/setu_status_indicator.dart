import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_radius.dart';
import '../app_typography.dart';

enum SetuStatusType {
  online,
  meshActive,
  searching,
  relaying,
  delivered,
  failed,
  offline,
}

class SetuStatusIndicator extends StatelessWidget {
  final SetuStatusType status;
  final String? labelOverride;
  final bool showDot;

  const SetuStatusIndicator({
    super.key,
    required this.status,
    this.labelOverride,
    this.showDot = true,
  });

  ({Color color, Color containerColor, IconData icon, String defaultLabel}) get _spec {
    switch (status) {
      case SetuStatusType.online:
        return (
          color: AppColors.success,
          containerColor: AppColors.successContainer,
          icon: Icons.check_circle_outline_rounded,
          defaultLabel: 'Online · Network Ready',
        );
      case SetuStatusType.meshActive:
        return (
          color: AppColors.accent,
          containerColor: AppColors.offlineContainer,
          icon: Icons.hub_rounded,
          defaultLabel: 'Offline · Mesh Active',
        );
      case SetuStatusType.searching:
        return (
          color: AppColors.warning,
          containerColor: AppColors.warningContainer,
          icon: Icons.radar_rounded,
          defaultLabel: 'Searching for Peers...',
        );
      case SetuStatusType.relaying:
        return (
          color: AppColors.relay,
          containerColor: AppColors.offlineContainer,
          icon: Icons.sync_rounded,
          defaultLabel: 'Relaying Active',
        );
      case SetuStatusType.delivered:
        return (
          color: AppColors.success,
          containerColor: AppColors.successContainer,
          icon: Icons.done_all_rounded,
          defaultLabel: 'Delivered',
        );
      case SetuStatusType.failed:
        return (
          color: AppColors.emergency,
          containerColor: AppColors.emergencyContainer,
          icon: Icons.error_outline_rounded,
          defaultLabel: 'Failed',
        );
      case SetuStatusType.offline:
        return (
          color: AppColors.offline,
          containerColor: AppColors.offlineContainer,
          icon: Icons.cloud_off_rounded,
          defaultLabel: 'Offline · Standby',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = labelOverride ?? spec.defaultLabel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? spec.containerColor : spec.color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillRadius,
        border: Border.all(
          color: spec.color.withValues(alpha: isDark ? 0.35 : 0.25),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: spec.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ] else ...[
            Icon(spec.icon, size: 14, color: spec.color),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: AppTypography.metadata.copyWith(
              color: isDark ? AppColors.textPrimary : spec.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
