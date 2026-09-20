// Trend arrows are computed from a real before/after comparison (see
// App.jsx's trends state, updated each successful poll) — never a
// hardcoded fake daily percentage.
//
// Rebuilt on MetricCard (src/components/ui/Primitives.jsx), which was
// already introduced and CSS-verified in the Block 1 redesign — this
// swap introduces ZERO new class names, only reuses .ds-metric-*
// rules already confirmed present in primitives.css.
//
// Redesign brief section 5 ("WHAT IS HAPPENING RIGHT NOW?") explicitly
// asks for Active emergencies and Critical emergencies to be visible on
// the dashboard as PRIMARY signal — this pass adds those two, computed
// live from the incidents already in memory (zero new API calls).
//
// HONEST SCOPE: the brief also lists "Community responders" as a
// dashboard metric. That count only exists per-incident, via
// fetchIncidentResponses(id) in services/api.js — there is no bulk
// "all responders across all active incidents" endpoint. Aggregating it
// here would mean firing one extra backend request PER active incident
// on every dashboard load and poll cycle. Given Ayush's cold-start
// findings (short client timeouts, Render free-tier sleep), adding an
// N+1 request pattern to the dashboard's hot path is exactly the wrong
// direction right now — it would make the timeout problem worse, not
// better. Flagged as a real gap, not silently added at the cost of
// backend load. Revisit once/if a bulk responder-count endpoint exists.
import { PipelineIcons, CategoryIcons, NavIcons, MiscIcons } from "../icons";
import { MetricCard } from "./ui/Primitives";

function StatsCards({ incidents, trends = {} }) {
  const active = incidents.filter((i) => i.status !== "closed");
  const activeCount = active.length;
  const criticalCount = active.filter((i) => i.priority === "Critical").length;

  const medical = incidents.filter((i) => i.type === "Medical").length;
  const fire = incidents.filter((i) => i.type === "Fire").length;
  const flood = incidents.filter((i) => i.type === "Flood").length;

  return (
    <div className="cards">
      <MetricCard
        icon={NavIcons.liveIncidents}
        label="Active Emergencies"
        value={activeCount}
        tone="network"
      />
      <MetricCard
        icon={MiscIcons.alert}
        label="Critical Emergencies"
        value={criticalCount}
        tone="critical"
      />
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
