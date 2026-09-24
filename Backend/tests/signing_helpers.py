"""
Test helpers for Block 2 signed requests (registration, nearby alerts, respond,
voice). Mirrors services/request_auth.py's canonical string exactly -- and, as
the Dart side must too, signs the RAW strings that are sent on the wire.
"""

import hashlib
import json
import secrets
from datetime import datetime, timezone

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

DOMAIN = "setu-req-v1"


def pubkey_hex(private_key: Ed25519PrivateKey) -> str:
    return private_key.public_key().public_bytes_raw().hex()


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def sign_request(private_key, method, path, parts, *, timestamp=None, nonce=None, sender=None) -> dict:
    sender = sender or pubkey_hex(private_key)
    timestamp = timestamp or now_iso()
    nonce = nonce or secrets.token_hex(16)
    message = "|".join([DOMAIN, method.upper(), path, sender, timestamp, nonce, *parts])
    return {
        "X-Setu-Sender": sender,
        "X-Setu-Timestamp": timestamp,
        "X-Setu-Nonce": nonce,
        "X-Setu-Signature": private_key.sign(message.encode("utf-8")).hex(),
    }


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def signed_json_post(client, private_key, path, payload: dict, **overrides):
    body = json.dumps(payload).encode("utf-8")
    headers = sign_request(private_key, "POST", path, [sha(body)], **overrides)
    headers["Content-Type"] = "application/json"
    return client.post(path, content=body, headers=headers)


def register_profile(client, private_key, name="Test User", contacts=None, **overrides):
    payload = {
        "sender_id": pubkey_hex(private_key),
        "name": name,
        "emergency_contacts": contacts or [],
    }
    return signed_json_post(client, private_key, "/register", payload, **overrides)


def signed_nearby(client, private_key, params: dict, **overrides):
    raw = {k: str(v) for k, v in params.items()}
    parts = [raw.get("lat", ""), raw.get("lon", ""), raw.get("radius_km", "")]
    headers = sign_request(private_key, "GET", "/alerts/nearby", parts, **overrides)
    return client.get("/alerts/nearby", params=raw, headers=headers)


def signed_voice(client, private_key, audio: bytes, *, filename="sos.wav", content_type="audio/wav",
                 lat="28.6139", lon="77.2090", priority=None, emergency_id=None, form_extra=None, **overrides):
    parts = [sha(audio), lat, lon, priority or "", emergency_id or ""]
    headers = sign_request(private_key, "POST", "/ingest/voice", parts, **overrides)
    data = {"latitude": lat, "longitude": lon}
    if priority is not None:
        data["priority"] = priority
    if emergency_id is not None:
        data["emergency_id"] = emergency_id
    data.update(form_extra or {})
    return client.post("/ingest/voice", data=data, files={"file": (filename, audio, content_type)}, headers=headers)
