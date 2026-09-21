# SETU Mesh — "Relayed" State: Design-Only Analysis

Owner: Vib (Mesh/Architecture). Written Sep 21 2026, updated during Bulk
Sprint 2 with native-layer findings. **This document is design-only.
Per both sprint briefs' explicit instruction, "Relayed" state is NOT
implemented in this pass** — this is the analysis needed to make an
informed decision later, not a proposal to build it now.

This supersedes/extends the "Relayed-state conclusion" section of
`SETU_VIB_MESH_HARDENING_REPORT.md` (Bulk Sprint 1) with what the native
audit changes about the answer.

## Definition

Today, an originating device's history/recovery entry has exactly two
states visible from an ack: "Sent" (queued/transmitted, no ack yet) and
"Delivered" (backend accepted it, an `AckPacket` made it back). There is
no intermediate state representing "a peer received and relayed your
packet, but it has not yet reached the internet" — from the originator's
point of view, a packet sitting at hop 3 of 5 looks identical to a packet
that never left the device's own radio range.

"Relayed" would be a third state: confirmation that *some* forward
progress happened, even without final delivery confirmation.

## Why the current ACK cannot represent it

`AckPacket` is explicitly, by design, an end-to-end signal — it is
originated once, only by whichever device actually uploads to the backend
(`_markPacketDelivered()` → `_originateAck()`), and it means exactly one
thing: "the backend has this." Overloading it to also mean "a peer touched
this" would require either:
- A new ack *type* distinguishing hop-ack from delivery-ack (rejected by
  both sprint briefs' non-negotiable rule against inventing a new packet
  type), or
- A boolean/counter field added to the existing ack's payload — but the
  existing ack's `signaturePayload` is explicitly frozen (non-negotiable
  rule in both briefs); any field affecting what's signed is out.

So representing "Relayed" genuinely requires a new protocol-level signal,
not a repurposing of what exists — which is exactly why this sprint
brief asks for design-only analysis rather than an implementation.

## Possible protocol event (design sketch, not proposed for immediate build)

A per-hop, unsigned, best-effort "I touched this packet_id" beacon,
separate from the signed `AckPacket`:
- Emitted by a relay hop the moment it decides to forward a packet (native
  `PacketRelayEngine.process()` already computes this exact moment — the
  `isNew = true` / `relayBytes != null` branch).
- NOT signed, NOT durable, NOT retried, NOT stored in `LocalQueueService`
  — purely a best-effort "progress ping" the way TCP has no equivalent for
  application-level relay confirmation. If it's lost, the originator
  simply doesn't get a "Relayed" update for that hop; that's an acceptable
  degradation for an informational-only state, unlike the emergency
  packet itself or its real delivery ack, both of which must be reliable.
- Would need its own packet-type byte value (a genuinely new type, which
  is why this needs a deliberate decision, not a quiet addition) and its
  own lightweight relay/dedup treatment — likely simpler than a full
  `MeshPacket` subtype, since it carries no payload beyond a packet_id and
  doesn't need TTL/hop-count semantics of its own (it dies at 1 hop by
  design — it's reporting "I saw it," not itself propagating).

## Possible packet design (sketch)

```
{
  "type": "relay_ping",          // new, minimal
  "packet_id": "<id being relayed>",
  "relayed_by": "<short device id>",  // for future multi-hop-path visibility, not required for a v1 boolean signal
  "hop_count_at_relay": 2
}
```
No `nonce`, no signature, no ttl beyond "delivered directly back toward
the presumed originator, single hop, not itself relayed further" — this
keeps it cheap, which matters given the cost analysis below.

## Battery cost

Every successful relay decision would now also transmit a second, smaller
payload back toward (an approximation of) the originator. In the current
architecture, "back toward the originator" is not a concept native or
Dart currently track for arbitrary packets (only the ack path knows how to
route back, via the mesh's ordinary flood-relay, not a directed route) —
so realistically this "relay ping" would have to flood the mesh exactly
like every other packet does today, at 1-hop TTL. That's a full
extra broadcast-radio-wake per relay decision, on every device in range,
for every hop of every packet — a meaningful percentage increase in radio
airtime for emergency traffic that is, by definition, happening in a
battery-constrained disaster scenario. This is the primary reason both
sprint briefs are cautious about building this blindly.

## Airtime cost

Related to battery: mesh bandwidth in a real disaster deployment (dozens
of devices, BLE's modest real-world throughput) is a genuinely scarce
resource. Doubling the number of broadcasts per relay hop for a
convenience feature (a nicer status than "Sent") competes directly with
the actual emergency payload's airtime, especially under Scenario 4 of
`MULTI_DEVICE_TEST_PLAN.md` (loop/dense topologies) where broadcast volume
is already the primary risk factor.

## Security implications

An unsigned, unauthenticated "I relayed packet X" ping is spoofable —
any device (malicious or buggy) could claim to have relayed a packet it
never actually saw, producing a false "Relayed" status client-side. Since
this is explicitly proposed as informational-only (never gating a real
decision — no retry logic, no relay-decision, no security check would
ever consult it), a spoofed ping is low-severity (a misleading UI state,
not a security bypass) — but it's still worth stating plainly rather than
silently assuming "well it's just UI, who cares."

## Native-layer note (Bulk Sprint 2 addition)

Native Kotlin's `PacketRelayEngine.process()` already knows the exact
moment a relay decision is made — a "relay ping" origination point would
naturally live in Kotlin, not Dart, unlike the real `AckPacket` (which is
Dart-only today, see `NATIVE_MESH_AUDIT.md` §9). This means implementing
"Relayed" state would be native Kotlin's first packet-*origination*
responsibility, not just relay/dedup — currently native only ever forwards
bytes it did not create. That's a meaningful architectural boundary shift
worth the team weighing on its own, independent of the airtime/battery
cost above: today, "what packets can exist" is entirely a Dart-layer
decision; this would be the first exception.

## Recommendation

Not recommended for implementation without a deliberate product decision
that the UX value (a more granular status than "Sent"/"Delivered")
outweighs the airtime/battery cost in an actual emergency scenario, and
without deciding whether native or Dart should own origination of the new
signal. If the team does decide to build it, this document's packet
sketch and cost analysis are a reasonable starting point, but the
unsigned/spoofable/best-effort framing above should be treated as a
starting proposal to be reviewed, not a final design.
