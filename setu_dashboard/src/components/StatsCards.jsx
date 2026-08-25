// Trend arrows are computed from a real before/after comparison (see
// App.jsx's trends state, updated each successful poll) — never a
// hardcoded fake daily percentage.
//
// Rebuilt on MetricCard (src/components/ui/Primitives.jsx), which was
// already introduced and CSS-verified in the Block 1 redesign — this
// swap introduces ZERO new class names, only reuses .ds-metric-*
// rules already confirmed present in primitives.css.

import { PipelineIcons, CategoryIcons } from "../icons";
import { MetricCard } from "./ui/Primitives";

function StatsCards({ incidents, trends = {} }) {
  const medical = incidents.filter((i) => i.type === "Medical").length;
  const fire = incidents.filter((i) => i.type === "Fire").length;
  const flood = incidents.filter((i) => i.type === "Flood").length;

  return (
    <div className="cards">
      <MetricCard
        icon={CategoryIcons.medical}
        label="Total Medical Cases"
        value={medical}
        trend={trends.Medical}
        tone="critical"
      />
      <MetricCard
        icon={CategoryIcons.fire}
        label="Fire Incidents"
        value={fire}
        trend={trends.Fire}
        tone="critical"
      />
      <MetricCard
        icon={CategoryIcons.natural_disaster}
        label="Flood Alerts"
        value={flood}
        trend={trends.Flood}
        tone="network"
      />
    </div>
  );
}

export default StatsCards;
