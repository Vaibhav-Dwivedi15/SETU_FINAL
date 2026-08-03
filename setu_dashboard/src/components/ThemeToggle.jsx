import { useTheme } from "../context/ThemeContext";

function ThemeToggle({ className = "theme-toggle-btn" }) {
  const { theme, toggleTheme } = useTheme();
  return (
    <button
      className={className}
      onClick={toggleTheme}
      title={theme === "dark" ? "Switch to light mode" : "Switch to dark mode"}
      aria-label="Toggle light/dark theme"
    >
      {theme === "dark" ? "☀️" : "🌙"}
    </button>
  );
}

export default ThemeToggle;
