import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_radius.dart';
import '../app_spacing.dart';

class SetuCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? accentBorderLeft;
  final double? width;
  final double? height;

  const SetuCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin = EdgeInsets.zero,
    this.backgroundColor,
    this.borderColor,
    this.accentBorderLeft,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = backgroundColor ??
        (isDark ? AppColors.bgSurface : AppColors.lightSurface);
    final border = borderColor ??
        (isDark ? AppColors.borderSubtle : AppColors.lightBorder);

    Widget cardContent = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.mdRadius,
        border: Border.all(color: border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.mdRadius,
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );

    if (accentBorderLeft != null) {
      cardContent = Container(
        width: width,
        height: height,
        margin: margin,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadius.mdRadius,
          border: Border.all(color: border, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: Container(color: accentBorderLeft),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: AppRadius.mdRadius,
                child: Padding(
                  padding: padding,
                  child: child,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return cardContent;
  }
}
