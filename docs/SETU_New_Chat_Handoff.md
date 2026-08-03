# SETU — Handoff for New Chat / New Claude Account
Paste this whole doc as the first message in the new chat. It's self-contained — no other chat history is assumed.

## What SETU is
Offline-first emergency mesh communication platform, built for **Smart India Hackathon (SIH) 2026**. Turns nearby smartphones into a BLE/Wi-Fi Direct mesh relay network — no SIM, no data, no new hardware — feeding distress signals into India's existing **112/SACHET** government emergency infrastructure rather than building a parallel system. Project name is **Setu** (Hindi for "bridge") — an earlier name, "Bharat Connect," was dropped due to a conflict with an existing NPCI/RBI brand.

**Deliberate scope:** cut from 15+ possible domains down to one mesh core + two verticals — disaster SOS, and a women's-safety stealth mode. This narrowing is a stated project strength, not a limitation. Resist scope creep back toward breadth.

## Team & roles
- **Vaibhav** — Team Lead + Mesh/Networking Lead (this is who you're talking to)
- **Sudheer** — Mobile/UI
- **Ayush** — Backend
- **Vaishnavi** — AI/ML
- **Vanshika** — Dashboard/Frontend
- **Shaurya** — Security + Documentation & Pitch Lead

## The five components
1. **Backend** — FastAPI, Python. Live at `https://setu-backend-cy78.onrender.com` (Render free tier — 30–50s cold start after inactivity, expected not a bug). Postgres via Neon. Ed25519 packet signature verification, incident dedup, SMS notifications, AI-analysis integration.
2. **AI Service** (`setu_ai_service`) — vendored inside the backend, also exists as its own standalone zip. Handles incident classification, urgency/priority scoring, and duplicate-cluster detection (geo + time + lexical + optional multilingual embedding via a Hugging Face sentence-transformers model). Built by Vaishnavi.
3. **Dashboard** — React + Vite, the responder-facing web app (not the citizen mobile app). Deployed at `https://setu-sih-dashboard.vercel.app`. Dark/light theme, live map, incidents table, analytics, command palette, CSV export. Built by Vanshika.
4. **Mobile app** (`setu_app`) — Flutter, the citizen-facing app. Has the full mesh networking layer (BLE/Wi-Fi Direct relay, packet signing, local queue, responder registry) plus native Kotlin transport layer. This is the **canonical, complete** app. Built by Sudheer.
5. **`setu_sos_app`** — a second Flutter zip that exists alongside `setu_app`. **Confirmed missing the entire mesh + security layer** that `setu_app` has. Almost certainly a stale/earlier fork — needs a direct check with Sudheer before treating it as current or using it for anything demo-facing.

## Critical facts that must not get overclaimed
- **Full signed-packet end-to-end relay between two physical devices has never been observed.** Connection layer (BLE/Wi-Fi Direct handshake) is confirmed working; actual packet relay with signature verification across two real devices has not been tested end-to-end. This distinction must hold in all pitch/documentation — it's been a recurring correction point in past sessions. Don't let this get rounded up to "relay works" anywhere.
- **The `Backend_final.zip` reviewed on Aug 4 has no CORS middleware in its code at all**, yet the live Render deployment works with `CORS_ALLOWED_ORIGINS_RAW` set — meaning that zip is very likely stale relative to whatever's actually deployed. Don't assume any specific backend zip matches production without confirming with Ayush first.
- **The in-memory AI dedup cluster state is still an unresolved architectural limitation** (see below) — the test-isolation symptom of it is fixed, but the underlying risk (state resets on restart, not shared across multiple worker processes) is not. Don't claim dedup is "fully solved" — only that the test suite correctly reflects its current, single-process-only behavior now.

## Fixed since the Aug 4 debug pass
- **Backend incident-dedup test failure — fixed and verified.** `test_nearby_same_type_reports_merge_into_one_incident` used to fail whenever the full suite ran (though it passed 100% of the time in isolation) — a test-isolation bug, not a dedup logic bug. Root cause: dedup depends on `setu_ai_service`'s `duplicate_detector.py`, which keeps cluster state in a plain in-memory list at module scope; earlier tests left residual state that later tests collided with. Fix: added `Backend/tests/conftest.py` with an autouse `reset_clusters()` fixture — the exact same pattern Vaishnavi's AI service already uses in its own test suite (`setu_ai_service/tests/test_models.py`), which the backend's tests had just never adopted. **Verified: 28/28 tests pass, reproducibly, across multiple run orders** (was 27/28). This is a small, targeted fix — one new file, nothing else touched. It does NOT change the underlying in-memory-state architecture; that's still a real limitation (see below), just no longer causing false test failures.
- **🔴 `SosRepository.triggerSOS()` never called the mesh layer at all — fixed.** Found while wiring the ack packet in (see below). The entire mesh stack (signing, relay, TTL, dedup, native transport) was built and tested, but the SOS button only ever sent SMS and wrote a local mock alert — nothing reached the actual mesh. This was almost certainly the single biggest gap in the whole project relative to what the pitch claims. Fixed: `triggerSOS()` now builds a signed `EmergencyPacket` via the existing `EmergencyPacketBuilder` and calls `MeshLocator.instance.meshService.originate()` for every SOS, private or public. **Not yet verified on real hardware** — see the relay test plan.
- **Mesh feature set added**: login permission gate (BLE/Wi-Fi/nearby/GPS, was completely missing before), permission retry before SOS, connectivity-based mesh start/stop, location-aware relay re-entry (a device that's moved can relay a previously-seen packet again), and a real ack-packet confirmation loop (exit node originates an ack on successful backend upload, it relays back through the mesh, the original sender's device surfaces it via a new `MeshService.acknowledgments` stream). Community alert packets (public-mode broadcast) also now actually go out over the mesh instead of just writing local mock data. All of this shipped as `setu-mesh-features-v2.zip` with a full file-destination table and honest list of what's still not wired (A's UI status is still optimistic, `community_demo_screen.dart` still shows mock data) — see that zip's `CHANGES.md` for exact detail. **None of this has been run through `flutter analyze` or a real build** — the working environment had no access to pub.dev.

## Still open / needs a team decision
- **Physical end-to-end relay test has still never been run** — and now that the SOS-to-mesh wiring gap above is fixed, it's finally possible to test meaningfully (before this fix, even a perfect test setup would have found nothing on the mesh at all). A 6-stage test plan exists (`SETU_Relay_Test_Plan.md` from this session) — run it before claiming relay works in any pitch context.
- **In-memory AI dedup cluster state is a genuine operational risk for anything beyond a single-process demo** — already flagged in the code's own comments (resets on restart, inconsistent across multiple workers). Worth a dry run under actual demo conditions (multiple SOS submissions, no backend restart in between) before SIH judging, to confirm it won't misbehave on stage. A real fix (Redis or DB-backed clusters) is a bigger call for the team, not something to change unilaterally.
- **`setu_sos_app` vs `setu_app`** — `setu_sos_app` is missing the entire mesh + security layer that `setu_app` has (confirmed in the Aug 4 review: 88 files vs 124, no `lib/mesh/`, no `lib/security/`, untouched default Flutter README). Needs a direct check with Sudheer on whether it's stale/dead before it goes anywhere near a demo.
- **Whether `Backend_final.zip` actually matches the live Render deployment** — unconfirmed as of Aug 4 (see CORS note above). Get a fresh export from Ayush before treating any backend zip as ground truth.
- **A's delivery confirmation is still optimistic** — the "Delivered" status shows immediately on send, not once a real ack confirms it reached the backend. Deliberately not fixed this session because the history screen's success styling does an exact string match on that status — fixing it properly needs three coordinated file changes, not a quick patch.

## Known-good state as of Aug 4, 2026
- Dashboard: built, tested, deployed, verified live and connected to the real backend (CORS configured, env vars set).
- AI service: 38/38 of its own tests pass in isolation; confirmed byte-identical between its standalone zip and the copy vendored in the backend.
- Backend: 28/28 tests pass after the dedup test-isolation fix above.
- Mobile app (`setu_app`): full mesh + security + native layer present and structurally sound; the previously-caught `mesh_service.dart` overwrite bug is confirmed fixed in the current zip; SOS-to-mesh wiring gap fixed this session (not yet device-tested); ack/alert packets fully wired end-to-end (not yet device-tested).
- No secrets or live `.env` files found in any of the five most recent submission zips — a real improvement given this project has previously caught a live API key exposure.

## Security incidents caught previously (for context, already resolved)
- A live Gemini API key was once found exposed in a submitted zip with an empty `.gitignore` — required credential rotation.
- `mesh_service.dart` was once found completely overwritten with an unrelated class in a teammate's submission — would have silently broken the whole relay pipeline. Confirmed fixed as of the Aug 4 review.

## Working style / how to talk to Vaibhav
- Fast, direct execution. Minimal preamble. No verbosity or "bachkana" (childish) tone.
- Working sessions often happen in **Hinglish** (Hindi+English, Roman script), matching team communication. Formal deliverables (pitch content, documentation) use English.
- Match register to context: informal for working sessions, sharp and professional for pitch/doc output.
- Corrections are given directly — incorporate immediately, don't re-explain or re-litigate.
- Scope creep gets pushed back on explicitly, not accommodated.
- **No overclaiming, ever** — especially around the end-to-end relay gap above. This has been corrected multiple times across sessions; it should not need correcting again.

## Tools & stack reference
- **Backend:** Python, FastAPI, SQLAlchemy, Postgres (Neon), Alembic (partially — currently using `create_all()` as a stopgap, not full migrations)
- **AI:** sentence-transformers (multilingual embedding dedup), Gemini API (optional, currently disabled by default via `SETU_AI_GEMINI_ENABLED=false`)
- **Mobile:** Flutter/Dart, native Kotlin (Android) for BLE/Wi-Fi Direct transport
- **Crypto:** Ed25519 packet signing
- **Dashboard:** React + Vite, deployed on Vercel
- **Target integration:** India's 112 emergency system, SACHET platform
- **Competition:** Smart India Hackathon (SIH) 2026

## What this new chat should NOT assume
Don't assume any code fix, test result, or deployment status beyond what's stated above as "known-good as of Aug 4, 2026" — if the person references something from further back (e.g. "the load test," "the Day 5/6 decision," specific bug fixes), ask them to paste the relevant detail rather than guessing, since chat history doesn't carry over across accounts.
