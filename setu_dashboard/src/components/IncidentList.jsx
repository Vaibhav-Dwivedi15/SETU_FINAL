import { timeAgo } from "../utils/timeAgo";
import { useTick } from "../utils/useTick";

function IncidentList({ incidents, onResolve, onSelect }) {
  useTick(); // keeps "Xm ago" timestamps below advancing without a data refetch

  return (
    <div className="incident-list">
      <h2>🚨 Recent Incidents</h2>

      {incidents.length === 0 && (
        <div className="empty-state">
          <span className="empty-icon">🔍</span>
          No incidents match your current filters.
        </div>
      )}

      {incidents.map((incident) => {
        // Guard added — previously incident.priority.toLowerCase() would
        // throw if priority was ever missing/undefined (a real risk once
        // this connects to live backend data with a different field
        // shape than the mock data).
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
              <span className={`status-badge ${isClosed ? "closed" : "active"}`}>
                {isClosed ? "Closed" : "Active"}
              </span>
            </div>

            {/* Bug fix: Low-priority incidents previously fell through to
                the "yellow" (Medium) badge color since there was no
                explicit branch for "Low" — a Low and a Medium incident
                looked identical in the list. */}
            <span className={`badge ${
              priority === "Critical"
                ? "red"
                : priority === "High"
                ? "orange"
                : priority === "Low"
                ? "green"
                : "yellow"
            }`}>
              {priority}
            </span>

            <p>{incident.city}</p>
            <small className="mono">{timeAgo(incident.reportedAt)}</small>

            {!isClosed && onResolve && (
              <button
                className="resolve-btn"
                onClick={(e) => {
                  e.stopPropagation();
                  onResolve(incident.id);
                }}
              >
                ✓ Mark Resolved
              </button>
            )}
          </div>
        );
      })}
    </div>
  );
}

export default IncidentList;
