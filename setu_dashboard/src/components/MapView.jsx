import { Fragment } from "react";
import { MapContainer, TileLayer, Marker, Popup, Circle } from "react-leaflet";
import "leaflet/dist/leaflet.css";
import { divIcon } from "leaflet";
import { useTheme } from "../context/ThemeContext";
import { ActionIcons } from "../icons";

// =====================================================
// SETU Dashboard — Live Map (v2)
// =====================================================

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
 * - SELECTED: enlarged 26x34 with distinct accent pulse
 * - CRITICAL: immediately visible, 24x30, distinct pulse wave
 * - HIGH: visible, 20x26
 * - MEDIUM: quieter, 18x24
 * - LOW: subtle, 15x20
 * - CLOSED: dimmed slate, 14x18
 */
function buildMarkerIcon(priority, isClosed = false, isSelected = false) {
  const color = isClosed ? "#475569" : priorityColor(priority);
  const isCritical = priority === "Critical" && !isClosed;
  const isHigh = priority === "High" && !isClosed;

  let width = 18;
  let height = 24;
  let dotRadius = 3;

  if (isSelected) {
    width = 26;
    height = 34;
    dotRadius = 4.5;
  } else if (isCritical) {
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
    <div class="setu-map-marker ${isCritical ? "setu-map-marker-critical" : ""} ${isClosed ? "setu-map-marker-closed" : ""} ${isSelected ? "setu-map-marker-selected" : ""}" style="width:${width}px;height:${height}px;">
      ${isCritical || isSelected ? '<span class="setu-map-marker-pulse"></span>' : ""}
      <svg width="${width}" height="${height}" viewBox="0 0 24 30" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M12 0C5.37 0 0 5.37 0 12C0 21 12 30 12 30C12 30 24 21 24 12C24 5.37 18.63 0 12 0Z" fill="${isSelected ? "#0284c7" : color}" fill-opacity="${isClosed ? "0.6" : "0.95"}" stroke="${isSelected ? "#ffffff" : "rgba(0,0,0,0.4)"}" stroke-width="${isSelected ? "2" : "1.2"}"/>
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
function getMarkerIcon(priority, isClosed = false, isSelected = false) {
  const key = `${priority}-${isClosed ? "closed" : "active"}-${isSelected ? "sel" : "norm"}`;
  if (!MARKER_ICON_CACHE[key]) {
    MARKER_ICON_CACHE[key] = buildMarkerIcon(priority, isClosed, isSelected);
  }
  return MARKER_ICON_CACHE[key];
}

function MapView({ incidents, onSelectIncident, selectedIncidentId, tall = false }) {
  const { theme } = useTheme();
  const tileUrl = theme === "light"
    ? "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png"
    : "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png";

  const validIncidents = incidents.filter(
    (i) => typeof i?.lat === "number" && typeof i?.lng === "number" && !isNaN(i.lat) && !isNaN(i.lng)
  );

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

        {validIncidents.map((incident) => {
          const color = priorityColor(incident.priority);
          const isClosed = incident.status === "closed";
          const isSelected = selectedIncidentId === incident.id;
          const isHighOrCritical = !isClosed && (incident.priority === "Critical" || incident.priority === "High" || isSelected);

          return (
            <Fragment key={incident.id}>
              {isHighOrCritical && (
                <Circle
                  center={[incident.lat, incident.lng]}
                  radius={isSelected ? 500 : incident.priority === "Critical" ? 400 : 250}
                  pathOptions={{
                    color: isSelected ? "#0284c7" : color,
                    fillColor: isSelected ? "#0284c7" : color,
                    fillOpacity: isSelected ? 0.12 : 0.05,
                    weight: isSelected ? 1.5 : 1,
                    opacity: isSelected ? 0.5 : 0.25,
                    dashArray: incident.priority === "Critical" && !isSelected ? undefined : "3, 3",
                  }}
                />
              )}
              <Marker
                position={[incident.lat, incident.lng]}
                icon={getMarkerIcon(incident.priority, isClosed, isSelected)}
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
            </Fragment>
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
