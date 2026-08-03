class RelayStatistics {
  int packetsReceived = 0;
  int packetsRelayed = 0;
  int packetsDropped = 0;
  int uploadSuccess = 0;
  int uploadFailure = 0;

  double get relaySuccessRate {
    if (packetsReceived == 0) return 0;
    return packetsRelayed / packetsReceived;
  }

  double get uploadSuccessRate {
    final total = uploadSuccess + uploadFailure;
    if (total == 0) return 0;
    return uploadSuccess / total;
  }

  void reset() {
    packetsReceived = 0;
    packetsRelayed = 0;
    packetsDropped = 0;
    uploadSuccess = 0;
    uploadFailure = 0;
  }
}