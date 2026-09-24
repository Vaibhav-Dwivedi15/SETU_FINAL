// Build-time configuration (Block 3). Nothing here is a secret: everything compiled in is
// public JavaScript. In particular there is NO responder key/token in this bundle --
// operators authenticate at runtime (see services/api.js loginWithKey).

// Replaced by Vite's `define` (vite.config.js). Undefined under plain node (tests) => false.
// Being a compile-time constant, a production build (VITE_DEMO_MODE unset) dead-code-eliminates
// every demo-data import, so no mock incident/team/resource data ships in it.
export const DEMO_MODE = typeof __DEMO_MODE__ !== "undefined" && __DEMO_MODE__ === true;

// Compile-time constants from vite.config.js `define` (undefined under plain node => dev/test defaults).
const isProdBuild = typeof __PROD_BUILD__ !== "undefined" && __PROD_BUILD__ === true;
const rawBackendUrl = (typeof __BACKEND_URL__ !== "undefined" ? __BACKEND_URL__ : "").replace(/\/+$/, "");

/** Human-readable reason the app cannot talk to a backend at all, or null. */
export const CONFIG_ERROR = (() => {
  if (!isProdBuild) return null; // dev/test: falls back to a local backend below
  if (!rawBackendUrl) return "VITE_BACKEND_URL was not set at build time; this build has no backend to talk to.";
  if (!/^https:\/\//i.test(rawBackendUrl)) return "VITE_BACKEND_URL must be an https:// URL in a production build.";
  return null;
})();

export const BACKEND_URL = rawBackendUrl || (isProdBuild ? "" : "http://localhost:8000");
export const POLL_INTERVAL_MS = 5000;
