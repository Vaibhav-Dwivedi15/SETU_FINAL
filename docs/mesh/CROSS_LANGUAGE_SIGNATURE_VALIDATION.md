# Cross-Language (Dart → Kotlin) Ed25519 Signature Validation

Owner: Vib (Mesh/Architecture). Written Sep 21 2026, Bulk Sprint 5, Phase 4.

## Status: BLOCKED (Dart SDK unavailable) — honest handoff package prepared, not a validation result

**This document does NOT claim cross-language validation.** No Dart SDK
exists anywhere in the sandbox this sprint's work was produced in —
re-confirmed this sprint (`dart`/`flutter` not on `PATH`, no Flutter/Dart
SDK directory found anywhere on the filesystem, same finding as Sprints
2-4). Per this sprint's explicit instruction: **stop honestly, do not
claim cross-language validation, prepare a fully executable handoff
package instead.** That is what this document and the two files in
`tools/cross_lang/` are.

## What's in the package

1. **`tools/cross_lang/dart_sign_fixture.dart`** — a ready-to-run Dart
   script. Uses the same `package:cryptography` `Ed25519()` algorithm
   object `SigningService.sign()` delegates to internally (not
   `SigningService` itself, which needs `FlutterSecureStorage` and a real
   Flutter engine — see the script's own header for why that distinction
   matters and why it doesn't weaken the result). Signs a FIXED,
   deterministic payload built to exactly match
   `EmergencyPacket.signaturePayload`'s real field order, using a fixed
   32-byte seed (bytes `0x00..0x1f` — a test fixture, not a production
   key). Prints the derived public key, the exact payload string, and the
   signature, all in hex/plain text — plus a Dart-side self-check
   (`dart_self_verify`) so a run confirms its own consistency before
   anyone even looks at the Kotlin side.

2. **`tools/cross_lang/VerifyDartSignature.java`** — a ready-to-run Java
   program. Takes the payload string, public key hex, and signature hex
   (copied verbatim from the Dart script's output) and verifies them with
   the exact same BouncyCastle `Ed25519PublicKeyParameters`/`Ed25519Signer`
   calls `SignatureVerifier.kt` uses.

## What HAS been done this sprint (real, executed, but not the cross-language proof itself)

The Java-side verifier program was compiled and smoke-tested — not
against real Dart output (none exists), but against the already-known-good
Java/BouncyCastle vector from
`docs/security/NATIVE_SIGNATURE_TEST_VECTOR.md` (Sprint 4), to prove the
verifier plumbing itself is correct before handing it off:

```
$ javac -cp bcprov-1.77.jar VerifyDartSignature.java
(no errors)

$ java -cp .:bcprov-1.77.jar VerifyDartSignature \
    "03a107bf-1767225600000000|03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8|emergency|2026-01-01T00:00:00.000Z|000102030405060708090a0b0c0d0e0f|03a107bf-1767225600000000|12.9716|77.5946|Test SOS message|critical" \
    "03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8" \
    "5edf2142db7afbf449fe0c4e46047ab90bb69f8cfbc5160cfe1b855e2819598815f67e466fc444acb97b3eb3f56f55f58ebabe92e50c33ae389743e234d61203"

dart_ok=true  <-- if true, this is real Dart-signed -> Kotlin-verified proof

$ java -cp .:bcprov-1.77.jar VerifyDartSignature \
    "<same payload>" "<same sender>" "<signature with one flipped hex char>"

dart_ok=false
```

Both cases behaved correctly (valid signature verifies true, a one-char
tamper verifies false) — real, captured evidence that the *verifier
script* is correct. This is explicitly **not** the cross-language proof
itself, since no Dart-produced value was involved — it is proof the tool
is ready and correct for whoever runs the Dart half next.

## What still needs a real Flutter/Dart environment

```bash
# Step 1 (needs Flutter/Dart installed):
cd setu_app
dart run ../tools/cross_lang/dart_sign_fixture.dart
# copy its printed sender_id(public_key_hex), payload_string, and signature_hex

# Step 2 (needs Java + the bcprov jar, e.g. from setu_app's own resolved
# BouncyCastle dependency, or the same bcprov-1.77.jar used throughout
# this engagement):
cd ../tools/cross_lang
javac -cp bcprov-1.77.jar VerifyDartSignature.java
java -cp .:bcprov-1.77.jar VerifyDartSignature \
    "<payload_string from step 1>" \
    "<sender_id(public_key_hex) from step 1>" \
    "<signature_hex from step 1>"
```

If `dart_ok=true`, that is the real, first-ever, executed proof in this
engagement's life that a signature Dart's actual cryptography stack
produces verifies correctly against the native Kotlin verification logic.
If `dart_ok=false`, that is real evidence of an actual interop bug — see
`VerifyDartSignature.java`'s own header for the most likely candidates to
check first (this fixture deliberately keeps latitude/longitude as fixed
literal strings identical on both sides, specifically to rule out the
`double.toString()` formatting risk from being the culprit in this first
run — a failure here would point somewhere else: UTF-8 encoding
differences, seed-to-keypair derivation differences between
`package:cryptography` and BouncyCastle, or byte ordering).

## Negative interoperability cases (also ready to run, not yet run)

Once step 1 above succeeds, the same `dart_sign_fixture.dart` payload
fields can be individually tampered (message, timestamp, latitude,
longitude, sender_id, signature) exactly as
`PacketRelayEngineTest.kt`'s Sprint 5 additions already do for the
JVM-only case (see `docs/mesh/SPRINT5_INTEGRATION_VALIDATION.md` §7) —
each tampered variant fed through `VerifyDartSignature.java` should print
`dart_ok=false`. This document does not fabricate those results either;
they require the same real Dart run as step 1.

## Bottom line

**Classification: BLOCKED (environment), NOT TESTED (interop claim).**
The package is genuinely executable by anyone with a working Flutter/Dart
install — it is not a stub or a placeholder. Nothing about SETU's
cross-language signature interoperability is claimed as proven by this
sprint.
