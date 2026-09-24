"""
Cross-language request-signing vectors (Block 2). The SAME file
(docs/backend/contract/request_signing_vectors.json) is verified here by the
backend's canonicalisation and by setu_app/test/backend_contract_test.dart,
which must reproduce every signature byte for byte from the same seed
(Ed25519 is deterministic).

Regenerate deliberately: UPDATE_CONTRACT_FIXTURES=1 pytest tests/test_request_signing_vectors.py
"""

import json
import os
import pathlib

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from app.services.request_auth import body_hash, canonical_string
from tests.signing_helpers import pubkey_hex

VECTORS = pathlib.Path(__file__).resolve().parents[2] / "docs/backend/contract/request_signing_vectors.json"
SEED = bytes(range(32))  # 0x00..0x1f -- a fixture, not a production key
TS = "2026-09-24T10:30:15.123456Z"
NONCE = "000102030405060708090a0b0c0d0e0f"


def build():
    key = Ed25519PrivateKey.from_private_bytes(SEED)
    sender = pubkey_hex(key)
    register_body = json.dumps({
        "sender_id": sender, "name": "Asha Verma", "age": None, "gender": None,
        "medical_history": "Blood group: O+", "emergency_contacts": ["+919876543210"],
    }, separators=(",", ":"))
    audio = bytes(range(256)) * 4
    cases = [
        {"name": "register", "method": "POST", "path": "/register", "body_utf8": register_body,
         "parts": [body_hash(register_body.encode())]},
        {"name": "respond", "method": "POST", "path": "/alerts/7/respond",
         "body_utf8": '{"sender_id":"%s","response_type":"CAN_HELP"}' % sender, "parts": None},
        {"name": "nearby", "method": "GET", "path": "/alerts/nearby", "body_utf8": None,
         "parts": ["28.6139", "77.209", "2.0"]},
        {"name": "voice", "method": "POST", "path": "/ingest/voice", "body_utf8": None,
         "audio_bytes_hex": audio.hex(), "parts": [body_hash(audio), "28.6139", "77.209", "high", ""]},
    ]
    respond = cases[1]
    respond["parts"] = [body_hash(respond["body_utf8"].encode())]
    for case in cases:
        canonical = canonical_string(case["method"], case["path"], sender, TS, NONCE, case["parts"])
        case["canonical"] = canonical
        case["signature"] = key.sign(canonical.encode()).hex()
    return {"seed_hex": SEED.hex(), "sender_id": sender, "timestamp": TS, "nonce": NONCE, "cases": cases}


def test_vectors_are_current_and_verify():
    generated = build()
    if os.environ.get("UPDATE_CONTRACT_FIXTURES"):
        VECTORS.write_text(json.dumps(generated, indent=2) + "\n")
    stored = json.loads(VECTORS.read_text())
    assert stored == generated, "request_signing_vectors.json is stale; regenerate deliberately"

    pub = Ed25519PrivateKey.from_private_bytes(SEED).public_key()
    for case in stored["cases"]:
        pub.verify(bytes.fromhex(case["signature"]), case["canonical"].encode())  # raises on mismatch
        assert case["canonical"].startswith("setu-req-v1|" + case["method"] + "|" + case["path"] + "|")
