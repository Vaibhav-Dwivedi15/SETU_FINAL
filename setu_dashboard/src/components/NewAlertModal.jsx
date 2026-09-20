import { useEffect, useRef, useState } from "react";
import { NavIcons, ActionIcons } from "../icons";
import { useFocusTrap } from "../utils/useFocusTrap";

function NewAlertModal({ onClose, onCreate }) {
  const [type, setType] = useState("");
  const [city, setCity] = useState("");
  const [priority, setPriority] = useState("High");
  const [typeTouched, setTypeTouched] = useState(false);
  const [cityTouched, setCityTouched] = useState(false);
  const firstFieldRef = useRef(null);
  const trapRef = useFocusTrap(true);

  const typeError = typeTouched && !type.trim();
  const cityError = cityTouched && !city.trim();
  const isValid = type.trim() && city.trim();

  useEffect(() => {
    firstFieldRef.current?.focus();
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    function handleKeyDown(e) {
      if (e.key === "Escape") onClose();
    }
    window.addEventListener("keydown", handleKeyDown);

    return () => {
      window.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = previousOverflow;
    };
  }, [onClose]);

  function handleSubmit() {
    setTypeTouched(true);
    setCityTouched(true);
    if (!type.trim() || !city.trim()) return;
    onCreate({ type: type.trim(), city: city.trim(), priority });
    onClose();
  }

  return (
    <div
      className="modal"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div
        ref={trapRef}
        className="modal-content"
        role="dialog"
        aria-modal="true"
        aria-labelledby="new-alert-title"
      >
        <div className="modal-header">
          <h2 id="new-alert-title" style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <NavIcons.liveIncidents className="ds-icon-md" aria-hidden="true" /> New Alert
          </h2>

          <button className="close-btn" onClick={onClose} aria-label="Close">
            <ActionIcons.dismiss className="ds-icon-sm" aria-hidden="true" />
          </button>
        </div>

        <div>
          <input
            ref={firstFieldRef}
            type="text"
            placeholder="Incident Type (e.g. Fire, Flood, Medical)"
            value={type}
            onChange={(e) => setType(e.target.value)}
            onBlur={() => setTypeTouched(true)}
            className={typeError ? "field-error" : ""}
            aria-invalid={typeError}
          />
          {typeError && <p className="field-error-text">Incident type is required.</p>}
        </div>

        <div>
          <input
            type="text"
            placeholder="City"
            value={city}
            onChange={(e) => setCity(e.target.value)}
            onBlur={() => setCityTouched(true)}
            className={cityError ? "field-error" : ""}
            aria-invalid={cityError}
            onKeyDown={(e) => {
              if (e.key === "Enter") handleSubmit();
            }}
          />
          {cityError && <p className="field-error-text">City is required.</p>}
        </div>

        <select value={priority} onChange={(e) => setPriority(e.target.value)}>
          <option>Critical</option>
          <option>High</option>
          <option>Medium</option>
          <option>Low</option>
        </select>

        <div className="modal-buttons">
          <button className="btn-cancel" onClick={onClose}>
            Cancel
          </button>

          <button className="btn-create" onClick={handleSubmit} disabled={!isValid}>
            Create Alert
          </button>
        </div>
      </div>
    </div>
  );
}

export default NewAlertModal;
