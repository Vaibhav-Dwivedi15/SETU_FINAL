import { timeAgo } from "../utils/timeAgo";
import { useTick } from "../utils/useTick";

const NAV_ITEMS = [
  { key: "dashboard", icon: "🏠", label: "Dashboard" },
  { key: "map", icon: "🗺", label: "Live Map" },
  { key: "incidents", icon: "🚨", label: "Incidents" },
  { key: "analytics", icon: "📊", label: "Analytics" },
  { key: "resources", icon: "📍", label: "Resources" },
  { key: "teams", icon: "👥", label: "Teams" },
  { key: "settings", icon: "⚙", label: "Settings" },
];

function Sidebar({ activePage, onNavigate, backendConnected, openIncidentCount, lastSyncedAt }) {
  useTick(15000); // keeps "Last synced Xs ago" advancing
  return (
    <aside className="sidebar">
      <div className="logo-row">
        <span className="logo-mark">◆</span>
        <h1 className="logo">SETU</h1>
      </div>

      <p className="menu-title">MAIN MENU</p>

      <ul>
        {NAV_ITEMS.map((item) => (
          <li
            key={item.key}
            className={activePage === item.key ? "active" : ""}
            onClick={() => onNavigate(item.key)}
            role="button"
            tabIndex={0}
            onKeyDown={(e) => {
              if (e.key === "Enter" || e.key === " ") onNavigate(item.key);
            }}
          >
            <span className="nav-icon">{item.icon}</span>
            <span>{item.label}</span>
            {item.key === "incidents" && openIncidentCount > 0 && (
              <span className="nav-count-badge">{openIncidentCount}</span>
            )}
          </li>
        ))}
      </ul>

      <div className="sidebar-footer">
        <h4>System Status</h4>
        <p className={backendConnected ? "status-live" : "status-offline"}>
          <span className="status-dot" />
          {backendConnected ? "Live (Backend Connected)" : "Offline (Mock Data)"}
        </p>
        {lastSyncedAt && (
          <span className="last-synced">Last synced {timeAgo(lastSyncedAt)}</span>
        )}
      </div>
    </aside>
  );
}

export default Sidebar;
