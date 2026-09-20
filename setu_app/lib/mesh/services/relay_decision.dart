class RelayDecision {
  const RelayDecision({
    required this.relay,
    required this.upload,
    required this.reason,
  });

  final bool relay;
  final bool upload;
  final String reason;
}