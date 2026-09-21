# SETU — Native Signature Closure + Build Recovery + Validation Readiness
## Bulk Sprint 4 Final Report

Owner: Vib (Mesh/Architecture). Branch: `feature/vib-security-closure`
(from `feature/vib-native-security`). Written Sep 21 2026.

---

## 1. Executive Summary

This sprint closes the single gap every prior sprint's report flagged as
the top open risk: the native Kotlin relay layer processed packets
(dedup, TTL, rebroadcast) without ever checking their signature, so a
device with Dart fully detached would relay a forged packet exactly as
readily as a real one. That gap is now closed in code:
`PacketRelayEngine.process()` verifies every packet's Ed25519 signature,
via a new `SignatureVerifier.kt`, before it is admitted to the dedup
cache or considered for relay at all.

Alongside that, this sprint made a real, evidence-based correction to
Sprint 3's conclusion that native testing was "fully blocked": it is not
— the Kotlin compiler and JUnit are both genuinely available in this
sandbox (bundled inside the local Gradle install), and were actually
invoked, with real compiled-and-executed output. The remaining, sharper
blocker for testing `PacketRelayEngine`/`SignatureVerifier` specifically
is one missing dependency (`org.json`), not a missing toolchain — a
smaller, better-understood problem than before.

What remains genuinely unverified, stated plainly: `SignatureVerifier.kt`
itself has never been compiled (the underlying BouncyCastle primitive
has, standalone, with real output); no real Android/Gradle build has
happened in any of the four sprints of this engagement; no physical
device has ever run any of this code.

## 2. Native Signature Status

**Design → Implementation, this sprint**: `SignatureVerifier.kt` (new)
implements `verify()` (BouncyCastle `Ed25519Signer`, never throws, false
on any malformed input — matching `SigningService.verify()`'s Dart
contract), `buildSignaturePayload()` (exact per-type pipe-delimited
payload reconstruction, using a raw-JSON-text regex extractor for
`latitude`/`longitude` to avoid the `double.toString()` interop risk),
and `verifyPacket()` (combined entry point). Wired into
`PacketRelayEngine.process()` immediately after the `packet_id`
emptiness check and before the dedup-cache lookup — see the code comment
at that exact call site for the full reasoning. A new `signatureFailures`
counter tracks rejections, exposed through the existing
`relayStats()`/`getRelayStats` channel.

**What has and hasn't been proven**: the BouncyCastle Ed25519 primitive
itself — the same `Ed25519PublicKeyParameters`/`Ed25519Signer` API calls
`SignatureVerifier.kt` uses — was proven correct with real, executed
output via a standalone Java harness (§3). `SignatureVerifier.kt` as a
Kotlin file has not itself been compiled (§4/§5). See
`docs/mesh/FINAL_VALIDATION_MATRIX.md` row 13 for the precise,
non-conflated statement of this distinction.

## 3. Crypto Test Vector

`tools/Ed25519VectorTest.java`, compiled with `javac` and run with `java`
against the locally-available `/usr/share/java/bcprov-1.77.jar`
(`org.bouncycastle:bcprov:1.77`, found this sprint via the OS's Debian
package repository — a real Maven-coordinate artifact, not an invented
one). Produces a deterministic, fixed-seed Ed25519 keypair, signs a
fixed `EmergencyPacket`-shaped payload, and runs 10 negative cases
(modified message/location/timestamp/sender_id/signature, malformed
public key, malformed signature, non-hex public key, empty signature),
all passing as expected, zero crashes. Full verbatim output in
`docs/security/NATIVE_SIGNATURE_TEST_VECTOR.md`, labeled **GENERATED
(Java/BouncyCastle), not Dart-executed** — the Dart SDK remains
unavailable, so this is not a cross-language interop proof, only proof
that the chosen crypto primitive itself is sound for SETU's wire format.

`tools/RawFieldExtractTest.java` separately validates, with 10/10 real
passing cases, the raw-JSON-number-extraction regex that
`SignatureVerifier.extractRawNumberField()` uses.

## 4. Dependency Status

- **BouncyCastle**: real project dependency declared as
  `org.bouncycastle:bcprov-jdk18on:1.78.1` (standard Maven Central
  coordinate — deliberately NOT the sandbox-local file path used only for
  offline validation). Not yet resolved/compiled against the real project
  (Maven Central network-blocked in this sandbox, confirmed again this
  sprint).
- **org.json:json:20231013**: added as a `testImplementation` for local
  JVM unit tests (Android's bundled `org.json` is a stub outside a real
  device/emulator — this is the standard workaround). Also not locally
  resolvable here — this is the specific, sharper blocker for compiling
  `PacketRelayEngineTest.kt`/`SignatureVerifier.kt`/`PacketRelayEngine.kt`
  in this sandbox (see `docs/mesh/NATIVE_TEST_INFRASTRUCTURE.md`).
- **junit:junit:4.13.2**: added as `testImplementation`. Genuinely
  locally available in this sandbox (bundled with the local Gradle
  install) and actually used — see §5.

## 5. START_STICKY Validation

No code change this sprint (Sprint 3 already implemented this). Reviewed
for edge cases per brief §9: corrupt-preferences handling, empty state,
cache boundary (500/501st entry), restart-with-empty-cache, duplicate/
stale IDs, rapid restart, unbounded-value risk, and stale-policy relay
escalation. **No defect found** — full row-by-row reasoning in
`docs/mesh/SPRINT4_EDGE_CASE_REVIEW.md` §1. This is a review-and-confirm
result, not a device-tested one.

## 6. Dedup Persistence Validation

Covered together with §5 above (`MeshStateStore`/`PacketRelayEngine`
share the same review) — see `SPRINT4_EDGE_CASE_REVIEW.md` §1, same
"no defect found" result. Additionally, `PacketRelayEngineTest.kt`'s
`process_invalidSignature_isNotAdmittedToDedupCache` test (written, not
yet executed — see §4) specifically asserts the new Sprint 4 invariant
that a signature-rejected packet must never poison the dedup cache.

## 7. Reconnect Validation

No code change this sprint. Reviewed per brief §11: first-attempt is
never delayed, backoff is strictly per-endpoint (no shared/global state),
`stopAll()` clears both backoff maps cleanly. **No defect found** — see
`SPRINT4_EDGE_CASE_REVIEW.md` §2.

## 8. Radio Resume Validation

No code change this sprint. Reviewed per brief §12: receiver registration
happens exactly once per service instance (standard `onCreate()`
lifecycle guarantee), cleanup in `onDestroy()` is correct, and a rapid
Bluetooth/Wi-Fi toggle storm degrades to redundant-but-harmless repeated
calls into an already-idempotent `startDutyCycle()` — not a leak or
crash risk. **No defect found.** The one explicit scope boundary (no
debounce for a toggle storm) is restated as a deliberate decision in
`SPRINT4_EDGE_CASE_REVIEW.md` §2, not a silently-missed case.

## 9. TTL Validation

`nextTtl()` — the one piece of `PacketRelayEngine` with zero missing-
dependency blockers — was actually compiled with a real `kotlinc`
(bundled inside the local Gradle install, invoked directly — a new
finding this sprint, see §11) and run under the real JUnit 4.13.2
runner: **13/13 tests passed, real captured output**
(`tools/NativeLogicTest.kt`), covering normal decrement, stale-non-
critical double decrement, stale-but-critical single decrement, a
hostile oversized `ttl=9999` input correctly clamped before decrementing,
boundary behavior at TTL 0 and 1, and negative input handling. This is
the strongest piece of executed evidence produced in this entire four-
sprint engagement.

## 10. Connection Authentication Decision

Unchanged this sprint. `docs/security/NATIVE_CONNECTION_AUTH_DESIGN.md`
(Sprint 3) remains the current state: 4 options compared, current
behavior (auto-accept, Option A) kept as-is, Option B (challenge-
response) recommended as future work, explicitly marked **"DECISION
REQUIRED FROM TEAM."** No implementation this sprint, by design — the
brief's own instruction.

## 11. Native Test Infrastructure

The headline finding of this sprint's toolchain investigation:

- Sprint 3 concluded native testing was "fully blocked" — true as far as
  it checked, but incomplete.
- Sprint 4 re-checked, per the brief's own instruction to verify local
  caches before assuming blockage, and found: `kotlinc` IS invocable
  (`/opt/gradle-8.14.3/lib/kotlin-compiler-embeddable-2.0.21.jar` plus
  its transitive jars, all in the same directory — not on `PATH` as a
  binary, which is why Sprint 3's `which kotlinc` check found nothing,
  but genuinely present and runnable via `java -cp ...`), and JUnit
  4.13.2 IS locally available (bundled with the same Gradle install).
  Both were actually exercised, not just located — real compile, real
  run, real 13/13 pass (§9).
- The real, sharper remaining blocker is `org.json` — confirmed absent
  from this sandbox by an exhaustive filesystem search, including
  Gradle's own bundled jars and the OS Maven repo that supplied
  BouncyCastle. This blocks compiling
  `PacketRelayEngineTest.kt`/`SignatureVerifier.kt`/`PacketRelayEngine.kt`
  specifically, standalone or via Gradle.
- Full breakdown, including exactly which files were executed vs.
  written-but-not-run, in `docs/mesh/NATIVE_TEST_INFRASTRUCTURE.md`.

## 12. Build Status

No change from Sprint 3's confirmed blockers: no Flutter SDK, no Dart
SDK, no Android SDK anywhere in this sandbox;
`setu_app/android/gradlew`'s wrapper distribution download is network-
blocked; the local standalone Gradle 8.14.3 can't build this specific
project because `local.properties`'s `flutter.sdk` path points to the
original developer's machine. Full detail, plus every command a real
developer machine needs, now in `docs/BUILD_AND_VALIDATION.md` (new this
sprint).

## 13. CI Status

`.github/workflows/setu-ci.yml` added this sprint — `flutter analyze`/
`flutter test`, `./gradlew testDebugUnitTest`, and a debug-APK compile-
validation build, using only stable, well-known third-party actions and
no hardcoded secrets. **Never run anywhere** — no GitHub Actions runner
reachable from this sandbox. Reviewed for safety, not claimed as a
confirmed-green pipeline; two TODOs left inline (the real Flutter version
pin, and confirming the Android SDK setup step) for whoever first runs it
for real.

## 14. Real-Device Test Status

Unchanged: zero physical devices used across all four sprints of this
engagement. `docs/mesh/MULTI_DEVICE_TEST_PLAN.md` gained a compact
Device A/B/C/D operator checklist this sprint (14 scenarios, including
5 new rows for Sprint 3/4 features — invalid-signature rejection,
START_STICKY persistence across a forced restart, Bluetooth/Wi-Fi
toggle resume, power-saver duty cycling, an internet-restoration-from-
cold variant), but it remains a plan, not an executed test pass.

## 15. Security Regression

No existing security behavior was weakened or removed this sprint. The
frozen wire contracts (`EmergencyPacket`/`AckPacket`/`AlertPacket`/
`TerminationPacket` `signaturePayload`) were not touched.
`SignatureVerifier`'s payload reconstruction was built by reading the
real Dart source field-by-field (documented in Sprint 3's
`NATIVE_SIGNATURE_VERIFICATION_DESIGN.md`), not guessed or copied
blindly. The new verification gate is strictly additive — every packet
that would have been accepted before (i.e., every packet Dart itself
signed correctly) still passes; only forged/malformed/unsigned packets
are newly rejected, and only before they can pollute the dedup cache or
be relayed.

## 16. Remaining Risks

1. **`SignatureVerifier.kt` itself is unverified by compilation.** The
   crypto primitive it calls is proven; the file wiring it together is
   not. This is the single most important open item — see
   `docs/mesh/FINAL_VALIDATION_MATRIX.md` row 13.
2. **No real cross-language (Dart-signs, Kotlin-verifies) test exists.**
   The Dart SDK's continued unavailability across all four sprints means
   this has never been possible to produce here.
3. **Zero device testing across the entire engagement.** Every
   correctness claim beyond §9's executed JUnit run rests on manual
   source review.
4. **Connection authentication remains auto-accept.** A known, previously
   flagged, still-open design decision requiring team input — not a
   regression, not newly discovered.
5. **`org.json` resolution is the most likely single fix that unblocks
   the most remaining work** — real compilation of the entire native
   signature-verification feature, standalone, hinges on it.

## 17. Exact Changed Files

- `setu_app/android/app/src/main/kotlin/com/setu/mesh/SignatureVerifier.kt` (new)
- `setu_app/android/app/src/main/kotlin/com/setu/mesh/PacketRelayEngine.kt` (signature-gate wiring, `signatureFailures` counter)
- `setu_app/android/app/src/main/kotlin/com/setu/mesh/MeshForegroundService.kt` (`signatureFailures` exposed via `relayStats()`)
- `setu_app/android/app/build.gradle.kts` (BouncyCastle + test dependencies)
- `setu_app/android/app/src/test/kotlin/com/setu/mesh/PacketRelayEngineTest.kt` (new, written not executed)
- `docs/security/NATIVE_SIGNATURE_TEST_VECTOR.md` (new)
- `docs/mesh/SPRINT4_EDGE_CASE_REVIEW.md` (new)
- `docs/mesh/NATIVE_TEST_INFRASTRUCTURE.md` (new)
- `docs/mesh/FINAL_VALIDATION_MATRIX.md` (new)
- `docs/BUILD_AND_VALIDATION.md` (new)
- `docs/mesh/MULTI_DEVICE_TEST_PLAN.md` (extended with operator checklist)
- `.github/workflows/setu-ci.yml` (new)
- `tools/Ed25519VectorTest.java`, `tools/RawFieldExtractTest.java`, `tools/NativeLogicTest.kt` (new; the last one actually compiled and run this sprint)

## 18. Commit Hashes (branch `feature/vib-security-closure`)

| Hash | Message |
|---|---|
| `873853b` | test: add deterministic Ed25519 signature test vector |
| `553c7d7` | security: implement native Ed25519 signature verification |
| `35c4b93` | docs: review START_STICKY, dedup persistence, reconnect backoff, radio resume for edge cases |
| `3e00d60` | test: add native relay unit coverage |
| `fe80bc9` | ci: add setu validation workflow |
| `bd9099c` | docs: add build and validation guide, final validation matrix, operator checklist |

## 19. Definition of Done (18 items)

| # | Item | Status |
|---|---|---|
| 1 | Deterministic crypto test vector, honestly labeled | DONE — GENERATED, not Dart-executed |
| 2 | Kotlin crypto dependency evaluated (no blind add) | DONE — checked local caches first, found BouncyCastle real |
| 3 | Native signature verification implemented (if safe) | DONE — `SignatureVerifier.kt`, wired into `process()` |
| 4 | No blind copy of Dart logic / no renormalized numbers | DONE — raw-text extraction, exact payload reconstruction |
| 5 | Security negative tests run | PARTIAL — run against standalone harness (10 cases); not yet against integrated Kotlin `process()` (blocked, see §11) |
| 6 | Background-native path validated | DONE (by code-path reasoning) — verification now lives inside `process()` itself, so it runs regardless of Dart attachment; not device-tested |
| 7 | START_STICKY/dedup edge cases reviewed | DONE — no defect found |
| 8 | Reconnect backoff/radio resume reviewed | DONE — no defect found |
| 9 | MAX_TTL cross-check | UNCHANGED (Sprint 3) — diagnostic-only, still in place |
| 10 | Connection-auth decision finalized | NOT DONE, by design — decision required from team |
| 11 | Native test infrastructure | DONE — real finding (kotlinc/JUnit available), real 13/13 executed pass, remaining `org.json` blocker documented precisely |
| 12 | `docs/BUILD_AND_VALIDATION.md` | DONE |
| 13 | CI readiness | DONE — `.github/workflows/setu-ci.yml` added, never run |
| 14 | Multi-device operator checklist (14 scenarios) | DONE |
| 15 | `docs/mesh/FINAL_VALIDATION_MATRIX.md` | DONE |
| 16 | No feature creep | DONE — no UI, no new packet types, no routing changes |
| 17 | Git branch + logical commits | DONE — 6 commits, `feature/vib-security-closure` |
| 18 | Final report with honest classification | DONE — this document |

## 20. Final Status Classification

- **IMPLEMENTED**: native Ed25519 signature verification (`SignatureVerifier.kt`, wired into `PacketRelayEngine`), `signatureFailures` metric, CI workflow, BouncyCastle dependency declaration.
- **VERIFIED (real executed output)**: `nextTtl()`/`parseTimestampMillis()` (13/13 JUnit), the BouncyCastle Ed25519 primitive (10/10 sign/verify cases), the raw-JSON-number-extraction regex (10/10 cases).
- **DESIGNED, NOT IMPLEMENTED**: connection authentication (unchanged, by design).
- **BLOCKED**: real Android/Gradle compilation (no SDK), `org.json`-dependent unit tests (no local artifact), any real cross-language Dart↔Kotlin signature interop test (no Dart SDK), all device testing (no hardware).
- **NEXT**: resolve `org.json` (most likely single highest-leverage fix); get a real Flutter/Android SDK + network access onto a build machine or CI runner to actually execute `./gradlew assembleDebug` for the first time in this engagement's life; get physical devices for the Sprint 3/4 rows of the multi-device checklist; bring the connection-authentication decision to the team.
