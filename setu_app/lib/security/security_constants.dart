/// =============================================================
/// SETU Security Constants
///
/// Purpose:
/// Stores all security-related constant values in one place.
/// Every security module should import this file instead of
/// hardcoding values.
///
/// Author: Security Team
/// =============================================================
library;
class SecurityConstants {
  // Prevent creating an object of this class.
  SecurityConstants._();

  // ============================================================
  // Replay Protection
  // ============================================================

  /// Maximum allowed packet age.
  /// Packets older than this will be rejected.
  static const Duration maxPacketAge = Duration(minutes: 5);

  /// Maximum allowed replay validation window.
  static const Duration replayWindow = Duration(minutes: 5);

  /// Maximum allowed clock difference between devices.
  /// Helps avoid rejecting packets due to small clock mismatch.
  static const Duration allowedClockSkew = Duration(seconds: 30);

  /// Use UTC timestamps throughout the application.
  static const bool useUtcTimestamp = true;

  // ============================================================
  // Nonce Cache
  // ============================================================

  /// Maximum number of nonces stored in memory.
  static const int maxNonceCacheSize = 500;

  /// Remove nonce after this duration.
  static const Duration nonceExpiry = Duration(minutes: 10);

  // ============================================================
  // TTL
  // ============================================================

  /// Default TTL assigned to a newly created packet.
  static const int defaultTTL = 5;

  /// Maximum allowed TTL.
  static const int maxTTL = 5;

  /// Minimum valid TTL.
  static const int minimumTTL = 1;

  // ============================================================
  // Digital Signature
  // ============================================================

  /// Signature algorithm used by SETU.
  static const String signatureAlgorithm = "Ed25519";

  // ============================================================
  // Packet
  // ============================================================

  /// Current packet format version.
  static const int packetVersion = 1;

  /// Maximum packet size in bytes.
  /// Change this if packet structure changes.
  static const int maxPacketSize = 4096;

  // ============================================================
  // Packet Types
  // ============================================================

  static const String emergencyPacket = "EMERGENCY";

  static const String terminationPacket = "TERMINATION";

  static const String acknowledgementPacket = "ACK";

  // ============================================================
  // Logging
  // ============================================================

  /// Enable or disable security logs.
  /// Keep false in production.
  static const bool enableSecurityLogs = false;
}