// =====================================================
// SETU Dashboard
// Page : Categories
// =====================================================
//
// Phase 4. The team spec's category-based incident sections. See
// src/utils/incidentCategories.js for the important honesty note about
// where these nine categories come from — they are a dashboard-side
// presentation layer over the backend's smaller real enum, NOT fields
// the mesh reports.
//
// Empty categories are shown by default (collapsed, dimmed, with a "0"
// count) rather than hidden, because hiding them would misrepresent the
// system as covering categories it can't currently populate. There's a
// toggle to hide them for a cleaner demo view, but the default is the
// honest one.

import { useState } from "react";
import { CATEGORIES, groupByCategory } from "../../utils/incidentCategories";
import { timeAgo } from "../../utils/timeAgo";
import { useTick } from "../../utils/useTick";
import RelayTrace from "../RelayTrace";

const PRIORITY_ORDER = { Critical: 4, High: 3, Medium: 2, Low: 1 };

function badgeClass(priority) {
  if (priority === "Critical") return "red";
  if (priority === "High") return "orange";
  if (priority === "Low") return "green";
  return "yellow";
}

function CategorySection({ category, incidents, onResolve, onSelectIncident, defaultOpen }) {
  const [open, setOpen] = useState(defaultOpen);
  const isEmpty = incidents.length === 0;

  const sorted = [...incidents].sort(
    (a, b) => (PRIORITY_ORDER[b.priority] || 0) - (PRIORITY_ORDER[a.priority] || 0)
  );

  const criticalCount = incidents.filter((i) => i.priority === "Critical").length;

  return (
    <section className={`category-section ${isEmpty ? "category-empty" : ""} ${open ? "open" : ""}`}>
      <button
        className="category-header"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
      >
        <span className="category-icon" aria-hidden="true">{category.icon}</span>
        <span className="category-label">{category.label}</span>
        {criticalCount > 0 && (
          <span className="category-critical-badge" title={`${criticalCount} critical`}>
            {criticalCount} critical
          </span>
        )}
        <span className="category-count">{incidents.length}</span>
        <span className="category-chevron" aria-hidden="true">{open ? "▾" : "▸"}</span>
      </button>

      {open && (
        <div className="category-body">
          {isEmpty ? (
            <p className="category-empty-note">
              No incidents in this category.
              {category.backendTypes.length === 0 && (
                <span className="category-empty-reason">
                  {" "}This category has no matching type in the mesh packet spec — it can only be
                  populated by AI classification.
                </span>
              )}
            </p>
          ) : (
            <div className="category-incident-grid">
              {sorted.map((incident) => {
                const isClosed = incident.status === "closed";
                return (
                  <article
                    key={incident.id}
                    className={`category-incident-card priority-${(incident.priority || "medium").toLowerCase()} ${isClosed ? "resolved" : ""}`}
                    onClick={() => onSelectIncident(incident)}
                    role="button"
                    tabIndex={0}
                    onKeyDown={(e) => {
                      if (e.key === "Enter" || e.key === " ") {
                        e.preventDefault();
                        onSelectIncident(incident);
                      }
                    }}
                  >
                    <div className="category-card-top">
                      <span className={`badge ${badgeClass(incident.priority)}`}>
                        {incident.priority}
                      </span>
                      <span className={`status-badge ${isClosed ? "closed" : "active"}`}>
                        {isClosed ? "Closed" : "Active"}
                      </span>
                    </div>

                    <h4>{incident.type}</h4>
                    <p className="category-card-city">{incident.city}</p>
                    <small className="mono">{timeAgo(incident.reportedAt)}</small>

                    <RelayTrace hopCount={incident.hopCount} />

                    {!isClosed && onResolve && (
                      <button
                        className="resolve-btn"
                        onClick={(e) => {
                          e.stopPropagation();
                          onResolve(incident.id);
                        }}
                      >
                        ✓ Mark Resolved
                      </button>
                    )}
                  </article>
                );
              })}
            </div>
          )}
        </div>
      )}
    </section>
  );
}

function CategoriesPage({ incidents, onResolve, onSelectIncident }) {
  useTick();
  const [hideEmpty, setHideEmpty] = useState(false);

  const grouped = groupByCategory(incidents);
  const visibleCategories = hideEmpty
    ? CATEGORIES.filter((c) => grouped[c.key].length > 0)
    : CATEGORIES;

  return (
    <div className="categories-page">
      <div className="categories-page-header">
        <h3>
          {incidents.length} incident{incidents.length === 1 ? "" : "s"} across{" "}
          {CATEGORIES.filter((c) => grouped[c.key].length > 0).length} active categor
          {CATEGORIES.filter((c) => grouped[c.key].length > 0).length === 1 ? "y" : "ies"}
        </h3>
        <label className="show-resolved-toggle">
          <input
            type="checkbox"
            checked={hideEmpty}
            onChange={(e) => setHideEmpty(e.target.checked)}
          />
          Hide empty categories
        </label>
      </div>

      {visibleCategories.length === 0 && (
        <div className="empty-state">
          <span className="empty-icon">🔍</span>
          No incidents match your current filters.
        </div>
      )}

      {visibleCategories.map((category) => (
        <CategorySection
          key={category.key}
          category={category}
          incidents={grouped[category.key]}
          onResolve={onResolve}
          onSelectIncident={onSelectIncident}
          defaultOpen={grouped[category.key].length > 0}
        />
      ))}
    </div>
  );
}

export default CategoriesPage;
