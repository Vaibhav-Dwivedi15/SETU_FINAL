import { NavIcons, CategoryIcons } from "../icons";
import { demoResources as resourcesData } from "../demo/demoData";

// BUG FIX (typography/cohesion pass): this dashboard-mini widget used to
// have its unit counts hardcoded (24/12/36/8) directly in JSX, copy-pasted
// from data/resources.js at some earlier point. That's exactly the kind
// of drift the redesign brief's data-honesty principle warns about — if
// resources.js is ever updated, this widget would keep showing stale
// numbers silently, with no error. Now reads the same single source of
// truth the full Response Capacity Center page uses, so there is only
// ever one place that knows the real fleet numbers.
const TYPE_ICON = {
  "Ambulance": CategoryIcons.medical,
  "Fire Truck": CategoryIcons.fire,
  "Police Unit": CategoryIcons.violence,
  "Rescue Drone": NavIcons.responseUnits,
};

function ResourcePanel() {
  // Block 3: no backend source for resource inventory exists, so outside an explicit DEMO build
  // there is nothing real to show -- say so instead of showing invented fleet numbers.
  if (resourcesData.length === 0) {
    return (
      <div className="resource-panel">
        <h2 className="ds-card-title">Emergency Resources</h2>
        <p className="ds-supporting">No resource inventory source is connected.</p>
      </div>
    );
  }
  return (
    <div className="resource-panel">
      <h2 className="ds-card-title" style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <CategoryIcons.medical className="ds-icon-md" aria-hidden="true" /> Emergency Resources
      </h2>

      {resourcesData.map((res) => {
        const Icon = TYPE_ICON[res.type] || NavIcons.resources;
        return (
          <div key={res.id} className="resource-card">
            <h3 style={{ display: "flex", alignItems: "center", gap: 6 }}>
              <Icon className="ds-icon-sm" aria-hidden="true" /> {res.type}s
            </h3>
            <h1 className="ds-mono">{res.total}</h1>
          </div>
        );
      })}
    </div>
  );
}

export default ResourcePanel;
