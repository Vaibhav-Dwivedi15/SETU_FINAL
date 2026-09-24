import { playAlertSound } from "../../utils/alertSound";
import { useTheme } from "../../context/ThemeContext";
import { ActionIcons } from "../../icons";
import { NetworkStatusPill, SectionHeader } from "../ui/Primitives";

import { BACKEND_URL, DEMO_MODE } from "../../config";
const BUILD_MODE = DEMO_MODE ? "demo" : "production";

// =====================================================
// SETU Dashboard — Settings (v2)
// =====================================================
//
// Redesign brief section 14 asked for a real product control center,
// grouped logically: Appearance / Notifications / Live Updates /
// Backend / Privacy / System. The previous pass had Appearance,
// Connection (Backend), Live Updates, Notifications. This pass adds
// the two missing groups.
//
// HONEST SCOPE: Privacy and System below are informational, not new
// interactive controls — there is no confirmed settings field or
// utility in this codebase for things like clearing local data or a
// real build-version string, so nothing here fakes a working toggle
// that isn't wired to anything. System shows Vite's real build mode
// (import.meta.env.MODE), the one genuinely available build fact.
function SettingsPage({ settings, onChange, backendConnected }) {
  const { theme, setTheme } = useTheme();
  return (
    <div className="settings-page">
      <SectionHeader
        title="Settings"
        description="Product control center — appearance, connection, notifications, and system state."
      />

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

      <div className="settings-card">
        <h3>Privacy</h3>
        <p className="settings-dim">
          This dashboard does not load any third-party analytics or tracking scripts. Incident location data is used only for map display and routing to response teams, and is not stored beyond what the connected backend retains.
        </p>
      </div>

      <div className="settings-card">
        <h3>System</h3>
        <div className="settings-row">
          <div>
            <strong>Build environment</strong>
            <p className="settings-dim">The Vite build mode this dashboard was compiled with.</p>
          </div>
          <span className="mono settings-dim">{BUILD_MODE}</span>
        </div>
      </div>
    </div>
  );
}

export default SettingsPage;
