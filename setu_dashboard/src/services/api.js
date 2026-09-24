// SETU Dashboard — Backend integration layer
//
// Real GET /incidents polling. Block 3: NO silent fallback to mock data -- a failed request is
// reported as a failure; sample data exists only in an explicit DEMO MODE build.
//
// ============================================================
// FIELD MAPPING BUGS FIXED (Phase 4, Aug 2026)
// ============================================================
// The previous normalizeIncident() read fields the backend never sends.
// Verified against Backend/app/models/incident.py + schemas/incident.py:
//
//   raw.priority      -> DOESN'T EXIST. The backend has TWO separate
//                        priority columns, deliberately never conflated:
//                        sender_priority (string: low/medium/high/critical,
//                        what the reporter declared) and ai_priority
//                        (float 1.0-5.0, what the AI assessed). Reading
//                        raw.priority meant EVERY live incident silently
//                        fell through to the "Medium" default — so the
//                        entire dashboard's color-coding, sorting, sound
//                        alerts and Critical popups were wrong against
//                        real backend data. This was invisible in mock
//                        mode because the mock data has a `priority` field.
//   raw.timestamp     -> DOESN'T EXIST on IncidentOut. It's created_at.
//   raw.emergency_id  -> DOESN'T EXIST on IncidentOut. Incident.id is the
//                        real identifier the other endpoints key off.
//   raw.city          -> DOESN'T EXIST anywhere in the backend. There is
//                        no reverse-geocoding server-side. Now derived
//                        client-side from coordinates (nearest known
//                        city, see deriveCity) and clearly falls back to
//                        a coordinate string rather than inventing a
//                        place name.
//
// ai_priority (float) is mapped to the same Critical/High/Medium/Low
// vocabulary the UI already speaks, and kept ALONGSIDE sender_priority
// rather than overwriting it — both are surfaced in the detail drawer,
// per the backend model's own "never let one silently overwrite the
// other" instruction.

import { BACKEND_URL, CONFIG_ERROR, DEMO_MODE, POLL_INTERVAL_MS } from "../config.js";
import { demoIncidents } from "../demo/demoData.js";

// ============================================================
// AUTHENTICATION (Block 3)
// ============================================================
// There is NO credential in this bundle. An operator types the responder key into the login
// screen; POST /auth/responder-login exchanges it for a short-lived, signed bearer token. The
// key itself is never stored; the token lives in sessionStorage (this tab only, gone when the
// tab closes) and expires server-side. A 401 from any call clears it and returns the app to the
// login screen. (sessionStorage is readable by injected script: the strict CSP in vercel.json
// is what protects it -- see docs/security/BLOCK3_FINAL_SECURITY_VALIDATION.md.)

const SESSION_KEY = "setu.session.v1";

export class ApiError extends Error {
  constructor(message, status = 0) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

function readSession() {
  try {
    const raw = sessionStorage.getItem(SESSION_KEY);
    if (!raw) return null;
    const session = JSON.parse(raw);
    if (!session.token || !(session.expiresAt > Date.now())) {
      sessionStorage.removeItem(SESSION_KEY);
      return null;
    }
    return session;
  } catch {
    return null;
  }
}

export function hasSession() {
  return readSession() !== null;
}

export function logout() {
  try { sessionStorage.removeItem(SESSION_KEY); } catch { /* storage unavailable */ }
}

function expireSession() {
  logout();
  if (typeof window !== "undefined") window.dispatchEvent(new Event("setu:auth-expired"));
}

export async function loginWithKey(key) {
  if (CONFIG_ERROR) throw new ApiError(CONFIG_ERROR);
  let response;
  try {
    response = await fetch(`${BACKEND_URL}/auth/responder-login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key }),
      signal: AbortSignal.timeout(8000),
    });
  } catch {
    throw new ApiError("Could not reach the backend.");
  }
  if (response.status === 401) throw new ApiError("Invalid credentials.", 401);
  if (response.status === 429) throw new ApiError("Too many attempts. Wait a minute and try again.", 429);
  if (response.status === 503) throw new ApiError("Login is not configured on the server (SESSION_SECRET).", 503);
  if (!response.ok) throw new ApiError(`Login failed (HTTP ${response.status}).`, response.status);
  const data = await response.json();
  if (!data.access_token) throw new ApiError("Login response was malformed.");
  try {
    sessionStorage.setItem(SESSION_KEY, JSON.stringify({
      token: data.access_token,
      expiresAt: Date.now() + Math.max(0, (data.expires_in || 0) - 30) * 1000,
    }));
  } catch {
    throw new ApiError("This browser blocked session storage.");
  }
}

/** Authenticated fetch: adds the bearer token, maps failures to ApiError, expires the session on 401. */
async function apiFetch(path, options = {}) {
  if (CONFIG_ERROR) throw new ApiError(CONFIG_ERROR);
  const session = readSession();
  if (!session) {
    expireSession();
    throw new ApiError("Not signed in.", 401);
  }
  let response;
  try {
    response = await fetch(`${BACKEND_URL}${path}`, {
      ...options,
      headers: { ...(options.headers || {}), Authorization: `Bearer ${session.token}` },
      signal: options.signal || AbortSignal.timeout(6000),
    });
  } catch {
    throw new ApiError("Backend unreachable.");
  }
  if (response.status === 401) {
    expireSession();
    throw new ApiError("Session expired. Sign in again.", 401);
  }
  if (!response.ok) throw new ApiError(`Backend returned ${response.status}.`, response.status);
  return response;
}

// Known city coordinates, used to give live backend incidents a
// human-readable place label. The backend genuinely has no city field —
// this is a display convenience, NOT data from the mesh. Anything
// further than ~80km from a known city shows coordinates instead of
// guessing a wrong city name.
const KNOWN_CITIES = [
  { name: "Prayagraj", lat: 25.4358, lng: 81.8463 },
  { name: "Lucknow", lat: 26.8467, lng: 80.9462 },
  { name: "Varanasi", lat: 25.3176, lng: 82.9739 },
  { name: "Kanpur", lat: 26.4499, lng: 80.3319 },
  { name: "Agra", lat: 27.1767, lng: 78.0081 },
  { name: "Delhi", lat: 28.6139, lng: 77.2090 },
  { name: "Noida", lat: 28.5355, lng: 77.3910 },
];

const CITY_MATCH_RADIUS_KM = 80;

function haversineKm(lat1, lon1, lat2, lon2) {
  const toRad = (d) => (d * Math.PI) / 180;
  const R = 6371;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.asin(Math.sqrt(a));
}

function deriveCity(lat, lng) {
  if (typeof lat !== "number" || typeof lng !== "number") return "Unknown";
  // (0,0) is the frozen spec's explicit "GPS unavailable" fallback —
  // label it honestly instead of pretending it's a real location.
  if (lat === 0 && lng === 0) return "Location unavailable";

  let nearest = null;
  let nearestDistance = Infinity;
  for (const city of KNOWN_CITIES) {
    const d = haversineKm(lat, lng, city.lat, city.lng);
    if (d < nearestDistance) {
      nearestDistance = d;
      nearest = city;
    }
  }
  if (nearest && nearestDistance <= CITY_MATCH_RADIUS_KM) return nearest.name;
  return `${lat.toFixed(2)}, ${lng.toFixed(2)}`;
}

// ai_priority is a 1.0-5.0 float per the Incident model. Mapped onto the
// same four-level vocabulary the UI already uses everywhere.
function aiPriorityToLabel(value) {
  if (typeof value !== "number") return null;
  if (value >= 4.5) return "Critical";
  if (value >= 3.5) return "High";
  if (value >= 2.0) return "Medium";
  return "Low";
}

const SENDER_PRIORITY_LABEL = {
  low: "Low",
  medium: "Medium",
  high: "High",
  critical: "Critical",
};

export function normalizeIncident(raw) {
  const lat = raw.latitude ?? raw.lat;
  const lng = raw.longitude ?? raw.lng;

  const senderPriority =
    SENDER_PRIORITY_LABEL[String(raw.sender_priority || "").toLowerCase()] || null;
  const aiPriority = aiPriorityToLabel(raw.ai_priority);

  // Display priority prefers the AI assessment when available (it's the
  // triage signal responders should act on), falling back to what the
  // reporter declared, then Medium. Both raw values are preserved below
  // so the detail drawer can show them side by side without either
  // having overwritten the other.
  // Block 2: the backend now returns `display_priority` (single authoritative
  // rule, see Backend incident_service.display_priority); the local derivation
  // is kept only as a fallback for older backend deployments.
  const displayPriority =
    SENDER_PRIORITY_LABEL[String(raw.display_priority || "").toLowerCase()] ||
    aiPriority || senderPriority || "Medium";

  return {
    id: raw.id,
    type: raw.incident_type || raw.type || "Unknown",
    // Preserved separately from `type` so categorizeIncident() can match
    // on the backend's real enum value even if `type` gets prettified.
    rawIncidentType: raw.incident_type || raw.type || "",
    aiIncidentType: raw.ai_incident_type || null,
    aiIncidentConfidence: raw.ai_incident_confidence ?? null,
    aiIncidentExplanation: raw.ai_incident_explanation || null,
    aiUrgency: raw.ai_urgency ?? null,
    aiUrgencyConfidence: raw.ai_urgency_confidence ?? null,
    aiUrgencyExplanation: raw.ai_urgency_explanation || null,

    city: deriveCity(lat, lng),
    priority: displayPriority,
    senderPriority,
    aiPriority,
    aiPriorityValue: typeof raw.ai_priority === "number" ? raw.ai_priority : null,

    lat,
    lng,
    // Backend IncidentStatus is "OPEN"/"CLOSED"; the dashboard speaks
    // "active"/"closed" throughout. Normalize here so no component has
    // to know both vocabularies.
    status: String(raw.status || "").toUpperCase() === "CLOSED" ? "closed" : "active",
    reportedAt: raw.created_at || raw.timestamp || new Date().toISOString(),
    closedAt: raw.closed_at || null,

    // No matched_cluster_id on IncidentOut — the backend already merges
    // duplicates server-side into a single Incident row, so each row IS
    // one real-world incident. Cluster key falls back to the id, making
    // the Merged view a no-op against live data (correct: there's
    // nothing left to merge) while still working on mock data.
    clusterKey: raw.matched_cluster_id || raw.id,

    hopCount: typeof raw.hop_count === "number" ? raw.hop_count : raw.hopCount,
    relayPath: raw.relay_path || null,
    // Independent reports merged into this incident (authoritative, from the backend).
    reportCount: typeof raw.report_count === "number" ? raw.report_count : 1,
    updatedAt: raw.updated_at || null,
  };
}

export async function fetchIncidents() {
  const response = await apiFetch("/incidents");
  const data = await response.json();
  if (!Array.isArray(data)) throw new ApiError("Backend returned an unexpected incidents payload.");
  return data.map(normalizeIncident);
}

function normalizeResponder(raw) {
  return {
    id: raw.id ?? raw.public_key,
    name: raw.name || "Unnamed Responder",
    organization: raw.organization || "Independent",
    publicKey: raw.public_key,
  };
}

export async function fetchResponders() {
  const response = await apiFetch("/responders");
  const data = await response.json();
  if (!Array.isArray(data)) throw new ApiError("Backend returned an unexpected responders payload.");
  return data.map(normalizeResponder);
}

// ============================================================
// Phase 3 / Phase 4 additions
// ============================================================

const RESPONSE_TYPE_LABEL = {
  NEARBY: "I'm nearby",
  CAN_HELP: "I can help",
  ALREADY_RESPONDING: "Already responding",
  CALLED_EMERGENCY_SERVICES: "Called emergency services",
  NAVIGATING: "Navigating to location",
};

/**
 * GET /incidents/{id}/responses — community members who responded to this incident from the
 * mobile app. Responder-gated. Block 3: a failed request THROWS (ApiError) instead of returning
 * [] -- "the request failed" must never be displayed as "nobody responded".
 */
export async function fetchIncidentResponses(incidentId) {
  const response = await apiFetch(`/incidents/${encodeURIComponent(incidentId)}/responses`);
  const data = await response.json();
  if (!Array.isArray(data)) throw new ApiError("Unexpected responses payload.");
  return data.map((r) => ({
    id: r.id,
    senderId: r.sender_id,
    responseType: r.response_type,
    responseLabel: RESPONSE_TYPE_LABEL[r.response_type] || r.response_type,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  }));
}

/** GET /incidents/{id}/history — IncidentAuditLog trail. Throws on failure (see above). */
export async function fetchIncidentHistory(incidentId) {
  const response = await apiFetch(`/incidents/${encodeURIComponent(incidentId)}/history`);
  const data = await response.json();
  if (!Array.isArray(data)) throw new ApiError("Unexpected history payload.");
  return data.map((h) => ({
    id: h.id,
    action: h.action,
    packetId: h.packet_id || null,
    detail: h.detail || null,
    createdAt: h.created_at,
  }));
}

/**
 * GET /incidents/{id}/government-notifications — GovernmentNotificationLog for this incident.
 * isMock is passed through as a first-class field (the backend decides it; the UI renders an
 * unmissable "simulated" marker from it). Throws on failure.
 */
export async function fetchIncidentGovernmentNotifications(incidentId) {
  const response = await apiFetch(`/incidents/${encodeURIComponent(incidentId)}/government-notifications`);
  const data = await response.json();
  if (!Array.isArray(data)) throw new ApiError("Unexpected notifications payload.");
  return data.map((g) => ({
    id: g.id,
    incidentId: g.incident_id,
    adapterName: g.adapter_name,
    isMock: Boolean(g.is_mock),
    status: g.status,
    referenceId: g.reference_id || null,
    requestPayload: g.request_payload || null,
    responseDetail: g.response_detail || null,
    createdAt: g.created_at,
  }));
}

/** GET /government/adapter-status — which adapter is live and whether it is the mock. Throws on failure. */
export async function fetchGovernmentAdapterStatus() {
  const response = await apiFetch("/government/adapter-status");
  const g = await response.json();
  return {
    adapterName: g.adapter_name,
    isMock: Boolean(g.is_mock),
    totalNotifications: g.total_notifications,
    detail: g.detail,
  };
}

/**
 * Polls GET /incidents.
 *   onUpdate(incidents)      every successful poll
 *   onError(ApiError|Error)  every FAILED poll (not just the first) -- a failure is shown as a
 *                            failure. Real data is never replaced with fake data.
 * DEMO MODE ONLY (explicit VITE_DEMO_MODE=true build): the sample incidents are delivered once
 * through onUpdate and the network is not used at all.
 */
export function startIncidentPolling(onUpdate, onError, intervalMs = POLL_INTERVAL_MS) {
  if (DEMO_MODE) {
    onUpdate(demoIncidents);
    return () => {};
  }
  let cancelled = false;
  let timeoutId = null;

  async function poll() {
    if (cancelled) return;
    try {
      onUpdate(await fetchIncidents());
    } catch (err) {
      if (!cancelled) onError(err);
      if (err instanceof ApiError && err.status === 401) return; // signed out: stop polling until re-login
    }
    if (!cancelled) timeoutId = setTimeout(poll, intervalMs);
  }

  poll();
  return () => { cancelled = true; if (timeoutId) clearTimeout(timeoutId); };
}

/**
 * POST /incidents/{id}/resolve — responder-gated and idempotent. Returns true ONLY when the
 * backend confirmed; otherwise throws, so the UI never shows an incident as closed that the
 * backend did not close. Parallel to (not a replacement for) the signed mesh termination.
 */
export async function resolveIncidentOnBackend(incidentId) {
  if (DEMO_MODE) return true;
  await apiFetch(`/incidents/${encodeURIComponent(incidentId)}/resolve`, { method: "POST" });
  return true;
}
