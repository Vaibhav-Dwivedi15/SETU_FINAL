import { timeAgo } from "../utils/timeAgo";
import { useTick } from "../utils/useTick";
import { ActionIcons, MiscIcons } from "../icons";
import { LuCirclePlus, LuLink, LuCircleCheckBig } from "react-icons/lu";
import { EmptyState } from "./ui/Primitives";

const ACTION_META = {
  CREATED: { Icon: LuCirclePlus, label: "Incident created", className: "created" },
  MERGED: { Icon: LuLink, label: "Corroborating report merged", className: "merged" },
  CLOSED: { Icon: LuCircleCheckBig, label: "Incident closed", className: "closed" },
};

function IncidentTimeline({ history, loading }) {
  useTick();

  return (
    <div className="incident-timeline-panel">
      <h3 className="ds-section-title">Incident Timeline</h3>

      {loading && <p className="ds-supporting">Loading timeline…</p>}

      {!loading && history.length === 0 && (
        <EmptyState icon={MiscIcons.empty} title="No audit entries available" />
      )}

      {!loading && history.length > 0 && (
        <ol className="incident-timeline">
          {history.map((entry) => {
            const meta = ACTION_META[entry.action] || { Icon: MiscIcons.empty, label: entry.action, className: "" };
            const { Icon } = meta;
            return (
              <li key={entry.id} className={`timeline-entry timeline-${meta.className}`}>
                <span className="timeline-icon"><Icon className="ds-icon-sm" aria-hidden="true" /></span>
                <div className="timeline-body">
                  <strong>{meta.label}</strong>
                  {entry.detail && <span className="ds-supporting">{entry.detail}</span>}
                  {entry.packetId && (
                    <span className="ds-supporting ds-mono" title={entry.packetId}>packet {entry.packetId.slice(0, 8)}…</span>
                  )}
                  <span className="ds-mono timeline-time">{timeAgo(entry.createdAt)}</span>
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
