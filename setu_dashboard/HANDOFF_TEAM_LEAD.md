> **Obsolete in part (Block 3):** `VITE_API_KEY` / `X-API-Key` from the browser and the automatic mock-data fallback were removed; see README.md.

# SETU Dashboard — Handoff to Team Lead (Vaibhav)

Final verification pass on Vanshika's dashboard. Covers what was
checked, what got fixed, and — most importantly — one real
architecture question that needs a decision before this can actually
talk to Ayush's backend for incident resolution.

---

## 1. What this dashboard is

The responder/control-room side of SETU — not the citizen SOS app.
Verified responders use this to see incoming alerts (from the mesh, via
Ayush's backend) and act on them: view details, mark resolved, track
resources and teams. Full breakdown in `README.md`.

## 2. Verification done this pass

- Fresh `npm install` + `npm run build` — clean, no errors
- Full test suite (12 tests: navigation, theme toggle, command palette,
  `/` shortcut, modal validation, detail drawer, notifications, CSV
  export, Teams fallback messaging, honest-stats checks) — all pass
- Checked every page renders and every documented feature (theme, sound
  alerts, CSV export, copy-to-clipboard) actually works, not just looks
  right

## 3. What was fixed

- **`.env.example` was missing `VITE_API_KEY`.** The dashboard's
  `services/api.js` reads this to authenticate against Ayush's backend,
  but it was never documented in the example env file. Without it, a
  teammate copying `.env.example` → `.env` would get silent 401s from
  Ayush's now-secured backend (RESPONDER_API_KEY/ADMIN_API_KEY are
  enforced there) with zero indication why — the dashboard just quietly
  falls back to mock data, which looks like "the backend isn't running"
  even when it is. Fixed, with an explicit comment explaining the
  failure mode.
- **`README.md` was still the unmodified Vite template boilerplate.**
  Never customized for this project. Replaced with something that
  actually describes what this is and how to run it.

## 4. The one thing that needs a real decision before integration

**The dashboard's "Mark Resolved" button doesn't have a real backend
endpoint to call yet — and the fix isn't just "add the endpoint."**

`services/api.js`'s `resolveIncidentOnBackend()` calls
`POST /incidents/{id}/resolve`. Ayush's backend, as last reviewed,
doesn't have this route — incidents get closed by sending a **signed
termination packet** through `POST /ingest` (Ed25519-signed, checked
against the responder registry by `sender_id`). That's the mesh-native
way an authorized responder closes an incident.

A browser dashboard can't do that the same way — it doesn't have a
responder's private signing key sitting in the browser (and shouldn't;
that key material belongs on a device, not in a web page). So this
isn't a small fix on either side alone. Two real options:

1. **Ayush adds a separate, API-key-gated REST endpoint**
   (`POST /incidents/{id}/resolve`) that performs the same
   authorization + status-change a termination packet would, without
   requiring a signature — a parallel administrative path alongside the
   mesh-native one, trusting the dashboard's existing API-key auth
   instead of Ed25519. This is what the dashboard already assumes exists
   (see `HANDOFF_AYUSH_BACKEND.md` for the exact spec) — simplest to
   wire up, but means "resolved via dashboard" and "resolved via signed
   mesh packet" are two different trust models converging on the same
   state change.
2. **Responders don't resolve from the dashboard at all** — closing an
   incident stays a mesh-only action (from a responder's phone, signed),
   and the dashboard's button either goes away or becomes
   read-only/informational until a termination packet actually arrives.

(1) is almost certainly what you want for the demo — it's a small,
well-scoped backend addition and keeps the dashboard's UX intact. But
it's Ayush's and your call, not something to silently implement by
guessing. The dashboard's current behavior (button works optimistically
in the UI, fails silently against the backend, never blocks the demo)
is a safe placeholder either way — nothing breaks while this gets
decided.

## 5. Known, already-documented limitations (not bugs)

- **Resources page is sample data**, not wired to a live fleet-tracking
  system — say so if asked, don't imply it's live
- **Teams page falls back to sample data** if the backend is
  unreachable or has no registered responders, and says so on-screen
- **AI Panel is explicitly labeled** "not a predictive model" — it's a
  live statistical snapshot of current incidents, not ML output
