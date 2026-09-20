# SETU – Security Architecture

## Overview

SETU's security scope is deliberately limited to what is actually implemented and tested in the current MVP. This document draws a hard line between **shipped** and **roadmap** — overclaiming security to a technically literate judge is a bigger credibility risk than not mentioning a feature at all.

---

## Security Objectives (What We're Actually Trying To Guarantee)

- **Authentication** — every emergency/termination packet provably originates from the sender's own key
- **Integrity** — any tampering with a signed packet is detectable
- **Replay Protection** — a captured packet can't be re-sent later to fake a new event
- **Controlled Propagation** — relay is bounded (TTL), not unlimited flooding
- **Reliable Delivery** — the pipeline stays trustworthy even with unreliable, intermittent connectivity

---

## Implemented (Shipped, In Current Code)

### 1. Ed25519 Digital Signatures
Every packet is signed with Ed25519. The device's public key **is** its `sender_id` — self-certifying identity, no separate PKI or identity-lookup service needed. Signature covers a frozen concatenated string (`signaturePayload`), not the raw JSON blob.

### 2. Replay Protection
Combines timestamp validation + nonce verification + a nonce cache. A packet that's too old, too far in the future (beyond allowed clock skew), or reuses a seen nonce is rejected. Implemented in `lib/security/`: `TimestampValidator`, `NonceCache`, `ReplayProtectionService`, `PacketValidator`.

### 3. TTL-Bound Relay
Every packet carries a TTL (max = 5), decremented per hop. At 0, the packet is dropped. Prevents unbounded circulation.

### 4. Signed Termination Packets
A termination packet undergoes the same signature/replay checks as an emergency packet before being honored.

---

## NOT Implemented — Explicitly Roadmap, Not Shipped

Say this plainly if asked; do not imply any of these exist:

- **Zero Trust Architecture** — would require centralized identity/policy infrastructure we don't have
- **Sybil resistance** — nothing currently stops one attacker from generating many keypairs/identities
- **GPS spoof detection** — location is trusted as reported
- **Android Keystore integration** — keys aren't yet hardware-backed
- **Public Key Infrastructure (PKI)** — no certificate authority; trust is currently self-certifying only
- **Biometric app-access authentication**
- **Formal penetration testing**
- **Backend-authorized termination** — a termination packet's `responder_id` is structurally validated but **not yet checked against a real registry of verified responders**. This is a known, actively flagged gap (Backend Lead + Security Lead joint item), not an oversight being hidden.

---

## Threat Model — What We Defend Against Today

| Threat | Current Mitigation |
|---|---|
| Packet tampering in transit | Ed25519 signature — any modification invalidates it |
| Replay of a captured packet | Timestamp window + nonce cache |
| Infinite relay loops / flooding | TTL cap + duplicate `packet_id` cache |
| Battery-drain griefing via forced relay | Battery-aware relay guard (skip relay below threshold, unless it's your own SOS) |
| Fake termination by a random bystander | Requires a valid signature (blocks trivial spoofing) — but **not yet** blocked from any arbitrary valid keypair, since there's no responder registry check yet |

## What We Do NOT Defend Against Yet

- A malicious actor with a validly-signed key generating many fake SOS packets (no Sybil resistance, no reputation system)
- A responder-registry bypass on termination (see above)
- Faked GPS coordinates in an emergency packet

---

## Privacy Approach

- Only minimal fields relay through the mesh: location, urgency type, short message. **Full sender profile / medical history never travels through the mesh** — it's fetched from the backend only after connectivity, via a secure server-to-server request, only on a verified responder's query.
- Relay-node phones are **silent carriers** — a bystander relaying someone else's packet never sees its content. Only the sender's own device and verified responders (via the dashboard) see message content.

---

## Judge Q&A (Honest Answers)

**Q: Do you have Zero Trust or Sybil resistance?**
A: Not in the MVP. Roadmap only. MVP ships message signing, replay protection, and TTL-bound relay.

**Q: What stops a fake SOS?**
A: A valid Ed25519 signature is required, plus geo/time corroboration before a report is escalated to "urgent," rate-limiting per identity, and a human responder always makes the final call — no fully automated escalation.

**Q: Can anyone close an emergency?**
A: Currently, anyone with a valid signed keypair can structurally send a termination packet — this is a known, disclosed gap. The fix (backend-issued trusted responder registry) is an active roadmap item, not claimed as done.

---

## Summary

SETU ships a real, working, tested security layer: signing, replay protection, and TTL-bound relay. It explicitly does not ship Zero Trust, Sybil resistance, GPS-spoof detection, or authorized termination — these stay labeled roadmap in every pitch, doc, and demo.
