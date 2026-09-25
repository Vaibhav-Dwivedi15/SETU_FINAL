import RecoveryPage from './components/pages/RecoveryPage';
import { useState, useEffect, useCallback, useRef } from "react";
import incidentsData from "./data/incidents";
import { startIncidentPolling, resolveIncidentOnBackend } from "./services/api";
import { playAlertSound } from "./utils/alertSound";
import { timeAgo } from "./utils/timeAgo";
import "./App.css";
// Phase 4 styles kept in their own file rather than appended to the
// 2000-line App.css â€” easier to review, and trivially revertable.
import "./phase4.css";
// Frontend redesign (Block 1 â€” foundation): design tokens, icon
// registry consumers, and the v2 component styles they drive. Loaded
// after App.css/phase4.css so their tokens/overrides win.
import "./design-system.css";
import "./components/sidebar-v2.css";
import "./components/critical-alert-v2.css";
import "./components/pipeline-v2.css";
import "./components/pages/categories-v2.css";
import "./components/map-v2.css";

import Sidebar from "./components/Sidebar";
import NewAlertModal from "./components/NewAlertModal";
import IncidentDetailDrawer from "./components/IncidentDetailDrawer";
import ToastStack from "./components/ToastStack";
import CommandPalette from "./components/CommandPalette";
import NotificationCenter from "./components/NotificationCenter";
import ThemeToggle from "./components/ThemeToggle";
import CriticalAlertModal from "./components/CriticalAlertModal";
import { ThemeProvider } from "./context/ThemeContext";
import { LanguageProvider } from "./context/LanguageContext";
import LanguageSelector from "./components/LanguageSelector";
import { ActionIcons } from "./icons";
import { NetworkStatusPill } from "./components/ui/Primitives";

import DashboardHome from "./components/pages/DashboardHome";
import LiveMapPage from "./components/pages/LiveMapPage";
import IncidentsPage from "./components/pages/IncidentsPage";
import CategoriesPage from "./components/pages/CategoriesPage";
import AnalyticsPage from "./components/pages/AnalyticsPage";
import ResourcesPage from "./components/pages/ResourcesPage";
import TeamsPage from "./components/pages/TeamsPage";
import SettingsPage from "./components/pages/SettingsPage";

const cityCoordinates = {
  Prayagraj: { lat: 25.4358, lng: 81.8463 },
  Lucknow: { lat: 26.8467, lng: 80.9462 },
  Varanasi: { lat: 25.3176, lng: 82.9739 },
  Kanpur: { lat: 26.4499, lng: 80.3319 },
  Agra: { lat: 27.1767, lng: 78.0081 },
  Delhi: { lat: 28.6139, lng: 77.2090 },
};

// Redesign brief section 2 explicitly bans emoji as product iconography,
// and section 15 asks for concise operational status language. The page
// titles here used to lead with an emoji character despite every other
// surface (sidebar, cards, badges) already having moved to the Lucide
// icon registry in icons.js â€” this was the one place that slipped
// through. Titles are now plain operational text; the icon-carrying job
// belongs to the sidebar nav item for the same page, not the header.
const PAGE_TITLES = {
  dashboard: { title: "Emergency Response Dashboard", subtitle: "AI-powered disaster monitoring, live" },
  map: { title: "Live Map", subtitle: "All active and recent incidents, plotted in real time" },
  incidents: { title: "Incidents", subtitle: "Full incident log with search and filters" },
  categories: { title: "Incident Categories", subtitle: "Incidents grouped by emergency category" },
  analytics: { title: "Analytics", subtitle: "Trends and breakdowns across all reported incidents" },
  resources: { title: "Response Capacity Center", subtitle: "Deployment status of emergency response assets" },
  teams: { title: "Response Teams", subtitle: "Registered responder teams" },
  settings: { title: "Settings", subtitle: "Dashboard configuration" },
    recovery: { title: "After-Disaster Recovery", subtitle: "Field damage reports and missing persons registry" },
};

const DEFAULT_SETTINGS = { pollIntervalMs: 5000, notificationsEnabled: true, soundEnabled: true };
const TRACKED_TYPES = ["Medical", "Fire", "Flood"];
const PRIORITY_ORDER = { Critical: 4, High: 3, Medium: 2, Low: 1 };

function loadSettings() {
  try {
    const raw = localStorage.getItem("setu_dashboard_settings");
    if (!raw) return DEFAULT_SETTINGS;
    return { ...DEFAULT_SETTINGS, ...JSON.parse(raw) };
  } catch {
    return DEFAULT_SETTINGS;
  }
}

function App() {
  const [activePage, setActivePage] = useState("dashboard");
  const [showModal, setShowModal] = useState(false);
  const [selectedIncident, setSelectedIncident] = useState(null);
  const [incidents, setIncidents] = useState(incidentsData);
  const [search, setSearch] = useState("");
  const [typeFilter, setTypeFilter] = useState("All");
  const [priorityFilter, setPriorityFilter] = useState("All");
  const [showResolved, setShowResolved] = useState(false);
  const [viewMode, setViewMode] = useState("merged"); // "merged" | "raw"
  const [backendConnected, setBackendConnected] = useState(false);
  const [settings, setSettings] = useState(loadSettings);
  const [toasts, setToasts] = useState([]);
  const [notifications, setNotifications] = useState([]);
  const [trends, setTrends] = useState({});
  const [commandPaletteOpen, setCommandPaletteOpen] = useState(false);
  const [lastSyncedAt, setLastSyncedAt] = useState(null);

  // Phase 4: Critical incidents get a blocking, unmissable modal rather
  // than just another toast. Held as a QUEUE, not a single value â€”
  // several Critical incidents can arrive in one poll cycle, and
  // overwriting would silently drop all but the last one.
  const [criticalQueue, setCriticalQueue] = useState([]);

  const knownIdsRef = useRef(new Set(incidentsData.map((i) => i.id)));
  const hasLoadedOnceRef = useRef(false);
  const prevCountsRef = useRef(null);
  const searchInputRef = useRef(null);

  useEffect(() => {
    localStorage.setItem("setu_dashboard_settings", JSON.stringify(settings));
  }, [settings]);

  // Global Ctrl/Cmd+K to open the command palette from anywhere, and
  // "/" to jump straight into the search box (skipped while typing in
  // any input/textarea/select, so it doesn't hijack normal typing).
  useEffect(() => {
    function handleGlobalKeyDown(e) {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setCommandPaletteOpen((open) => !open);
        return;
      }
      const tag = document.activeElement?.tagName;
      const isTyping = tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT";
      if (e.key === "/" && !isTyping) {
        e.preventDefault();
        searchInputRef.current?.focus();
      }
    }
    window.addEventListener("keydown", handleGlobalKeyDown);
    return () => window.removeEventListener("keydown", handleGlobalKeyDown);
  }, []);

  // Real backend polling. Falls back to mock data automatically if the
  // backend isn't up yet. Also detects genuinely new incidents (not seen
  // on any previous poll) and raises a toast + persistent notification +
  // optional sound for them â€” skips the very first successful load so
  // switching from mock->real data doesn't fire a notification storm for
  // incidents that were already there.
  useEffect(() => {
    const stopPolling = startIncidentPolling(
      (freshIncidents) => {
        setBackendConnected(true);
        setLastSyncedAt(new Date().toISOString());
        setIncidents(freshIncidents);

        const newCounts = {};
        TRACKED_TYPES.forEach((t) => {
          newCounts[t] = freshIncidents.filter((i) => i.type === t).length;
        });
        if (prevCountsRef.current) {
          const delta = {};
          TRACKED_TYPES.forEach((t) => {
            delta[t] = newCounts[t] - prevCountsRef.current[t];
          });
          setTrends(delta);
        }
        prevCountsRef.current = newCounts;

        if (hasLoadedOnceRef.current) {
          const newOnes = freshIncidents.filter(
            (i) => i.status !== "closed" && !knownIdsRef.current.has(i.id)
          );
          if (newOnes.length > 0) {
            if (settings.notificationsEnabled) {
              setToasts((prev) => [
                ...prev,
                ...newOnes.map((i) => ({ id: `${i.id}-${Date.now()}`, type: i.type, city: i.city, priority: i.priority })),
              ]);
            }
            setNotifications((prev) => [
              ...newOnes.map((i) => ({
                id: `${i.id}-${Date.now()}`,
                type: i.type,
                city: i.city,
                priority: i.priority,
                at: new Date().toISOString(),
                read: false,
                incident: i,
              })),
              ...prev,
            ].slice(0, 50)); // cap history so this can't grow unbounded over a long demo session

            // Phase 4: escalate Critical-priority arrivals to the
            // blocking modal. Deliberately NOT gated on
            // notificationsEnabled â€” that setting governs routine toast
            // noise; a Critical emergency is exactly what a responder
            // opened this dashboard for and must not be suppressible by
            // a general "quiet" preference.
            const newCriticals = newOnes.filter((i) => i.priority === "Critical");
            if (newCriticals.length > 0) {
              setCriticalQueue((prev) => [...prev, ...newCriticals]);
            }

            if (settings.soundEnabled) {
              const worst = newOnes.reduce((acc, i) =>
                (PRIORITY_ORDER[i.priority] || 0) > (PRIORITY_ORDER[acc.priority] || 0) ? i : acc
              , newOnes[0]);
              playAlertSound(worst.priority);
            }
          }
        }
        freshIncidents.forEach((i) => knownIdsRef.current.add(i.id));
        hasLoadedOnceRef.current = true;
      },
      () => {
        setBackendConnected(false);
        setIncidents(incidentsData);
        hasLoadedOnceRef.current = true;
      },
      settings.pollIntervalMs
    );
    return stopPolling;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [settings.pollIntervalMs, settings.notificationsEnabled, settings.soundEnabled]);

  useEffect(() => {
    if (toasts.length === 0) return;
    const timer = setTimeout(() => setToasts((prev) => prev.slice(1)), 6000);
    return () => clearTimeout(timer);
  }, [toasts]);

  const baseFiltered = incidents.filter((item) => {
    const matchesSearch =
      item.type.toLowerCase().includes(search.toLowerCase()) ||
      item.city.toLowerCase().includes(search.toLowerCase());
    const matchesType = typeFilter === "All" || item.type === typeFilter;
    const matchesPriority = priorityFilter === "All" || item.priority === priorityFilter;
    const matchesStatus = showResolved || item.status !== "closed";
    return matchesSearch && matchesType && matchesPriority && matchesStatus;
  });

  // Merged view: collapses multiple reports of the same real-world
  // incident (grouped by clusterKey) into one card with a report count.
  // NOTE: against a live backend this is effectively a no-op, and
  // correctly so â€” the backend already deduplicates server-side into a
  // single Incident row, so there are no duplicates left to merge. It
  // still does real work against mock data.
  function mergeByCluster(items) {
    const groups = new Map();
    for (const item of items) {
      const key = item.clusterKey || item.id;
      if (!groups.has(key)) {
        groups.set(key, { ...item, reportCount: 1 });
      } else {
        const existing = groups.get(key);
        existing.reportCount += 1;
        if ((PRIORITY_ORDER[item.priority] || 0) > (PRIORITY_ORDER[existing.priority] || 0)) {
          Object.assign(existing, item, { reportCount: existing.reportCount });
        }
      }
    }
    return Array.from(groups.values());
  }

  const filteredIncidents = viewMode === "merged" ? mergeByCluster(baseFiltered) : baseFiltered;

  const incidentTypes = ["All", ...new Set(incidents.map((i) => i.type))];
  const priorityLevels = ["All", "Critical", "High", "Medium", "Low"];
  const openIncidentCount = incidents.filter((i) => i.status !== "closed").length;
  const criticalIncidentCount = incidents.filter((i) => i.status !== "closed" && i.priority === "Critical").length;

  function createIncident(newIncident) {
    const location = cityCoordinates[newIncident.city] || cityCoordinates.Prayagraj;
    const incident = {
      id: Date.now(),
      reportedAt: new Date().toISOString(),
      status: "active",
      ...newIncident,
      lat: location.lat,
      lng: location.lng,
    };
    knownIdsRef.current.add(incident.id);
    setIncidents((prev) => [...prev, incident]);
  }

  // Termination-trigger from the pipeline design: a verified responder
  // marks an incident resolved. Updates the UI immediately (optimistic)
  // and attempts the real backend call in parallel.
  const resolveIncident = useCallback((incidentId) => {
    setIncidents((prev) =>
      prev.map((i) => (i.id === incidentId ? { ...i, status: "closed" } : i))
    );
    resolveIncidentOnBackend(incidentId);
  }, []);

  const activeCritical = criticalQueue[0] || null;

  const dismissCritical = useCallback(() => {
    setCriticalQueue((prev) => prev.slice(1));
  }, []);

  const openCriticalDetails = useCallback(() => {
    setCriticalQueue((prev) => {
      if (prev.length > 0) setSelectedIncident(prev[0]);
      return prev.slice(1);
    });
  }, []);

  const pageInfo = PAGE_TITLES[activePage];
  const showFilterBar =
    activePage === "dashboard" ||
    activePage === "incidents" ||
    activePage === "categories" ||
    activePage === "map";

  return (
    <ThemeProvider>
    <LanguageProvider>
    <div className="app">
      <Sidebar
        activePage={activePage}
        onNavigate={setActivePage}
        backendConnected={backendConnected}
        openIncidentCount={openIncidentCount}
        lastSyncedAt={lastSyncedAt}
      />

      <main className="main">
        <header className="navbar">
          <div className="command-context">
            <h2 className="ds-page-title">{pageInfo.title}</h2>
            <div className="command-meta">
              <span>SECTOR: PRAYAGRAJ GRID • OPS CONSOLE</span>
              <span>•</span>
              <span className="ds-mono">915MHz LoRa MESH</span>
            </div>
          </div>

          <div className="command-telemetry-strip">
            <div className="telemetry-pill">
              <span className="telemetry-dot success" />
              <span>ACTIVE:</span>
              <strong>{openIncidentCount}</strong>
            </div>

            <div className={`telemetry-pill ${criticalIncidentCount > 0 ? "critical-active" : ""}`}>
              <span className={`telemetry-dot ${criticalIncidentCount > 0 ? "danger" : "success"}`} />
              <span>CRITICAL:</span>
              <strong>{criticalIncidentCount}</strong>
            </div>

            <NetworkStatusPill
              connected={backendConnected}
              lastSyncedAt={lastSyncedAt}
              formatTime={timeAgo}
            />
          </div>

          <div className="nav-right">
            {showFilterBar && (
              <>
                <input
                  ref={searchInputRef}
                  type="text"
                  placeholder="Search incidents... (/)"
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                />

                <select value={typeFilter} onChange={(e) => setTypeFilter(e.target.value)}>
                  {incidentTypes.map((t) => (
                    <option key={t} value={t}>{t}</option>
                  ))}
                </select>

                <select value={priorityFilter} onChange={(e) => setPriorityFilter(e.target.value)}>
                  {priorityLevels.map((p) => (
                    <option key={p} value={p}>{p === "All" ? "All Urgencies" : p}</option>
                  ))}
                </select>

                <div className="view-toggle">
                  <button
                    className={viewMode === "merged" ? "active" : ""}
                    onClick={() => setViewMode("merged")}
                    title="Collapse duplicate reports of the same incident"
                  >
                    Merged
                  </button>
                  <button
                    className={viewMode === "raw" ? "active" : ""}
                    onClick={() => setViewMode("raw")}
                    title="Show every individual report separately"
                  >
                    Raw
                  </button>
                </div>

                <label className="show-resolved-toggle">
                  <input
                    type="checkbox"
                    checked={showResolved}
                    onChange={(e) => setShowResolved(e.target.checked)}
                  />
                  Resolved
                </label>

                <button className="alert-btn" onClick={() => setShowModal(true)} style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
                  <ActionIcons.add className="ds-icon-sm" aria-hidden="true" /> + Report
                </button>
              </>
            )}

            <button className="cmdk-launcher" onClick={() => setCommandPaletteOpen(true)} title="Search everything (Ctrl/Cmd+K)" style={{ display: "inline-flex", alignItems: "center", gap: 5 }}>
              <ActionIcons.search className="ds-icon-sm" aria-hidden="true" /> <kbd>⌘K</kbd>
            </button>

            <NotificationCenter
              notifications={notifications}
              onMarkAllRead={() => setNotifications((prev) => prev.map((n) => ({ ...n, read: true })))}
              onClear={() => setNotifications([])}
              onSelect={(incident) => setSelectedIncident(incident)}
            />

            <LanguageSelector />

            <ThemeToggle />

            <div className="responder-pill" title="Active responder dispatcher session">
              <span className="responder-pill-badge">OPERATOR</span>
              <span className="ds-mono">#04 DISPATCH</span>
            </div>
          </div>
        </header>

        {/* key={activePage} forces React to remount this section's
            subtree on every nav change, which retriggers the
            .content's page-transition-in CSS animation (design-system.css)
            â€” redesign brief section 18 asked for page transitions and
            this was the one still missing. Respects prefers-reduced-motion
            via the existing global override in design-system.css. */}
        <section className="content" key={activePage}>
          {activePage === "dashboard" && (
            <DashboardHome
              allIncidents={incidents}
              filteredIncidents={filteredIncidents}
              onResolve={resolveIncident}
              onSelectIncident={setSelectedIncident}
              trends={trends}
            />
          )}
          {activePage === "map" && (
            <LiveMapPage incidents={filteredIncidents} onSelectIncident={setSelectedIncident} />
          )}
          {activePage === "incidents" && (
            <IncidentsPage
              incidents={filteredIncidents}
              onResolve={resolveIncident}
              onSelectIncident={setSelectedIncident}
            />
          )}
          {activePage === "categories" && (
            <CategoriesPage
              incidents={filteredIncidents}
              onResolve={resolveIncident}
              onSelectIncident={setSelectedIncident}
            />
          )}
          {activePage === "analytics" && <AnalyticsPage incidents={incidents} />}
          {activePage === "resources" && <ResourcesPage />}
          {activePage === "teams" && <TeamsPage />}
          {activePage === "recovery" && <RecoveryPage />}
          {activePage === "settings" && (
            <SettingsPage settings={settings} onChange={setSettings} backendConnected={backendConnected} />
          )}
        </section>
      </main>

      {showModal && (
        <NewAlertModal onClose={() => setShowModal(false)} onCreate={createIncident} />
      )}

      {selectedIncident && (
        <IncidentDetailDrawer
          incident={selectedIncident}
          onClose={() => setSelectedIncident(null)}
          onResolve={resolveIncident}
        />
      )}

      {/* Phase 4: blocking Critical-priority alert. Rendered above the
          detail drawer intentionally â€” a new Critical arriving while a
          responder reads another incident must not be missable. */}
      {activeCritical && (
        <CriticalAlertModal
          incident={activeCritical}
          onAcknowledge={dismissCritical}
          onViewDetails={openCriticalDetails}
        />
      )}

      <CommandPalette
        open={commandPaletteOpen}
        onClose={() => setCommandPaletteOpen(false)}
        onNavigate={setActivePage}
        incidents={incidents}
        onSelectIncident={setSelectedIncident}
        onOpenNewAlert={() => setShowModal(true)}
      />

      <ToastStack
        toasts={toasts}
        onDismiss={(id) => setToasts((prev) => prev.filter((t) => t.id !== id))}
      />
    </div>
    </LanguageProvider>
    </ThemeProvider>
  );
}

export default App;

