import resourcesData from "../../data/resources";
import { NavIcons, CategoryIcons } from "../../icons";

// resourcesData.icon holds emoji strings (see data/resources.js) — mapped
// here to icons ALREADY confirmed working in earlier redesign blocks
// (CategoryIcons.medical/fire/violence, NavIcons.responseUnits), rather
// than importing fresh unverified icon names. "Rescue Drone" has no
// confirmed drone/aircraft icon available yet — NavIcons.responseUnits
// (a truck icon) is used as the closest confirmed stand-in until a
// verified aircraft icon name can be added.
const TYPE_ICON = {
  "Ambulance": CategoryIcons.medical,
  "Fire Truck": CategoryIcons.fire,
  "Police Unit": CategoryIcons.violence,
  "Rescue Drone": NavIcons.responseUnits,
};

function ResourcesPage() {
  return (
    <div className="resources-page">
      {resourcesData.map((res) => {
        const pctDeployed = Math.round((res.deployed / res.total) * 100);
        const Icon = TYPE_ICON[res.type] || NavIcons.resources;
        return (
          <div key={res.id} className="resource-detail-card">
            <div className="resource-detail-header">
              <span className="resource-detail-icon"><Icon className="ds-icon-md" aria-hidden="true" /></span>
              <div>
                <h3>{res.type}</h3>
                <p className="resource-detail-base">Base: {res.base}</p>
              </div>
              <span className="resource-detail-total">{res.total}</span>
            </div>

            <div className="resource-bar">
              <div className="resource-bar-fill" style={{ width: `${pctDeployed}%` }} />
            </div>

            <div className="resource-detail-stats">
              <span><i className="dot dot-deployed" /> Deployed: {res.deployed}</span>
              <span><i className="dot dot-available" /> Available: {res.available}</span>
            </div>
          </div>
        );
      })}
    </div>
  );
}

export default ResourcesPage;
