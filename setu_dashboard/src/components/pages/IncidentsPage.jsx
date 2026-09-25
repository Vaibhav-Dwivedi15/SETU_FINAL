import { useState } from "react";
import { timeAgo } from "../../utils/timeAgo";
import { useTick } from "../../utils/useTick";
import { exportIncidentsToCsv } from "../../utils/exportCsv";
import { ActionIcons, MiscIcons, CategoryIcons, PipelineIcons } from "../../icons";
import { PriorityBadge, StatusBadge, EmptyState } from "../ui/Primitives";
import { categorizeIncident } from "../../utils/incidentCategories";

const PRIORITY_ORDER = { Critical: 4, High: 3, Medium: 2, Low: 1 };

function IncidentsPage({ incidents = [], onResolve, onSelectIncident, selectedIncidentId }) {
  const [sortBy, setSortBy] = useState("priority"); // "priority" | "time"
  const [statusFilter, setStatusFilter] = useState("all"); // "all" | "active" | "critical" | "closed"
  useTick();

  const filtered = incidents.filter((incident) => {
    if (statusFilter === "active") return incident.status !== "closed";
    if (statusFilter === "critical") return incident.priority === "Critical" && incident.status !== "closed";
    if (statusFilter === "closed") return incident.status === "closed";
    return true;
  });

  const sorted = [...filtered].sort((a, b) => {
    if (sortBy === "priority") {
      return (PRIORITY_ORDER[b.priority] || 0) - (PRIORITY_ORDER[a.priority] || 0);
    }
    return (b.id || 0) - (a.id || 0); // newest first
  });

  const totalCount = incidents.length;
  const criticalCount = incidents.filter((i) => i.priority === "Critical" && i.status !== "closed").length;
  const highCount = incidents.filter((i) => i.priority === "High" && i.status !== "closed").length;
  const activeCount = incidents.filter((i) => i.status !== "closed").length;
  const closedCount = incidents.filter((i) => i.status === "closed").length;

  return (
    <div className="incidents-page">
      {/* Top Incident Queue Summary Banner */}
      <div className="incidents-summary-strip">
        <div className="summary-chip" onClick={() => setStatusFilter("all")}>
          <span className="summary-chip-label">TOTAL QUEUE</span>
          <strong className="ds-mono">{totalCount}</strong>
        </div>

        <div 
          className={`summary-chip ${criticalCount > 0 ? "critical-alert" : ""}`}
          onClick={() => setStatusFilter("critical")}
        >
          <span className="summary-chip-label">CRITICAL ATTENTION</span>
          <strong className="ds-mono" style={{ color: criticalCount > 0 ? "var(--danger)" : undefined }}>
            {criticalCount}
          </strong>
        </div>

        <div className="summary-chip" onClick={() => setStatusFilter("active")}>
          <span className="summary-chip-label">HIGH URGENCY</span>
          <strong className="ds-mono" style={{ color: "var(--warning)" }}>{highCount}</strong>
        </div>

        <div className="summary-chip" onClick={() => setStatusFilter("active")}>
          <span className="summary-chip-label">ACTIVE OPERATIONS</span>
          <strong className="ds-mono">{activeCount}</strong>
        </div>

        <div className="summary-chip" onClick={() => setStatusFilter("closed")}>
          <span className="summary-chip-label">RESOLVED</span>
          <strong className="ds-mono" style={{ color: "var(--success)" }}>{closedCount}</strong>
        </div>
      </div>

      {/* Control & Sorting Toolbar */}
      <div className="incidents-page-header">
        <div className="incidents-filter-toggles">
          <button
            className={`incidents-filter-btn ${statusFilter === "all" ? "active" : ""}`}
            onClick={() => setStatusFilter("all")}
          >
            All ({totalCount})
          </button>
          <button
            className={`incidents-filter-btn ${statusFilter === "active" ? "active" : ""}`}
            onClick={() => setStatusFilter("active")}
          >
            Active ({activeCount})
          </button>
          <button
            className={`incidents-filter-btn ${statusFilter === "critical" ? "active" : ""}`}
            onClick={() => setStatusFilter("critical")}
            style={{ color: criticalCount > 0 && statusFilter !== "critical" ? "var(--danger)" : undefined }}
          >
            Critical ({criticalCount})
          </button>
          <button
            className={`incidents-filter-btn ${statusFilter === "closed" ? "active" : ""}`}
            onClick={() => setStatusFilter("closed")}
          >
            Resolved ({closedCount})
          </button>
        </div>

        <div className="sort-toggle">
          <span className="sort-label ds-metadata">SORT:</span>
          <button 
            className={sortBy === "priority" ? "active" : ""} 
            onClick={() => setSortBy("priority")}
          >
            Priority
          </button>
          <button 
            className={sortBy === "time" ? "active" : ""} 
            onClick={() => setSortBy("time")}
          >
            Newest
          </button>
          <button
            className="export-btn"
            onClick={() => exportIncidentsToCsv(sorted)}
            disabled={sorted.length === 0}
            title="Download current incident queue as CSV"
            style={{ display: "inline-flex", alignItems: "center", gap: 6 }}
          >
            <ActionIcons.download className="ds-icon-sm" aria-hidden="true" /> Export CSV
          </button>
        </div>
      </div>

      {/* Queue Column Headers */}
      <div className="queue-columns-header ds-metadata">
        <span className="col-severity">SEVERITY / STATUS</span>
        <span className="col-type">INCIDENT TYPE &amp; CATEGORY</span>
        <span className="col-location">SECTOR LOCATION</span>
        <span className="col-mesh">TRANSPORT &amp; RELAY</span>
        <span className="col-time">TIMESTAMP</span>
        <span className="col-actions">ACTION</span>
      </div>

      {/* Queue Body */}
      {sorted.length === 0 ? (
        <EmptyState
          icon={MiscIcons.empty}
          title="NO MATCHING INCIDENTS IN QUEUE"
          description="No incidents match your current search and filters. Try clearing or widening the filter criteria."
        />
      ) : (
        <div className="incidents-table">
          {sorted.map((incident) => {
            const priority = incident.priority || "Medium";
            const isClosed = incident.status === "closed";
            const isSelected = selectedIncidentId === incident.id;
            const catKey = categorizeIncident(incident);
            const CatIcon = CategoryIcons[catKey] || CategoryIcons.other || MiscIcons.alert;

            return (
              <div
                key={incident.id}
                className={`incident-queue-row priority-${priority.toLowerCase()} ${isClosed ? "resolved" : ""} ${isSelected ? "selected" : ""}`}
                onClick={() => onSelectIncident(incident)}
                tabIndex={0}
                role="button"
                aria-selected={isSelected}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault();
                    onSelectIncident(incident);
                  }
                }}
              >
                {/* Column 1: Severity & Status Badges */}
                <div className="col-severity col-cell">
                  <PriorityBadge priority={priority} size="sm" />
                  <StatusBadge status={isClosed ? "closed" : "active"} label={isClosed ? "Closed" : "Active"} />
                </div>

                {/* Column 2: Type, Category, Report Count */}
                <div className="col-type col-cell">
                  <CatIcon className="ds-icon-sm cat-indicator-icon" aria-hidden="true" />
                  <div className="incident-type-meta">
                    <strong className="queue-incident-title">{incident.type}</strong>
                    {incident.reportCount > 1 && (
                      <span className="report-count-badge" title="Merged reports of same event">
                        ×{incident.reportCount} reports
                      </span>
                    )}
                  </div>
                </div>

                {/* Column 3: Location */}
                <div className="col-location col-cell">
                  <ActionIcons.location className="ds-icon-sm location-pin-icon" aria-hidden="true" />
                  <span className="queue-location-text">{incident.city}</span>
                </div>

                {/* Column 4: Transport & Hop Count */}
                <div className="col-mesh col-cell">
                  {typeof incident.hopCount === "number" ? (
                    <span className={`queue-mesh-pill ${incident.hopCount > 0 ? "relayed" : "direct"} ds-mono`}>
                      <PipelineIcons.meshRelay className="ds-icon-sm" aria-hidden="true" />
                      {incident.hopCount > 0 ? `${incident.hopCount} Hops Mesh` : "Direct Uplink"}
                    </span>
                  ) : (
                    <span className="queue-mesh-pill unknown ds-mono">Standard Uplink</span>
                  )}
                </div>

                {/* Column 5: Time Ago */}
                <div className="col-time col-cell">
                  <span 
                    className="mono queue-time-text" 
                    title={incident.reportedAt ? new Date(incident.reportedAt).toLocaleString() : ""}
                  >
                    {timeAgo(incident.reportedAt)}
                  </span>
                </div>

                {/* Column 6: Actions */}
                <div className="col-actions col-cell">
                  <button 
                    className="inspect-action-btn"
                    onClick={(e) => {
                      e.stopPropagation();
                      onSelectIncident(incident);
                    }}
                    title="Open Incident Dossier"
                  >
                    Inspect →
                  </button>

                  {!isClosed && onResolve && (
                    <button
                      className="resolve-action-btn"
                      onClick={(e) => {
                        e.stopPropagation();
                        onResolve(incident.id);
                      }}
                      title="Mark Incident Resolved"
                    >
                      <ActionIcons.confirm className="ds-icon-sm" aria-hidden="true" />
                      <span>Resolve</span>
                    </button>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

export default IncidentsPage;
