// =====================================================
// SETU Dashboard
// Component : Community Response Panel
// =====================================================
//
// Phase 4, surfacing Phase 3's backend data. Shows which nearby SETU
// users responded to an incident from the mobile app, and how.
//
// PRIVACY: sender_id is a hex-encoded Ed25519 public key — it is a
// pseudonymous device identifier, not a name, but it's still an
// identifier and there's no reason a responder dashboard needs the full
// value on screen. Truncated for display; the full value is available on
// hover/copy for anyone who genuinely needs it for cross-referencing.
//
// Empty state matters here: "no responses yet" is a real, common, and
// completely fine state — not an error, and not something to fill with
// placeholder rows.

import { timeAgo } from "../utils/timeAgo";
import { useTick } from "../utils/useTick";

const RESPONSE_ICON = {
  NEARBY: "📍",
  CAN_HELP: "🤝",
  ALREADY_RESPONDING: "🏃",
  CALLED_EMERGENCY_SERVICES: "📞",
  NAVIGATING: "🧭",
};

function shortenSenderId(senderId) {
  if (!senderId) return "unknown";
  if (senderId.length <= 14) return senderId;
  return `${senderId.slice(0, 6)}…${senderId.slice(-4)}`;
}

function CommunityResponsePanel({ responses, loading }) {
  useTick();

  return (
    <div className="community-response-panel">
      <h3 className="drawer-section-title">
        Community Responses
        {responses.length > 0 && (
          <span className="drawer-section-count">{responses.length}</span>
        )}
      </h3>

      {loading && (
        <p className="community-response-empty">Loading responses…</p>
      )}

      {!loading && responses.length === 0 && (
        <p className="community-response-empty">
          No nearby SETU users have responded to this incident yet.
        </p>
      )}

      {!loading && responses.length > 0 && (
        <ul className="community-response-list">
          {responses.map((r) => (
            <li key={r.id} className={`community-response-item response-${r.responseType.toLowerCase()}`}>
              <span className="community-response-icon" aria-hidden="true">
                {RESPONSE_ICON[r.responseType] || "•"}
              </span>
              <div className="community-response-body">
                <strong>{r.responseLabel}</strong>
                <span className="community-response-meta mono" title={r.senderId}>
                  {shortenSenderId(r.senderId)} · {timeAgo(r.updatedAt || r.createdAt)}
                </span>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

export default CommunityResponsePanel;
