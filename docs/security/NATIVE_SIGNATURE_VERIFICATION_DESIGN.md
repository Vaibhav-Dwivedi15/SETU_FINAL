# SETU Native Mesh — Signature Verification Design

Owner: Vib (Mesh/Architecture). Written Sep 21 2026, Bulk Sprint 3.
Status: **DESIGNED, NOT IMPLEMENTED** — see §11 for why, and the final
report's Blockers section for the honest account of what stopped this.

## 1. Current Dart Signature Flow

```
Origin device:
  packet = EmergencyPacketBuilder.build(...)          // unsigned
  signature = SigningService.sign(packet.signaturePayload)
  signedPacket = packet.copyWith(signature: signature)

Receiving device (mesh_service.dart:246-309), in this exact order:
  1. PacketFactory.fromJson()            — malformed JSON dropped here
  2. PacketValidator.validate()          — in this sub-order:
       a. packet version check
       b. TTL bounds check (ttl < 1 || ttl > 5 -> drop)
       c. ReplayProtectionService.validate():
            - timestamp validated first (clock skew, max age)
            - then nonce (duplicate-nonce cache, 500 entries / 10 min)
     Any failure here -> dropped, logged, never reaches signature check.
  3. SigningService.verify(packet.signaturePayload, packet.senderId, packet.signature)
       -- senderId IS the Ed25519 public key (see §3). Never throws;
          returns false on any malformed input.
  4. Only for TerminationPacket: ResponderRegistry.checkResponder(senderId)
```

Signature verification is deliberately the **most expensive** check and
is placed **after** the cheap structural/replay checks, not before —
confirmed by mesh_service.dart's own comment and its separate
`MeshMetrics.instance.signatureVerify` timing wrapper around just that
step.

## 2. Current Packet Fields (signature-relevant)

Every `MeshPacket` subclass (`EmergencyPacket`, `AckPacket`,
`AlertPacket`, `TerminationPacket`) carries, at minimum: `packetId`,
`senderId`, `type`, `timestamp` (UTC `DateTime`), `nonce`, `signature`,
plus type-specific fields. `ttl` and `hop_count` exist on the wire but
are **excluded from every signaturePayload by design** — this is what
lets a relay hop decrement TTL / increment hop_count without invalidating
the originator's signature. This design does not touch that.

## 3. Current sender_id

`sender_id` is **not an independent identifier** — it is the device's
32-byte Ed25519 public key, hex-encoded (64 lowercase hex chars, no
`0x` prefix), returned by `IdentityService.getOrCreateSenderId()` →
`SigningService.getOrCreatePublicKeyHex()`. This is self-certifying: any
device can verify any packet's signature using only the fields already
present in that packet, with zero separate key-exchange or key-lookup
infrastructure. A native Kotlin verifier needs no new key-distribution
mechanism — it reads the same `sender_id` field already in the JSON.

## 4. Current Signature Encoding

- JSON field: `"signature"` (string).
- Encoding: hex, same helpers as the public key (`_bytesToHex`).
- Length: standard Ed25519 signature = 64 bytes = 128 hex chars.

## 5. Exact Bytes Being Signed

**Not JSON.** A manually pipe (`|`)-delimited string, UTF-8 encoded at
sign/verify time. Common pattern:
```
packetId|senderId|type.name|timestamp.toIso8601String()|nonce|<type-specific fields, declaration order>
```

Per type (verbatim from `lib/mesh/models/*.dart`):

```dart
// EmergencyPacket
'$packetId|$senderId|${type.name}|${timestamp.toIso8601String()}|'
'$nonce|$emergencyId|$latitude|$longitude|$message|${priority.name}'

// AckPacket
'$packetId|$senderId|${type.name}|${timestamp.toIso8601String()}|'
'$nonce|$originalPacketId|$emergencyId'

// AlertPacket
'$packetId|$senderId|${type.name}|${timestamp.toIso8601String()}|'
'$nonce|$incidentType|$latitude|$longitude|$radiusMeters'

// TerminationPacket
'$packetId|$senderId|${type.name}|${timestamp.toIso8601String()}|'
'$nonce|$emergencyId|$responderId'
```

RecoveryPacketBuilder does not introduce a separate scheme — it signs the
`EmergencyPacket` it wraps via the same `signaturePayload` getter.

**This exact string construction — field order, `|` separator, UTF-8
encoding — must not change.** A native verifier reconstructs this same
string from the fields it parses out of the received JSON and hands it
to its own Ed25519 verify call.

### The one real interop risk: `double.toString()`

`latitude`/`longitude` (and `AlertPacket.radiusMeters`, which is an
`int`, so safe) are interpolated via Dart's default `double.toString()`
— its shortest-round-trippable-decimal algorithm does not guarantee
byte-identical output to Kotlin/Java's `Double.toString()` for the same
numeric value. If a native verifier ever had to **re-derive**
`signaturePayload` from a `Double` it parsed out of JSON and reformatted
itself, a mismatched decimal string would make a legitimate signature
fail to verify.

**This is avoidable, and the avoidance is mandatory, not optional**: a
native verifier must build the payload string using the **exact
substrings it received in the incoming JSON** for `latitude`/`longitude`
(i.e. read them as the raw JSON number's original text representation,
or — more robustly — read `latitude`/`longitude` as `String` via
`json.get("latitude").toString()` only if that is confirmed to preserve
`org.json`'s own formatting identically to what was received; the safer
approach is for `PacketRelayEngine`'s existing `JSONObject` parse to
expose the original field text directly via `json.opt("latitude")` and
format defensively). This needs a concrete implementation-time decision
(see §10) and, critically, **a fixed test vector** (see §9) to prove it
before ever trusting a "verified" result in production.

## 6. Kotlin-Compatible Ed25519 Implementation Options

Dart's `cryptography: 2.9.0` package uses a pure-Dart implementation of
standard RFC 8032 Ed25519 (32-byte seed → 32-byte public key, 64-byte
signature) — the same standard essentially every mainstream Ed25519
library implements, so cross-language interop is expected *if* byte
encodings match (see §5's caveat, which is about payload construction,
not the signature algorithm itself).

Options surveyed for Kotlin/Android:

| Option | Availability | Notes |
|---|---|---|
| **BouncyCastle** (`org.bouncycastle:bcprov-jdk18on`) | Not currently a project dependency. Would need to be added via Maven Central. | Most common choice for Android Ed25519 below API 26; pure-Java, works on any minSdk. `Ed25519PrivateKeyParameters`/`Ed25519PublicKeyParameters`/`Ed25519Signer` API is well-documented and directly matches raw 32/64-byte key and signature layout. |
| **Google Tink** (`com.google.crypto.tink:tink-android`) | Not currently a project dependency. Would need Maven Central. | Higher-level, opinionated API (keysets, not raw bytes) — would need extra work to interoperate with Dart's raw-hex key/signature format, since Tink prefers its own keyset serialization. More setup than needed for this narrow use case. |
| **Platform `java.security`** (`NamedParameterSpec("Ed25519")`, `EdECPrivateKeySpec`/`EdECPublicKeySpec`, API added in Android 12 / API 31 for full EdDSA support, partial support claims vary by OEM) | Already present (JDK-bundled, no new dependency) — **but only on API 31+, well above what this project's `minSdk` (`flutter.minSdkVersion`, not overridden in this build.gradle.kts, so whatever Flutter's own default is for the installed Flutter SDK version — not independently confirmable from source in this sandbox) can be assumed to guarantee.** | Zero new dependency, but cannot be relied on as the *only* path without confirming `minSdk >= 31` for every device SETU targets, which this audit cannot confirm without the actual Flutter SDK installed. Given this is a disaster-response app meant to run on whatever phone a bystander already owns, assuming a recent-API-only device is a real availability regression, not a safe default. |

**Recommendation (design only)**: BouncyCastle is the correct choice —
minSdk-independent, raw-byte-oriented API that maps directly onto what
Dart already produces (32-byte pubkey, 64-byte signature, both already
hex-encoded in the wire format). Tink's opinionated keyset model is more
friction than benefit here. The platform API is minSdk-gated in a way
that can't be safely assumed for a bystander's arbitrary phone.

## 7. Required Dependencies

`org.bouncycastle:bcprov-jdk18on` (a current stable version at design
time — exact pinned version to be chosen when this is actually
implemented, not guessed here) added to
`setu_app/android/app/build.gradle.kts`'s `dependencies {}` block, next
to the existing `play-services-nearby` line. No other native dependency
changes needed. **This is a new dependency — see §11, this is exactly
the kind of addition the sprint brief says not to make casually, and it
was not made this pass.**

## 8. Key Parsing Requirements

- Public key: `sender_id` field, 64 hex chars → decode to 32 raw bytes →
  `Ed25519PublicKeyParameters(rawBytes, 0)`.
- Signature: `signature` field, 128 hex chars → decode to 64 raw bytes →
  fed directly to `Ed25519Signer.verifySignature()`.
- No key format negotiation needed (no PEM, no ASN.1/DER wrapping to
  parse) — both are raw fixed-length byte arrays, matching exactly what
  Dart already produces via its own `_bytesToHex`/`_hexToBytes` helpers.
- **Malformed input handling is mandatory, not optional**: a hex string
  of the wrong length, non-hex characters, or an all-zero/invalid curve
  point must all result in "verification failed," never a thrown
  exception that could crash `PacketRelayEngine.process()` (which today
  has no signature-check code path at all, so this is new surface area
  needing the same defensive posture as the existing JSON-parse try/catch
  at the top of `process()`).

## 9. Verification Performance Implications

Not measured — no device available (see final report §12). Expected
qualitatively: Ed25519 verification is fast (microseconds on modern
mobile CPUs, this is one of Ed25519's designed properties versus e.g.
RSA), and BouncyCastle's pure-Java implementation, while slower than a
native/JNI implementation, should still be well within the latency
budget of a relay decision that already does JSON parsing and haversine
distance math per packet. This needs to be **measured**, not assumed,
once real hardware is available — added as an explicit item to
`MULTI_DEVICE_TEST_PLAN.md`'s future scope, not invented here.

**Before any implementation**, a fixed test vector must be produced:
run Dart's `SigningService` once with a hardcoded seed, capture
`(publicKeyHex, payloadString, signatureHex)`, and hardcode that exact
tuple into a Kotlin unit test asserting the BouncyCastle-based verifier
accepts it and rejects a single-byte-flipped variant. This is the single
most important validation step before trusting any native verification
result — the existing Dart test suite has no such pinned vector (round-
trip tests only, freshly generated keys each run), so one does not yet
exist anywhere in this codebase and must be created as part of
implementation, not assumed to already exist.

## 10. Failure Behavior

Mirroring `SigningService.verify()`'s existing contract (never throws,
returns `false` on any malformed input): a native verifier must return a
clean boolean/sealed result, never propagate an exception up through
`PacketRelayEngine.process()`. On verification failure, the packet must:
- **Not** be inserted into the `seen` dedup cache as if it were
  legitimate (a spoofed/corrupted packet flooding retries should not
  poison the cache against a later legitimate copy of the same
  `packet_id` — though note: a legitimate packet re-sent with a genuinely
  different signature is not expected in this protocol, so this is a
  narrow theoretical edge case, not the primary concern).
- **Not** be relayed.
- **Not** count toward `totalProcessed`/be treated as a normal drop in a
  way indistinguishable from a benign duplicate — a distinct counter
  (e.g. `signatureFailures`) would give real visibility into whether this
  is actually happening in the field, mirroring how Dart's own
  `MeshMetrics` separately tracks signature-verify timing today.
- Be logged (native `Log.w`/`Log.i`, consistent with existing logging
  hygiene — never log the payload or signature in full, per the
  Observability doc's existing hygiene rule).

## 11. Compatibility Risks

- **§5's `double.toString()` risk** is the most concrete, described
  above — must be solved with a fixed test vector before trusting any
  "verified" result on `EmergencyPacket`/`AlertPacket` (packets with
  float fields in their payload). `AckPacket`/`TerminationPacket` have no
  float fields in their signed payload and are lower interop risk.
- **`timestamp.toIso8601String()` formatting** — Dart's UTC ISO8601
  output (`2026-01-01T12:00:00.000Z` style, millisecond precision,
  trailing `Z`) must be reproduced exactly if a native verifier ever
  reformats a parsed timestamp rather than using the raw string it
  received. The safer approach (like the float fields) is to always
  reuse the **exact substring received in JSON**, never reformat a parsed
  value before it goes into the payload-to-verify string.
- **No fixed test vector exists today** anywhere in the codebase (§9) —
  this is a real gap that must be closed before any implementation, not
  a footnote.
- **New dependency, unvalidatable in this sandbox** (§11 title, see next
  section) — the actual blocker for this pass.

## 12. Migration Strategy (if/when implemented)

1. Add the BouncyCastle dependency; confirm the project actually builds
   with it (this alone requires the toolchain this sandbox does not
   have).
2. Implement the fixed test-vector unit test (§9) first, prove it passes,
   *then* wire verification into `PacketRelayEngine.process()`.
3. Insert the verification call at the point specified in
   `docs/security/NATIVE_MESH_AUDIT.md`'s updated packet-processing-order
   section — after size/structural checks, before dedup-cache insertion
   (see the companion analysis in that doc for why, and why this is safer
   than verifying after insertion).
4. Ship behind a mechanism that lets a bad rollout be reverted without a
   full app update if at all possible (e.g. a policy flag pushed the same
   way `allowRelay`/`discoveryIntervalMs` already are, defaulting to "off,
   trust as today" until confidence is established) — **not implemented
   or even scaffolded this pass**, listed here only as a migration-safety
   consideration for whoever picks this up.
5. Validate on real devices per an expanded `MULTI_DEVICE_TEST_PLAN.md`
   scenario using at least one deliberately malformed/forged packet
   injected from a test harness or modified client.

## Summary Table

| Question (from sprint brief) | Answer |
|---|---|
| Can native signature verification be added safely? | Yes, in principle — BouncyCastle is a well-understood, minSdk-independent path that maps directly onto Dart's existing raw-byte encoding. |
| Was it implemented this pass? | **No.** See final report §11/Blockers — a new Maven dependency cannot be resolved or built in this sandbox (network to Maven Central and the Gradle wrapper distribution are both blocked; confirmed by direct test, not assumed), so nothing here could be compiled or verified. Implementing crypto code that has never been compiled, let alone tested against a real signature, would violate this sprint's own rule against fabricated verification. |
| What would change if implemented? | Only `PacketRelayEngine.kt` (a new verification step + a new dependency) and `build.gradle.kts` (one new dependency line). No signature payload, no key format, no wire format change anywhere. |
