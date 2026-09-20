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

  /// Aug 5 2026: see HistoryService.updateStatusByEmergencyId --
  /// exposed here so MeshLocator's ack listener can update history
  /// without reaching past the repository layer.
  Future<void> updateStatusByEmergencyId(String emergencyId, String newStatus) async {
    await _service.updateStatusByEmergencyId(emergencyId, newStatus);
  }

  Future<void> clearHistory() async {
    await _service.clearHistory();
  }
}
