# SETU Mesh — Deduplication

Owner: Vib (Mesh/Architecture). Source-level audit as of Sep 21 2026.

## Current Implementation

There are **two separate identifiers in play**, and they are NOT the same
mechanism:

1. **`nonce`** — generated once at packet creation, never regenerated on
   relay (`withRelayHop()` only changes `ttl`/`hopCount`). Checked by
   `ReplayProtectionService` (via `PacketValidator.validate`) on every
   **receive**, in `MeshServiceImpl._handlePayload`. Bounded cache:
   `SecurityConstants.maxNonceCacheSize = 500`, `nonceExpiry = 10 minutes`,
   evicted FIFO by insertion order (`NonceCache._trimCache`). This is a
   **security** mechanism (replay protection), not a relay-loop mechanism,
   but it does incidentally reject an already-seen packet within its
   10-minute/500-entry window.

2. **`packetId`** (== `emergencyId` for an `EmergencyPacket`/`RecoveryReportModel`)
   — the identifier the **native Kotlin `PacketRelayEngine`'s in-memory
   seen-ID cache** uses to prevent relay loops. This cache is entirely
   outside the Dart codebase's control. `MeshConstants.duplicateCacheSize = 1000`
   is declared in `mesh_constants.dart` but **never referenced anywhere in
   `lib/`** — it appears to document an intended Dart-side dedup cache that
   was never actually built; the real dedup-by-packetId logic lives only in
   native code.

## What Actually Prevents a Duplicate Storm Today

Not a single Dart-side dedup cache — a combination of:
- The native seen-ID cache (out of scope for this Dart-layer pass; per
  `test/cache_and_relay_test.dart`'s own comments, it has **zero automated
  test coverage** in this repository).
- `NonceCache`'s 500-entry/10-minute window (security-motivated, but
  incidentally also rejects a same-nonce repeat within that window).
- TTL providing a hard ceiling on how many times any single packet, looped
  or not, can be re-relayed (max `SecurityConstants.maxTTL = 5` hops before
  `AdaptiveTtl.canRelay` refuses further relay).

## Known Limitations (not fixed this pass)

1. **No Dart-side packetId dedup cache exists**, despite a constant
   (`MeshConstants.duplicateCacheSize`) suggesting one was planned. Not
   added this pass — the sprint brief's own instruction was "do not
   blindly increase cache sizes" and, more fundamentally, adding a second,
   independent dedup layer in Dart that doesn't coordinate with the native
   seen-ID cache risks *inconsistent* behavior (Dart says duplicate, native
   says new, or vice versa) rather than better protection. This needs a
   deliberate design decision about which layer is authoritative, not a
   quick patch.

2. **`NonceCache`'s 500-entry cap is a real, if narrow, duplicate-storm
   risk under flood**: if more than 500 distinct nonces arrive within 10
   minutes, the oldest nonce is evicted; if that same original packet is
   still circulating slowly through a bridge topology, it would be
   re-accepted as if new once its nonce falls out of the window. This is a
   capacity limit, not a bug — raising it is a real option but was not done
   here without evidence of it being hit in practice (see "do not blindly
   increase cache sizes").

3. **Recovery and SOS packets share the same emergencyId/packetId
   generation formula** and therefore the same identifier namespace — see
   `ACK_LIFECYCLE.md`'s note on this.

4. **Native relay-loop-prevention code has no automated test coverage in
   this repository.** The Dart-side `SimulatedMesh` test harness
   (`test/mesh_simulation.dart`) explicitly models the native seen-cache's
   *expected* behavior for the purpose of testing Dart-side relay/priority
   logic — it does not, and cannot, verify the real Kotlin implementation.

## Future Design (not implemented)

If a real Dart-side dedup cache is ever added, it should be scoped
explicitly as a defense-in-depth layer that never contradicts the native
cache's decision (e.g. only used to avoid redundant local processing, never
as the sole gate on relay), and sized/evicted based on actual measured
traffic from `MeshMetrics`'s duplicate-suppression counters (already
plumbed in from native stats via `_pullNativeStats`), not a guessed
constant.
