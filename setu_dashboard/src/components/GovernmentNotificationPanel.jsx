// =====================================================
// SETU Dashboard — Government Notification Panel (v2)
// =====================================================
// Visual redesign only — the SIMULATED banner logic/wording is
// UNCHANGED from v1 by design (see v1's module docstring: this
// disclosure is non-negotiable, never soften it for a demo).

import { timeAgo } from "../utils/timeAgo";
import { useTick } from "../utils/useTick";
import { useLanguage } from "../context/LanguageContext";
import { PipelineIcons, MiscIcons } from "../icons";
import { EmptyState } from "./ui/Primitives";

function GovernmentNotificationPanel({ notifications, loading }) {
  useTick();
  const { t } = useLanguage();
  const anyMock = notifications.some((n) => n.isMock);

  return (
    <div className="government-panel">
      <h3 className="ds-section-title">{t("gov.title")}</h3>

      {(anyMock || notifications.length === 0) && (
        <div className="government-mock-banner" role="note">
          <MiscIcons.alert className="ds-icon-md" aria-hidden="true" />
          <div>
            <span className="government-mock-badge">{t("gov.simulated")}</span>
            <p>{t("gov.noReal")}</p>
          </div>
        </div>
      )}

      {loading && <p className="ds-supporting">Loading…</p>}

      {!loading && notifications.length === 0 && (
        <EmptyState icon={PipelineIcons.government} title={t("gov.none")} />
      )}

      {!loading && notifications.length > 0 && (
        <ul className="government-list">
          {notifications.map((n) => (
            <li key={n.id} className={`government-item government-${String(n.status).toLowerCase()}`}>
              <div className="government-item-top">
                <span className={`government-status government-status-${String(n.status).toLowerCase()}`}>{n.status}</span>
                <span className="ds-mono government-adapter">{n.adapterName}</span>
                <span className="ds-mono government-time">{timeAgo(n.createdAt)}</span>
              </div>
              {n.referenceId && (
                <div className="government-reference">
                  <span className="ds-metadata">{t("gov.reference")}</span>
                  <code className="ds-mono" title={n.referenceId}>{n.referenceId}</code>
                </div>
              )}
              {n.responseDetail && <p className="ds-supporting">{n.responseDetail}</p>}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

export default GovernmentNotificationPanel;
