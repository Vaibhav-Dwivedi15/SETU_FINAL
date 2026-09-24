// Mock/fallback data — used when the backend isn't reachable (see
// src/services/api.js). "status" distinguishes active/closed.
// "hopCount" mirrors the mesh packet's real hop_count field so the map
// popup can show a relay-hop count even in offline/mock mode, ahead of
// the backend actually sending it. "reportedAt" is a real ISO timestamp
// (previously there was no time field at all — incident.time rendered
// as nothing) staggered across the last few hours so the new live
// "time ago" display has something realistic to show.
const now = Date.now();

const incidents = [
  {
    id: 1,
    type: "Medical",
    city: "Prayagraj",
    priority: "High",
    lat: 25.4358,
    lng: 81.8463,
    status: "active",
    hopCount: 3,
    reportedAt: new Date(now - 6 * 60 * 1000).toISOString(), // 6 min ago
  },
  {
    id: 2,
    type: "Fire",
    city: "Lucknow",
    priority: "Medium",
    lat: 26.8467,
    lng: 80.9462,
    status: "active",
    hopCount: 1,
    reportedAt: new Date(now - 42 * 60 * 1000).toISOString(), // 42 min ago
  },
  {
    id: 3,
    type: "Flood",
    city: "Varanasi",
    priority: "Critical",
    lat: 25.3176,
    lng: 82.9739,
    status: "active",
    hopCount: 4,
    reportedAt: new Date(now - 2 * 60 * 1000).toISOString(), // 2 min ago
  },
  {
    id: 4,
    type: "Medical",
    city: "Kanpur",
    priority: "Low",
    lat: 26.4499,
    lng: 80.3319,
    status: "closed",
    hopCount: 2,
    reportedAt: new Date(now - 3 * 60 * 60 * 1000).toISOString(), // 3h ago
  },
];

export default incidents;

// Unique marker: tests/security.test.mjs asserts it is ABSENT from every non-demo build.
export const DEMO_MARKER = "SETU_DEMO_DATASET_MARKER";
