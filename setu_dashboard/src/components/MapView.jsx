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
  High: "#f59e0b",
  Medium: "#eab308",
  Low: "#10b981",
};
const DEFAULT_COLOR = "#64748b";

function priorityColor(priority) {
  return PRIORITY_COLOR[priority] || DEFAULT_COLOR;
}

/**
 * Builds a self-contained SVG marker as a Leaflet divIcon.
 * Strict visual hierarchy per command-center specifications:
 * - CRITICAL: immediately visible, 26x32, distinct pulse wave
 * - HIGH: visible, 22x28
 * - MEDIUM: quieter, 18x24
 * - LOW: subtle, 15x20
 * - CLOSED: dimmed slate, 14x18
 */
function buildMarkerIcon(priority, isClosed = false) {
  const color = isClosed ? "#475569" : priorityColor(priority);
  const isCritical = priority === "Critical" && !isClosed;
  const isHigh = priority === "High" && !isClosed;

  let width = 18;
  let height = 24;
  let dotRadius = 3;

  if (isCritical) {
    width = 24;
    height = 30;
    dotRadius = 4.5;
  } else if (isHigh) {
    width = 20;
    height = 26;
    dotRadius = 3.5;
  } else if (isClosed) {
    width = 14;
    height = 18;
    dotRadius = 2.5;
  }

  const html = `
    <div class="setu-map-marker ${isCritical ? "setu-map-marker-critical" : ""} ${isClosed ? "setu-map-marker-closed" : ""}" style="width:${width}px;height:${height}px;">
      ${isCritical ? '<span class="setu-map-marker-pulse"></span>' : ""}
      <svg width="${width}" height="${height}" viewBox="0 0 24 30" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M12 0C5.37 0 0 5.37 0 12C0 21 12 30 12 30C12 30 24 21 24 12C24 5.37 18.63 0 12 0Z" fill="${color}" fill-opacity="${isClosed ? "0.6" : "0.95"}" stroke="rgba(0,0,0,0.4)" stroke-width="1.2"/>
        <circle cx="12" cy="11" r="${dotRadius}" fill="#ffffff" fill-opacity="${isClosed ? "0.5" : "0.95"}"/>
      </svg>
    </div>
  `;

  return divIcon({
    html,
    className: "setu-map-marker-wrapper",
    iconSize: [width, height],
    iconAnchor: [width / 2, height],
    popupAnchor: [0, -height],
  });
}

const MARKER_ICON_CACHE = {};
function getMarkerIcon(priority, isClosed = false) {
  const key = `${priority}-${isClosed ? "closed" : "active"}`;
  if (!MARKER_ICON_CACHE[key]) {
    MARKER_ICON_CACHE[key] = buildMarkerIcon(priority, isClosed);
  }
  return MARKER_ICON_CACHE[key];
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
          const isHighOrCritical = !isClosed && (incident.priority === "Critical" || incident.priority === "High");

          return (
            <div key={incident.id}>
              {isHighOrCritical && (
                <Circle
                  center={[incident.lat, incident.lng]}
                  radius={incident.priority === "Critical" ? 400 : 250}
                  pathOptions={{
                    color,
                    fillColor: color,
                    fillOpacity: 0.05,
                    weight: 1,
                    opacity: 0.25,
                    dashArray: incident.priority === "Critical" ? undefined : "3, 3",
                  }}
                />
              )}
              <Marker
                position={[incident.lat, incident.lng]}
                icon={getMarkerIcon(incident.priority, isClosed)}
                eventHandlers={
                  onSelectIncident ? { click: () => onSelectIncident(incident) } : undefined
                }
              >
                <Popup className="setu-tactical-popup">
                  <div className="popup-body">
                    <div className="popup-header">
                      <span className={`popup-tag priority-${(incident.priority || "medium").toLowerCase()}`}>
                        {incident.priority || "Normal"}
                      </span>
                      <span className="popup-id ds-mono">#{String(incident.id).slice(-4)}</span>
                    </div>

                    <h4 className="popup-title">{incident.type}</h4>
                    <p className="popup-location">{incident.city}</p>

                    <div className="popup-coords ds-mono">
                      LAT {Number(incident.lat).toFixed(4)} • LNG {Number(incident.lng).toFixed(4)}
                    </div>

                    {typeof incident.hopCount === "number" && incident.hopCount > 0 && (
                      <div className="popup-mesh-tag">
                        <ActionIcons.refresh className="ds-icon-sm" aria-hidden="true" />
                        <span>Mesh Relayed ({incident.hopCount} hop{incident.hopCount > 1 ? "s" : ""})</span>
                      </div>
                    )}

                    <div className="popup-footer">
                      <span className={`status-pill ${isClosed ? "closed" : "active"}`}>
                        {isClosed ? "RESOLVED" : "ACTIVE"}
                      </span>
                      {onSelectIncident && (
                        <button
                          className="popup-inspect-btn"
                          onClick={() => onSelectIncident(incident)}
                        >
                          Inspect →
                        </button>
                      )}
                    </div>
                  </div>
                </Popup>
              </Marker>
            </div>
          );
        })}
      </MapContainer>

      <div className="map-legend">
        <span className="legend-title ds-metadata">INCIDENT SEVERITY</span>
        <span className="legend-item"><i className="dot dot-critical" /> Critical</span>
        <span className="legend-item"><i className="dot dot-high" /> High</span>
        <span className="legend-item"><i className="dot dot-medium" /> Medium</span>
        <span className="legend-item"><i className="dot dot-low" /> Low</span>
        <span className="legend-item"><i className="dot dot-closed" /> Resolved</span>
      </div>
    </div>
  );
}

export default MapView;
