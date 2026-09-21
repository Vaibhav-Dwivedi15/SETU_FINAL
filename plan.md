# SETU — Engineering Plan (SIH Problem-Statement Alignment + Mesh Performance)

Based on actual inspection of `SETU_FINAL.zip` (Flutter app `setu_app`, native Android mesh engine, `Backend` FastAPI service, `setu_ai_service`, `setu_dashboard`). No code changed yet — this is the audit + plan only, as required before touching anything.

---

## 0. What already exists (do NOT rebuild these)

| Pipeline stage | Where | Status |
|---|---|---|
| Discovery/advertising | `android/.../NearbyConnectionsManager.kt` | Working. `Strategy.P2P_CLUSTER`, tie-breaker on endpoint name avoids the double-request-drop bug. |
| Duty-cycled discovery (battery) | `MeshForegroundService.kt` (`startDutyCycle`) | Working. 5s burst-on, off-time driven by `MeshPolicy.discoveryInterval` (5s/15s/30s by power mode). Full-power = always-on, no restart bug. |
| Connection reuse | `NearbyConnectionsManager.connectedEndpoints` | Already satisfied — Nearby Connections keeps sessions open; `broadcastBytes` reuses existing endpoints, no reconnect-per-message. |
| Dedup | `PacketRelayEngine.kt` (native) | Working. In-memory `LinkedHashSet`, capped at 500 (`maxCacheSize`), O(1) lookup. Runs even if Dart/Flutter isn't attached (background/killed app). |
| Relay-again-after-moving | `PacketRelayEngine.kt` | Extra feature beyond the prompt: haversine-based re-entry after 150m drift. Working, deliberately narrow. |
| TTL decrement | `PacketRelayEngine.kt` + `mesh_service.dart._relayPacket` | Working but **flat**, not adaptive (see §5). |
| Store-and-forward | `local_queue_service.dart` (SQLite via `sqflite`) | Working. Persists across restarts; `markEmergencyClosed` sweeps queue on verified termination. |
| Retry-on-connectivity | `mesh_service.dart` (`_retryTimer`, 30s) + `_tryUpload` | Working, simple periodic poll rather than event-driven. |
| Battery-aware relay gating | `MeshPolicy` (Dart) + `currentAllowRelay` (native, pushed via `updateMeshPolicy`) | Working on both sides, kept in sync. |
| Failed-node handling | `NearbyConnectionsManager.onDisconnected` removes from `connectedEndpoints` | Working — a dropped peer is silently excluded from future `broadcastBytes`, pipeline doesn't block. |
| Signature + replay protection | `security/` (`signing_service.dart`, `nonce_cache.dart`, `replay_protection_service.dart`, `timestamp_validator.dart`, `packet_validator.dart`) | Working, has unit tests. |
| Backend dedup (incident-level) | `Backend/app/services/deduplication_service.py` | Working — 150m/15min haversine window, already load-tested and fsync-optimized (4 commits/packet → 1). |

**Conclusion:** the mesh transport is real and functioning, not a prototype. The gaps are specifically the items the prompt calls out — priority queueing, adaptive TTL, and end-to-end latency instrumentation — plus disaster-lifecycle (before/after) features that don't exist yet.

---

## 1. Confirmed gaps vs. the prompt (this is what changes)

1. **No priority queue.** `mesh_service.dart` and `NearbyConnectionsManager.broadcastBytes` treat every packet identically — SOS and a routine status update relay in the same order. `mesh/enums/emergency_priority.dart` already exists as a field on `EmergencyPacket` but nothing reads it to reorder transmission.
2. **No adaptive TTL.** TTL is `SecurityConstants.defaultTTL` (5), decremented by exactly 1 per hop, both in Dart and in `PacketRelayEngine.kt`. No adjustment for hop count, packet age, or local network density.
3. **No end-to-end latency/metrics instrumentation.** `MeshMetrics` (Dart) only keeps five running counters (`sent/received/relayed/uploaded/dropped`) — no timestamps, no per-stage latency, no packet-loss %, no duplicate rate, no relay success rate, no battery-impact measurement. Section 4/8 of the prompt is currently unmeasurable.
4. **Dead scaffolding, never wired in:** `mesh_optimizer.dart`, `relay_decision.dart`, `mesh_health.dart`, `upload_scheduler.dart`, `mesh_constants.dart` are not imported by `mesh_service.dart` at all — likely where priority/adaptive-TTL logic was meant to land. Reuse these files rather than adding new ones.
5. **No parallel-fan-out control.** `broadcastBytes` loops `connectedEndpoints` calling `sendBytes` — each call is async/non-blocking already (no sequential wait), so this is close to fine, but there's no dedup-storm guard if many peers relay near-simultaneously — worth a small bounded check, not a rewrite.
6. **Automated device-count/failure-scenario tests don't exist.** Current tests (`packet_test`, `signing_service_test`, `nonce_cache_test`, `replay_protection_service_test`, `timestamp_validator_test`, `packet_validator_test`, `cache_and_relay_test` — 607 lines total) cover the security/packet layer well but nothing simulates 1/2/3/5/10-device topologies, disconnect-during-relay, low battery, Internet appearing/disappearing mid-route, or Exit Node failure.
7. **No preparedness/recovery modules.** `lib/features/` has `sos`, `child_safety`, `contacts`, `history`, `relay`, `nearby`, `community`, `lost_child`, `settings`, `stealth`, `voice_sos` — all "during" disaster. Nothing for before-disaster (cached instructions, readiness checks, evacuation guidance) or after-disaster (damage reports, resource availability, recovery status) yet.
8. **No performance benchmarks recorded anywhere** in `docs/` or `setu_app/docs/` — targets in §8 of the prompt can't be written until real numbers exist.

---

## 2. BEFORE — Preparedness module (new)

Add as a new feature module `lib/features/preparedness/`, following the existing repo's `data/models` + `data/repositories` + `data/services` + `presentation/screens` pattern (matches `contacts/`, `history/`).

- **Local disaster-info cache**: bundle static JSON (flood/fire/earthquake/accident safety instructions) into `assets/`, load once, persist to the same `sqflite` pattern `local_queue_service.dart` already uses — no network dependency.
- **Device readiness check screen**: reuse `mesh_permission_service.dart` (already checks Bluetooth/location/Wi-Fi permission state for onboarding) — surface it as an on-demand "Am I ready?" screen instead of only a one-time gate.
- **Mesh availability/status widget**: reuse `MeshMetrics` + `MeshHealth` (currently unused dead code, §1.4) — wire `MeshHealth.healthy` into a home-screen status chip.
- **Emergency contact configuration**: `contacts/` feature already exists — extend, don't rebuild.
- **Preparedness notifications**: local notifications only (no backend dependency) reminding users to check readiness — new, small.

## 3. DURING — Response module (extend existing, preserve pipeline)

Sender → Relay → Exit Node → Backend → Responder pipeline is **not touched structurally**. Only additions:

- `emergency_category.dart` already lists categories — confirm it covers medical/accident/fire/flood/violence/women-safety/child-safety/senior-citizen (extend enum if any are missing; this is a small, additive change).
- Priority queue (§5 below) sits inside `mesh_service.dart`/`PacketRelayEngine.kt`, not a new pipeline.

## 4. AFTER — Recovery module (new)

New `lib/features/recovery/` module, same architecture pattern:

- Damage/incident reporting, missing-person reporting, resource availability — each as its own packet type extending `MeshPacket` (matching how `AlertPacket`/`TerminationPacket`/`AckPacket` already extend it via `PacketFactory`), so they ride the existing mesh transport and `LocalQueueService` store-and-forward for free.
- Community status updates — reuse `community/` feature's existing `VolunteerAlertModel` pattern.
- Backend: new `Incident`-adjacent models in `Backend/app/models/` (mirror `incident.py`), new router in `Backend/app/routers/`, reusing `deduplication_service.py`'s haversine/time-window merge logic rather than duplicating it.

---

## 5. Mesh performance work (the primary engineering task)

All changes are **additive to existing files**, not rewrites:

**A. Priority queue** — add a `PriorityQueue<MeshPacket>` (CRITICAL/HIGH/MEDIUM/LOW, keyed off the existing `EmergencyPriority` enum) inside `MeshServiceImpl` between `_handlePayload`'s validation step and `_relayPacket`/`_tryUpload`. Critical packets (SOS, medical) bypass queued non-critical traffic. Wire `mesh_optimizer.dart`'s currently-dead `policyFor()` logic here instead of leaving it unused.

**B. Adaptive TTL** — extend `PacketRelayEngine.process()` (native) and `MeshPacket.withRelayHop()` (Dart) to adjust decrement based on hop count + packet age, with `SecurityConstants.maxTTL` as a hard upper bound that's never exceeded (prompt explicitly says: safety bound required, don't just raise TTL).

**C. Metrics instrumentation** — extend `MeshMetrics` (currently 5 counters) to record: discovery latency, connection-establish latency, packet-receive-to-relay latency, signature-verify latency, queue latency, relay latency, end-to-end delivery latency (packet-originated timestamp → backend-upload timestamp, using the existing `timestamp` field already on every packet), packet loss %, duplicate rate (from `PacketRelayEngine`'s seen-cache hit rate), relay success rate, battery delta (compare `battery_service.dart` reading at originate vs. upload). This is the prerequisite for §8 — benchmarks can't be produced without this.

**D. Failed-node continuation** — already correct behavior (§0), add a regression test for it rather than new code.

**E. Duplicate-storm guard for fan-out** — small bounded check in `broadcastBytes`/relay path so N peers relaying the same packet within the same burst window don't all originate simultaneously; cheap addition to the existing seen-cache.

Everything else in prompt §5 (connection reuse, store-and-forward, battery-aware relay) is already implemented — verify with tests, don't rebuild.

## 6. Nearby Connections audit result

Already reviewed in §0 — `P2P_CLUSTER` strategy, tie-break connection logic, and duty-cycled start/stop are correct and match the prompt's requirements (no unnecessary start/stop, no Nearby Messages usage, connections reused). No changes needed here beyond what §5 adds on top.

## 7. Test matrix to build

New integration/simulation tests, alongside the existing 7 unit-test files in `setu_app/test/`:

`1 device`, `2 devices`, `3 devices`, `5 devices`, `10 devices`, dense network, sparse network, disconnect-during-relay, low-battery relay, duplicate packet, expired TTL, invalid signature, replayed packet, multiple simultaneous SOS, Internet appears mid-route, Internet disappears mid-route, Exit Node failure, backend unavailable, background/foreground transition.

Most of these can be written as Dart unit/widget tests against `MeshServiceImpl` with fake `NearbyService`/`BackendService`/`LocalQueueService` implementations (the abstract classes already support this — `MeshService`, `NearbyService`, `BackendService` are all interfaces). Multi-device topology tests need a harness that fakes N `NearbyService` instances wired to each other — new, but built on existing interfaces, no architecture change.

## 8. Performance targets

Not set yet — per the prompt's explicit instruction, no numbers are invented here. Once §5-C metrics land, run the §7 test matrix and record actual measured discovery time, connection time, single-hop/multi-hop/end-to-end delivery, packet loss, duplicate rate. Those measured numbers go in the SIH presentation, not estimates.

## 9. Architecture (target state)

Matches the prompt's diagram. Concretely: `USER → SETU MOBILE APP (Flutter)` with new Preparedness/Recovery feature modules alongside existing SOS/Response module → `MESH COMMUNICATION ENGINE` (`mesh_service.dart` + native `MeshForegroundService`/`PacketRelayEngine`/`NearbyConnectionsManager`) with the priority queue and adaptive-TTL additions from §5 → `EXIT NODE` (device with real internet, existing `backend_service.dart hasRealInternet()` check) → `SETU BACKEND` (FastAPI, existing) → `INCIDENT PROCESSING` (existing `incident_service.py`, `deduplication_service.py`, `setu_ai_service` classifier) → `OPERATIONS DASHBOARD` (existing `setu_dashboard` React app) → `RESPONDERS`. Security stays cross-cutting exactly as already built (`security/` folder + `Backend/app/services/signature_service.py`).

## 10. Execution order (per prompt's development rule)

1. Wire up `MeshMetrics` latency instrumentation (§5-C) first — nothing else can be measured without it.
2. Run existing test suite + a manual 2-3 device benchmark to get baseline numbers.
3. Implement priority queue (§5-A), reusing dead `mesh_optimizer.dart`.
4. Implement adaptive TTL (§5-B).
5. Re-run benchmark, compare before/after, fix any regression.
6. Build the test matrix (§7).
7. Build Preparedness module (§2) — no dependency on mesh changes, can run in parallel.
8. Build Recovery module (§4) — depends on new packet types being added to `PacketFactory`.
9. Document: files changed, why, bottlenecks found, optimizations made, tests run, before/after numbers, remaining limitations, next step — per the prompt's required end-of-work report format.

---

**Not doing:** rewriting `MeshServiceImpl`, replacing Nearby Connections, replacing `PacketRelayEngine`'s dedup cache, changing the packet wire format, or adding Nearby Messages (deprecated, prompt explicitly forbids it). Every item above is an addition to, or activation of, code that already exists in this repo.
