# SETU – Mesh Protocol

## Overview

The SETU Mesh Protocol defines how emergency messages are created, signed, transmitted, relayed, and terminated across nearby devices without relying on internet or cellular networks. This document reflects the **actual current implementation** (`mesh_packet.dart`, `emergency_packet.dart`, `termination_packet.dart` — GitHub `main`), not an early draft.

---

## Objectives

- Enable offline, device-to-device communication
- Prevent duplicate and replayed packet forwarding
- Keep relay bounded (no infinite propagation)
- Minimize battery consumption on relay-node devices
- Ensure packet authenticity and integrity via digital signing

---

## Packet Lifecycle

```text
User Triggers SOS
        │
        ▼
Signed Emergency Packet Generated (Ed25519)
        │
        ▼
Nearby Devices Receive Packet (silent, background — no UI shown to bystander)
        │
        ▼
Packet Validation (version, TTL range, signature)
        │
        ├── Invalid → Drop
        ▼
Replay Check (timestamp window + nonce cache)
        │
        ├── Duplicate/Replayed → Drop
        ▼
Battery Check
        │
        ├── Below threshold (device is not the sender) → Skip relay
        ▼
Store in Local Queue (SQLite, survives app restart)
        │
        ▼
Decrement TTL, Increment Hop Count, Relay to Nearby Devices
        │
        ▼
Repeat Until:
• TTL reaches 0
• Termination Packet received for this emergency_id
• A relay device reaches internet (Exit Node → auto-forward to backend)
```

---

## Packet Types

### 1. Emergency Packet

Common fields (every packet type): `packet_id`, `sender_id` (Ed25519 public key, hex — self-certifying, no separate identity lookup needed), `type`, `timestamp` (ISO 8601), `nonce`, `ttl`, `hop_count`, `protocol_version`, `signature`.

Emergency-specific fields: `emergency_id`, `latitude`, `longitude` (0.0 fallback if GPS unavailable — a disclosed limitation, not hidden), `message`, `priority` (`low`/`medium`/`high`/`critical`).

### 2. Termination Packet

Common fields as above, plus: `emergency_id` (which emergency is closing), `responder_id` (identity of the responder closing it).

**Known limitation, stated plainly:** `responder_id` is currently only structurally validated on receipt — it is not yet checked against a backend-issued trusted responder registry. Closing this gap (so only an actually-verified responder's termination is honored) is an open item shared between the Backend and Security leads.

---

## Packet Identification

Every packet has a `packet_id` — a unique string used for duplicate-detection and loop-prevention. Devices track seen `packet_id`s in a temporary cache; a repeat is dropped without re-processing or re-relaying.

---

## Hop Count

`hop_count` starts at 0 and increments by 1 on every relay. Used for diagnostics, and can be surfaced on the responder dashboard as a demo detail (e.g. "this message traveled 4 hops with zero internet").

---

## Time To Live (TTL)

**Default and maximum TTL = 5** (this was corrected from an earlier value of 8, to match `SecurityConstants.maxTTL`; if you see `TTL = 8` or `TTL = 10` anywhere, it's stale). Each relay decrements TTL by 1. At TTL = 0, the packet is dropped and relay stops.

---

## Relay Rules

A device relays a packet only if all of the following hold:
- Signature is valid
- Packet version is supported
- TTL is within the valid range (1–5) and > 0 after decrement
- Timestamp is within the allowed freshness window and clock-skew tolerance
- Nonce has not been seen before
- Packet has not already been seen (duplicate check)
- The emergency has not been terminated
- Device battery is above the relay threshold, **or** this device is the original sender (a sender always transmits its own SOS regardless of battery)

---

## Security Layer (see Security_Architecture.md for full detail)

Every packet is Ed25519-signed. Signing is over a specific concatenated string (`signaturePayload`), not the raw JSON, so verification is fast and the exact signed format is frozen. Replay protection combines timestamp validation + a nonce cache (`NonceCache`, `TimestampValidator`, `ReplayProtectionService`, `PacketValidator` — all implemented and integrated in `lib/security/`).

---

## Cache Policy

Devices temporarily store seen `packet_id`s and `nonce`s with expiry (nonce cache: 10 minutes, capped at 500 entries) so memory doesn't grow unbounded during sustained relay activity.

---

## Protocol Principles

- Offline First
- Store and Forward
- Multi-Hop, TTL-Bounded
- Signed and Replay-Protected
- Silent Carrier (bystander devices never surface content they relay)
- Battery Aware

---

## Honest Range Reality

BLE / Wi-Fi Direct give roughly **10–200m per hop** in real-world conditions — this is **cluster-level resilience** (a building, a stampede, a village), not district-wide or state-wide coverage. Bluetooth 5 Coded PHY could extend this 3–4x without new hardware (roadmap item, not shipped — Nearby Connections API doesn't expose it by default). True kilometer-scale coverage would need dedicated LoRa hardware beacons — a longer-term deployment item, not something citizens carry.

---

## Future Enhancements (Roadmap, Not Shipped)

- Bluetooth 5 Coded PHY (Long Range mode) for extended per-hop range
- Backend-issued trusted responder registry for termination authorization
- Wi-Fi Aware (NAN) for lower-power background discovery
- Dedicated LoRa hardware relay beacons at high-risk zones
- Adaptive/priority-based relay ordering
