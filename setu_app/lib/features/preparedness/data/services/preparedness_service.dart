import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/services.dart' show rootBundle;

import '../models/safety_guide_model.dart';

/// Loads a JSON list of guides bundled INSIDE the app (packaged into the
/// APK at build time), so guide screens work with zero connectivity,
/// exactly like every other "must work offline" requirement in SETU.
///
/// Deliberately NOT a network call, NOT a backend-fetched cache, and NOT
/// wired to any government API. If a real integration is added later it
/// should replace this data source, not the contract
/// (loadGuides()/guideById()).
///
/// Parsed once and cached in memory -- this is a few KB of text.
class GuideLibrary {
  GuideLibrary({
    required this.assetPath,
    required this.listKey,
    Future<String> Function(String path)? loader,
  }) : _loader = loader ?? rootBundle.loadString;

  final String assetPath;
  final String listKey;
  final Future<String> Function(String path) _loader;

  List<SafetyGuideModel>? _cached;

  Future<List<SafetyGuideModel>> loadGuides() async {
    final cached = _cached;
    if (cached != null) return cached;

    try {
      final raw = await _loader(assetPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final guides = (json[listKey] as List)
          .map((entry) => SafetyGuideModel.fromJson(entry as Map<String, dynamic>))
          .toList();
      _cached = guides;
      return guides;
    } catch (e) {
      // A missing/corrupt bundled asset must not crash the screen -- it
      // should show "unavailable", not throw while someone is checking
      // evacuation steps. Not cached, so a later call can retry.
      developer.log('Failed to load guides from $assetPath: $e', name: 'GuideLibrary');
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

/// PRIORITY 7 (BEFORE-disaster / preparedness): the bundled disaster and
/// safety guides.
abstract final class PreparednessService {
  static final GuideLibrary instance = GuideLibrary(
    assetPath: 'assets/preparedness/safety_guides.json',
    listKey: 'guides',
  );
}
