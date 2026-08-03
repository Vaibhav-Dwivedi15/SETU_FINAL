// =====================================================
// SETU Design System v1.0
// Module : AppButton
// Owner  : Sudheer
// =====================================================
//
// Three variants: primary (blue, everyday actions), secondary
// (outlined, low-emphasis), emergency (reserved — SOS and
// truly destructive/critical actions only). Emergency should
// be rare in the UI; if it starts appearing often, that's a
// sign something should be primary instead.

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_elevation.dart';
import '../app_radius.dart';
import '../app_typography.dart';

enum AppButtonVariant { primary, secondary, emergency }

class AppButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool fullWidth;

  const AppButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20),
          const SizedBox(width: 8),
        ],
        Text(label, style: AppTypography.bodyStrong),
      ],
    );

    final width = fullWidth ? double.infinity : null;

    switch (variant) {
      case AppButtonVariant.primary:
        return SizedBox(
          width: width,
          height: 52,
          child: ElevatedButton(onPressed: onPressed, child: content),
        );

      case AppButtonVariant.secondary:
        return SizedBox(
          width: width,
          height: 52,
          child: OutlinedButton(onPressed: onPressed, child: content),
        );

      case AppButtonVariant.emergency:
        return SizedBox(
          width: width,
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppColors.emergencyGradient,
              borderRadius: AppRadius.mdRadius,
              boxShadow: AppElevation.tinted(AppColors.emergency),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: AppRadius.mdRadius,
              child: InkWell(
                borderRadius: AppRadius.mdRadius,
                onTap: onPressed,
                child: Center(
                  child: DefaultTextStyle(
                    style: AppTypography.bodyStrong.copyWith(color: Colors.white),
                    child: IconTheme(
                      data: const IconThemeData(color: Colors.white),
                      child: content,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    }
  }
}
