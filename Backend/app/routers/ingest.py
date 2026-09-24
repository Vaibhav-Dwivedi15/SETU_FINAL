"""
POST /ingest -- receives a batch of packets from a device that has regained
connectivity after mesh-relaying offline.

CONTRACT (Block 2 -- see docs/backend/PACKET_CONTRACT.md): HTTP success is NOT
packet acceptance. The batch response is HTTP 200 whenever the request itself
was well-formed and processed, and reports one entry per packet in exactly one
of four lists, each entry carrying `packet_id` and `status`:

  {"accepted":   [{"packet_id", "status": "ACCEPTED", "incident_id" | "closed_incident_id", ...}],
   "duplicates": [{"packet_id", "status": "DUPLICATE", ...}],
   "rejected":   [{"packet_id", "status": "REJECTED", "code", "reason"}],
   "failed":     [{"packet_id", "status": "FAILED", "code", "reason", "retryable": true}]}

Only ACCEPTED and DUPLICATE mean the backend holds the packet. See
app/services/ingest_service.py for the state semantics and check order.
Whole-request problems (body not JSON / `packets` missing or > 500 entries)
are 422; oversized bodies 413; rate limiting 429 -- all non-2xx, which the
mobile client already treats as "not delivered, retry later".
"""

from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from app.core.rate_limit import enforce_ingest_rate_limit
from app.db.base import get_db
from app.schemas.packet import PacketBatchIn
from app.services.ingest_service import process_batch

router = APIRouter()


@router.post("/ingest")
def ingest_packets(
    batch: PacketBatchIn,
    request: Request,
    db: Session = Depends(get_db),
):
    enforce_ingest_rate_limit(request, packet_count=len(batch.packets))
    return process_batch(db, batch.packets)
