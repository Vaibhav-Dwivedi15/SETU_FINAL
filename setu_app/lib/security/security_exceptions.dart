/// =============================================================
/// SETU Security Exceptions
///
/// Purpose:
/// Defines all security-related exceptions used by the
/// SETU security module.
///
/// Author: Security Team
/// =============================================================
library;

/// Base class for all security exceptions.
class SecurityException implements Exception {
  final String message;

  const SecurityException(this.message);

  @override
  String toString() => message;
}

/// =============================================================
/// Signature Exceptions
/// =============================================================

/// Invalid digital signature.
class InvalidSignatureException extends SecurityException {
  const InvalidSignatureException()
      : super("Invalid digital signature.");
}

/// Missing digital signature.
class MissingSignatureException extends SecurityException {
  const MissingSignatureException()
      : super("Missing digital signature.");
}

/// =============================================================
/// Replay Protection Exceptions
/// =============================================================

/// Packet replay detected.
class ReplayAttackException extends SecurityException {
  const ReplayAttackException()
      : super("Replay attack detected.");
}

/// Duplicate nonce detected.
class DuplicateNonceException extends SecurityException {
  const DuplicateNonceException()
      : super("Duplicate nonce detected.");
}

/// Nonce not found.
class NonceNotFoundException extends SecurityException {
  const NonceNotFoundException()
      : super("Nonce not found.");
}

/// =============================================================
/// Timestamp Exceptions
/// =============================================================

/// Packet timestamp expired.
class ExpiredPacketException extends SecurityException {
  const ExpiredPacketException()
      : super("Packet has expired.");
}

/// Packet timestamp is invalid.
class InvalidTimestampException extends SecurityException {
  const InvalidTimestampException()
      : super("Invalid packet timestamp.");
}

/// =============================================================
/// TTL Exceptions
/// =============================================================

/// Invalid TTL value.
class InvalidTTLException extends SecurityException {
  const InvalidTTLException()
      : super("Invalid TTL value.");
}

/// TTL expired.
class TTLExpiredException extends SecurityException {
  const TTLExpiredException()
      : super("Packet TTL expired.");
}

/// =============================================================
/// Packet Exceptions
/// =============================================================

/// Invalid packet format.
class InvalidPacketException extends SecurityException {
  const InvalidPacketException()
      : super("Invalid packet format.");
}

/// Packet version mismatch.
class UnsupportedPacketVersionException extends SecurityException {
  const UnsupportedPacketVersionException()
      : super("Unsupported packet version.");
}

/// Packet type is invalid.
class InvalidPacketTypeException extends SecurityException {
  const InvalidPacketTypeException()
      : super("Invalid packet type.");
}

/// Packet is too large.
class PacketTooLargeException extends SecurityException {
  const PacketTooLargeException()
      : super("Packet size exceeds the allowed limit.");
}