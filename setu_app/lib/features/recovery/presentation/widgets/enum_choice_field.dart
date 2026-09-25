import 'package:flutter/material.dart';

import 'package:setu_app/core/design_system/app_colors.dart';
import 'package:setu_app/core/design_system/app_spacing.dart';
import 'package:setu_app/core/design_system/app_typography.dart';
import 'package:setu_app/core/widgets/theme_colors.dart';

/// A labelled single-choice group rendered as chips (48 dp touch
/// targets), with an inline error line for validation.
class EnumChoiceField<T extends Enum> extends StatelessWidget {
  const EnumChoiceField({
    super.key,
    required this.label,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
    this.errorText,
  });

  final String label;
  final List<T> values;
  final String Function(T value) labelOf;
  final T? selected;
  final ValueChanged<T> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Semantics(
        container: true,
        label: label,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: AppTypography.label.copyWith(color: context.textSecondaryColor)),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final value in values)
                  ChoiceChip(
                    label: Text(labelOf(value)),
                    selected: value == selected,
                    onSelected: (_) => onChanged(value),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    visualDensity: VisualDensity.standard,
                  ),
              ],
            ),
            if (errorText != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(errorText!,
                    style: AppTypography.caption.copyWith(color: AppColors.emergencyBright)),
              ),
          ],
        ),
      ),
    );
  }
}
