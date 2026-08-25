import { NavIcons, CategoryIcons } from "../icons";

function ResourcePanel() {
  return (
    <div className="resource-panel">
      <h2 style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <CategoryIcons.medical className="ds-icon-md" aria-hidden="true" /> Emergency Resources
      </h2>

      <div className="resource-card">
        <h3 style={{ display: "flex", alignItems: "center", gap: 6 }}>
          <CategoryIcons.medical className="ds-icon-sm" aria-hidden="true" /> Ambulances
        </h3>
        <h1>24</h1>
      </div>

      <div className="resource-card">
        <h3 style={{ display: "flex", alignItems: "center", gap: 6 }}>
          <CategoryIcons.fire className="ds-icon-sm" aria-hidden="true" /> Fire Trucks
        </h3>
        <h1>12</h1>
      </div>

      <div className="resource-card">
        <h3 style={{ display: "flex", alignItems: "center", gap: 6 }}>
          <CategoryIcons.violence className="ds-icon-sm" aria-hidden="true" /> Police Units
        </h3>
        <h1>36</h1>
      </div>

      <div className="resource-card">
        <h3 style={{ display: "flex", alignItems: "center", gap: 6 }}>
          <NavIcons.responseUnits className="ds-icon-sm" aria-hidden="true" /> Rescue Drones
        </h3>
        <h1>8</h1>
      </div>
    </div>
  );
}

export default ResourcePanel;
