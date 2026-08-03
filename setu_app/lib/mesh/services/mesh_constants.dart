class MeshConstants {
  const MeshConstants._();

  // NOTE: Must stay in sync with SecurityConstants.maxTTL / defaultTTL
  // (lib/security/security_constants.dart). TTL was corrected project-wide
  // from 8 -> 5; these were left stale here even though nothing currently
  // imports them. Actual packet creation uses SecurityConstants.defaultTTL
  // directly (see lib/screens/home/home_screen.dart) — these two constants
  // are currently unused dead code, kept only for any future relay-engine
  // code that references MeshConstants instead of SecurityConstants.
  static const defaultTtl = 5;
  static const maxHopCount = 5;

  static const maxRelayQueue = 500;

  static const maxRetryAttempts = 5;

  static const uploadInterval = Duration(seconds: 30);

  static const cacheExpiry = Duration(minutes: 30);

  static const metricsInterval = Duration(minutes: 5);

  static const duplicateCacheSize = 1000;
}