import { useState } from "react";
import { timeAgo } from "../../utils/timeAgo";
import { useTick } from "../../utils/useTick";
import { exportIncidentsToCsv } from "../../utils/exportCsv";

const PRIORITY_ORDER = { Critical: 4, High: 3, Medium: 2, Low: 1 };

function IncidentsPage({ incidents, onResolve, onSelectIncident }) {
  const [sortBy, setSortBy] = useState("priority"); // "priority" | "time"
  useTick();

  const sorted = [...incidents].sort((a, b) => {
    if (sortBy === "priority") {
      return (PRIORITY_ORDER[b.priority] || 0) - (PRIORITY_ORDER[a.priority] || 0);
    }
    return (b.id || 0) - (a.id || 0); // newest first — id is Date.now() for locally-created alerts
  });

  return (
    <div className="incidents-page">
      <div className="incidents-page-header">
        <h3>{incidents.length} Incident{incidents.length === 1 ? "" : "s"}</h3>
        <div className="sort-toggle">
          <span>Sort by:</span>
          <button className={sortBy === "priority" ? "active" : ""} onClick={() => setSortBy("priority")}>Priority</button>
          <button className={sortBy === "time" ? "active" : ""} onClick={() => setSortBy("time")}>Newest</button>
          <button
            className="export-btn"
            onClick={() => exportIncidentsToCsv(sorted)}
            disabled={sorted.length === 0}
            title="Download the current filtered list as CSV"
          >
            ⬇ Export CSV
          </button>
        </div>
      </div>

      {sorted.length === 0 && (
        <div className="empty-state">
          <span className="empty-icon">🔍</span>
          No incidents match your current filters.
        </div>
      )}

      <div className="incidents-table">
        {sorted.map((incident) => {
          const priority = incident.priority || "Medium";
          const isClosed = incident.status === "closed";
          return (
            <div
              key={incident.id}
              className={`incident-row priority-${priority.toLowerCase()} ${isClosed ? "resolved" : ""}`}
              onClick={() => onSelectIncident(incident)}
            >
              <span className={`rail-dot dot-${priority.toLowerCase()}`} />
              <div className="incident-row-main">
                <strong>{incident.type}</strong>
                <span className="incident-row-city">{incident.city}</span>
              </div>
              {incident.reportCount > 1 && (
                <span className="report-count-badge">×{incident.reportCount}</span>
              )}
              <span className={`status-badge ${isClosed ? "closed" : "active"}`}>
                {isClosed ? "Closed" : "Active"}
              </span>
              <span className="mono incident-row-time">{timeAgo(incident.reportedAt)}</span>
              {!isClosed && (
                <button
                  className="resolve-btn resolve-btn-inline"
                  onClick={(e) => {
                    e.stopPropagation();
                    onResolve(incident.id);
                  }}
                >
                  ✓ Resolve
                </button>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

export default IncidentsPage;
