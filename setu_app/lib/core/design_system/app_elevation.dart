// =====================================================
// SETU Design System v1.0
// Module : Elevation / Shadows
// Owner  : Sudheer
// =====================================================
//
// Soft, low-contrast shadows — premium apps use elevation to
// suggest depth quietly, not with hard black drop-shadows.
// Dark mode gets NO shadows (they're invisible/wrong on dark
// surfaces) — use a subtle border instead, handled at the
// component level.

import 'package:flutter/material.dart';

class AppElevation {
  AppElevation._();

  static List<BoxShadow> level1 = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> level2 = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> level3 = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.10),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  /// Emergency elements get a tinted shadow (their own color,
  /// not generic black) — makes the SOS button feel like it's
  /// glowing rather than just sitting on a shadow.
  static List<BoxShadow> tinted(Color color, {double alpha = 0.35}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: alpha),
        blurRadius: 16,
        offset: const Offset(0, 6),
      ),
    ];
  }
}
