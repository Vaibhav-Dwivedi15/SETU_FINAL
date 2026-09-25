import { Fragment, useState, useEffect } from "react";
import { MapContainer, TileLayer, Marker, Popup, Circle, useMap } from "react-leaflet";
import "leaflet/dist/leaflet.css";
import { divIcon } from "leaflet";
import { useTheme } from "../context/ThemeContext";
import { ActionIcons, MiscIcons } from "../icons";

// =====================================================
// SETU Dashboard — Live Geospatial Intelligence Map (v2)
// Precision Disaster Operations Mapping
// =====================================================

const DEFAULT_CENTER = [25.4358, 81.8463]; // Prayagraj Command Hub
const DEFAULT_ZOOM = 7;

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
 * Builds self-contained SVG pin as a Leaflet divIcon.
 * Strict visual hierarchy:
 * - SELECTED: enlarged 28x36 with distinct focus ring
 * - CRITICAL: 24x30 with danger pulse
 * - HIGH: 20x26
 * - MEDIUM: 18x24
 * - LOW: 16x22
 * - CLOSED: 14x18 dimmed slate
 */
function buildMarkerIcon(priority, isClosed = false, isSelected = false) {
  const color = isClosed ? "#475569" : priorityColor(priority);
  const isCritical = priority === "Critical" && !isClosed;
  const isHigh = priority === "High" && !isClosed;

  let width = 18;
  let height = 24;
  let dotRadius = 3;

  if (isSelected) {
    width = 28;
    height = 36;
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
      ${isCritical ? '<span class="setu-map-marker-pulse"></span>' : ""}
      <svg width="${width}" height="${height}" viewBox="0 0 24 30" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M12 0C5.37 0 0 5.37 0 12C0 21 12 30 12 30C12 30 24 21 24 12C24 5.37 18.63 0 12 0Z" fill="${isSelected ? "#0284c7" : color}" fill-opacity="${isClosed ? "0.6" : "0.95"}" stroke="${isSelected ? "#ffffff" : "rgba(0,0,0,0.35)"}" stroke-width="${isSelected ? "2.5" : "1.2"}"/>
        <circle cx="12" cy="11" r="${dotRadius}" fill="#ffffff" fill-opacity="${isClosed ? "0.6" : "0.95"}"/>
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

/**
 * Controller to smoothly focus the map when selected incident changes,
 * or reset focus when recenter is clicked.
 */
function MapController({ selectedIncident, recenterTrigger }) {
  const map = useMap();

  useEffect(() => {
    if (selectedIncident && typeof selectedIncident.lat === "number" && typeof selectedIncident.lng === "number") {
      map.flyTo([selectedIncident.lat, selectedIncident.lng], Math.max(map.getZoom(), 11), {
        duration: 1.0,
      });
    }
  }, [selectedIncident, map]);

  useEffect(() => {
    if (recenterTrigger > 0) {
      map.flyTo(DEFAULT_CENTER, DEFAULT_ZOOM, { duration: 0.8 });
    }
  }, [recenterTrigger, map]);

  return null;
}

function MapView({ incidents = [], onSelectIncident, selectedIncidentId, tall = false }) {
  const { theme } = useTheme();
  const [tileError, setTileError] = useState(false);
  const [recenterCount, setRecenterCount] = useState(0);

  const tileUrl = theme === "light"
    ? "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png"
    : "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png";

  const validIncidents = incidents.filter(
    (i) => typeof i?.lat === "number" && typeof i?.lng === "number" && !isNaN(i.lat) && !isNaN(i.lng)
  );

  const selectedIncident = validIncidents.find((i) => i.id === selectedIncidentId);
  const criticalCount = validIncidents.filter((i) => i.priority === "Critical" && i.status !== "closed").length;

  return (
    <div className={`map-container ${tall ? "map-container-tall" : ""}`}>
      {/* Tactical Map HUD Header */}
      <div className="map-hud-bar">
        <div className="map-hud-left">
          <span className="map-hud-badge">PRAYAGRAJ SECTOR</span>
          <span className="map-hud-status ds-mono">
            {validIncidents.length} TARGETS PLOTTED {criticalCount > 0 ? `• ${criticalCount} CRITICAL` : ""}
          </span>
        </div>

        <div className="map-hud-actions">
          <button
            className="map-hud-btn"
            onClick={() => setRecenterCount((c) => c + 1)}
            title="Reset focus to Prayagraj Command Hub"
          >
            <ActionIcons.location className="ds-icon-sm" aria-hidden="true" /> Recenter Hub
          </button>
        </div>
      </div>

      {tileError && (
        <div className="map-offline-banner">
          <MiscIcons.alert className="ds-icon-sm" aria-hidden="true" />
          <span>Local Tactical Grid Active • Map Tiles Offline (Operating on cached telemetry)</span>
        </div>
      )}

      <MapContainer
        center={DEFAULT_CENTER}
        zoom={DEFAULT_ZOOM}
        style={{ height: tall ? "100%" : "420px", width: "100%" }}
        scrollWheelZoom
      >
        <TileLayer
          attribution='&copy; OpenStreetMap, &copy; CARTO'
          url={tileUrl}
          eventHandlers={{
            tileerror: () => setTileError(true),
            load: () => setTileError(false),
          }}
        />

        <MapController
          selectedIncident={selectedIncident}
          recenterTrigger={recenterCount}
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
                  radius={isSelected ? 600 : incident.priority === "Critical" ? 450 : 250}
                  pathOptions={{
                    color: isSelected ? "#0284c7" : color,
                    fillColor: isSelected ? "#0284c7" : color,
                    fillOpacity: isSelected ? 0.15 : 0.06,
                    weight: isSelected ? 2 : 1,
                    opacity: isSelected ? 0.7 : 0.3,
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

                    {typeof incident.hopCount === "number" && (
                      <div className="popup-mesh-tag">
                        <ActionIcons.refresh className="ds-icon-sm" aria-hidden="true" />
                        <span>{incident.hopCount === 0 ? "Direct Uplink" : `Mesh Relayed (${incident.hopCount} hop${incident.hopCount > 1 ? "s" : ""})`}</span>
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
                          Inspect Dossier →
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

      {/* High-Contrast Tactical Legend */}
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
