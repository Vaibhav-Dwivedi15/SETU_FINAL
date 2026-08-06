// =====================================================
// SETU Design System v1.0
// Module : Typography
// Owner  : Sudheer
// =====================================================
//
// A deliberate, named scale — every text style in the app
// should come from here, not a random TextStyle(fontSize: 17).
//
// Aug 6 2026: displayLarge/headline/title now use Space Grotesk
// (via google_fonts) instead of the platform default -- the same
// typeface as the dashboard's headers (see setu_dashboard's App.css),
// so the two products share a literal, deliberate brand identity
// instead of coincidentally similar defaults. body/bodyStrong/caption/
// label deliberately STAY on the platform default -- Space Grotesk's
// slightly mechanical character reads well at header sizes but adds
// nothing (and costs legibility) at small body-text sizes, so this is
// a targeted pairing, not a full font swap.
//
// Requires the google_fonts package: `flutter pub add google_fonts`.
// The font is bundled/cached by the package (no manual asset setup),
// and google_fonts falls back to the platform default automatically
// if the network fetch on first run ever fails -- never a hard crash.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTypography {
  AppTypography._();

  static TextStyle get displayLarge => GoogleFonts.spaceGrotesk(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.5,
        height: 1.2,
      );

  static TextStyle get headline => GoogleFonts.spaceGrotesk(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.2,
        height: 1.25,
      );

  static TextStyle get title => GoogleFonts.spaceGrotesk(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 1.3,
      );

  static const TextStyle subtitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.normal,
    height: 1.5,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.normal,
    height: 1.4,
  );

  static const TextStyle label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    height: 1.3,
  );

  /// The one exception to "everything from the scale" — the
  /// SOS button's own label is deliberately larger/bolder than
  /// anything else in the app, since it's the app's identity
  /// element. Kept on the platform default (not Space Grotesk) --
  /// this label needs to read as urgent/human, not typographically
  /// "designed"; the mechanical display face is wrong for this one
  /// spot specifically.
  static const TextStyle sosButton = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.4,
  );
}
