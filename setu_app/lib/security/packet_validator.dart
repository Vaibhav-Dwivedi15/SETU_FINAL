import 'replay_protection_service.dart';
import 'security_constants.dart';
import 'security_exceptions.dart';

/// =============================================================
/// SETU Packet Validator
///
/// Purpose:
/// Central validator for incoming packets.
///
/// Validation Order:
/// 1. Packet Version
/// 2. TTL
/// 3. Replay Protection
///
/// Signature verification is performed separately by
/// SigningService inside the application.
///
/// Author: Security Team
/// =============================================================

class PacketValidator {
  PacketValidator({
    ReplayProtectionService? replayProtectionService,
  }) : _replayProtectionService =
            replayProtectionService ?? ReplayProtectionService();

  final ReplayProtectionService _replayProtectionService;

  /// ============================================================
  /// Validate Packet
  /// ============================================================
  ///
  /// Returns true if packet passes all security checks.
  ///
  /// Throws:
  /// - InvalidPacketException
  /// - UnsupportedPacketVersionException
  /// - InvalidTTLException
  /// - ExpiredPacketException
  /// - InvalidTimestampException
  /// - DuplicateNonceException
  bool validate({
    required int packetVersion,
    required int ttl,
    required DateTime timestamp,
    required String nonce,
  }) {
    // ----------------------------------------------------------
    // Packet Version
    // ----------------------------------------------------------

    if (packetVersion != SecurityConstants.packetVersion) {
      throw const UnsupportedPacketVersionException();
    }

    // ----------------------------------------------------------
    // TTL Validation
    // ----------------------------------------------------------

    if (ttl < SecurityConstants.minimumTTL ||
        ttl > SecurityConstants.maxTTL) {
      throw const InvalidTTLException();
    }

    // ----------------------------------------------------------
    // Replay Protection
    // ----------------------------------------------------------

    _replayProtectionService.validate(
      timestamp: timestamp,
      nonce: nonce,
    );

    return true;
  }

  /// ============================================================
  /// Clear Replay Cache
  /// ============================================================

  void clearReplayCache() {
    _replayProtectionService.clearCache();
  }

  /// ============================================================
  /// Cached Nonce Count
  /// ============================================================

  int get cachedNonceCount =>
      _replayProtectionService.cachedNonceCount;
}