import '../models/history_model.dart';
import '../services/history_service.dart';

class HistoryRepository {
  final HistoryService _service = HistoryService();

  Future<List<HistoryModel>> getHistory() {
    return _service.getHistory();
  }

  Future<void> addHistory(HistoryModel history) async {
    await _service.addHistory(history);
  }

  Future<void> clearHistory() async {
    await _service.clearHistory();
  }
}
