import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
} from "recharts";
import { ActionIcons } from "../icons";

function AnalyticsChart({ incidents = [] }) {
  const data = [
    { category: "Medical", incidents: incidents.filter((i) => i.type === "Medical").length },
    { category: "Fire", incidents: incidents.filter((i) => i.type === "Fire").length },
    { category: "Flood", incidents: incidents.filter((i) => i.type === "Flood").length },
  ];

  return (
    <div className="analytics-card">
      <h3 style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <ActionIcons.chartPie className="ds-icon-sm" aria-hidden="true" /> Incident Statistics
      </h3>

      <ResponsiveContainer width="100%" height={250}>
        <LineChart data={data}>
          <CartesianGrid strokeDasharray="3 3" stroke="#1f2937" />
          <XAxis dataKey="category" stroke="#94a3b8" fontSize={12} />
          <YAxis stroke="#94a3b8" fontSize={12} allowDecimals={false} />
          <Tooltip contentStyle={{ background: "#151d2e", border: "1px solid #1f2937", borderRadius: 8, color: "#e8edf5" }} />
          <Line type="monotone" dataKey="incidents" stroke="#38bdf8" strokeWidth={3} dot={{ fill: "#38bdf8", r: 4 }} />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}

export default AnalyticsChart;
