import { useEffect, useState } from "react";
import { MapContainer, TileLayer, Marker } from "react-leaflet";
import { Icon } from "leaflet";
import { timeAgo } from "../utils/timeAgo";
import { useTick } from "../utils/useTick";
import { useTheme } from "../context/ThemeContext";
import {
  fetchIncidentResponses,
  fetchIncidentHistory,
  fetchIncidentGovernmentNotifications,
} from "../services/api";
import { getCategory, categorizeIncident } from "../utils/incidentCategories";
import RelayTrace from "./RelayTrace";
import DeliveryStatusPanel from "./DeliveryStatusPanel";
import CommunityResponsePanel from "./CommunityResponsePanel";
import IncidentTimeline from "./IncidentTimeline";
import GovernmentNotificationPanel from "./GovernmentNotificationPanel";

const priorityIcon = {
  Critical: new Icon({ iconUrl: "https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-red.png", shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png", iconSize: [25, 41], iconAnchor: [12, 41] }),
  High: new Icon({ iconUrl: "https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-orange.png", shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png", iconSize: [25, 41], iconAnchor: [12, 41] }),
  Medium: new Icon({ iconUrl: "https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-gold.png", shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png", iconSize: [25, 41], iconAnchor: [12, 41] }),
  Low: new Icon({ iconUrl: "https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-green.png", shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png", iconSize: [25, 41], iconAnchor: [12, 41] }),
};

function badgeClass(priority) {
  if (priority === "Critical") return "red";
  if (priority === "High") return "orange";
  if (priority === "Low") return "green";
  return "yellow";
}

function IncidentDetailDrawer({ incident, onClose, onResolve }) {
  useTick();
  const { theme } = useTheme();
  const [copied, setCopied] = useState(null); // "id" | "coords" | null
  const [responses, setResponses] = useState([]);
  const [history, setHistory] = useState([]);
  const [loadingResponses, setLoadingResponses] = useState(false);
  const [loadingHistory, setLoadingHistory] = useState(false);
  const [govNotifications, setGovNotifications] = useState([]);
  const [loadingGov, setLoadingGov] = useState(false);
  const [activeTab, setActiveTab] = useState("overview"); // "overview" | "delivery" | "activity"

  useEffect(() => {
    function handleKeyDown(e) {
      if (e.key === "Escape") onClose();
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [onClose]);

  // Fetch Phase 3 community responses + the backend audit trail whenever
  // a different incident is opened. Both degrade to [] rather than
  // throwing if the endpoints aren't available on the deployed backend
  // (see services/api.js), so an older deployment shows honest empty
  // states instead of breaking the drawer.
  useEffect(() => {
    if (!incident?.id) return;
    let cancelled = false;

    setLoadingResponses(true);
    setLoadingHistory(true);
    setLoadingGov(true);
    setResponses([]);
    setHistory([]);
    setGovNotifications([]);
    setActiveTab("overview");

    fetchIncidentResponses(incident.id).then((data) => {
      if (!cancelled) {
        setResponses(data);
        setLoadingResponses(false);
      }
    });

    fetchIncidentHistory(incident.id).then((data) => {
      if (!cancelled) {
        setHistory(data);
        setLoadingHistory(false);
      }
    });

    fetchIncidentGovernmentNotifications(incident.id).then((data) => {
      if (!cancelled) {
        setGovNotifications(data);
        setLoadingGov(false);
      }
    });

    return () => { cancelled = true; };
  }, [incident?.id]);

  if (!incident) return null;

  const priority = incident.priority || "Medium";
  const isClosed = incident.status === "closed";
  const icon = priorityIcon[priority] || priorityIcon.Medium;
  const category = getCategory(categorizeIncident(incident));
  const tileUrl = theme === "light"
    ? "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png"
    : "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png";

  function copyToClipboard(text, key) {
    navigator.clipboard?.writeText(text).then(() => {
      setCopied(key);
      setTimeout(() => setCopied(null), 1500);
    });
  }

  const hasCoords = typeof incident.lat === "number" && typeof incident.lng === "number";
  const hasAiAssessment =
    incident.aiIncidentType || incident.aiUrgency != null || incident.aiPriorityValue != null;

  return (
    <>
      <div className="drawer-backdrop" onClick={onClose} />
      <aside className="detail-drawer" role="dialog" aria-modal="true" aria-labelledby="drawer-title">
        <div className="drawer-header">
          <div>
            <span className={`badge ${badgeClass(priority)}`}>{priority}</span>
            <span className="drawer-category-chip">{category.icon} {category.label}</span>
            <h2 id="drawer-title">{incident.type}</h2>
          </div>
          <button className="close-btn" onClick={onClose} aria-label="Close details">✖</button>
        </div>

        <div className="drawer-tabs" role="tablist">
          <button
            role="tab"
            aria-selected={activeTab === "overview"}
            className={activeTab === "overview" ? "active" : ""}
            onClick={() => setActiveTab("overview")}
          >
            Overview
          </button>
          <button
            role="tab"
            aria-selected={activeTab === "delivery"}
            className={activeTab === "delivery" ? "active" : ""}
            onClick={() => setActiveTab("delivery")}
          >
            Delivery
          </button>
          <button
            role="tab"
            aria-selected={activeTab === "activity"}
            className={activeTab === "activity" ? "active" : ""}
            onClick={() => setActiveTab("activity")}
          >
            Activity
            {responses.length > 0 && <span className="drawer-tab-dot" aria-hidden="true" />}
          </button>
        </div>

        <div className="drawer-scroll">
          {activeTab === "overview" && (
            <>
              {hasCoords && (
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
                    <TileLayer attribution='&copy; OpenStreetMap, &copy; CARTO' url={tileUrl} />
                    <Marker position={[incident.lat, incident.lng]} icon={icon} />
                  </MapContainer>
                </div>
              )}

              <dl className="drawer-meta">
                <div>
                  <dt>Location</dt>
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
                {isClosed && incident.closedAt && (
                  <div>
                    <dt>Closed</dt>
                    <dd className="mono">{timeAgo(incident.closedAt)}</dd>
                  </div>
                )}
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
                {hasCoords && (
                  <div>
                    <dt>Coordinates</dt>
                    <dd className="mono">{incident.lat.toFixed(4)}, {incident.lng.toFixed(4)}</dd>
                  </div>
                )}
              </dl>

              {typeof incident.hopCount === "number" && (
                <div className="drawer-relay-row">
                  <RelayTrace hopCount={incident.hopCount} />
                </div>
              )}

              {/* Reporter-declared vs AI-assessed priority are shown side
                  by side and never conflated — the backend model is
                  explicit that these answer different questions and
                  neither should silently overwrite the other. */}
              <div className="priority-comparison">
                <h3 className="drawer-section-title">Priority Assessment</h3>
                <div className="priority-comparison-grid">
                  <div>
                    <span className="priority-comparison-label">Reporter declared</span>
                    {incident.senderPriority ? (
                      <span className={`badge ${badgeClass(incident.senderPriority)}`}>
                        {incident.senderPriority}
                      </span>
                    ) : (
                      <span className="priority-comparison-none">Not provided</span>
                    )}
                  </div>
                  <div>
                    <span className="priority-comparison-label">AI assessed</span>
                    {incident.aiPriority ? (
                      <span className={`badge ${badgeClass(incident.aiPriority)}`}>
                        {incident.aiPriority}
                        {incident.aiPriorityValue != null && (
                          <span className="mono"> ({incident.aiPriorityValue.toFixed(1)})</span>
                        )}
                      </span>
                    ) : (
                      <span className="priority-comparison-none">Not assessed</span>
                    )}
                  </div>
                </div>
              </div>

              {hasAiAssessment && (
                <div className="ai-assessment">
                  <h3 className="drawer-section-title">AI Analysis</h3>
                  {incident.aiIncidentType && (
                    <div className="ai-assessment-row">
                      <span className="ai-assessment-label">Classified as</span>
                      <span>
                        {incident.aiIncidentType}
                        {incident.aiIncidentConfidence != null && (
                          <span className="mono ai-confidence">
                            {" "}{Math.round(incident.aiIncidentConfidence * 100)}% confidence
                          </span>
                        )}
                      </span>
                    </div>
                  )}
                  {incident.aiIncidentExplanation && (
                    <p className="ai-explanation">{incident.aiIncidentExplanation}</p>
                  )}
                  {incident.aiUrgency != null && (
                    <div className="ai-assessment-row">
                      <span className="ai-assessment-label">Urgency</span>
                      <span>
                        {incident.aiUrgency}/5
                        {incident.aiUrgencyConfidence != null && (
                          <span className="mono ai-confidence">
                            {" "}{Math.round(incident.aiUrgencyConfidence * 100)}% confidence
                          </span>
                        )}
                      </span>
                    </div>
                  )}
                  {incident.aiUrgencyExplanation && (
                    <p className="ai-explanation">{incident.aiUrgencyExplanation}</p>
                  )}
                </div>
              )}

              <div className="drawer-copy-row">
                <button
                  className={`drawer-copy-btn ${copied === "id" ? "copied" : ""}`}
                  onClick={() => copyToClipboard(String(incident.id), "id")}
                >
                  {copied === "id" ? "✓ Copied" : "📋 Copy ID"}
                </button>
                {hasCoords && (
                  <button
                    className={`drawer-copy-btn ${copied === "coords" ? "copied" : ""}`}
                    onClick={() => copyToClipboard(`${incident.lat}, ${incident.lng}`, "coords")}
                  >
                    {copied === "coords" ? "✓ Copied" : "📍 Copy Coordinates"}
                  </button>
                )}
              </div>
            </>
          )}

          {activeTab === "delivery" && (
            <>
              <DeliveryStatusPanel incident={incident} responseCount={responses.length} />
              <GovernmentNotificationPanel
                notifications={govNotifications}
                loading={loadingGov}
              />
            </>
          )}

          {activeTab === "activity" && (
            <>
              <CommunityResponsePanel responses={responses} loading={loadingResponses} />
              <IncidentTimeline history={history} loading={loadingHistory} />
            </>
          )}
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
