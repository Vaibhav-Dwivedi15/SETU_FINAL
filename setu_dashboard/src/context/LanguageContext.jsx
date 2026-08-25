// Language selection, persisted to localStorage.
//
// Mirrors ThemeContext.jsx's pattern exactly (same storage approach,
// same hook shape, same must-be-inside-provider error) so there's one
// consistent way context works in this codebase rather than two.
//
// See utils/i18n.js for what is and isn't translated — short version:
// dashboard UI chrome yes, incident content no.

import { createContext, useContext, useEffect, useState } from "react";
import { translate, isSupportedLanguage } from "../utils/i18n";

const LanguageContext = createContext(null);

function loadInitialLanguage() {
  try {
    const stored = localStorage.getItem("setu_dashboard_language");
    if (stored && isSupportedLanguage(stored)) return stored;
  } catch {
    // localStorage unavailable — fall through to browser preference
  }

  // No saved preference — take the browser's language if we support it,
  // rather than always forcing English on a first visit.
  const browserLang = (navigator.language || "en").split("-")[0];
  if (isSupportedLanguage(browserLang)) return browserLang;

  return "en";
}

export function LanguageProvider({ children }) {
  const [language, setLanguage] = useState(loadInitialLanguage);

  useEffect(() => {
    try {
      localStorage.setItem("setu_dashboard_language", language);
    } catch {
      // Non-fatal: the app still works, the choice just won't persist.
    }
    // Keeps assistive tech and browser translation prompts correct.
    document.documentElement.setAttribute("lang", language);
  }, [language]);

  // t() is bound to the current language so components call t("nav.map")
  // rather than translate(language, "nav.map") everywhere.
  const t = (key) => translate(language, key);

  return (
    <LanguageContext.Provider value={{ language, setLanguage, t }}>
      {children}
    </LanguageContext.Provider>
  );
}

export function useLanguage() {
  const ctx = useContext(LanguageContext);
  if (!ctx) throw new Error("useLanguage must be used within a LanguageProvider");
  return ctx;
}
