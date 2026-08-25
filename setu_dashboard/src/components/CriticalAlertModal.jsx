// =====================================================
// SETU Dashboard
// Component : Critical Alert Modal
// =====================================================
//
// Phase 4. The team spec calls for high-priority incidents to get a
// PROMINENT popup, not just another line in the incident log. Toasts
// (ToastStack) already handle routine new-incident notifications; this
// is deliberately heavier — a centered, blocking, unmissable modal that
// a responder has to acknowledge.
//
// Only fires for Critical. High/Medium/Low continue to use the existing
// toast path — escalating everything defeats the point of escalation.
//
// The acknowledgement wording is the spec's own exit-node message:
// it confirms to the responder that the report genuinely completed its
// mesh journey and reached the network.

import { useEffect } from "react";
import RelayTrace from "./RelayTrace";

export const EXIT_NODE_ACK_MESSAGE =
  "Emergency information successfully reached the SETU network. Thank you for helping connect someone in need.";

function CriticalAlertModal({ incident, onAcknowledge, onViewDetails }) {
  useEffect(() => {
    function handleKeyDown(e) {
      if (e.key === "Escape") onAcknowledge();
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [onAcknowledge]);

  if (!incident) return null;

  return (
    <div className="critical-alert-backdrop" role="alertdialog" aria-modal="true" aria-labelledby="critical-alert-title">
      <div className="critical-alert-modal">
        <div className="critical-alert-pulse-ring" aria-hidden="true" />

        <div className="critical-alert-header">
          <span className="critical-alert-icon" aria-hidden="true">🚨</span>
          <div>
            <p className="critical-alert-eyebrow">CRITICAL PRIORITY</p>
            <h2 id="critical-alert-title">{incident.type}</h2>
          </div>
        </div>

        <dl className="critical-alert-meta">
          <div>
            <dt>Location</dt>
            <dd>{incident.city}</dd>
          </div>
          {typeof incident.lat === "number" && typeof incident.lng === "number" && (
            <div>
              <dt>Coordinates</dt>
              <dd className="mono">{incident.lat.toFixed(4)}, {incident.lng.toFixed(4)}</dd>
            </div>
          )}
          {incident.aiUrgency != null && (
            <div>
              <dt>AI Urgency</dt>
              <dd>{incident.aiUrgency}/5</dd>
            </div>
          )}
        </dl>

        {typeof incident.hopCount === "number" && (
          <div className="critical-alert-relay">
            <RelayTrace hopCount={incident.hopCount} />
          </div>
        )}

        {/* Exit-node acknowledgement, per the team spec's exact wording. */}
        <p className="critical-alert-ack">{EXIT_NODE_ACK_MESSAGE}</p>

        <div className="critical-alert-actions">
          <button className="critical-alert-primary" onClick={onViewDetails}>
            View Full Details
          </button>
          <button className="critical-alert-secondary" onClick={onAcknowledge}>
            Acknowledge
          </button>
        </div>
      </div>
    </div>
  );
}

export default CriticalAlertModal;
