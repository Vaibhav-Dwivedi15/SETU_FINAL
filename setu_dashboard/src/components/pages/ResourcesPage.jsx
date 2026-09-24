import { demoResources as resourcesData } from "../../demo/demoData";
import { NavIcons, CategoryIcons, StatusIcons, PipelineIcons } from "../../icons";
import { SectionHeader, MetricCard, EmptyState } from "../ui/Primitives";

// =====================================================
// SETU Dashboard — Response Capacity Center (v2)
// =====================================================
//
// Redesign brief section 12: turn the old flat AVAILABLE/DEPLOYED/
// TOTAL inventory list into a proper "Response Capacity Center" with
// a fleet-wide summary plus per-unit-type capacity visualization.
//
// Icons all come from the existing registry (icons.js) — no new icon
// package added. Police Unit / Rescue Drone were previously mapped to
// CategoryIcons.violence (a warning triangle — reads as "danger", and
// is the exact same icon already used for the Violence incident
// category elsewhere) and NavIcons.responseUnits (a plain truck — wrong
// vehicle type for an aerial drone). Swapped to icons already imported
// elsewhere in the registry that fit better semantically.
const TYPE_ICON = {
  "Ambulance": CategoryIcons.medical,
  "Fire Truck": CategoryIcons.fire,
  "Police Unit": CategoryIcons.women_safety,
  "Rescue Drone": PipelineIcons.meshRelay,
};

function readinessColor(pctAvailable) {
  if (pctAvailable >= 50) return "var(--success)";
  if (pctAvailable >= 20) return "var(--caution)";
  return "var(--danger)";
}

function ResourcesPage() {
  if (!resourcesData || resourcesData.length === 0) {
    return (
      <div className="resources-page-shell">
        <SectionHeader title="Response Capacity Center" description="Live fleet capacity across every response unit type." />
        <EmptyState
          icon={NavIcons.resources}
          title="NO RESOURCE DATA"
          description="No response units are currently registered."
        />
      </div>
    );
  }

  const totalAll = resourcesData.reduce((sum, r) => sum + r.total, 0);
  const deployedAll = resourcesData.reduce((sum, r) => sum + r.deployed, 0);
  const availableAll = resourcesData.reduce((sum, r) => sum + r.available, 0);
  const readinessAll = totalAll > 0 ? Math.round((availableAll / totalAll) * 100) : 0;

  return (
    <div className="resources-page-shell">
      <SectionHeader
        title="Response Capacity Center"
        description="Live fleet capacity across every response unit type."
      />

      <div className="ds-metric-row">
        <MetricCard icon={NavIcons.resources} label="Total Assets" value={totalAll} />
        <MetricCard icon={StatusIcons.active} label="Deployed" value={deployedAll} tone="critical" />
        <MetricCard icon={StatusIcons.confirmed} label="Available" value={availableAll} tone="community" />
        <MetricCard icon={NavIcons.networkHealth} label="Fleet Readiness" value={`${readinessAll}%`} tone="network" />
      </div>

      <div className="resources-page">
        {resourcesData.map((res) => {
          const pctDeployed = Math.round((res.deployed / res.total) * 100);
          const pctAvailable = Math.round((res.available / res.total) * 100);
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
                <span style={{ color: readinessColor(pctAvailable), fontWeight: 700 }}>{pctAvailable}% ready</span>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

export default ResourcesPage;
