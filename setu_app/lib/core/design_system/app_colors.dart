// =====================================================
// SETU Design System v1.0
// Module : Colors
// Owner  : Sudheer
// =====================================================
//
// KEY SHIFT FROM EARLIER WORK: primary is now Deep Blue
// (trust, calm, government-grade), not red. Red is now
// RESERVED exclusively for emergency/SOS-critical elements —
// the SOS button, active-emergency status chips, danger
// states. Using red as the general app chrome color made
// every screen feel alarming; reserving it makes it actually
// mean something when it appears.
//
// Gradients are used sparingly (SOS button, maybe one hero
// element) — not on every icon badge, per "avoid loud
// gradients" in the design brief.
import 'package:flutter/material.dart';
class AppColors {
  AppColors._();
  // ---- Primary (Trust) ----
  static const Color primary = Color(0xFF0D47A1); // Deep Blue 900
  static const Color primaryLight = Color(0xFF1565C0); // Blue 800
  static const Color primaryContainer = Color(0xFFE3EDF9);
  // ---- Emergency (reserved — SOS, danger states only) ----
  static const Color emergency = Color(0xFFB71C1C); // Deep Red 900
  static const Color emergencyDark = Color(0xFF7A0000);
  static const Color emergencyContainer = Color(0xFFFBE4E4);
  static const LinearGradient emergencyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [emergency, emergencyDark],
  );
  // ---- Semantic ----
  static const Color success = Color(0xFF2E7D32);
  static const Color successContainer = Color(0xFFE1F0E2);
  static const Color warning = Color(0xFFEF6C00);
  static const Color warningContainer = Color(0xFFFCE9DA);
  static const Color info = primary;
  static const Color infoContainer = primaryContainer;
  // Aug 6 2026: mesh relay signal color — matches the dashboard's
  // --relay token (setu_dashboard/src/App.css) exactly, so both
  // products render the same "packet successfully relayed" state in
  // the same color. Deliberately distinct from `success` (a different
  // teal-green, not the same green reused for form-success/generic
  // OK states) — see RelayTraceIndicator and RelayTrace.jsx for where
  // this is used.
  static const Color relay = Color(0xFF2DD4A8);
  // ---- Neutral / Grayscale ----
  static const Color neutral900 = Color(0xFF1A1C1E);
  static const Color neutral700 = Color(0xFF43474D);
  static const Color neutral500 = Color(0xFF73777F);
  static const Color neutral300 = Color(0xFFC3C7CF);
  static const Color neutral100 = Color(0xFFEEF0F4);
  // ---- Light theme surfaces ----
  static const Color lightBackground = Color(0xFFF7F9FC);
  static const Color lightSurface = Colors.white;
  static const Color lightTextPrimary = neutral900;
  static const Color lightTextSecondary = neutral500;
  static const Color lightBorder = neutral300;
  // ---- Dark theme surfaces ----
  static const Color darkBackground = Color(0xFF101214);
  static const Color darkSurface = Color(0xFF1C1F22);
  static const Color darkTextPrimary = Color(0xFFECEDEF);
  static const Color darkTextSecondary = Color(0xFF9CA1A8);
  static const Color darkBorder = Color(0xFF32363B);
}
