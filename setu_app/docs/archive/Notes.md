# 🌉 SETU
## *Jab Network Toote, Setu Jode.*

> **Technical Planning Document**
> **Version:** 2.0 (corrected — supersedes the original v1.0 draft)
> **Prepared For:** Smart India Hackathon (SIH) 2026
> **Status:** MVP in active development, real-hardware relay confirmed

---

# PART 1 — EXECUTIVE SUMMARY

## 1.1 Introduction

Natural disasters, mass gatherings, and connectivity shutdowns disrupt traditional communication precisely when it's needed most. Existing emergency services — including India's 112 — depend on mobile towers and internet connectivity that may be damaged, overloaded, or unavailable.

**SETU** is an offline-first emergency relay: nearby Android smartphones form a decentralized Bluetooth/Wi-Fi Direct mesh, carrying a signed emergency packet from device to device until one reaches internet, at which point it's pushed to a backend, triaged by AI, and shown to a verified responder.

SETU is explicitly a **feeder into 112 India and NDMA's SACHET**, not a replacement.

## 1.2 Vision Statement

> "To ensure that no emergency message is lost simply because communication infrastructure has failed."

## 1.3 Mission

- Enable emergency communication without internet.
- Turn existing Android smartphones into a relay mesh — no new hardware.
- Feed verified, prioritized reports into existing government systems.
- Stay honest, in every document and every pitch, about what's shipped versus roadmap.

## 1.4 Project Snapshot

| Attribute | Details |
|---|---|
| Project Name | SETU |
| Category | Disaster Management & Emergency Response |
| Target Platform | Android (mesh transport); Flutter app is cross-platform |
| Framework | Flutter (Dart) + Kotlin (native transport) |
| Networking | Bluetooth LE + Wi-Fi Direct (Google Nearby Connections API) |
| Security | Ed25519 signing, nonce + timestamp replay protection, TTL-bound relay |
| Backend | FastAPI (Python) |
| AI Triage | Rule-based baseline + feature-flagged LLM fallback |
| Dashboard | React + Leaflet |

## 1.5 Scope Discipline

The original concept covered 15+ domains (disaster, women's safety, railways, mining, border security, etc.). This is deliberately narrowed to **one mesh-relay core, demonstrated through two verticals**: disaster SOS and women's-safety stealth mode. Everything else is documented Future Vision, not part of the current build.

## 1.6 Current Build Status (as of this document)

- ✅ Mesh core: packet models, native Kotlin transport, Foreground Service, SQLite queue, security integration — code-complete.
- ✅ **Signed-packet relay confirmed on real hardware** — Redmi 8A → Realme RMX3998, signature verified, TTL=5, hop=0 (direct hop).
- ✅ Relay-forwarding wired in Dart layer (`_relayPacket()` in `mesh_service.dart`) with battery-aware guard (`MeshPolicy.allowRelay`).
- ✅ A native-layer bug (camelCase/snake_case field mismatch in `PacketRelayEngine.kt`) that silently broke background relay has been found and fixed.
- ⏳ Multi-hop relay (3+ devices) — not yet tested, only 2 physical devices available so far.
- ⏳ Termination-packet authorization — structurally validated only; not yet checked against a backend-issued trusted responder registry (`ResponderRegistry.dart` fails open with a logged warning until that registry syncs).
- ⏳ Mobile UI (Sudheer), Backend (Ayush), AI service integration (Vaishnavi), Dashboard (Vanshika) — in progress in their own tracks.

---

# PART 2 — PROBLEM STATEMENT

## 2.1 Background

Emergency response effectiveness depends heavily on how quickly a distress signal reaches a responder. Modern systems like 112 India depend on cellular networks, internet, and centralized infrastructure — all of which are exactly what disasters damage first.

## 2.2 Failure Causes

| Cause | Impact |
|---|---|
| Flood / Earthquake | Physical damage to towers, power loss |
| Fire | Local network equipment destroyed |
| Mass gatherings | Tower congestion even with intact infrastructure |
| Remote/rural areas | Baseline coverage gap, disaster or not |
| Planned shutdowns | Digital emergency channel removed entirely |

## 2.3 The Single-Point-of-Failure Problem

```text
Citizen → Mobile Tower → Internet → Emergency Server → Authorities
```
If any one link breaks, the whole chain breaks. SETU's core idea is to replace the fragile middle links (tower, internet) with a redundant, self-forming mesh of nearby phones — while still ending at the same authorities.

## 2.4 Problem Statement

> How can emergency messages be transmitted reliably when mobile towers and internet connectivity are unavailable — without requiring new hardware, and without pretending to solve every disaster-communication problem at once?

---

# PART 3 — EXISTING SOLUTIONS, HONESTLY COMPARED

| Solution | Offline | Multi-Hop | Signed/Auth | Emergency-Specific | Notes |
|---|---|---|---|---|---|
| 112 India | ❌ | ❌ | N/A | ✅ | Native, trusted, but needs signal |
| SACHET | ❌ | ❌ | N/A | ⚠ Partial | One-way alerting only |
| Bridgefy | ✅ | ⚠ Limited | ❌ | ❌ | General messaging, no emergency workflow |
| FireChat | ✅ | ✅ | ❌ | ❌ | Discontinued |
| Meshtastic | ✅ | ✅ | ⚠ | ⚠ Requires hardware | LoRa-based, needs dedicated radios |
| **SETU** | ✅ | ✅ (in progress) | ✅ (Ed25519, shipped) | ✅ | Feeder into 112/SACHET, not standalone |

**Honest framing:** SETU is not claiming to out-range Meshtastic or replace 112. Its specific niche is: phone-only (no extra hardware), cryptographically signed, and structured specifically around the emergency-triage workflow (dedup, priority, responder dashboard) that general mesh messengers don't have.

---

# PART 4 — PROPOSED SOLUTION

## 4.1 Overview

Nearby Android phones form a Bluetooth/Wi-Fi Direct mesh. A citizen's signed SOS packet relays phone-to-phone (TTL-bounded, duplicate-checked, battery-aware) until an Exit Node reaches internet and auto-uploads to the backend. AI triages and deduplicates; a verified responder sees it live and dispatches help; a signed termination packet propagates back through the mesh to close the loop.

## 4.2 Design Principles

| Principle | What it means here |
|---|---|
| Offline First | Core relay works with zero connectivity |
| Signed & Replay-Protected | Every packet is Ed25519-signed; replay blocked via nonce + timestamp |
| Silent Carrier | Bystander relay-node phones show zero UI for content they carry |
| Honest Scope | Security/range/adoption claims match what's tested, not what's aspirational |
| Feeder, Not Replacement | Ends at 112/SACHET, doesn't try to be them |

## 4.3 Solution Workflow (6 stages — see `notes/System_Architecture_Diagram.md` for the authoritative diagram)

1. **Sender** triggers SOS → signed `EmergencyPacket` generated (TTL=5, nonce, Ed25519 signature).
2. **Relay Node(s)** — silent carriers; duplicate check, battery check, TTL decrement, forward.
3. **Exit Node** — first device with real internet auto-POSTs to backend, no tap required.
4. **Backend** — verifies signature/replay, dedups, triages via AI, sends SMS to sender's own emergency contacts.
5. **Responder** — verified authority sees live dashboard, dispatches help.
6. **Termination** — signed termination packet flows back into the mesh; relay devices stop propagating and clear their local cache for that emergency.

## 4.4 What's Deliberately NOT in the Solution (and why)

Per the pipeline gap-analysis (see `Setu_Pipeline_Doc1/Doc2`): Android cannot silently turn on radios even with permission granted (a deliberate OS security decision); a fully-off Bluetooth radio cannot be woken by an incoming signal (a physics/OS constraint, not a design gap); random bystanders never make termination decisions (only a verified responder can); full sender profile/medical history never travels through the mesh (privacy — fetched from backend separately, only on verified request).

---

# PART 5 — SYSTEM ARCHITECTURE

See `notes/System_Architecture.md` for the full authoritative layer-by-layer breakdown (this section is a summary).

```text
Flutter UI → Mesh + Security Layer (Dart) → Native Transport (Kotlin) → BLE/Wi-Fi Direct
                                                      │
                                        (Exit Node reaches internet)
                                                      ▼
                                    FastAPI Backend → AI Triage / SMS / Dashboard
```

**Key correction from the original v1.0 draft:** the original diagram omitted the Responder and Termination stages entirely — a 4-stage pipeline instead of 6. This has been fixed everywhere; any deck or diagram showing only Sender→Relay→Exit→Backend is out of date.

---

# PART 6 — TECHNOLOGY STACK

| Layer | Technology | Why |
|---|---|---|
| Mobile UI | Flutter (Dart) | Single codebase, fast iteration |
| Native transport | Kotlin | Required for Nearby Connections API, BLE, Foreground Service |
| Mesh networking | Google Nearby Connections API (`P2P_CLUSTER`) | Offline, multi-connection capable |
| Local storage | SQLite (`sqflite`) | Store-and-forward queue survives restarts |
| Security | Ed25519 (`cryptography`-equivalent Dart package) | Fast, modern, self-certifying identity |
| Backend | FastAPI (Python) | High-performance async APIs |
| Database | PostgreSQL / SQLite | Incident storage |
| AI | Python, rule-based + LLM fallback | Predictable latency, cost-controlled |
| Dashboard | React + Leaflet | Live map, responder-facing |
| SMS Gateway | Twilio (planned) | Backend-side only, never a bystander's phone |

**Not used, and deliberately so:** no PKI/certificate authority (self-certifying keys instead), no cloud dependency for the offline relay path itself, no dedicated hardware for the MVP (LoRa beacons are a roadmap item, not shipped).

---

# PART 7 — TEAM & IMPLEMENTATION

## 7.1 Team Structure

| Role | Owner | Owns |
|---|---|---|
| Team Lead + Mesh/Networking Lead | Vaibhav | Mesh core, native transport, security integration, overall coordination |
| Mobile / UI Lead | Sudheer | Citizen-facing Flutter app, stealth mode |
| Backend Lead | Ayush | FastAPI ingest, dedup, SMS gateway, responder registry |
| AI / ML Lead | Vaishnavi | Urgency triage, duplicate-incident merging |
| Dashboard / Frontend Lead | Vanshika | Live responder map |
| Security + Documentation & Pitch Lead | Shaurya | Signing/replay module, security scope docs, pitch deck |

## 7.2 Testing Strategy

| Testing Type | Status |
|---|---|
| Unit tests (packet layer) | ✅ 14/14 passing (`packet_test.dart`, `cache_and_relay_test.dart`) |
| Native Kotlin relay logic | ❌ No automated coverage yet — flagged, not hidden |
| Security module (signing/replay) | Unconfirmed — check with Shaurya's chat |
| Real hardware, 2-device signed relay | ✅ Confirmed (Redmi 8A ↔ Realme RMX3998) |
| Real hardware, multi-hop (3+ device) | ⏳ Pending — need a 3rd device |
| Multi-OEM breadth testing | ⏳ Pending |
| Backend/AI/Dashboard integration testing | ⏳ Pending — depends on other roles' progress |

## 7.3 Known Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Device/OEM Bluetooth throttling varies | Test across 3+ real OEMs before finalizing |
| Termination packet currently unauthorized | Backend-issued responder registry — joint Ayush/Shaurya item, tracked |
| Battery drain from relaying others' traffic | `MeshPolicy.allowRelay` gates relay below 20% battery (own SOS always sends) |
| Overclaiming to judges | Every doc in `notes/` and this document is written to match tested reality, not aspiration |

---

# PART 8 — CONCLUSION & ROADMAP

## 8.1 Conclusion

SETU demonstrates that a real, cryptographically signed emergency relay can run on unmodified consumer Android phones with no new hardware — confirmed on real devices, not just in theory. Its value is specifically as a **feeder** into India's existing emergency response infrastructure for the moments that infrastructure is unreachable, not as a parallel or competing system.

## 8.2 Honest Limitations (say these plainly, don't hide them)

- Realistic per-hop range is 10–200m — cluster-level resilience, not district-wide.
- Multi-hop relay through a 3rd device is unverified so far.
- Termination-packet authorization is not yet enforced against a real registry.
- No Zero Trust, Sybil resistance, or GPS-spoof detection — explicitly roadmap.
- Coverage depends on institutional pre-deployment, not assumed organic mass adoption.

## 8.3 Roadmap

Bluetooth 5 Coded PHY for extended range, backend-issued trusted responder registry, LoRa hardware relay beacons for true long-range deployment, SDK partnerships for broader coverage, Android Keystore + PKI for stronger key security, government API integration with 112/SACHET.

---

**Document Status:** This v2.0 supersedes the original v1.0 planning draft. The original is preserved for history but should not be treated as authoritative — see `notes/` folder for the current corrected reference set (`Judge_QA.md`, `Security_Architecture.md`, `Mesh_Protocol.md`, `System_Architecture.md`, `System_Architecture_Diagram.md`, `Problem_Statement.md`, `Unique_Value_Proposition.md`).
