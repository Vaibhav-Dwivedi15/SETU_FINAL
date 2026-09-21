# SETU Native Mesh — Connection-Level Authentication Design

Owner: Vib (Mesh/Architecture). Written Sep 21 2026, Bulk Sprint 3.
Status: **DESIGNED, NOT IMPLEMENTED** — no product/security decision has
been made yet; this document exists so the team can make one.

## Current State

`NearbyConnectionsManager.onConnectionInitiated` accepts every incoming
connection unconditionally:
```kotlin
override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
    Log.i(TAG, "Connection initiated with $endpointId, auto-accepting")
    connectionsClient.acceptConnection(endpointId, payloadCallback)
}
```
No check on `info` (which, in the real Nearby Connections API, carries an
`authenticationDigits`/token the app could optionally surface to the user
for manual confirmation — SETU does not use this).

## Does Nearby Already Provide Endpoint Identity?

Nearby Connections' `endpointName` (here, `"setu-" + random 4-digit
number`, generated fresh per process start — see
`NearbyConnectionsManager.localEndpointName`) is **not a stable identity**.
It changes every time the app/service restarts, is not tied to any
cryptographic material, and is trivially spoofable — any device running
compatible code can advertise as any `endpointName` it likes. Nearby
Connections does provide an out-of-band `authenticationDigits` short code
for optional human verification (the "does this match on both screens?"
pattern used by some pairing UIs), but SETU's auto-accept flow does not
surface or check it.

## Does SETU Have a Trusted Device Identity Already?

**Yes, at the application layer — `sender_id` (see
`NATIVE_SIGNATURE_VERIFICATION_DESIGN.md` §3/§4).** Every device already
has a persistent, self-certifying identity: its Ed25519 public key,
hex-encoded. This identity is **not** currently checked at connection
time — it only becomes relevant once a *packet* signed by that key
arrives, one layer above the raw Nearby Connections transport.

## Is Connection-Level Authentication Actually Necessary?

This is the central question this document exists to help answer, and it
has a real, non-obvious answer once signature verification is
considered (whether implemented in Kotlin per
`NATIVE_SIGNATURE_VERIFICATION_DESIGN.md`, or only in Dart as today):

- **An unauthenticated Nearby Connection is not, by itself, a security
  hole for the emergency protocol.** A malicious device can connect
  freely today, but any packet it sends still has to pass signature
  verification (Dart-side today; possibly native-side in the future) to
  be accepted, relayed by a Dart-attached device, or acted upon. Auto-
  accept lets an attacker **talk to the mesh**, not forge messages that
  will be trusted.
- **What an unauthenticated connection DOES enable**: (a) an attacker
  device consuming a legitimate device's limited concurrent-connection
  slots / radio time (a denial-of-service against relay capacity, not
  message integrity); (b) — the more serious one, already flagged in
  `NATIVE_MESH_AUDIT.md` §5 and `NATIVE_SIGNATURE_VERIFICATION_DESIGN.md`
  — while native has **no signature verification of its own**, a
  backgrounded, Dart-detached device connected to by an attacker will
  relay forged packets further into the mesh before any Dart-attached
  device eventually rejects them. This is really a consequence of the
  *signature* gap, not the *connection* gap — closing native signature
  verification closes most of this risk regardless of connection auth.

So the two gaps are related but not the same, and the signature gap is
the more consequential one to close first.

## Option A — No Connection Authentication, Rely on Packet Signatures

**Description**: keep auto-accept as-is. Security is entirely enforced at
the packet layer (today: Dart signature verification; future,
potentially: native too, per the sibling design doc).

**Pros**: zero UX cost — critical for a disaster-response app where
asking a panicked bystander to complete a pairing ceremony is actively
harmful (the brief's own words: "not to create an annoying pairing
ceremony during an earthquake because engineers enjoy suffering," which
is the right instinct here). No implementation cost. Already the de facto
model — packet signing is already the actual trust boundary this
protocol relies on.

**Cons**: does not address the DoS-via-connection-slot-exhaustion
concern, and does not close the "native relays forgeries it can't verify"
gap by itself — that gap is closed by native signature verification, not
by connection auth.

## Option B — Challenge-Response

**Description**: on `onConnectionInitiated`, before accepting, exchange a
short cryptographic challenge (e.g. the connecting device signs a nonce
with its Ed25519 key — the same key already used for packet signing) to
prove the peer holds a private key, without needing to decide in advance
*which* key is trustworthy (any valid keypair passes — this proves
"is a real SETU client," not "is an authorized device").

**Pros**: closes the DoS-via-fake-endpoint concern (a non-SETU device
can't complete the challenge). No new identity/pairing UX — fully
automatic, reuses the existing keypair infrastructure conceptually.

**Cons**: real implementation cost — needs its own small protocol over
the Nearby Connections raw-bytes channel (a request/response exchange
before the "real" mesh traffic starts), and depends on the same Ed25519
crypto capability this sprint could not add to native (§11 of the sibling
design doc — no Maven dependency could be resolved in this sandbox).
Would need its own careful design pass, not a corollary of this one.
Still does not distinguish "a legitimate but unfamiliar SETU device" from
"an authorized responder" — any device with any keypair passes, which is
the same trust level packet signatures already provide today, just moved
one layer earlier. The marginal security value over Option A is
therefore mostly the DoS mitigation, not new message-integrity guarantees.

## Option C — Known-Device Identity

**Description**: maintain an allowlist of known `sender_id` public keys
(e.g. devices belonging to the user's own household, or pre-registered
responder devices) and only auto-accept connections from
recognized endpoints, falling back to manual confirmation or rejection
for unknown ones.

**Pros**: strongest connection-level guarantee, if the allowlist can be
trusted.

**Cons**: directly conflicts with the app's actual purpose. SETU's value
is precisely that **any** nearby stranger's phone can become a relay hop
for **anyone's** emergency packet — that is the entire "last line of
digital communication when conventional networks fail" premise. An
allowlist model would break relaying through strangers, which is the core
feature, not an edge case. **Not compatible with this app's actual
design goal** — included here for completeness of the comparison, not as
a live option.

## Option D — Pairing/Trust Model

**Description**: a one-time manual pairing step (QR code scan, PIN
exchange, NFC tap) between devices that will regularly relay for each
other (e.g. household members, a response team), establishing a longer-
term trust relationship beyond a single connection.

**Pros**: could support a legitimate future use case — a response team
that wants assurance its own relay chain isn't being interfered with —
without breaking the general stranger-relay model (this could layer on
top of, not replace, Options A/B for the general public case).

**Cons**: real UX and implementation cost; only useful for a subset of
deployment scenarios (organized teams, not the general bystander-relay
case); the brief's own framing (no pairing ceremony during an emergency)
argues against this being the *default* path. Would need its own product
scoping — who initiates pairing, how it's revoked, how it interacts with
device loss/replacement — none of which this document attempts to design.

## Recommendation

**Option A (status quo — no connection-level auth, rely on packet
signatures) for the general case, with Option B (challenge-response) as
a real candidate for a future pass specifically to close the DoS/relay-
capacity-exhaustion gap** — but only once native signature verification
(the higher-priority, more consequential gap) is actually implemented,
since Option B's implementation cost significantly overlaps with that
work (both need a working native Ed25519 capability this sandbox
couldn't validate this pass). Option C is not compatible with the app's
purpose. Option D is a legitimate but separate, narrower feature for
organized-team deployments, not a general connection-security fix, and
should be scoped as its own product decision if the team wants it.

**Not implemented this pass, for either A/B/C/D** — this document's job
is to inform that decision, not make it.
