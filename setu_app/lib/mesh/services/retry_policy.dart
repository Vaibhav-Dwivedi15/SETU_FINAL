class RetryPolicy {
  RetryPolicy({
    this.initialDelay = const Duration(seconds: 5),
    this.maxDelay = const Duration(seconds: 60),
  });

  final Duration initialDelay;
  final Duration maxDelay;

  Duration nextDelay(int attempt) {
    if (attempt <= 0) return initialDelay;

    final seconds = initialDelay.inSeconds * (1 << (attempt - 1));

    return Duration(
      seconds: seconds > maxDelay.inSeconds
          ? maxDelay.inSeconds
          : seconds,
    );
  }
}