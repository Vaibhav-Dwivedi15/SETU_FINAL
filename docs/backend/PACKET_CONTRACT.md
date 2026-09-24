# SETU packet & request contract (Block 2)

Authoritative description of what each layer produces, accepts and answers.
Everything here is enforced by tests named in §8. Status labels: VERIFIED =
executed in this environment; SOURCE REVIEW = read from code only.

## 1. Packet types

`Dart PacketType` = `emergency | termination | ack | alert`. The backend's
`PacketType` = `emergency | termination` only — by design.

| | emergency | termination | ack | alert |
|---|---|---|---|---|
| Producer | `EmergencyPacketBuilder` (SOS, recovery report) | responder app (`TerminationPacket`) | exit node after a confirmed upload (`AckPacketBuilder`, via `_originateAck`) | `AlertPacketBuilder` on a PUBLIC SOS |
| Consumers | mesh relays; backend `/ingest`; dashboard via Incident | mesh relays (close local queue/relay state, gated by `ResponderRegistry`); backend `/ingest` | mesh relays; origin device (`acknowledgments` stream → History/Recovery status) | mesh relays; nearby-alert UI |
| Signed fields (pipe-joined, `signaturePayload`) | `packet_id, sender_id, type, timestamp, nonce, emergency_id, latitude, longitude, message, priority` | `packet_id, sender_id, type, timestamp, nonce, emergency_id, responder_id` | `packet_id, sender_id, type, timestamp, nonce, original_packet_id, emergency_id` | `packet_id, sender_id, type, timestamp, nonce, incident_type, latitude, longitude, radius_meters` |
| Not signed (change per hop) | `ttl, hop_count, protocol_version, relay_path` | same | same | same |
| Accepted by backend? | **Yes** | **Yes** (sender must be a registered responder key) | **No** — `REJECTED unsupported_type` | **No** — `REJECTED unsupported_type` |
| Relayable | yes (tier = its declared `priority`) | yes (CRITICAL tier) | yes (HIGH tier) | yes (MEDIUM tier) |
| Uploadable to `/ingest` | yes (durable queue + `_tryUpload`) | yes | **no** (`_isUploadable`, `_tryUpload` first line, `_retryPendingUploads` filter) | **no** (same) |
| Terminal? | no (closed by a termination) | terminal for its emergency (clears local queue/relay, marks CLOSED) | terminal (surfaced on the origin's `acknowledgments` stream; one ACK per delivery event) | terminal (mesh broadcast only) |
| Expected `/ingest` response | `ACCEPTED` (+ `incident_id`, dedup decision, `sms_contacts_notified`) / `DUPLICATE` / `REJECTED` / `FAILED` | `ACCEPTED` (+ `closed_incident_id`, `null` if nothing to close) / `DUPLICATE` / `REJECTED unauthorized_responder` … | `REJECTED unsupported_type` (never sent) | `REJECTED unsupported_type` (never sent) |

The `voice` report is **not** a mesh packet: it is a signed HTTP request
(`POST /ingest/voice`, §3) that the backend turns into an internal emergency
row (`packet_id = voice-<uuid>`, `hop_count = 0`, `signature = signed-voice-request:<sig>`).

**No upload loop (VERIFIED by source review + tests).** Every mobile call site of
the backend upload is `MeshServiceImpl._tryUpload`, `_retryPendingUploads` and
`SosRepository` (emergency packet only). `_tryUpload` returns immediately for
`AckPacket`/`AlertPacket`; the durable queue never stores them (`_isUploadable`);
the retry sweep skips legacy rows of those types; and even a stray upload would
be `REJECTED` (mobile: `markUploaded`, stop retrying, no ACK). Backend support for
ack/alert was deliberately **not** added — nothing in the architecture requires the
backend to hold them.

## 2. `/ingest` response (HTTP success ≠ packet acceptance)

`POST /ingest {"packets": [ ... ≤500 ... ]}` → HTTP 200 with each packet in
exactly one list; every entry has `packet_id` and `status`:

| List | `status` | Meaning | Mobile (`UploadOutcome`) | ACK? | Retry? |
|---|---|---|---|---|---|
| `accepted` | `ACCEPTED` | authenticated, fresh, processed | `accepted` | yes | no |
| `duplicates` | `DUPLICATE` | this **exact** authenticated packet (same `sender_id`, `packet_id`, signed content) is already held | `duplicate` | yes (idempotent) | no |
| `rejected` | `REJECTED` (+`code`,`reason`) | never acceptable as sent | `rejected` | **no** | no (`markUploaded`) |
| `failed` | `FAILED` (+`retryable:true`) | server error, no decision | `failed` | **no** | yes |

Non-2xx (413 body too large, 422 bad envelope, 429 throttled, 5xx) ⇒ mobile
`failed` ⇒ packet stays queued and is retried. Reject codes:
`malformed`, `too_large` (>4096 B serialized), `unknown_type`, `unsupported_type`
(ack/alert), `schema`, `invalid_ttl` (outside 1..5), `invalid_timestamp`, `stale`
(>3600 s), `future_timestamp` (>30 s), `invalid_signature`, `packet_id_conflict`,
`unauthorized_responder`.

Check order (cheapest first; **authentication precedes dedup**):
size → type → schema/TTL → timestamp → signature → identity/dedup → store → route.

**Identity** = `(sender_id, packet_id)`; `sender_id` is the Ed25519 key that just
verified the signature. Only authenticated packets are stored (`raw_packets`);
refusals go to `rejected_packets`, which dedup never reads. Consequences:
a forged/stale/unsigned packet can never occupy a `packet_id`; a different key
using the same `packet_id` is an independent packet; the same key re-using a
`packet_id` with different content is `REJECTED packet_id_conflict` (never
`DUPLICATE`, so it can never be mistaken for a delivery).

### ACK meaning (unchanged protocol, now explicit)
An ACK = "**the backend held this packet when the exit node last asked**":
generated only after `ACCEPTED` or `DUPLICATE`, never after `REJECTED`,
`FAILED`, throttling or network failure. It is still **client-generated and
signed by the exit node**, not by the backend (KNOWN LIMITATION: a malicious
uploader could ACK without uploading; a backend-signed receipt would need a
protocol change, out of scope for Block 2).

## 3. Signed requests (registration, voice, nearby alerts, respond)

Use the device's existing Ed25519 key; nothing new is stored or sent.
Headers `X-Setu-Sender` (64 lower-hex pubkey = `sender_id`), `X-Setu-Timestamp`
(ISO-8601 with zone), `X-Setu-Nonce` (16–128 of `[A-Za-z0-9_-]`),
`X-Setu-Signature` (128 lower-hex) over

```
setu-req-v1|METHOD|/path|sender_id|timestamp|nonce|<part>|<part>…
```

| Endpoint | parts |
|---|---|
| `POST /register` | `sha256_hex(raw body)` |
| `POST /alerts/{id}/respond` | `sha256_hex(raw body)` |
| `GET /alerts/nearby` | raw `lat`, `lon`, `radius_km` query strings |
| `POST /ingest/voice` | `sha256_hex(audio bytes)`, raw `latitude`, `longitude`, `priority` or `""`, `emergency_id` or `""` |

Window ±300 s; `(sender, nonce)` single-use (replay ⇒ 401); the domain prefix
cannot be parsed as a packet payload (its 3rd field is `GET`/`POST`, not a packet
type). Status codes: 401 missing/invalid/stale/replayed, 400 malformed header,
403 identity mismatch / not registered / foreign `emergency_id`. Dart and Python
reproduce identical signatures from
`docs/backend/contract/request_signing_vectors.json`.

## 4. Time constants (`Backend/app/core/contract.py`)

| Constant | Value | Question it answers |
|---|---|---|
| `MESH_CARRY_MAX_AGE_SECONDS` | 300 | (Dart `maxPacketAge`) hop-to-hop freshness on **receipt** over the mesh — mirror only |
| `PACKET_MAX_AGE_SECONDS` | 3600 | how old may a signed packet be when it reaches `/ingest`? Longer than the mesh bound **on purpose**: delayed sync of packets held offline is a designed feature; the timestamp is signed so this only bounds replay |
| `PACKET_MAX_FUTURE_SKEW_SECONDS` | 30 | (Dart `allowedClockSkew`) |
| `AI_DEDUP_WINDOW_SECONDS` | 300 | how long the AI keeps a text/geo cluster open (server receipt time) |
| `INCIDENT_DEDUP_WINDOW_SECONDS` | 900 | backend DB fallback dedup window (AI unavailable / proposal vetoed) |
| `AI_DEDUP_RADIUS_METERS` / `INCIDENT_DEDUP_RADIUS_METERS` | 500 / 150 | AI geo radius / fallback radius |

Timestamps: strict ISO-8601 **with explicit zone** (`Z` or `±hh:mm`), 0–9
fractional digits; naive/date-only/basic/space-separated forms are
`invalid_timestamp` (no local-vs-UTC ambiguity). The raw string — never a
re-serialisation — is what the signature covers.

## 5. Incident dedup (AI proposes, backend decides)

Each `accepted` emergency carries `dedup_decision` (`NEW_INCIDENT|MERGED`),
`matched_incident_id`, `dedup_reason`, `dedup_evidence`. Reasons:
`no_ai_match`, `ai_match_accepted`, `ai_match_vetoed_{closed,unresolved,category,distance}`,
`fallback_match`, `fallback_no_match`. A CLOSED incident can never absorb a new
emergency; a category conflict or a backend-computed distance beyond the radius
vetoes the AI's proposal; after a veto the backend's own OPEN-incident dedup
still applies.

## 6. Dashboard `IncidentOut`

`id, incident_type, latitude, longitude, status, hop_count, relay_path,
sender_priority, ai_incident_type, ai_incident_confidence, ai_incident_explanation,
ai_urgency, ai_urgency_confidence, ai_urgency_explanation, ai_priority,
display_priority, report_count, created_at, updated_at, closed_at`. Golden example:
`Backend/tests/contract/incident_out.example.json` (checked by pytest **and** the
dashboard's `npm test`). `relay_id`, named in the Block 2 brief, does not exist
anywhere in the dashboard or backend code (grep-verified) — nothing was added for it.

## 7. Nearby alerts

Signed, **registered** device only; per-IP and per-key rate limit; at most 20
rows; fields `incident_id, incident_type, sender_priority, ai_priority,
distance_km (100 m resolution), created_at, message`. No coordinates, sender
identity, profile, contacts or medical data.

## 8. Where each rule is tested

`Backend/tests/`: `test_ingest_contract.py` (§2, §4, squatting), `test_request_auth.py`
(§3, §7, SMS, voice), `test_dedup_safety.py` (§5), `test_dashboard_contract.py` (§6),
`test_abuse_controls.py`, `test_e2e_contract.py` (all layers, real Dart wire packets),
`test_request_signing_vectors.py`; `setu_app/test/backend_contract_test.dart`,
`block1_mesh_test.dart`; `setu_dashboard/tests/contract.test.mjs`.
