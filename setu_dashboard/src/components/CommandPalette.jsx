import { useEffect, useMemo, useRef, useState } from "react";

const PAGE_COMMANDS = [
  { key: "dashboard", icon: "🏠", label: "Go to Dashboard" },
  { key: "map", icon: "🗺", label: "Go to Live Map" },
  { key: "incidents", icon: "🚨", label: "Go to Incidents" },
  { key: "analytics", icon: "📊", label: "Go to Analytics" },
  { key: "resources", icon: "📍", label: "Go to Resources" },
  { key: "teams", icon: "👥", label: "Go to Teams" },
  { key: "settings", icon: "⚙", label: "Go to Settings" },
];

function CommandPalette({ open, onClose, onNavigate, incidents, onSelectIncident, onOpenNewAlert }) {
  const [query, setQuery] = useState("");
  const [activeIndex, setActiveIndex] = useState(0);
  const inputRef = useRef(null);

  useEffect(() => {
    if (open) {
      setQuery("");
      setActiveIndex(0);
      // slight delay so the element exists before focusing, since this
      // mounts at the same moment the open-triggering keydown is still bubbling
      requestAnimationFrame(() => inputRef.current?.focus());
    }
  }, [open]);

  const results = useMemo(() => {
    const q = query.trim().toLowerCase();

    const pageResults = PAGE_COMMANDS
      .filter((p) => !q || p.label.toLowerCase().includes(q))
      .map((p) => ({ type: "page", ...p }));

    const actionResults = (!q || "new alert report incident".includes(q) || "new alert".includes(q))
      ? [{ type: "action", key: "new-alert", icon: "➕", label: "Create New Alert" }]
      : [];

    const incidentResults = q
      ? incidents
          .filter((i) => `${i.type} ${i.city}`.toLowerCase().includes(q))
          .slice(0, 6)
          .map((i) => ({ type: "incident", key: `incident-${i.id}`, icon: "🚨", label: `${i.type} — ${i.city}`, incident: i }))
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
      <div className="cmdk-panel" role="dialog" aria-modal="true" aria-label="Command palette">
        <div className="cmdk-input-row">
          <span className="cmdk-search-icon">🔍</span>
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
          {results.map((r, idx) => (
            <div
              key={r.key}
              className={`cmdk-result ${idx === activeIndex ? "active" : ""}`}
              onMouseEnter={() => setActiveIndex(idx)}
              onClick={() => runResult(r)}
            >
              <span className="cmdk-result-icon">{r.icon}</span>
              <span>{r.label}</span>
              {r.type === "incident" && (
                <span className={`badge ${(r.incident.priority || "Medium").toLowerCase() === "critical" ? "red" : ""}`} style={{ marginLeft: "auto" }}>
                  {r.incident.priority || "Medium"}
                </span>
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

export default CommandPalette;
