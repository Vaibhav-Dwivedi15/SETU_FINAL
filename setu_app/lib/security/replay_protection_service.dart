import 'nonce_cache.dart';
import 'timestamp_validator.dart';

/// =============================================================
/// SETU Replay Protection Service
///
/// Purpose:
/// Combines timestamp validation and nonce validation
/// to prevent replay attacks.
///
/// Every incoming packet must pass through this service
/// before it is accepted.
///
/// Author: Security Team
/// =============================================================

class ReplayProtectionService {
  ReplayProtectionService({
    TimestampValidator? timestampValidator,
    NonceCache? nonceCache,
  })  : _timestampValidator =
            timestampValidator ?? const TimestampValidator(),
        _nonceCache = nonceCache ?? NonceCache();

  final TimestampValidator _timestampValidator;
  final NonceCache _nonceCache;

  /// ============================================================
  /// Validate Packet
  /// ============================================================
  ///
  /// Validation Order:
  ///
  /// 1. Timestamp
  /// 2. Nonce
  ///
  /// Returns true if packet is safe.
  ///
  /// Throws:
  /// - InvalidTimestampException
  /// - ExpiredPacketException
  /// - DuplicateNonceException
  bool validate({
    required DateTime timestamp,
    required String nonce,
  }) {
    _timestampValidator.validate(timestamp);

    _nonceCache.validate(nonce);

    return true;
  }

  /// ============================================================
  /// Check Nonce Only
  /// ============================================================
  bool isNonceSeen(String nonce) {
    return _nonceCache.contains(nonce);
  }

  /// ============================================================
  /// Clear Cache
  /// ============================================================
  void clearCache() {
    _nonceCache.clear();
  }

  /// ============================================================
  /// Cache Statistics
  /// ============================================================
  int get cachedNonceCount => _nonceCache.size;

  bool get isCacheEmpty => _nonceCache.isEmpty;
}