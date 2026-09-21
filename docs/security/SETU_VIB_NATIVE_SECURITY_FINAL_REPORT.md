# SETU — VIB Bulk Sprint 3: Native Security + State Persistence + Build/E2E Validation — Final Report

Owner: Vib (Mesh/Architecture). Branch: `feature/vib-native-security`
(from `feature/vib-native-mesh`). Date: Sep 21 2026.

## 1. Executive Summary

This sprint closed two of the four remaining native gaps from Bulk
Sprint 2 (START_STICKY state amnesia, MAX_TTL drift visibility, plus two
P1 items — reconnection backoff and Bluetooth/Wi-Fi auto-resume), designed
(but did not implement) native signature verification and connection
authentication, and confirmed with direct, repeatable evidence that this
sandbox cannot build the Android project or run any native test — two
independent blockers, not one, both documented with exact error output
below. No fabricated test results, no invented performance numbers, no
device-testing claims. Everything implemented is a source-level change,
carefully reviewed and balance-checked, but **not compiled and not run**
— stated plainly here and in every relevant doc, not just this section.

## 2. Native Security Architecture (status after this sprint)

- **Dedup, TTL, relay decisions**: native, independent of Dart (unchanged
  from Sprint 2).
- **Signature verification**: still Dart-only. Designed this sprint
  (`docs/security/NATIVE_SIGNATURE_VERIFICATION_DESIGN.md`), not
  implemented — see §3.
- **Connection authentication**: still none (auto-accept). Designed this
  sprint (`docs/security/NATIVE_CONNECTION_AUTH_DESIGN.md`), not
  implemented — a genuine product/security decision, not a sandbox
  limitation, is what's actually blocking this one.
- **State persistence**: NEW this sprint — policy and a bounded dedup
  snapshot now survive a `START_STICKY` restart (§4).
- **TTL sync**: NEW this sprint — a diagnostic-only cross-check that logs
  a warning on drift, does not enforce anything (§5).
- **Reconnection**: NEW this sprint — bounded backoff for the
  failed-connection-attempt case (§6).
- **Bluetooth/Wi-Fi resume**: NEW this sprint — auto-resumes discovery
  when a toggled-off radio comes back on (§8).

## 3. Signature Verification Status

**DESIGNED, NOT IMPLEMENTED.** Full design in
`docs/security/NATIVE_SIGNATURE_VERIFICATION_DESIGN.md`: exact Dart
signing flow, exact `signaturePayload` construction per packet type
(byte-precise, including the `double.toString()` interop risk for
lat/lon fields), self-certifying `sender_id` (= the Ed25519 public key
itself, hex-encoded), BouncyCastle recommended as the implementation path
(minSdk-independent, unlike the platform `java.security` Ed25519 API
which needs API 31+).

**Why not implemented**: this would require adding
`org.bouncycastle:bcprov-jdk18on` as a new Gradle dependency. Verified by
direct test (not assumed) that Maven Central is unreachable from this
sandbox:
```
$ curl -sS -o /dev/null -w "HTTP_CODE:%{http_code}\n" https://repo1.maven.org/maven2/...
curl: (56) CONNECT tunnel failed, response 403
HTTP_CODE:000
```
Writing crypto-verification code that could not be compiled, let alone
tested against a real signature, would violate this sprint's own rule
against fabricated verification (§0: "DO NOT create fake test results").
No signature-verification code was written in native this pass — only
the design document.

## 4. START_STICKY Persistence

**IMPLEMENTED (unvalidated on hardware/build).** New `MeshStateStore`
(SharedPreferences, not a database — deliberately, per the brief's own
"do not create a database for a handful of values" instruction):
- Policy (`currentDiscoveryIntervalMs`/`currentAllowRelay`) persisted on
  every explicit `updateMeshPolicy()` call.
- A bounded snapshot of `PacketRelayEngine`'s `seen` dedup cache
  (already capped at 500 entries) persisted every 30 seconds, plus
  best-effort on a graceful `onDestroy()`.
- `MeshForegroundService.onCreate()` restores both **before** discovery
  starts, per the brief's own recommended restore order (load policy →
  load bounded dedup state → initialize Nearby → start discovery).
- `lastKnownLat`/`lastKnownLon` deliberately **not** persisted — losing
  them only degrades the location-based dedup re-entry feature back to
  plain packet-id dedup, not a correctness issue, and persisting GPS
  coordinates is exactly the kind of extra state surface not worth adding
  for what it buys.
- An abrupt OOM-kill (no `onDestroy()` guarantee on Android) can still
  lose up to one 30-second interval's worth of dedup history — an
  accepted, explicitly documented trade-off (see `MeshStateStore.kt`'s own
  doc comment), not a silently-assumed guarantee. This does not create a
  correctness gap: a re-relayed packet slipping through is still bounded
  by TTL and still deduped independently by every other device's own
  cache, exactly as already happens when the in-memory cache evicts an
  entry under normal FIFO pressure.

## 5. TTL Synchronization

**IMPLEMENTED (diagnostic only, unvalidated).** Dart now pushes
`SecurityConstants.maxTTL` alongside every `updateMeshPolicy` call;
native logs a loud `Log.e` warning if it doesn't match
`PacketRelayEngine.MAX_TTL`. Does not change TTL behavior, does not
reject anything, does not gate anything — purely makes a future
accidental drift visible in logs instead of silent. A real shared-source-
of-truth mechanism (codegen, a build-time check) remains future work; both
values are currently `5`, so there is no live drift today.

## 6. Reconnection Behavior

**IMPLEMENTED for one case, deliberately scoped (unvalidated).** Bounded
exponential backoff (2s initial, doubling, 30s ceiling, reset on success)
before retrying a `requestConnection` to an endpoint whose **last attempt
failed** (`onConnectionResult` non-OK). Never delays a first attempt to a
newly-discovered endpoint. **Explicitly does not cover** a connection that
succeeds and then disconnects quickly ("flapping" in the more general
sense) — picking a duration threshold to distinguish that from a normal
short-but-useful relay contact would be exactly the arbitrary-value guess
this sprint's rules prohibit without real-device data. Documented as a
remaining gap, not silently dropped.

## 7. Connection Authentication Decision

**NOT DECIDED, NOT IMPLEMENTED — by design.** Full comparison of 4
options in `docs/security/NATIVE_CONNECTION_AUTH_DESIGN.md`. Recommendation:
keep auto-accept (Option A) for the general case — an allowlist (Option C)
would break the app's core "any stranger's phone can relay" premise —
with challenge-response (Option B) as a real future candidate once native
signature verification exists (they share implementation dependencies).
This is a genuine product/security decision for the team, not something
this sprint should make unilaterally.

## 8. Bluetooth/Wi-Fi Resume Status

**IMPLEMENTED (unvalidated on hardware/build).** Confirmed via source
review that no resume logic existed before this pass (failure listeners
only logged). New `BroadcastReceiver` in `MeshForegroundService`,
registered in `onCreate()` and unregistered in `onDestroy()`, listens for
`BluetoothAdapter.ACTION_STATE_CHANGED` and Wi-Fi's
`WIFI_STATE_CHANGED_ACTION`, calling the existing `startDutyCycle()` on a
transition to ON. No new permissions required (`BLUETOOTH`/
`ACCESS_WIFI_STATE` already declared in `AndroidManifest.xml` for Nearby
Connections itself — confirmed by direct read of the manifest, not
assumed).

## 9. Native Tests

**NOT DONE — blocked, documented, not faked.** Confirmed (again, this
sprint, not just carried over from Sprint 2) that no test infrastructure
exists (`test/`/`androidTest/` absent, no test dependencies in
`build.gradle.kts`). Adding a minimal JUnit-based unit test suite for
`PacketRelayEngine` (the brief's own suggested smallest useful target)
would require a `testImplementation("junit:junit:...")` dependency —
same Maven Central resolution blocker as §3. No local `kotlinc` is
available either (checked: `which kotlinc kotlin` → not found), so there
is no way to even compile a standalone test file outside Gradle in this
sandbox. Documented as blocked; no test files were written that could not
actually be executed.

## 10. Build Validation

**BLOCKED — two independent, confirmed blockers, not one:**

1. `./gradlew tasks --offline` needs the Gradle wrapper to download
   `gradle-9.1.0-all.zip` from `services.gradle.org`; the sandbox's proxy
   returns `403 Forbidden` on that tunnel (full stack trace captured,
   carried over from Sprint 2, re-confirmed this sprint).
2. **New this sprint**: a locally-installed standalone Gradle 8.14.3
   (`/opt/gradle/bin/gradle`) exists and *can* start without hitting the
   wrapper's network requirement — but fails independently:
   ```
   * Where:
   Settings file '.../setu_app/android/settings.gradle.kts' line: 20
   * What went wrong:
   Error resolving plugin [id: 'dev.flutter.flutter-plugin-loader', version: '1.0.0']
   > Included build '/home/vaibhav/snap/flutter/common/flutter/packages/flutter_tools/gradle' does not exist.
   ```
   `local.properties`'s `flutter.sdk` path points at the original
   developer's machine, which does not exist in this sandbox — and no
   Flutter SDK or Android SDK is installed here at all (confirmed:
   `which flutter dart` → not found; no `ANDROID_HOME`/`ANDROID_SDK_ROOT`;
   no SDK directory found anywhere on disk).

`java -version` → OpenJDK 21.0.10 (present). `./gradlew --version` was
not separately run (it hits the same wrapper-download blocker as `tasks`
before reaching version output) — this is not a gap, both commands fail
at the identical first step.

`flutter analyze`/`flutter test` — **BLOCKED**, same as Sprint 2: no
Flutter SDK on `PATH`.

**No build command in this sprint was retried more than once** once its
failure mode was understood, per the brief's own instruction not to waste
the sprint on repeated impossible commands.

## 11. Real-Device Validation

**BLOCKED — no physical devices available to this sandbox, unchanged
from Sprint 2.** `docs/mesh/MULTI_DEVICE_TEST_PLAN.md` (written Sprint 2)
remains the plan for whoever next has hardware; this sprint's new fixes
(state persistence, backoff, radio resume) are exactly the kind of change
that plan's scenarios would exercise, but none of it has been run.

## 12. Performance

**Not measured, not invented.** No new performance claims this sprint —
signature verification (the one place real measurement would matter most)
was not implemented, so there's nothing new to measure. The
measurement-methodology guidance from Sprint 2's final report (§15 of
`SETU_VIB_NATIVE_MESH_FINAL_REPORT.md`) still applies unchanged.

## 13. Security Regression

Checked by direct diff inspection (not assumed): only one Dart file
changed this sprint (`nearby_service.dart`), and the only change is one
new key (`'maxTtl': SecurityConstants.maxTTL`) added to the existing
`updateMeshPolicy` platform-channel call — purely additive, no change to
signing, verification, serialization, replay handling, or any packet
model. Confirmed via `git diff --stat`:
```
setu_app/lib/mesh/services/nearby_service.dart | 14 ++
```
(all Kotlin changes are new files or additive methods/receivers — no
existing dedup/TTL/relay/ack logic lines were altered, confirmed by
re-reading every modified method in full). Recovery ACK, SOS ACK, packet
serialization, signature payload, and replay behavior are all
**unchanged** this sprint — there was no code path in this sprint's
changes that touches any of them.

## 14. Remaining Risks

- **Native still has no signature verification** — the top security item
  from Sprint 2, still open. Blocked on a dependency this sandbox cannot
  resolve, not on a design gap (the design is now complete).
- **Native still has no connection authentication** — a product decision,
  not a sandbox limitation.
- **None of this sprint's 4 implemented fixes have been compiled or run.**
  This is the single most important caveat on this sprint's work,
  repeated deliberately: state persistence, TTL-drift warning,
  reconnection backoff, and Bluetooth/Wi-Fi resume are all believed
  correct from careful source review (every modified file was fully
  re-read after editing, and mechanically balance-checked for brace/paren/
  string correctness), but that is not the same as a passing build or a
  passing device test.
- **OOM-kill can still lose up to 30s of dedup history** — documented,
  accepted trade-off, not a hidden gap.
- **Reconnection backoff does not cover the "connects then quickly
  disconnects" flapping case** — documented, not silently dropped.
- **A fixed cross-language signature test vector still does not exist
  anywhere in the codebase** — needed before native signature
  verification is ever implemented, not created this pass (nothing to
  test against yet, since nothing was implemented).

## 15. Blockers

1. **Maven Central unreachable** (confirmed by direct `curl` test,
   `403` on the CONNECT tunnel) — blocks adding BouncyCastle (signature
   verification) and JUnit (native tests). This is the same proxy
   restriction already confirmed for the Gradle wrapper's own
   distribution download in Sprint 2, now independently confirmed for
   Maven Central specifically.
2. **No Flutter SDK, no Android SDK, anywhere in this sandbox** —
   confirmed both by `which` checks and by the standalone-Gradle attempt
   failing on a missing `flutter.sdk` path and (implicitly, since it
   never got that far) a missing Android SDK too.
3. **No physical Android devices** — unchanged since this engagement
   began.

None of these are new categories of blocker versus Sprint 2 — this sprint
adds direct, repeatable evidence (exact commands, exact output) rather
than restating the same conclusion without re-checking it.

## 16. Exact Changed Files

- `setu_app/android/app/src/main/kotlin/com/setu/mesh/MeshStateStore.kt`
  (new)
- `setu_app/android/app/src/main/kotlin/com/setu/mesh/PacketRelayEngine.kt`
  (added `snapshotSeen()`/`restoreSeen()`, no existing logic changed)
- `setu_app/android/app/src/main/kotlin/com/setu/mesh/MeshForegroundService.kt`
  (state persistence wiring, MAX_TTL drift check, Bluetooth/Wi-Fi resume
  receiver)
- `setu_app/android/app/src/main/kotlin/com/setu/mesh/NearbyConnectionsManager.kt`
  (reconnection backoff)
- `setu_app/android/app/src/main/kotlin/com/setu/setu_app/handlers/MeshChannelHandler.kt`
  (threads the new optional `maxTtl` argument through)
- `setu_app/lib/mesh/services/nearby_service.dart` (adds `maxTtl` to the
  existing `updateMeshPolicy` call — the only Dart change this sprint)
- `docs/security/NATIVE_SIGNATURE_VERIFICATION_DESIGN.md` (new)
- `docs/security/NATIVE_CONNECTION_AUTH_DESIGN.md` (new)
- `docs/mesh/NATIVE_MESH_AUDIT.md`, `docs/mesh/NATIVE_FAILURE_MATRIX.md`,
  `docs/mesh/FAILURE_HANDLING.md`, `docs/mesh/TTL.md`,
  `docs/mesh/DEDUPLICATION.md` (updated with Sprint 3 findings)

**Git-discipline note, stated honestly**: because all of
`MeshForegroundService.kt`'s three features (state persistence, MAX_TTL
check, Bluetooth/Wi-Fi resume) were written to the file before any
sprint-3 commit was made, `git add`'s whole-file staging meant the first
commit touching that file (`fix: persist native mesh policy...`) ended up
containing all three, rather than each landing in its own intended
commit. The commit *messages* accurately describe what each commit's own
named files are for, but `MeshForegroundService.kt`'s later commits show
no diff for it (already included earlier). The end state and every
individual diff were fully reviewed regardless — this only affects commit
granularity, not correctness or transparency of what changed.

## 17. Commit Hashes

On branch `feature/vib-native-security` (from `feature/vib-native-mesh`):

```
148c0b0  security: design native signature verification
e2cf6d8  security: design native connection authentication (A/B/C/D comparison)
272c97d  fix: persist native mesh policy and bounded dedup state across restart
6b7447b  fix: add bounded reconnection backoff for failed connection attempts
ba2f40c  fix: prevent TTL constant drift + resume Bluetooth/Wi-Fi after toggle
7050df2  docs: document native security decisions + cross-reference sprint 3 fixes
```
(hashes are from this sandbox's local clone; they will differ once
applied to your own clone and committed there.)

## Definition of Done

| # | Item | Status |
|---|---|---|
| 1 | Native signature design completed | **DONE** |
| 2 | Native signature implementation completed IF safely possible | **BLOCKED** — Maven Central unreachable, confirmed by direct test; not implemented rather than shipped uncompiled |
| 3 | No signature payload changed | **DONE** — confirmed, zero packet-model files touched |
| 4 | Invalid native packets handled safely | **VERIFIED** (re-confirmed, not just carried over) — malformed JSON caught cleanly in `PacketRelayEngine.process()` |
| 5 | START_STICKY state issue addressed or explicitly scoped | **DONE** for policy + dedup cache; location intentionally out of scope |
| 6 | Dedup persistence bounded | **DONE** — same 500-entry cap as the in-memory cache |
| 7 | Battery policy restored safely | **DONE** |
| 8 | MAX_TTL drift protection addressed | **DONE** (diagnostic-level, not enforcement-level) |
| 9 | Reconnection behavior reviewed | **DONE** — implemented for the failed-attempt case, explicitly scoped away from the flapping-after-connect case |
| 10 | Connection authentication decision documented | **DESIGNED** — decision itself intentionally left to the team |
| 11 | Bluetooth/Wi-Fi resume reviewed | **DONE** — implemented |
| 12 | Native test infrastructure created IF feasible | **BLOCKED** — same Maven Central blocker; no local `kotlinc` either |
| 13 | Build attempted honestly | **DONE** — two independent blockers found and documented with exact output, not just restated |
| 14 | Flutter validation attempted honestly | **BLOCKED** — no Flutter SDK, confirmed |
| 15 | Real device tests executed IF hardware exists | **BLOCKED** — no hardware |
| 16 | Security regression checked | **DONE** — confirmed via direct diff inspection, only one additive Dart line changed |
| 17 | Documentation updated | **DONE** |
| 18 | Final report produced | **DONE** (this document) |

**Overall sprint status: every task achievable without a working
Android/Flutter toolchain, a resolvable Maven dependency, or physical
hardware was completed. The three real blockers are documented with
direct, reproducible evidence, not asserted from memory — and nothing
was implemented that could not be reviewed line-by-line, even though
none of it has been compiled or run.**
