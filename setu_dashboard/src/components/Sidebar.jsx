import { NavIcons } from "../icons";
import { NetworkStatusPill } from "./ui/Primitives";
import { timeAgo } from "../utils/timeAgo";
import { useTick } from "../utils/useTick";
import { useLanguage } from "../context/LanguageContext";
import setuLogo from "../assets/setu-logo.png";

// Grouped IA, per the redesign brief's "Emergency Operations Console"
// structure â€” sections visually separate what were previously 8 flat
// items into their operational purpose.
const NAV_GROUPS = [
  {
    label: "OPERATIONS",
    items: [
      { key: "dashboard", icon: NavIcons.overview, labelKey: "nav.dashboard" },
      { key: "map", icon: NavIcons.liveMap, labelKey: "nav.map" },
      { key: "incidents", icon: NavIcons.liveIncidents, labelKey: "nav.incidents" },
    ],
  },
  {
    label: "INTELLIGENCE",
    items: [
      { key: "categories", icon: NavIcons.categories, labelKey: "nav.categories" },
      { key: "analytics", icon: NavIcons.analytics, labelKey: "nav.analytics" },
    ],
  },
  {
    label: "RECOVERY",
    items: [
      { key: "recovery", icon: NavIcons.responseCenter, labelKey: "nav.recovery" },
    ],
  },
  {
    label: "RESOURCES",
    items: [
      { key: "resources", icon: NavIcons.resources, labelKey: "nav.resources" },
      { key: "teams", icon: NavIcons.teams, labelKey: "nav.teams" },
    ],
  },
  {
    label: "SYSTEM",
    items: [
      { key: "settings", icon: NavIcons.settings, labelKey: "nav.settings" },
    ],
  },
];

function Sidebar({ activePage, onNavigate, backendConnected, openIncidentCount, lastSyncedAt }) {
  useTick(15000);
  const { t } = useLanguage();

  return (
    <aside className="sidebar ds-atmosphere">
      <div className="logo-row">
        <img src={setuLogo} alt="SETU" className="logo-mark-img" />
        <div>
          <h1 className="logo">SETU</h1>
          <span className="sidebar-tagline">Emergency Operations Console</span>
        </div>
      </div>

      <nav className="sidebar-nav">
        {NAV_GROUPS.map((group) => (
          <div key={group.label} className="sidebar-group">
            <p className="sidebar-group-label">{group.label}</p>
            <ul>
              {group.items.map((item) => {
                const Icon = item.icon;
                const isActive = activePage === item.key;
                return (
                  <li key={item.key}>
                    <button
                      className={`sidebar-nav-item ${isActive ? "active" : ""}`}
                      onClick={() => onNavigate(item.key)}
                      aria-current={isActive ? "page" : undefined}
                    >
                      {isActive && <span className="sidebar-active-indicator" aria-hidden="true" />}
                      <Icon className="ds-icon-md sidebar-nav-icon" aria-hidden="true" />
                      <span>{t(item.labelKey)}</span>
                      {item.key === "incidents" && openIncidentCount > 0 && (
                        <span className="nav-count-badge">{openIncidentCount}</span>
                      )}
                    </button>
                  </li>
                );
              })}
            </ul>
          </div>
        ))}
      </nav>

      <div className="sidebar-footer">
        <NetworkStatusPill
          connected={backendConnected}
          lastSyncedAt={lastSyncedAt}
          formatTime={timeAgo}
        />
      </div>
    </aside>
  );
}

export default Sidebar;

