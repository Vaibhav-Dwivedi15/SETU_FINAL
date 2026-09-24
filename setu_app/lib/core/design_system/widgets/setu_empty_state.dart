import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_spacing.dart';
import '../app_typography.dart';
import 'setu_button.dart';

class SetuEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SetuEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isDark ? AppColors.bgSurfaceAlt : AppColors.lightBackground,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? AppColors.borderSubtle : AppColors.lightBorder,
                  width: 1,
                ),
              ),
              child: Icon(
                icon,
                size: 32,
                color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.cardTitle.copyWith(
                color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                description,
                textAlign: TextAlign.center,
                style: AppTypography.supporting.copyWith(
                  color: isDark ? AppColors.textDim : AppColors.lightTextDim,
                ),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              SetuButton(
                label: actionLabel!,
                onPressed: onAction,
                variant: SetuButtonVariant.secondary,
                size: SetuButtonSize.sm,
                fullWidth: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
