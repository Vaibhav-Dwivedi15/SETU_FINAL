import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_model.dart';

class HistoryService {
  static const String _historyKey = "sos_history";

  Future<List<HistoryModel>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();

    final List<String> data = prefs.getStringList(_historyKey) ?? [];

    return data.map((item) => HistoryModel.fromJson(jsonDecode(item))).toList();
  }

  Future<void> saveHistory(List<HistoryModel> history) async {
    final prefs = await SharedPreferences.getInstance();

    final List<String> data = history
        .map((item) => jsonEncode(item.toJson()))
        .toList();

    await prefs.setStringList(_historyKey, data);
  }

  Future<void> addHistory(HistoryModel history) async {
    final historyList = await getHistory();

    historyList.insert(0, history);

    await saveHistory(historyList);
  }

  /// Aug 5 2026: added so a real ack arriving later (see
  /// MeshLocator's acknowledgments listener) can update an
  /// already-written history entry's status from "Sent" to
  /// "Delivered" -- finds by emergencyId, not by list position, since
  /// the ack can arrive well after this entry was written and other
  /// entries may have been added in between. No-op (not an error) if
  /// no matching entry is found -- e.g. history was cleared, or this
  /// is an old entry written before emergencyId existed.
  Future<void> updateStatusByEmergencyId(String emergencyId, String newStatus) async {
    if (emergencyId.isEmpty) return;

    final historyList = await getHistory();
    final index = historyList.indexWhere((h) => h.emergencyId == emergencyId);
    if (index == -1) return;

    historyList[index] = historyList[index].copyWith(status: newStatus);
    await saveHistory(historyList);
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_historyKey);
  }
}
