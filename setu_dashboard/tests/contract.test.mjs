// Block 2 -- dashboard <-> backend contract. Consumes the SAME golden example the
// backend's tests/test_dashboard_contract.py proves the live API matches, and
// checks the dashboard's normalizeIncident() maps every backend field it needs.
// Run: node --test tests/contract.test.mjs   (or `npm test`)
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

import { normalizeIncident } from "../src/services/api.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const example = JSON.parse(
  readFileSync(path.join(here, "../../Backend/tests/contract/incident_out.example.json"), "utf8"),
);

test("every backend field is mapped, nothing is defaulted away", () => {
  const n = normalizeIncident(example);
  assert.equal(n.id, example.id);
  assert.equal(n.lat, example.latitude);
  assert.equal(n.lng, example.longitude);
  assert.equal(n.status, "active");
  assert.equal(n.senderPriority, "High"); // backend sender_priority "high"
  assert.equal(n.priority, example.display_priority);
  assert.equal(n.aiPriorityValue, example.ai_priority);
  assert.equal(n.aiIncidentType, example.ai_incident_type);
  assert.equal(n.aiIncidentConfidence, example.ai_incident_confidence);
  assert.equal(n.aiIncidentExplanation, example.ai_incident_explanation);
  assert.equal(n.aiUrgency, example.ai_urgency);
  assert.equal(n.aiUrgencyConfidence, example.ai_urgency_confidence);
  assert.equal(n.aiUrgencyExplanation, example.ai_urgency_explanation);
  assert.equal(n.hopCount, example.hop_count);
  assert.deepEqual(n.relayPath, example.relay_path);
  assert.equal(n.reportCount, example.report_count);
  assert.equal(n.reportedAt, example.created_at);
  assert.equal(n.closedAt, null);
});

test("backend display_priority is authoritative (critical modal keys off it)", () => {
  for (const label of ["Critical", "High", "Medium", "Low"]) {
    assert.equal(normalizeIncident({ ...example, display_priority: label }).priority, label);
  }
  // Critical AI assessment surfaces as Critical even if the sender declared "low".
  const critical = normalizeIncident({ ...example, ai_priority: 4.8, sender_priority: "low", display_priority: "Critical" });
  assert.equal(critical.priority, "Critical");
  assert.equal(critical.senderPriority, "Low"); // both preserved, never conflated
});

test("closed incidents", () => {
  const n = normalizeIncident({ ...example, status: "CLOSED", closed_at: "2026-09-24T15:00:00Z" });
  assert.equal(n.status, "closed");
  assert.equal(n.closedAt, "2026-09-24T15:00:00Z");
});

test("older backend without new fields still renders (fallback path)", () => {
  const legacy = { id: 9, incident_type: "fire", latitude: 1, longitude: 2, status: "OPEN", created_at: "2026-09-24T14:00:00Z" };
  const n = normalizeIncident(legacy);
  assert.equal(n.priority, "Medium");
  assert.equal(n.reportCount, 1);
});
