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

  // ---- Dashboard Visual Identity Tokens (Dark Theme Core) ----
  static const Color bgApp = Color(0xFF080B12); // Dashboard --bg-app
  static const Color bgSidebar = Color(0xFF0A0E17); // Dashboard --bg-sidebar
  static const Color bgSurface = Color(0xFF111827); // Dashboard --bg-surface (slate 900)
  static const Color bgSurfaceAlt = Color(0xFF151D2E); // Dashboard --bg-surface-alt
  static const Color bgSurfaceHover = Color(0xFF1A2338); // Dashboard --bg-surface-hover
  static const Color bgInput = Color(0xFF0D1421); // Dashboard --bg-input

  // ---- Borders ----
  static const Color borderSubtle = Color(0xFF3E526E); // Dashboard --border-subtle
  static const Color borderStrong = Color(0xFF556F9A); // Dashboard --border-strong

  // ---- Text Scale ----
  static const Color textPrimary = Color(0xFFE8EDF5); // Dashboard --text-primary
  static const Color textSecondary = Color(0xFF94A3B8); // Dashboard --text-secondary
  static const Color textDim = Color(0xFF8290AB); // Dashboard --text-dim

  // ---- Accent / Connectivity ----
  static const Color accent = Color(0xFF38BDF8); // Dashboard --accent / --network (Sky blue 400)
  static const Color accentDim = Color(0xFF0EA5E9); // Dashboard --accent-dim
  static const Color accentGlow = Color(0x4038BDF8); // Dashboard --accent-glow

  // ---- Domain / Severity Colors ----
  static const Color emergency = Color(0xFFDC2626); // Emergency Red
  static const Color emergencyBright = Color(0xFFF87171); // Dashboard --danger
  static const Color emergencyDark = Color(0xFF7F1D1D); // Dashboard --danger-dim
  static const Color emergencyContainer = Color(0xFF2B1214);

  static const Color warning = Color(0xFFFB923C); // Dashboard --warning (Orange 400)
  static const Color warningDark = Color(0xFF7C2D12); // Dashboard --warning-dim
  static const Color warningContainer = Color(0xFF2C1810);

  static const Color caution = Color(0xFFFBBF24); // Dashboard --caution (Amber 400)
  static const Color success = Color(0xFF4ADE80); // Dashboard --success (Green 400)
  static const Color successDark = Color(0xFF14532D); // Dashboard --success-dim
  static const Color successContainer = Color(0xFF0F291E);

  static const Color network = Color(0xFF38BDF8); // Dashboard --network
  static const Color offline = Color(0xFF70829D); // Dashboard --offline
  static const Color offlineContainer = Color(0xFF1E2633);
  static const Color relay = Color(0xFF2DD4A8); // Dashboard --relay (Teal)
  static const Color community = Color(0xFFA78BFA); // Dashboard --community (Purple)

  // ---- Gradients ----
  static const LinearGradient emergencyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEF4444), Color(0xFF991B1B)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF38BDF8), Color(0xFF0284C7)],
  );

  // ---- Backward Compatibility Aliases ----
  static const Color primary = Color(0xFF0284C7); // Sky 600 trust blue
  static const Color primaryLight = Color(0xFF38BDF8); // Sky 400
  static const Color primaryContainer = Color(0xFF1E293B);
  static const Color info = primaryLight;
  static const Color infoContainer = primaryContainer;

  // ---- Neutral scale ----
  static const Color neutral900 = Color(0xFF080B12);
  static const Color neutral700 = Color(0xFF1E293B);
  static const Color neutral500 = Color(0xFF64748B);
  static const Color neutral300 = Color(0xFF94A3B8);
  static const Color neutral100 = Color(0xFFF1F5F9);

  // ---- Light theme surfaces ----
  static const Color lightBackground = Color(0xFFF1F5F9);
  static const Color lightSurface = Colors.white;
  static const Color lightSurfaceAlt = Color(0xFFF8FAFC);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextDim = Color(0xFF627793);
  static const Color lightBorder = Color(0xFFCBD5E1);
  static const Color lightBorderStrong = Color(0xFF94A3B8);

  // ---- Dark theme surfaces ----
  static const Color darkBackground = Color(0xFF080B12);
  static const Color darkSurface = Color(0xFF111827);
  static const Color darkSurfaceAlt = Color(0xFF151D2E);
  static const Color darkTextPrimary = Color(0xFFE8EDF5);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextDim = Color(0xFF8290AB);
  static const Color darkBorder = Color(0xFF3E526E);
  static const Color darkBorderStrong = Color(0xFF556F9A);
}
