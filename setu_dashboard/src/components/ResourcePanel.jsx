import { NavIcons, CategoryIcons } from "../icons";
import resourcesData from "../data/resources";

const TYPE_ICON = {
  "Ambulance": CategoryIcons.medical,
  "Fire Truck": CategoryIcons.fire,
  "Police Unit": CategoryIcons.women_safety,
  "Rescue Drone": NavIcons.responseUnits,
};

function ResourcePanel() {
  const totalFleet = resourcesData.reduce((sum, r) => sum + r.total, 0);
  const totalAvail = resourcesData.reduce((sum, r) => sum + r.available, 0);

  return (
    <div className="resource-panel">
      <div className="resource-panel-header">
        <h3 className="ds-card-title" style={{ display: "flex", alignItems: "center", gap: 8, margin: 0 }}>
          <NavIcons.resources className="ds-icon-md" aria-hidden="true" style={{ color: "var(--accent)" }} />
          <span>Fleet Capacity &amp; Resource Readiness</span>
        </h3>
        <span className="ds-mono" style={{ fontSize: 11, color: "var(--text-dim)" }}>
          {totalAvail}/{totalFleet} READY ACROSS DISTRICT
        </span>
      </div>

      <div className="resource-cards-grid">
        {resourcesData.map((res) => {
          const Icon = TYPE_ICON[res.type] || NavIcons.resources;
          return (
            <div key={res.id} className="resource-card">
              <div className="resource-card-top">
                <Icon className="ds-icon-sm" aria-hidden="true" style={{ color: "var(--accent)" }} />
                <span className="resource-card-type">{res.type}s</span>
              </div>
              <div className="resource-card-stat">
                <span className="resource-card-avail ds-mono">{res.available}</span>
                <span className="resource-card-total ds-mono">/ {res.total} ready</span>
              </div>
              <div className="resource-card-base">
                <span className="resource-status-dot active" />
                <span>{res.base}</span>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

export default ResourcePanel;
