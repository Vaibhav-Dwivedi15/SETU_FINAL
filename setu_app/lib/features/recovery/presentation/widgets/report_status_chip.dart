import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_typography.dart';

import '../../data/models/report_status.dart';

/// Status shown as icon + text, never colour alone.
class ReportStatusChip extends StatelessWidget {
  const ReportStatusChip({super.key, required this.status});

  final ReportStatus status;

  Color get _color {
    switch (status) {
      case ReportStatus.draft:
        return AppColors.offline;
      case ReportStatus.pendingSync:
        return AppColors.warning;
      case ReportStatus.submitted:
        return AppColors.success;
      case ReportStatus.failed:
        return AppColors.emergencyBright;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Status: ${status.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.14),
          borderRadius: AppRadius.pillRadius,
          border: Border.all(color: _color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(status.icon, size: 14, color: _color),
            const SizedBox(width: 4),
            Text(
              status.label.toUpperCase(),
              style: AppTypography.metadata.copyWith(
                color: _color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
