import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/checklist.dart';

/// Bundled checklist definitions (offline asset) plus the user's
/// completion state (SharedPreferences, one id-set per checklist).
class ChecklistRepository {
  ChecklistRepository({Future<String> Function(String path)? loader})
      : _loader = loader ?? rootBundle.loadString;

  static const String kitId = 'emergency_kit';
  static const String _assetPath = 'assets/preparedness/checklists.json';
  static const String _keyPrefix = 'checklist_done_';

  final Future<String> Function(String path) _loader;
  List<Checklist>? _catalog;

  Future<List<Checklist>> loadChecklists() async {
    final cached = _catalog;
    if (cached != null) return cached;
    try {
      final json = jsonDecode(await _loader(_assetPath)) as Map<String, dynamic>;
      final loaded = (json['checklists'] as List)
          .map((e) => Checklist.fromJson(e as Map<String, dynamic>))
          .toList();
      _catalog = loaded;
      return loaded;
    } catch (e) {
      developer.log('Failed to load checklists: $e', name: 'ChecklistRepository');
      return const [];
    }
  }

  Future<Checklist?> checklistById(String id) async {
    for (final c in await loadChecklists()) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Progress for one checklist. Stored ids that no longer exist in the
  /// bundled definition are ignored, so a content update never inflates
  /// the completed count.
  Future<ChecklistProgress?> progressFor(String id) async {
    final checklist = await checklistById(id);
    if (checklist == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('$_keyPrefix$id') ?? const [];
    final valid = checklist.items.map((i) => i.id).toSet();
    return ChecklistProgress(
      checklist: checklist,
      completedIds: stored.where(valid.contains).toSet(),
    );
  }

  Future<List<ChecklistProgress>> allProgress() async {
    final result = <ChecklistProgress>[];
    for (final c in await loadChecklists()) {
      final progress = await progressFor(c.id);
      if (progress != null) result.add(progress);
    }
    return result;
  }

  Future<void> setItemDone(String checklistId, String itemId, bool done) async {
    final prefs = await SharedPreferences.getInstance();
    final current = (prefs.getStringList('$_keyPrefix$checklistId') ?? const []).toSet();
    done ? current.add(itemId) : current.remove(itemId);
    await prefs.setStringList('$_keyPrefix$checklistId', current.toList());
  }

  Future<void> reset(String checklistId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$checklistId');
  }
}
