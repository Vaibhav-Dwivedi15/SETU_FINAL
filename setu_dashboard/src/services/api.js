// SETU Dashboard — Backend integration layer
//
// Real GET /incidents polling, with graceful fallback to mock data
// (src/data/incidents.js) if the backend isn't reachable — so the
// dashboard never breaks during a demo.
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

// `import.meta.env` only exists under Vite; the guard lets the same module be
// imported by the node contract test (tests/contract.test.mjs).
const ENV = import.meta.env || {};
const BACKEND_URL = ENV.VITE_BACKEND_URL || "http://localhost:8000";
const POLL_INTERVAL_MS = 5000;

// Per the role brief (Section 6): only verified responders should see
// this dashboard; it's gated by X-API-Key on the backend. Read from env,
// never hardcoded.
const API_KEY = ENV.VITE_API_KEY || "";

function authHeaders() {
  return API_KEY ? { "X-API-Key": API_KEY } : {};
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
  const response = await fetch(`${BACKEND_URL}/incidents`, {
    headers: authHeaders(),
    signal: AbortSignal.timeout(4000),
  });
  if (!response.ok) throw new Error(`Backend returned ${response.status}`);
  const data = await response.json();
  return Array.isArray(data) ? data.map(normalizeIncident) : [];
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
  const response = await fetch(`${BACKEND_URL}/responders`, {
    headers: authHeaders(),
    signal: AbortSignal.timeout(4000),
  });
  if (!response.ok) throw new Error(`Backend returned ${response.status}`);
  const data = await response.json();
  return Array.isArray(data) ? data.map(normalizeResponder) : [];
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
 * GET /incidents/{id}/responses — community members who responded to
 * this incident from the mobile app (Phase 3). Responder-API-key gated.
 *
 * Returns [] rather than throwing when the endpoint isn't available, so
 * an older backend deployment degrades to "no responses yet" instead of
 * breaking the whole detail drawer.
 */
export async function fetchIncidentResponses(incidentId) {
  try {
    const response = await fetch(`${BACKEND_URL}/incidents/${incidentId}/responses`, {
      headers: authHeaders(),
      signal: AbortSignal.timeout(4000),
    });
    if (!response.ok) return [];
    const data = await response.json();
    if (!Array.isArray(data)) return [];
    return data.map((r) => ({
      id: r.id,
      senderId: r.sender_id,
      responseType: r.response_type,
      responseLabel: RESPONSE_TYPE_LABEL[r.response_type] || r.response_type,
      createdAt: r.created_at,
      updatedAt: r.updated_at,
    }));
  } catch {
    return [];
  }
}

/**
 * GET /incidents/{id}/history — the backend's IncidentAuditLog trail
 * (CREATED / MERGED / CLOSED entries). Same degrade-to-empty behavior.
 */
export async function fetchIncidentHistory(incidentId) {
  try {
    const response = await fetch(`${BACKEND_URL}/incidents/${incidentId}/history`, {
      headers: authHeaders(),
      signal: AbortSignal.timeout(4000),
    });
    if (!response.ok) return [];
    const data = await response.json();
    if (!Array.isArray(data)) return [];
    return data.map((h) => ({
      id: h.id,
      action: h.action,
      packetId: h.packet_id || null,
      detail: h.detail || null,
      createdAt: h.created_at,
    }));
  } catch {
    return [];
  }
}

/**
 * GET /incidents/{id}/government-notifications — the backend's
 * GovernmentNotificationLog for this incident (Phase 2 adapter output).
 *
 * isMock is passed through as a first-class field, NOT inferred from the
 * adapter name string here — the backend decides it, and the UI renders
 * an unmissable "simulated" marker from it. See
 * Backend/app/routers/government.py on why that marker must stay.
 *
 * Degrades to [] rather than throwing, same as the other Phase 3/4
 * fetchers, so an older backend deployment shows an honest empty state
 * instead of breaking the drawer.
 */
export async function fetchIncidentGovernmentNotifications(incidentId) {
  try {
    const response = await fetch(`${BACKEND_URL}/incidents/${incidentId}/government-notifications`, {
      headers: authHeaders(),
      signal: AbortSignal.timeout(4000),
    });
    if (!response.ok) return [];
    const data = await response.json();
    if (!Array.isArray(data)) return [];
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
  } catch {
    return [];
  }
}

/**
 * GET /government/adapter-status — which adapter is live and whether
 * it's the mock. Used to render a global "simulated" indicator.
 */
export async function fetchGovernmentAdapterStatus() {
  try {
    const response = await fetch(`${BACKEND_URL}/government/adapter-status`, {
      headers: authHeaders(),
      signal: AbortSignal.timeout(4000),
    });
    if (!response.ok) return null;
    const g = await response.json();
    return {
      adapterName: g.adapter_name,
      isMock: Boolean(g.is_mock),
      totalNotifications: g.total_notifications,
      detail: g.detail,
    };
  } catch {
    return null;
  }
}

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
  return () => { cancelled = true; if (timeoutId) clearTimeout(timeoutId); };
}

/**
 * POST /incidents/{id}/resolve — confirmed real, API-key gated, and
 * idempotent (see Backend/app/routers/incidents.py). This is the
 * dashboard's administrative resolve path, deliberately PARALLEL to the
 * mesh-native signed termination packet, not a replacement for it — a
 * private Ed25519 signing key can't live in a browser.
 */
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
