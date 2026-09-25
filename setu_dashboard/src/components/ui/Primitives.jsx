// =====================================================
// SETU Dashboard — Core UI primitives
// =====================================================
//
// Shared building blocks so severity/status/empty-state treatment is
// defined ONCE and every page inherits it, instead of each page
// reimplementing its own badge/empty-state styling (the exact
// duplication the redesign brief calls out).

import { StatusIcons, MiscIcons } from "../../icons";

const PRIORITY_META = {
  Critical: { key: "critical", label: "Critical" },
  High: { key: "high", label: "High" },
  Medium: { key: "medium", label: "Medium" },
  Low: { key: "low", label: "Low" },
};

/** Severity badge. Never color-only — always icon + label + shape,
 *  per the redesign brief's accessibility requirement (don't rely on
 *  color alone for emergency states). */
export function PriorityBadge({ priority, size = "md" }) {
  const meta = PRIORITY_META[priority] || PRIORITY_META.Medium;
  return (
    <span className={`ds-priority-badge ds-priority-${meta.key} ds-badge-${size}`}>
      <span className="ds-priority-dot" aria-hidden="true" />
      {meta.label}
    </span>
  );
}

/** Confirmed / unknown / pending / active / closed / failed —
 *  the three-state pipeline vocabulary (see DeliveryStatusPanel)
 *  generalized into one reusable badge for use anywhere. */
export function StatusBadge({ status, label }) {
  const Icon = StatusIcons[status] || StatusIcons.unknown;
  return (
    <span className={`ds-status-badge ds-status-${status}`}>
      <Icon className="ds-icon-sm" aria-hidden="true" />
      {label || status}
    </span>
  );
}

/** Category chip — icon + label, used on incident cards / detail
 *  drawer / category page. isAiOnly renders a subtle "AI-classified"
 *  marker so it's never confused with a backend-native category. */
export function CategoryChip({ icon: Icon, label, isAiOnly }) {
  return (
    <span className="ds-category-chip">
      <Icon className="ds-icon-sm" aria-hidden="true" />
      {label}
      {isAiOnly && <span className="ds-category-chip-ai" title="Populated via AI classification only">AI</span>}
    </span>
  );
}

/** Every empty state in the product renders through this — designed,
 *  never a blank area or unstyled text (redesign brief section 19). */
export function EmptyState({ icon: Icon = MiscIcons.empty, title, description, action }) {
  return (
    <div className="ds-empty-state">
      <div className="ds-empty-icon"><Icon className="ds-icon-lg" aria-hidden="true" /></div>
      <p className="ds-empty-title">{title}</p>
      {description && <p className="ds-empty-description">{description}</p>}
      {action && <div className="ds-empty-action">{action}</div>}
    </div>
  );
}

/** Section label used above any grouped content — page-level heading
 *  hierarchy piece (redesign brief section 4/16). */
export function SectionHeader({ title, description, actions }) {
  return (
    <div className="ds-section-header">
      <div>
        <h2 className="ds-page-title">{title}</h2>
        {description && <p className="ds-supporting" style={{ marginTop: 4 }}>{description}</p>}
      </div>
      {actions && <div className="ds-section-header-actions">{actions}</div>}
    </div>
  );
}

/** Top-line metric card (active emergencies / critical count / etc.)
 *  — replaces ad-hoc stat boxes with one consistent, icon-led format. */
export function MetricCard({ icon: Icon, label, value, trend, tone = "neutral" }) {
  return (
    <div className={`ds-metric-card ds-metric-${tone} ds-surface`}>
      <div className="ds-metric-icon"><Icon className="ds-icon-md" aria-hidden="true" /></div>
      <div className="ds-metric-body">
        <span className="ds-metadata">{label}</span>
        <span className="ds-metric-value ds-mono">{value}</span>
        {trend != null && (
          <span className={`ds-metric-trend ${trend > 0 ? "up" : trend < 0 ? "down" : ""}`}>
            {trend === 0 ? "— no change" : `${trend > 0 ? "+" : ""}${trend} since last sync`}
          </span>
        )}
      </div>
    </div>
  );
}

/** Live-state pill for the header / sidebar footer — replaces the
 *  plain "Live (Backend Connected)" text line with an operational
 *  status indicator (redesign brief section 4). */
export function NetworkStatusPill({ connected, lastSyncedAt, formatTime }) {
  return (
    <div
      className={`ds-network-pill ${connected ? "online" : "offline"}`}
      title={connected ? "Backend API connected and streaming incident telemetry" : "Operating in offline mode with verified local fallback incidents"}
    >
      <span className="ds-network-pulse" aria-hidden="true" />
      <span className="ds-network-pill-label">{connected ? "ONLINE" : "OFFLINE"}</span>
      {connected && lastSyncedAt && (
        <span className="ds-network-pill-sync ds-mono">{formatTime(lastSyncedAt)}</span>
      )}
    </div>
  );
}
