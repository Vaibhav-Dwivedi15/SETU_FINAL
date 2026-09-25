import { useState } from "react";
import MapView from "../MapView";
import IncidentList from "../IncidentList";
import AnalyticsChart from "../AnalyticsChart";
import AIPanel from "../AIPanel";
import ResourcePanel from "../ResourcePanel";
import { NavIcons, ActionIcons, CategoryIcons, MiscIcons } from "../../icons";

function DashboardHome({ allIncidents, filteredIncidents, onResolve, onSelectIncident, trends = {} }) {
  const [tacticalTab, setTacticalTab] = useState("live"); // "live" | "critical" | "ai"
  const [showTray, setShowTray] = useState(false);

  const active = allIncidents.filter((i) => i.status !== "closed");
  const activeCount = active.length;
  const criticalCount = active.filter((i) => i.priority === "Critical").length;
  const medicalCount = active.filter((i) => i.type === "Medical").length;
  const fireCount = active.filter((i) => i.type === "Fire").length;
  const floodCount = active.filter((i) => i.type === "Flood").length;
  const meshRelayedCount = active.filter((i) => typeof i.hopCount === "number" && i.hopCount > 0).length;

  const criticalFiltered = filteredIncidents.filter((i) => i.priority === "Critical");

  return (
    <div className="ops-command-container">
      {/* Top Operational Mission Bar */}
      <div className="ops-mission-bar">
        <div className="ops-mission-item">
          <NavIcons.liveIncidents className="ds-icon-sm" aria-hidden="true" />
          <span>ACTIVE INCIDENTS:</span>
          <strong>{activeCount}</strong>
        </div>

        <div className="ops-mission-divider" />

        <div className={`ops-mission-item ${criticalCount > 0 ? "critical" : ""}`}>
          <MiscIcons.alert className="ds-icon-sm" aria-hidden="true" />
          <span>CRITICAL:</span>
          <strong>{criticalCount}</strong>
        </div>

        <div className="ops-mission-divider" />

        <div className="ops-mission-item">
          <CategoryIcons.medical className="ds-icon-sm" aria-hidden="true" />
          <span>MEDICAL:</span>
          <strong>{medicalCount}</strong>
          {trends.Medical != null && trends.Medical !== 0 && (
            <span className="ds-mono" style={{ fontSize: 10, color: trends.Medical > 0 ? "var(--danger)" : "var(--success)" }}>
              {trends.Medical > 0 ? `+${trends.Medical}` : trends.Medical}
            </span>
          )}
        </div>

        <div className="ops-mission-divider" />

        <div className="ops-mission-item">
          <CategoryIcons.fire className="ds-icon-sm" aria-hidden="true" />
          <span>FIRE:</span>
          <strong>{fireCount}</strong>
        </div>

        <div className="ops-mission-divider" />

        <div className="ops-mission-item">
          <CategoryIcons.natural_disaster className="ds-icon-sm" aria-hidden="true" />
          <span>FLOOD:</span>
          <strong>{floodCount}</strong>
        </div>

        <div className="ops-mission-divider" />

        <div className="ops-mission-item" style={{ marginLeft: "auto" }}>
          <ActionIcons.refresh className="ds-icon-sm" aria-hidden="true" style={{ color: "var(--network)" }} />
          <span>MESH PACKETS:</span>
          <strong className="ds-mono" style={{ color: "var(--network)" }}>{meshRelayedCount} RELAYED</strong>
        </div>
      </div>

      {/* Main Operations Command Workspace (Map 67% + Tactical Feed 33%) */}
      <div className="ops-command-workspace">
        {/* Left: Geospatial Intelligence Area */}
        <div className="ops-map-area">
          <div className="ops-map-header">
            <div className="ops-map-title">
              <NavIcons.liveMap className="ds-icon-sm" aria-hidden="true" style={{ color: "var(--accent)" }} />
              <span>Geospatial Incident Intelligence</span>
            </div>
            <div className="ops-map-status">
              <span className="ds-mono">{filteredIncidents.length} TARGETS PLOTTED</span>
            </div>
          </div>

          <MapView
            incidents={filteredIncidents}
            onSelectIncident={onSelectIncident}
            tall
          />

          <div className="ops-map-footer ds-mono">
            <span>REFERENCE: WGS84 • GRID: SECTOR 4 DISPATCH</span>
            <span>TELEMETRY: 915MHz LoRa RF MESH • CARTO TACTICAL BASEMAP</span>
          </div>
        </div>

        {/* Right: Tactical Operations Feed Panel */}
        <div className="ops-feed-area">
          <div className="ops-feed-tabs">
            <button
              className={`ops-feed-tab ${tacticalTab === "live" ? "active" : ""}`}
              onClick={() => setTacticalTab("live")}
            >
              ACTIVE FEED ({filteredIncidents.length})
            </button>
            <button
              className={`ops-feed-tab ${tacticalTab === "critical" ? "active" : ""}`}
              onClick={() => setTacticalTab("critical")}
              style={{ color: criticalFiltered.length > 0 && tacticalTab !== "critical" ? "var(--danger)" : undefined }}
            >
              CRITICAL ({criticalFiltered.length})
            </button>
            <button
              className={`ops-feed-tab ${tacticalTab === "ai" ? "active" : ""}`}
              onClick={() => setTacticalTab("ai")}
            >
              AI TRIAGE
            </button>
          </div>

          <div className="ops-feed-body">
            {tacticalTab === "live" && (
              <IncidentList
                incidents={filteredIncidents}
                onResolve={onResolve}
                onSelect={onSelectIncident}
                hideHeader
              />
            )}

            {tacticalTab === "critical" && (
              <IncidentList
                incidents={criticalFiltered}
                onResolve={onResolve}
                onSelect={onSelectIncident}
                title="Critical Incidents"
                hideHeader
              />
            )}

            {tacticalTab === "ai" && (
              <AIPanel incidents={allIncidents} />
            )}
          </div>
        </div>
      </div>

      {/* Collapsible Secondary Intelligence Tray */}
      <div className="ops-intelligence-tray">
        <button
          className="ops-tray-toggle"
          onClick={() => setShowTray((v) => !v)}
          aria-expanded={showTray}
        >
          <span style={{ display: "inline-flex", alignItems: "center", gap: 8 }}>
            <NavIcons.analytics className="ds-icon-sm" aria-hidden="true" />
            <span>Response Asset Readiness & Historical Telemetry Trends</span>
          </span>
          <span className="ds-mono" style={{ fontSize: 11 }}>
            {showTray ? "▲ COLLAPSE TRAY" : "▼ EXPAND INTELLIGENCE TRAY"}
          </span>
        </button>

        {showTray && (
          <div className="ops-tray-content">
            <ResourcePanel />
            <AnalyticsChart incidents={allIncidents} />
          </div>
        )}
      </div>
    </div>
  );
}

export default DashboardHome;
