/// Snapshot of "is this device actually ready to carry mesh traffic
/// right now" — the preparedness-module counterpart to the one-time
/// onboarding permission gate (permission_gate_screen.dart).
///
/// Deliberately re-checkable on demand: onboarding only ever runs once,
/// but Bluetooth/location get turned off by users constantly (battery
/// saving, flights, habit), and a device that silently stopped being a
/// usable relay is exactly the kind of gap "preparedness" is supposed
/// to catch before a real emergency, not during one.
class ReadinessStatus {
  const ReadinessStatus({
    required this.permissionsGranted,
    required this.bluetoothEnabled,
    required this.wifiEnabled,
    required this.connectedPeers,
    required this.batteryLevel,
  });

  final bool permissionsGranted;
  final bool bluetoothEnabled;
  final bool wifiEnabled;

  /// From MeshServiceImpl.connectedPeerCount (added Priority 1/2 this
  /// session) — zero connected peers is normal (nobody nearby yet), not
  /// necessarily a problem, so it is shown as information, not a
  /// pass/fail check.
  final int connectedPeers;

  final int batteryLevel;

  /// Whether the device could actually carry emergency mesh traffic
  /// right now. Deliberately does NOT require connectedPeers > 0 —
  /// unlike mesh/services/mesh_health.dart's MeshHealth.healthy, which
  /// was written for "is the mesh currently doing useful work" and
  /// factors in queue depth. This is "is the DEVICE ready", which a
  /// phone with radios on and permissions granted can be even with
  /// nobody in range yet.
  bool get ready => permissionsGranted && bluetoothEnabled;

  List<String> get problems {
    final issues = <String>[];
    if (!permissionsGranted) {
      issues.add('SETU needs Bluetooth and location permission to relay emergencies.');
    }
    if (!bluetoothEnabled) {
      issues.add('Bluetooth is off. Turn it on so this phone can find nearby devices.');
    }
    if (!wifiEnabled) {
      issues.add('Wi-Fi is off. Some mesh connections use Wi-Fi Direct alongside Bluetooth.');
    }
    if (batteryLevel > 0 && batteryLevel <= 20) {
      issues.add('Battery is low — SETU reduces relay activity below 20% to protect it.');
    }
    return issues;
  }
}
