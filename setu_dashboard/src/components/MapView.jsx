import { MapContainer, TileLayer, Marker, Popup, Circle } from "react-leaflet";
import "leaflet/dist/leaflet.css";
import { divIcon } from "leaflet";
import { useTheme } from "../context/ThemeContext";
import { ActionIcons } from "../icons";

// =====================================================
// SETU Dashboard — Live Map (v2)
// =====================================================
//
// Redesign brief section 10 asked for: incident clusters, individual
// incidents, approximate affected areas, responder presence, mesh
// activity, internet exit nodes, professional (non-emoji) markers,
// priority+category communication, and a critical pulse.
//
// HONEST SCOPE for this pass:
//   - Professional markers: DONE. Replaced the old external hotlinked
//     PNG pin images with self-contained inline SVG (no external asset
//     dependency at all now, and no emoji).
//   - Priority communication: DONE — color-coded exactly as before.
//   - Critical pulse: DONE — a CSS keyframe ring, only on Critical
//     markers, restrained (not flashing/bouncing).
//   - Approximate affected area: DONE — a soft translucent Circle
//     overlay around each active incident (radius is a fixed visual
//     approximation, not derived from any real blast/flood-radius
//     model — that data doesn't exist yet).
//   - Incident clustering (grouping many nearby markers into one
//     cluster bubble at low zoom): NOT done this pass — would need a
//     new dependency (e.g. react-leaflet-cluster), not currently
//     installed. Flagged, not guessed at.
//   - Responder presence / internet exit-node markers: NOT done —
//     there is no data model for responder location or per-incident
//     exit-node identity anywhere in this app yet. Fabricating markers
//     for data that doesn't exist would be exactly the kind of
//     overclaim this project's own documentation explicitly rejects.
//     Flagged as a real gap, not silently faked.

const PRIORITY_COLOR = {
  Critical: "#ef4444",
  High: "#f97316",
  Medium: "#eab308",
  Low: "#22c55e",
};
const DEFAULT_COLOR = "#94a3b8";

function priorityColor(priority) {
  return PRIORITY_COLOR[priority] || DEFAULT_COLOR;
}

/**
 * Builds a self-contained SVG marker as a Leaflet divIcon -- no external
 * image URL, no emoji. Critical incidents get an extra pulse-ring div
 * (CSS-animated, see map-v2.css) layered behind the marker dot.
 */
function buildMarkerIcon(priority) {
  const color = priorityColor(priority);
  const isCritical = priority === "Critical";

  const html = `
    <div class="setu-map-marker ${isCritical ? "setu-map-marker-critical" : ""}">
      ${isCritical ? '<span class="setu-map-marker-pulse"></span>' : ""}
      <svg width="26" height="34" viewBox="0 0 26 34" xmlns="http://www.w3.org/2000/svg">
        <path d="M13 0C5.8 0 0 5.8 0 13c0 9.75 13 21 13 21s13-11.25 13-21C26 5.8 20.2 0 13 0z" fill="${color}" stroke="rgba(0,0,0,.25)" stroke-width="1"/>
        <circle cx="13" cy="13" r="5" fill="white" fill-opacity="0.9"/>
      </svg>
    </div>
  `;

  return divIcon({
    html,
    className: "setu-map-marker-wrapper",
    iconSize: [26, 34],
    iconAnchor: [13, 34],
    popupAnchor: [0, -32],
  });
}

const MARKER_ICON_CACHE = {};
function getMarkerIcon(priority) {
  if (!MARKER_ICON_CACHE[priority]) {
    MARKER_ICON_CACHE[priority] = buildMarkerIcon(priority);
  }
  return MARKER_ICON_CACHE[priority];
}

// Fixed visual radius for the "approximate affected area" circle --
// deliberately NOT derived from any real hazard-radius model (no such
// data exists), purely a soft visual cue that something happened
// roughly here, not a precise boundary claim.
const AFFECTED_AREA_RADIUS_M = 350;

function MapView({ incidents, onSelectIncident, tall = false }) {
  const { theme } = useTheme();
  const tileUrl = theme === "light"
    ? "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png"
    : "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png";

  return (
    <div className={`map-container ${tall ? "map-container-tall" : ""}`}>
      <MapContainer
        center={[25.4358, 81.8463]}
        zoom={6}
        style={{ height: tall ? "100%" : "400px", width: "100%" }}
        scrollWheelZoom
      >
        <TileLayer
          attribution='&copy; OpenStreetMap, &copy; CARTO'
          url={tileUrl}
        />

        {incidents.map((incident) => {
          const color = priorityColor(incident.priority);
          const isClosed = incident.status === "closed";
          return (
            <div key={incident.id}>
              {!isClosed && (
                <Circle
                  center={[incident.lat, incident.lng]}
                  radius={AFFECTED_AREA_RADIUS_M}
                  pathOptions={{ color, fillColor: color, fillOpacity: 0.08, weight: 1, opacity: 0.3 }}
                />
              )}
              <Marker
                position={[incident.lat, incident.lng]}
                icon={getMarkerIcon(incident.priority)}
                eventHandlers={
                  onSelectIncident ? { click: () => onSelectIncident(incident) } : undefined
                }
              >
                <Popup>
                  <strong>{incident.type}</strong>
                  <br />
                  {incident.city}
                  <br />
                  {incident.priority}
                  <br />
                  {typeof incident.hopCount === "number" && (
                    <>
                      <span style={{ display: "inline-flex", alignItems: "center", gap: 4 }}>
                        <ActionIcons.refresh className="ds-icon-sm" aria-hidden="true" />
                        {incident.hopCount} hop{incident.hopCount === 1 ? "" : "s"} — no internet needed
                      </span>
                      <br />
                    </>
                  )}
                  <span style={{ color: isClosed ? "#2FA85C" : "#E14545" }}>
                    {isClosed ? "● Resolved" : "● Active"}
                  </span>
                </Popup>
              </Marker>
            </div>
          );
        })}
      </MapContainer>

      <div className="map-legend">
        <span><i className="dot dot-critical" /> Critical</span>
        <span><i className="dot dot-high" /> High</span>
        <span><i className="dot dot-medium" /> Medium</span>
        <span><i className="dot dot-low" /> Low</span>
      </div>
    </div>
  );
}

export default MapView;
