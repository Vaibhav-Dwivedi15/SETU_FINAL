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

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: EmergencyCategory.values.map((category) {
        final isSelected = category == selected;

        return ChoiceChip(
          selected: isSelected,
          onSelected: (_) => onChanged(category),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.pillRadius),
          avatar: Icon(
            category.icon,
            size: 18,
            color: isSelected ? Colors.white : AppColors.primary,
          ),
          label: Text(category.title),
          selectedColor: AppColors.primary,
          labelStyle: AppTypography.body.copyWith(
            color: isSelected
                ? Colors.white
                : theme.textTheme.bodyLarge?.color,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
          backgroundColor: isDark ? Colors.white10 : AppColors.neutral100,
        );
      }).toList(),
    );
  }
}
