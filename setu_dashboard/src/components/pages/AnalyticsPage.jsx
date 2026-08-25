import {
  BarChart, Bar, PieChart, Pie, Cell,
  XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer,
} from "recharts";
import { NavIcons, ActionIcons } from "../../icons";

const PRIORITY_COLORS = { Critical: "#f87171", High: "#fb923c", Medium: "#fbbf24", Low: "#4ade80" };
const TYPE_COLOR = "#38bdf8";

function AnalyticsPage({ incidents }) {
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

  const total = incidents.length;
  const closed = incidents.filter((i) => i.status === "closed").length;
  const resolutionRate = total > 0 ? Math.round((closed / total) * 100) : 0;
  const avgReports = (() => {
    const withReports = incidents.filter((i) => i.reportCount > 1);
    if (withReports.length === 0) return null;
    const total = withReports.reduce((sum, i) => sum + i.reportCount, 0);
    return (total / withReports.length).toFixed(1);
  })();

  return (
    <div className="analytics-page">
      <div className="analytics-stat-row">
        <div className="analytics-stat">
          <p>Total Incidents</p>
          <h1>{total}</h1>
        </div>
        <div className="analytics-stat">
          <p>Resolution Rate</p>
          <h1>{resolutionRate}%</h1>
        </div>
        <div className="analytics-stat">
          <p>Currently Active</p>
          <h1>{total - closed}</h1>
        </div>
        {avgReports && (
          <div className="analytics-stat">
            <p>Avg Reports / Merged Incident</p>
            <h1>{avgReports}</h1>
          </div>
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
        </div>
      </div>
    </div>
  );
}

export default AnalyticsPage;
