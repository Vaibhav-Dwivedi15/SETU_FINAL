// Previously this panel showed fixed numbers (Flood Risk 82%, Fire Risk
// 41%, "Deploy two ambulances to Prayagraj") that never changed no
// matter what incidents existed — pure hardcoded demo text presented
// next to a "🤖 AI Risk Prediction" heading, which reads as an actual
// model output when it wasn't one. This version computes real numbers
// from the live incident list and is honest in its own caption about
// what it actually is: a live snapshot of the current incident mix, not
// a predictive model. The AI/ML Lead's real dedup/prioritization work
// is a separate, actual pipeline — this panel doesn't pretend to be that.
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
      <h2>📡 Live Situational Snapshot</h2>
      <p className="ai-panel-caption">Computed from currently active incidents — not a predictive model.</p>

      <div className="risk-card flood-risk">
        <h3>🌊 Flood Share</h3>
        <h1>{floodPct}%</h1>
        <p>
          {active.filter((i) => i.type === "Flood").length} active flood incident
          {active.filter((i) => i.type === "Flood").length === 1 ? "" : "s"} out of {total} total active.
        </p>
      </div>

      <div className="risk-card fire-risk">
        <h3>🔥 Fire Share</h3>
        <h1>{firePct}%</h1>
        <p>
          {active.filter((i) => i.type === "Fire").length} active fire incident
          {active.filter((i) => i.type === "Fire").length === 1 ? "" : "s"} out of {total} total active.
        </p>
      </div>

      <div className="risk-card medical-risk">
        <h3>🚑 Medical Demand</h3>
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
