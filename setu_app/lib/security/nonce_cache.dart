import 'security_constants.dart';
import 'security_exceptions.dart';

/// =============================================================
/// SETU Nonce Cache
///
/// Purpose:
/// Prevents replay attacks by remembering previously seen
/// packet nonces for a limited period.
///
/// Author: Security Team
/// =============================================================

class NonceCache {
  NonceCache();

  /// nonce -> first seen time (UTC)
  final Map<String, DateTime> _cache = {};

  /// ============================================================
  /// Validate Nonce
  /// ============================================================
  ///
  /// Returns true if the nonce has never been seen.
  ///
  /// Throws:
  /// - DuplicateNonceException
  bool validate(String nonce) {
    _removeExpiredNonces();

    if (_cache.containsKey(nonce)) {
      throw const DuplicateNonceException();
    }

    _cache[nonce] = DateTime.now().toUtc();

    _trimCache();

    return true;
  }

  /// ============================================================
  /// Check without storing
  /// ============================================================
  bool contains(String nonce) {
    _removeExpiredNonces();
    return _cache.containsKey(nonce);
  }

  /// ============================================================
  /// Store nonce manually
  /// ============================================================
  void add(String nonce) {
    _removeExpiredNonces();

    _cache[nonce] = DateTime.now().toUtc();

    _trimCache();
  }

  /// ============================================================
  /// Remove expired entries
  /// ============================================================
  void _removeExpiredNonces() {
    final now = DateTime.now().toUtc();

    _cache.removeWhere(
      (_, timestamp) =>
          now.difference(timestamp) >
          SecurityConstants.nonceExpiry,
    );
  }

  /// ============================================================
  /// Keep cache size under control
  /// ============================================================
  void _trimCache() {
    while (_cache.length > SecurityConstants.maxNonceCacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// ============================================================
  /// Clear cache
  /// ============================================================
  void clear() {
    _cache.clear();
  }

  /// ============================================================
  /// Cache Size
  /// ============================================================
  int get size => _cache.length;

  /// ============================================================
  /// Cache Empty?
  /// ============================================================
  bool get isEmpty => _cache.isEmpty;

  /// ============================================================
  /// Cache Not Empty?
  /// ============================================================
  bool get isNotEmpty => _cache.isNotEmpty;
}