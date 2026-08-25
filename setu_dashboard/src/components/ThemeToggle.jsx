import { useTheme } from "../context/ThemeContext";
import { ActionIcons } from "../icons";

// Redesign brief section 2: no emoji as product iconography. This was
// the last control still rendering a raw emoji character as its icon —
// swapped for the same Sun/Moon icons SettingsPage already uses
// (ActionIcons.themeLight / ActionIcons.themeDark), so both places that
// let you switch theme now speak the same visual language.
function ThemeToggle({ className = "theme-toggle-btn" }) {
  const { theme, toggleTheme } = useTheme();
  const Icon = theme === "dark" ? ActionIcons.themeLight : ActionIcons.themeDark;
  return (
    <button
      className={className}
      onClick={toggleTheme}
      title={theme === "dark" ? "Switch to light mode" : "Switch to dark mode"}
      aria-label="Toggle light/dark theme"
    >
      <Icon className="ds-icon-sm" aria-hidden="true" />
    </button>
  );
}

export default ThemeToggle;
