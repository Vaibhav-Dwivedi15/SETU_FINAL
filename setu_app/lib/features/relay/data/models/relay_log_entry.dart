// =====================================================
// SETU Project
// Module : Relay Log (persistent relay activity history)
// =====================================================
//
// Added Aug 6 2026. WHY THIS EXISTS: MeshMetrics is a plain in-memory
// singleton (int sent = 0, etc.) -- it was never designed to survive a
// process restart, so the Relay Status screen's numbers correctly
// reset to 0 every time the app is fully backgrounded-and-killed then
// reopened, which on Android can happen at any time. This mirrors
// HistoryModel/HistoryService/HistoryRepository's exact pattern
// (SharedPreferences-backed, capped list, most-recent-first) so relay
// activity survives app restarts the same way SOS history already
// does.
enum RelayLogType { sent, received, relayed, uploaded, dropped }

class RelayLogEntry {
  final String id;
  final DateTime timestamp;
  final RelayLogType type;
  final String packetId;
  final String detail;

  RelayLogEntry({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.packetId,
    required this.detail,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'type': type.name,
        'packetId': packetId,
        'detail': detail,
      };

  factory RelayLogEntry.fromJson(Map<String, dynamic> json) {
    return RelayLogEntry(
      id: json['id'],
      timestamp: DateTime.parse(json['timestamp']),
      type: RelayLogType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => RelayLogType.dropped,
      ),
      packetId: json['packetId'] ?? '',
      detail: json['detail'] ?? '',
    );
  }
}
