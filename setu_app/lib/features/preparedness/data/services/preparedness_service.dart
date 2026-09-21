import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/services.dart' show rootBundle;

import '../models/safety_guide_model.dart';

/// PRIORITY 7 (BEFORE-disaster / preparedness).
///
/// Loads disaster safety guides bundled INSIDE the app (assets/preparedness/
/// safety_guides.json — packaged into the APK at build time), so this
/// screen works with zero connectivity, exactly like every other
/// "must work offline" requirement in the mesh layer itself.
///
/// Deliberately NOT a network call, NOT a backend-fetched cache, and NOT
/// wired to any government API — the session brief is explicit that
/// external government integration must not be fabricated. If a real
/// integration is added later, it should replace this service's data
/// source, not this service's contract (loadGuides()/guideById()).
///
/// Parsed once and cached in memory for the app's lifetime — this is a
/// few KB of text, not something worth re-parsing on every screen visit.
class PreparednessService {
  PreparednessService._();
  static final PreparednessService instance = PreparednessService._();

  static const _assetPath = 'assets/preparedness/safety_guides.json';

  List<SafetyGuideModel>? _cached;

  Future<List<SafetyGuideModel>> loadGuides() async {
    final cached = _cached;
    if (cached != null) return cached;

    try {
      final raw = await rootBundle.loadString(_assetPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final guides = (json['guides'] as List)
          .map((entry) => SafetyGuideModel.fromJson(entry as Map<String, dynamic>))
          .toList();
      _cached = guides;
      return guides;
    } catch (e) {
      // A missing/corrupt bundled asset must not crash the preparedness
      // screen -- it should show "unavailable", not throw during a
      // moment someone may be checking evacuation steps.
      developer.log('Failed to load preparedness guides: $e', name: 'PreparednessService');
      return const [];
    }
  }

  Future<SafetyGuideModel?> guideById(String id) async {
    final guides = await loadGuides();
    for (final guide in guides) {
      if (guide.id == id) return guide;
    }
    return null;
  }
}
