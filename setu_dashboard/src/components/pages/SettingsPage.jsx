import { playAlertSound } from "../../utils/alertSound";
import { useTheme } from "../../context/ThemeContext";
import { ActionIcons } from "../../icons";
import { NetworkStatusPill } from "../ui/Primitives";

const BACKEND_URL = import.meta.env.VITE_BACKEND_URL || "http://localhost:8000";

function SettingsPage({ settings, onChange, backendConnected }) {
  const { theme, setTheme } = useTheme();
  return (
    <div className="settings-page">
      <div className="settings-card">
        <h3>Appearance</h3>
        <div className="settings-row">
          <div>
            <strong>Theme</strong>
            <p className="settings-dim">Switch between the dark command-center look and a light theme.</p>
          </div>
          <div className="settings-theme-toggle">
            <button className={theme === "dark" ? "active" : ""} onClick={() => setTheme("dark")} style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
              <ActionIcons.themeDark className="ds-icon-sm" aria-hidden="true" /> Dark
            </button>
            <button className={theme === "light" ? "active" : ""} onClick={() => setTheme("light")} style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
              <ActionIcons.themeLight className="ds-icon-sm" aria-hidden="true" /> Light
            </button>
          </div>
        </div>
      </div>
      <div className="settings-card">
        <h3>Connection</h3>
        <div className="settings-row">
          <div>
            <strong>Backend URL</strong>
            <p className="mono settings-dim">{BACKEND_URL}</p>
          </div>
          <NetworkStatusPill connected={backendConnected} lastSyncedAt={null} formatTime={() => ""} />
        </div>
        <p className="settings-hint">
          Set VITE_BACKEND_URL in .env to point this dashboard at a different backend instance.
        </p>
      </div>

      <div className="settings-card">
        <h3>Live Updates</h3>
        <div className="settings-row">
          <div>
            <strong>Poll interval</strong>
            <p className="settings-dim">How often the dashboard checks the backend for new incidents.</p>
          </div>
          <select
            value={settings.pollIntervalMs}
            onChange={(e) => onChange({ ...settings, pollIntervalMs: Number(e.target.value) })}
          >
            <option value={3000}>3 seconds</option>
            <option value={5000}>5 seconds</option>
            <option value={10000}>10 seconds</option>
            <option value={30000}>30 seconds</option>
          </select>
        </div>
      </div>

      <div className="settings-card">
        <h3>Notifications</h3>
        <div className="settings-row">
          <div>
            <strong>New alert toasts</strong>
            <p className="settings-dim">Show a popup notification when a new incident is reported.</p>
          </div>
          <label className="toggle-switch">
            <input
              type="checkbox"
              checked={settings.notificationsEnabled}
              onChange={(e) => onChange({ ...settings, notificationsEnabled: e.target.checked })}
            />
            <span className="toggle-slider" />
          </label>
        </div>

        <div className="settings-row settings-row-spaced">
          <div>
            <strong>Sound alerts</strong>
            <p className="settings-dim">Play a short tone when a new incident arrives (louder for Critical).</p>
          </div>
          <label className="toggle-switch">
            <input
              type="checkbox"
              checked={settings.soundEnabled}
              onChange={(e) => onChange({ ...settings, soundEnabled: e.target.checked })}
            />
            <span className="toggle-slider" />
          </label>
        </div>

        {settings.soundEnabled && (
          <button className="settings-test-btn" onClick={() => playAlertSound("Critical")} style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
            <ActionIcons.volume className="ds-icon-sm" aria-hidden="true" /> Test sound
          </button>
        )}
      </div>
    </div>
  );
}

export default SettingsPage;
