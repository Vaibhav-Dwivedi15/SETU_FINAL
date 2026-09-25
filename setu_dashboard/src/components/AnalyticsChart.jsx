import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
} from "recharts";
import { ActionIcons } from "../icons";
import { useTheme } from "../context/ThemeContext";

function AnalyticsChart({ incidents = [] }) {
  const { theme } = useTheme();
  const isLight = theme === "light";

  const data = [
    { category: "Medical", incidents: incidents.filter((i) => i.type === "Medical").length },
    { category: "Fire", incidents: incidents.filter((i) => i.type === "Fire").length },
    { category: "Flood", incidents: incidents.filter((i) => i.type === "Flood").length },
  ];

  const gridColor = isLight ? "#cbd5e1" : "rgba(148, 163, 184, 0.15)";
  const axisColor = isLight ? "#475569" : "#94a3b8";
  const lineColor = isLight ? "#0284c7" : "#38bdf8";

  return (
    <div className="analytics-card">
      <h3 style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <ActionIcons.chartPie className="ds-icon-sm" aria-hidden="true" /> Incident Category Volume
      </h3>

      <ResponsiveContainer width="100%" height={250}>
        <LineChart data={data}>
          <CartesianGrid strokeDasharray="3 3" stroke={gridColor} />
          <XAxis dataKey="category" stroke={axisColor} fontSize={12} tickLine={false} />
          <YAxis stroke={axisColor} fontSize={12} allowDecimals={false} tickLine={false} />
          <Tooltip
            contentStyle={{
              background: isLight ? "#ffffff" : "#0e1626",
              border: isLight ? "1px solid #cbd5e1" : "1px solid rgba(148, 163, 184, 0.24)",
              borderRadius: 6,
              color: isLight ? "#0f172a" : "#f8fafc",
              fontSize: 12,
              boxShadow: "0 4px 12px rgba(0,0,0,0.15)",
            }}
          />
          <Line
            type="monotone"
            dataKey="incidents"
            stroke={lineColor}
            strokeWidth={2.5}
            dot={{ fill: lineColor, r: 4 }}
            activeDot={{ r: 6, stroke: lineColor }}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}

export default AnalyticsChart;
