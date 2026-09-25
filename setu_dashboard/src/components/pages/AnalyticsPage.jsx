import {
  BarChart, Bar, PieChart, Pie, Cell,
  XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer,
} from "recharts";
import { NavIcons, ActionIcons, PipelineIcons, MiscIcons, CategoryIcons } from "../../icons";
import { SectionHeader, MetricCard, EmptyState } from "../ui/Primitives";
import { useTheme } from "../../context/ThemeContext";

// =====================================================
// SETU Dashboard — Analytics (v2)
// Operational disaster intelligence:
// - Incident Category Breakdown
// - Priority Severity Distribution
// - Mesh Delivery & Resolution Trajectory
// =====================================================

function AnalyticsPage({ incidents = [] }) {
  const { theme } = useTheme();
  const isLight = theme === "light";
  const total = incidents.length;

  if (total === 0) {
    return (
      <div className="analytics-page">
        <SectionHeader
          title="Operational Analytics & Telemetry"
          description="Incident intelligence computed live from verified report streams."
        />
        <EmptyState
          icon={MiscIcons.empty}
          title="NO DATA RECORDED YET"
          description="No incidents have been reported in this operational session. Telemetry charts and distribution analytics will populate automatically as packets arrive."
        />
      </div>
    );
  }

  const priorityColors = {
    Critical: isLight ? "#dc2626" : "#ef4444",
    High: isLight ? "#d97706" : "#f59e0b",
    Medium: isLight ? "#ca8a04" : "#eab308",
    Low: isLight ? "#059669" : "#10b981",
  };

  const typeColor = isLight ? "#0284c7" : "#38bdf8";
  const gridColor = isLight ? "#cbd5e1" : "rgba(148, 163, 184, 0.15)";
  const axisColor = isLight ? "#334155" : "#cbd5e1";
  const tooltipStyle = {
    background: isLight ? "#ffffff" : "#0e1626",
    border: isLight ? "1px solid #cbd5e1" : "1px solid rgba(148, 163, 184, 0.24)",
    borderRadius: 6,
    color: isLight ? "#0f172a" : "#f8fafc",
    fontSize: 12,
    boxShadow: "0 4px 16px rgba(0,0,0,0.15)",
  };

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
  const directConnected = withHopData.filter((i) => i.hopCount === 0).length;
  const meshRate = withHopData.length > 0 ? Math.round((meshRelayed / withHopData.length) * 100) : null;

  const withReports = incidents.filter((i) => i.reportCount > 1);
  const avgReports = withReports.length > 0
    ? (withReports.reduce((sum, i) => sum + i.reportCount, 0) / withReports.length).toFixed(1)
    : null;

  const deliveryData = [
    { name: "Mesh Relayed", value: meshRelayed, fill: isLight ? "#0284c7" : "#0ea5e9" },
    { name: "Direct Uplink", value: directConnected, fill: isLight ? "#64748b" : "#94a3b8" },
    { name: "Resolved", value: closed, fill: isLight ? "#059669" : "#10b981" },
    { name: "Active Queue", value: total - closed, fill: isLight ? "#dc2626" : "#ef4444" },
  ].filter(d => d.value > 0);

  return (
    <div className="analytics-page">
      <SectionHeader
        title="Operational Analytics & Telemetry"
        description="Live incident intelligence, network delivery rates, and response metrics."
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
            <CategoryIcons.fire className="ds-icon-sm" aria-hidden="true" /> Incidents by Emergency Category
          </h3>
          <ResponsiveContainer width="100%" height={260}>
            <BarChart data={typeData} margin={{ top: 12, right: 12, left: -10, bottom: 5 }}>
              <CartesianGrid strokeDasharray="3 3" stroke={gridColor} />
              <XAxis dataKey="type" stroke={axisColor} fontSize={12} tickLine={false} />
              <YAxis stroke={axisColor} fontSize={12} allowDecimals={false} tickLine={false} />
              <Tooltip contentStyle={tooltipStyle} />
              <Bar dataKey="count" fill={typeColor} radius={[4, 4, 0, 0]} name="Incidents" />
            </BarChart>
          </ResponsiveContainer>
        </div>

        <div className="analytics-card">
          <h3 style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <ActionIcons.chartPie className="ds-icon-sm" aria-hidden="true" /> Severity Level Breakdown
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
                  innerRadius={45}
                  outerRadius={85}
                  paddingAngle={3}
                  label={({ priority, percent }) => `${priority} ${(percent * 100).toFixed(0)}%`}
                >
                  {priorityData.map((entry) => (
                    <Cell key={entry.priority} fill={priorityColors[entry.priority]} />
                  ))}
                </Pie>
                <Tooltip contentStyle={tooltipStyle} />
                <Legend wrapperStyle={{ fontSize: 12, color: axisColor }} />
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

        <div className="analytics-card">
          <h3 style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <PipelineIcons.meshRelay className="ds-icon-sm" aria-hidden="true" /> Network & Delivery Health
          </h3>
          <ResponsiveContainer width="100%" height={260}>
            <BarChart data={deliveryData} layout="vertical" margin={{ top: 10, right: 20, left: 20, bottom: 5 }}>
              <CartesianGrid strokeDasharray="3 3" stroke={gridColor} />
              <XAxis type="number" stroke={axisColor} fontSize={12} allowDecimals={false} tickLine={false} />
              <YAxis dataKey="name" type="category" stroke={axisColor} fontSize={12} tickLine={false} width={90} />
              <Tooltip contentStyle={tooltipStyle} />
              <Bar dataKey="value" radius={[0, 4, 4, 0]} name="Count">
                {deliveryData.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={entry.fill} />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>
    </div>
  );
}

export default AnalyticsPage;

