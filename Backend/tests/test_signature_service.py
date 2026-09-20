"""
Unit tests for signature_service.py -- Ed25519 verification per the
scheme Vaibhav (Mesh Lead) confirmed on Day 5.

IMPORTANT SCOPE NOTE: these tests prove the Python implementation is
internally self-consistent (sign with a real Ed25519 key here, verify
with the same code here) -- they do NOT prove cross-language byte-exact
compatibility with the actual Dart mesh client. No golden test vector
exists yet (see signature_service.py's module docstring and Day 5 log
Section 4e); add one here the moment Vaibhav sends real untruncated
hardware-test output.
"""

from types import SimpleNamespace

import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from app.services.signature_service import build_signed_payload, verify_signature


def _make_signed_packet(payload_obj, private_key):
    # sender_id IS part of the signed payload (Section 4b) -- it must be
    # set to the real hex pubkey BEFORE build_signed_payload() runs, or
    # the signature covers a different sender_id than the one shipped,
    # and verification will (correctly) fail.
    payload_obj.sender_id = private_key.public_key().public_bytes_raw().hex()
    payload = build_signed_payload(payload_obj)
    payload_obj.signature = private_key.sign(payload.encode("utf-8")).hex()
    return payload_obj


def _emergency_packet(**overrides):
    fields = dict(
        packet_id="p1",
        sender_id=None,  # filled in by _make_signed_packet
        type="emergency",
        timestamp="2026-08-02T12:00:00.000000Z",
        nonce="nonce-1",
        emergency_id="e1",
        latitude=28.6139,
        longitude=77.2090,
        message="fire near market",
        priority="high",
    )
    fields.update(overrides)
    return SimpleNamespace(**fields)


def _termination_packet(**overrides):
    fields = dict(
        packet_id="p2",
        sender_id=None,
        type="termination",
        timestamp="2026-08-02T12:05:00.000000Z",
        nonce="nonce-2",
        emergency_id="e1",
        responder_id="badge-123",
    )
    fields.update(overrides)
    return SimpleNamespace(**fields)


def test_valid_emergency_signature_accepted():
    private_key = Ed25519PrivateKey.generate()
    packet = _make_signed_packet(_emergency_packet(), private_key)
    assert verify_signature(packet) is True


def test_valid_termination_signature_accepted():
    private_key = Ed25519PrivateKey.generate()
    packet = _make_signed_packet(_termination_packet(), private_key)
    assert verify_signature(packet) is True


def test_termination_signature_accepted_with_null_responder_id():
    """
    responder_id is Optional -- a null value must serialize to the
    literal text "null" (Dart's universal null-interpolation behavior),
    not an empty string, and must still verify correctly.
    """
    private_key = Ed25519PrivateKey.generate()
    packet = _make_signed_packet(_termination_packet(responder_id=None), private_key)
    assert verify_signature(packet) is True


def test_tampered_payload_rejected():
    private_key = Ed25519PrivateKey.generate()
    packet = _make_signed_packet(_emergency_packet(), private_key)
    packet.message = "this was not the signed message"
    assert verify_signature(packet) is False


def test_wrong_key_rejected():
    """
    Signed by one device's key but sender_id claims a different device
    (a spoofing attempt) -- must be rejected.
    """
    signer_key = Ed25519PrivateKey.generate()
    claimed_key = Ed25519PrivateKey.generate()
    packet = _make_signed_packet(_emergency_packet(), signer_key)
    packet.sender_id = claimed_key.public_key().public_bytes_raw().hex()
    assert verify_signature(packet) is False


def test_malformed_hex_sender_id_rejected():
    private_key = Ed25519PrivateKey.generate()
    packet = _make_signed_packet(_emergency_packet(), private_key)
    packet.sender_id = "not-valid-hex!!"
    assert verify_signature(packet) is False


def test_malformed_hex_signature_rejected():
    private_key = Ed25519PrivateKey.generate()
    packet = _make_signed_packet(_emergency_packet(), private_key)
    packet.signature = "not-valid-hex!!"
    assert verify_signature(packet) is False


def test_ttl_hop_count_protocol_version_excluded_from_payload():
    """
    The exact bug this rewrite fixes: ttl/hop_count/protocol_version
    must NOT affect the signed payload, since they legitimately change
    per relay hop after signing. A packet whose ttl/hop_count changed
    after signing must still verify.
    """
    private_key = Ed25519PrivateKey.generate()
    packet = _emergency_packet()
    packet.ttl = 5
    packet.hop_count = 0
    packet.protocol_version = 1
    packet = _make_signed_packet(packet, private_key)

    # Simulate the packet having been relayed: ttl decremented, hop_count
    # incremented, well after the signature was computed.
    packet.ttl = 3
    packet.hop_count = 2

    assert verify_signature(packet) is True


def test_payload_excludes_ttl_hop_count_protocol_version_by_construction():
    """
    Directly asserts the built payload string has no way to encode
    ttl/hop_count/protocol_version, regardless of what verify_signature
    does with the result.
    """
    packet = _emergency_packet(sender_id="deadbeef")
    packet.ttl = 5
    packet.hop_count = 0
    packet.protocol_version = 1
    payload = build_signed_payload(packet)
    assert payload == (
        "p1|deadbeef|emergency|2026-08-02T12:00:00.000000Z|nonce-1|"
        "e1|28.6139|77.209|fire near market|high"
    )


def test_unknown_packet_type_raises():
    packet = _emergency_packet(type="something-else")
    with pytest.raises(ValueError):
        build_signed_payload(packet)
