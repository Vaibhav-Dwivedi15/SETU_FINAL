# SETU — Backend API contract for the mobile app (Aug 25, 2026)

For Sudheer. These endpoints are **built, committed, and live on the backend**.
The Flutter side is not built — this document is the contract to build against.

---

## 1. Email OTP login (replaces the demo client-side OTP)

The current `login_screen.dart` generates a 6-digit code locally and shows it on
screen. It's honestly labelled a demo in its own header comment, but it verifies
nothing. These two endpoints replace it.

**Why email and not SMS:** SMS OTP in India requires a paid gateway plus TRAI DLT
sender registration. Email is free with no telecom regulatory dependency.

### `POST /auth/request-otp`
```json
{ "email": "user@example.com", "sender_id": "<hex Ed25519 public key, optional>" }
```
Response `200`:
```json
{
  "email": "user@example.com",
  "delivered": true,
  "expires_in_minutes": 10,
  "detail": "Verification code sent to user@example.com."
}
```

**CRITICAL — do not skip this:** `delivered` can be `false` with a `200` status.
That means the code exists but **no email actually went out** (SMTP unconfigured
or the send failed). The app **must** show `detail` to the user in that case, not
a "code sent!" message. Showing success over an email that went nowhere is exactly
the kind of demo-time lie this project's shipped-vs-roadmap rule exists to prevent.

Resending inside 60 seconds reuses the existing live code instead of emailing a
new one — so a "Resend" button won't mail-bomb the address, but it also won't
generate a fresh code within that window.

### `POST /auth/verify-otp`
```json
{ "email": "user@example.com", "code": "123456" }
```
Response `200`: `{ "email": "...", "verified": true, "sender_id": "...", "detail": "Email verified successfully." }`

Response `400` with a specific `detail` for each failure — show it directly:
- No active code for this email → request a new one
- Code expired (10 min lifetime)
- Too many incorrect attempts (limit 5) → request a new code
- Code incorrect

Codes are single-use. A correct code will not verify a second time.

**Scope note:** verifying does NOT return a session token or JWT, and does not
gate any other endpoint. SETU's real identity primitive is still the device's
Ed25519 keypair (`sender_id` IS the hex public key). Email verification only
confirms a human controls a contactable address. Don't build a parallel auth
system on this without a team decision.

---

## 2. Voice SOS

### `GET /ingest/voice/status`
Call this **before** showing a record button.
```json
{ "available": true, "detail": "Voice SOS is available." }
```
If `available` is `false`, don't let the user record something that can't be
processed — the server needs `openai-whisper` plus a system `ffmpeg` install,
and neither is present on a fresh Render instance.

### `POST /ingest/voice`
`multipart/form-data`:

| field | type | notes |
|---|---|---|
| `file` | file | audio; `.wav .mp3 .m4a .ogg .oga .webm .flac .aac .mp4`, max 25MB |
| `sender_id` | string | hex Ed25519 public key — required |
| `latitude` | float | defaults 0.0 (the spec's no-GPS fallback) |
| `longitude` | float | defaults 0.0 |
| `priority` | string | optional: `low` \| `medium` \| `high` \| `critical` |
| `emergency_id` | string | optional; server generates one if omitted |

Response `200`:
```json
{
  "incident_id": 42,
  "emergency_id": "voice-a1b2c3d4e5f6",
  "packet_id": "voice-...",
  "transcript": "There is a fire on the second floor, two people are trapped",
  "ai_analysis_available": true,
  "note": "..."
}
```

**Show the transcript back to the user.** A mis-transcription during an emergency
is something they need to see and be able to correct.

Errors: `503` transcription unavailable · `415` unsupported format · `413` too
large · `400` empty file · `422` transcription produced nothing (silent/corrupt audio).

**Multilingual — what's real:** Whisper runs in *translate* mode, so a user can
speak Hindi, Bengali, Tamil, Marathi, etc. and the pipeline understands it. The
stored message is the **English translation** — the original-language wording is
not preserved. Don't describe it as "the message is kept in the user's language."

**Trust level — important:** voice uploads are **not** Ed25519-signed (audio can't
travel the mesh; it's far too large for BLE/Wi-Fi Direct hop-by-hop relay, which
is the constraint the whole system is designed around). So this arrives over the
internet, unsigned, and is marked as such in the incident's audit trail. It does
**not** carry the same cryptographic guarantees as `/ingest`. Don't present it as
if it does.

---

## 3. Nearby community alerts (Phase 3, already live)

### `GET /alerts/nearby?lat=&lon=&radius_km=&sender_id=`
Polling, not push. The app sends its **own current** coordinates each call;
nothing is stored server-side. `radius_km` defaults to 2, hard-capped at 15.
Passing `sender_id` excludes incidents that sender already responded to.

Returns privacy-safe fields only — no victim identity, ever. The `message` field
carries the spec's exact wording: *"An emergency has been reported near your area.
If you are safe and able to help, please open SETU for details."*

### `POST /alerts/{incident_id}/respond`
```json
{ "sender_id": "...", "response_type": "CAN_HELP" }
```
Valid: `NEARBY` · `CAN_HELP` · `ALREADY_RESPONDING` · `CALLED_EMERGENCY_SERVICES` · `NAVIGATING`

Upsert by `(incident_id, sender_id)` — responding again updates the existing row
rather than creating a duplicate.

---

## Not built on the Flutter side (yours to do)

1. Replace `login_screen.dart`'s local OTP with `/auth/request-otp` + `/auth/verify-otp`.
   The existing file's own header says the swap should only touch `_sendOtp()` —
   worth checking that still holds now that it's email rather than phone.
2. Voice recording UI + upload to `/ingest/voice`, gated on `/ingest/voice/status`.
   Needs a recording package and mic permission in `AndroidManifest.xml`.
3. Poll `/alerts/nearby` when the app is open, and wire the five response actions.
4. App-wide language switching. The existing `language_selection_screen.dart` sets
   a preference — whether it actually drives app-wide strings needs checking; the
   dashboard's approach (`src/utils/i18n.js`) may be a useful reference for the
   key structure, but Flutter would normally use `flutter_localizations` + ARB files.
