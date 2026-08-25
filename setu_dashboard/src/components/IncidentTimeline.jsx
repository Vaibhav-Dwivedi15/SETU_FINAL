// =====================================================
// SETU Dashboard
// Component : Incident Audit Timeline
// =====================================================
//
// Phase 4. Renders the backend's IncidentAuditLog trail (GET
// /incidents/{id}/history) — every CREATED / MERGED / CLOSED action in
// chronological order. This is real server-side audit data, not a
// client-side reconstruction.
//
// MERGED entries are the visible proof that duplicate detection is
// genuinely working: each one is another independent report of the same
// real-world emergency that got folded into this incident rather than
// creating a duplicate.

import { timeAgo } from "../utils/timeAgo";
import { useTick } from "../utils/useTick";

const ACTION_META = {
  CREATED: { icon: "🆕", label: "Incident created", className: "created" },
  MERGED: { icon: "🔗", label: "Corroborating report merged", className: "merged" },
  CLOSED: { icon: "✓", label: "Incident closed", className: "closed" },
};

function IncidentTimeline({ history, loading }) {
  useTick();

  return (
    <div className="incident-timeline-panel">
      <h3 className="drawer-section-title">
        Incident Timeline
        {history.length > 0 && (
          <span className="drawer-section-count">{history.length}</span>
        )}
      </h3>

      {loading && <p className="community-response-empty">Loading timeline…</p>}

      {!loading && history.length === 0 && (
        <p className="community-response-empty">
          No audit entries available for this incident.
        </p>
      )}

      {!loading && history.length > 0 && (
        <ol className="incident-timeline">
          {history.map((entry) => {
            const meta = ACTION_META[entry.action] || { icon: "•", label: entry.action, className: "" };
            return (
              <li key={entry.id} className={`timeline-entry timeline-${meta.className}`}>
                <span className="timeline-icon" aria-hidden="true">{meta.icon}</span>
                <div className="timeline-body">
                  <strong>{meta.label}</strong>
                  {entry.detail && <span className="timeline-detail">{entry.detail}</span>}
                  {entry.packetId && (
                    <span className="timeline-detail mono" title={entry.packetId}>
                      packet {entry.packetId.slice(0, 8)}…
                    </span>
                  )}
                  <span className="timeline-time mono">{timeAgo(entry.createdAt)}</span>
                </div>
              </li>
            );
          })}
        </ol>
      )}
    </div>
  );
}

export default IncidentTimeline;
