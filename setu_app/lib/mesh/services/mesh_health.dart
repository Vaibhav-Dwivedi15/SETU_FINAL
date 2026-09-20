class MeshHealth {
  const MeshHealth({
    required this.connectedPeers,
    required this.pendingUploads,
    required this.pendingRelay,
    required this.batteryLevel,
  });

  final int connectedPeers;
  final int pendingUploads;
  final int pendingRelay;
  final int batteryLevel;

  bool get healthy =>
      connectedPeers > 0 &&
      batteryLevel > 20 &&
      pendingUploads < 100 &&
      pendingRelay < 100;
}