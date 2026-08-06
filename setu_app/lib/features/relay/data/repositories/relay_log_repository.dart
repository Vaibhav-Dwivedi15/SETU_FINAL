import '../models/relay_log_entry.dart';
import '../services/relay_log_service.dart';

/// Aug 6 2026. Singleton (like MeshLocator) so mesh_service.dart can log
/// an entry from a single shared instance without threading a
/// repository through the constructor -- same reasoning as
/// HistoryRepository, just needs to be reachable from the mesh layer
/// itself, not only from UI code.
class RelayLogRepository {
  RelayLogRepository._();
  static final RelayLogRepository instance = RelayLogRepository._();

  final RelayLogService _service = RelayLogService();

  // Matches the ID convention already used by HistoryModel and
  // NearbyAlertModel elsewhere in this codebase -- no new package
  // dependency needed. A simple counter guards against two entries
  // logged in the same millisecond colliding (relay events can fire
  // in rapid succession).
  static int _collisionGuard = 0;

  Future<List<RelayLogEntry>> getLog() => _service.getLog();

  Future<void> log({
    required RelayLogType type,
    required String packetId,
    required String detail,
  }) {
    _collisionGuard = (_collisionGuard + 1) % 1000;
    final id = '${DateTime.now().millisecondsSinceEpoch}_$_collisionGuard';
    return _service.addEntry(
      RelayLogEntry(
        id: id,
        timestamp: DateTime.now(),
        type: type,
        packetId: packetId,
        detail: detail,
      ),
    );
  }

  Future<void> clearLog() => _service.clearLog();
}
