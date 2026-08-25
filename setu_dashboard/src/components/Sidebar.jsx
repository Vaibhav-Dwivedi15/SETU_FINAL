import { timeAgo } from "../utils/timeAgo";
import { useTick } from "../utils/useTick";
import setuLogo from "../assets/setu-logo.png";
import { useLanguage } from "../context/LanguageContext";

const NAV_ITEMS = [
  { key: "dashboard", icon: "🏠", labelKey: "nav.dashboard" },
  { key: "map", icon: "🗺", labelKey: "nav.map" },
  { key: "incidents", icon: "🚨", labelKey: "nav.incidents" },
  // Phase 4: category-based incident sections, per the team spec.
  { key: "categories", icon: "🗂", labelKey: "nav.categories" },
  { key: "analytics", icon: "📊", labelKey: "nav.analytics" },
  { key: "resources", icon: "📍", labelKey: "nav.resources" },
  { key: "teams", icon: "👥", labelKey: "nav.teams" },
  { key: "settings", icon: "⚙", labelKey: "nav.settings" },
];

function Sidebar({ activePage, onNavigate, backendConnected, openIncidentCount, lastSyncedAt }) {
  useTick(15000); // keeps "Last synced Xs ago" advancing
  const { t } = useLanguage();
  return (
    <aside className="sidebar">
      <div className="logo-row">
        <img src={setuLogo} alt="SETU" className="logo-mark-img" />
        <h1 className="logo">SETU</h1>
      </div>

      <p className="menu-title">{t("nav.mainMenu")}</p>

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
            <span>{t(item.labelKey)}</span>
            {item.key === "incidents" && openIncidentCount > 0 && (
              <span className="nav-count-badge">{openIncidentCount}</span>
            )}
          </li>
        ))}
      </ul>

      <div className="sidebar-footer">
        <h4>{t("status.systemStatus")}</h4>
        <p className={backendConnected ? "status-live" : "status-offline"}>
          <span className="status-dot" />
          {backendConnected ? t("status.live") : t("status.offline")}
        </p>
        {lastSyncedAt && (
          <span className="last-synced">{t("status.lastSynced")} {timeAgo(lastSyncedAt)}</span>
        )}
      </div>
    </aside>
  );
}

export default Sidebar;
