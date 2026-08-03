# SETU – Judge Q&A

> Every answer here matches what's actually implemented and tested as of this handoff. Don't let a rehearsed answer drift ahead of Section 4 of the project status (build state) — if something's roadmap, say roadmap.

---

## 1. What problem does SETU solve?
Emergency communication during exactly the moments 112/cellular networks are unreachable — tower damage, overload, coverage gaps, or shutdowns — by relaying a signed SOS phone-to-phone until a device reaches internet.

## 2. Why is this problem important?
Delayed communication during disasters directly costs rescue time and lives; India's disaster and mass-gathering incident history makes this a recurring, not hypothetical, failure mode.

## 3. Why did you choose this problem?
India regularly experiences floods, earthquakes, cyclones, and large public gatherings where communication failures are common, and existing solutions assume connectivity that isn't guaranteed.

## 4. What makes SETU different from existing emergency apps?
It's offline-first by design (mesh relay, not a fallback mode), it's a feeder into 112/SACHET rather than a competing app, and it ships real cryptographic signing + replay protection rather than just "send and hope."

## 5. How does SETU actually work?
1. User triggers SOS (button or stealth gesture).
2. App generates a signed, TTL-bounded emergency packet.
3. Nearby devices with the app receive and validate it silently.
4. Devices relay it (subject to TTL, battery, and duplicate checks) until one reaches internet.
5. That device auto-forwards to the backend; AI triages and deduplicates it; a responder sees it on a live dashboard.

## 6. What technologies are used?
Flutter (Dart), Kotlin (native Android transport via Google Nearby Connections API), Bluetooth LE + Wi-Fi Direct, Ed25519 signing, FastAPI backend, a rule-based + LLM-fallback AI triage service, React + Leaflet dashboard.

## 7. Why Flutter?
Single codebase across Android/iOS for the citizen-facing app, though mesh transport currently targets Android specifically (see Q19).

## 8. Does SETU require internet?
No — the core relay works fully offline. Internet is only needed at the exit-node → backend hop, and for the dashboard/SMS side.

## 9. Why mesh networking specifically?
It turns every nearby phone into a relay node instead of depending on a single tower — resilience comes from redundancy of nearby devices, not from a central point of failure.

## 10. What is multi-hop relay, concretely?
If Device A can't reach Device D directly: A → B → C → D, with each hop decrementing TTL (max 5 hops) and incrementing hop count.

## 11. How do you prevent duplicate relay?
Each packet has a unique `packet_id`; every device caches recently-seen IDs and drops repeats without reprocessing or re-relaying.

## 12. How do you stop infinite forwarding?
TTL (max 5) decrements on every hop; at 0, the packet is dropped.

## 13. How do you prevent fake SOS messages?
**Shipped today:** every packet requires a valid Ed25519 signature; replay protection via timestamp + nonce blocks resending captured packets; a human responder always makes the final escalation call — nothing is fully automated.
**Roadmap, not shipped:** Sybil resistance (nothing yet stops one actor from generating many valid keypairs), GPS-spoof detection, reputation scoring.

## 14. Is user privacy protected?
Yes — only minimal fields (location, urgency type, short message) relay through the mesh. Full profile/medical history is fetched from the backend separately, only on a verified responder's request, never broadcast through the mesh.

## 15. Is user data stored on the cloud?
Only after connectivity is restored and a packet reaches the backend — offline relay is fully device-to-device with no cloud dependency.

## 16. Does SETU replace 112 or SACHET?
No — it's explicitly a feeder into them. 112 needs signal to work at all; SETU exists for the moment it's unreachable, and pushes verified reports back into 112/SACHET once connectivity returns.

## 17. Why should the government adopt SETU?
It strengthens existing emergency infrastructure for the connectivity-failure case specifically, without requiring a parallel emergency-response system — B2G pilot deployment with disaster management authorities, not a competing consumer product.

## 18. Can SETU work in remote villages?
Only with **institutional pre-deployment** — volunteer/responder/staff phones with the app pre-installed — not by assuming random villagers happen to have it. This is a deliberate design choice: relying on organic mass adoption is the exact limitation that constrained Bridgefy and FireChat at scale. Long-term coverage in truly sparse areas depends on dedicated hardware relay beacons (LoRa), not phone density.

## 19. Does SETU work on iPhone?
The app is cross-platform (Flutter), but full mesh transport is currently built and tested on Android — iOS has stricter background networking restrictions that would need separate engineering work, not yet done.

## 20. What's the actual range? Will it work district-wide?
No — realistic range is 10-200m per hop (BLE/Wi-Fi Direct), which is cluster-level resilience (a building, a stampede, a village), not district-wide. Bluetooth 5 Coded PHY could extend this 3-4x without new hardware (roadmap); true kilometer-scale coverage needs dedicated LoRa beacons (longer-term deployment item).

## 21. Has this actually been tested on real hardware?
Yes, for a two-device hop: a signed SOS packet has been sent from one physical phone (Redmi 8A) and received, decoded, and signature-verified on a second physical phone (Realme RMX3998) — different OEMs, over Bluetooth/Nearby Connections, with TTL and hop-count carried correctly (hop 0, ttl 5 on receipt). **What's still pending:** multi-hop relay (3+ devices, where the second device forwards to a third) and real-world range/OEM-breadth testing haven't been done yet — only the direct A→B hop is confirmed so far.

## 22. What's genuinely novel here, patent-wise?
The urgency-prioritization heuristic and duplicate-incident collapsing logic — not the mesh routing protocol itself, which builds on 20+ years of existing delay-tolerant/epidemic-routing research.

## 23. What's the future roadmap?
Bluetooth 5 Coded PHY for extended range, backend-issued trusted responder registry (closing the current termination-authorization gap), LoRa hardware relay beacons, SDK partnerships for broader coverage, government API integration with 112/SACHET, Android Keystore + PKI for stronger key security.

---

## Closing Statement

SETU is a resilient communication feeder for the moment India's emergency infrastructure loses signal — narrow in scope, honest about what's shipped versus roadmap, and built to hand a verified, prioritized signal to the nearest human who can act on it.

> **"Jab Network Toote, Setu Jode."**