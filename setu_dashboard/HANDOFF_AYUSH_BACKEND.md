# SETU Dashboard — Integration Handoff for Ayush (Backend Lead)

What the dashboard actually calls on your API, field-by-field, plus one
endpoint it expects that doesn't exist yet. Read section 3 first — it's
the one that needs your decision before anything else here matters.

---

## 1. Endpoints the dashboard calls today

All from `src/services/api.js`. All send `X-API-Key: <VITE_API_KEY>`
when that env var is set (see `.env.example`).

### `GET /incidents`
Polled every N seconds (default 5s, user-configurable in Settings).
Expected response: a JSON array. Each item is normalized by
`normalizeIncident()` in `api.js`, which reads (falling back gracefully
if a field is absent):

| Dashboard expects | Your field (best guess — confirm) |
|---|---|
| `emergency_id` or `id` | your `Incident.id` / `emergency_id` |
| `incident_type` or `type` | your `Incident.incident_type` |
| `city` or `location_name` | — |
| `priority` (lowercase: low/medium/high/critical) | your `Incident.priority` |
| `latitude`, `longitude` | — |
| `status` | — |
| `timestamp` | ISO string, used for live "time ago" display |
| `matched_cluster_id` | from the AI service's dedup output, if you're passing it through — falls back to a type+city heuristic if absent |
| `hop_count` | from the packet's real `hop_count` field — surfaced in the map popup as "traveled through N phones, zero internet" |

**Please diff this table against your actual current `IncidentOut`
schema** — this was last confirmed against an earlier version of your
backend and may have drifted. Field-name mismatches fail silently on
the dashboard side (missing fields just show as "Unknown" or blank, no
error thrown) so a manual check is worth doing rather than assuming.

### `GET /responders`
Used by the Teams page. Expected: array of
`{ id, public_key, name, organization }`. Requires the responder (or
admin) API key — matches your existing RBAC.

### `POST /incidents/{id}/resolve` — **does not exist on your backend yet**
See section 3.

## 2. CORS

The dashboard is a browser app calling your API cross-origin. Your
backend's `CORS_ALLOWED_ORIGINS_RAW` env var needs to include wherever
this dashboard is actually served from (e.g.
`http://localhost:5173` for local dev, plus whatever the real deployed
origin is once you have one). Without it, every request fails at the
browser level with a CORS error — this looks identical to "backend is
down" from the dashboard's side (falls back to mock data, "Offline"
badge), so if incidents aren't loading and you can `curl` the endpoint
fine yourself, check this first.

## 3. The resolve-endpoint gap — needs your input

The dashboard's "Mark Resolved" button calls:
```
POST /incidents/{id}/resolve
Headers: X-API-Key: <responder or admin key>
```
expecting a 2xx response. Your backend currently closes incidents via a
signed termination packet through `/ingest`, not a REST call — see the
Team Lead handoff doc for the full context on why a browser dashboard
can't just send a signed packet the same way a mesh device can.

**If you add this endpoint**, a reasonable spec that matches what the
dashboard already assumes:

```python
@router.post("/incidents/{incident_id}/resolve")
def resolve_incident(
    incident_id: int,
    db: Session = Depends(get_db),
    _: None = Depends(verify_responder_api_key),  # same auth as your other responder routes
):
    incident = db.query(Incident).filter(Incident.id == incident_id).first()
    if not incident:
        raise HTTPException(status_code=404, detail="Incident not found")
    incident.status = "closed"
    db.commit()
    # optionally: audit_service.record_audit_event(..., action="resolve_incident_via_dashboard", ...)
    return {"status": "closed", "incident_id": incident_id}
```

This trusts the dashboard's existing API-key auth rather than requiring
a signature — a deliberately different (lighter) trust model than the
mesh's Ed25519 packets, since there's no responder private key
available in a browser context. Worth an audit-log entry specifically
noting "resolved via dashboard" vs "resolved via signed termination
packet" if you want to keep that distinction visible later.

Until this exists, the dashboard's resolve button updates the UI
optimistically and fails silently against your backend (logged to
console, not shown to the user) — doesn't block anything, but also
doesn't actually close anything on your side yet.

## 4. Quick integration test

Once `VITE_BACKEND_URL` and `VITE_API_KEY` are set in the dashboard's
`.env` and your backend is running with matching CORS config:

```bash
npm run dev
```

Sidebar should show "Live (Backend Connected)" instead of "Offline
(Mock Data)", and "Last synced Xs ago" should be advancing. If it still
says Offline, check in this order: (1) backend actually reachable at
that URL, (2) CORS origin configured, (3) API key matches what your
backend expects, (4) `GET /incidents` returns a 2xx with a JSON array
(even an empty one — a non-array response also triggers the fallback).
