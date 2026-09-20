// =====================================================
// SETU Project
// Module : Theme (UI/UX overhaul, Block 28 — de-orange the red)
// Owner  : Sudheer
// =====================================================
//
// Single source of truth for app colors — see Block 10 for
// why the old duplicate file was removed, Block 13/19 for the
// earlier color history.
//
// Block 28: primary moved from Red 800 (0xFFC62828, still
// read as orange-leaning on some screens) to Red 900
// (0xFFB71C1C), paired with a true maroon dark
// (0xFF690000) instead of a lighter dark-red. This reads as
// a deeper, more serious "emergency maroon" rather than a
// bright orange-red — closer to the tone of trusted
// government/safety apps (e.g. Aarogya Setu-style palettes)
// while keeping SETU's own red identity.

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Brand — deliberately the same in light and dark mode.
  static const Color primary = Color(0xFFB71C1C); // Red 900
  static const Color primaryDark = Color(0xFF690000); // true maroon

  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFFFA000);
  static const Color danger = Color(0xFFB71C1C);

  static const Color info = Color(0xFF1565C0);
  static const Color infoDark = Color(0xFF0D47A1);

  static const Color alert = Color(0xFFEF6C00);
  static const Color alertDark = Color(0xFFB53D00);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryDark],
  );

  static const LinearGradient infoGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [info, infoDark],
  );

  static const LinearGradient alertGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [alert, alertDark],
  );

  // Light theme surfaces
  static const Color lightBackground = Color(0xFFF7F9FC);
  static const Color lightSurface = Colors.white;
  static const Color lightTextPrimary = Color(0xFF212121);
  static const Color lightTextSecondary = Color(0xFF757575);
  static const Color lightBorder = Color(0xFFE0E0E0);

  // Dark theme surfaces
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkTextPrimary = Color(0xFFECECEC);
  static const Color darkTextSecondary = Color(0xFFA0A0A0);
  static const Color darkBorder = Color(0xFF2C2C2C);
}
