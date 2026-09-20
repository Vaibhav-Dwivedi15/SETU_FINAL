// =====================================================
// SETU Project
// Module : Home Dashboard (Block 13 — visual polish)
// Owner  : Sudheer
// =====================================================
//
// Redesigned from the old top-icon/bottom-text stacked
// layout, which overflowed on 2-line labels like "Emergency
// Contacts". Icon now sits beside the text in a horizontal
// row (same pattern as DashboardGridTile), giving text much
// more room on one line — no more overflow.

import 'package:flutter/material.dart';

import 'package:setu_app/core/constants/app_colors.dart';

class QuickAccessTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const QuickAccessTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: theme.cardColor,
          elevation: isDark ? 0 : 4,
          shadowColor: Colors.black12,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Container(
              height: 72,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: isDark
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white12),
                    )
                  : null,
              child: Row(
                children: [
                  Container(
                    height: 46,
                    width: 46,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
