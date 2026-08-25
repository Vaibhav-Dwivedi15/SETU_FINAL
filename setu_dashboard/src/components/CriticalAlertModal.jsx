// =====================================================
// SETU Dashboard — Critical Alert (v2)
// =====================================================
//
// Premium emergency alert, per redesign brief section 9. Restrained
// urgency: a controlled pulse ring + a single accent color (danger),
// not a flashing/bouncing effect. Icons replace the previous emoji.

import { useEffect, useRef } from "react";
import RelayTrace from "./RelayTrace";
import { CategoryIcons, ActionIcons, MiscIcons } from "../icons";
import { PriorityBadge } from "./ui/Primitives";
import { categorizeIncident } from "../utils/incidentCategories";
import { useFocusTrap } from "../utils/useFocusTrap";

export const EXIT_NODE_ACK_MESSAGE =
  "Emergency information successfully reached the SETU network. Thank you for helping connect someone in need.";

function CriticalAlertModal({ incident, onAcknowledge, onViewDetails, onRespond, onNavigate }) {
  const trapRef = useFocusTrap(Boolean(incident));
  const primaryButtonRef = useRef(null);

  useEffect(() => {
    function handleKeyDown(e) { if (e.key === "Escape") onAcknowledge(); }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [onAcknowledge]);

  // Blocking alertdialog — this is exactly the kind of interruption a
  // keyboard/screen-reader user most needs an initial focus landing
  // spot for, since it can appear while they're anywhere else in the app.
  useEffect(() => {
    if (incident) primaryButtonRef.current?.focus();
  }, [incident]);

  if (!incident) return null;

  const CategoryIcon = CategoryIcons[categorizeIncident(incident)] || MiscIcons.alert;
  const hasCoords = typeof incident.lat === "number" && typeof incident.lng === "number";

  return (
    <div className="critical-alert-backdrop" role="alertdialog" aria-modal="true" aria-labelledby="critical-alert-title">
      <div className="critical-alert-modal" ref={trapRef}>
        <div className="critical-alert-pulse-ring" aria-hidden="true" />

        <div className="critical-alert-header">
          <div className="critical-alert-icon-badge">
            <CategoryIcon className="ds-icon-lg" aria-hidden="true" />
          </div>
          <div>
            <p className="critical-alert-eyebrow">
              <MiscIcons.alert className="ds-icon-sm" aria-hidden="true" /> CRITICAL PRIORITY
            </p>
            <h2 id="critical-alert-title">{incident.type}</h2>
          </div>
        </div>

        <div className="critical-alert-facts">
          <div className="critical-alert-fact">
            <ActionIcons.location className="ds-icon-sm" aria-hidden="true" />
            <div><span className="ds-metadata">Where</span><span>{incident.city}</span></div>
          </div>
          <div className="critical-alert-fact">
            <MiscIcons.empty className="ds-icon-sm" aria-hidden="true" />
            <div><span className="ds-metadata">When</span><span>Just now</span></div>
          </div>
          <div className="critical-alert-fact">
            <ActionIcons.notifications className="ds-icon-sm" aria-hidden="true" />
            <div><span className="ds-metadata">Priority</span><PriorityBadge priority="Critical" size="sm" /></div>
          </div>
          <div className="critical-alert-fact">
            <ActionIcons.refresh className="ds-icon-sm" aria-hidden="true" />
            <div>
              <span className="ds-metadata">Network</span>
              <span>{typeof incident.hopCount === "number" && incident.hopCount > 0 ? "Mesh relayed" : "Direct"}</span>
            </div>
          </div>
        </div>

        {typeof incident.hopCount === "number" && (
          <div className="critical-alert-relay"><RelayTrace hopCount={incident.hopCount} /></div>
        )}

        <p className="critical-alert-ack">{EXIT_NODE_ACK_MESSAGE}</p>

        <div className="critical-alert-actions">
          <button ref={primaryButtonRef} className="critical-alert-primary" onClick={onViewDetails}>
            <ActionIcons.view className="ds-icon-sm" aria-hidden="true" /> View Incident
          </button>
          {onRespond && (
            <button className="critical-alert-secondary" onClick={onRespond}>
              <ActionIcons.respond className="ds-icon-sm" aria-hidden="true" /> Respond
            </button>
          )}
          {onNavigate && hasCoords && (
            <button className="critical-alert-secondary" onClick={onNavigate}>
              <ActionIcons.navigate className="ds-icon-sm" aria-hidden="true" /> Navigate
            </button>
          )}
          <button className="critical-alert-dismiss" onClick={onAcknowledge} aria-label="Dismiss">
            <ActionIcons.dismiss className="ds-icon-sm" aria-hidden="true" />
          </button>
        </div>
      </div>
    </div>
  );
}

export default CriticalAlertModal;
