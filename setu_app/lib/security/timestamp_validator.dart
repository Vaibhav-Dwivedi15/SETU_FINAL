import 'security_constants.dart';
import 'security_exceptions.dart';

/// =============================================================
/// SETU Timestamp Validator
///
/// Purpose:
/// Validates packet timestamps to prevent replay attacks.
/// Every received packet must pass this validation before
/// further processing.
///
/// Author: Security Team
/// =============================================================

class TimestampValidator {
  const TimestampValidator();

  /// Validates the packet timestamp.
  ///
  /// Returns:
  /// - true if the timestamp is valid.
  ///
  /// Throws:
  /// - InvalidTimestampException
  /// - ExpiredPacketException
  bool validate(DateTime packetTimestamp) {
    // Always compare timestamps in UTC.
    final currentTime = DateTime.now().toUtc();
    final packetTime = packetTimestamp.toUtc();

    final packetAge = currentTime.difference(packetTime);

    // Packet timestamp is too far in the future.
    if (packetAge.isNegative &&
        packetAge.abs() > SecurityConstants.allowedClockSkew) {
      throw const InvalidTimestampException();
    }

    // Packet is older than the allowed replay window.
    if (packetAge > SecurityConstants.maxPacketAge) {
      throw const ExpiredPacketException();
    }

    return true;
  }

  /// Returns true if the packet is expired.
  bool isExpired(DateTime packetTimestamp) {
    final currentTime = DateTime.now().toUtc();
    final packetTime = packetTimestamp.toUtc();

    return currentTime.difference(packetTime) >
        SecurityConstants.maxPacketAge;
  }

  /// Returns the age of the packet.
  Duration packetAge(DateTime packetTimestamp) {
    final currentTime = DateTime.now().toUtc();
    final packetTime = packetTimestamp.toUtc();

    return currentTime.difference(packetTime);
  }
}