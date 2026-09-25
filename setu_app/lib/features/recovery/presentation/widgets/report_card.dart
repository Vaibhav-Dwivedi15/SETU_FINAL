import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';
import 'package:setu_app/core/widgets/theme_colors.dart';

import '../../data/models/recovery_record.dart';
import 'report_presentation.dart';
import 'report_status_chip.dart';

/// One row in My Reports: type, ID, time, location, severity/urgency and
/// current local status.
class ReportCard extends StatelessWidget {
  const ReportCard({super.key, required this.record, required this.onTap});

  final RecoveryRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final priority = record.priorityLabel;
    final location = record.location.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        button: true,
        label: '${record.type.title}, ${record.headline}, '
            'status ${record.status.label}, report ${record.id}',
        excludeSemantics: true,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: SetuCard(
            onTap: onTap,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(record.type.icon, size: 18, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        record.headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.cardTitle
                            .copyWith(color: context.textPrimaryColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ReportStatusChip(status: record.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${record.type.filterLabel} · ${record.id}'
                  '${priority == null ? '' : ' · $priority'}',
                  style: AppTypography.caption.copyWith(color: context.textSecondaryColor),
                ),
                if (location.isNotEmpty)
                  Text(
                    location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(color: context.textSecondaryColor),
                  ),
                Text(
                  formatDateTime(record.updatedAt),
                  style: AppTypography.metadata.copyWith(color: context.textDimColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
