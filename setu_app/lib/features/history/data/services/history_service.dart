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

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_historyKey);
  }
}
