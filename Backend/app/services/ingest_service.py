"""
Per-packet /ingest pipeline with explicit, deterministic outcomes (Block 2).

Every packet in a batch ends in exactly ONE of four states, and the HTTP
status of the batch response says nothing about any individual packet
(HTTP success != packet acceptance):

  ACCEPTED   authenticated, fresh, well-formed, processed (incident created /
             merged / closed). The backend now holds this packet.
  DUPLICATE  this EXACT authenticated packet (same sender_id, packet_id AND
             signed content) was already accepted earlier. The backend holds
             it, so the client may treat it as delivered.
  REJECTED   the backend will never accept this packet as sent (malformed,
             oversized, unsupported type, bad TTL, bad/forged signature, stale,
             future-dated, packet_id reused with different content,
             unauthorized responder). NOT delivered; retrying is pointless.
  FAILED     a server-side error prevented a decision. NOT delivered; the
             client SHOULD retry later (retryable=true).

Order of checks (cheapest first, and AUTHENTICATION BEFORE DEDUP -- this is
the packet-ID-squatting fix: an unauthenticated packet can never occupy or
suppress a packet_id):

  size -> type -> schema/TTL -> timestamp -> signature -> dedup identity ->
  store -> route by type

Only packets that passed the signature check are ever written to raw_packets;
refusals are recorded in rejected_packets, which dedup never consults.
"""

import json
import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Optional

from pydantic import ValidationError
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.contract import (
    INGEST_ACCEPTED_TYPES,
    MAX_PACKET_BYTES,
    PACKET_MAX_AGE_SECONDS,
    PACKET_MAX_FUTURE_SKEW_SECONDS,
    PACKET_TTL_MAX,
    PACKET_TTL_MIN,
)
from app.core.timeutil import age_seconds, parse_timestamp
from app.models.audit_log import AuditAction, IncidentAuditLog
from app.models.incident import Incident
from app.models.packet import PacketStatus, RawPacket, RejectedPacket
from app.schemas.packet import PacketIn, PacketType
from app.services.ai_analysis_service import analyze as ai_analyze
from app.services.incident_service import (
    close_incident_by_emergency_id,
    process_sos_packet,
    send_incident_notifications,
    sms_event_key,
)
from app.services.responder_service import is_authorized_responder
from app.services.signature_service import build_signed_payload, verify_signature
from app.services.sms_service import count_notified

logger = logging.getLogger("setu.ingest")

MESH_ONLY_TYPES = ("ack", "alert")


class PacketState(str, Enum):
    ACCEPTED = "ACCEPTED"
    DUPLICATE = "DUPLICATE"
    REJECTED = "REJECTED"
    FAILED = "FAILED"


@dataclass
class PacketResult:
    packet_id: str
    state: PacketState
    code: Optional[str] = None
    reason: Optional[str] = None
    detail: dict = field(default_factory=dict)

    def as_dict(self) -> dict:
        out: dict[str, Any] = {"packet_id": self.packet_id, "status": self.state.value}
        if self.code:
            out["code"] = self.code
        if self.reason:
            out["reason"] = self.reason
        if self.state == PacketState.FAILED:
            out["retryable"] = True
        out.update(self.detail)
        return out


def _rejected(packet_id: str, code: str, reason: str) -> PacketResult:
    return PacketResult(packet_id, PacketState.REJECTED, code, reason)


def _echo_id(raw_packet: Any) -> str:
    """packet_id to echo back for a possibly-malformed packet (bounded, always a str)."""
    if isinstance(raw_packet, dict):
        value = raw_packet.get("packet_id")
        if isinstance(value, (str, int)) and str(value):
            return str(value)[:256]
    return "unknown"


def _record_rejection(db: Session, raw_packet: Any, result: PacketResult) -> None:
    """Best-effort audit row; never lets an audit failure change the outcome."""
    try:
        sender = raw_packet.get("sender_id") if isinstance(raw_packet, dict) else None
        db.add(RejectedPacket(
            packet_id=result.packet_id[:64],
            sender_id=str(sender)[:64] if isinstance(sender, str) else None,
            code=(result.code or "rejected")[:48],
            reason=(result.reason or "")[:200],
        ))
        db.commit()
    except Exception:
        db.rollback()
        logger.warning("could not record rejected packet %s", result.packet_id[:16])


def build_raw_packet(packet: PacketIn, status: PacketStatus) -> RawPacket:
    return RawPacket(
        **packet.model_dump(exclude={"incident_type", "type", "priority"}),
        incident_type=packet.incident_type.value if packet.incident_type else None,
        type=packet.type.value,
        priority=packet.priority.value if packet.priority else None,
        status=status,
    )


def first_validation_error(exc: ValidationError) -> tuple[str, str]:
    errors = exc.errors()
    if not errors:
        return "schema", str(exc)[:200]
    first = errors[0]
    field_path = ".".join(str(loc) for loc in first.get("loc", ())) or "unknown field"
    code = "invalid_ttl" if field_path == "ttl" else "schema"
    return code, f"{field_path}: {first.get('msg', 'invalid value')}"[:200]


def validate_packet(raw_packet: Any) -> tuple[Optional[PacketIn], Optional[PacketResult]]:
    """Stateless checks: size, type, schema, TTL, timestamp. Returns (packet, None) or (None, rejection)."""
    packet_id = _echo_id(raw_packet)

    if not isinstance(raw_packet, dict):
        return None, _rejected(packet_id, "malformed", "packet must be a JSON object")

    try:
        size = len(json.dumps(raw_packet, separators=(",", ":"), ensure_ascii=False).encode("utf-8"))
    except (TypeError, ValueError):
        return None, _rejected(packet_id, "malformed", "packet is not serialisable JSON")
    if size > MAX_PACKET_BYTES:
        return None, _rejected(packet_id, "too_large", f"packet is {size} bytes (max {MAX_PACKET_BYTES})")

    ptype = raw_packet.get("type")
    if not isinstance(ptype, str) or ptype not in INGEST_ACCEPTED_TYPES:
        if isinstance(ptype, str) and ptype in MESH_ONLY_TYPES:
            return None, _rejected(packet_id, "unsupported_type", f"packet type '{ptype}' is mesh-only and not accepted by /ingest")
        shown = ptype[:32] if isinstance(ptype, str) else type(ptype).__name__
        return None, _rejected(packet_id, "unknown_type", f"unknown packet type {shown!r} (accepted: {', '.join(INGEST_ACCEPTED_TYPES)})")

    try:
        packet = PacketIn.model_validate(raw_packet)
    except ValidationError as exc:
        code, reason = first_validation_error(exc)
        return None, _rejected(packet_id, code, f"schema validation failed ({reason})")

    if not (PACKET_TTL_MIN <= packet.ttl <= PACKET_TTL_MAX):
        return None, _rejected(packet.packet_id, "invalid_ttl", f"ttl {packet.ttl} outside {PACKET_TTL_MIN}..{PACKET_TTL_MAX}")

    if not packet.emergency_id:
        return None, _rejected(packet.packet_id, "schema", "emergency_id is required")

    try:
        sent_at = parse_timestamp(packet.timestamp)
    except ValueError as exc:
        return None, _rejected(packet.packet_id, "invalid_timestamp", str(exc))
    age = age_seconds(sent_at)
    if age > PACKET_MAX_AGE_SECONDS:
        return None, _rejected(packet.packet_id, "stale", f"packet is {int(age)}s old (max {PACKET_MAX_AGE_SECONDS}s)")
    if age < -PACKET_MAX_FUTURE_SKEW_SECONDS:
        return None, _rejected(packet.packet_id, "future_timestamp", f"timestamp is {int(-age)}s in the future (max skew {PACKET_MAX_FUTURE_SKEW_SECONDS}s)")

    return packet, None


def _classify_existing(existing: RawPacket, packet: PacketIn) -> PacketResult:
    """Same (sender_id, packet_id) already accepted: exact repeat -> DUPLICATE, anything else -> REJECTED."""
    try:
        same_content = build_signed_payload(existing) == build_signed_payload(packet)
    except ValueError:
        same_content = False
    if not same_content:
        return _rejected(
            packet.packet_id, "packet_id_conflict",
            "packet_id was already used by this sender for different signed content",
        )
    detail: dict[str, Any] = {}
    if existing.type == "emergency":
        detail["incident_id"] = existing.incident_id
    return PacketResult(packet.packet_id, PacketState.DUPLICATE, "duplicate", "duplicate packet_id (identical packet already accepted)", detail)


def _duplicate_extras(db: Session, existing: RawPacket, result: PacketResult) -> None:
    """For a duplicate emergency: retry failed SMS (idempotent) and report how many contacts the backend covers."""
    if existing.type != "emergency" or existing.incident_id is None:
        return
    try:
        created_here = (
            db.query(IncidentAuditLog.id)
            .filter(
                IncidentAuditLog.incident_id == existing.incident_id,
                IncidentAuditLog.packet_id == existing.packet_id,
                IncidentAuditLog.action == AuditAction.CREATED,
            )
            .first()
        )
        if created_here:
            incident = db.query(Incident).filter(Incident.id == existing.incident_id).first()
            if incident:
                send_incident_notifications(db, incident, existing.sender_id)
        result.detail["sms_contacts_notified"] = count_notified(db, sms_event_key(existing.incident_id))
    except Exception:
        db.rollback()
        logger.exception("duplicate-path notification retry failed")


def _existing_identity(db: Session, packet: PacketIn) -> Optional[RawPacket]:
    return (
        db.query(RawPacket)
        .filter(RawPacket.sender_id == packet.sender_id, RawPacket.packet_id == packet.packet_id)
        .first()
    )


def process_packet(db: Session, raw_packet: Any) -> PacketResult:
    packet, rejection = validate_packet(raw_packet)
    if rejection:
        _record_rejection(db, raw_packet, rejection)
        return rejection

    # AUTHENTICATE before touching dedup state (packet-ID squatting fix).
    if not verify_signature(packet):
        result = _rejected(packet.packet_id, "invalid_signature", "invalid signature")
        _record_rejection(db, raw_packet, result)
        return result

    try:
        # Legacy junk from before Block 2 (unauthenticated packets stored under a packet_id).
        db.query(RawPacket).filter(
            RawPacket.packet_id == packet.packet_id,
            RawPacket.status.in_([PacketStatus.REJECTED_SIGNATURE, PacketStatus.EXPIRED]),
        ).delete(synchronize_session=False)

        existing = _existing_identity(db, packet)
        if existing is not None:
            db.commit()
            result = _classify_existing(existing, packet)
            if result.state == PacketState.DUPLICATE:
                _duplicate_extras(db, existing, result)
            else:
                _record_rejection(db, raw_packet, result)
            return result

        if packet.type == PacketType.TERMINATION and not is_authorized_responder(db, packet.sender_id):
            db.commit()
            result = _rejected(packet.packet_id, "unauthorized_responder", "unauthorized responder")
            _record_rejection(db, raw_packet, result)
            return result

        db.add(build_raw_packet(packet, PacketStatus.VALIDATED))
        db.flush()  # visible in this transaction; committed once by the routed handler

        if packet.type == PacketType.EMERGENCY:
            age = max(int(age_seconds(parse_timestamp(packet.timestamp))), 0)
            ai_result = ai_analyze(
                message=packet.message,
                emergency_id=packet.emergency_id,
                relay_count=packet.hop_count,
                age_seconds=age,
                latitude=packet.latitude if packet.latitude is not None else 0.0,
                longitude=packet.longitude if packet.longitude is not None else 0.0,
            )
            outcome = process_sos_packet(db, packet, ai_result=ai_result)  # commits
            detail = {"incident_id": outcome.incident.id, "sms_contacts_notified": outcome.sms_contacts_notified}
            detail.update(outcome.dedup.as_dict())
            return PacketResult(packet.packet_id, PacketState.ACCEPTED, detail=detail)

        closed = close_incident_by_emergency_id(db, packet.emergency_id)  # commits
        return PacketResult(
            packet.packet_id, PacketState.ACCEPTED,
            detail={"closed_incident_id": closed.id if closed else None},
        )

    except IntegrityError:
        # Concurrent insert of the same (sender_id, packet_id): the DB constraint decided.
        db.rollback()
        try:
            existing = _existing_identity(db, packet)
            if existing is not None:
                result = _classify_existing(existing, packet)
                if result.state == PacketState.DUPLICATE:
                    _duplicate_extras(db, existing, result)
                return result
        except Exception:
            db.rollback()
        return PacketResult(packet.packet_id, PacketState.FAILED, "server_error", "temporary error, retry")
    except Exception:
        db.rollback()
        logger.exception("ingest failed for packet %s", packet.packet_id[:16])
        return PacketResult(packet.packet_id, PacketState.FAILED, "server_error", "temporary error, retry")


def process_batch(db: Session, raw_packets: list) -> dict:
    buckets = {"accepted": [], "duplicates": [], "rejected": [], "failed": []}
    key = {
        PacketState.ACCEPTED: "accepted",
        PacketState.DUPLICATE: "duplicates",
        PacketState.REJECTED: "rejected",
        PacketState.FAILED: "failed",
    }
    for raw_packet in raw_packets:
        result = process_packet(db, raw_packet)
        buckets[key[result.state]].append(result.as_dict())
    return buckets
