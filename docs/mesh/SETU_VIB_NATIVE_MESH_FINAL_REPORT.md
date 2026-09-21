# SETU — VIB Bulk Sprint 2: Native Mesh Audit + Multi-Device Reliability + Integration Validation — Final Report

Owner: Vib (Mesh/Architecture). Branch: `feature/vib-native-mesh` (from
`feature/vib-mesh-hardening`, which itself sits on `main` at `850e3c9`).
Date: Sep 21 2026.

## 1. Executive Summary

Bulk Sprint 1 hardened the Dart mesh layer but flagged its own biggest
blind spot honestly: the native Kotlin mesh layer and real multi-device
behavior were never verified. This sprint closes that gap as far as a
sandbox with no Flutter SDK, no Android toolchain, and no physical devices
can close it: a full source-level audit of all 8 native Kotlin files,
2 concrete thread-safety fixes with zero logic changes, a redundant-
reconnection guard, and five new/updated design documents. The single
most important finding is a correction, not a bug: **native Kotlin is not
a dumb transport.** It independently implements packet deduplication, TTL
decrement, and relay/rebroadcast decisions — a full second implementation
of relay-critical logic that runs even when Dart is not attached. Every
document in `docs/mesh/` written in Sprint 1 has now been corrected or
extended to reflect this. No build could be run, no device test could be
executed, and both facts are stated plainly below rather than glossed
over.

## 2. Native Architecture Audited

`MeshForegroundService.kt` (duty-cycling, jitter/echo-suppression
rebroadcast, `START_STICKY` foreground service lifecycle),
`NearbyConnectionsManager.kt` (Nearby Connections wrapper — advertising,
discovery, connection tie-break, payload send/broadcast),
`PacketRelayEngine.kt` (native dedup cache, TTL decrement, relay decision
logic — the file at the center of this sprint's correction), plus
`MainActivity.kt` and its 4 MethodChannel handlers
(`DirectSmsChannelHandler.kt`, `MeshChannelHandler.kt`,
`RadioStateChannelHandler.kt`, `VolumeKeyChannelHandler.kt`), read for
completeness but not independently audited in depth (they are thin
platform-channel plumbing, not relay-critical logic).

## 3. Files Inspected

All 8 files listed above, plus a check of `android/app/src/test/` and
`android/app/src/androidTest/` (both absent) and `build.gradle.kts`
(no test dependencies declared).

## 4. Files Changed

- `setu_app/android/app/src/main/kotlin/com/setu/mesh/PacketRelayEngine.kt`
- `setu_app/android/app/src/main/kotlin/com/setu/mesh/NearbyConnectionsManager.kt`
- `docs/mesh/NATIVE_MESH_AUDIT.md` (new)
- `docs/mesh/NATIVE_FAILURE_MATRIX.md` (new)
- `docs/mesh/MULTI_DEVICE_TEST_PLAN.md` (new)
- `docs/mesh/RELAYED_STATE_DESIGN.md` (new)
- `docs/mesh/DEDUPLICATION.md`, `docs/mesh/TTL.md`,
  `docs/mesh/FAILURE_HANDLING.md`, `docs/mesh/ACK_LIFECYCLE.md`,
  `docs/mesh/OBSERVABILITY.md` (updated with native-layer findings)

`MeshForegroundService.kt` and `MainActivity.kt`/handlers were **not
modified** — see §7 for why (their gaps require feature additions or
product decisions, not mechanical patches).

## 5. Bugs Found

See `NATIVE_MESH_AUDIT.md` (18 sections) and `NATIVE_FAILURE_MATRIX.md`
(18 scenarios) for the full, cited list. Headline findings:
- **Confirmed**: native independently does dedup, TTL, relay decisions
  (correction to Sprint 1's speculation, not a bug in itself, but changes
  the risk picture of every other finding below).
- **Confirmed bug (fixed)**: `PacketRelayEngine`'s dedup cache and
  `NearbyConnectionsManager`'s connection-state collections were not
  thread-safe against concurrent Nearby Connections callback delivery.
- **Confirmed bug (fixed)**: no guard against re-requesting a connection
  to an already-connected endpoint during duty-cycle-triggered
  rediscovery.
- **Confirmed gap (not fixed, documented)**: no signature verification in
  native at all — a backgrounded, Dart-detached device will relay any
  well-formed JSON claiming valid fields.
- **Confirmed gap (not fixed, documented)**: no authentication on
  connection acceptance (`onConnectionInitiated` auto-accepts
  unconditionally).
- **Confirmed gap (not fixed, documented)**: `START_STICKY` restart wipes
  the dedup cache and resets battery policy to full-power defaults until
  Dart re-syncs.
- **Confirmed gap (not fixed, documented)**: no reconnection backoff for a
  flapping connection.
- **Confirmed gap (not fixed, documented)**: `MAX_TTL` is a
  separately-declared Kotlin constant with no enforced sync against
  Dart's `SecurityConstants.maxTTL` (currently both `5`, no live drift).
- **Re-verified, confirmed OK**: malformed JSON in `process()` is caught
  cleanly (`try/catch` around `JSONObject(String(bytes))`), no crash risk
  — this had been flagged for re-verification mid-sprint and was checked
  directly against source before this report was written.

## 6. Bugs Fixed

1. Thread-safety: `PacketRelayEngine.process()`, `rememberOriginated()`,
   `recentEchoCount()`, `noteSuppressedRelay()` now run inside
   `synchronized(lock)`. Closes a real race (two concurrent copies of the
   same packet both passing the dedup check before either records it).
2. Thread-safety: `NearbyConnectionsManager.connectedEndpoints` and
   `connectionStartedAtNanos` now `Collections.synchronizedSet`/`Map`;
   `broadcastBytes()` explicitly synchronizes on `connectedEndpoints`
   while iterating (required per `java.util` docs even for a synchronized
   wrapper).
3. Redundant-reconnection guard: `onEndpointFound` now returns early if
   the discovered endpoint is already in `connectedEndpoints`.

All three fixes are additive synchronization/guards only — every touched
method body is otherwise byte-for-byte identical to before. No relay
decision, dedup key, TTL value, or connection-acceptance logic changed.

## 7. Bugs Intentionally Not Fixed

| Bug | Why not fixed this pass |
|---|---|
| No signature verification in native | Porting Ed25519 verification into Kotlin is a substantial addition (crypto library, key-format handling, a second implementation to keep in sync with Dart) — explicitly outside "smallest safe fix" scope and outside this sprint's rule against crypto changes without a concrete, scoped decision |
| No authentication on connection acceptance | Real feature with UX implications (a pairing/trust step), not a mechanical patch |
| `START_STICKY` restart amnesia (dedup cache + policy reset) | Needs SharedPreferences persistence — a scoped feature addition, not a one-line fix |
| No reconnection backoff | Needs real-hardware timing validation before shipping a specific backoff curve — this sandbox cannot validate that |
| `MAX_TTL` Dart/Kotlin constant drift risk | Needs a shared source of truth (codegen or a build-time sync check) across two languages — infrastructure work, not a patch; both values are currently equal so there is no live drift today |
| No Bluetooth/Wi-Fi state-change auto-resume | Needs a `BroadcastReceiver` for adapter state changes — a real feature addition |
| `Nearby.getConnectionsClient()` unguarded at construction | Cannot confirm from source alone whether/how this can throw; changing error handling without being able to trigger the failure on a device risks masking a real crash with a silent no-op |

## 8. Dedup Behavior (native)

`LinkedHashSet<String>` keyed on `packet_id`, bounded 500, FIFO-evicted,
insertion before any TTL/signature check (no signature check exists to
order against). Thread-safety fixed this pass; eviction policy, cache
size, and key scheme unchanged. See `DEDUPLICATION.md`'s Correction note
and `NATIVE_MESH_AUDIT.md` §4/§6.

## 9. TTL Behavior (native)

`nextTtl()` is a hand-maintained mirror of Dart's `AdaptiveTtl.nextTtl` —
same invariants (`result <= MAX_TTL`, `result < input`, `result >= 0`),
same stale-packet extra-decrement rule. `MAX_TTL = 5`, declared separately
from Dart's equivalent constant with no enforced sync (see §7). Confirmed
unchanged this pass. See `TTL.md`'s Correction note and
`NATIVE_MESH_AUDIT.md` §7.

## 10. ACK Behavior (native)

No ack construction in native at all — an `AckPacket`'s bytes are just
another payload to `PacketRelayEngine.process()`, deduped/TTL'd/relayed
identically to any other packet type. Native can relay an ack it didn't
originate but can never originate one itself. See `ACK_LIFECYCLE.md`'s
Native Layer section and `NATIVE_MESH_AUDIT.md` §9/§10.

## 11. Connection Behavior (native)

Lexicographic tie-break (`localEndpointName < info.endpointName`)
confirmed correct — resolves Sprint 1's "unverifiable" flag on this item.
Auto-accept on `onConnectionInitiated` confirmed to have no
authentication check (§7). Redundant-reconnection guard added this pass.
`onDisconnected` cleanup confirmed correct. See `NATIVE_MESH_AUDIT.md`
§2/§3/§11 and `NATIVE_FAILURE_MATRIX.md` rows 6/7.

## 12. Battery Behavior (native)

Zero direct battery checks in Kotlin — purely driven by
`allowRelay`/`discoveryIntervalMs` pushed from Dart via `updateMeshPolicy`.
Correctly re-checked at both duty-cycle timing and relay-dispatch time.
Resets to full-power defaults on a `START_STICKY` restart until Dart
re-syncs (§7). See `NATIVE_MESH_AUDIT.md` §14.

## 13. Exit-Node Behavior (native)

Not a native concept — "exit node" is entirely Dart's
`hasRealInternet()` decision; native has no awareness of connectivity
beyond the policy flags it receives. See `NATIVE_MESH_AUDIT.md` §15.

## 14. Security Observations

The most significant finding of this sprint: while a device is
backgrounded with only the native foreground service alive (a real,
common app state), it will relay any well-formed JSON blob claiming valid
`packet_id`/`ttl`/etc. fields, with **zero signature verification** —
signature checking is Dart-only. An end-to-end forged packet is still
rejected once it reaches a device with Dart attached (the receiving
device's `_handlePayload` verifies before acting on it), but intermediate
backgrounded native-only hops will faithfully relay it further. Not fixed
this pass (§7) — flagged as the top item for a future, deliberately-scoped
security pass. Connection-level auto-accept with no authentication is a
related, lower-severity finding (an unauthenticated *connection* is not
the same as an unauthenticated *packet*, since the signature gate still
exists one layer up for any Dart-attached device).

## 15. Performance Observations

No real numbers exist or were invented — this sandbox has no devices to
measure with. `discoveryLatencyMicros`/`connectionLatencyMicros` are
already instrumented in `NearbyConnectionsManager` (from Sprint 1's
review) and are the right numbers to capture once real hardware is
available; `MULTI_DEVICE_TEST_PLAN.md` Scenario 1 doubles as a first
real-world latency measurement opportunity (elapsed time from origination
to "Delivered"). No measurement plan beyond "use the existing
instrumentation and this test plan" was needed — nothing new had to be
built.

## 16. Test Infrastructure

**Confirmed none exists.** No `test/`/`androidTest/` directories, zero
`*Test*.kt` files, no test dependencies in `build.gradle.kts`. Not built
this pass — per the brief, the missing infrastructure is documented, not
papered over with tests that couldn't actually be compiled or run in this
sandbox (no Flutter/Android toolchain — see §17).

## 17. Real-Device Results

**BLOCKED — no physical devices available to this sandbox session.**
`MULTI_DEVICE_TEST_PLAN.md` (4 scenarios) is the plan for whoever next has
hardware; none of it has been executed. Stated plainly, consistent with
this sprint's explicit rule against claiming device-testing results
without actual devices.

## 18. Blocked Tests / Build Validation

**BLOCKED.** Attempted `./gradlew tasks --offline` from
`setu_app/android/`: Gradle wrapper needs to download `gradle-9.1.0-all`
and the sandbox's network proxy returns `HTTP/1.1 403 Forbidden` on the
tunnel to `services.gradle.org` — full stack trace captured during this
session. No Flutter SDK is installed (`flutter`/`dart` not found on
`PATH`), so `flutter analyze`, `flutter test`, and any Flutter-side build
step are equally unavailable. `java` and a standalone `gradle` binary
(`/opt/gradle/bin/gradle`) ARE present, but the wrapper-pinned version
still needs network access this sandbox's proxy denies. This is the same
toolchain limitation reported (and not resolved) in every prior session of
this engagement — restated here rather than silently assumed unchanged.

## 19. Relayed-State Conclusion

Design-only, not implemented — see `RELAYED_STATE_DESIGN.md` in full.
Summary: representing "Relayed" requires a genuinely new, unsigned,
best-effort protocol event (the existing `AckPacket` is end-to-end by
design and its `signaturePayload` is frozen), would naturally originate
from native Kotlin's `PacketRelayEngine` (the first time native would
originate a packet rather than only relay one), and carries a real
airtime/battery cost in exactly the resource-constrained scenario this app
exists for. Recommended: not implemented without a deliberate product
decision weighing that cost against the UX value.

## 20. Remaining Risks

- Native has no signature verification (§14) — the top open security
  item.
- `START_STICKY` restart amnesia means a killed-and-restarted service
  briefly ignores its last-known battery tier.
- No reconnection backoff — a flapping connection in marginal range could
  generate a meaningful amount of reconnect traffic; severity unknown
  without real-hardware data.
- `MAX_TTL` drift risk between Dart and Kotlin has no enforced guard — low
  likelihood, but silent if it ever happens.
- This sprint's own two fixes (thread-safety, reconnection guard) have
  **not been validated on real hardware or even compiled** — they are
  believed correct from careful source review and byte-for-byte diffing
  against the original method bodies, but that is not the same as a
  passing build or a passing device test. This is the single most
  important caveat on this entire sprint's work and is repeated here
  deliberately, not just in §17/§18.

## 21. Recommended Next Work

1. Get this branch onto a machine with a working Flutter/Android
   toolchain and actually run `flutter analyze` / `./gradlew build` to
   catch anything a static read missed (a real risk, given the fixes were
   never compiled).
2. Run `MULTI_DEVICE_TEST_PLAN.md`'s 4 scenarios on real hardware —
   Scenario 4 (the 4-device ring) is the most important one, since it's
   the first real exercise of this sprint's thread-safety fix under
   genuine concurrent callback delivery.
3. A deliberate, scoped decision (not a quiet patch) on native signature
   verification — the top remaining security gap.
4. A deliberate decision on connection-level authentication.
5. A scoped SharedPreferences-persistence fix for `START_STICKY` restart
   amnesia.
6. Team decision on whether "Relayed" state is worth its airtime/battery
   cost, per `RELAYED_STATE_DESIGN.md`.

## 22. Commit Hashes

On branch `feature/vib-native-mesh` (from `feature/vib-mesh-hardening`,
which sits on `main` at `850e3c9`):

```
3a33479  audit: document native mesh architecture (Kotlin dedup/TTL/relay confirmed non-trivial)
445d005  fix: harden native relay/connection thread-safety, guard redundant reconnects
3479285  docs: document native mesh failure matrix (18 scenarios)
2aec857  docs: add multi-device validation plan (4 physical-device scenarios)
0e80d50  docs: relayed-state design analysis (design-only, not implemented)
bcc7f95  docs: cross-reference native findings into existing mesh docs
```
(hashes are from this sandbox's local clone; they will differ once you
apply the diff to your own clone and commit — the commit messages and
diff content are what matters, not these exact hex values)

## Definition of Done

| # | Item | Status |
|---|---|---|
| 1 | Full native Kotlin audit (`NATIVE_MESH_AUDIT.md`) | **DONE** |
| 2 | Native dedup verification, smallest safe fix only | **DONE** (thread-safety fixed; cache size/eviction/key scheme untouched) |
| 3 | Relay-loop test design analysis (4 topologies) | **DONE** (`MULTI_DEVICE_TEST_PLAN.md` Scenario 4 + `NATIVE_FAILURE_MATRIX.md` row 14) |
| 4 | Endpoint tie-break audit | **DONE** (confirmed correct, resolves Sprint 1's "unverifiable" flag) |
| 5 | Connection lifecycle audit | **DONE** |
| 6 | ACK path native audit | **DONE** |
| 7 | Signature + replay audit | **DONE** (confirmed absent in native; not fixed, documented as top risk) |
| 8 | TTL native audit | **DONE** |
| 9 | Battery native audit | **DONE** |
| 10 | Store-and-forward native audit | **DONE** (native has none of its own; correctly delegates to Dart) |
| 11 | Exit-node native audit | **DONE** (not a native concept, confirmed) |
| 12 | Thread-safety audit | **DONE**, with fixes applied |
| 13 | `NATIVE_FAILURE_MATRIX.md` | **DONE** |
| 14 | `MULTI_DEVICE_TEST_PLAN.md` | **DONE** (plan only, per brief — no simulator built) |
| 15 | Real-device validation attempt | **BLOCKED** — no hardware available |
| 16 | Performance baseline | **PARTIALLY DONE** — measurement plan only, no numbers (no hardware) |
| 17 | Observability extension | **DONE** (reused existing layer, see `OBSERVABILITY.md`) |
| 18 | `RELAYED_STATE_DESIGN.md` | **DONE** (design-only, explicitly not implemented) |
| 19 | Automated tests | **NOT DONE** — no test infrastructure exists; documented rather than faked |
| 20 | Build validation attempts | **BLOCKED** — documented exact reasons (§18) |
| 21 | Code-quality pass / dead-code re-confirmation | **DONE** — `home_screen.dart` re-confirmed still orphaned (no import anywhere outside a comment) |
| 22 | Git discipline (new branch, logical commits) | **DONE** — `feature/vib-native-mesh`, 6 commits, not pushed to main |

**Overall sprint status: substantially complete for everything achievable
without a working Android/Flutter toolchain or physical devices. The two
hard blockers (build validation, real-device testing) are documented
exactly, not worked around or faked.**
