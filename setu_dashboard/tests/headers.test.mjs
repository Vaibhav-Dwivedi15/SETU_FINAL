// Block 3 -- the security headers are REAL HTTP response headers, tested against the actual
// built output served by `vite preview` (which applies the exact header set from vercel.json,
// the file the production host reads).
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { spawn, execFileSync } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const PORT = 4179;
const BASE = `http://127.0.0.1:${PORT}`;
const vercel = JSON.parse(readFileSync(path.join(root, "vercel.json"), "utf8"));
const expected = Object.fromEntries(vercel.headers.find((r) => r.source === "/(.*)").headers.map((h) => [h.key.toLowerCase(), h.value]));
let server;

before(async () => {
  execFileSync(process.execPath, [path.join(root, "node_modules/vite/bin/vite.js"), "build", "--logLevel", "error"], { cwd: root, env: { ...process.env, VITE_BACKEND_URL: "https://setu-backend-cy78.onrender.com" }, stdio: "pipe" });
  // Run vite directly (not via npx) so kill() terminates the real server process.
  server = spawn(process.execPath, [path.join(root, "node_modules/vite/bin/vite.js"), "preview", "--port", String(PORT), "--strictPort", "--host", "127.0.0.1"], { cwd: root, stdio: "ignore" });
  for (let i = 0; i < 50; i++) {
    try { await fetch(BASE); return; } catch { await new Promise((r) => setTimeout(r, 200)); }
  }
  throw new Error("vite preview did not start");
});
after(() => server?.kill());

const directives = (csp) => Object.fromEntries(csp.split(";").map((d) => d.trim()).filter(Boolean).map((d) => { const [n, ...v] = d.split(/\s+/); return [n, v]; }));

test("every security header is served on the app shell and on assets", async () => {
  const asset = readdirSync(path.join(root, "dist/assets")).find((f) => f.endsWith(".js"));
  for (const url of [`${BASE}/`, `${BASE}/assets/${asset}`, `${BASE}/does-not-exist`]) {
    const res = await fetch(url);
    for (const [name, value] of Object.entries(expected)) {
      assert.equal(res.headers.get(name), value, `${name} on ${url}`);
    }
  }
});

test("required headers exist with safe values", () => {
  for (const name of ["content-security-policy", "strict-transport-security", "x-frame-options", "x-content-type-options", "referrer-policy", "permissions-policy"]) {
    assert.ok(expected[name], `${name} missing from vercel.json`);
  }
  assert.equal(expected["x-frame-options"], "DENY");
  assert.equal(expected["x-content-type-options"], "nosniff");
  assert.equal(expected["referrer-policy"], "no-referrer");
  assert.match(expected["strict-transport-security"], /max-age=\d{7,}/);
  assert.match(expected["permissions-policy"], /geolocation=\(\)/);
});

test("CSP is strict: no unsafe-eval, no inline scripts, no wildcards, no framing", () => {
  const csp = directives(expected["content-security-policy"]);
  assert.deepEqual(csp["script-src"], ["'self'"]);
  assert.ok(!expected["content-security-policy"].includes("unsafe-eval"));
  assert.ok(!csp["style-src"].includes("'unsafe-inline'"), "style elements are not allowed inline; only style ATTRIBUTES are");
  assert.deepEqual(csp["style-src-attr"], ["'unsafe-inline'"]);
  assert.deepEqual(csp["frame-ancestors"], ["'none'"]);
  assert.deepEqual(csp["object-src"], ["'none'"]);
  assert.deepEqual(csp["base-uri"], ["'self'"]);
  for (const [name, values] of Object.entries(csp)) {
    assert.ok(!values.includes("*"), `${name} must not be a bare wildcard`);
    assert.ok(!values.includes("http:"), `${name} must not allow plain http:`);
  }
  assert.ok(csp["connect-src"].every((v) => v === "'self'" || v.startsWith("https://")), "API calls are https only");
  assert.ok("upgrade-insecure-requests" in csp);
});

test("the built page has no inline script and no meta-tag CSP", async () => {
  const html = await (await fetch(`${BASE}/`)).text();
  assert.ok(!/<script(?![^>]*\bsrc=)[^>]*>/i.test(html), "inline <script> would violate script-src 'self'");
  assert.ok(!/http-equiv=["']Content-Security-Policy/i.test(html), "the CSP is a header, not a meta tag");
});
