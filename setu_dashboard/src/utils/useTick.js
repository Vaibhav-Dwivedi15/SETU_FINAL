import { useEffect, useState } from "react";

// Forces a re-render every intervalMs by flipping a dummy counter.
// Used purely so relative-time text ("2m ago") keeps advancing on
// screen without needing new data — the underlying incident data
// doesn't change, only how "ago" is phrased.
export function useTick(intervalMs = 30000) {
  const [, setTick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setTick((t) => t + 1), intervalMs);
    return () => clearInterval(id);
  }, [intervalMs]);
}
