// Real-browser CSP check (Block 3). Builds the dashboard, serves it with the EXACT header set
// from vercel.json (only connect-src gains a local mock-backend origin), drives headless Chrome
// over CDP, signs in against a mock backend and reports every CSP violation.
//   node scripts/browser-csp-check.mjs        (needs google-chrome; exits non-zero on violations)
import http from "node:http";
import { execFileSync, spawn } from "node:child_process";
import { mkdtempSync, readFileSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const CHROME = ["/usr/bin/google-chrome", "/usr/bin/google-chrome-stable", "/usr/bin/chromium"].find(existsSync);
if (!CHROME) { console.log("SKIP: no Chrome/Chromium found"); process.exit(0); }

const APP_PORT = 4181, API_PORT = 4182, CDP_PORT = 9333;
const APP = `http://127.0.0.1:${APP_PORT}`, API = `http://127.0.0.1:${API_PORT}`;
const out = mkdtempSync(path.join(tmpdir(), "setu-csp-"));

// mode != production so an http mock backend is accepted by config.js; code paths are otherwise identical.
execFileSync(process.execPath, [path.join(root, "node_modules/vite/bin/vite.js"), "build", "--mode", "staging", "--outDir", out, "--emptyOutDir", "--logLevel", "error"],
  { cwd: root, env: { ...process.env, VITE_BACKEND_URL: API }, stdio: "inherit" });

const vercel = JSON.parse(readFileSync(path.join(root, "vercel.json"), "utf8"));
const headers = Object.fromEntries(vercel.headers.find((r) => r.source === "/(.*)").headers.map((h) => [h.key, h.value]));
headers["Content-Security-Policy"] = headers["Content-Security-Policy"].replace(/connect-src [^;]+/, (m) => `${m} ${API}`);

const mime = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png" };
const appServer = http.createServer((req, res) => {
  let p = path.join(out, req.url === "/" ? "index.html" : decodeURIComponent(req.url.split("?")[0]));
  if (!p.startsWith(out) || !existsSync(p)) p = path.join(out, "index.html");
  res.writeHead(200, { ...headers, "Content-Type": mime[path.extname(p)] || "application/octet-stream" });
  res.end(readFileSync(p));
}).listen(APP_PORT);

const incident = (id, priority) => ({ id, incident_type: "fire", latitude: 25.4358, longitude: 81.8463, status: "OPEN", hop_count: 2, relay_path: ["a", "b"],
  sender_priority: "high", ai_incident_type: "Fire", ai_incident_confidence: 0.8, ai_incident_explanation: "x", ai_urgency: 4, ai_urgency_confidence: 0.7, ai_urgency_explanation: "y",
  ai_priority: 4.6, display_priority: priority, report_count: 2, created_at: new Date().toISOString(), updated_at: null, closed_at: null });
const apiServer = http.createServer((req, res) => {
  const cors = { "Access-Control-Allow-Origin": APP, "Access-Control-Allow-Headers": "Authorization, Content-Type", "Access-Control-Allow-Methods": "GET, POST, OPTIONS" };
  if (req.method === "OPTIONS") { res.writeHead(204, cors); return res.end(); }
  const json = (o) => { res.writeHead(200, { ...cors, "Content-Type": "application/json" }); res.end(JSON.stringify(o)); };
  if (req.url === "/auth/responder-login") return json({ access_token: "t.s", token_type: "Bearer", expires_in: 3600 });
  if (req.headers.authorization !== "Bearer t.s") { res.writeHead(401, cors); return res.end("{}"); }
  if (req.url === "/incidents") return json([incident(1, "Critical"), incident(2, "Medium")]);
  json([]);
}).listen(API_PORT);

const chrome = spawn(CHROME, ["--headless=new", "--no-sandbox", "--disable-gpu", `--remote-debugging-port=${CDP_PORT}`, `--user-data-dir=${path.join(out, "profile")}`, "about:blank"], { stdio: "ignore" });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let target;
for (let i = 0; i < 50 && !target; i++) {
  try { target = (await (await fetch(`http://127.0.0.1:${CDP_PORT}/json`)).json()).find((t) => t.type === "page"); } catch { await sleep(200); }
}
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => (ws.onopen = r));
let id = 0; const pending = new Map(); const violations = []; const consoleErrors = [];
ws.onmessage = (m) => {
  const msg = JSON.parse(m.data);
  if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg.result); pending.delete(msg.id); }
  const text = msg.params?.entry?.text || msg.params?.args?.map((a) => a.value).join(" ") || "";
  if (msg.method === "Log.entryAdded" || msg.method === "Runtime.consoleAPICalled") {
    if (/Content Security Policy|Refused to/i.test(text + (msg.params?.entry?.url || ""))) violations.push(text.slice(0, 220));
    else if (msg.params?.entry?.level === "error") consoleErrors.push(text.slice(0, 160));
  }
  if (msg.method === "Runtime.exceptionThrown") consoleErrors.push(JSON.stringify(msg.params.exceptionDetails.exception?.description || "").slice(0, 200));
};
const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const evalJs = async (expression) => (await send("Runtime.evaluate", { expression, returnByValue: true })).result?.value;
await send("Log.enable"); await send("Runtime.enable"); await send("Page.enable");

await send("Page.navigate", { url: APP }); await sleep(2500);
const loginShown = await evalJs("document.body.innerText.includes('Responder key')");
await evalJs(`(async()=>{const r=await fetch('${API}/auth/responder-login',{method:'POST',headers:{'Content-Type':'application/json'},body:'{"key":"k"}'});const d=await r.json();sessionStorage.setItem('setu.session.v1',JSON.stringify({token:d.access_token,expiresAt:Date.now()+3600000}));return 1})()`);
await sleep(500);
await send("Page.navigate", { url: APP }); await sleep(4000);
const text = await evalJs("document.body.innerText");
const rendered = /Emergency Response Dashboard/i.test(text) || /Critical/.test(text);
const noLoginAfter = !/Responder key/.test(text);

// Negative control: an inline script MUST be blocked and reported, proving the detector works.
const before = violations.length;
await evalJs("document.body.appendChild(Object.assign(document.createElement('script'),{textContent:'window.__x=1'})); 1");
await sleep(800);
const detectorWorks = violations.length > before;
violations.splice(before); // the deliberate violation is not a finding

ws.close(); chrome.kill(); appServer.close(); apiServer.close(); rmSync(out, { recursive: true, force: true });
console.log(JSON.stringify({ loginScreenShown: loginShown, dashboardRendered: rendered && noLoginAfter, cspViolations: violations, detectorWorks, otherConsoleErrors: consoleErrors.slice(0, 5) }, null, 2));
process.exit(detectorWorks && loginShown && rendered && noLoginAfter && violations.length === 0 ? 0 : 1);
