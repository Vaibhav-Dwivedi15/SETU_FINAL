import { timeAgo } from "../utils/timeAgo";
import { useTick } from "../utils/useTick";
import { ActionIcons, MiscIcons, CategoryIcons } from "../icons";
import { PriorityBadge, StatusBadge, EmptyState } from "./ui/Primitives";
import { categorizeIncident } from "../utils/incidentCategories";

function IncidentList({ incidents, onResolve, onSelect, title = "Recent Incidents", hideHeader = false }) {
  useTick(); // keeps "Xm ago" timestamps advancing live

  return (
    <div className="incident-list-container">
      {!hideHeader && (
        <div className="incident-list-header">
          <h3 className="ds-card-title">{title}</h3>
          <span className="incident-count-pill ds-mono">{incidents.length}</span>
        </div>
      )}

      {incidents.length === 0 && (
        <EmptyState
          icon={MiscIcons.empty}
          title="NO MATCHING INCIDENTS"
          description="No incidents match the active operational criteria."
        />
      )}

      <div className="incident-rows-stream">
        {incidents.map((incident) => {
          const priority = incident.priority || "Medium";
          const isClosed = incident.status === "closed";
          const catKey = categorizeIncident(incident);
          const CatIcon = CategoryIcons[catKey] || CategoryIcons.other || MiscIcons.alert;

          return (
            <div
              className={`ops-incident-row priority-${priority.toLowerCase()} ${isClosed ? "resolved" : ""} ${onSelect ? "clickable" : ""}`}
              key={incident.id}
              onClick={() => onSelect && onSelect(incident)}
              tabIndex={0}
              role="button"
              onKeyDown={(e) => {
                if (e.key === "Enter" || e.key === " ") {
                  e.preventDefault();
                  onSelect && onSelect(incident);
                }
              }}
            >
              {/* Row Line 1: Type, Report Count, Time */}
              <div className="row-primary-line">
                <div className="row-type-group">
                  <CatIcon className="ds-icon-sm row-cat-icon" aria-hidden="true" />
                  <strong className="row-type">{incident.type}</strong>
                  {incident.reportCount > 1 && (
                    <span className="row-merged-badge" title="Merged reports">
                      ×{incident.reportCount}
                    </span>
                  )}
                </div>
                <span className="row-time ds-mono">{timeAgo(incident.reportedAt)}</span>
              </div>

              {/* Row Line 2: Location and Mesh Relay */}
              <div className="row-secondary-line">
                <span className="row-location">{incident.city}</span>
                {typeof incident.hopCount === "number" && (
                  <span className="row-mesh-tag ds-mono">
                    <ActionIcons.refresh className="ds-icon-sm" aria-hidden="true" />
                    {incident.hopCount > 0 ? `${incident.hopCount}H MESH` : "DIRECT"}
                  </span>
                )}
              </div>

              {/* Row Line 3: Priority & Status Badges */}
              <div className="row-tertiary-line">
                <div className="row-badges">
                  <PriorityBadge priority={priority} size="sm" />
                  <StatusBadge status={isClosed ? "closed" : "active"} label={isClosed ? "Closed" : "Active"} />
                  {incident.aiIncidentType && (
                    <span className="row-ai-badge">AI TRIAGED</span>
                  )}
                </div>

                {!isClosed && onResolve && (
                  <button
                    className="row-quick-resolve"
                    title="Mark Resolved"
                    onClick={(e) => {
                      e.stopPropagation();
                      onResolve(incident.id);
                    }}
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
    </div>
  );
}

export default IncidentList;
