import "./security.css";
import { demoMarker } from "../demo/demoData.js";

// Persistent, honest status strip: DEMO MODE, backend failure, stale data. Never hides itself
// while the condition holds.
function StatusBanner({ demoMode, error, lastSyncedAt, onDismissError }) {
  return (
    <div className="status-banners">
      {demoMode && (
        <div className="banner banner-demo" role="status" data-dataset={demoMarker}>
          <strong>DEMO MODE</strong> — sample data, not real incidents. This build does not talk to a backend.
        </div>
      )}
      {error && (
        <div className="banner banner-error" role="alert">
          <strong>Live data unavailable:</strong> {error}
          {lastSyncedAt ? ` Showing the last data received at ${new Date(lastSyncedAt).toLocaleTimeString()}.` : " No data has been received."}
          {onDismissError && <button type="button" onClick={onDismissError} aria-label="Dismiss">×</button>}
        </div>
      )}
    </div>
  );
}

export default StatusBanner;
