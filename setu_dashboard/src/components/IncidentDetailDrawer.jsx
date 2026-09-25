import { useEffect, useState } from "react";
import { MapContainer, TileLayer, Marker } from "react-leaflet";
import { divIcon } from "leaflet";
import { timeAgo } from "../utils/timeAgo";
import { useTick } from "../utils/useTick";
import { useTheme } from "../context/ThemeContext";
import { fetchIncidentResponses, fetchIncidentHistory, fetchIncidentGovernmentNotifications } from "../services/api";
import { getCategory, categorizeIncident } from "../utils/incidentCategories";
import { CategoryIcons, ActionIcons } from "../icons";
import { PriorityBadge, StatusBadge } from "./ui/Primitives";
import { useFocusTrap } from "../utils/useFocusTrap";
import RelayTrace from "./RelayTrace";
import DeliveryStatusPanel from "./DeliveryStatusPanel";
import CommunityResponsePanel from "./CommunityResponsePanel";
import IncidentTimeline from "./IncidentTimeline";
import GovernmentNotificationPanel from "./GovernmentNotificationPanel";

function getDrawerMarker(priority) {
  const colors = {
    Critical: "#ef4444",
    High: "#f59e0b",
    Medium: "#eab308",
    Low: "#10b981",
  };
  const color = colors[priority] || "#64748b";
  const html = `
    <div style="display:flex;align-items:center;justify-content:center;filter:drop-shadow(0 2px 4px rgba(0,0,0,0.4));">
      <svg width="22" height="28" viewBox="0 0 24 30" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M12 0C5.37 0 0 5.37 0 12C0 21 12 30 12 30C12 30 24 21 24 12C24 5.37 18.63 0 12 0Z" fill="${color}" stroke="rgba(0,0,0,0.3)" stroke-width="1.2"/>
        <circle cx="12" cy="11" r="3.5" fill="#ffffff" fill-opacity="0.95"/>
      </svg>
    </div>
  `;
  return divIcon({
    html,
    className: "drawer-mini-marker",
    iconSize: [22, 28],
    iconAnchor: [11, 28],
  });
}

function IncidentDetailDrawer({ incident, onClose, onResolve }) {
  useTick();
  const { theme } = useTheme();
  const trapRef = useFocusTrap(Boolean(incident));
  const [copied, setCopied] = useState(null);
  const [responses, setResponses] = useState([]);
  const [history, setHistory] = useState([]);
  const [govNotifications, setGovNotifications] = useState([]);
  const [loadingResponses, setLoadingResponses] = useState(false);
  const [loadingHistory, setLoadingHistory] = useState(false);
  const [loadingGov, setLoadingGov] = useState(false);
  const [activeTab, setActiveTab] = useState("overview");

  useEffect(() => {
    function handleKeyDown(e) { if (e.key === "Escape") onClose(); }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [onClose]);

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
      if (!cancelled) { setResponses(data); setLoadingResponses(false); }
    });
    fetchIncidentHistory(incident.id).then((data) => {
      if (!cancelled) { setHistory(data); setLoadingHistory(false); }
    });
    fetchIncidentGovernmentNotifications(incident.id).then((data) => {
      if (!cancelled) { setGovNotifications(data); setLoadingGov(false); }
    });

    return () => { cancelled = true; };
  }, [incident?.id]);

  if (!incident) return null;

  const priority = incident.priority || "Medium";
  const isClosed = incident.status === "closed";
  const icon = getDrawerMarker(priority);
  const category = getCategory(categorizeIncident(incident));
  const CategoryIcon = CategoryIcons[category.key] || ActionIcons.location;
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
  const hasAiAssessment = incident.aiIncidentType || incident.aiUrgency != null || incident.aiPriorityValue != null;

  return (
    <>
      <div className="drawer-backdrop" onClick={onClose} />
      <aside className="detail-drawer" ref={trapRef} role="dialog" aria-modal="true" aria-labelledby="drawer-title">
        <div className="drawer-header">
          <div>
            <div style={{ display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
              <PriorityBadge priority={priority} />
              <span className="drawer-category-chip">
                <CategoryIcon className="ds-icon-sm" aria-hidden="true" /> {category.label}
              </span>
            </div>
            <h2 id="drawer-title">{incident.type}</h2>
          </div>
          <button className="close-btn" onClick={onClose} aria-label="Close details">
            <ActionIcons.dismiss className="ds-icon-md" aria-hidden="true" />
          </button>
        </div>

        <div className="drawer-tabs" role="tablist">
          <button role="tab" aria-selected={activeTab === "overview"} className={activeTab === "overview" ? "active" : ""} onClick={() => setActiveTab("overview")}>Overview</button>
          <button role="tab" aria-selected={activeTab === "delivery"} className={activeTab === "delivery" ? "active" : ""} onClick={() => setActiveTab("delivery")}>Delivery</button>
          <button role="tab" aria-selected={activeTab === "activity"} className={activeTab === "activity" ? "active" : ""} onClick={() => setActiveTab("activity")}>
            Activity
            {responses.length > 0 && <span className="drawer-tab-dot" aria-hidden="true" />}
          </button>
        </div>

        <div className="drawer-scroll">
          {activeTab === "overview" && (
            <>
              {hasCoords && (
                <div className="drawer-mini-map">
                  <MapContainer center={[incident.lat, incident.lng]} zoom={11} zoomControl={false} dragging={false} scrollWheelZoom={false} doubleClickZoom={false} style={{ height: "180px", width: "100%" }}>
                    <TileLayer attribution='&copy; OpenStreetMap, &copy; CARTO' url={tileUrl} />
                    <Marker position={[incident.lat, incident.lng]} icon={icon} />
                  </MapContainer>
                </div>
              )}

              <dl className="drawer-meta">
                <div><dt>Location</dt><dd>{incident.city}</dd></div>
                <div><dt>Status</dt><dd><StatusBadge status={isClosed ? "closed" : "active"} label={isClosed ? "Closed" : "Active"} /></dd></div>
                <div><dt>Reported</dt><dd className="mono" title={incident.reportedAt ? new Date(incident.reportedAt).toLocaleString() : ""}>{timeAgo(incident.reportedAt)}</dd></div>
                {isClosed && incident.closedAt && (<div><dt>Closed</dt><dd className="mono">{timeAgo(incident.closedAt)}</dd></div>)}
                {incident.reportCount > 1 && (<div><dt>Merged Reports</dt><dd>{incident.reportCount} independent reports</dd></div>)}
                {typeof incident.hopCount === "number" && (
                  <div>
                    <dt>Mesh Path</dt>
                    <dd style={{ display: "flex", alignItems: "center", gap: 6 }}>
                      <ActionIcons.refresh className="ds-icon-sm" aria-hidden="true" />
                      {incident.hopCount} hop{incident.hopCount === 1 ? "" : "s"} — no internet needed
                    </dd>
                  </div>
                )}
                {hasCoords && (<div><dt>Coordinates</dt><dd className="mono">{incident.lat.toFixed(4)}, {incident.lng.toFixed(4)}</dd></div>)}
              </dl>

              {typeof incident.hopCount === "number" && (
                <div className="drawer-relay-row"><RelayTrace hopCount={incident.hopCount} /></div>
              )}

              <div className="priority-comparison">
                <h3 className="ds-section-title">Priority Assessment</h3>
                <div className="priority-comparison-grid">
                  <div>
                    <span className="priority-comparison-label">Reporter declared</span>
                    {incident.senderPriority ? <PriorityBadge priority={incident.senderPriority} size="sm" /> : <span className="priority-comparison-none">Not provided</span>}
                  </div>
                  <div>
                    <span className="priority-comparison-label">AI assessed</span>
                    {incident.aiPriority ? (
                      <span style={{ display: "flex", alignItems: "center", gap: 6 }}>
                        <PriorityBadge priority={incident.aiPriority} size="sm" />
                        {incident.aiPriorityValue != null && <span className="mono">({incident.aiPriorityValue.toFixed(1)})</span>}
                      </span>
                    ) : <span className="priority-comparison-none">Not assessed</span>}
                  </div>
                </div>
              </div>

              {hasAiAssessment && (
                <div className="ai-assessment">
                  <h3 className="ds-section-title">AI Analysis</h3>
                  {incident.aiIncidentType && (
                    <div className="ai-assessment-row">
                      <span className="ai-assessment-label">Classified as</span>
                      <span>{incident.aiIncidentType}{incident.aiIncidentConfidence != null && <span className="mono ai-confidence"> {Math.round(incident.aiIncidentConfidence * 100)}% confidence</span>}</span>
                    </div>
                  )}
                  {incident.aiIncidentExplanation && <p className="ai-explanation">{incident.aiIncidentExplanation}</p>}
                  {incident.aiUrgency != null && (
                    <div className="ai-assessment-row">
                      <span className="ai-assessment-label">Urgency</span>
                      <span>{incident.aiUrgency}/5{incident.aiUrgencyConfidence != null && <span className="mono ai-confidence"> {Math.round(incident.aiUrgencyConfidence * 100)}% confidence</span>}</span>
                    </div>
                  )}
                  {incident.aiUrgencyExplanation && <p className="ai-explanation">{incident.aiUrgencyExplanation}</p>}
                </div>
              )}

              <div className="drawer-copy-row">
                <button className={`drawer-copy-btn ${copied === "id" ? "copied" : ""}`} onClick={() => copyToClipboard(String(incident.id), "id")}>
                  {copied === "id" ? (<><ActionIcons.confirm className="ds-icon-sm" aria-hidden="true" /> Copied</>) : (<><ActionIcons.copy className="ds-icon-sm" aria-hidden="true" /> Copy ID</>)}
                </button>
                {hasCoords && (
                  <button className={`drawer-copy-btn ${copied === "coords" ? "copied" : ""}`} onClick={() => copyToClipboard(`${incident.lat}, ${incident.lng}`, "coords")}>
                    {copied === "coords" ? (<><ActionIcons.confirm className="ds-icon-sm" aria-hidden="true" /> Copied</>) : (<><ActionIcons.location className="ds-icon-sm" aria-hidden="true" /> Copy Coordinates</>)}
                  </button>
                )}
              </div>
            </>
          )}

          {activeTab === "delivery" && (
            <>
              <DeliveryStatusPanel incident={incident} responseCount={responses.length} />
              <GovernmentNotificationPanel notifications={govNotifications} loading={loadingGov} />
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
          <button className="resolve-btn drawer-resolve" onClick={() => { onResolve(incident.id); onClose(); }}>
            <ActionIcons.confirm className="ds-icon-sm" aria-hidden="true" /> Mark Resolved
          </button>
        )}
      </aside>
    </>
  );
}

export default IncidentDetailDrawer;
