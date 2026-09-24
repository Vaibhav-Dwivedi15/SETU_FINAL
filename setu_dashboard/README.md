> **Block 3 security note.** The dashboard no longer contains any responder key: operators sign in at
> runtime (`POST /auth/responder-login`) and receive a short-lived session token. Anything named
> `VITE_*` is public JavaScript. Sample/mock data exists only in an explicit `VITE_DEMO_MODE=true`
> build. Security headers are defined in `vercel.json`. See `docs/security/BLOCK3_FINAL_SECURITY_VALIDATION.md`.
> (Older text below that mentions `VITE_API_KEY` or automatic mock-data fallback is obsolete.)

# SETU — Responder Dashboard

Web dashboard for verified responders (NDRF, fire, police, medical,
government officials) to monitor and act on SOS alerts relayed through
SETU's offline-first mesh network. Not the citizen-facing app — that's
the separate Flutter mobile app. See
`HANDOFF_TEAM_LEAD.md` and `HANDOFF_AYUSH_BACKEND.md` for the full
picture of how this fits into the rest of the project and what's needed
to wire it up to the live backend.

## Quick start

```bash
npm install
cp .env.example .env   # then fill in VITE_BACKEND_URL (https:// in production). There is NO API-key variable.
npm run dev
```

Works with zero setup even before the backend is live — it automatically
falls back to representative mock data and shows "Offline (Mock Data)"
in the sidebar. Every feature (map, filters, command palette, exports,
theme) works identically on mock data, so this is safe to demo from
even without Ayush's backend running.

## Pages

- **Dashboard** — overview: stats, map, recent incidents, analytics, live situational snapshot, resources
- **Live Map** — full-size map with an incident rail
- **Incidents** — full sortable table, CSV export
- **Analytics** — type/priority breakdowns, resolution rate
- **Resources** — asset deployment status (currently sample data — see handoff docs)
- **Teams** — registered responders (fetched from the backend, falls back to sample data)
- **Settings** — theme, poll interval, notifications, sound alerts — all real and persisted

## Features worth knowing about

- **Command palette** — Ctrl/Cmd+K, or `/` to jump straight to search
- **Notification center** — bell icon, persistent alert history
- **Light/dark theme** — toggle in the navbar or Settings
- **Incident detail drawer** — click any incident for full detail + mini-map + copy-to-clipboard actions

## Tech stack

React + Vite, react-leaflet (CARTO tiles), Recharts. No router — page
switching is in-memory state (`activePage` in `App.jsx`), not URL-based.
No Redux — plain React state + one Context (theme only).

## Testing

Test tooling isn't a permanent dependency (kept `package.json` lean) —
install ad hoc when needed:

```bash
npm install -D jsdom @testing-library/react @testing-library/jest-dom vitest
npx vitest run --environment jsdom
```
