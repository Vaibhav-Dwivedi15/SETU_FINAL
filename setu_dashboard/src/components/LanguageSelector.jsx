// Language switcher for the navbar. Sits next to ThemeToggle and
// follows the same visual weight — a small control, not a feature
// announcement.
//
// Shows each language in its OWN script (हिन्दी, বাংলা, தமிழ்), not
// transliterated into English. Someone who needs the Hindi interface is
// looking for "हिन्दी", not "Hindi".

import { LANGUAGES } from "../utils/i18n";
import { useLanguage } from "../context/LanguageContext";

function LanguageSelector() {
  const { language, setLanguage, t } = useLanguage();

  return (
    <label className="language-selector" title={t("lang.label")}>
      <span className="language-selector-icon" aria-hidden="true">🌐</span>
      <select
        value={language}
        onChange={(e) => setLanguage(e.target.value)}
        aria-label={t("lang.label")}
      >
        {LANGUAGES.map((lang) => (
          <option key={lang.code} value={lang.code}>
            {lang.native}
          </option>
        ))}
      </select>
    </label>
  );
}

export default LanguageSelector;
