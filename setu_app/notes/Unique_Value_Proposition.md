# SETU – Unique Value Proposition

## What Makes SETU Different?

Unlike traditional emergency apps that depend entirely on mobile networks or the internet, SETU keeps working in the exact moment those fail — via a Bluetooth/Wi-Fi Direct mesh of nearby phones, with no new hardware and no SIM required.

**Deliberately narrow, deliberately honest:** SETU is not "everything for every disaster domain." It's one working mesh-relay core, demonstrated through two verticals (disaster SOS, women's-safety stealth mode), with everything else clearly labeled future roadmap.

---

## Unique Features (What's Actually True Today)

### 1. Offline-First, Signed Communication
Works without internet or cellular signal. Every packet is Ed25519-signed and replay-protected — not just "sent," but authenticated.

### 2. Silent-Carrier Mesh
Nearby phones relay packets automatically and silently — no bystander notification, no panic-inducing popups, no content exposure to strangers.

### 3. TTL-Bounded Multi-Hop Relay
Messages travel phone-to-phone up to 5 hops, extending effective range well beyond a single device's radio without unbounded flooding.

### 4. Feeder Into Government Systems, Not a Competitor
Once connectivity is regained, SETU pushes into the same pipeline that already exists (112/SACHET) rather than trying to replace it — this is a deliberate positioning choice, not an afterthought.

### 5. AI-Assisted Triage & Deduplication
Rule-based urgency scoring with an LLM fallback only for edge cases; duplicate reports of the same incident are merged using geo + time + text similarity, so responders see one prioritized incident, not a flood of raw duplicates.

### 6. Privacy-Minimized by Design
Only minimal fields (location, type, short message) travel through the mesh. Full sender profile/medical history is never broadcast — it's fetched securely from the backend only on a verified responder's request.

---

## Honest Comparison

| Feature | 112 India | Bridgefy / FireChat | SETU |
|---|---|---|---|
| Works without internet/cellular | ❌ | ✅ | ✅ |
| Signed, replay-protected packets | N/A | Limited | ✅ |
| Feeds into government emergency response | ✅ (native) | ❌ | ✅ (feeder) |
| Emergency-workflow-aware (triage, dedup, dashboard) | ✅ | ❌ | ✅ |
| Range per hop | N/A (needs tower) | ~10-100m | ~10-200m (BLE/Wi-Fi Direct) |
| District/state-wide coverage claim | ✅ (via towers) | ❌ | ❌ (honestly cluster-level only) |

*(We deliberately do not claim district-wide coverage — that would be an overclaim BLE/Wi-Fi Direct physics doesn't support. See Mesh_Protocol.md.)*

---

## Value Proposition

SETU turns any cluster of nearby smartphones into an emergency relay mesh — no SIM, no data, no new hardware — and gets a distress signal to the nearest human who can act on it, verified and prioritized by AI, the moment a relay path exists.

---

## One-Line Pitch (frozen — use exactly this)

> "Setu turns any cluster of nearby smartphones into an emergency relay mesh — no SIM, no data, no new hardware — and gets a distress signal to the nearest human who can act on it, verified and prioritized by AI, the moment a relay path exists."
