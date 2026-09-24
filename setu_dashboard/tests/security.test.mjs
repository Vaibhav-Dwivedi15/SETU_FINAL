// Block 3 -- dashboard security regression tests.
//  * no privileged responder secret in the browser bundle (and none in the source)
//  * demo/mock data is compiled OUT of a normal build; DEMO MODE is explicit and off by default
//  * API failures are reported, never replaced with fake data
//  * session handling (sessionStorage token, 401 => signed out)
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readdirSync, readFileSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const CANARY = "CANARY_RESPONDER_SECRET_9f8e7d6c5b4a";
const dirs = [];

function walk(dir) {
  return readdirSync(dir).flatMap((n) => {
    const p = path.join(dir, n);
    return statSync(p).isDirectory() ? walk(p) : [p];
  });
}

function build(env) {
  const out = mkdtempSync(path.join(tmpdir(), "setu-dash-"));
  dirs.push(out);
  execFileSync(process.execPath, [path.join(root, "node_modules/vite/bin/vite.js"), "build", "--outDir", out, "--emptyOutDir", "--logLevel", "error"], {
    cwd: root,
    env: { ...process.env, ...env },
    stdio: "pipe",
  });
  return walk(out).filter((f) => /\.(js|css|html)$/.test(f)).map((f) => readFileSync(f, "utf8")).join("\n");
}

const PROD = { VITE_BACKEND_URL: "https://backend.example.test", VITE_API_KEY: CANARY, VITE_RESPONDER_API_KEY: CANARY };
let prodBundle;
let demoBundle;
before(() => {
  prodBundle = build(PROD);
  demoBundle = build({ ...PROD, VITE_DEMO_MODE: "true" });
});
after(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

test("no responder secret or API-key header exists in the production bundle", () => {
  assert.ok(!prodBundle.includes(CANARY), "an env-provided key must never reach the bundle");
  assert.ok(!/x-api-key/i.test(prodBundle), "the dashboard must not speak X-API-Key at all");
  assert.ok(prodBundle.includes("Bearer"), "it authenticates with a session bearer token");
});

test("no source file reads a responder key from the environment", () => {
  const offenders = walk(path.join(root, "src"))
    .filter((f) => /\.(js|jsx)$/.test(f))
    .filter((f) => /VITE_[A-Z_]*(API_KEY|SECRET|TOKEN|PASSWORD)/.test(readFileSync(f, "utf8")));
  assert.deepEqual(offenders, []);
  assert.ok(!/VITE_[A-Z_]*(API_KEY|SECRET|TOKEN|PASSWORD)\s*=/.test(readFileSync(path.join(root, ".env.example"), "utf8").replace(/^\s*#.*$/gm, "")));
});

test("demo data is compiled out of a normal build and present only in an explicit demo build", () => {
  assert.ok(!prodBundle.includes("SETU_DEMO_DATASET_MARKER"), "sample incidents/teams/resources must not ship");
  assert.ok(demoBundle.includes("SETU_DEMO_DATASET_MARKER"));
  assert.ok(demoBundle.includes("DEMO MODE"), "demo builds announce themselves");
});

test("a production build without VITE_BACKEND_URL reports a configuration error instead of guessing localhost", () => {
  const bundle = build({ VITE_BACKEND_URL: "" });
  assert.ok(bundle.includes("VITE_BACKEND_URL was not set at build time"));
  const http = build({ VITE_BACKEND_URL: "http://insecure.example.test" });
  assert.ok(http.includes("must be an https:// URL"));
});

// ------------------------------------------------------------------ api.js behaviour (node, mocked fetch)

class MemoryStorage {
  constructor() { this.m = new Map(); }
  getItem(k) { return this.m.has(k) ? this.m.get(k) : null; }
  setItem(k, v) { this.m.set(k, String(v)); }
  removeItem(k) { this.m.delete(k); }
}

async function freshApi() {
  globalThis.sessionStorage = new MemoryStorage();
  const events = [];
  globalThis.window = { dispatchEvent: (e) => events.push(e.type), addEventListener() {}, removeEventListener() {} };
  const api = await import(`../src/services/api.js?${Math.random()}`);
  return { api, events };
}

function mockFetch(handler) {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    calls.push({ url: String(url), options });
    return handler(String(url), options);
  };
  return calls;
}
const json = (status, body) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

test("login stores only a short-lived token, never the key; requests carry it as a bearer", async () => {
  const { api } = await freshApi();
  const calls = mockFetch((url) =>
    url.endsWith("/auth/responder-login") ? json(200, { access_token: "tok.sig", token_type: "Bearer", expires_in: 3600 }) : json(200, []),
  );
  await api.loginWithKey("operator-typed-key");
  assert.ok(api.hasSession());
  const stored = sessionStorage.getItem("setu.session.v1");
  assert.ok(!stored.includes("operator-typed-key"));
  await api.fetchIncidents();
  assert.equal(calls.at(-1).options.headers.Authorization, "Bearer tok.sig");
  assert.equal(calls.at(-1).options.headers["X-API-Key"], undefined);
});

test("no session => no request is sent and the app is told to sign in", async () => {
  const { api, events } = await freshApi();
  const calls = mockFetch(() => json(200, []));
  await assert.rejects(api.fetchIncidents(), /Not signed in/);
  assert.equal(calls.length, 0);
  assert.ok(events.includes("setu:auth-expired"));
});

test("401 clears the session and signals sign-out", async () => {
  const { api, events } = await freshApi();
  mockFetch((url) => (url.endsWith("/auth/responder-login") ? json(200, { access_token: "t.s", expires_in: 3600 }) : json(401, { detail: "x" })));
  await api.loginWithKey("k");
  await assert.rejects(api.fetchIncidents(), /expired/i);
  assert.ok(!api.hasSession());
  assert.ok(events.includes("setu:auth-expired"));
});

test("login failures are specific and store nothing", async () => {
  for (const [status, re] of [[401, /Invalid credentials/], [429, /Too many/], [503, /not configured/], [500, /HTTP 500/]]) {
    const { api } = await freshApi();
    mockFetch(() => json(status, {}));
    await assert.rejects(api.loginWithKey("k"), re);
    assert.ok(!api.hasSession());
  }
});

test("API failures are errors, never empty/fake data", async () => {
  const { api } = await freshApi();
  mockFetch((url) => (url.endsWith("/auth/responder-login") ? json(200, { access_token: "t.s", expires_in: 3600 }) : json(500, {})));
  await api.loginWithKey("k");
  for (const fn of [() => api.fetchIncidents(), () => api.fetchResponders(), () => api.fetchIncidentResponses(1), () => api.fetchIncidentHistory(1), () => api.fetchIncidentGovernmentNotifications(1), () => api.fetchGovernmentAdapterStatus()]) {
    await assert.rejects(fn(), /Backend returned 500/);
  }
  mockFetch(() => { throw new TypeError("network down"); });
  await assert.rejects(api.fetchIncidents(), /unreachable/);
  mockFetch(() => json(200, { not: "an array" }));
  await assert.rejects(api.fetchIncidents(), /unexpected/);
});

test("resolve reports failure instead of pretending success", async () => {
  const { api } = await freshApi();
  mockFetch((url) => (url.endsWith("/auth/responder-login") ? json(200, { access_token: "t.s", expires_in: 3600 }) : json(503, {})));
  await api.loginWithKey("k");
  await assert.rejects(api.resolveIncidentOnBackend(5));
});

test("polling surfaces every failure and never delivers sample data", async () => {
  const { api } = await freshApi();
  mockFetch((url) => (url.endsWith("/auth/responder-login") ? json(200, { access_token: "t.s", expires_in: 3600 }) : json(502, {})));
  await api.loginWithKey("k");
  const updates = [];
  const errors = [];
  const stop = api.startIncidentPolling((i) => updates.push(i), (e) => errors.push(e.message), 20);
  await new Promise((r) => setTimeout(r, 120));
  stop();
  assert.deepEqual(updates, []);
  assert.ok(errors.length >= 2, "each failed poll is reported, not just the first");
});

test("DEMO_MODE is off in a plain node/unset build", async () => {
  const { DEMO_MODE } = await import("../src/config.js");
  assert.equal(DEMO_MODE, false);
});
