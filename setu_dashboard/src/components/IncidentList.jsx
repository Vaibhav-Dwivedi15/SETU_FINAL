import { timeAgo } from "../utils/timeAgo";
import { useTick } from "../utils/useTick";
import RelayTrace from "./RelayTrace";
import { NavIcons, ActionIcons, MiscIcons } from "../icons";
import { PriorityBadge, StatusBadge, EmptyState } from "./ui/Primitives";

function IncidentList({ incidents, onResolve, onSelect }) {
  useTick(); // keeps "Xm ago" timestamps below advancing without a data refetch

  return (
    <div className="incident-list">
      <h2 className="ds-card-title" style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <NavIcons.liveIncidents className="ds-icon-md" aria-hidden="true" /> Recent Incidents
      </h2>

      {incidents.length === 0 && (
        <EmptyState
          icon={MiscIcons.empty}
          title="NO MATCHING INCIDENTS"
          description="No incidents match your current search and filters."
        />
      )}

      {incidents.map((incident) => {
        // Guard kept from v1 — priority can be missing/undefined once this
        // connects to live backend data with a different field shape than
        // the mock data.
        const priority = incident.priority || "Medium";
        const isClosed = incident.status === "closed";

        return (
          <div
            className={`incident ${priority.toLowerCase()} ${isClosed ? "resolved" : ""} ${onSelect ? "incident-clickable" : ""}`}
            key={incident.id}
            onClick={() => onSelect && onSelect(incident)}
          >
            <div className="incident-header">
              <h4>{incident.type}</h4>
              {incident.reportCount > 1 && (
                <span className="report-count-badge" title="Number of independent reports merged into this incident">
                  ×{incident.reportCount} reports
                </span>
              )}
              <StatusBadge status={isClosed ? "closed" : "active"} label={isClosed ? "Closed" : "Active"} />
            </div>

            <PriorityBadge priority={priority} />

            <p>{incident.city}</p>
            <small className="mono">{timeAgo(incident.reportedAt)}</small>

            <RelayTrace hopCount={incident.hopCount} />

            {!isClosed && onResolve && (
              <button
                className="resolve-btn"
                onClick={(e) => {
                  e.stopPropagation();
                  onResolve(incident.id);
                }}
                style={{ display: "inline-flex", alignItems: "center", gap: 6 }}
              >
                <ActionIcons.confirm className="ds-icon-sm" aria-hidden="true" /> Mark Resolved
              </button>
            )}
          </div>
        );
      })}
    </div>
  );
}

export default IncidentList;
