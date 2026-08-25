// =====================================================
// SETU Dashboard
// Component : Government Notification Panel
// =====================================================
//
// Surfaces the backend's GovernmentNotificationLog for one incident
// (GET /incidents/{id}/government-notifications).
//
// THE SIMULATED BANNER IS NOT DECORATION. The active backend adapter is
// a mock — no real 112/ERSS or state emergency API is integrated or
// authorized. Reference IDs are prefixed MOCK-GOV- for exactly this
// reason. Anyone screenshotting this panel for a demo or a deck must be
// unable to mistake it for a real government dispatch. Do not remove or
// soften the banner to make a demo look better; that is precisely the
// overclaim this project's shipped-vs-roadmap rule exists to prevent.

import { timeAgo } from "../utils/timeAgo";
import { useTick } from "../utils/useTick";
import { useLanguage } from "../context/LanguageContext";

function GovernmentNotificationPanel({ notifications, loading }) {
  useTick();
  const { t } = useLanguage();

  const anyMock = notifications.some((n) => n.isMock);

  return (
    <div className="government-panel">
      <h3 className="drawer-section-title">
        {t("gov.title")}
        {notifications.length > 0 && (
          <span className="drawer-section-count">{notifications.length}</span>
        )}
      </h3>

      {(anyMock || notifications.length === 0) && (
        <div className="government-mock-banner" role="note">
          <span className="government-mock-badge">{t("gov.simulated")}</span>
          <p>{t("gov.noReal")}</p>
        </div>
      )}

      {loading && <p className="community-response-empty">Loading…</p>}

      {!loading && notifications.length === 0 && (
        <p className="community-response-empty">{t("gov.none")}</p>
      )}

      {!loading && notifications.length > 0 && (
        <ul className="government-list">
          {notifications.map((n) => (
            <li
              key={n.id}
              className={`government-item government-${String(n.status).toLowerCase()}`}
            >
              <div className="government-item-top">
                <span className={`government-status government-status-${String(n.status).toLowerCase()}`}>
                  {n.status}
                </span>
                <span className="government-adapter mono">{n.adapterName}</span>
                <span className="government-time mono">{timeAgo(n.createdAt)}</span>
              </div>

              {n.referenceId && (
                <div className="government-reference">
                  <span className="government-reference-label">{t("gov.reference")}</span>
                  <code className="mono" title={n.referenceId}>{n.referenceId}</code>
                </div>
              )}

              {n.responseDetail && (
                <p className="government-detail">{n.responseDetail}</p>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

export default GovernmentNotificationPanel;
