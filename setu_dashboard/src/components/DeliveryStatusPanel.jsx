// =====================================================
// SETU Dashboard
// Component : Delivery & Notification Status
// =====================================================
//
// Phase 4. The spec asks the incident detail view to show
// "relay / delivery / notification status".
//
// HONESTY DISCIPLINE — read before changing this:
// The backend does NOT expose a per-incident notification-status field.
// What can be truthfully derived from GET /incidents alone:
//
//   Mesh relay      -> CONFIRMED. hop_count is a real field on the frozen
//                      packet spec, genuinely counted per relay hop.
//   Backend receipt -> CONFIRMED. If the dashboard is rendering this
//                      incident at all, the packet reached the backend
//                      and was stored.
//   SMS to contacts -> UNKNOWN from this endpoint. The backend fires
//                      notify_emergency_contacts() only when the sender
//                      has a registered profile with contacts, and does
//                      not report the outcome on IncidentOut.
//   Government      -> UNKNOWN from this endpoint, and note it is a MOCK
//                      adapter today (MOCK-GOV-... reference ids). There
//                      is no authorized real 112/ERSS integration.
//
// So this component renders three states — confirmed / unknown /
// not-applicable — and never shows a green check for something it can't
// actually verify. If a future backend release adds real per-incident
// notification status to IncidentOut, wire it in here; until then,
// "Status not reported by backend" is the correct, honest label.

const STEP_STATE = {
  CONFIRMED: "confirmed",
  UNKNOWN: "unknown",
  PENDING: "pending",
};

function StatusRow({ label, state, detail }) {
  const icon =
    state === STEP_STATE.CONFIRMED ? "✓" :
    state === STEP_STATE.PENDING ? "…" : "?";

  return (
    <li className={`delivery-step delivery-step-${state}`}>
      <span className="delivery-step-icon" aria-hidden="true">{icon}</span>
      <div className="delivery-step-body">
        <strong>{label}</strong>
        <span className="delivery-step-detail">{detail}</span>
      </div>
    </li>
  );
}

function DeliveryStatusPanel({ incident, responseCount }) {
  if (!incident) return null;

  const hasHops = typeof incident.hopCount === "number";
  const isClosed = incident.status === "closed";

  return (
    <div className="delivery-status-panel">
      <h3 className="drawer-section-title">Delivery Pipeline</h3>

      <ul className="delivery-steps">
        <StatusRow
          label="Mesh relay"
          state={hasHops ? STEP_STATE.CONFIRMED : STEP_STATE.UNKNOWN}
          detail={
            hasHops
              ? incident.hopCount === 0
                ? "Reported directly — origin device had connectivity"
                : `Relayed through ${incident.hopCount} device${incident.hopCount === 1 ? "" : "s"} with no internet`
              : "Hop count not reported for this incident"
          }
        />

        <StatusRow
          label="Backend receipt"
          state={STEP_STATE.CONFIRMED}
          detail="Packet validated, signature verified, and stored"
        />

        <StatusRow
          label="Emergency contact SMS"
          state={STEP_STATE.UNKNOWN}
          detail="Fires server-side only if the reporter registered contacts. Outcome not reported by this endpoint."
        />

        <StatusRow
          label="Government notification"
          state={STEP_STATE.UNKNOWN}
          detail="Mock adapter — no authorized 112/ERSS integration exists yet. Not a real dispatch."
        />

        <StatusRow
          label="Community response"
          state={responseCount > 0 ? STEP_STATE.CONFIRMED : STEP_STATE.PENDING}
          detail={
            responseCount > 0
              ? `${responseCount} nearby SETU user${responseCount === 1 ? "" : "s"} responded`
              : "No community responses recorded yet"
          }
        />

        <StatusRow
          label="Resolution"
          state={isClosed ? STEP_STATE.CONFIRMED : STEP_STATE.PENDING}
          detail={isClosed ? "Incident closed" : "Incident still open"}
        />
      </ul>
    </div>
  );
}

export default DeliveryStatusPanel;
