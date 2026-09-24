// =====================================================
// SETU Project
// Module : SOS / Emergency Category (UI-only)
// Owner  : Sudheer
// =====================================================
//
// Design System v1 pass: this is a categorization choice, not
// the alarm itself, so it stays in Primary Blue (trust) — not
// Emergency Red — consistent with the "red is rare and means
// something" rule from the design brief.

import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_radius.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';

import '../../data/models/emergency_category.dart';

class EmergencyCategorySelector extends StatelessWidget {
  final EmergencyCategory selected;
  final ValueChanged<EmergencyCategory> onChanged;

  const EmergencyCategorySelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selectedBg = isDark ? AppColors.accent : AppColors.primary;
    final unselectedBg = isDark ? AppColors.bgSurfaceAlt : AppColors.lightBackground;
    final unselectedBorder = isDark ? AppColors.borderSubtle : AppColors.lightBorder;
    final unselectedText = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: EmergencyCategory.values.map((category) {
        final isSelected = category == selected;

        return ChoiceChip(
          selected: isSelected,
          onSelected: (_) => onChanged(category),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.pillRadius,
            side: BorderSide(
              color: isSelected ? Colors.transparent : unselectedBorder,
              width: 1,
            ),
          ),
          avatar: Icon(
            category.icon,
            size: 18,
            color: isSelected ? (isDark ? AppColors.bgApp : Colors.white) : AppColors.accent,
          ),
          label: Text(category.title),
          selectedColor: selectedBg,
          labelStyle: AppTypography.bodyStrong.copyWith(
            fontSize: 13.5,
            color: isSelected
                ? (isDark ? AppColors.bgApp : Colors.white)
                : unselectedText,
          ),
          backgroundColor: unselectedBg,
        );
      }).toList(),
    );
  }
}
