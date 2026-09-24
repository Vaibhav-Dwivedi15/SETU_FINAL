import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_radius.dart';
import '../app_typography.dart';

enum SetuButtonVariant {
  primary,
  secondary,
  emergency,
  outlined,
  ghost,
}

enum SetuButtonSize {
  sm,
  md,
  lg,
}

class SetuButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final SetuButtonVariant variant;
  final SetuButtonSize size;
  final bool fullWidth;
  final bool isLoading;

  const SetuButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.variant = SetuButtonVariant.primary,
    this.size = SetuButtonSize.md,
    this.fullWidth = true,
    this.isLoading = false,
  });

  double get _height {
    switch (size) {
      case SetuButtonSize.sm:
        return 40;
      case SetuButtonSize.md:
        return 50;
      case SetuButtonSize.lg:
        return 56;
    }
  }

  TextStyle get _textStyle {
    switch (size) {
      case SetuButtonSize.sm:
        return AppTypography.label;
      case SetuButtonSize.md:
        return AppTypography.bodyStrong;
      case SetuButtonSize.lg:
        return AppTypography.subtitle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bg;
    Color fg;
    BorderSide border = BorderSide.none;

    switch (variant) {
      case SetuButtonVariant.primary:
        bg = isDark ? AppColors.accent : AppColors.primary;
        fg = isDark ? AppColors.bgApp : Colors.white;
        break;
      case SetuButtonVariant.secondary:
        bg = isDark ? AppColors.bgSurfaceAlt : AppColors.lightBackground;
        fg = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
        border = BorderSide(
          color: isDark ? AppColors.borderSubtle : AppColors.lightBorder,
        );
        break;
      case SetuButtonVariant.emergency:
        bg = AppColors.emergency;
        fg = Colors.white;
        break;
      case SetuButtonVariant.outlined:
        bg = Colors.transparent;
        fg = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
        border = BorderSide(
          color: isDark ? AppColors.borderSubtle : AppColors.lightBorder,
          width: 1.2,
        );
        break;
      case SetuButtonVariant.ghost:
        bg = Colors.transparent;
        fg = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;
        break;
    }

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          ),
          const SizedBox(width: 10),
        ] else if (icon != null) ...[
          Icon(icon, size: size == SetuButtonSize.sm ? 16 : 20, color: fg),
          const SizedBox(width: 8),
        ],
        Text(
          label,
          style: _textStyle.copyWith(color: fg),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: onPressed != null && !isLoading,
      label: label,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: _height,
          minWidth: fullWidth ? double.infinity : 48,
        ),
        child: SizedBox(
          width: fullWidth ? double.infinity : null,
          height: _height,
          child: Material(
            color: onPressed == null ? bg.withValues(alpha: 0.4) : bg,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.mdRadius,
              side: border,
            ),
            child: InkWell(
              borderRadius: AppRadius.mdRadius,
              onTap: (isLoading || onPressed == null) ? null : onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
