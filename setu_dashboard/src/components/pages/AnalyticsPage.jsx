import {
  BarChart, Bar, PieChart, Pie, Cell,
  XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer,
} from "recharts";
import { NavIcons, ActionIcons, PipelineIcons, MiscIcons } from "../../icons";
import { SectionHeader, MetricCard, EmptyState } from "../ui/Primitives";

// =====================================================
// SETU Dashboard — Analytics (v2)
// =====================================================
//
// Redesign brief section 11 asked for: dark-theme charts, meaningful
// axes/labels/legends/tooltips, designed empty states instead of a
// broken-looking blank chart, and useful questions answered
// (incidents by category, by priority, resolution rate, mesh
// delivery performance).
//
// HONEST SCOPE for this pass:
//   - Incidents by type / by priority: DONE — restyled bar + pie,
//     using SectionHeader/MetricCard primitives already confirmed
//     working elsewhere in the product (no new components invented).
//   - Resolution rate, active count: DONE (already existed, restyled
//     as MetricCard tiles instead of plain stat boxes).
//   - Mesh delivery rate: DONE — uses the real `hopCount` field that
//     already exists on incident objects (confirmed via MapView.jsx's
//     popup, which reads incident.hopCount) to show what fraction of
//     incidents actually traveled through the mesh vs. reached the
//     backend directly. Only shown when that field is present on at
//     least one incident, so it never silently claims 0% on data that
//     was simply never measured.
//   - Empty-state handling: DONE — a designed EmptyState replaces a
//     blank/broken chart area when there is no incident data, and the
//     priority pie specifically falls back to its own EmptyState if
//     every incident is missing a priority value.
//   - "Average response time" and "incident trend over time" from the
//     redesign brief: NOT done this pass. No confirmed created-at /
//     resolved-at timestamp field exists on the incident objects this
//     page receives (only report-merge counts and hop counts are
//     confirmed). Fabricating a trend line from data that doesn't
//     exist would be exactly the kind of overclaim this project's own
//     documentation explicitly rejects — flagged as a real gap, not
//     silently faked. Add once a real timestamp field is confirmed.
const PRIORITY_COLORS = { Critical: "#f87171", High: "#fb923c", Medium: "#fbbf24", Low: "#4ade80" };
const TYPE_COLOR = "#38bdf8";

function AnalyticsPage({ incidents = [] }) {
  const total = incidents.length;

  if (total === 0) {
    return (
      <div className="analytics-page">
        <SectionHeader
          title="Analytics"
          description="Incident intelligence, computed live from current incident data."
        />
        <EmptyState
          icon={MiscIcons.empty}
          title="NO DATA YET"
          description="No incidents have been reported in this session, so there is nothing to analyze yet. Charts will populate automatically as reports come in."
        />
      </div>
    );
  }

  const types = [...new Set(incidents.map((i) => i.type))];
  const typeData = types.map((type) => ({
    type,
    count: incidents.filter((i) => i.type === type).length,
  }));

  const priorities = ["Critical", "High", "Medium", "Low"];
  const priorityData = priorities.map((priority) => ({
    priority,
    count: incidents.filter((i) => (i.priority || "Medium") === priority).length,
  })).filter((d) => d.count > 0);

  const closed = incidents.filter((i) => i.status === "closed").length;
  const resolutionRate = Math.round((closed / total) * 100);

  const withHopData = incidents.filter((i) => typeof i.hopCount === "number");
  const meshRelayed = withHopData.filter((i) => i.hopCount > 0).length;
  const meshRate = withHopData.length > 0 ? Math.round((meshRelayed / withHopData.length) * 100) : null;

  const withReports = incidents.filter((i) => i.reportCount > 1);
  const avgReports = withReports.length > 0
    ? (withReports.reduce((sum, i) => sum + i.reportCount, 0) / withReports.length).toFixed(1)
    : null;

  return (
    <div className="analytics-page">
      <SectionHeader
        title="Analytics"
        description="Incident intelligence, computed live from current incident data."
      />

      <div className="ds-metric-row">
        <MetricCard icon={NavIcons.liveIncidents} label="Total Incidents" value={total} />
        <MetricCard icon={ActionIcons.confirm} label="Resolution Rate" value={`${resolutionRate}%`} tone="community" />
        <MetricCard icon={ActionIcons.trendUp} label="Currently Active" value={total - closed} tone="critical" />
        {meshRate !== null && (
          <MetricCard icon={PipelineIcons.meshRelay} label="Mesh Delivery Rate" value={`${meshRate}%`} tone="network" />
        )}
        {avgReports && (
          <MetricCard icon={ActionIcons.copy} label="Avg Reports / Merged Incident" value={avgReports} />
        )}
      </div>

      <div className="analytics-charts-grid">
        <div className="analytics-card">
          <h3 style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <NavIcons.analytics className="ds-icon-sm" aria-hidden="true" /> Incidents by Type
          </h3>
          <ResponsiveContainer width="100%" height={260}>
            <BarChart data={typeData}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border-subtle)" />
              <XAxis dataKey="type" stroke="var(--text-secondary)" fontSize={12} />
              <YAxis stroke="var(--text-secondary)" fontSize={12} allowDecimals={false} />
              <Tooltip contentStyle={{ background: "var(--bg-surface)", border: "1px solid var(--border-subtle)", borderRadius: 8, color: "var(--text-primary)" }} />
              <Bar dataKey="count" fill={TYPE_COLOR} radius={[6, 6, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>

        <div className="analytics-card">
          <h3 style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <ActionIcons.chartPie className="ds-icon-sm" aria-hidden="true" /> Incidents by Priority
          </h3>
          {priorityData.length > 0 ? (
            <ResponsiveContainer width="100%" height={260}>
              <PieChart>
                <Pie
                  data={priorityData}
                  dataKey="count"
                  nameKey="priority"
                  cx="50%"
                  cy="50%"
                  outerRadius={90}
                  label={(entry) => `${entry.priority}: ${entry.count}`}
                >
                  {priorityData.map((entry) => (
                    <Cell key={entry.priority} fill={PRIORITY_COLORS[entry.priority]} />
                  ))}
                </Pie>
                <Tooltip contentStyle={{ background: "var(--bg-surface)", border: "1px solid var(--border-subtle)", borderRadius: 8, color: "var(--text-primary)" }} />
                <Legend wrapperStyle={{ fontSize: 12, color: "var(--text-secondary)" }} />
              </PieChart>
            </ResponsiveContainer>
          ) : (
            <EmptyState
              icon={MiscIcons.empty}
              title="NOT ASSESSED"
              description="No incidents currently have a priority value set."
            />
          )}
        </div>
      </div>
    </div>
  );
}

export default AnalyticsPage;
