# SETU — Sprint 5 Integration Validation

Owner: Vib (Mesh/Architecture). Written Sep 21 2026, Bulk Sprint 5.
Branch: `feature/vib-integration-validation` (from `feature/vib-security-closure`).

This document is the technical record for Phases 0-1, 5-9, and 12-13 of
the Sprint 5 brief. Phase 2/3's own compile+test evidence is summarized
here (§6/§7) with the full mechanics; Phase 4 (cross-language) has its own
document, `docs/mesh/CROSS_LANGUAGE_SIGNATURE_VALIDATION.md`, because it
is a distinct, still-BLOCKED claim that must not be conflated with the
JVM-only evidence here.

**Throughout this document: SOURCE REVIEW, COMPILED, UNIT TESTED,
INTEGRATION TESTED, and DEVICE TESTED are five different claims and are
never collapsed into each other.**

## §1. Baseline (Phase 0)

- Starting commit: `a0f1451` (`docs: native security closure sprint final report`, tip of `feature/vib-security-closure`).
- Working tree: clean at start.
- Branch created: `feature/vib-integration-validation`.

## §2. Environment Inventory (Phase 0, real commands run this sprint)

| Tool | Available? | Evidence |
|---|---|---|
| Java | Yes — OpenJDK 21.0.10 | `java -version` |
| Gradle | Yes — 8.14.3, both `/opt/gradle/bin/gradle` (on PATH) and the identical install at `/opt/gradle-8.14.3` | `gradle -version` |
| Flutter | **No** | `flutter --version` → command not found; no Flutter SDK directory found anywhere on the filesystem |
| Dart | **No** | `dart --version` → command not found; same filesystem search |
| Android SDK | **No** | No `platforms/android-*`, `build-tools/`, or `android.jar` found anywhere |
| `adb` | **No** | Command not found |
| `ANDROID_HOME`/`ANDROID_SDK_ROOT` | Unset | — |
| Maven/Gradle dependency caches | Empty | `~/.gradle/caches/modules-2` contains only a lock file, zero resolved modules; `~/.m2` has zero files |
| Network to Maven Central / Google Maven / Gradle distribution servers | **Blocked by organization policy** | Direct `curl` returns `CONNECT tunnel failed, response 403` for all three; the egress proxy's own status endpoint confirms its allowlist covers only `registry.npmjs.org`, `jsr.io`, `pypi.org`, `files.pythonhosted.org`, `index.crates.io`, `proxy.golang.org`, and Anthropic-internal hosts — no Maven-related host is present, so this is a durable policy, not a transient failure |
| `kotlinc` (as jars, invocable via `java -cp`) | Yes — bundled inside the Gradle 8.14.3 install (`kotlin-compiler-embeddable-2.0.21.jar` + transitive jars, all in the same `lib/` directory) | Actually invoked this sprint and Sprint 4 |
| JUnit 4.13.2 | Yes — same Gradle install | Actually invoked this sprint and Sprint 4 |
| BouncyCastle (`bcprov-1.77.jar`) | Yes — via the OS's Debian package repository | Found Sprint 4, used again this sprint |
| `org.json` (standalone Maven artifact) | **No** — confirmed again this sprint by the same exhaustive search (Gradle caches, `~/.m2`, OS package repo, `find / -iname "*json*.jar"`) | See §5 |

## §3. Project Configuration Inspected (Phase 5)

`setu_app/android/local.properties` (unchanged, NOT modified this sprint
— see below for why):
```
sdk.dir=/home/vaibhav/Android/Sdk
flutter.sdk=/home/vaibhav/snap/flutter/common/flutter
flutter.buildMode=debug
flutter.versionName=1.0.0
flutter.versionCode=1
```
Both paths point at the original developer's machine and do not exist in
this sandbox. Per the brief's explicit instruction ("only modify it if
the environment actually contains Flutter"): **this sandbox does not
contain Flutter at all**, so there is no correct local path to substitute
— editing this file would not have unblocked anything and was correctly
left untouched.

`setu_app/android/settings.gradle.kts` requires `flutter.sdk` to resolve
to a real path containing `packages/flutter_tools/gradle` (via
`includeBuild(...)`). This is a sharper, newly-confirmed finding this
sprint: **even a hypothetically-correct `local.properties` path could not
fix this build**, because there is no Flutter SDK content anywhere in
this sandbox for any path to point to. The blocker is Flutter's total
absence, not merely a wrong string in a config file.

## §4. `org.json` Resolution (Phase 1)

Investigated in the requested order, all negative:
1. Existing Android dependency tree — never successfully resolved once,
   in any sprint (no successful Gradle sync has ever occurred).
2. Gradle caches (`~/.gradle/caches/modules-2`) — empty.
3. Android SDK bundled jars — no Android SDK present at all.
4. OS package repositories (`dpkg -l`, `apt list --installed`) — no
   `org.json`-providing package found.
5. Local Maven repositories (`~/.m2`) — empty.
6. Gradle dependency cache — same as #2.
7. Network availability — confirmed blocked (§2).

**Conclusion: org.json is genuinely unresolvable in this sandbox by any
channel.** Per the brief's explicit instruction ("DO NOT fake the test...
create a minimal local test strategy that does not alter production
code"), the approach taken is documented in full in §6 below — a
test-only, clearly-labeled JSON shim, never touching production code or
`build.gradle.kts`'s real dependency declaration.

## §5. `SignatureVerifier.kt` — Real Compilation (Phase 2)

The exact, **unmodified, byte-for-byte-identical** production files —
`SignatureVerifier.kt` and `PacketRelayEngine.kt`, copied directly from
`setu_app/android/app/src/main/kotlin/com/setu/mesh/` and verified
identical via `diff` before compiling — were compiled together with a
new test-only file, `tools/test-shim/org/json/JSONObject.kt`.

**What that shim is, precisely** (full reasoning and stated limitations
in the file's own extensive doc comment — read it before trusting
anything below): a hand-written, from-scratch reimplementation of the
small subset of `org.json.JSONObject`'s public API the production files
actually call (`JSONObject(String)`, `optString`, `optInt`/`optInt`
1-arg, `has`, `put`, `remove`, `toString`), built for SETU's actual wire
shape (flat, scalar-only JSON objects — no packet type nests one JSON
object inside another). It is NOT the real `org.json` library. One real
API-surface gap was found and fixed during this process: real
`org.json`'s `optInt(String)` single-argument overload (default 0) was
missing from the first draft of the shim — caught by the compiler
itself when `SignatureVerifier.kt`'s real, unmodified source (which calls
exactly that overload for `radius_meters`) failed to compile, fixed in
the shim, never in the production file.

**Result — real, captured command and output:**
```
$ java -cp $CP org.jetbrains.kotlin.cli.jvm.K2JVMCompilerKt -no-stdlib -no-reflect -cp $CP -d out $(find src -name "*.kt")
(no errors, no warnings)

$ find out -name "*.class"
out/com/setu/mesh/PacketRelayEngine$Companion.class
out/com/setu/mesh/PacketRelayEngine$RelayResult.class
out/com/setu/mesh/PacketRelayEngine.class
out/com/setu/mesh/SignatureVerifier.class
out/org/json/JSONObject$Parser.class
out/org/json/JSONObject.class
out/org/json/JSONShimParseException.class
```

**Classification: COMPILED** (real production Kotlin source, real
`kotlinc`, zero modifications to `SignatureVerifier.kt`/
`PacketRelayEngine.kt`) — against a test-only substitute dependency, not
the real `org.json` artifact and not the real Android/Gradle build. This
distinction is carried through consistently into
`docs/mesh/FINAL_VALIDATION_MATRIX.md`.

## §6. Integrated `PacketRelayEngineTest.kt` — Real Execution (Phase 3)

The real, unmodified `PacketRelayEngineTest.kt` (Sprint 4's file, later
extended in-place this sprint — see §7) was copied verbatim into the same
workspace and compiled alongside the files in §5, plus JUnit 4.13.2 and
BouncyCastle on the classpath. Compiled cleanly. Run with the real JUnit
runner:

```
$ java -cp out:kotlin-stdlib:junit-4.13.2:hamcrest-core:bcprov RunWithNames
JUnit version 4.13.2
....................
Time: 0.243

OK (20 tests)
```

All 20 individual test names and PASS results were captured (see the
full per-test listing in this sprint's commit message for the test
commit, or re-run `tools/cross_lang`-adjacent `RunWithNames.java` pattern
described inline in this file's own history). **Classification:
INTEGRATION TESTED** for everything these 20 tests cover — the real
`SignatureVerifier`/`PacketRelayEngine` source, exercised together,
through JUnit, with real captured pass/fail output.

## §7. Closing the Sprint 4 Coverage Gap: the ACCEPT Path

Sprint 4's test suite (12 tests) exercised only REJECT paths — every
fixture packet used a fixed, deliberately-invalid `signature` value,
because Sprint 4 had no way to produce a genuinely valid one from Kotlin.
This sprint's real compile unlocked that: `PacketRelayEngineTest.kt` was
extended (still the same real, single test file — not a copy) with a
`signedEmergencyPacket()` helper that generates a fresh Ed25519 keypair
and REALLY signs a payload with BouncyCastle's `Ed25519Signer` (the same
primitive `SignatureVerifier.verify()` itself uses to check it), adding 8
new tests:

- `process_validSignature_isAccepted_andRelayed`
- `process_validSignature_entersDedupCache_exactlyOnce_duplicateSuppressed`
- `process_validSignature_tamperedMessageAfterSigning_isRejected`
- `process_validSignature_tamperedLatitudeAfterSigning_isRejected`
- `process_validSignature_tamperedLongitudeAfterSigning_isRejected`
- `process_validSignature_tamperedTimestampAfterSigning_isRejected`
- `process_validSignature_tamperedSenderIdAfterSigning_isRejected`
- `process_validSignature_tamperedSignatureItself_isRejected`

All 8 passed (folded into the 20/20 total in §6). This closes the most
important gap in the brief's 16-scenario minimum list: items 1
(valid signature accepted), 13 (valid packet enters dedup exactly once),
and 14 (duplicate valid packet suppressed) are now genuinely, freshly
covered with real executed evidence, not just reasoned about.

**Note on brief items not separately, explicitly named as their own
test**: "malformed signature rejected" and "non-hex sender_id rejected"
are covered by the pre-existing `process_malformedPublicKey_...` and
`process_missingSignatureField_...` tests (both use malformed/absent
values in the same fixture shape); a dedicated "hostile ttl=9999 +
invalid signature" combination test was considered and deliberately not
added as a separate case, because `PacketRelayEngine.process()`'s actual
code structure (verified in §5 and re-confirmed by reading the compiled
source) makes this combination structurally redundant to test
separately: signature verification happens unconditionally BEFORE the
`ttl` value is read at all (see §8), so any invalid-signature test
already proves TTL is never reached, regardless of what TTL value the
packet claims.

## §8. Security Gate Integration (Phase 6) — Ordering, Confirmed By Compiled Source

Re-read directly from the real, just-compiled `PacketRelayEngine.kt`
source (line numbers as of this sprint):
```
totalProcessed++
val rawJson = String(bytes)
json = JSONObject(rawJson)          // structural parse
packetId = json.optString(...)      // packet_id presence check
if (packetId.isEmpty()) return REJECT
if (!SignatureVerifier.verifyPacket(rawJson, json)) {   // <-- SIGNATURE GATE
    signatureFailures++
    return REJECT (not relayed, not remembered)
}
if (seen.contains(packetId)) { ... dedup ... }          // <-- dedup, AFTER signature
...
val ttl = json.optInt("ttl", 0)                         // <-- TTL, AFTER dedup
```
This is exactly the required flow: **parse → packet_id check → signature
verify → dedup admission → TTL processing → relay decision**, with a
REJECT on invalid signature short-circuiting before dedup or TTL are ever
reached. This ordering is not just source-reviewed — it is the exact
ordering that produced the real §6/§7 test results (the dedup-cache-
poisoning test in particular, `process_invalidSignature_isNotAdmittedToDedupCache`,
would fail if this ordering were ever violated).

**The actual invariant — untrusted packets never enter the relay
pipeline — is INTEGRATION TESTED, not merely source-reviewed.**

## §9. START_STICKY + Security Interaction (Phase 7)

No code change was needed or made here this sprint — Sprint 4's
`SPRINT4_EDGE_CASE_REVIEW.md` already reviewed `MeshStateStore`/
`PacketRelayEngine`'s persistence boundary conditions and found no
defect. This sprint adds one additional, source-confirmed fact: because
signature verification happens BEFORE a packet is ever added to `seen`
(§8), a packet that fails verification is *never* persisted by
`MeshStateStore.saveSeenIds()` either — `snapshotSeen()` only ever
reflects `seen`, which invalid packets never enter. So the interaction
between START_STICKY persistence and the new security gate is, by
construction, the same "no defect found" conclusion as Sprint 4's
review, now with the added confirmation that a rejected packet cannot
leave any trace in the persisted dedup state to restore on a later
restart. This is SOURCE REVIEW (reasoned from the confirmed-real code
path in §8), not device-tested.

## §10. TTL + Signature Interaction (Phase 8)

Confirmed by source (§8): a forged packet with `ttl=9999` and an invalid
signature is rejected at the signature gate — `nextTtl()`/the `ttl`
field are never even read. `nextTtl()`'s own TTL-clamping behavior
(a valid packet claiming `ttl=9999` is clamped to `MAX_TTL` before
decrementing) is unchanged from Sprint 3/4 and remains
**UNIT TESTED** (`nextTtl_hostileOversizedTtl_isClampedFirst`, part of
the 20/20 in §6). `PacketRelayEngine.MAX_TTL` (native) vs.
`SecurityConstants.maxTTL` (Dart) cross-check logging is unchanged from
Sprint 3 — still diagnostic-only, non-enforcing, still in place in
`MeshForegroundService.updateMeshPolicy()`.

## §11. Reconnect + Radio Regression Check (Phase 9)

No redesign, no code change. Re-reviewed against Sprint 4's
`SPRINT4_EDGE_CASE_REVIEW.md` §2 findings — first-attempt-not-delayed,
per-endpoint backoff isolation, `stopAll()` clearing both maps, receiver
registered exactly once per service lifecycle, and the explicit,
restated scope boundary that post-connect "flapping" (connects then
quickly disconnects) remains outside the current backoff model — all
still hold; nothing in this sprint's other changes touches
`NearbyConnectionsManager.kt` or the radio-resume receiver at all.
**Classification: SOURCE REVIEW, unchanged from Sprint 4, re-confirmed.**

## §12. Observability (Phase 12) — one real fix made

Reviewed `signatureFailures`/`relayStats()`/`getRelayStats` (all
unchanged in shape from Sprint 4). Found a real gap: `PacketRelayEngine`
deliberately has **no** `android.util.Log` import (this independence
from the Android SDK is exactly what made §5's real standalone compile
possible, and is preserved on purpose), so a signature rejection was
previously observable ONLY by polling the `signatureFailures` counter —
there was no logcat line marking the moment it happened. Fixed in
`MeshForegroundService.onPayloadReceived()` (which already owns
`Log`/`TAG`): a before/after delta check on `signatureFailures` around
the `process()` call, logging exactly:
```
Log.w(TAG, "signature verification failed packet_id=${result.packetId ?: "unknown"} reason=INVALID_SIGNATURE")
```
No raw signature, no public key, no packet message/location content —
only `packet_id` and a fixed reason string, matching the brief's own
allowed-example format exactly. This is a small, additive, non-
architectural fix (adds one delta check and one log line in the service,
zero changes to `PacketRelayEngine`'s own Android-independence).

## §13. Security Review (Phase 13)

Focused re-read of `SignatureVerifier.kt`, `PacketRelayEngine.kt`,
`MeshForegroundService.kt`, `build.gradle.kts`, the tests, and the CI
workflow, specifically hunting for the failure modes the brief lists:

| Checked for | Found? |
|---|---|
| Fail-open behavior (any path where a verification failure results in ACCEPT) | **No** — every exception in `SignatureVerifier.verify()` is caught and returns `false`; `buildSignaturePayload()` returns `null` on any missing/unparseable field, and `verifyPacket()` treats `null` payload as `?: return false`; `PacketRelayEngine.process()` checks `if (!SignatureVerifier.verifyPacket(...))` — correct reject-on-false polarity, confirmed by the passing `process_invalidSignature_isRejected_notRelayed` test |
| Exception swallowing that results in acceptance | **No** — every catch block explicitly returns `false`/`null` (reject), never a default-accept value |
| Verification after dedup / after relay | **No** — confirmed ordering in §8, backed by an integration test that would fail if this were violated |
| Malformed JSON / malformed key / malformed signature crashes | **No** — all three have passing tests (`process_malformedJson_isRejected_doesNotCrash`, `process_malformedPublicKey_isRejected_doesNotCrash`, and the tampered-signature tests), none throw |
| Accidental trust of `sender_id` or `packet_id` before verification | **No** — `packet_id` is read only for the emptiness/dedup-key check (never trusted as an authorization signal), and `sender_id` is never used for anything except as the public key input to `verify()` itself |
| Signature bypass for specific packet types | **No** — `buildSignaturePayload()`'s `when(type)` has an explicit `else -> null` for any unrecognized type, which is treated identically to a verification failure |
| Debug-only verification | **No** — the gate in `PacketRelayEngine.process()` is unconditional, no build-flavor/debug check surrounds it |
| Dart-only verification assumptions | **No** — this is precisely the gap Sprint 4/5 closed: verification is now native, runs regardless of whether Dart is attached |
| Logging of sensitive material | **No** (after §12's fix) — the new log line emits only `packet_id` and a fixed reason string |

**No fail-open finding anywhere.** The invariant — FAIL CLOSED, reject
whenever verification cannot be performed — holds throughout, both by
source review and by the integration tests in §6/§7 that would fail if
it didn't.

## §14. No Connection Authentication Implementation (Phase 14)

Confirmed: no implementation added this sprint. `auto-accept` remains
unchanged in `NearbyConnectionsManager.kt`. No allowlist was introduced.
`docs/security/NATIVE_CONNECTION_AUTH_DESIGN.md` (Sprint 3) remains the
current, unimplemented decision record.
