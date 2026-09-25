import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/design_system/widgets/design_system_widgets.dart';

import 'theme_colors.dart';

/// A full-width navigation row used by the Prepare and Recovery hubs:
/// icon, title, one line of context and a chevron. Always at least 64 dp
/// tall so it is an easy touch target, and grows with the text size.
class HubTile extends StatelessWidget {
  const HubTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accent = AppColors.accent,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        button: true,
        label: '$title. $subtitle',
        excludeSemantics: true,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: SetuCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            onTap: onTap,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: AppRadius.smRadius,
                  ),
                  child: Icon(icon, size: 22, color: accent),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: AppTypography.cardTitle
                              .copyWith(color: context.textPrimaryColor)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: AppTypography.caption
                              .copyWith(color: context.textSecondaryColor)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: context.textDimColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
