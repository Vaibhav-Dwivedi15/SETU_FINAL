# SETU — VIB SPRINT 5 FINAL REPORT
## Native Security Integration + First Real Build Attempt + Cross-Language Validation Handoff

Owner: Vib (Mesh/Architecture). Branch: `feature/vib-integration-validation`
(from `feature/vib-security-closure`). Written Sep 21 2026.

---

## 1. Executive Summary

Sprint 5's mission was to convert Sprint 4's source-level implementation
into actual executable evidence, without adding features. That happened:
the real, unmodified `SignatureVerifier.kt` and `PacketRelayEngine.kt`
were compiled for the first time in this engagement's life, and the real
`PacketRelayEngineTest.kt` ran 20/20 tests with real captured JUnit
output — including, for the first time, tests of the ACCEPT path (a
genuinely BouncyCastle-signed valid packet), not just REJECT paths.

This was achieved by resolving the `org.json` blocker with a narrowly
scoped, extensively documented, test-only JSON shim — not the real
`org.json` artifact, and explicitly labeled as such everywhere it
matters. **This is real progress, but it is PARTIALLY VERIFIED, not fully
VERIFIED**: the real Android/Gradle build remains completely blocked
(confirmed again this sprint, with a sharper root cause than before: the
Flutter SDK is entirely absent from this sandbox, not just misconfigured
in `local.properties`), and cross-language Dart↔Kotlin interop remains
unproven (Dart SDK still unavailable) — though a fully executable handoff
package for that specific test now exists and was Kotlin-side
smoke-tested.

No architecture was touched. No packet formats, signature payloads, TTL
semantics, or routing changed. Connection authentication remains
unimplemented, by design. One small, real code fix was made outside the
"more tests" scope: signature rejections are now logged (previously
silent except for a counter), without exposing any sensitive data.

## 2. Starting Commit

`a0f1451` — `docs: native security closure sprint final report`, tip of
`feature/vib-security-closure`. Working tree clean at start (confirmed via
`git status`).

## 3. Branch

`feature/vib-integration-validation`, created from `feature/vib-security-closure`.

## 4. Environment Inventory

Real commands run this sprint (full detail in
`docs/mesh/SPRINT5_INTEGRATION_VALIDATION.md` §2):

| Tool | Available? |
|---|---|
| Java (OpenJDK 21.0.10) | Yes |
| Gradle 8.14.3 (`/opt/gradle/bin/gradle`, on PATH) | Yes |
| Flutter | **No** |
| Dart | **No** |
| Android SDK | **No** |
| `adb` | **No** |
| Maven/Gradle dependency caches | Empty |
| Network to Maven Central/Google Maven/Gradle distribution | **Blocked by organization policy** (confirmed via the egress proxy's own allowlist, not just a transient failure) |
| `kotlinc` (as bundled jars) | Yes |
| JUnit 4.13.2 | Yes |
| BouncyCastle | Yes (OS package repo) |
| `org.json` | **No** |

Nothing was assumed — every row above was checked with a real command
this sprint, not carried forward from Sprint 4's memory.

## 5. org.json Resolution

Investigated in the required order (dependency tree, Gradle caches,
Android SDK jars, OS package repos, local Maven repos, Gradle dependency
cache, network) — all seven came back negative. `org.json` is genuinely
unresolvable in this sandbox. Per the brief's explicit instruction, a
minimal, clearly-labeled, test-only local test strategy was built instead
of faking a result — see §6.

## 6. SignatureVerifier Compilation

**Real, byte-for-byte-identical copies** of `SignatureVerifier.kt` and
`PacketRelayEngine.kt` (verified via `diff` against the actual
`setu_app/android/app/src/main/kotlin/com/setu/mesh/` files before
compiling, zero modifications) were compiled with a real `kotlinc`
against a new test-only `org.json.JSONObject`-compatible shim
(`tools/test-shim/org/json/JSONObject.kt`). Compiled cleanly, zero
errors. One real API-surface gap was found and fixed IN THE SHIM (not in
production code) during this process: real `org.json`'s single-argument
`optInt(String)` overload was initially missing, caught by the compiler
itself rejecting `SignatureVerifier.kt`'s real, unmodified call to it.

**Classification: COMPILED** (real production source, real compiler) —
**not** against the real `org.json` artifact, **not** the real
Android/Gradle build. This distinction is never collapsed anywhere in
this sprint's documentation.

## 7. Integrated Native Tests

The real `PacketRelayEngineTest.kt` was compiled and run alongside the
files in §6, plus JUnit 4.13.2 and BouncyCastle. **Result: 20/20 tests
passed, real captured JUnit output** (per-test names and outcomes
captured via a JUnit `RunListener`). This includes 8 new tests added this
sprint specifically to close Sprint 4's biggest test-coverage gap: every
prior fixture used a fixed, invalid signature, so only REJECT paths were
ever exercised. The new tests generate a real, valid Ed25519 signature
with BouncyCastle inside the test itself and prove: valid signature
accepted and relayed; valid packet enters the dedup cache exactly once;
a duplicate of it is suppressed; and six independent post-signing tamper
variants (message, latitude, longitude, timestamp, sender_id, signature
itself) are each independently rejected.

**Classification: INTEGRATION TESTED**, for everything these 20 tests
cover, with the same "against a test-only shim, not real org.json"
caveat as §6.

## 8. Cross-Language Validation

**No claim of cross-language validation is made.** Dart SDK confirmed
still unavailable (checked again this sprint). Per the brief's explicit
instruction, a fully executable handoff package was prepared instead:
`tools/cross_lang/dart_sign_fixture.dart` (ready to run on a real Flutter
machine, signs a fixed deterministic payload using the same
`package:cryptography` `Ed25519()` primitive `SigningService.sign()`
delegates to) and `tools/cross_lang/VerifyDartSignature.java`
(BouncyCastle verifier for that script's output). The Java verifier was
compiled and smoke-tested this sprint against a known-good Java-generated
vector — real result: `dart_ok=true` for a valid case, `dart_ok=false`
for a tampered one — confirming the tool itself is correct and ready,
while explicitly not claiming the cross-language proof it is built to
eventually produce. Full detail in
`docs/mesh/CROSS_LANGUAGE_SIGNATURE_VALIDATION.md`.

**Classification: BLOCKED (environment), NOT TESTED (interop claim).**

## 9. Android Build Status

Real, honest attempt made:
```
$ cd setu_app/android
$ /opt/gradle/bin/gradle testDebugUnitTest --no-daemon
...
FAILURE: Build failed with an exception.
* Where: Settings file '.../settings.gradle.kts' line: 20
* What went wrong:
Error resolving plugin [id: 'dev.flutter.flutter-plugin-loader', version: '1.0.0']
> Included build '/home/vaibhav/snap/flutter/common/flutter/packages/flutter_tools/gradle' does not exist.
```
`./gradlew assembleDebug` fails identically (same root cause). **Root
cause classification: A — environment blocker** (Flutter SDK genuinely
absent from this sandbox — not merely a wrong path in
`local.properties`). Per the brief's explicit instruction,
`local.properties` was **not** modified, since there is no correct local
Flutter path to substitute in an environment that contains no Flutter SDK
at all — even a corrected path would fail identically, because
`settings.gradle.kts` requires real content at
`$flutterSdkPath/packages/flutter_tools/gradle`, not just a valid-looking
string.

## 10. Flutter/Dart Status

`flutter`/`dart` not on `PATH`; no SDK directory anywhere on the
filesystem. Unchanged from every prior sprint of this engagement.

## 11. Security Gate Validation

Re-read directly from the real, just-compiled source and cross-checked
against §7's passing tests: the exact required flow — parse → packet_id
check → **signature verify** → dedup admission → TTL processing → relay
decision — holds, with signature verification happening unconditionally
before dedup or TTL are ever reached. The `process_invalidSignature_isNotAdmittedToDedupCache`
test specifically would fail if this ordering were ever violated; it
passed. **The invariant "untrusted packets never enter the relay
pipeline" is INTEGRATION TESTED, not merely source-reviewed.**

## 12. START_STICKY + Dedup Validation

No code change needed. Re-confirmed (source review, building on Sprint
4's `SPRINT4_EDGE_CASE_REVIEW.md`) that because signature verification
happens before a packet ever reaches `seen`, a rejected packet can never
be persisted by `MeshStateStore` either — by construction, not by a
separate defensive check. **Classification: SOURCE REVIEW.**

## 13. TTL Validation

`nextTtl()`'s hostile-oversized-TTL clamping behavior is unchanged and
**VERIFIED** (13/13 in Sprint 4's standalone harness, re-confirmed as
part of this sprint's 20/20 integrated run). Confirmed by source that a
forged packet with `ttl=9999` and an invalid signature is rejected at the
signature gate before TTL is ever read — structurally redundant to test
as a separate combined case, since verification always precedes TTL
access regardless of the TTL value claimed.

## 14. Reconnection Validation

No redesign, no code change. Re-confirmed against Sprint 4's edge-case
review: first-attempt-not-delayed, per-endpoint backoff isolation,
`stopAll()` clears state correctly, post-connect flapping explicitly
remains outside the current backoff model (a restated, deliberate scope
boundary, not a new gap). **Classification: SOURCE REVIEW, unchanged.**

## 15. Radio Resume Validation

No code change. Re-confirmed: receiver registered exactly once per
service lifecycle, cleanup correct, no permission changes, no
architecture changes. **Classification: SOURCE REVIEW, unchanged.**

## 16. CI Validation

`.github/workflows/setu-ci.yml` reviewed. One real, project-derived fact
found and noted inline (`setu_app/pubspec.yaml`'s `sdk: ^3.12.2`
constraint) — not sufficient to safely pin an exact Flutter version
without network access to confirm the Flutter↔Dart mapping, so that TODO
and the Android SDK setup TODO both deliberately remain, per the
instruction not to invent a version. **Never executed anywhere.
Classification: DESIGNED / NOT EXECUTED — explicitly not labeled GREEN.**

## 17. Device Validation Status

Zero physical devices used, unchanged across all five sprints.
`docs/mesh/DEVICE_VALIDATION_RUNBOOK.md` (new this sprint) adds a
15-scenario Device A/B/C/D procedure covering the Sprint 4/5-specific
cases (signature rejection, TTL exhaustion, forced-restart interaction
with the security gate) with required evidence specified per row — a
plan, explicitly stated as such, not a result.

## 18. Remaining Risks

1. **The real `org.json` artifact and the real Android/Gradle build
   remain untested against.** This sprint's compile/test evidence is
   real but is against a substitute dependency and a JVM-only toolchain —
   see `docs/mesh/FINAL_VALIDATION_MATRIX.md` row 13 for the precise
   statement of what is and isn't proven.
2. **Cross-language Dart↔Kotlin interop remains completely unproven** —
   a ready-to-run package exists (§8) but has never been executed.
3. **Zero device testing across the entire five-sprint engagement.**
4. **Connection authentication remains auto-accept**, a known, unchanged,
   team-decision-pending item.
5. **The test-only `org.json` shim's stated, documented limitations**
   (see its own doc comment) mean a small residual risk that the real
   `org.json` artifact could behave differently in some edge case this
   shim wasn't built to replicate — low-probability given the tiny, stable
   API surface used, but not zero.

## 19. Exact Changed Files

- `tools/test-shim/org/json/JSONObject.kt` (new)
- `setu_app/android/app/src/test/kotlin/com/setu/mesh/PacketRelayEngineTest.kt` (extended, 8 new tests, real file not a copy)
- `tools/cross_lang/dart_sign_fixture.dart` (new)
- `tools/cross_lang/VerifyDartSignature.java` (new)
- `docs/mesh/CROSS_LANGUAGE_SIGNATURE_VALIDATION.md` (new)
- `setu_app/android/app/src/main/kotlin/com/setu/mesh/MeshForegroundService.kt` (signature-rejection logging)
- `.github/workflows/setu-ci.yml` (TODO review, one resolved with real evidence)
- `docs/mesh/DEVICE_VALIDATION_RUNBOOK.md` (new)
- `docs/mesh/SPRINT5_INTEGRATION_VALIDATION.md` (new)
- `docs/mesh/FINAL_VALIDATION_MATRIX.md` (rewritten with new classification vocabulary and re-graded rows)
- `.gitignore` (added `*.class`, after a stray build artifact was accidentally committed and then removed)
- `setu_app/android/local.properties` — **explicitly NOT modified** (no correct local path exists to set)

## 20. Commit Hashes (branch `feature/vib-integration-validation`)

| Hash | Message |
|---|---|
| `64788d4` | test: unblock native security test infrastructure |
| `214e2f6` | test: compile and validate integrated signature verification |
| `68af0c3` | test: add cross-language Ed25519 interoperability fixture |
| `b98dec9` | chore: remove accidentally committed .class build artifact |
| `fa2f1b5` | security: log signature rejection without exposing sensitive data |
| `6cc5018` | ci: finalize SETU validation workflow |
| `495e05a` | docs: add device validation runbook |
| `243ee34` | docs: finalize Sprint 5 validation matrix |

## 21. Final Validation Matrix

See `docs/mesh/FINAL_VALIDATION_MATRIX.md` (16 rows, strict
IMPLEMENTED/VERIFIED/PARTIALLY VERIFIED/DESIGNED/BLOCKED/NOT TESTED
classification, every VERIFIED/PARTIALLY VERIFIED row backed by a named
command and real result). Headline changes this sprint: native dedup,
relay decision, and TTL move to VERIFIED; native signature verification
moves to PARTIALLY VERIFIED (real compile + real 20/20 test pass, real
toolchain gap stated); a new row separates the still-BLOCKED
cross-language claim from the JVM-only integration claim.

## 22. Definition of Done

| # | Item | Status |
|---|---|---|
| 1 | `feature/vib-integration-validation` created | DONE |
| 2 | Environment fully inventoried | DONE — real commands, §4 |
| 3 | org.json blocker investigated honestly | DONE — 7/7 channels checked, all negative, §5 |
| 4 | SignatureVerifier.kt actually compiled OR exact blocker proven | DONE — actually compiled, §6 |
| 5 | PacketRelayEngine integrated tests executed OR exact blocker proven | DONE — actually executed, 20/20, §7 |
| 6 | Signature rejection before dedup proven where executable | DONE — integration tested, §11 |
| 7 | Invalid packets cannot enter relay pipeline | DONE — proven by test + source, §11 |
| 8 | Valid packets still pass verification | DONE — new accept-path tests, §7 |
| 9 | Ed25519 negative cases executed | DONE — 6 new tamper cases + Sprint 4's 10, all real |
| 10 | Dart→Kotlin vector executed OR Dart SDK blocker explicitly proven | PARTIAL — blocker proven, handoff package prepared and Kotlin-side smoke-tested, not Dart-executed, §8 |
| 11 | Android build attempted honestly | DONE — real command, real error, §9 |
| 12 | Flutter build/test attempted if SDK exists | N/A — SDK does not exist, honestly stated |
| 13 | CI workflow reviewed | DONE — §16 |
| 14 | START_STICKY interaction reviewed | DONE — §12 |
| 15 | TTL + signature ordering validated | DONE — §11/§13 |
| 16 | Reconnect/radio regressions reviewed | DONE — §14/§15 |
| 17 | Device runbook created | DONE — §17 |
| 18 | Final validation matrix updated | DONE — §21 |
| 19 | No architecture feature creep | DONE — no packet/routing/ACK/UI/AI/backend changes |
| 20 | Final report generated with evidence-backed classifications | DONE — this document |

## 23. Recommended Next Sprint

1. **Resolve `org.json` for real** (network access, or a developer
   vendoring the real jar) and re-run `PacketRelayEngineTest.kt` against
   it — very likely a near-zero-code-change upgrade from PARTIALLY
   VERIFIED to fully VERIFIED, since the logic itself is now proven
   correct.
2. **Get a real Flutter/Android SDK onto a build machine or CI runner**
   and run `./gradlew assembleDebug` for the first time in this
   engagement's life.
3. **Run `tools/cross_lang/dart_sign_fixture.dart`** on that same real
   Flutter environment and feed its output into
   `tools/cross_lang/VerifyDartSignature.java` — the single most
   valuable remaining unknown in this engagement.
4. **Get physical devices** and start working through
   `docs/mesh/DEVICE_VALIDATION_RUNBOOK.md`.
5. **Bring the connection-authentication decision to the team** —
   unchanged, still open, since Sprint 3.
