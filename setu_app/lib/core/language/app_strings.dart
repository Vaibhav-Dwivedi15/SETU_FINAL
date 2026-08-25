// =====================================================
// SETU Project
// Module : App Strings (i18n)
// =====================================================
//
// Lightweight, no-dependency i18n — deliberately not the `intl` package
// + generated ARB files (language_selection_screen.dart's own comment
// flagged that as "a larger, separate piece of work"). This is the
// smaller alternative: a plain lookup table plus a ChangeNotifier
// (LanguageController), same "no new state-management dependency for
// one piece of state" philosophy the project already uses for theme.
//
// Key naming mirrors setu_dashboard/src/utils/i18n.js's key structure
// (e.g. "nav.home", "sos.holdToSend") so the same mental model applies
// on both the mobile app and the dashboard, even though the two are
// separate implementations with no shared code.
//
// USAGE:
//   Text(AppStrings.of(context).t('home.sosButton'))
// Rebuilds automatically when LanguageController's language changes,
// because `of(context)` reads LanguageController.instance via a
// ListenableBuilder higher up the tree (see app.dart wiring).
//
// COVERAGE — READ BEFORE ASSUMING THIS IS COMPLETE: this first pass
// covers login/OTP/voice-SOS (the screens touched in this same change)
// plus a handful of common home-screen strings, NOT every string in
// every existing screen. Missing keys fall back to English, then to the
// key itself (visible, findable, like "home.sosButton" -- not a silent
// blank), so a gap is obvious rather than hidden. Extending coverage to
// the rest of the app is mechanical but sizeable: add keys here, then
// replace hardcoded Text('...') with AppStrings.of(context).t('...')
// screen by screen.

import 'package:flutter/material.dart';

import 'package:setu_app/core/language/language_controller.dart';

class AppStrings {
  AppStrings._(this._languageCode);

  final String _languageCode;

  static AppStrings of(BuildContext context) {
    // Reads the controller directly rather than via InheritedWidget --
    // the ListenableBuilder in app.dart already rebuilds this whole
    // subtree on language change, so a plain read here is sufficient
    // and avoids introducing a second context-propagation mechanism
    // alongside ThemeController's existing one.
    return AppStrings._(LanguageController.instance.languageCode);
  }

  String t(String key) {
    final table = _translations[_languageCode] ?? _translations['en']!;
    return table[key] ?? _translations['en']![key] ?? key;
  }

  static const List<Map<String, String>> supportedLanguages = [
    {'code': 'en', 'native': 'English'},
    {'code': 'hi', 'native': 'हिन्दी'},
    {'code': 'bn', 'native': 'বাংলা'},
    {'code': 'ta', 'native': 'தமிழ்'},
    {'code': 'te', 'native': 'తెలుగు'},
    {'code': 'mr', 'native': 'मराठी'},
  ];

  static final Map<String, Map<String, String>> _translations = {
    'en': {
      'login.title': 'Login',
      'login.subtitle': 'Enter your details to get started. We\'ll email you a verification code.',
      'login.fullName': 'Full Name',
      'login.email': 'Email',
      'login.phone': 'Phone Number',
      'login.sendCode': 'Send Verification Code',
      'login.sendingCode': 'Sending code...',

      'otp.title': 'Verify Email',
      'otp.verify': 'Verify & Continue',
      'otp.verifying': 'Verifying...',
      'otp.resend': 'Resend code',

      'voice.title': 'Voice SOS',
      'voice.subtitle': 'Speak your emergency instead of typing. Works in any '
          'language — your message is understood and translated automatically.',
      'voice.tapToRecord': 'Tap to start recording',
      'voice.sent': 'Voice SOS sent',
      'voice.tryAgain': 'Try Again',

      'home.sosButton': 'SEND SOS',
      'home.voiceSos': 'Voice SOS',
      'home.nearbyAlerts': 'Nearby Alerts',
      'home.relayStatus': 'Relay Status',
      'home.history': 'History',
      'home.settings': 'Settings',

      'nearby.title': 'Nearby Alerts',
      'nearby.empty': 'No Nearby Alerts',
      'nearby.respondNearby': 'I\'m nearby',
      'nearby.respondCanHelp': 'I can help',
      'nearby.respondAlreadyResponding': 'Already responding',
      'nearby.respondCalledServices': 'Called emergency services',
      'nearby.respondNavigating': 'Navigating to location',
    },
    'hi': {
      'login.title': 'लॉगिन',
      'login.subtitle': 'शुरू करने के लिए अपनी जानकारी भरें। हम आपको ईमेल पर सत्यापन कोड भेजेंगे।',
      'login.fullName': 'पूरा नाम',
      'login.email': 'ईमेल',
      'login.phone': 'फ़ोन नंबर',
      'login.sendCode': 'सत्यापन कोड भेजें',
      'login.sendingCode': 'कोड भेजा जा रहा है...',

      'otp.title': 'ईमेल सत्यापित करें',
      'otp.verify': 'सत्यापित करें और जारी रखें',
      'otp.verifying': 'सत्यापित हो रहा है...',
      'otp.resend': 'कोड पुनः भेजें',

      'voice.title': 'वॉइस एसओएस',
      'voice.subtitle': 'टाइप करने के बजाय अपनी आपातकालीन स्थिति बोलें। किसी भी भाषा में काम करता है।',
      'voice.tapToRecord': 'रिकॉर्डिंग शुरू करने के लिए टैप करें',
      'voice.sent': 'वॉइस एसओएस भेजा गया',
      'voice.tryAgain': 'पुनः प्रयास करें',

      'home.sosButton': 'एसओएस भेजें',
      'home.voiceSos': 'वॉइस एसओएस',
      'home.nearbyAlerts': 'आस-पास की चेतावनियाँ',
      'home.relayStatus': 'रिले स्थिति',
      'home.history': 'इतिहास',
      'home.settings': 'सेटिंग्स',

      'nearby.title': 'आस-पास की चेतावनियाँ',
      'nearby.empty': 'कोई आस-पास की चेतावनी नहीं',
      'nearby.respondNearby': 'मैं पास में हूँ',
      'nearby.respondCanHelp': 'मैं मदद कर सकता हूँ',
      'nearby.respondAlreadyResponding': 'पहले से जा रहा हूँ',
      'nearby.respondCalledServices': 'आपातकालीन सेवाओं को बुलाया',
      'nearby.respondNavigating': 'स्थान की ओर जा रहा हूँ',
    },
    'bn': {
      'login.title': 'লগইন',
      'login.subtitle': 'শুরু করতে আপনার তথ্য দিন। আমরা আপনাকে ইমেইলে যাচাইকরণ কোড পাঠাব।',
      'login.fullName': 'পুরো নাম',
      'login.email': 'ইমেইল',
      'login.phone': 'ফোন নম্বর',
      'login.sendCode': 'যাচাইকরণ কোড পাঠান',
      'login.sendingCode': 'কোড পাঠানো হচ্ছে...',

      'otp.title': 'ইমেইল যাচাই করুন',
      'otp.verify': 'যাচাই করুন এবং চালিয়ে যান',
      'otp.verifying': 'যাচাই করা হচ্ছে...',
      'otp.resend': 'কোড আবার পাঠান',

      'voice.title': 'ভয়েস এসওএস',
      'voice.subtitle': 'টাইপ করার পরিবর্তে আপনার জরুরি অবস্থা বলুন।',
      'voice.tapToRecord': 'রেকর্ডিং শুরু করতে ট্যাপ করুন',
      'voice.sent': 'ভয়েস এসওএস পাঠানো হয়েছে',
      'voice.tryAgain': 'আবার চেষ্টা করুন',

      'home.sosButton': 'এসওএস পাঠান',
      'home.voiceSos': 'ভয়েস এসওএস',
      'home.nearbyAlerts': 'কাছাকাছি সতর্কতা',
      'home.relayStatus': 'রিলে অবস্থা',
      'home.history': 'ইতিহাস',
      'home.settings': 'সেটিংস',

      'nearby.title': 'কাছাকাছি সতর্কতা',
      'nearby.empty': 'কোনো কাছাকাছি সতর্কতা নেই',
      'nearby.respondNearby': 'আমি কাছাকাছি আছি',
      'nearby.respondCanHelp': 'আমি সাহায্য করতে পারি',
      'nearby.respondAlreadyResponding': 'ইতিমধ্যে যাচ্ছি',
      'nearby.respondCalledServices': 'জরুরি পরিষেবাকে কল করা হয়েছে',
      'nearby.respondNavigating': 'স্থানের দিকে যাচ্ছি',
    },
    'ta': {
      'login.title': 'உள்நுழைவு',
      'login.subtitle': 'தொடங்க உங்கள் விவரங்களை உள்ளிடவும். சரிபார்ப்பு குறியீட்டை மின்னஞ்சல் செய்வோம்.',
      'login.fullName': 'முழு பெயர்',
      'login.email': 'மின்னஞ்சல்',
      'login.phone': 'தொலைபேசி எண்',
      'login.sendCode': 'சரிபார்ப்பு குறியீட்டை அனுப்பு',
      'login.sendingCode': 'குறியீடு அனுப்பப்படுகிறது...',

      'otp.title': 'மின்னஞ்சலை சரிபார்க்கவும்',
      'otp.verify': 'சரிபார்த்து தொடரவும்',
      'otp.verifying': 'சரிபார்க்கிறது...',
      'otp.resend': 'குறியீட்டை மீண்டும் அனுப்பு',

      'voice.title': 'குரல் SOS',
      'voice.subtitle': 'தட்டச்சு செய்வதற்குப் பதிலாக உங்கள் அவசரநிலையைப் பேசுங்கள்.',
      'voice.tapToRecord': 'பதிவு தொடங்க தட்டவும்',
      'voice.sent': 'குரல் SOS அனுப்பப்பட்டது',
      'voice.tryAgain': 'மீண்டும் முயற்சிக்கவும்',

      'home.sosButton': 'SOS அனுப்பு',
      'home.voiceSos': 'குரல் SOS',
      'home.nearbyAlerts': 'அருகிலுள்ள எச்சரிக்கைகள்',
      'home.relayStatus': 'ரிலே நிலை',
      'home.history': 'வரலாறு',
      'home.settings': 'அமைப்புகள்',

      'nearby.title': 'அருகிலுள்ள எச்சரிக்கைகள்',
      'nearby.empty': 'அருகிலுள்ள எச்சரிக்கைகள் இல்லை',
      'nearby.respondNearby': 'நான் அருகில் இருக்கிறேன்',
      'nearby.respondCanHelp': 'நான் உதவ முடியும்',
      'nearby.respondAlreadyResponding': 'ஏற்கனவே செல்கிறேன்',
      'nearby.respondCalledServices': 'அவசர சேவைகளை அழைத்தேன்',
      'nearby.respondNavigating': 'இடத்திற்கு செல்கிறேன்',
    },
    'te': {
      'login.title': 'లాగిన్',
      'login.subtitle': 'ప్రారంభించడానికి మీ వివరాలను నమోదు చేయండి. మేము మీకు ఇమెయిల్‌లో ధృవీకరణ కోడ్ పంపుతాము.',
      'login.fullName': 'పూర్తి పేరు',
      'login.email': 'ఇమెయిల్',
      'login.phone': 'ఫోన్ నంబర్',
      'login.sendCode': 'ధృవీకరణ కోడ్ పంపండి',
      'login.sendingCode': 'కోడ్ పంపబడుతోంది...',

      'otp.title': 'ఇమెయిల్‌ను ధృవీకరించండి',
      'otp.verify': 'ధృవీకరించి కొనసాగించండి',
      'otp.verifying': 'ధృవీకరిస్తోంది...',
      'otp.resend': 'కోడ్‌ను మళ్లీ పంపండి',

      'voice.title': 'వాయిస్ SOS',
      'voice.subtitle': 'టైప్ చేయడానికి బదులుగా మీ అత్యవసర పరిస్థితిని మాట్లాడండి.',
      'voice.tapToRecord': 'రికార్డింగ్ ప్రారంభించడానికి నొక్కండి',
      'voice.sent': 'వాయిస్ SOS పంపబడింది',
      'voice.tryAgain': 'మళ్లీ ప్రయత్నించండి',

      'home.sosButton': 'SOS పంపండి',
      'home.voiceSos': 'వాయిస్ SOS',
      'home.nearbyAlerts': 'సమీప హెచ్చరికలు',
      'home.relayStatus': 'రిలే స్థితి',
      'home.history': 'చరిత్ర',
      'home.settings': 'సెట్టింగ్‌లు',

      'nearby.title': 'సమీప హెచ్చరికలు',
      'nearby.empty': 'సమీప హెచ్చరికలు లేవు',
      'nearby.respondNearby': 'నేను సమీపంలో ఉన్నాను',
      'nearby.respondCanHelp': 'నేను సహాయం చేయగలను',
      'nearby.respondAlreadyResponding': 'ఇప్పటికే వెళుతున్నాను',
      'nearby.respondCalledServices': 'అత్యవసర సేవలకు కాల్ చేసాను',
      'nearby.respondNavigating': 'ప్రదేశానికి వెళుతున్నాను',
    },
    'mr': {
      'login.title': 'लॉगिन',
      'login.subtitle': 'सुरू करण्यासाठी तुमचे तपशील भरा. आम्ही तुम्हाला ईमेलवर पडताळणी कोड पाठवू.',
      'login.fullName': 'पूर्ण नाव',
      'login.email': 'ईमेल',
      'login.phone': 'फोन नंबर',
      'login.sendCode': 'पडताळणी कोड पाठवा',
      'login.sendingCode': 'कोड पाठवत आहे...',

      'otp.title': 'ईमेल पडताळा',
      'otp.verify': 'पडताळा आणि सुरू ठेवा',
      'otp.verifying': 'पडताळत आहे...',
      'otp.resend': 'कोड पुन्हा पाठवा',

      'voice.title': 'व्हॉइस एसओएस',
      'voice.subtitle': 'टाइप करण्याऐवजी तुमची आणीबाणी बोला.',
      'voice.tapToRecord': 'रेकॉर्डिंग सुरू करण्यासाठी टॅप करा',
      'voice.sent': 'व्हॉइस एसओएस पाठवले',
      'voice.tryAgain': 'पुन्हा प्रयत्न करा',

      'home.sosButton': 'एसओएस पाठवा',
      'home.voiceSos': 'व्हॉइस एसओएस',
      'home.nearbyAlerts': 'जवळपासचे इशारे',
      'home.relayStatus': 'रिले स्थिती',
      'home.history': 'इतिहास',
      'home.settings': 'सेटिंग्ज',

      'nearby.title': 'जवळपासचे इशारे',
      'nearby.empty': 'जवळपास कोणतेही इशारे नाहीत',
      'nearby.respondNearby': 'मी जवळ आहे',
      'nearby.respondCanHelp': 'मी मदत करू शकतो',
      'nearby.respondAlreadyResponding': 'आधीच जात आहे',
      'nearby.respondCalledServices': 'आणीबाणी सेवांना कॉल केला',
      'nearby.respondNavigating': 'ठिकाणाकडे जात आहे',
    },
  };
}
