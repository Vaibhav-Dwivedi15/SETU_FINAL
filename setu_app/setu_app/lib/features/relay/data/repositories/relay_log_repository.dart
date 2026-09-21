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

  /// Sep 2026: made failure-proof.
  ///
  /// Every call site in the relay hot path is `unawaited(...)` (see
  /// mesh_service.dart), which means a rejected future from here becomes
  /// an UNHANDLED async error rather than something the relay path
  /// catches. SharedPreferences can genuinely fail — disk full, storage
  /// locked, platform channel not available (headless/background
  /// isolate, unit tests) — and when it does, a telemetry write must not
  /// be able to disturb emergency packet relay. Logging is observability,
  /// never a dependency of delivery.
  ///
  /// [disabled] lets the mesh test harness turn persistence off entirely
  /// so simulation runs don't touch platform storage at all.
  static bool disabled = false;

  Future<void> log({
    required RelayLogType type,
    required String packetId,
    required String detail,
  }) async {
    if (disabled) return;
    _collisionGuard = (_collisionGuard + 1) % 1000;
    final id = '${DateTime.now().millisecondsSinceEpoch}_$_collisionGuard';
    try {
      await _service.addEntry(
        RelayLogEntry(
          id: id,
          timestamp: DateTime.now(),
          type: type,
          packetId: packetId,
          detail: detail,
        ),
      );
    } catch (_) {
      // Swallowed on purpose — see doc comment above.
    }
  }

  Future<void> clearLog() => _service.clearLog();
}
