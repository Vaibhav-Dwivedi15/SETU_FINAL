// SETU Dashboard — Backend integration layer
//
// This is genuinely new — the previous version only ever displayed
// static mock data (src/data/incidents.js) with no connection to the
// backend at all. This adds real GET /incidents polling, while
// gracefully falling back to the mock data if the backend isn't
// reachable — so the dashboard never breaks (e.g. for a demo) even
// before Ayush's backend is live.

const BACKEND_URL = import.meta.env.VITE_BACKEND_URL || "http://localhost:8000";
const POLL_INTERVAL_MS = 5000;

// Per the role brief (Section 6): "Only verified responders should ever
// see this dashboard. It's gated by API-key auth on the backend
// (X-API-Key header)." This reads the key from the environment so it's
// never hardcoded in source. If VITE_API_KEY isn't set, requests still go
// out (so local dev against a not-yet-auth-enforcing backend keeps
// working) but Ayush's backend should reject them once auth is enforced
// there — this is the dashboard's half of that contract, not the backend
// half.
const API_KEY = import.meta.env.VITE_API_KEY || "";

function authHeaders() {
  return API_KEY ? { "X-API-Key": API_KEY } : {};
}

// Normalizes a backend incident (snake_case, lowercase priority — see
// the frozen packet spec) into the shape this dashboard's components
// already expect (id, type, city, priority as Capitalized string,
// lat/lng, status). Keeping this in one place means the rest of the
// dashboard doesn't need to know about the backend's exact field names.
function normalizeIncident(raw) {
  const priorityMap = { low: "Low", medium: "Medium", high: "High", critical: "Critical" };
  return {
    id: raw.emergency_id || raw.id,
    type: raw.incident_type || raw.type || "Unknown",
    city: raw.city || raw.location_name || "Unknown",
    priority: priorityMap[(raw.priority || "").toLowerCase()] || raw.priority || "Medium",
    lat: raw.latitude ?? raw.lat,
    lng: raw.longitude ?? raw.lng,
    status: raw.status || "active",
    // reportedAt is the real, unformatted timestamp — components format
    // it live via utils/timeAgo.js. Previously this field was pre-baked
    // into a locale time string here, which meant it could never update
    // ("2m ago" -> "10m ago") without a fresh fetch, and mock data had
    // no timestamp at all.
    reportedAt: raw.timestamp || new Date().toISOString(),
    // clusterKey groups reports of the same real-world incident together
    // for the Merged view. Prefers the AI service's real duplicate-
    // detection result (matched_cluster_id) once the backend sends it;
    // falls back to a type+city heuristic until then — good enough for
    // demo purposes, should be swapped for the real field once Ayush's
    // /incidents response includes it.
    clusterKey: raw.matched_cluster_id || `${raw.incident_type || raw.type}-${raw.city || raw.location_name}`,
    // hop_count is a real field on the frozen packet spec (Section 3).
    // Surfacing it is called out in the role brief as a strong demo
    // detail ("this message traveled through 4 phones with zero
    // internet"). Defaults to undefined if the backend hasn't started
    // sending it yet — MapView only renders the line when it's a number.
    hopCount: typeof raw.hop_count === "number" ? raw.hop_count : raw.hopCount,
  };
}

export async function fetchIncidents() {
  const response = await fetch(`${BACKEND_URL}/incidents`, {
    headers: authHeaders(),
    signal: AbortSignal.timeout(4000),
  });
  if (!response.ok) throw new Error(`Backend returned ${response.status}`);
  const data = await response.json();
  return Array.isArray(data) ? data.map(normalizeIncident) : [];
}

// Normalizes a backend responder (public_key, name, organization) into
// the shape the Teams page expects. Kept separate from normalizeIncident
// since the two have no fields in common.
function normalizeResponder(raw) {
  return {
    id: raw.id ?? raw.public_key,
    name: raw.name || "Unnamed Responder",
    organization: raw.organization || "Independent",
    publicKey: raw.public_key,
  };
}

// GET /responders — requires the responder API key (see authHeaders()).
// Used by the Teams page. Throws on failure so the caller can fall back
// to mock data, same pattern as fetchIncidents.
export async function fetchResponders() {
  const response = await fetch(`${BACKEND_URL}/responders`, {
    headers: authHeaders(),
    signal: AbortSignal.timeout(4000),
  });
  if (!response.ok) throw new Error(`Backend returned ${response.status}`);
  const data = await response.json();
  return Array.isArray(data) ? data.map(normalizeResponder) : [];
}

// Polls fetchIncidents() every intervalMs. onUpdate is called with fresh
// data on success; onFallback is called ONCE the first time a fetch
// fails, so the caller can seed itself with mock data and keep the
// dashboard usable instead of showing an empty/broken screen.
// intervalMs is now caller-configurable (see Settings page) — previously
// hardcoded to a fixed 5s with no way to change it short of editing code.
export function startIncidentPolling(onUpdate, onFallback, intervalMs = POLL_INTERVAL_MS) {
  let fallbackTriggered = false;
  let cancelled = false;
  let timeoutId = null;

  async function poll() {
    if (cancelled) return;
    try {
      const incidents = await fetchIncidents();
      onUpdate(incidents);
    } catch (err) {
      if (!fallbackTriggered) {
        fallbackTriggered = true;
        console.warn("SETU dashboard: backend unreachable, using mock data. Reason:", err.message);
        onFallback();
      }
    }
    if (!cancelled) timeoutId = setTimeout(poll, intervalMs);
  }

  poll();
  return () => { cancelled = true; if (timeoutId) clearTimeout(timeoutId); }; // returns a cleanup function
}

// Termination-trigger stub — marks an incident resolved on the backend.
// Endpoint name is a best guess (Ayush's backend isn't finalized yet);
// this needs to be confirmed against his actual route once it exists.
// Until then it fails silently and the UI still updates optimistically
// (see App.jsx), so the demo isn't blocked on backend availability.
export async function resolveIncidentOnBackend(incidentId) {
  try {
    const response = await fetch(`${BACKEND_URL}/incidents/${incidentId}/resolve`, {
      method: "POST",
      headers: authHeaders(),
      signal: AbortSignal.timeout(4000),
    });
    return response.ok;
  } catch (err) {
    console.warn("SETU dashboard: could not reach backend to resolve incident. Reason:", err.message);
    return false;
  }
}