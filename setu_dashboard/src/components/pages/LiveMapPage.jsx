import MapView from "../MapView";
import { timeAgo } from "../../utils/timeAgo";
import { useTick } from "../../utils/useTick";
import { NavIcons, MiscIcons } from "../../icons";
import { EmptyState } from "../ui/Primitives";

function LiveMapPage({ incidents, onSelectIncident }) {
  useTick();
  const sorted = [...incidents].sort((a, b) => {
    const order = { Critical: 4, High: 3, Medium: 2, Low: 1 };
    return (order[b.priority] || 0) - (order[a.priority] || 0);
  });

  return (
    <div className="live-map-page">
      <div className="live-map-primary">
        <MapView incidents={incidents} onSelectIncident={onSelectIncident} tall />
      </div>

      <div className="live-map-rail">
        <h3 className="ds-card-title">Active on Map ({incidents.length})</h3>
        {sorted.length === 0 && (
          <EmptyState
            icon={MiscIcons.empty}
            title="NETWORK CLEAR"
            description="No active emergency reports are currently being received."
          />
        )}
        {sorted.map((incident) => (
          <button
            key={incident.id}
            className="rail-item"
            onClick={() => onSelectIncident(incident)}
          >
            <span className={`rail-dot dot-${(incident.priority || "medium").toLowerCase()}`} />
            <span className="rail-text">
              <strong>{incident.type}</strong>
              <span>{incident.city}</span>
            </span>
            <span className="mono rail-time">{timeAgo(incident.reportedAt)}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

export default LiveMapPage;
