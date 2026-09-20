// Computes real numbers from the live incident list — honest about
// being a live snapshot, not a predictive model. See original header
// note (unchanged below).
import { NavIcons, CategoryIcons, ActionIcons } from "../icons";

function AIPanel({ incidents = [] }) {
  const active = incidents.filter((i) => i.status !== "closed");
  const total = active.length;

  const pct = (type) => (total === 0 ? 0 : Math.round((active.filter((i) => i.type === type).length / total) * 100));
  const floodPct = pct("Flood");
  const firePct = pct("Fire");
  const medicalCount = active.filter((i) => i.type === "Medical").length;
  const medicalDemand = medicalCount === 0 ? "Low" : medicalCount <= 2 ? "Moderate" : "High";
  const medicalCritical = active.filter((i) => i.type === "Medical" && i.priority === "Critical").length;

  return (
    <div className="ai-panel">
      <h2 className="ds-card-title" style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <ActionIcons.refresh className="ds-icon-md" aria-hidden="true" /> Live Situational Snapshot
      </h2>
      <p className="ai-panel-caption">Computed from currently active incidents — not a predictive model.</p>

      <div className="risk-card flood-risk">
        <h3 style={{ display: "flex", alignItems: "center", gap: 6 }}>
          <CategoryIcons.natural_disaster className="ds-icon-sm" aria-hidden="true" /> Flood Share
        </h3>
        <h1>{floodPct}%</h1>
        <p>
          {active.filter((i) => i.type === "Flood").length} active flood incident
          {active.filter((i) => i.type === "Flood").length === 1 ? "" : "s"} out of {total} total active.
        </p>
      </div>

      <div className="risk-card fire-risk">
        <h3 style={{ display: "flex", alignItems: "center", gap: 6 }}>
          <CategoryIcons.fire className="ds-icon-sm" aria-hidden="true" /> Fire Share
        </h3>
        <h1>{firePct}%</h1>
        <p>
          {active.filter((i) => i.type === "Fire").length} active fire incident
          {active.filter((i) => i.type === "Fire").length === 1 ? "" : "s"} out of {total} total active.
        </p>
      </div>

      <div className="risk-card medical-risk">
        <h3 style={{ display: "flex", alignItems: "center", gap: 6 }}>
          <CategoryIcons.medical className="ds-icon-sm" aria-hidden="true" /> Medical Demand
        </h3>
        <h1>{medicalDemand}</h1>
        <p>
          {medicalCount} active medical case{medicalCount === 1 ? "" : "s"}
          {medicalCritical > 0 ? `, ${medicalCritical} critical` : ""}.
        </p>
      </div>
    </div>
  );
}

export default AIPanel;
