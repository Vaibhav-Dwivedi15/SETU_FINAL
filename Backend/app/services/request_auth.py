"""
Proof-of-possession for non-mesh requests (Block 2), using the device's
EXISTING Ed25519 identity key. No passwords, no private keys stored or sent.

Every protected request carries four headers:

  X-Setu-Sender     hex Ed25519 public key (== sender_id, 64 hex chars)
  X-Setu-Timestamp  ISO-8601 with zone (same format/parser as packets)
  X-Setu-Nonce      client-chosen unique value, 16-128 chars [A-Za-z0-9_-]
  X-Setu-Signature  lowercase hex Ed25519 signature over the CANONICAL STRING

  canonical = "setu-req-v1|METHOD|/path|sender_id|timestamp|nonce|<part>|<part>..."

`parts` are endpoint-specific and bind the request's content so a signature
for one request cannot be reused for another:

  POST /register            [sha256_hex(raw request body)]
  POST /alerts/{id}/respond [sha256_hex(raw request body)]
  GET  /alerts/nearby       [lat_string, lon_string, radius_string_or_""]  (raw query strings)
  POST /ingest/voice        [sha256_hex(audio bytes), lat_string, lon_string,
                             priority_or_"", emergency_id_or_""]           (raw form strings)

Properties enforced here:
  * possession  -- the signature verifies under the public key in X-Setu-Sender;
                   the endpoint then requires that key to equal the identity it acts for
  * freshness   -- |now - timestamp| <= SIGNED_REQUEST_WINDOW_SECONDS
  * no replay   -- UNIQUE(sender_id, nonce) in signed_request_nonces
  * domain separation -- the "setu-req-v1|GET/POST|..." prefix can never parse as a
                   mesh packet signing payload (its 3rd field would have to be the
                   packet type, and "GET"/"POST" are not packet types), so a request
                   signature cannot be replayed as a packet signature or vice versa.

Failure statuses: 401 for missing/invalid/replayed/stale authentication,
400 for structurally malformed header values.
"""

import binascii
import hashlib
import logging
import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Optional, Sequence

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from fastapi import Depends, Header, HTTPException, Request
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.contract import SIGNED_REQUEST_WINDOW_SECONDS
from app.core.timeutil import age_seconds, parse_timestamp
from app.db.base import get_db
from app.models.signed_request_nonce import SignedRequestNonce

logger = logging.getLogger("setu.request_auth")

DOMAIN = "setu-req-v1"
_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_HEX128 = re.compile(r"^[0-9a-f]{128}$")
_NONCE = re.compile(r"^[A-Za-z0-9_-]{16,128}$")


@dataclass
class SignedHeaders:
    sender_id: Optional[str]
    timestamp: Optional[str]
    nonce: Optional[str]
    signature: Optional[str]


def signed_headers(
    x_setu_sender: Optional[str] = Header(default=None),
    x_setu_timestamp: Optional[str] = Header(default=None),
    x_setu_nonce: Optional[str] = Header(default=None),
    x_setu_signature: Optional[str] = Header(default=None),
) -> SignedHeaders:
    return SignedHeaders(x_setu_sender, x_setu_timestamp, x_setu_nonce, x_setu_signature)


def is_valid_sender_key(sender_id: Optional[str]) -> bool:
    return bool(sender_id) and bool(_HEX64.match(sender_id))


def body_hash(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_string(method: str, path: str, sender_id: str, timestamp: str, nonce: str, parts: Sequence[str]) -> str:
    return "|".join([DOMAIN, method.upper(), path, sender_id, timestamp, nonce, *parts])


def verify_signed_request(
    db: Session, headers: SignedHeaders, method: str, path: str, parts: Sequence[str]
) -> str:
    """Returns the authenticated sender_id (public key hex) or raises HTTPException."""
    if not all([headers.sender_id, headers.timestamp, headers.nonce, headers.signature]):
        raise HTTPException(status_code=401, detail="Missing request signature headers (X-Setu-Sender/Timestamp/Nonce/Signature).")
    if not is_valid_sender_key(headers.sender_id):
        raise HTTPException(status_code=400, detail="X-Setu-Sender must be a 64-character lowercase hex Ed25519 public key.")
    if not _NONCE.match(headers.nonce):
        raise HTTPException(status_code=400, detail="X-Setu-Nonce must be 16-128 characters of [A-Za-z0-9_-].")
    if not _HEX128.match(headers.signature):
        raise HTTPException(status_code=400, detail="X-Setu-Signature must be 128 lowercase hex characters.")
    try:
        sent_at = parse_timestamp(headers.timestamp)
    except ValueError:
        raise HTTPException(status_code=400, detail="X-Setu-Timestamp must be ISO-8601 with an explicit zone.")

    skew = abs(age_seconds(sent_at))
    if skew > SIGNED_REQUEST_WINDOW_SECONDS:
        raise HTTPException(status_code=401, detail="Request timestamp outside the accepted window.")

    message = canonical_string(method, path, headers.sender_id, headers.timestamp, headers.nonce, parts)
    try:
        Ed25519PublicKey.from_public_bytes(binascii.unhexlify(headers.sender_id)).verify(
            binascii.unhexlify(headers.signature), message.encode("utf-8")
        )
    except (InvalidSignature, ValueError, binascii.Error):
        raise HTTPException(status_code=401, detail="Invalid request signature.")

    # Signature is valid -- only NOW consume the nonce (unauthenticated garbage cannot fill the table).
    try:
        cutoff = datetime.now(timezone.utc) - timedelta(seconds=2 * SIGNED_REQUEST_WINDOW_SECONDS)
        db.query(SignedRequestNonce).filter(SignedRequestNonce.created_at < cutoff).delete(synchronize_session=False)
        db.add(SignedRequestNonce(sender_id=headers.sender_id, nonce=headers.nonce))
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=401, detail="Request nonce already used (replay).")

    return headers.sender_id


async def require_signed_body(
    request: Request,
    db: Session = Depends(get_db),
    headers: SignedHeaders = Depends(signed_headers),
) -> str:
    """Dependency for JSON-body endpoints: signature covers sha256(raw body)."""
    raw = await request.body()
    return verify_signed_request(db, headers, request.method, request.url.path, [body_hash(raw)])
