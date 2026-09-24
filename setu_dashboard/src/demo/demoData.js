// The ONLY importer of the sample datasets. Guarded by the compile-time DEMO_MODE constant, so
// in a normal (non-demo) build the dynamic import below is dead code and the sample data is
// not part of the bundle. Demo builds are explicit: VITE_DEMO_MODE=true, and the UI shows a
// permanent "DEMO MODE" banner.
// Evaluated in THIS module (not imported) so the bundler can constant-fold the branch and drop
// the dynamic imports entirely when __DEMO_MODE__ is false.
const DEMO_MODE = typeof __DEMO_MODE__ !== "undefined" && __DEMO_MODE__ === true;

const demo = DEMO_MODE
  ? {
      incidents: (await import("../data/incidents.js")).default,
      teams: (await import("../data/teams.js")).default,
      resources: (await import("../data/resources.js")).default,
      marker: (await import("../data/incidents.js")).DEMO_MARKER,
    }
  : null;

export const demoIncidents = demo ? demo.incidents : [];
export const demoTeams = demo ? demo.teams : [];
export const demoResources = demo ? demo.resources : [];
export const demoMarker = demo ? demo.marker : null;
