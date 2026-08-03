"""
SMS notification service.

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

import logging

import httpx

from app.core.config import settings

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
        logger.warning(
            f"[SMS] SMS_GATEWAY_USERNAME/PASSWORD not set in .env -- would send to {to_number}: {message}"
        )
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
        logger.error(f"[SMS] SMS Gateway request failed for {to_number}: {exc}")
        return False

    logger.info(f"[SMS] Queued for {to_number} (message id={data.get('id')}, state={data.get('state')})")
    return True


def notify_emergency_contacts(sender_name: str, contacts: list[str], incident_type: str, incident_id: int) -> None:
    """
    Called when a brand-new incident is created (never on a dedup merge).
    Sends one SMS per emergency contact.
    """
    if not contacts:
        logger.info(f"[SMS] No emergency contacts on file for incident {incident_id}, skipping.")
        return

    message = (
        f"SETU Alert: {sender_name} has reported a {incident_type} emergency "
        f"(Incident #{incident_id}). This is an automated safety notification."
    )

    for contact in contacts:
        send_sms(contact, message)