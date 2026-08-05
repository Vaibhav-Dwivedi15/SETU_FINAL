import 'dart:async';
import 'dart:developer' as developer;

/// Aug 5 2026: added a broadcast stream so a live relay-status screen
/// can react to counter changes instead of polling. The counters
/// themselves are unchanged (still plain ints incremented from
/// MeshService) -- callers that just do `MeshMetrics.instance.sent++`
/// keep working exactly as before. The new `notify()` call is what
/// pushes an update to any listening UI; MeshService calls it after
/// each counter change (see mesh_service.dart). Kept deliberately
/// simple (a single "something changed" tick, not per-field events) --
/// the relay screen just re-reads all five counters on each tick.
class MeshMetrics {
  MeshMetrics._();
  static final instance = MeshMetrics._();

  int sent = 0;
  int received = 0;
  int relayed = 0;
  int uploaded = 0;
  int dropped = 0;

  final _controller = StreamController<void>.broadcast();

  /// Emits after any counter changes, so live UI can rebuild. Purely
  /// additive -- nothing that increments the counters is required to
  /// call this, but MeshService does so the relay screen stays fresh.
  Stream<void> get changes => _controller.stream;

  /// Call after mutating any counter to push a UI refresh.
  void notify() {
    if (!_controller.isClosed) _controller.add(null);
  }

  void log() {
    developer.log(
      '''
Mesh Metrics
Sent      : $sent
Received  : $received
Relayed   : $relayed
Uploaded  : $uploaded
Dropped   : $dropped
''',
      name: 'MeshMetrics',
    );
  }

  void reset() {
    sent = 0;
    received = 0;
    relayed = 0;
    uploaded = 0;
    dropped = 0;
    notify();
  }
}
