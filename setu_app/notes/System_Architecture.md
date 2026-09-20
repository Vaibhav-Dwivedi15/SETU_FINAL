# SETU – System Architecture

## Overview

SETU follows an offline-first, modular architecture. Smartphones communicate directly via mesh networking without depending on cellular infrastructure; a backend and dashboard exist for the moment connectivity is restored.

---

## High-Level Architecture

```text
+--------------------------------------------------------------+
|                       SETU Mobile App (Flutter)               |
+--------------------------------------------------------------+
|  UI: SOS Trigger | Stealth Mode | Relay Status | Confirmation |
+--------------------------------------------------------------+
|  Mesh Layer (Dart): MeshService | LocalQueueService |         |
|  ResponderRegistry | UploadScheduler | IdentityService        |
+--------------------------------------------------------------+
|  Security Layer (Dart): SigningService | PacketValidator |    |
|  ReplayProtectionService | NonceCache | TimestampValidator    |
+--------------------------------------------------------------+
|  Native Transport (Kotlin): NearbyConnectionsManager |        |
|  MeshForegroundService | PacketRelayEngine                    |
+--------------------------------------------------------------+
|  Communication Hardware: Bluetooth LE | Wi-Fi Direct           |
+--------------------------------------------------------------+
                              │
                    (Exit Node reaches internet)
                              │
                              ▼
+--------------------------------------------------------------+
|                  Backend (FastAPI, Python)                    |
|  POST /ingest — signature/replay verify, dedup, store         |
|  GET /incidents — merged, urgency-sorted, API-key gated       |
+--------------------------------------------------------------+
                              │
                ┌─────────────┼─────────────┐
                ▼             ▼             ▼
        AI Triage Service   SMS Gateway   Responder Dashboard
        (urgency + dedup)   (Twilio)      (React + Leaflet)
```

---

## Core Components

### Mobile UI (Sudheer)
SOS trigger, disguised stealth-mode screen, live relay-status view, confirmation. Talks to the mesh layer via platform channels — never touches packet internals directly.

### Mesh Layer (Vaibhav)
Device discovery, packet creation/validation/relay decisions, local store-and-forward queue (SQLite, survives restarts), battery-aware relay guard, exit-node internet-reachability detection and auto-upload.

### Security Layer (Shaurya, integrated into the app by Vaibhav)
Ed25519 signing/verification, replay protection (timestamp + nonce), TTL enforcement. See `Security_Architecture.md` for the honest shipped-vs-roadmap breakdown.

### Native Transport (Vaibhav)
Wraps Google Nearby Connections API (`P2P_CLUSTER` strategy — one device holds multiple simultaneous connections). Runs as a Foreground Service so relay continues in the background legally under Android's restrictions.

### Backend (Ayush)
`/ingest` accepts signed packets, verifies them, deduplicates by geography + time + incident type, stores incidents. `/incidents` serves the dashboard, gated by API-key auth.

### AI Triage (Vaishnavi)
Rule-based urgency baseline first; a feature-flagged Gemini/LLM fallback only for messages the rules can't classify — never on the default path. Duplicate-detection combines text-embedding similarity with geo/time clustering.

### Responder Dashboard (Vanshika)
Live map, incident markers color-coded by urgency, filter by type/urgency, raw-vs-merged toggle, termination trigger (sends a real signed termination packet back through the backend, not just a local UI change).

---

## Data Flow (End to End)

1. Citizen triggers SOS (button or stealth gesture) — no signal required.
2. App generates a signed `EmergencyPacket` (TTL=5, nonce, Ed25519 signature).
3. Packet relays phone-to-phone over BLE/Wi-Fi Direct — store-and-forward, silent to bystanders.
4. First device to reach real internet (Exit Node) auto-POSTs to `/ingest` — no tap required from that device's owner.
5. Backend verifies signature + replay status, deduplicates against existing incidents, triggers AI triage, sends SMS to the sender's pre-set emergency contacts.
6. Verified responder sees the live incident on the dashboard, dispatches help.
7. Responder marks resolved → signed termination packet flows back into the mesh → relay devices stop propagating and clear that emergency from their queue.

---

## Design Principles

- Offline First
- Modular, Role-Separated Codebase
- Honest Security & Range Claims (no overclaiming to judges)
- Silent Carrier (bystander privacy)
- Feeder Into 112/SACHET, Not a Replacement

---

## Future Expansion (Roadmap, Not MVP)

- Bluetooth 5 Coded PHY for extended range
- Dedicated LoRa hardware relay beacons
- Backend-issued trusted responder registry
- SDK partnerships with already-popular apps for coverage
- Government emergency API integration (SACHET/112 direct feed)
