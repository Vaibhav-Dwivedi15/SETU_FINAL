// =====================================================
// SETU Dashboard
// Utility : Incident Category Taxonomy
// =====================================================
//
// Phase 4. The team spec calls for the dashboard to group incidents into
// nine named categories. IMPORTANT HONESTY NOTE: the backend's frozen
// packet spec (Section 3) does NOT have these nine categories as a field.
// Its IncidentType enum is a different, smaller set:
//   fire, stampede, landslide, flood, medical, trapped,
//   structural_collapse, other
//
// So these nine categories are a DASHBOARD-SIDE PRESENTATION LAYER,
// derived from what the backend actually sends. Categories that the
// backend has no way to express yet (Women Safety, Child Safety, Senior
// Citizen, Violence) will only ever populate if the AI service's
// ai_incident_type produces them, or if a future packet-spec change adds
// them. Until then those sections will render empty — that is the honest
// state, not a bug to paper over by faking assignments.
//
// Do not present these nine as "what the mesh reports". They're how the
// dashboard organizes what it receives.

export const CATEGORIES = [
  {
    key: "women_safety",
    label: "Women Safety",
    icon: "🛡",
    // No backend enum value maps here today — populated only via AI
    // classification (see matchesCategory below). See module note.
    backendTypes: [],
    aiKeywords: ["women", "woman", "harassment", "molest", "stalk", "eve teasing"],
  },
  {
    key: "child_safety",
    label: "Child Safety",
    icon: "🧒",
    backendTypes: [],
    aiKeywords: ["child", "kid", "minor", "baby", "infant", "missing child"],
  },
  {
    key: "senior_citizen",
    label: "Senior Citizen",
    icon: "🧓",
    backendTypes: [],
    aiKeywords: ["senior", "elderly", "old age", "bujurg", "vridh"],
  },
  {
    key: "violence",
    label: "Violence",
    icon: "⚠",
    backendTypes: [],
    aiKeywords: ["violence", "assault", "attack", "riot", "fight", "weapon"],
  },
  {
    key: "medical",
    label: "Medical",
    icon: "🚑",
    backendTypes: ["medical"],
    aiKeywords: ["medical", "injury", "cardiac", "bleeding", "unconscious"],
  },
  {
    key: "accident",
    label: "Accident",
    icon: "🚗",
    // structural_collapse and trapped are the closest real backend enum
    // values to "accident" in the spec's own vocabulary.
    backendTypes: ["trapped", "structural_collapse"],
    aiKeywords: ["accident", "crash", "collision", "trapped", "collapse"],
  },
  {
    key: "fire",
    label: "Fire",
    icon: "🔥",
    backendTypes: ["fire"],
    aiKeywords: ["fire", "burn", "smoke", "blaze"],
  },
  {
    key: "natural_disaster",
    label: "Natural Disaster",
    icon: "🌊",
    backendTypes: ["flood", "landslide", "stampede"],
    aiKeywords: ["flood", "landslide", "earthquake", "cyclone", "stampede"],
  },
  {
    key: "general_sos",
    label: "General SOS",
    icon: "🆘",
    // Explicit catch-all. "other" is a real backend enum value, and
    // anything unrecognized lands here rather than being dropped from
    // the UI entirely.
    backendTypes: ["other"],
    aiKeywords: [],
  },
];

const GENERAL_SOS_KEY = "general_sos";

/**
 * Resolves which single category an incident belongs to.
 *
 * Precedence, deliberately ordered:
 *   1. Exact match on the backend's own incident_type enum value
 *      (most trustworthy — it's the frozen spec's real field).
 *   2. Keyword match against the AI service's ai_incident_type, if
 *      present. This is the ONLY path by which the four
 *      no-backend-enum categories (Women/Child/Senior/Violence) can be
 *      populated today.
 *   3. Fall through to General SOS. Never drops an incident.
 *
 * Returns a category key string.
 */
export function categorizeIncident(incident) {
  const rawType = String(incident.rawIncidentType || incident.type || "").toLowerCase().trim();
  const aiType = String(incident.aiIncidentType || "").toLowerCase().trim();

  // 1. Backend enum exact match
  for (const category of CATEGORIES) {
    if (category.backendTypes.some((t) => t === rawType)) {
      return category.key;
    }
  }

  // 2. AI-derived keyword match (checks ai_incident_type first, then the
  //    display type as a weaker secondary signal)
  const haystack = `${aiType} ${rawType}`;
  for (const category of CATEGORIES) {
    if (category.aiKeywords.some((kw) => haystack.includes(kw))) {
      return category.key;
    }
  }

  // 3. Catch-all
  return GENERAL_SOS_KEY;
}

/**
 * Groups a list of incidents into { categoryKey: [incidents] }.
 * Every category key is present in the result even when empty — the UI
 * decides whether to render empty sections, this function doesn't hide
 * them (see module note on honest empty states).
 */
export function groupByCategory(incidents) {
  const groups = {};
  CATEGORIES.forEach((c) => { groups[c.key] = []; });

  for (const incident of incidents) {
    const key = categorizeIncident(incident);
    if (!groups[key]) groups[key] = [];
    groups[key].push(incident);
  }

  return groups;
}

export function getCategory(key) {
  return CATEGORIES.find((c) => c.key === key) || CATEGORIES[CATEGORIES.length - 1];
}
