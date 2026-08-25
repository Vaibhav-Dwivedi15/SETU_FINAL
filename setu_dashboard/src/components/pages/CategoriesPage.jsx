import { useState } from "react";
import { CATEGORIES, groupByCategory } from "../../utils/incidentCategories";
import { timeAgo } from "../../utils/timeAgo";
import { useTick } from "../../utils/useTick";
import RelayTrace from "../RelayTrace";
import { CategoryIcons, AI_ONLY_CATEGORIES, ActionIcons } from "../../icons";
import { PriorityBadge, StatusBadge, EmptyState, SectionHeader } from "../ui/Primitives";
import { MiscIcons } from "../../icons";

const PRIORITY_ORDER = { Critical: 4, High: 3, Medium: 2, Low: 1 };

function CategorySection({ category, incidents, onResolve, onSelectIncident, defaultOpen }) {
  const [open, setOpen] = useState(defaultOpen);
  const isEmpty = incidents.length === 0;
  const isAiOnly = AI_ONLY_CATEGORIES.has(category.key);
  const Icon = CategoryIcons[category.key] || MiscIcons.alert;
  const Chevron = open ? ActionIcons.chevronDown : ActionIcons.chevronRight;

  const sorted = [...incidents].sort(
    (a, b) => (PRIORITY_ORDER[b.priority] || 0) - (PRIORITY_ORDER[a.priority] || 0)
  );
  const criticalCount = incidents.filter((i) => i.priority === "Critical").length;

  return (
    <section className={`cat-section ds-surface ${isEmpty ? "cat-section-empty" : ""} ${open ? "open" : ""}`}>
      <button className="cat-header" onClick={() => setOpen((o) => !o)} aria-expanded={open}>
        <div className={`cat-icon-badge ${isEmpty ? "dim" : ""}`}>
          <Icon className="ds-icon-md" aria-hidden="true" />
        </div>
        <div className="cat-header-text">
          <span className="ds-card-title">{category.label}</span>
          {isAiOnly && <span className="cat-ai-note">AI-classified only — no mesh packet field yet</span>}
        </div>
        {criticalCount > 0 && (
          <PriorityBadge priority="Critical" size="sm" />
        )}
        <span className="cat-count ds-mono">{incidents.length}</span>
        <Chevron className="ds-icon-sm cat-chevron" aria-hidden="true" />
      </button>

      {open && (
        <div className="cat-body">
          {isEmpty ? (
            <EmptyState
              icon={MiscIcons.empty}
              title="No incidents in this category"
              description={
                isAiOnly
                  ? "This category has no matching type in the mesh packet spec — it can only be populated by AI classification of the report's content."
                  : undefined
              }
            />
          ) : (
            <div className="cat-incident-grid">
              {sorted.map((incident) => {
                const isClosed = incident.status === "closed";
                return (
                  <article
                    key={incident.id}
                    className={`cat-incident-card priority-${(incident.priority || "medium").toLowerCase()} ${isClosed ? "resolved" : ""}`}
                    onClick={() => onSelectIncident(incident)}
                    role="button"
                    tabIndex={0}
                    onKeyDown={(e) => {
                      if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onSelectIncident(incident); }
                    }}
                  >
                    <div className="cat-card-top">
                      <PriorityBadge priority={incident.priority} size="sm" />
                      <StatusBadge status={isClosed ? "closed" : "active"} label={isClosed ? "Closed" : "Active"} />
                    </div>
                    <h4 className="ds-card-title">{incident.type}</h4>
                    <p className="ds-supporting cat-card-city">{incident.city}</p>
                    <small className="ds-mono cat-card-time">{timeAgo(incident.reportedAt)}</small>
                    <RelayTrace hopCount={incident.hopCount} />
                    {!isClosed && onResolve && (
                      <button
                        className="resolve-btn"
                        onClick={(e) => { e.stopPropagation(); onResolve(incident.id); }}
                      >
                        <ActionIcons.confirm className="ds-icon-sm" aria-hidden="true" /> Mark Resolved
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
  const activeCategoryCount = CATEGORIES.filter((c) => grouped[c.key].length > 0).length;
  const visibleCategories = hideEmpty ? CATEGORIES.filter((c) => grouped[c.key].length > 0) : CATEGORIES;

  return (
    <div className="categories-page">
      <SectionHeader
        title="Incident Categories"
        description={`${incidents.length} active report${incidents.length === 1 ? "" : "s"} across ${activeCategoryCount} categor${activeCategoryCount === 1 ? "y" : "ies"} — where are the problems?`}
        actions={
          <label className="show-resolved-toggle">
            <input type="checkbox" checked={hideEmpty} onChange={(e) => setHideEmpty(e.target.checked)} />
            Hide empty categories
          </label>
        }
      />

      {visibleCategories.length === 0 ? (
        <EmptyState icon={MiscIcons.empty} title="No incidents match your current filters" />
      ) : (
        visibleCategories.map((category) => (
          <CategorySection
            key={category.key}
            category={category}
            incidents={grouped[category.key]}
            onResolve={onResolve}
            onSelectIncident={onSelectIncident}
            defaultOpen={grouped[category.key].length > 0}
          />
        ))
      )}
    </div>
  );
}

export default CategoriesPage;
