// =====================================================
// SETU Dashboard — Delivery Pipeline (v2)
// =====================================================
//
// Redesign brief section 8 asks for a visually impressive connected
// pipeline (SOURCE -> MESH RELAY -> ... -> RESOLUTION). Same three
// honest states as v1 (confirmed/unknown/pending) — see v1's module
// docstring for why "unknown" must never be upgraded to a fake
// checkmark. Only the presentation changed: a connected vertical
// chain with icon nodes instead of a flat card list.

import { PipelineIcons, StatusIcons, NavIcons } from "../icons";

const STEP_STATE = { CONFIRMED: "confirmed", UNKNOWN: "unknown", PENDING: "pending" };

function PipelineNode({ icon: Icon, label, state, detail, isLast }) {
  const StatusIcon = StatusIcons[state];
  return (
    <li className={`pipeline-node pipeline-${state}`}>
      <div className="pipeline-node-rail">
        <span className="pipeline-node-dot"><Icon className="ds-icon-sm" aria-hidden="true" /></span>
        {!isLast && <span className="pipeline-node-line" />}
      </div>
      <div className="pipeline-node-body">
        <div className="pipeline-node-title-row">
          <strong>{label}</strong>
          <StatusIcon className="ds-icon-sm pipeline-status-icon" aria-hidden="true" />
        </div>
        <span className="ds-supporting">{detail}</span>
      </div>
    </li>
  );
}

function DeliveryStatusPanel({ incident, responseCount }) {
  if (!incident) return null;

  const hasHops = typeof incident.hopCount === "number";
  const isClosed = incident.status === "closed";

  const steps = [
    {
      icon: PipelineIcons.meshRelay,
      label: "Mesh Relay",
      state: hasHops ? STEP_STATE.CONFIRMED : STEP_STATE.UNKNOWN,
      detail: hasHops
        ? incident.hopCount === 0
          ? "Reported directly — origin device had connectivity"
          : `Relayed through ${incident.hopCount} device${incident.hopCount === 1 ? "" : "s"} with no internet`
        : "Hop count not reported for this incident",
    },
    {
      // Redesign brief section 8's exact chain names an "Exit Node" step
      // between Mesh Relay and Backend — the specific mesh device that
      // actually had internet and forwarded the packet onward. There is
      // no exit-node identity field anywhere in the backend's packet
      // spec or IncidentOut model (same honest gap already documented
      // in MapView.jsx for exit-node map markers). Rather than silently
      // omitting the step the brief explicitly asks for, or inventing a
      // fake device id, it's shown here in the UNKNOWN state — present,
      // truthful about not being tracked yet.
      icon: NavIcons.networkHealth,
      label: "Exit Node",
      state: STEP_STATE.UNKNOWN,
      detail: "Which mesh device had internet and forwarded this packet is not tracked by the current backend model.",
    },
    {
      icon: PipelineIcons.backendReceipt,
      label: "Backend Receipt",
      state: STEP_STATE.CONFIRMED,
      detail: "Packet validated, signature verified, and stored",
    },
    {
      icon: PipelineIcons.sms,
      label: "Emergency Contact SMS",
      state: STEP_STATE.UNKNOWN,
      detail: "Fires server-side only if the reporter registered contacts. Outcome not reported by this endpoint.",
    },
    {
      icon: PipelineIcons.government,
      label: "Government Notification",
      state: STEP_STATE.UNKNOWN,
      detail: "Mock adapter — no authorized 112/ERSS integration exists yet. Not a real dispatch.",
    },
    {
      icon: PipelineIcons.community,
      label: "Community Response",
      state: responseCount > 0 ? STEP_STATE.CONFIRMED : STEP_STATE.PENDING,
      detail: responseCount > 0
        ? `${responseCount} nearby SETU user${responseCount === 1 ? "" : "s"} responded`
        : "No community responses recorded yet",
    },
    {
      icon: PipelineIcons.resolution,
      label: "Resolution",
      state: isClosed ? STEP_STATE.CONFIRMED : STEP_STATE.PENDING,
      detail: isClosed ? "Incident closed" : "Incident still open",
    },
  ];

  return (
    <div className="delivery-status-panel">
      <h3 className="ds-section-title">Delivery Pipeline</h3>
      <ul className="pipeline-chain">
        {steps.map((step, i) => (
          <PipelineNode key={step.label} {...step} isLast={i === steps.length - 1} />
        ))}
      </ul>
    </div>
  );
}

export default DeliveryStatusPanel;
