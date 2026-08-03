"""
Signature verification.

STATUS: Implemented (Day 5, Aug 3) -- Ed25519, per Vaibhav's (Mesh Lead)
confirmed scheme. See Day 5 log Section 4 for the full spec discussion;
this docstring covers the parts that matter for correctness.

Scheme (confirmed, do not re-derive):
- Asymmetric, per-device Ed25519. `sender_id` IS the hex-encoded Ed25519
  public key -- self-certifying, no registry/lookup needed to verify.
- This is DIFFERENT from the responder registry (GET /responders/keys),
  which is an AUTHORIZATION check that runs AFTER signature verification
  already passed -- see responder_service.py. Do not conflate the two.

Signed payload (confirmed field order -- do not deviate):
- Common (all packet types), 5 fields only: packet_id, sender_id, type,
  timestamp, nonce.
- Emergency adds: emergency_id, latitude, longitude, message, priority.
- Termination adds: emergency_id, responder_id.
- ttl, hop_count, protocol_version are NOT part of the signed payload --
  deliberately excluded because they change per relay hop, and the
  signature is computed once at origination. (An earlier version of this
  file mistakenly included them; that bug is fixed as of this rewrite.)

Serialization (plain pipe-separated string, NOT JSON -- mirrors Dart
string interpolation on the mesh side):
  packet_id|sender_id|type|timestamp|nonce|emergency_id|latitude|longitude|message|priority
  (termination: packet_id|sender_id|type|timestamp|nonce|emergency_id|responder_id)

Formatting details that matter for byte-exact matching:
- type/priority use the bare enum value (lowercase, e.g. "emergency",
  "high") -- this backend's PacketType.value / PriorityLevel.value
  already produce exactly this, no conversion needed.
- timestamp: use packet.timestamp EXACTLY as received (the raw string).
  Never re-parse/reformat it -- Dart's toIso8601String() format
  (microseconds, Z suffix) must be reproduced byte-for-byte, and the
  only safe way to do that is to never touch the original string.
- latitude/longitude: Dart's default double->string interpolation
  (shortest round-trip decimal). KNOWN UNVERIFIED RISK: Python's
  float-to-string also uses a shortest-round-trip algorithm and usually
  agrees with Dart's, but the two are NOT guaranteed byte-identical in
  every case (tie-breaking differences). Not yet tested against a real
  cross-language vector -- see Day 5 log Section 4e/4d.
- Any nullable field, if null, maps to the literal text "null" (Dart's
  universal null-interpolation behavior for $variable) -- not an empty
  string. Applies in practice mainly to responder_id on some
  termination packets.
- Signature encoding: hex string, lowercase, no separators.

No golden test vector exists yet (confirmed by Vaibhav) -- a real
hardware test produced a verified signed packet device-to-device, but
the UI only showed truncated values, so the full untruncated hex was
never captured. Until Vaibhav sends one from multi-hop testing, this
file is validated only by its own self-consistent sign/verify round-trip
tests (see tests/test_signature_service.py) -- that proves internal
correctness, NOT cross-language (Dart<->Python) byte-exactness.
"""

import binascii

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PublicKey,
)


def _dart_str(value) -> str:
    """
    Mimic Dart's `$variable` string interpolation for a single field:
    null -> the literal text "null" (Dart's universal null-interpolation
    behavior), everything else -> str(value). Used for the
    nullable/optional payload fields (mainly responder_id).
    """
    if value is None:
        return "null"
    return str(value)


def build_signed_payload(packet) -> str:
    """
    Reconstruct the exact pipe-separated string that the mesh device
    signed, per Day 5 log Section 4b/4c. Raises ValueError if packet.type
    is neither "emergency" nor "termination" (should be unreachable given
    PacketType is an enum, but fail loudly rather than silently signing
    the wrong thing).
    """
    packet_type = packet.type.value if hasattr(packet.type, "value") else packet.type

    common = [
        packet.packet_id,
        packet.sender_id,
        packet_type,
        packet.timestamp,  # raw string, never re-parsed -- see module docstring
        packet.nonce,
    ]

    if packet_type == "emergency":
        priority = (
            packet.priority.value
            if packet.priority is not None and hasattr(packet.priority, "value")
            else packet.priority
        )
        fields = common + [
            _dart_str(packet.emergency_id),
            _dart_str(packet.latitude),
            _dart_str(packet.longitude),
            _dart_str(packet.message),
            _dart_str(priority),
        ]
    elif packet_type == "termination":
        fields = common + [
            _dart_str(packet.emergency_id),
            _dart_str(packet.responder_id),
        ]
    else:
        raise ValueError(f"unknown packet type for signature payload: {packet_type!r}")

    return "|".join(fields)


def verify_signature(packet) -> bool:
    """
    Verify a packet's Ed25519 signature.

    sender_id is the hex-encoded Ed25519 public key (self-certifying --
    no lookup needed). Returns False for any failure mode (bad signature,
    malformed hex, wrong-length key, etc.) -- never raises, matching the
    rest of the codebase's defensive style (callers just branch on the
    bool).
    """
    try:
        public_key_bytes = binascii.unhexlify(packet.sender_id)
        signature_bytes = binascii.unhexlify(packet.signature)
        public_key = Ed25519PublicKey.from_public_bytes(public_key_bytes)
        payload = build_signed_payload(packet)
        public_key.verify(signature_bytes, payload.encode("utf-8"))
        return True
    except (InvalidSignature, ValueError, binascii.Error, TypeError):
        return False
