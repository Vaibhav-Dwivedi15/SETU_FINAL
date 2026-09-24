import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_radius.dart';
import '../app_spacing.dart';
import '../app_typography.dart';

class SetuOfflineBanner extends StatelessWidget {
  final bool isOffline;
  final int? peerCount;
  final VoidCallback? onTap;

  const SetuOfflineBanner({
    super.key,
    required this.isOffline,
    this.peerCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isOffline
        ? (isDark ? AppColors.offlineContainer : const Color(0xFFE2E8F0))
        : (isDark ? AppColors.successContainer : const Color(0xFFDCFCE7));

    final borderColor = isOffline
        ? (isDark ? AppColors.borderSubtle : AppColors.lightBorder)
        : (isDark ? AppColors.successDark : const Color(0xFF86EFAC));

    final iconColor = isOffline ? AppColors.accent : AppColors.success;
    final titleColor = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final subColor = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;

    final title = isOffline ? 'Offline Mode · Mesh Active' : 'Connected to Emergency Network';
    final description = isOffline
        ? (peerCount != null && peerCount! > 0
            ? '$peerCount nearby SETU peer(s) found. Emergency alerts will relay automatically.'
            : 'No cellular required. Emergency signals will relay through nearby SETU devices.')
        : 'Direct internet link active. Distress signals send immediately.';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: AppRadius.mdRadius,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.mdRadius,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.14),
                    borderRadius: AppRadius.smRadius,
                  ),
                  child: Icon(
                    isOffline ? Icons.hub_rounded : Icons.wifi_rounded,
                    size: 20,
                    color: iconColor,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: AppTypography.cardTitle.copyWith(
                                color: titleColor,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (isOffline)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.18),
                                borderRadius: AppRadius.pillRadius,
                              ),
                              child: Text(
                                'HOP-BY-HOP',
                                style: AppTypography.metadata.copyWith(
                                  color: AppColors.accent,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: AppTypography.caption.copyWith(
                          color: subColor,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: subColor,
                    size: 20,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
