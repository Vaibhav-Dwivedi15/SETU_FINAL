// =====================================================
// SETU Dashboard
// Utility : Internationalization (i18n)
// =====================================================
//
// Lightweight i18n with no dependency — the dashboard's translatable
// surface is small enough that pulling in react-i18next would cost more
// than it saves.
//
// SCOPE, HONESTLY: this translates the dashboard's own UI CHROME (nav,
// labels, buttons, status text). It does NOT translate incident content
// — incident messages arrive from the backend already translated to
// English by Whisper (see Backend/app/routers/voice.py), and typed
// reports are stored as sent. So switching language here changes the
// responder's interface, not the reported data. Don't claim otherwise.
//
// Languages chosen to cover the largest speaker populations in the
// deployment region plus English as the working default.

export const LANGUAGES = [
  { code: "en", label: "English", native: "English" },
  { code: "hi", label: "Hindi", native: "हिन्दी" },
  { code: "bn", label: "Bengali", native: "বাংলা" },
  { code: "ta", label: "Tamil", native: "தமிழ்" },
  { code: "te", label: "Telugu", native: "తెలుగు" },
  { code: "mr", label: "Marathi", native: "मराठी" },
];

const translations = {
  en: {
    "nav.dashboard": "Dashboard",
    "nav.map": "Live Map",
    "nav.incidents": "Incidents",
    "nav.categories": "Categories",
    "nav.analytics": "Analytics",
    "nav.resources": "Resources",
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
    "gov.simulated": "SIMULATED — mock adapter",
    "gov.noReal": "No real 112/ERSS integration is authorized. Reference IDs are simulated.",
    "gov.none": "No government notification recorded for this incident.",
    "gov.reference": "Reference",

    "critical.eyebrow": "CRITICAL PRIORITY",
    "critical.viewDetails": "View Full Details",
    "critical.acknowledge": "Acknowledge",

    "lang.label": "Language",
  },

  hi: {
    "nav.dashboard": "डैशबोर्ड",
    "nav.map": "लाइव मानचित्र",
    "nav.incidents": "घटनाएँ",
    "nav.categories": "श्रेणियाँ",
    "nav.analytics": "विश्लेषण",
    "nav.resources": "संसाधन",
    "nav.teams": "टीमें",
    "nav.settings": "सेटिंग्स",
    "nav.mainMenu": "मुख्य मेन्यू",

    "status.systemStatus": "सिस्टम स्थिति",
    "status.live": "लाइव (बैकएंड जुड़ा हुआ)",
    "status.offline": "ऑफ़लाइन (नमूना डेटा)",
    "status.lastSynced": "अंतिम सिंक",

    "priority.critical": "अति गंभीर",
    "priority.high": "उच्च",
    "priority.medium": "मध्यम",
    "priority.low": "निम्न",

    "incident.active": "सक्रिय",
    "incident.closed": "बंद",
    "incident.markResolved": "हल के रूप में चिह्नित करें",
    "incident.noMatch": "आपके वर्तमान फ़िल्टर से कोई घटना मेल नहीं खाती।",

    "category.women_safety": "महिला सुरक्षा",
    "category.child_safety": "बाल सुरक्षा",
    "category.senior_citizen": "वरिष्ठ नागरिक",
    "category.violence": "हिंसा",
    "category.medical": "चिकित्सा",
    "category.accident": "दुर्घटना",
    "category.fire": "आग",
    "category.natural_disaster": "प्राकृतिक आपदा",
    "category.general_sos": "सामान्य एसओएस",

    "drawer.overview": "अवलोकन",
    "drawer.delivery": "वितरण",
    "drawer.activity": "गतिविधि",
    "drawer.location": "स्थान",
    "drawer.status": "स्थिति",
    "drawer.reported": "सूचित",
    "drawer.coordinates": "निर्देशांक",
    "drawer.meshPath": "मेश पथ",

    "gov.title": "सरकारी अधिसूचना",
    "gov.simulated": "अनुरूपित — मॉक एडाप्टर",
    "gov.noReal": "कोई वास्तविक 112/ERSS एकीकरण अधिकृत नहीं है। संदर्भ आईडी अनुरूपित हैं।",
    "gov.none": "इस घटना के लिए कोई सरकारी अधिसूचना दर्ज नहीं है।",
    "gov.reference": "संदर्भ",

    "critical.eyebrow": "अति गंभीर प्राथमिकता",
    "critical.viewDetails": "पूरा विवरण देखें",
    "critical.acknowledge": "स्वीकार करें",

    "lang.label": "भाषा",
  },

  bn: {
    "nav.dashboard": "ড্যাশবোর্ড",
    "nav.map": "লাইভ মানচিত্র",
    "nav.incidents": "ঘটনা",
    "nav.categories": "বিভাগ",
    "nav.analytics": "বিশ্লেষণ",
    "nav.resources": "সম্পদ",
    "nav.teams": "দল",
    "nav.settings": "সেটিংস",
    "nav.mainMenu": "প্রধান মেনু",

    "status.systemStatus": "সিস্টেমের অবস্থা",
    "status.live": "লাইভ (ব্যাকএন্ড সংযুক্ত)",
    "status.offline": "অফলাইন (নমুনা তথ্য)",
    "status.lastSynced": "সর্বশেষ সিঙ্ক",

    "priority.critical": "সংকটজনক",
    "priority.high": "উচ্চ",
    "priority.medium": "মাঝারি",
    "priority.low": "নিম্ন",

    "incident.active": "সক্রিয়",
    "incident.closed": "বন্ধ",
    "incident.markResolved": "সমাধান হিসেবে চিহ্নিত করুন",
    "incident.noMatch": "আপনার বর্তমান ফিল্টারের সাথে কোনো ঘটনা মেলে না।",

    "category.women_safety": "নারী নিরাপত্তা",
    "category.child_safety": "শিশু নিরাপত্তা",
    "category.senior_citizen": "প্রবীণ নাগরিক",
    "category.violence": "সহিংসতা",
    "category.medical": "চিকিৎসা",
    "category.accident": "দুর্ঘটনা",
    "category.fire": "আগুন",
    "category.natural_disaster": "প্রাকৃতিক দুর্যোগ",
    "category.general_sos": "সাধারণ এসওএস",

    "drawer.overview": "সংক্ষিপ্ত বিবরণ",
    "drawer.delivery": "বিতরণ",
    "drawer.activity": "কার্যকলাপ",
    "drawer.location": "অবস্থান",
    "drawer.status": "অবস্থা",
    "drawer.reported": "রিপোর্ট করা",
    "drawer.coordinates": "স্থানাঙ্ক",
    "drawer.meshPath": "মেশ পথ",

    "gov.title": "সরকারি বিজ্ঞপ্তি",
    "gov.simulated": "অনুকরণীয় — মক অ্যাডাপ্টার",
    "gov.noReal": "কোনো প্রকৃত 112/ERSS একীকরণ অনুমোদিত নয়। রেফারেন্স আইডি অনুকরণীয়।",
    "gov.none": "এই ঘটনার জন্য কোনো সরকারি বিজ্ঞপ্তি রেকর্ড করা হয়নি।",
    "gov.reference": "রেফারেন্স",

    "critical.eyebrow": "সংকটজনক অগ্রাধিকার",
    "critical.viewDetails": "সম্পূর্ণ বিবরণ দেখুন",
    "critical.acknowledge": "স্বীকার করুন",

    "lang.label": "ভাষা",
  },

  ta: {
    "nav.dashboard": "டாஷ்போர்டு",
    "nav.map": "நேரடி வரைபடம்",
    "nav.incidents": "சம்பவங்கள்",
    "nav.categories": "வகைகள்",
    "nav.analytics": "பகுப்பாய்வு",
    "nav.resources": "வளங்கள்",
    "nav.teams": "குழுக்கள்",
    "nav.settings": "அமைப்புகள்",
    "nav.mainMenu": "முதன்மை மெனு",

    "status.systemStatus": "அமைப்பு நிலை",
    "status.live": "நேரலை (பின்தளம் இணைக்கப்பட்டது)",
    "status.offline": "ஆஃப்லைன் (மாதிரி தரவு)",
    "status.lastSynced": "கடைசி ஒத்திசைவு",

    "priority.critical": "மிக அவசரம்",
    "priority.high": "உயர்",
    "priority.medium": "நடுத்தர",
    "priority.low": "குறைவு",

    "incident.active": "செயலில்",
    "incident.closed": "மூடப்பட்டது",
    "incident.markResolved": "தீர்க்கப்பட்டதாகக் குறி",
    "incident.noMatch": "உங்கள் தற்போதைய வடிகட்டிகளுடன் எந்த சம்பவமும் பொருந்தவில்லை.",

    "category.women_safety": "பெண்கள் பாதுகாப்பு",
    "category.child_safety": "குழந்தை பாதுகாப்பு",
    "category.senior_citizen": "மூத்த குடிமகன்",
    "category.violence": "வன்முறை",
    "category.medical": "மருத்துவம்",
    "category.accident": "விபத்து",
    "category.fire": "தீ",
    "category.natural_disaster": "இயற்கை பேரிடர்",
    "category.general_sos": "பொது SOS",

    "drawer.overview": "மேலோட்டம்",
    "drawer.delivery": "வழங்கல்",
    "drawer.activity": "செயல்பாடு",
    "drawer.location": "இடம்",
    "drawer.status": "நிலை",
    "drawer.reported": "தெரிவிக்கப்பட்டது",
    "drawer.coordinates": "ஆயத்தொலைவுகள்",
    "drawer.meshPath": "மெஷ் பாதை",

    "gov.title": "அரசு அறிவிப்பு",
    "gov.simulated": "உருவகப்படுத்தப்பட்டது — மாதிரி அடாப்டர்",
    "gov.noReal": "உண்மையான 112/ERSS ஒருங்கிணைப்பு அங்கீகரிக்கப்படவில்லை. குறிப்பு ஐடிகள் உருவகப்படுத்தப்பட்டவை.",
    "gov.none": "இந்த சம்பவத்திற்கு அரசு அறிவிப்பு பதிவு செய்யப்படவில்லை.",
    "gov.reference": "குறிப்பு",

    "critical.eyebrow": "மிக அவசர முன்னுரிமை",
    "critical.viewDetails": "முழு விவரங்களைப் பார்க்க",
    "critical.acknowledge": "ஒப்புக்கொள்",

    "lang.label": "மொழி",
  },

  te: {
    "nav.dashboard": "డాష్‌బోర్డ్",
    "nav.map": "లైవ్ మ్యాప్",
    "nav.incidents": "సంఘటనలు",
    "nav.categories": "వర్గాలు",
    "nav.analytics": "విశ్లేషణ",
    "nav.resources": "వనరులు",
    "nav.teams": "బృందాలు",
    "nav.settings": "సెట్టింగ్‌లు",
    "nav.mainMenu": "ప్రధాన మెనూ",

    "status.systemStatus": "సిస్టమ్ స్థితి",
    "status.live": "లైవ్ (బ్యాకెండ్ కనెక్ట్ అయింది)",
    "status.offline": "ఆఫ్‌లైన్ (నమూనా డేటా)",
    "status.lastSynced": "చివరి సమకాలీకరణ",

    "priority.critical": "అత్యంత తీవ్రం",
    "priority.high": "అధిక",
    "priority.medium": "మధ్యస్థం",
    "priority.low": "తక్కువ",

    "incident.active": "క్రియాశీలం",
    "incident.closed": "మూసివేయబడింది",
    "incident.markResolved": "పరిష్కరించినట్లు గుర్తించండి",
    "incident.noMatch": "మీ ప్రస్తుత ఫిల్టర్‌లతో ఏ సంఘటనా సరిపోలలేదు.",

    "category.women_safety": "మహిళా భద్రత",
    "category.child_safety": "పిల్లల భద్రత",
    "category.senior_citizen": "వృద్ధ పౌరులు",
    "category.violence": "హింస",
    "category.medical": "వైద్యం",
    "category.accident": "ప్రమాదం",
    "category.fire": "అగ్ని",
    "category.natural_disaster": "ప్రకృతి విపత్తు",
    "category.general_sos": "సాధారణ SOS",

    "drawer.overview": "అవలోకనం",
    "drawer.delivery": "పంపిణీ",
    "drawer.activity": "కార్యకలాపం",
    "drawer.location": "స్థానం",
    "drawer.status": "స్థితి",
    "drawer.reported": "నివేదించబడింది",
    "drawer.coordinates": "కోఆర్డినేట్లు",
    "drawer.meshPath": "మెష్ మార్గం",

    "gov.title": "ప్రభుత్వ నోటిఫికేషన్",
    "gov.simulated": "అనుకరణ — మాక్ అడాప్టర్",
    "gov.noReal": "నిజమైన 112/ERSS ఏకీకరణ అధికారం లేదు. రిఫరెన్స్ IDలు అనుకరణ.",
    "gov.none": "ఈ సంఘటనకు ప్రభుత్వ నోటిఫికేషన్ నమోదు కాలేదు.",
    "gov.reference": "సూచన",

    "critical.eyebrow": "అత్యంత తీవ్ర ప్రాధాన్యత",
    "critical.viewDetails": "పూర్తి వివరాలు చూడండి",
    "critical.acknowledge": "అంగీకరించండి",

    "lang.label": "భాష",
  },

  mr: {
    "nav.dashboard": "डॅशबोर्ड",
    "nav.map": "थेट नकाशा",
    "nav.incidents": "घटना",
    "nav.categories": "श्रेण्या",
    "nav.analytics": "विश्लेषण",
    "nav.resources": "संसाधने",
    "nav.teams": "संघ",
    "nav.settings": "सेटिंग्ज",
    "nav.mainMenu": "मुख्य मेनू",

    "status.systemStatus": "प्रणाली स्थिती",
    "status.live": "थेट (बॅकएंड जोडलेले)",
    "status.offline": "ऑफलाइन (नमुना डेटा)",
    "status.lastSynced": "शेवटचे सिंक",

    "priority.critical": "अत्यंत गंभीर",
    "priority.high": "उच्च",
    "priority.medium": "मध्यम",
    "priority.low": "कमी",

    "incident.active": "सक्रिय",
    "incident.closed": "बंद",
    "incident.markResolved": "निराकरण म्हणून चिन्हांकित करा",
    "incident.noMatch": "तुमच्या सध्याच्या फिल्टरशी कोणतीही घटना जुळत नाही.",

    "category.women_safety": "महिला सुरक्षा",
    "category.child_safety": "बाल सुरक्षा",
    "category.senior_citizen": "ज्येष्ठ नागरिक",
    "category.violence": "हिंसा",
    "category.medical": "वैद्यकीय",
    "category.accident": "अपघात",
    "category.fire": "आग",
    "category.natural_disaster": "नैसर्गिक आपत्ती",
    "category.general_sos": "सामान्य एसओएस",

    "drawer.overview": "आढावा",
    "drawer.delivery": "वितरण",
    "drawer.activity": "क्रियाकलाप",
    "drawer.location": "स्थान",
    "drawer.status": "स्थिती",
    "drawer.reported": "नोंदवले",
    "drawer.coordinates": "निर्देशांक",
    "drawer.meshPath": "मेश मार्ग",

    "gov.title": "सरकारी सूचना",
    "gov.simulated": "अनुरूपित — मॉक अ‍ॅडॉप्टर",
    "gov.noReal": "कोणतेही वास्तविक 112/ERSS एकत्रीकरण अधिकृत नाही. संदर्भ आयडी अनुरूपित आहेत.",
    "gov.none": "या घटनेसाठी कोणतीही सरकारी सूचना नोंदवली गेली नाही.",
    "gov.reference": "संदर्भ",

    "critical.eyebrow": "अत्यंत गंभीर प्राधान्य",
    "critical.viewDetails": "संपूर्ण तपशील पहा",
    "critical.acknowledge": "स्वीकारा",

    "lang.label": "भाषा",
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
