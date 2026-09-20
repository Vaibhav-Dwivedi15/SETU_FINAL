# SETU – System Architecture Diagram

## End-to-End Flow (6 Stages — this is the full pipeline, not a subset)

```text
+----------------------+
|   1. SENDER          |
|  (in emergency)      |
|  Triggers SOS         |
|  → Signed EmergencyPacket (Ed25519, TTL=5, nonce)
+----------------------+
            │  BLE / Wi-Fi Direct
            ▼
+----------------------+
|  2. RELAY NODE(S)     |
|  Silent carriers       |
|  - Duplicate check    |
|  - Battery check       |
|  - TTL decrement       |
|  - Forward to next hop |
+----------------------+
            │  (repeats until TTL=0 or internet found)
            ▼
+----------------------+
|  3. EXIT NODE          |
|  First device with     |
|  internet — auto-      |
|  forwards, no tap       |
+----------------------+
            │  HTTPS POST /ingest
            ▼
+----------------------+
|  4. BACKEND (FastAPI)  |
|  - Verify signature/    |
|    replay                |
|  - Dedup / merge         |
|  - AI triage (urgency)   |
|  - SMS to emergency      |
|    contacts (Twilio)     |
+----------------------+
            │
            ▼
+----------------------+
|  5. RESPONDER            |
|  Verified (police/NDRF)   |
|  Sees live dashboard,     |
|  dispatches help          |
+----------------------+
            │  marks "Resolved"
            ▼
+----------------------+
|  6. TERMINATION           |
|  Signed termination        |
|  packet flows back into    |
|  mesh — relay devices       |
|  stop propagating, clear    |
|  local cache for this        |
|  emergency_id                |
+----------------------+
```

**Note:** Any diagram or slide that shows only Sender → Relay → Exit → Backend is **missing 2 of 6 stages** (Responder, Termination) — this was an identified gap in an earlier pitch-deck version and must not be reintroduced.

---

## Component Responsibilities

| Layer | Responsibility | Owner |
|---|---|---|
| Mobile UI | SOS trigger, stealth mode, relay-status display | Sudheer |
| Mesh + Security | Packet creation, signing, relay logic, TTL/replay enforcement | Vaibhav + Shaurya |
| Native Transport | Nearby Connections wrapper, Foreground Service | Vaibhav |
| Backend | Ingest, verify, dedup, SMS gateway | Ayush |
| AI Triage | Urgency scoring, duplicate-incident merging | Vaishnavi |
| Dashboard | Live map, filtering, termination trigger | Vanshika |

---

## Honest Range Note (relevant to this diagram)

Each hop in the "Relay Node(s)" stage covers roughly 10–200m — this diagram shows the *logical* pipeline, not a claim about geographic coverage. See `Mesh_Protocol.md` for the full range discussion.

---

## Design Goal

> Every smartphone in range becomes a relay node — but the pipeline only earns trust with judges if every stage (including Responder and Termination) is shown and none of the claims outrun what's actually tested.
