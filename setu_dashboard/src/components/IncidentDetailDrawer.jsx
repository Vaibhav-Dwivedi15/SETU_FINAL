import { useEffect, useState } from "react";
import { MapContainer, TileLayer, Marker } from "react-leaflet";
import { Icon } from "leaflet";
import { timeAgo } from "../utils/timeAgo";
import { useTick } from "../utils/useTick";
import { useTheme } from "../context/ThemeContext";

const priorityIcon = {
  Critical: new Icon({ iconUrl: "https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-red.png", shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png", iconSize: [25, 41], iconAnchor: [12, 41] }),
  High: new Icon({ iconUrl: "https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-orange.png", shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png", iconSize: [25, 41], iconAnchor: [12, 41] }),
  Medium: new Icon({ iconUrl: "https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-gold.png", shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png", iconSize: [25, 41], iconAnchor: [12, 41] }),
  Low: new Icon({ iconUrl: "https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-green.png", shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png", iconSize: [25, 41], iconAnchor: [12, 41] }),
};

function IncidentDetailDrawer({ incident, onClose, onResolve }) {
  useTick();
  const { theme } = useTheme();
  const [copied, setCopied] = useState(null); // "id" | "coords" | null

  useEffect(() => {
    function handleKeyDown(e) {
      if (e.key === "Escape") onClose();
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [onClose]);

  if (!incident) return null;

  const priority = incident.priority || "Medium";
  const isClosed = incident.status === "closed";
  const icon = priorityIcon[priority] || priorityIcon.Medium;
  const tileUrl = theme === "light"
    ? "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png"
    : "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png";

  function copyToClipboard(text, key) {
    navigator.clipboard?.writeText(text).then(() => {
      setCopied(key);
      setTimeout(() => setCopied(null), 1500);
    });
  }

  return (
    <>
      <div className="drawer-backdrop" onClick={onClose} />
      <aside className="detail-drawer" role="dialog" aria-modal="true" aria-labelledby="drawer-title">
        <div className="drawer-header">
          <div>
            <span className={`badge ${priority === "Critical" ? "red" : priority === "High" ? "orange" : priority === "Low" ? "green" : "yellow"}`}>
              {priority}
            </span>
            <h2 id="drawer-title">{incident.type}</h2>
          </div>
          <button className="close-btn" onClick={onClose} aria-label="Close details">✖</button>
        </div>

        <div className="drawer-mini-map">
          <MapContainer
            center={[incident.lat, incident.lng]}
            zoom={11}
            zoomControl={false}
            dragging={false}
            scrollWheelZoom={false}
            doubleClickZoom={false}
            style={{ height: "180px", width: "100%" }}
          >
            <TileLayer
              attribution='&copy; OpenStreetMap, &copy; CARTO'
              url={tileUrl}
            />
            <Marker position={[incident.lat, incident.lng]} icon={icon} />
          </MapContainer>
        </div>

        <dl className="drawer-meta">
          <div>
            <dt>City</dt>
            <dd>{incident.city}</dd>
          </div>
          <div>
            <dt>Status</dt>
            <dd>
              <span className={`status-badge ${isClosed ? "closed" : "active"}`}>
                {isClosed ? "Closed" : "Active"}
              </span>
            </dd>
          </div>
          <div>
            <dt>Reported</dt>
            <dd className="mono" title={incident.reportedAt ? new Date(incident.reportedAt).toLocaleString() : ""}>
              {timeAgo(incident.reportedAt)}
            </dd>
          </div>
          {incident.reportCount > 1 && (
            <div>
              <dt>Merged Reports</dt>
              <dd>{incident.reportCount} independent reports</dd>
            </div>
          )}
          {typeof incident.hopCount === "number" && (
            <div>
              <dt>Mesh Path</dt>
              <dd>🔀 {incident.hopCount} hop{incident.hopCount === 1 ? "" : "s"} — no internet needed</dd>
            </div>
          )}
          <div>
            <dt>Coordinates</dt>
            <dd className="mono">{incident.lat.toFixed(4)}, {incident.lng.toFixed(4)}</dd>
          </div>
        </dl>

        <div className="drawer-copy-row">
          <button
            className={`drawer-copy-btn ${copied === "id" ? "copied" : ""}`}
            onClick={() => copyToClipboard(String(incident.id), "id")}
          >
            {copied === "id" ? "✓ Copied" : "📋 Copy ID"}
          </button>
          <button
            className={`drawer-copy-btn ${copied === "coords" ? "copied" : ""}`}
            onClick={() => copyToClipboard(`${incident.lat}, ${incident.lng}`, "coords")}
          >
            {copied === "coords" ? "✓ Copied" : "📍 Copy Coordinates"}
          </button>
        </div>

        {!isClosed && (
          <button
            className="resolve-btn drawer-resolve"
            onClick={() => {
              onResolve(incident.id);
              onClose();
            }}
          >
            ✓ Mark Resolved
          </button>
        )}
      </aside>
    </>
  );
}

export default IncidentDetailDrawer;
