"""
SMS notification service.

BLOCK 2 -- SMS RESPONSIBILITY (see docs/backend/BLOCK2_FINAL_VALIDATION.md §11):
  * WHO SENDS: this backend gateway is the authoritative notifier once an SOS
    packet has been accepted by /ingest. The mobile app sends a direct SMS
    only when the backend did not confirm it queued SMS for all of the
    device's contacts (offline / backend unreachable / contact not registered).
  * WHEN: exactly once per newly created incident (never on merge).
  * TO WHOM: the emergency_contacts registered for the packet's sender_id.
  * IDEMPOTENCY: SmsNotification ledger, UNIQUE(event_key, contact_hash).
    A retry / duplicate upload / concurrent request re-attempts only contacts
    whose previous attempt FAILED at the gateway, never a queued one.
  * LOGGING: numbers are masked, message bodies are never logged.

STATUS: LIVE (SMS Gateway for Android, Cloud Server mode) -- sends a
real SMS to each emergency contact for a brand-new incident, routed
through Ayush's own Android phone and Jio SIM via the free, open-source
"SMS Gateway for Android" app (https://sms-gate.app), instead of a paid
third-party SMS provider.

Why this over Fast2SMS: Fast2SMS requires a non-refundable minimum
wallet top-up (Rs 100) before any send is even possible, on top of the
per-SMS charge and a manual approval step per message on the Quick SMS
route -- real friction for a zero-budget student project. SMS Gateway
for Android's Cloud Server mode is genuinely free (no card, no
registration, no per-message minimum -- confirmed via their own pricing
page, which guarantees free Cloud Server access stays free), open
source, and uses the existing phone plan's SMS quota. Confirmed working
end-to-end on Aug 2 (real SMS delivered).

Trade-off: the phone must stay on, unlocked/connected to the internet,
with the app running in Cloud Server "Online" mode, for sends to
actually go out -- fine for a hackathon demo, not a real production
posture. Worth remembering before a live demo: check the phone is
online beforehand.

Swapping providers later should only require editing send_sms() below
-- every caller goes through notify_emergency_contacts(), so nothing
else in the codebase needs to change.

Docs: https://docs.sms-gate.app/getting-started/public-cloud-server/
"""

import hashlib
import logging

import httpx
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.sms_notification import SmsNotification

logger = logging.getLogger("setu.sms")

SMS_GATEWAY_URL = "https://api.sms-gate.app/3rdparty/v1/messages"


def _to_e164(phone_number: str) -> str:
    """
    Normalizes a phone number to E.164 format, which the gateway
    requires (e.g. +919876543210). Assumes any number without a '+'
    is a 10-digit Indian mobile number missing its country code.
    """
    digits = "".join(ch for ch in phone_number if ch.isdigit())
    if phone_number.strip().startswith("+"):
        return "+" + digits
    if len(digits) == 10:
        return f"+91{digits}"
    if len(digits) == 12 and digits.startswith("91"):
        return f"+{digits}"
    return f"+{digits}"  # best-effort fallback for anything unexpected


def _mask(phone_number: str) -> str:
    digits = "".join(ch for ch in phone_number if ch.isdigit())
    return f"***{digits[-2:]}" if len(digits) >= 2 else "***"


def _contact_hash(phone_number: str) -> str:
    return hashlib.sha256(_to_e164(phone_number).encode("utf-8")).hexdigest()


def send_sms(to_number: str, message: str) -> bool:
    """
    Sends one SMS via SMS Gateway for Android's Cloud Server API.
    Returns True only once the gateway server ACCEPTS the request (the
    message then goes to "Pending" until the phone itself is online and
    actually sends it -- this does not guarantee delivery, only that the
    request was queued). A network error, timeout, or non-2xx response
    returns False rather than raising, so one failed SMS never crashes
    the /ingest request that triggered it.
    """
    if not settings.sms_gateway_username or not settings.sms_gateway_password:
        logger.warning("[SMS] gateway credentials not set -- not sending to %s", _mask(to_number))
        return False

    payload = {
        "textMessage": {"text": message},
        "phoneNumbers": [_to_e164(to_number)],
    }

    try:
        response = httpx.post(
            SMS_GATEWAY_URL,
            auth=(settings.sms_gateway_username, settings.sms_gateway_password),
            json=payload,
            timeout=10.0,
        )
        response.raise_for_status()
        data = response.json()
    except (httpx.HTTPError, ValueError) as exc:
        logger.error("[SMS] gateway request failed for %s: %s", _mask(to_number), type(exc).__name__)
        return False

    logger.info("[SMS] queued for %s (message id=%s, state=%s)", _mask(to_number), data.get("id"), data.get("state"))
    return True


def count_notified(db: Session, event_key: str) -> int:
    """How many contacts the ledger says are handled (queued or in flight) for this event."""
    return (
        db.query(SmsNotification)
        .filter(SmsNotification.event_key == event_key, SmsNotification.status.in_(("queued", "pending")))
        .count()
    )


def notify_emergency_contacts(
    db: Session,
    event_key: str,
    sender_name: str,
    contacts: list[str],
    incident_type: str,
    incident_id: int,
) -> int:
    """
    Idempotently notify each contact for `event_key`. Returns the number of
    contacts now handled by the backend (queued or in flight), including
    ones handled by an earlier call.

    Claim protocol per contact: INSERT a 'pending' ledger row (UNIQUE) -- only
    the inserter sends. A previous 'failed' row is re-claimed with a
    conditional UPDATE so two concurrent retries cannot both send.
    """
    if not contacts:
        logger.info("[SMS] no emergency contacts on file for incident %s, skipping.", incident_id)
        return 0

    message = (
        f"SETU Alert: {sender_name} has reported a {incident_type} emergency "
        f"(Incident #{incident_id}). This is an automated safety notification."
    )

    seen_hashes = set()
    for contact in contacts:
        contact_hash = _contact_hash(contact)
        if contact_hash in seen_hashes:  # same number listed twice
            continue
        seen_hashes.add(contact_hash)

        if not _claim(db, event_key, contact_hash):
            continue  # already queued/in flight from an earlier attempt

        ok = False
        try:
            ok = send_sms(contact, message)
        finally:
            _finish(db, event_key, contact_hash, "queued" if ok else "failed")

    return count_notified(db, event_key)


def _claim(db: Session, event_key: str, contact_hash: str) -> bool:
    try:
        db.add(SmsNotification(event_key=event_key, contact_hash=contact_hash, status="pending"))
        db.commit()
        return True
    except IntegrityError:
        db.rollback()

    # Row exists. Only a FAILED attempt may be retried, and only one caller wins.
    claimed = (
        db.query(SmsNotification)
        .filter(
            SmsNotification.event_key == event_key,
            SmsNotification.contact_hash == contact_hash,
            SmsNotification.status == "failed",
        )
        .update({"status": "pending"}, synchronize_session=False)
    )
    db.commit()
    return claimed == 1


def _finish(db: Session, event_key: str, contact_hash: str, status: str) -> None:
    try:
        db.query(SmsNotification).filter(
            SmsNotification.event_key == event_key,
            SmsNotification.contact_hash == contact_hash,
        ).update({"status": status}, synchronize_session=False)
        db.commit()
    except Exception:
        db.rollback()
        logger.exception("[SMS] could not record ledger status")
