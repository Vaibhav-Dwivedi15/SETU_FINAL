// Trend arrows are now computed from a real before/after comparison
// (see App.jsx's trends state, updated each successful poll) instead of
// hardcoded "▲ 12% Today" text that never changed and wasn't tied to
// any actual data. With no historical/daily backend data to compare
// against, "since last update" is the honest thing to show — a fixed
// fake daily percentage would just be a made-up number.
function TrendLabel({ delta }) {
  if (delta === undefined || delta === null) {
    return <span className="trend-neutral">— since last update</span>;
  }
  if (delta > 0) return <span className="trend-up">▲ +{delta} since last update</span>;
  if (delta < 0) return <span className="trend-down">▼ {delta} since last update</span>;
  return <span className="trend-neutral">→ No change</span>;
}

function StatsCards({ incidents, trends = {} }) {
  const medical = incidents.filter((i) => i.type === "Medical").length;
  const fire = incidents.filter((i) => i.type === "Fire").length;
  const flood = incidents.filter((i) => i.type === "Flood").length;

  return (
    <div className="cards">
      <div className="card medical">
        <p>Total Medical Cases</p>
        <h1>{medical}</h1>
        <TrendLabel delta={trends.Medical} />
      </div>

      <div className="card fire">
        <p>Fire Incidents</p>
        <h1>{fire}</h1>
        <TrendLabel delta={trends.Fire} />
      </div>

      <div className="card flood">
        <p>Flood Alerts</p>
        <h1>{flood}</h1>
        <TrendLabel delta={trends.Flood} />
      </div>
    </div>
  );
}

export default StatsCards;
