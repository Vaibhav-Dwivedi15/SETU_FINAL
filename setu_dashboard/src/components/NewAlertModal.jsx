import { useEffect, useRef, useState } from "react";

function NewAlertModal({ onClose, onCreate }) {
  const [type, setType] = useState("");
  const [city, setCity] = useState("");
  const [priority, setPriority] = useState("High");
  const [typeTouched, setTypeTouched] = useState(false);
  const [cityTouched, setCityTouched] = useState(false);
  const firstFieldRef = useRef(null);

  const typeError = typeTouched && !type.trim();
  const cityError = cityTouched && !city.trim();
  const isValid = type.trim() && city.trim();

  // Close on Escape, focus the first field on open, and lock background
  // scroll while the modal is up -- none of this existed before, so the
  // modal previously had no keyboard escape hatch and the page behind it
  // stayed scrollable while it was open.
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
    if (!type.trim() || !city.trim()) return; // defense in depth even though the button is disabled in this state
    onCreate({ type: type.trim(), city: city.trim(), priority });
    onClose();
  }

  return (
    <div
      className="modal"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose(); // click on the backdrop itself closes it
      }}
    >
      <div
        className="modal-content"
        role="dialog"
        aria-modal="true"
        aria-labelledby="new-alert-title"
      >
        <div className="modal-header">
          <h2 id="new-alert-title">🚨 New Alert</h2>

          <button className="close-btn" onClick={onClose} aria-label="Close">
            ✖
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
