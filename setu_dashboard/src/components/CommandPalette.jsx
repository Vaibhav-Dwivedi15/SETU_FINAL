import { useEffect, useMemo, useRef, useState } from "react";
import { NavIcons, ActionIcons } from "../icons";
import { PriorityBadge } from "./ui/Primitives";
import { useFocusTrap } from "../utils/useFocusTrap";

// Icon components (not emoji strings) — keys match App.jsx's activePage
// values exactly (unchanged, since onNavigate(result.key) sets that
// state directly). Mapped to the SAME NavIcons entries Sidebar.jsx
// already uses successfully for these pages.
const PAGE_COMMANDS = [
  { key: "dashboard", icon: NavIcons.overview, label: "Go to Dashboard" },
  { key: "map", icon: NavIcons.liveMap, label: "Go to Live Map" },
  { key: "incidents", icon: NavIcons.liveIncidents, label: "Go to Incidents" },
  { key: "analytics", icon: NavIcons.analytics, label: "Go to Analytics" },
  { key: "resources", icon: NavIcons.resources, label: "Go to Resources" },
  { key: "teams", icon: NavIcons.teams, label: "Go to Teams" },
  { key: "settings", icon: NavIcons.settings, label: "Go to Settings" },
];

function CommandPalette({ open, onClose, onNavigate, incidents, onSelectIncident, onOpenNewAlert }) {
  const [query, setQuery] = useState("");
  const [activeIndex, setActiveIndex] = useState(0);
  const inputRef = useRef(null);
  const trapRef = useFocusTrap(open);

  useEffect(() => {
    if (open) {
      setQuery("");
      setActiveIndex(0);
      requestAnimationFrame(() => inputRef.current?.focus());
    }
  }, [open]);

  const results = useMemo(() => {
    const q = query.trim().toLowerCase();

    const pageResults = PAGE_COMMANDS
      .filter((p) => !q || p.label.toLowerCase().includes(q))
      .map((p) => ({ type: "page", ...p }));

    const actionResults = (!q || "new alert report incident".includes(q) || "new alert".includes(q))
      ? [{ type: "action", key: "new-alert", icon: ActionIcons.add, label: "Create New Alert" }]
      : [];

    const incidentResults = q
      ? incidents
          .filter((i) => `${i.type} ${i.city}`.toLowerCase().includes(q))
          .slice(0, 6)
          .map((i) => ({ type: "incident", key: `incident-${i.id}`, icon: NavIcons.liveIncidents, label: `${i.type} — ${i.city}`, incident: i }))
      : [];

    return [...actionResults, ...pageResults, ...incidentResults];
  }, [query, incidents]);

  useEffect(() => {
    setActiveIndex(0);
  }, [query]);

  function runResult(result) {
    if (!result) return;
    if (result.type === "page") onNavigate(result.key);
    if (result.type === "action" && result.key === "new-alert") onOpenNewAlert();
    if (result.type === "incident") {
      onNavigate("incidents");
      onSelectIncident(result.incident);
    }
    onClose();
  }

  function handleKeyDown(e) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setActiveIndex((i) => Math.min(i + 1, results.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActiveIndex((i) => Math.max(i - 1, 0));
    } else if (e.key === "Enter") {
      e.preventDefault();
      runResult(results[activeIndex]);
    } else if (e.key === "Escape") {
      onClose();
    }
  }

  if (!open) return null;

  return (
    <div className="cmdk-backdrop" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="cmdk-panel" ref={trapRef} role="dialog" aria-modal="true" aria-label="Command palette">
        <div className="cmdk-input-row">
          <span className="cmdk-search-icon"><ActionIcons.search className="ds-icon-sm" aria-hidden="true" /></span>
          <input
            ref={inputRef}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Search pages, incidents, or type a command..."
          />
          <kbd>ESC</kbd>
        </div>

        <div className="cmdk-results">
          {results.length === 0 && (
            <div className="cmdk-empty">No matches for "{query}"</div>
          )}
          {results.map((r, idx) => {
            const Icon = r.icon;
            return (
              <div
                key={r.key}
                className={`cmdk-result ${idx === activeIndex ? "active" : ""}`}
                onMouseEnter={() => setActiveIndex(idx)}
                onClick={() => runResult(r)}
              >
                <span className="cmdk-result-icon"><Icon className="ds-icon-sm" aria-hidden="true" /></span>
                <span>{r.label}</span>
                {r.type === "incident" && (
                  <span style={{ marginLeft: "auto" }}>
                    <PriorityBadge priority={r.incident.priority || "Medium"} size="sm" />
                  </span>
                )}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

export default CommandPalette;
