import { timeAgo } from "../utils/timeAgo";
import { useTick } from "../utils/useTick";
import { EmptyState } from "./ui/Primitives";
import { PipelineIcons } from "../icons";
import { LuMapPin, LuHandHeart, LuFootprints, LuPhoneCall, LuCompass } from "react-icons/lu";

const RESPONSE_META = {
  NEARBY: { Icon: LuMapPin, tone: "nearby" },
  CAN_HELP: { Icon: LuHandHeart, tone: "can_help" },
  ALREADY_RESPONDING: { Icon: LuFootprints, tone: "already_responding" },
  CALLED_EMERGENCY_SERVICES: { Icon: LuPhoneCall, tone: "called_emergency_services" },
  NAVIGATING: { Icon: LuCompass, tone: "navigating" },
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
      <h3 className="ds-section-title">Community Responses</h3>

      {loading && <p className="ds-supporting">Loading responses…</p>}

      {!loading && responses.length === 0 && (
        <EmptyState
          icon={PipelineIcons.community}
          title="No nearby SETU users have responded yet"
        />
      )}

      {!loading && responses.length > 0 && (
        <ul className="community-response-list">
          {responses.map((r) => {
            const meta = RESPONSE_META[r.responseType] || { Icon: PipelineIcons.community, tone: "" };
            const { Icon } = meta;
            return (
              <li key={r.id} className={`community-response-item response-${meta.tone}`}>
                <span className="community-response-icon"><Icon className="ds-icon-sm" aria-hidden="true" /></span>
                <div className="community-response-body">
                  <strong>{r.responseLabel}</strong>
                  <span className="ds-mono community-response-meta" title={r.senderId}>
                    {shortenSenderId(r.senderId)} · {timeAgo(r.updatedAt || r.createdAt)}
                  </span>
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

export default CommunityResponsePanel;
