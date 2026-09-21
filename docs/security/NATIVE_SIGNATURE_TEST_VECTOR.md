# SETU Native Mesh — Ed25519 Signature Test Vector

Owner: Vib (Mesh/Architecture). Written Sep 21 2026, Bulk Sprint 4.

## What This Is, and Is Not

This document records a **GENERATED (not Dart-executed)** deterministic
Ed25519 test vector, produced and verified by actually running a
standalone Java program against BouncyCastle — not invented, not
hand-computed, not claimed without execution.

**Label, precisely**: every number below is **real, executed output**
from `Ed25519VectorTest.java`, compiled with `javac` and run with `java`
against `/usr/share/java/bcprov-1.77.jar` (Maven coordinates
`org.bouncycastle:bcprov:1.77`, confirmed present in this sandbox — see
§5 of the final report for how this was found). This is **not**
cross-verified against Dart's actual `cryptography` package output,
because the Dart SDK remains unavailable in this sandbox (confirmed
again this sprint, unchanged from Sprint 3) — no real Dart-signed packet
exists anywhere in this engagement to compare against. What this vector
proves: **the exact BouncyCastle primitives proposed for the native
Kotlin verifier (`Ed25519PrivateKeyParameters` / `Ed25519PublicKeyParameters`
/ `Ed25519Signer`) correctly sign and verify SETU's raw 32-byte-seed /
32-byte-pubkey / 64-byte-signature, hex-encoded wire format**, and that
tampering with any signed field is correctly detected. It does **not**
prove Kotlin will accept a signature Dart actually produced — that needs
either a real Dart run (still blocked) or a real device (still blocked).

## How It Was Generated

`payload` was built to exactly match `EmergencyPacket.signaturePayload`'s
real field order and the real generation scheme in
`emergency_packet_builder.dart` (packetId = first 8 hex chars of
sender_id + `-` + a fixed fake epoch-micros value; nonce = 16 fixed bytes
hex-encoded, matching `_generateNonce()`'s real 16-byte/32-hex-char
shape; timestamp in the exact `DateTime.toUtc().toIso8601String()`
format Dart produces for a UTC time with zero sub-second remainder).
Every "random" or "current time" value that Dart would normally compute
was replaced with a **fixed, hardcoded** value so the vector is
reproducible — this is a test fixture, not a real packet, and contains no
production key material (the 32-byte seed is literally the bytes
`0x00..0x1f`, chosen for readability, not security).

## The Vector (verbatim program output)

```
seed_hex=000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
sender_id(public_key_hex)=03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8
sender_id_length=64

payload_string=03a107bf-1767225600000000|03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8|emergency|2026-01-01T00:00:00.000Z|000102030405060708090a0b0c0d0e0f|03a107bf-1767225600000000|12.9716|77.5946|Test SOS message|critical
payload_utf8_byte_length=226

signature_hex=5edf2142db7afbf449fe0c4e46047ab90bb69f8cfbc5160cfe1b855e2819598815f67e466fc444acb97b3eb3f56f55f58ebabe92e50c33ae389743e234d61203
signature_length=128
```

Field breakdown (for anyone reconstructing this by hand):

| Field | Value |
|---|---|
| `packetId` | `03a107bf-1767225600000000` |
| `senderId` (= public key, hex) | `03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8` |
| `type.name` | `emergency` |
| `timestamp` | `2026-01-01T00:00:00.000Z` |
| `nonce` | `000102030405060708090a0b0c0d0e0f` |
| `emergencyId` | `03a107bf-1767225600000000` (same as packetId) |
| `latitude` | `12.9716` |
| `longitude` | `77.5946` |
| `message` | `Test SOS message` |
| `priority.name` | `critical` |
| `signature` (hex) | `5edf2142db7afbf449fe0c4e46047ab90bb69f8cfbc5160cfe1b855e2819598815f67e466fc444acb97b3eb3f56f55f58ebabe92e50c33ae389743e234d61203` |

## Negative Cases (all executed, all passed as expected)

```
[CASE 1] valid packet -> verify() = true (expected true)
[CASE 2] modified message -> verify() = false (expected false)
[CASE 3] modified latitude -> verify() = false (expected false)
[CASE 4] modified timestamp -> verify() = false (expected false)
[CASE 5] modified sender_id -> verify() = false (expected false)
[CASE 6] modified signature -> verify() = false (expected false)
[CASE 7] malformed public key (short) -> verify() = false (expected false, no exception)
[CASE 8] malformed signature (short) -> verify() = false (expected false, no exception)
[CASE 9] non-hex public key -> verify() = false (expected false, no exception)
[CASE 10] empty signature -> verify() = false (expected false, no exception)

ALL_CASES_COMPLETED_NO_CRASH=true
```

This covers 10 of the sprint brief's 11 required negative scenarios
directly (valid / modified description-equivalent(message) / modified
location / modified timestamp / modified sender_id / modified signature /
malformed public key / malformed signature / missing signature, plus the
no-crash guarantee). The remaining two (replay-packet behavior, oversized-
packet rejection) are **not signature concerns** — they are handled by
`ReplayProtectionService`/`SecurityConstants.maxPacketSize` respectively,
already covered in `docs/mesh/FAILURE_HANDLING.md` and
`docs/mesh/NATIVE_FAILURE_MATRIX.md`, and were not re-tested here since
this harness is scoped to the signature primitive only.

## Reproducing This

The exact program (`Ed25519VectorTest.java`) is included in this sprint's
delivery zip under `tools/`. To re-run it:
```
javac -cp bcprov-1.77.jar Ed25519VectorTest.java
java -cp .:bcprov-1.77.jar Ed25519VectorTest
```
Any BouncyCastle Ed25519 provider jar with the standard
`Ed25519PrivateKeyParameters`/`Ed25519PublicKeyParameters`/`Ed25519Signer`
classes should reproduce identical output (Ed25519 is fully deterministic
given a fixed seed and fixed message — no randomness in signing itself).

## What Would Still Be Needed for a REAL Cross-Language Vector

A genuine Dart-vs-Kotlin interop proof needs: (1) a working Flutter/Dart
SDK to actually run `SigningService.sign()` on a fixed payload and capture
its real output, and (2) comparing that real Dart-produced signature
against what this same payload verifies as under Kotlin/BouncyCastle. Both
require tooling this sandbox does not have. This document is the closest
approximation achievable without that tooling — it proves the crypto
*primitive* is sound, not that the two *specific runtimes* agree.
