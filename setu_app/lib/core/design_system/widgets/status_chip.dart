// =====================================================
// SETU Design System v1.0
// Module : StatusChip
// Owner  : Sudheer
// =====================================================
//
// Every "state" in the app (mesh connection, relay progress,
// delivery, volunteer response) should render through this
// component — not raw Text. Covers every state named in the
// design brief: Mesh Active, Offline, Connected, Relaying,
// Uploading, Delivered, Volunteer Responding, Government
// Connected — plus generic success/warning/danger/neutral for
// anything else (e.g. History's Delivered/Failed).

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_radius.dart';
import '../app_typography.dart';

enum StatusChipKind {
  meshActive,
  offline,
  connected,
  relaying,
  uploading,
  delivered,
  volunteerResponding,
  governmentConnected,
  success,
  warning,
  danger,
  neutral,
}

class StatusChip extends StatelessWidget {
  final StatusChipKind kind;
  final String? labelOverride;

  const StatusChip({super.key, required this.kind, this.labelOverride});

  ({IconData icon, Color color, String label}) get _spec {
    switch (kind) {
      case StatusChipKind.meshActive:
        return (icon: Icons.hub, color: AppColors.success, label: 'Mesh Active');
      case StatusChipKind.offline:
        return (icon: Icons.cloud_off, color: AppColors.neutral500, label: 'Offline');
      case StatusChipKind.connected:
        return (icon: Icons.link, color: AppColors.success, label: 'Connected');
      case StatusChipKind.relaying:
        return (icon: Icons.sync, color: AppColors.primary, label: 'Relaying');
      case StatusChipKind.uploading:
        return (icon: Icons.upload, color: AppColors.primary, label: 'Uploading');
      case StatusChipKind.delivered:
        return (icon: Icons.check_circle, color: AppColors.success, label: 'Delivered');
      case StatusChipKind.volunteerResponding:
        return (icon: Icons.volunteer_activism, color: AppColors.warning, label: 'Volunteer Responding');
      case StatusChipKind.governmentConnected:
        return (icon: Icons.account_balance, color: AppColors.primary, label: 'Government Connected');
      case StatusChipKind.success:
        return (icon: Icons.check_circle, color: AppColors.success, label: 'Success');
      case StatusChipKind.warning:
        return (icon: Icons.warning_amber_rounded, color: AppColors.warning, label: 'Warning');
      case StatusChipKind.danger:
        return (icon: Icons.error, color: AppColors.emergency, label: 'Failed');
      case StatusChipKind.neutral:
        return (icon: Icons.circle, color: AppColors.neutral500, label: '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final spec = _spec;
    final color = spec.color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.12),
        borderRadius: AppRadius.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(spec.icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            labelOverride ?? spec.label,
            style: AppTypography.label.copyWith(color: color, letterSpacing: 0.2),
          ),
        ],
      ),
    );
  }
}
