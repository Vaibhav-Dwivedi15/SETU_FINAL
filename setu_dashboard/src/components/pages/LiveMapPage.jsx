import { useState } from "react";
import MapView from "../MapView";
import { timeAgo } from "../../utils/timeAgo";
import { useTick } from "../../utils/useTick";
import { NavIcons, MiscIcons, ActionIcons } from "../../icons";
import { EmptyState } from "../ui/Primitives";

function LiveMapPage({ incidents = [], onSelectIncident, selectedIncidentId }) {
  useTick();
  const [railFilter, setRailFilter] = useState("all"); // "all" | "critical" | "active"
  const [railSearch, setRailSearch] = useState("");

  const filtered = incidents.filter((incident) => {
    const matchesSearch =
      incident.type.toLowerCase().includes(railSearch.toLowerCase()) ||
      incident.city.toLowerCase().includes(railSearch.toLowerCase());
    
    if (!matchesSearch) return false;
    if (railFilter === "critical") return incident.priority === "Critical" && incident.status !== "closed";
    if (railFilter === "active") return incident.status !== "closed";
    return true;
  });

  const sorted = [...filtered].sort((a, b) => {
    const order = { Critical: 4, High: 3, Medium: 2, Low: 1 };
    return (order[b.priority] || 0) - (order[a.priority] || 0);
  });

  const criticalCount = incidents.filter((i) => i.priority === "Critical" && i.status !== "closed").length;
  const activeCount = incidents.filter((i) => i.status !== "closed").length;

  return (
    <div className="live-map-page">
      <div className="live-map-primary">
        <MapView
          incidents={incidents}
          onSelectIncident={onSelectIncident}
          selectedIncidentId={selectedIncidentId}
          tall
        />
      </div>

      <div className="live-map-rail">
        <div className="rail-header">
          <h3 className="ds-card-title">Geospatial Targets ({sorted.length})</h3>
          <span className="ds-mono rail-total-count">{incidents.length} TOTAL</span>
        </div>

        {/* Rail Quick Toggles */}
        <div className="rail-filter-tabs">
          <button
            className={`rail-filter-btn ${railFilter === "all" ? "active" : ""}`}
            onClick={() => setRailFilter("all")}
          >
            All ({incidents.length})
          </button>
          <button
            className={`rail-filter-btn ${railFilter === "critical" ? "active" : ""}`}
            onClick={() => setRailFilter("critical")}
            style={{ color: criticalCount > 0 && railFilter !== "critical" ? "var(--danger)" : undefined }}
          >
            Critical ({criticalCount})
          </button>
          <button
            className={`rail-filter-btn ${railFilter === "active" ? "active" : ""}`}
            onClick={() => setRailFilter("active")}
          >
            Active ({activeCount})
          </button>
        </div>

        {/* Rail Search */}
        <div className="rail-search-box">
          <ActionIcons.search className="ds-icon-sm" aria-hidden="true" />
          <input
            type="text"
            placeholder="Filter targets..."
            value={railSearch}
            onChange={(e) => setRailSearch(e.target.value)}
            className="rail-search-input"
            aria-label="Filter targets on map"
          />
        </div>

        {/* Targets List */}
        <div className="rail-list">
          {sorted.length === 0 && (
            <EmptyState
              icon={MiscIcons.empty}
              title="NO TARGETS FOUND"
              description="No active incidents match your filter. Try switching to 'All' or clearing search."
            />
          )}

          {sorted.map((incident) => {
            const isSelected = selectedIncidentId === incident.id;
            const priority = (incident.priority || "medium").toLowerCase();
            const isClosed = incident.status === "closed";

            return (
              <button
                key={incident.id}
                className={`rail-item ${isSelected ? "selected" : ""} ${isClosed ? "closed" : ""}`}
                onClick={() => onSelectIncident(incident)}
                title={`Inspect ${incident.type} in ${incident.city}`}
              >
                <span className={`rail-dot dot-${priority}`} />
                <div className="rail-text">
                  <div className="rail-title-row">
                    <strong>{incident.type}</strong>
                    {incident.reportCount > 1 && (
                      <span className="rail-badge">×{incident.reportCount}</span>
                    )}
                  </div>
                  <span className="rail-sub">{incident.city}</span>
                </div>
                <div className="rail-meta">
                  <span className="mono rail-time">{timeAgo(incident.reportedAt)}</span>
                  {typeof incident.hopCount === "number" && (
                    <span className="rail-hop-tag ds-mono">
                      {incident.hopCount > 0 ? `${incident.hopCount}H` : "DIR"}
                    </span>
                  )}
                </div>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

export default LiveMapPage;
