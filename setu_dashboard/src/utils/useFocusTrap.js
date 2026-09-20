import { useEffect, useRef } from "react";

const FOCUSABLE_SELECTOR =
  'a[href], button:not([disabled]), textarea:not([disabled]), input:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])';

// =====================================================
// SETU Dashboard — Focus trap (accessibility fix)
// =====================================================
//
// Redesign brief section 21 (accessibility) asks for keyboard
// navigation and clear focus states — those already worked (Escape
// closes every modal/drawer/palette, focus-visible outlines exist
// globally in design-system.css). What was missing: while a modal is
// open, Tab could walk focus straight out of the dialog into the page
// behind it. That's a real WCAG dialog-pattern gap, invisible to
// visual/mouse testing since it only shows up navigating by keyboard.
//
// Traps Tab/Shift+Tab cycling within the returned container ref while
// `active` is true, and restores focus to whatever triggered the
// dialog once it closes (so a keyboard user lands back where they
// were, not at the top of <body>).
//
// Usage:
//   const trapRef = useFocusTrap(isOpen);
//   <div ref={trapRef}>...dialog content...</div>
export function useFocusTrap(active) {
  const containerRef = useRef(null);
  const previouslyFocusedRef = useRef(null);

  useEffect(() => {
    if (!active) return undefined;

    previouslyFocusedRef.current = document.activeElement;

    function handleKeyDown(e) {
      if (e.key !== "Tab") return;
      const container = containerRef.current;
      if (!container) return;

      const focusable = Array.from(container.querySelectorAll(FOCUSABLE_SELECTOR)).filter(
        (el) => el.offsetParent !== null // skip hidden/collapsed elements
      );
      if (focusable.length === 0) return;

      const first = focusable[0];
      const last = focusable[focusable.length - 1];

      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    }

    document.addEventListener("keydown", handleKeyDown);
    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      previouslyFocusedRef.current?.focus?.();
    };
  }, [active]);

  return containerRef;
}
