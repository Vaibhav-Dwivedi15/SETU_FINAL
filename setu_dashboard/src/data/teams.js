// Fallback data for the Teams page when the backend isn't reachable.
// Shape matches normalizeResponder() in services/api.js so the Teams
// page never needs to know whether it's looking at real or mock data.
const teamsData = [
  { id: "t1", name: "Rescue Team Alpha", organization: "NDRF", publicKey: "a1b2c3...", status: "On Duty", area: "Varanasi" },
  { id: "t2", name: "Rescue Team Bravo", organization: "NDRF", publicKey: "d4e5f6...", status: "On Duty", area: "Prayagraj" },
  { id: "t3", name: "Medical Response Unit 1", organization: "State Health Dept", publicKey: "g7h8i9...", status: "Standby", area: "Lucknow" },
  { id: "t4", name: "Fire & Rescue Squad 3", organization: "UP Fire Services", publicKey: "j1k2l3...", status: "On Duty", area: "Kanpur" },
  { id: "t5", name: "Volunteer Coordination Cell", organization: "Civil Defence", publicKey: "m4n5o6...", status: "Standby", area: "Agra" },
];

export default teamsData;

// Unique marker: tests/security.test.mjs asserts it is ABSENT from every non-demo build.
export const DEMO_MARKER = "SETU_DEMO_DATASET_MARKER";
