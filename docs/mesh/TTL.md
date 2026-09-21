# SETU Mesh — TTL

Owner: Vib (Mesh/Architecture). Source-level audit as of Sep 21 2026.
**No TTL values or signature semantics were changed this pass** — this
document records current behavior, it does not propose changes to it.

## Current Implementation

- **Actual default TTL in use: 5** (`SecurityConstants.defaultTTL = 5`,
  used directly in `EmergencyPacketBuilder`/`RecoveryPacketBuilder`).
  `SecurityConstants.maxTTL = 5`, `minimumTTL = 1`.
  `MeshConstants.defaultTtl = 5` also exists but is **dead/unused code** —
  the file's own comment says so; real packets never read it.

- **Decrement**: `AdaptiveTtl.nextTtl()` computes the next hop's TTL.
  CRITICAL-priority packets always lose exactly 1. Non-critical packets
  lose 2 when stale (age ≥ 60% of max packet age, ~3 minutes) or in a dense
  cluster (≥6 connected peers). Input TTL is clamped to the ceiling first,
  so a hostile packet claiming `ttl=9999` cannot get unlimited hops — the
  class's own invariants guarantee `result < input` and `result >= 0`.

- **Expiry checks happen twice**: a cheap pre-check before a packet is even
  admitted to the relay queue, and again at actual dispatch time (using the
  freshly-computed next TTL, since cluster density and packet age can
  change while the packet was queued). Additionally, `PacketValidator`
  independently rejects any *incoming* packet with `ttl < 1 || ttl > 5` at
  the security layer, before it is ever processed further.

- **TTL is outside the signed payload** — confirmed intentional by reading
  `signaturePayload` on every packet type; TTL and hop_count both mutate
  per relay hop by design, so including them in the signature would break
  relaying entirely. **This pass did not touch this.**

- **Persistence**: `LocalQueueService` stores the full packet JSON,
  including whatever TTL it had at the moment of enqueue. A packet held
  offline for hours and later relayed carries that original TTL forward —
  it is not "topped up." Staleness-based deceleration in `AdaptiveTtl`
  (the 60%-of-max-age rule) does correctly compute age from the packet's
  own timestamp at dispatch time, which independently penalizes an old
  held packet's remaining hop budget — and `PacketValidator`'s own
  `maxPacketAge` check would reject a genuinely stale packet on arrival at
  the next hop's receiving device before it gets this far anyway.

## Known Limitations

- No limitation was found in TTL handling itself during this pass beyond
  what's inherent to the design (see "Future Design" below for one open
  question). The main risk areas TTL alone cannot fully cover — relay
  loops and duplicate storms — are addressed (or documented as not fully
  addressed) in `DEDUPLICATION.md`, since TTL only bounds loop *length*, it
  does not prevent a loop from forming.

## Future Design (not implemented, not proposed as urgent)

- Whether TTL=5 is the right ceiling for real deployment topologies (dense
  urban clusters vs. sparse rural chains) is a question for real-device
  field data, not something to change speculatively from source review
  alone. `docs/MESH_PERFORMANCE.md` (Sprint 1 deliverable) is the right
  place to correlate this against actual benchmark numbers once available.
