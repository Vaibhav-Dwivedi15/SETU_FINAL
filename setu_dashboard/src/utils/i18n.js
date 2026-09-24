// =====================================================
// SETU Dashboard
// Utility : Internationalization (i18n)
// =====================================================
//
// Lightweight i18n with no dependency â€” the dashboard's translatable
// surface is small enough that pulling in react-i18next would cost more
// than it saves.
//
// SCOPE, HONESTLY: this translates the dashboard's own UI CHROME (nav,
// labels, buttons, status text). It does NOT translate incident content
// â€” incident messages arrive from the backend already translated to
// English by Whisper (see Backend/app/routers/voice.py), and typed
// reports are stored as sent. So switching language here changes the
// responder's interface, not the reported data. Don't claim otherwise.
//
// Languages chosen to cover the largest speaker populations in the
// deployment region plus English as the working default.

export const LANGUAGES = [
  { code: "en", label: "English", native: "English" },
  { code: "hi", label: "Hindi", native: "à¤¹à¤¿à¤¨à¥à¤¦à¥€" },
  { code: "bn", label: "Bengali", native: "à¦¬à¦¾à¦‚à¦²à¦¾" },
  { code: "ta", label: "Tamil", native: "à®¤à®®à®¿à®´à¯" },
  { code: "te", label: "Telugu", native: "à°¤à±†à°²à±à°—à±" },
  { code: "mr", label: "Marathi", native: "à¤®à¤°à¤¾à¤ à¥€" },
];

const translations = {
  en: {
    "nav.dashboard": "Dashboard",
    "nav.map": "Live Map",
    "nav.incidents": "Incidents",
    "nav.categories": "Categories",
    "nav.analytics": "Analytics",
    "nav.resources": "Resources",
    "nav.recovery": "Recovery & Damage",
    "nav.teams": "Teams",
    "nav.settings": "Settings",
    "nav.mainMenu": "MAIN MENU",

    "status.systemStatus": "System Status",
    "status.live": "Live (Backend Connected)",
    "status.offline": "Offline (Mock Data)",
    "status.lastSynced": "Last synced",

    "priority.critical": "Critical",
    "priority.high": "High",
    "priority.medium": "Medium",
    "priority.low": "Low",

    "incident.active": "Active",
    "incident.closed": "Closed",
    "incident.markResolved": "Mark Resolved",
    "incident.noMatch": "No incidents match your current filters.",

    "category.women_safety": "Women Safety",
    "category.child_safety": "Child Safety",
    "category.senior_citizen": "Senior Citizen",
    "category.violence": "Violence",
    "category.medical": "Medical",
    "category.accident": "Accident",
    "category.fire": "Fire",
    "category.natural_disaster": "Natural Disaster",
    "category.general_sos": "General SOS",

    "drawer.overview": "Overview",
    "drawer.delivery": "Delivery",
    "drawer.activity": "Activity",
    "drawer.location": "Location",
    "drawer.status": "Status",
    "drawer.reported": "Reported",
    "drawer.coordinates": "Coordinates",
    "drawer.meshPath": "Mesh Path",

    "gov.title": "Government Notification",
    "gov.simulated": "SIMULATED â€” mock adapter",
    "gov.noReal": "No real 112/ERSS integration is authorized. Reference IDs are simulated.",
    "gov.none": "No government notification recorded for this incident.",
    "gov.reference": "Reference",

    "critical.eyebrow": "CRITICAL PRIORITY",
    "critical.viewDetails": "View Full Details",
    "critical.acknowledge": "Acknowledge",

    "lang.label": "Language",
  },

  hi: {
    "nav.dashboard": "à¤¡à¥ˆà¤¶à¤¬à¥‹à¤°à¥à¤¡",
    "nav.map": "à¤²à¤¾à¤‡à¤µ à¤®à¤¾à¤¨à¤šà¤¿à¤¤à¥à¤°",
    "nav.incidents": "à¤˜à¤Ÿà¤¨à¤¾à¤à¤",
    "nav.categories": "à¤¶à¥à¤°à¥‡à¤£à¤¿à¤¯à¤¾à¤",
    "nav.analytics": "à¤µà¤¿à¤¶à¥à¤²à¥‡à¤·à¤£",
    "nav.resources": "à¤¸à¤‚à¤¸à¤¾à¤§à¤¨",
    "nav.teams": "à¤Ÿà¥€à¤®à¥‡à¤‚",
    "nav.settings": "à¤¸à¥‡à¤Ÿà¤¿à¤‚à¤—à¥à¤¸",
    "nav.mainMenu": "à¤®à¥à¤–à¥à¤¯ à¤®à¥‡à¤¨à¥à¤¯à¥‚",

    "status.systemStatus": "à¤¸à¤¿à¤¸à¥à¤Ÿà¤® à¤¸à¥à¤¥à¤¿à¤¤à¤¿",
    "status.live": "à¤²à¤¾à¤‡à¤µ (à¤¬à¥ˆà¤•à¤à¤‚à¤¡ à¤œà¥à¤¡à¤¼à¤¾ à¤¹à¥à¤†)",
    "status.offline": "à¤‘à¤«à¤¼à¤²à¤¾à¤‡à¤¨ (à¤¨à¤®à¥‚à¤¨à¤¾ à¤¡à¥‡à¤Ÿà¤¾)",
    "status.lastSynced": "à¤…à¤‚à¤¤à¤¿à¤® à¤¸à¤¿à¤‚à¤•",

    "priority.critical": "à¤…à¤¤à¤¿ à¤—à¤‚à¤­à¥€à¤°",
    "priority.high": "à¤‰à¤šà¥à¤š",
    "priority.medium": "à¤®à¤§à¥à¤¯à¤®",
    "priority.low": "à¤¨à¤¿à¤®à¥à¤¨",

    "incident.active": "à¤¸à¤•à¥à¤°à¤¿à¤¯",
    "incident.closed": "à¤¬à¤‚à¤¦",
    "incident.markResolved": "à¤¹à¤² à¤•à¥‡ à¤°à¥‚à¤ª à¤®à¥‡à¤‚ à¤šà¤¿à¤¹à¥à¤¨à¤¿à¤¤ à¤•à¤°à¥‡à¤‚",
    "incident.noMatch": "à¤†à¤ªà¤•à¥‡ à¤µà¤°à¥à¤¤à¤®à¤¾à¤¨ à¤«à¤¼à¤¿à¤²à¥à¤Ÿà¤° à¤¸à¥‡ à¤•à¥‹à¤ˆ à¤˜à¤Ÿà¤¨à¤¾ à¤®à¥‡à¤² à¤¨à¤¹à¥€à¤‚ à¤–à¤¾à¤¤à¥€à¥¤",

    "category.women_safety": "à¤®à¤¹à¤¿à¤²à¤¾ à¤¸à¥à¤°à¤•à¥à¤·à¤¾",
    "category.child_safety": "à¤¬à¤¾à¤² à¤¸à¥à¤°à¤•à¥à¤·à¤¾",
    "category.senior_citizen": "à¤µà¤°à¤¿à¤·à¥à¤  à¤¨à¤¾à¤—à¤°à¤¿à¤•",
    "category.violence": "à¤¹à¤¿à¤‚à¤¸à¤¾",
    "category.medical": "à¤šà¤¿à¤•à¤¿à¤¤à¥à¤¸à¤¾",
    "category.accident": "à¤¦à¥à¤°à¥à¤˜à¤Ÿà¤¨à¤¾",
    "category.fire": "à¤†à¤—",
    "category.natural_disaster": "à¤ªà¥à¤°à¤¾à¤•à¥ƒà¤¤à¤¿à¤• à¤†à¤ªà¤¦à¤¾",
    "category.general_sos": "à¤¸à¤¾à¤®à¤¾à¤¨à¥à¤¯ à¤à¤¸à¤“à¤à¤¸",

    "drawer.overview": "à¤…à¤µà¤²à¥‹à¤•à¤¨",
    "drawer.delivery": "à¤µà¤¿à¤¤à¤°à¤£",
    "drawer.activity": "à¤—à¤¤à¤¿à¤µà¤¿à¤§à¤¿",
    "drawer.location": "à¤¸à¥à¤¥à¤¾à¤¨",
    "drawer.status": "à¤¸à¥à¤¥à¤¿à¤¤à¤¿",
    "drawer.reported": "à¤¸à¥‚à¤šà¤¿à¤¤",
    "drawer.coordinates": "à¤¨à¤¿à¤°à¥à¤¦à¥‡à¤¶à¤¾à¤‚à¤•",
    "drawer.meshPath": "à¤®à¥‡à¤¶ à¤ªà¤¥",

    "gov.title": "à¤¸à¤°à¤•à¤¾à¤°à¥€ à¤…à¤§à¤¿à¤¸à¥‚à¤šà¤¨à¤¾",
    "gov.simulated": "à¤…à¤¨à¥à¤°à¥‚à¤ªà¤¿à¤¤ â€” à¤®à¥‰à¤• à¤à¤¡à¤¾à¤ªà¥à¤Ÿà¤°",
    "gov.noReal": "à¤•à¥‹à¤ˆ à¤µà¤¾à¤¸à¥à¤¤à¤µà¤¿à¤• 112/ERSS à¤à¤•à¥€à¤•à¤°à¤£ à¤…à¤§à¤¿à¤•à¥ƒà¤¤ à¤¨à¤¹à¥€à¤‚ à¤¹à¥ˆà¥¤ à¤¸à¤‚à¤¦à¤°à¥à¤­ à¤†à¤ˆà¤¡à¥€ à¤…à¤¨à¥à¤°à¥‚à¤ªà¤¿à¤¤ à¤¹à¥ˆà¤‚à¥¤",
    "gov.none": "à¤‡à¤¸ à¤˜à¤Ÿà¤¨à¤¾ à¤•à¥‡ à¤²à¤¿à¤ à¤•à¥‹à¤ˆ à¤¸à¤°à¤•à¤¾à¤°à¥€ à¤…à¤§à¤¿à¤¸à¥‚à¤šà¤¨à¤¾ à¤¦à¤°à¥à¤œ à¤¨à¤¹à¥€à¤‚ à¤¹à¥ˆà¥¤",
    "gov.reference": "à¤¸à¤‚à¤¦à¤°à¥à¤­",

    "critical.eyebrow": "à¤…à¤¤à¤¿ à¤—à¤‚à¤­à¥€à¤° à¤ªà¥à¤°à¤¾à¤¥à¤®à¤¿à¤•à¤¤à¤¾",
    "critical.viewDetails": "à¤ªà¥‚à¤°à¤¾ à¤µà¤¿à¤µà¤°à¤£ à¤¦à¥‡à¤–à¥‡à¤‚",
    "critical.acknowledge": "à¤¸à¥à¤µà¥€à¤•à¤¾à¤° à¤•à¤°à¥‡à¤‚",

    "lang.label": "à¤­à¤¾à¤·à¤¾",
  },

  bn: {
    "nav.dashboard": "à¦¡à§à¦¯à¦¾à¦¶à¦¬à§‹à¦°à§à¦¡",
    "nav.map": "à¦²à¦¾à¦‡à¦­ à¦®à¦¾à¦¨à¦šà¦¿à¦¤à§à¦°",
    "nav.incidents": "à¦˜à¦Ÿà¦¨à¦¾",
    "nav.categories": "à¦¬à¦¿à¦­à¦¾à¦—",
    "nav.analytics": "à¦¬à¦¿à¦¶à§à¦²à§‡à¦·à¦£",
    "nav.resources": "à¦¸à¦®à§à¦ªà¦¦",
    "nav.teams": "à¦¦à¦²",
    "nav.settings": "à¦¸à§‡à¦Ÿà¦¿à¦‚à¦¸",
    "nav.mainMenu": "à¦ªà§à¦°à¦§à¦¾à¦¨ à¦®à§‡à¦¨à§",

    "status.systemStatus": "à¦¸à¦¿à¦¸à§à¦Ÿà§‡à¦®à§‡à¦° à¦…à¦¬à¦¸à§à¦¥à¦¾",
    "status.live": "à¦²à¦¾à¦‡à¦­ (à¦¬à§à¦¯à¦¾à¦•à¦à¦¨à§à¦¡ à¦¸à¦‚à¦¯à§à¦•à§à¦¤)",
    "status.offline": "à¦…à¦«à¦²à¦¾à¦‡à¦¨ (à¦¨à¦®à§à¦¨à¦¾ à¦¤à¦¥à§à¦¯)",
    "status.lastSynced": "à¦¸à¦°à§à¦¬à¦¶à§‡à¦· à¦¸à¦¿à¦™à§à¦•",

    "priority.critical": "à¦¸à¦‚à¦•à¦Ÿà¦œà¦¨à¦•",
    "priority.high": "à¦‰à¦šà§à¦š",
    "priority.medium": "à¦®à¦¾à¦à¦¾à¦°à¦¿",
    "priority.low": "à¦¨à¦¿à¦®à§à¦¨",

    "incident.active": "à¦¸à¦•à§à¦°à¦¿à¦¯à¦¼",
    "incident.closed": "à¦¬à¦¨à§à¦§",
    "incident.markResolved": "à¦¸à¦®à¦¾à¦§à¦¾à¦¨ à¦¹à¦¿à¦¸à§‡à¦¬à§‡ à¦šà¦¿à¦¹à§à¦¨à¦¿à¦¤ à¦•à¦°à§à¦¨",
    "incident.noMatch": "à¦†à¦ªà¦¨à¦¾à¦° à¦¬à¦°à§à¦¤à¦®à¦¾à¦¨ à¦«à¦¿à¦²à§à¦Ÿà¦¾à¦°à§‡à¦° à¦¸à¦¾à¦¥à§‡ à¦•à§‹à¦¨à§‹ à¦˜à¦Ÿà¦¨à¦¾ à¦®à§‡à¦²à§‡ à¦¨à¦¾à¥¤",

    "category.women_safety": "à¦¨à¦¾à¦°à§€ à¦¨à¦¿à¦°à¦¾à¦ªà¦¤à§à¦¤à¦¾",
    "category.child_safety": "à¦¶à¦¿à¦¶à§ à¦¨à¦¿à¦°à¦¾à¦ªà¦¤à§à¦¤à¦¾",
    "category.senior_citizen": "à¦ªà§à¦°à¦¬à§€à¦£ à¦¨à¦¾à¦—à¦°à¦¿à¦•",
    "category.violence": "à¦¸à¦¹à¦¿à¦‚à¦¸à¦¤à¦¾",
    "category.medical": "à¦šà¦¿à¦•à¦¿à§Žà¦¸à¦¾",
    "category.accident": "à¦¦à§à¦°à§à¦˜à¦Ÿà¦¨à¦¾",
    "category.fire": "à¦†à¦—à§à¦¨",
    "category.natural_disaster": "à¦ªà§à¦°à¦¾à¦•à§ƒà¦¤à¦¿à¦• à¦¦à§à¦°à§à¦¯à§‹à¦—",
    "category.general_sos": "à¦¸à¦¾à¦§à¦¾à¦°à¦£ à¦à¦¸à¦“à¦à¦¸",

    "drawer.overview": "à¦¸à¦‚à¦•à§à¦·à¦¿à¦ªà§à¦¤ à¦¬à¦¿à¦¬à¦°à¦£",
    "drawer.delivery": "à¦¬à¦¿à¦¤à¦°à¦£",
    "drawer.activity": "à¦•à¦¾à¦°à§à¦¯à¦•à¦²à¦¾à¦ª",
    "drawer.location": "à¦…à¦¬à¦¸à§à¦¥à¦¾à¦¨",
    "drawer.status": "à¦…à¦¬à¦¸à§à¦¥à¦¾",
    "drawer.reported": "à¦°à¦¿à¦ªà§‹à¦°à§à¦Ÿ à¦•à¦°à¦¾",
    "drawer.coordinates": "à¦¸à§à¦¥à¦¾à¦¨à¦¾à¦™à§à¦•",
    "drawer.meshPath": "à¦®à§‡à¦¶ à¦ªà¦¥",

    "gov.title": "à¦¸à¦°à¦•à¦¾à¦°à¦¿ à¦¬à¦¿à¦œà§à¦žà¦ªà§à¦¤à¦¿",
    "gov.simulated": "à¦…à¦¨à§à¦•à¦°à¦£à§€à¦¯à¦¼ â€” à¦®à¦• à¦…à§à¦¯à¦¾à¦¡à¦¾à¦ªà§à¦Ÿà¦¾à¦°",
    "gov.noReal": "à¦•à§‹à¦¨à§‹ à¦ªà§à¦°à¦•à§ƒà¦¤ 112/ERSS à¦à¦•à§€à¦•à¦°à¦£ à¦…à¦¨à§à¦®à§‹à¦¦à¦¿à¦¤ à¦¨à¦¯à¦¼à¥¤ à¦°à§‡à¦«à¦¾à¦°à§‡à¦¨à§à¦¸ à¦†à¦‡à¦¡à¦¿ à¦…à¦¨à§à¦•à¦°à¦£à§€à¦¯à¦¼à¥¤",
    "gov.none": "à¦à¦‡ à¦˜à¦Ÿà¦¨à¦¾à¦° à¦œà¦¨à§à¦¯ à¦•à§‹à¦¨à§‹ à¦¸à¦°à¦•à¦¾à¦°à¦¿ à¦¬à¦¿à¦œà§à¦žà¦ªà§à¦¤à¦¿ à¦°à§‡à¦•à¦°à§à¦¡ à¦•à¦°à¦¾ à¦¹à¦¯à¦¼à¦¨à¦¿à¥¤",
    "gov.reference": "à¦°à§‡à¦«à¦¾à¦°à§‡à¦¨à§à¦¸",

    "critical.eyebrow": "à¦¸à¦‚à¦•à¦Ÿà¦œà¦¨à¦• à¦…à¦—à§à¦°à¦¾à¦§à¦¿à¦•à¦¾à¦°",
    "critical.viewDetails": "à¦¸à¦®à§à¦ªà§‚à¦°à§à¦£ à¦¬à¦¿à¦¬à¦°à¦£ à¦¦à§‡à¦–à§à¦¨",
    "critical.acknowledge": "à¦¸à§à¦¬à§€à¦•à¦¾à¦° à¦•à¦°à§à¦¨",

    "lang.label": "à¦­à¦¾à¦·à¦¾",
  },

  ta: {
    "nav.dashboard": "à®Ÿà®¾à®·à¯à®ªà¯‹à®°à¯à®Ÿà¯",
    "nav.map": "à®¨à¯‡à®°à®Ÿà®¿ à®µà®°à¯ˆà®ªà®Ÿà®®à¯",
    "nav.incidents": "à®šà®®à¯à®ªà®µà®™à¯à®•à®³à¯",
    "nav.categories": "à®µà®•à¯ˆà®•à®³à¯",
    "nav.analytics": "à®ªà®•à¯à®ªà¯à®ªà®¾à®¯à¯à®µà¯",
    "nav.resources": "à®µà®³à®™à¯à®•à®³à¯",
    "nav.teams": "à®•à¯à®´à¯à®•à¯à®•à®³à¯",
    "nav.settings": "à®…à®®à¯ˆà®ªà¯à®ªà¯à®•à®³à¯",
    "nav.mainMenu": "à®®à¯à®¤à®©à¯à®®à¯ˆ à®®à¯†à®©à¯",

    "status.systemStatus": "à®…à®®à¯ˆà®ªà¯à®ªà¯ à®¨à®¿à®²à¯ˆ",
    "status.live": "à®¨à¯‡à®°à®²à¯ˆ (à®ªà®¿à®©à¯à®¤à®³à®®à¯ à®‡à®£à¯ˆà®•à¯à®•à®ªà¯à®ªà®Ÿà¯à®Ÿà®¤à¯)",
    "status.offline": "à®†à®ƒà®ªà¯à®²à¯ˆà®©à¯ (à®®à®¾à®¤à®¿à®°à®¿ à®¤à®°à®µà¯)",
    "status.lastSynced": "à®•à®Ÿà¯ˆà®šà®¿ à®’à®¤à¯à®¤à®¿à®šà¯ˆà®µà¯",

    "priority.critical": "à®®à®¿à®• à®…à®µà®šà®°à®®à¯",
    "priority.high": "à®‰à®¯à®°à¯",
    "priority.medium": "à®¨à®Ÿà¯à®¤à¯à®¤à®°",
    "priority.low": "à®•à¯à®±à¯ˆà®µà¯",

    "incident.active": "à®šà¯†à®¯à®²à®¿à®²à¯",
    "incident.closed": "à®®à¯‚à®Ÿà®ªà¯à®ªà®Ÿà¯à®Ÿà®¤à¯",
    "incident.markResolved": "à®¤à¯€à®°à¯à®•à¯à®•à®ªà¯à®ªà®Ÿà¯à®Ÿà®¤à®¾à®•à®•à¯ à®•à¯à®±à®¿",
    "incident.noMatch": "à®‰à®™à¯à®•à®³à¯ à®¤à®±à¯à®ªà¯‹à®¤à¯ˆà®¯ à®µà®Ÿà®¿à®•à®Ÿà¯à®Ÿà®¿à®•à®³à¯à®Ÿà®©à¯ à®Žà®¨à¯à®¤ à®šà®®à¯à®ªà®µà®®à¯à®®à¯ à®ªà¯Šà®°à¯à®¨à¯à®¤à®µà®¿à®²à¯à®²à¯ˆ.",

    "category.women_safety": "à®ªà¯†à®£à¯à®•à®³à¯ à®ªà®¾à®¤à¯à®•à®¾à®ªà¯à®ªà¯",
    "category.child_safety": "à®•à¯à®´à®¨à¯à®¤à¯ˆ à®ªà®¾à®¤à¯à®•à®¾à®ªà¯à®ªà¯",
    "category.senior_citizen": "à®®à¯‚à®¤à¯à®¤ à®•à¯à®Ÿà®¿à®®à®•à®©à¯",
    "category.violence": "à®µà®©à¯à®®à¯à®±à¯ˆ",
    "category.medical": "à®®à®°à¯à®¤à¯à®¤à¯à®µà®®à¯",
    "category.accident": "à®µà®¿à®ªà®¤à¯à®¤à¯",
    "category.fire": "à®¤à¯€",
    "category.natural_disaster": "à®‡à®¯à®±à¯à®•à¯ˆ à®ªà¯‡à®°à®¿à®Ÿà®°à¯",
    "category.general_sos": "à®ªà¯Šà®¤à¯ SOS",

    "drawer.overview": "à®®à¯‡à®²à¯‹à®Ÿà¯à®Ÿà®®à¯",
    "drawer.delivery": "à®µà®´à®™à¯à®•à®²à¯",
    "drawer.activity": "à®šà¯†à®¯à®²à¯à®ªà®¾à®Ÿà¯",
    "drawer.location": "à®‡à®Ÿà®®à¯",
    "drawer.status": "à®¨à®¿à®²à¯ˆ",
    "drawer.reported": "à®¤à¯†à®°à®¿à®µà®¿à®•à¯à®•à®ªà¯à®ªà®Ÿà¯à®Ÿà®¤à¯",
    "drawer.coordinates": "à®†à®¯à®¤à¯à®¤à¯Šà®²à¯ˆà®µà¯à®•à®³à¯",
    "drawer.meshPath": "à®®à¯†à®·à¯ à®ªà®¾à®¤à¯ˆ",

    "gov.title": "à®…à®°à®šà¯ à®…à®±à®¿à®µà®¿à®ªà¯à®ªà¯",
    "gov.simulated": "à®‰à®°à¯à®µà®•à®ªà¯à®ªà®Ÿà¯à®¤à¯à®¤à®ªà¯à®ªà®Ÿà¯à®Ÿà®¤à¯ â€” à®®à®¾à®¤à®¿à®°à®¿ à®…à®Ÿà®¾à®ªà¯à®Ÿà®°à¯",
    "gov.noReal": "à®‰à®£à¯à®®à¯ˆà®¯à®¾à®© 112/ERSS à®’à®°à¯à®™à¯à®•à®¿à®£à¯ˆà®ªà¯à®ªà¯ à®…à®™à¯à®•à¯€à®•à®°à®¿à®•à¯à®•à®ªà¯à®ªà®Ÿà®µà®¿à®²à¯à®²à¯ˆ. à®•à¯à®±à®¿à®ªà¯à®ªà¯ à®à®Ÿà®¿à®•à®³à¯ à®‰à®°à¯à®µà®•à®ªà¯à®ªà®Ÿà¯à®¤à¯à®¤à®ªà¯à®ªà®Ÿà¯à®Ÿà®µà¯ˆ.",
    "gov.none": "à®‡à®¨à¯à®¤ à®šà®®à¯à®ªà®µà®¤à¯à®¤à®¿à®±à¯à®•à¯ à®…à®°à®šà¯ à®…à®±à®¿à®µà®¿à®ªà¯à®ªà¯ à®ªà®¤à®¿à®µà¯ à®šà¯†à®¯à¯à®¯à®ªà¯à®ªà®Ÿà®µà®¿à®²à¯à®²à¯ˆ.",
    "gov.reference": "à®•à¯à®±à®¿à®ªà¯à®ªà¯",

    "critical.eyebrow": "à®®à®¿à®• à®…à®µà®šà®° à®®à¯à®©à¯à®©à¯à®°à®¿à®®à¯ˆ",
    "critical.viewDetails": "à®®à¯à®´à¯ à®µà®¿à®µà®°à®™à¯à®•à®³à¯ˆà®ªà¯ à®ªà®¾à®°à¯à®•à¯à®•",
    "critical.acknowledge": "à®’à®ªà¯à®ªà¯à®•à¯à®•à¯Šà®³à¯",

    "lang.label": "à®®à¯Šà®´à®¿",
  },

  te: {
    "nav.dashboard": "à°¡à°¾à°·à±â€Œà°¬à±‹à°°à±à°¡à±",
    "nav.map": "à°²à±ˆà°µà± à°®à±à°¯à°¾à°ªà±",
    "nav.incidents": "à°¸à°‚à°˜à°Ÿà°¨à°²à±",
    "nav.categories": "à°µà°°à±à°—à°¾à°²à±",
    "nav.analytics": "à°µà°¿à°¶à±à°²à±‡à°·à°£",
    "nav.resources": "à°µà°¨à°°à±à°²à±",
    "nav.teams": "à°¬à±ƒà°‚à°¦à°¾à°²à±",
    "nav.settings": "à°¸à±†à°Ÿà±à°Ÿà°¿à°‚à°—à±â€Œà°²à±",
    "nav.mainMenu": "à°ªà±à°°à°§à°¾à°¨ à°®à±†à°¨à±‚",

    "status.systemStatus": "à°¸à°¿à°¸à±à°Ÿà°®à± à°¸à±à°¥à°¿à°¤à°¿",
    "status.live": "à°²à±ˆà°µà± (à°¬à±à°¯à°¾à°•à±†à°‚à°¡à± à°•à°¨à±†à°•à±à°Ÿà± à°…à°¯à°¿à°‚à°¦à°¿)",
    "status.offline": "à°†à°«à±â€Œà°²à±ˆà°¨à± (à°¨à°®à±‚à°¨à°¾ à°¡à±‡à°Ÿà°¾)",
    "status.lastSynced": "à°šà°¿à°µà°°à°¿ à°¸à°®à°•à°¾à°²à±€à°•à°°à°£",

    "priority.critical": "à°…à°¤à±à°¯à°‚à°¤ à°¤à±€à°µà±à°°à°‚",
    "priority.high": "à°…à°§à°¿à°•",
    "priority.medium": "à°®à°§à±à°¯à°¸à±à°¥à°‚",
    "priority.low": "à°¤à°•à±à°•à±à°µ",

    "incident.active": "à°•à±à°°à°¿à°¯à°¾à°¶à±€à°²à°‚",
    "incident.closed": "à°®à±‚à°¸à°¿à°µà±‡à°¯à°¬à°¡à°¿à°‚à°¦à°¿",
    "incident.markResolved": "à°ªà°°à°¿à°·à±à°•à°°à°¿à°‚à°šà°¿à°¨à°Ÿà±à°²à± à°—à±à°°à±à°¤à°¿à°‚à°šà°‚à°¡à°¿",
    "incident.noMatch": "à°®à±€ à°ªà±à°°à°¸à±à°¤à±à°¤ à°«à°¿à°²à±à°Ÿà°°à±â€Œà°²à°¤à±‹ à° à°¸à°‚à°˜à°Ÿà°¨à°¾ à°¸à°°à°¿à°ªà±‹à°²à°²à±‡à°¦à±.",

    "category.women_safety": "à°®à°¹à°¿à°³à°¾ à°­à°¦à±à°°à°¤",
    "category.child_safety": "à°ªà°¿à°²à±à°²à°² à°­à°¦à±à°°à°¤",
    "category.senior_citizen": "à°µà±ƒà°¦à±à°§ à°ªà±Œà°°à±à°²à±",
    "category.violence": "à°¹à°¿à°‚à°¸",
    "category.medical": "à°µà±ˆà°¦à±à°¯à°‚",
    "category.accident": "à°ªà±à°°à°®à°¾à°¦à°‚",
    "category.fire": "à°…à°—à±à°¨à°¿",
    "category.natural_disaster": "à°ªà±à°°à°•à±ƒà°¤à°¿ à°µà°¿à°ªà°¤à±à°¤à±",
    "category.general_sos": "à°¸à°¾à°§à°¾à°°à°£ SOS",

    "drawer.overview": "à°…à°µà°²à±‹à°•à°¨à°‚",
    "drawer.delivery": "à°ªà°‚à°ªà°¿à°£à±€",
    "drawer.activity": "à°•à°¾à°°à±à°¯à°•à°²à°¾à°ªà°‚",
    "drawer.location": "à°¸à±à°¥à°¾à°¨à°‚",
    "drawer.status": "à°¸à±à°¥à°¿à°¤à°¿",
    "drawer.reported": "à°¨à°¿à°µà±‡à°¦à°¿à°‚à°šà°¬à°¡à°¿à°‚à°¦à°¿",
    "drawer.coordinates": "à°•à±‹à°†à°°à±à°¡à°¿à°¨à±‡à°Ÿà±à°²à±",
    "drawer.meshPath": "à°®à±†à°·à± à°®à°¾à°°à±à°—à°‚",

    "gov.title": "à°ªà±à°°à°­à±à°¤à±à°µ à°¨à±‹à°Ÿà°¿à°«à°¿à°•à±‡à°·à°¨à±",
    "gov.simulated": "à°…à°¨à±à°•à°°à°£ â€” à°®à°¾à°•à± à°…à°¡à°¾à°ªà±à°Ÿà°°à±",
    "gov.noReal": "à°¨à°¿à°œà°®à±ˆà°¨ 112/ERSS à°à°•à±€à°•à°°à°£ à°…à°§à°¿à°•à°¾à°°à°‚ à°²à±‡à°¦à±. à°°à°¿à°«à°°à±†à°¨à±à°¸à± IDà°²à± à°…à°¨à±à°•à°°à°£.",
    "gov.none": "à°ˆ à°¸à°‚à°˜à°Ÿà°¨à°•à± à°ªà±à°°à°­à±à°¤à±à°µ à°¨à±‹à°Ÿà°¿à°«à°¿à°•à±‡à°·à°¨à± à°¨à°®à±‹à°¦à± à°•à°¾à°²à±‡à°¦à±.",
    "gov.reference": "à°¸à±‚à°šà°¨",

    "critical.eyebrow": "à°…à°¤à±à°¯à°‚à°¤ à°¤à±€à°µà±à°° à°ªà±à°°à°¾à°§à°¾à°¨à±à°¯à°¤",
    "critical.viewDetails": "à°ªà±‚à°°à±à°¤à°¿ à°µà°¿à°µà°°à°¾à°²à± à°šà±‚à°¡à°‚à°¡à°¿",
    "critical.acknowledge": "à°…à°‚à°—à±€à°•à°°à°¿à°‚à°šà°‚à°¡à°¿",

    "lang.label": "à°­à°¾à°·",
  },

  mr: {
    "nav.dashboard": "à¤¡à¥…à¤¶à¤¬à¥‹à¤°à¥à¤¡",
    "nav.map": "à¤¥à¥‡à¤Ÿ à¤¨à¤•à¤¾à¤¶à¤¾",
    "nav.incidents": "à¤˜à¤Ÿà¤¨à¤¾",
    "nav.categories": "à¤¶à¥à¤°à¥‡à¤£à¥à¤¯à¤¾",
    "nav.analytics": "à¤µà¤¿à¤¶à¥à¤²à¥‡à¤·à¤£",
    "nav.resources": "à¤¸à¤‚à¤¸à¤¾à¤§à¤¨à¥‡",
    "nav.teams": "à¤¸à¤‚à¤˜",
    "nav.settings": "à¤¸à¥‡à¤Ÿà¤¿à¤‚à¤—à¥à¤œ",
    "nav.mainMenu": "à¤®à¥à¤–à¥à¤¯ à¤®à¥‡à¤¨à¥‚",

    "status.systemStatus": "à¤ªà¥à¤°à¤£à¤¾à¤²à¥€ à¤¸à¥à¤¥à¤¿à¤¤à¥€",
    "status.live": "à¤¥à¥‡à¤Ÿ (à¤¬à¥…à¤•à¤à¤‚à¤¡ à¤œà¥‹à¤¡à¤²à¥‡à¤²à¥‡)",
    "status.offline": "à¤‘à¤«à¤²à¤¾à¤‡à¤¨ (à¤¨à¤®à¥à¤¨à¤¾ à¤¡à¥‡à¤Ÿà¤¾)",
    "status.lastSynced": "à¤¶à¥‡à¤µà¤Ÿà¤šà¥‡ à¤¸à¤¿à¤‚à¤•",

    "priority.critical": "à¤…à¤¤à¥à¤¯à¤‚à¤¤ à¤—à¤‚à¤­à¥€à¤°",
    "priority.high": "à¤‰à¤šà¥à¤š",
    "priority.medium": "à¤®à¤§à¥à¤¯à¤®",
    "priority.low": "à¤•à¤®à¥€",

    "incident.active": "à¤¸à¤•à¥à¤°à¤¿à¤¯",
    "incident.closed": "à¤¬à¤‚à¤¦",
    "incident.markResolved": "à¤¨à¤¿à¤°à¤¾à¤•à¤°à¤£ à¤®à¥à¤¹à¤£à¥‚à¤¨ à¤šà¤¿à¤¨à¥à¤¹à¤¾à¤‚à¤•à¤¿à¤¤ à¤•à¤°à¤¾",
    "incident.noMatch": "à¤¤à¥à¤®à¤šà¥à¤¯à¤¾ à¤¸à¤§à¥à¤¯à¤¾à¤šà¥à¤¯à¤¾ à¤«à¤¿à¤²à¥à¤Ÿà¤°à¤¶à¥€ à¤•à¥‹à¤£à¤¤à¥€à¤¹à¥€ à¤˜à¤Ÿà¤¨à¤¾ à¤œà¥à¤³à¤¤ à¤¨à¤¾à¤¹à¥€.",

    "category.women_safety": "à¤®à¤¹à¤¿à¤²à¤¾ à¤¸à¥à¤°à¤•à¥à¤·à¤¾",
    "category.child_safety": "à¤¬à¤¾à¤² à¤¸à¥à¤°à¤•à¥à¤·à¤¾",
    "category.senior_citizen": "à¤œà¥à¤¯à¥‡à¤·à¥à¤  à¤¨à¤¾à¤—à¤°à¤¿à¤•",
    "category.violence": "à¤¹à¤¿à¤‚à¤¸à¤¾",
    "category.medical": "à¤µà¥ˆà¤¦à¥à¤¯à¤•à¥€à¤¯",
    "category.accident": "à¤…à¤ªà¤˜à¤¾à¤¤",
    "category.fire": "à¤†à¤—",
    "category.natural_disaster": "à¤¨à¥ˆà¤¸à¤°à¥à¤—à¤¿à¤• à¤†à¤ªà¤¤à¥à¤¤à¥€",
    "category.general_sos": "à¤¸à¤¾à¤®à¤¾à¤¨à¥à¤¯ à¤à¤¸à¤“à¤à¤¸",

    "drawer.overview": "à¤†à¤¢à¤¾à¤µà¤¾",
    "drawer.delivery": "à¤µà¤¿à¤¤à¤°à¤£",
    "drawer.activity": "à¤•à¥à¤°à¤¿à¤¯à¤¾à¤•à¤²à¤¾à¤ª",
    "drawer.location": "à¤¸à¥à¤¥à¤¾à¤¨",
    "drawer.status": "à¤¸à¥à¤¥à¤¿à¤¤à¥€",
    "drawer.reported": "à¤¨à¥‹à¤‚à¤¦à¤µà¤²à¥‡",
    "drawer.coordinates": "à¤¨à¤¿à¤°à¥à¤¦à¥‡à¤¶à¤¾à¤‚à¤•",
    "drawer.meshPath": "à¤®à¥‡à¤¶ à¤®à¤¾à¤°à¥à¤—",

    "gov.title": "à¤¸à¤°à¤•à¤¾à¤°à¥€ à¤¸à¥‚à¤šà¤¨à¤¾",
    "gov.simulated": "à¤…à¤¨à¥à¤°à¥‚à¤ªà¤¿à¤¤ â€” à¤®à¥‰à¤• à¤…â€à¥…à¤¡à¥‰à¤ªà¥à¤Ÿà¤°",
    "gov.noReal": "à¤•à¥‹à¤£à¤¤à¥‡à¤¹à¥€ à¤µà¤¾à¤¸à¥à¤¤à¤µà¤¿à¤• 112/ERSS à¤à¤•à¤¤à¥à¤°à¥€à¤•à¤°à¤£ à¤…à¤§à¤¿à¤•à¥ƒà¤¤ à¤¨à¤¾à¤¹à¥€. à¤¸à¤‚à¤¦à¤°à¥à¤­ à¤†à¤¯à¤¡à¥€ à¤…à¤¨à¥à¤°à¥‚à¤ªà¤¿à¤¤ à¤†à¤¹à¥‡à¤¤.",
    "gov.none": "à¤¯à¤¾ à¤˜à¤Ÿà¤¨à¥‡à¤¸à¤¾à¤ à¥€ à¤•à¥‹à¤£à¤¤à¥€à¤¹à¥€ à¤¸à¤°à¤•à¤¾à¤°à¥€ à¤¸à¥‚à¤šà¤¨à¤¾ à¤¨à¥‹à¤‚à¤¦à¤µà¤²à¥€ à¤—à¥‡à¤²à¥€ à¤¨à¤¾à¤¹à¥€.",
    "gov.reference": "à¤¸à¤‚à¤¦à¤°à¥à¤­",

    "critical.eyebrow": "à¤…à¤¤à¥à¤¯à¤‚à¤¤ à¤—à¤‚à¤­à¥€à¤° à¤ªà¥à¤°à¤¾à¤§à¤¾à¤¨à¥à¤¯",
    "critical.viewDetails": "à¤¸à¤‚à¤ªà¥‚à¤°à¥à¤£ à¤¤à¤ªà¤¶à¥€à¤² à¤ªà¤¹à¤¾",
    "critical.acknowledge": "à¤¸à¥à¤µà¥€à¤•à¤¾à¤°à¤¾",

    "lang.label": "à¤­à¤¾à¤·à¤¾",
  },
};

/**
 * Returns the translated string for `key` in `lang`.
 *
 * Falls back to English, then to the key itself. Returning the key
 * rather than an empty string is deliberate: a missing translation
 * shows up as visible, findable text like "gov.title" instead of
 * silently rendering a blank label that nobody notices until a demo.
 */
export function translate(lang, key) {
  const table = translations[lang] || translations.en;
  return table[key] ?? translations.en[key] ?? key;
}

export function isSupportedLanguage(code) {
  return Object.prototype.hasOwnProperty.call(translations, code);
}

