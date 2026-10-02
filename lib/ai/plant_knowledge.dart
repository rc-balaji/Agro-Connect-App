enum LeafLanguage { english, tamil, hindi, malayalam, kannada }

extension LeafLanguageInfo on LeafLanguage {
  String get code => switch (this) {
        LeafLanguage.english => 'en',
        LeafLanguage.tamil => 'ta',
        LeafLanguage.hindi => 'hi',
        LeafLanguage.malayalam => 'ml',
        LeafLanguage.kannada => 'kn',
      };

  String get nativeName => switch (this) {
        LeafLanguage.english => 'English',
        LeafLanguage.tamil => 'தமிழ்',
        LeafLanguage.hindi => 'हिन्दी',
        LeafLanguage.malayalam => 'മലയാളം',
        LeafLanguage.kannada => 'ಕನ್ನಡ',
      };

  static LeafLanguage fromCode(String? code) {
    return LeafLanguage.values.firstWhere(
      (e) => e.code == code,
      orElse: () => LeafLanguage.english,
    );
  }
}

class DiseaseAdvice {
  const DiseaseAdvice({
    required this.crop,
    required this.condition,
    required this.status,
    required this.symptoms,
    required this.treatment,
    required this.prevention,
    required this.note,
  });

  final String crop;
  final String condition;
  final String status;
  final List<String> symptoms;
  final List<String> treatment;
  final List<String> prevention;
  final String note;
}

class LeafText {
  static String ui(LeafLanguage lang, String key) {
    return (_ui[lang.code]?[key] ?? _ui['en']![key] ?? key);
  }

  static const Map<String, Map<String, String>> _ui = {
    'en': {
      'title': 'Leaf AI',
      'subtitle': 'Offline plant health screening',
      'live': 'Live Scan',
      'photo': 'Photo Scan',
      'start': 'Start live scan',
      'stop': 'Stop live scan',
      'capture': 'Capture photo',
      'gallery': 'Choose from gallery',
      'analyzing': 'Analyzing leaf on this device…',
      'ready': 'Model ready · Offline',
      'loading': 'Loading offline AI model…',
      'focus': 'Keep one leaf centered inside the guide',
      'result': 'AI screening result',
      'confidence': 'Confidence',
      'high': 'High confidence',
      'review': 'Review result',
      'uncertain': 'Uncertain · Retake a clear leaf photo',
      'symptoms': 'What to look for',
      'treatment': 'Care & treatment',
      'prevention': 'Prevention',
      'top': 'Other possibilities',
      'noResult': 'Scan a leaf to see an offline result.',
      'modelError': 'Offline AI model is unavailable.',
      'cameraError': 'Camera is unavailable on this device.',
      'language': 'Language',
      'offline': 'Runs fully offline after installation',
    },
    'ta': {
      'title': 'Leaf AI',
      'subtitle': 'இணையமில்லா தாவர ஆரோக்கிய பரிசோதனை',
      'live': 'நேரடி ஸ்கேன்',
      'photo': 'புகைப்பட ஸ்கேன்',
      'start': 'நேரடி ஸ்கேன் தொடங்கு',
      'stop': 'நேரடி ஸ்கேன் நிறுத்து',
      'capture': 'புகைப்படம் எடு',
      'gallery': 'கேலரியில் தேர்வு செய்',
      'analyzing': 'இந்த சாதனத்திலேயே இலையை ஆய்வு செய்கிறது…',
      'ready': 'மாடல் தயார் · Offline',
      'loading': 'Offline AI மாடல் ஏற்றப்படுகிறது…',
      'focus': 'ஒரே இலையை வழிகாட்டி பெட்டிக்குள் தெளிவாக வைக்கவும்',
      'result': 'AI ஆரம்ப பரிசோதனை முடிவு',
      'confidence': 'நம்பிக்கை',
      'high': 'உயர் நம்பிக்கை',
      'review': 'முடிவை சரிபார்க்கவும்',
      'uncertain': 'தெளிவில்லை · தெளிவான இலை புகைப்படம் எடுக்கவும்',
      'symptoms': 'கவனிக்க வேண்டிய அறிகுறிகள்',
      'treatment': 'பராமரிப்பு & சிகிச்சை',
      'prevention': 'தடுப்பு',
      'top': 'மற்ற சாத்தியங்கள்',
      'noResult': 'Offline முடிவைக் காண ஒரு இலையை ஸ்கேன் செய்யவும்.',
      'modelError': 'Offline AI மாடல் கிடைக்கவில்லை.',
      'cameraError': 'இந்த சாதனத்தில் கேமரா கிடைக்கவில்லை.',
      'language': 'மொழி',
      'offline': 'நிறுவிய பிறகு முழுவதும் offline-ல் இயங்கும்',
    },
    'hi': {
      'title': 'Leaf AI',
      'subtitle': 'ऑफलाइन पौधा स्वास्थ्य स्क्रीनिंग',
      'live': 'लाइव स्कैन',
      'photo': 'फोटो स्कैन',
      'start': 'लाइव स्कैन शुरू करें',
      'stop': 'लाइव स्कैन रोकें',
      'capture': 'फोटो लें',
      'gallery': 'गैलरी से चुनें',
      'analyzing': 'इसी डिवाइस पर पत्ती का विश्लेषण हो रहा है…',
      'ready': 'मॉडल तैयार · Offline',
      'loading': 'Offline AI मॉडल लोड हो रहा है…',
      'focus': 'एक पत्ती को गाइड के बीच साफ रखें',
      'result': 'AI स्क्रीनिंग परिणाम',
      'confidence': 'विश्वास',
      'high': 'उच्च विश्वास',
      'review': 'परिणाम की समीक्षा करें',
      'uncertain': 'अनिश्चित · साफ पत्ती की फोटो फिर लें',
      'symptoms': 'देखने योग्य लक्षण',
      'treatment': 'देखभाल और उपचार',
      'prevention': 'रोकथाम',
      'top': 'अन्य संभावनाएँ',
      'noResult': 'ऑफलाइन परिणाम के लिए पत्ती स्कैन करें।',
      'modelError': 'Offline AI मॉडल उपलब्ध नहीं है।',
      'cameraError': 'इस डिवाइस पर कैमरा उपलब्ध नहीं है।',
      'language': 'भाषा',
      'offline': 'इंस्टॉल होने के बाद पूरी तरह ऑफलाइन चलता है',
    },
    'ml': {
      'title': 'Leaf AI',
      'subtitle': 'ഓഫ്‌ലൈൻ സസ്യാരോഗ്യ സ്ക്രീനിംഗ്',
      'live': 'ലൈവ് സ്കാൻ',
      'photo': 'ഫോട്ടോ സ്കാൻ',
      'start': 'ലൈവ് സ്കാൻ ആരംഭിക്കുക',
      'stop': 'ലൈവ് സ്കാൻ നിർത്തുക',
      'capture': 'ഫോട്ടോ എടുക്കുക',
      'gallery': 'ഗാലറിയിൽ നിന്ന് തിരഞ്ഞെടുക്കുക',
      'analyzing': 'ഈ ഉപകരണത്തിൽ തന്നെ ഇല പരിശോധിക്കുന്നു…',
      'ready': 'മോഡൽ തയ്യാറാണ് · Offline',
      'loading': 'Offline AI മോഡൽ ലോഡ് ചെയ്യുന്നു…',
      'focus': 'ഒരു ഇല ഗൈഡിന്റെ മധ്യത്തിൽ വ്യക്തമായി വയ്ക്കുക',
      'result': 'AI സ്ക്രീനിംഗ് ഫലം',
      'confidence': 'വിശ്വാസനില',
      'high': 'ഉയർന്ന വിശ്വാസം',
      'review': 'ഫലം പരിശോധിക്കുക',
      'uncertain': 'അനിശ്ചിതം · വ്യക്തമായ ഇല ഫോട്ടോ വീണ്ടും എടുക്കുക',
      'symptoms': 'ശ്രദ്ധിക്കേണ്ട ലക്ഷണങ്ങൾ',
      'treatment': 'പരിചരണവും ചികിത്സയും',
      'prevention': 'പ്രതിരോധം',
      'top': 'മറ്റ് സാധ്യതകൾ',
      'noResult': 'ഓഫ്‌ലൈൻ ഫലത്തിന് ഒരു ഇല സ്കാൻ ചെയ്യുക.',
      'modelError': 'Offline AI മോഡൽ ലഭ്യമല്ല.',
      'cameraError': 'ഈ ഉപകരണത്തിൽ ക്യാമറ ലഭ്യമല്ല.',
      'language': 'ഭാഷ',
      'offline': 'ഇൻസ്റ്റാൾ ചെയ്ത ശേഷം പൂർണ്ണമായി ഓഫ്‌ലൈൻ പ്രവർത്തിക്കുന്നു',
    },
    'kn': {
      'title': 'Leaf AI',
      'subtitle': 'ಆಫ್‌ಲೈನ್ ಸಸ್ಯ ಆರೋಗ್ಯ ಪರಿಶೀಲನೆ',
      'live': 'ಲೈವ್ ಸ್ಕ್ಯಾನ್',
      'photo': 'ಫೋಟೋ ಸ್ಕ್ಯಾನ್',
      'start': 'ಲೈವ್ ಸ್ಕ್ಯಾನ್ ಪ್ರಾರಂಭಿಸಿ',
      'stop': 'ಲೈವ್ ಸ್ಕ್ಯಾನ್ ನಿಲ್ಲಿಸಿ',
      'capture': 'ಫೋಟೋ ತೆಗೆದುಕೊಳ್ಳಿ',
      'gallery': 'ಗ್ಯಾಲರಿಯಿಂದ ಆಯ್ಕೆ ಮಾಡಿ',
      'analyzing': 'ಈ ಸಾಧನದಲ್ಲೇ ಎಲೆಯನ್ನು ಪರಿಶೀಲಿಸಲಾಗುತ್ತಿದೆ…',
      'ready': 'ಮಾದರಿ ಸಿದ್ಧ · Offline',
      'loading': 'Offline AI ಮಾದರಿ ಲೋಡ್ ಆಗುತ್ತಿದೆ…',
      'focus': 'ಒಂದು ಎಲೆಯನ್ನು ಗೈಡ್ ಮಧ್ಯದಲ್ಲಿ ಸ್ಪಷ್ಟವಾಗಿ ಇರಿಸಿ',
      'result': 'AI ಪರಿಶೀಲನೆ ಫಲಿತಾಂಶ',
      'confidence': 'ವಿಶ್ವಾಸ',
      'high': 'ಹೆಚ್ಚಿನ ವಿಶ್ವಾಸ',
      'review': 'ಫಲಿತಾಂಶ ಪರಿಶೀಲಿಸಿ',
      'uncertain': 'ಅನಿಶ್ಚಿತ · ಸ್ಪಷ್ಟ ಎಲೆ ಫೋಟೋ ಮತ್ತೆ ತೆಗೆದುಕೊಳ್ಳಿ',
      'symptoms': 'ಗಮನಿಸಬೇಕಾದ ಲಕ್ಷಣಗಳು',
      'treatment': 'ಆರೈಕೆ ಮತ್ತು ಚಿಕಿತ್ಸೆ',
      'prevention': 'ತಡೆಗಟ್ಟುವಿಕೆ',
      'top': 'ಇತರೆ ಸಾಧ್ಯತೆಗಳು',
      'noResult': 'ಆಫ್‌ಲೈನ್ ಫಲಿತಾಂಶಕ್ಕಾಗಿ ಎಲೆಯನ್ನು ಸ್ಕ್ಯಾನ್ ಮಾಡಿ.',
      'modelError': 'Offline AI ಮಾದರಿ ಲಭ್ಯವಿಲ್ಲ.',
      'cameraError': 'ಈ ಸಾಧನದಲ್ಲಿ ಕ್ಯಾಮೆರಾ ಲಭ್ಯವಿಲ್ಲ.',
      'language': 'ಭಾಷೆ',
      'offline': 'ಇನ್‌ಸ್ಟಾಲ್ ಆದ ನಂತರ ಸಂಪೂರ್ಣ ಆಫ್‌ಲೈನ್‌ನಲ್ಲಿ ಕೆಲಸ ಮಾಡುತ್ತದೆ',
    },
  };
}

class PlantKnowledge {
  static DiseaseAdvice forLabel(String label, LeafLanguage language) {
    final parts = label.split('___');
    final cropKey = parts.isNotEmpty ? parts.first : label;
    final diseaseKey = parts.length > 1 ? parts.sublist(1).join('___') : label;
    final healthy = diseaseKey.toLowerCase().contains('healthy');
    final category = healthy ? 'healthy' : _categoryFor(diseaseKey);
    final lang = language.code;

    final crop = _cropNames[lang]?[cropKey] ?? _pretty(cropKey);
    final condition = healthy
        ? (_healthyName[lang] ?? 'Healthy')
        : (_diseaseNames[lang]?[diseaseKey] ?? _pretty(diseaseKey));
    final template = _templates[lang]?[category] ?? _templates['en']![category]!;

    return DiseaseAdvice(
      crop: crop,
      condition: condition,
      status: healthy ? (_healthyName[lang] ?? 'Healthy') : condition,
      symptoms: template.symptoms,
      treatment: template.treatment,
      prevention: template.prevention,
      note: _notes[lang] ?? _notes['en']!,
    );
  }

  static String _categoryFor(String disease) {
    final d = disease.toLowerCase();
    if (d.contains('virus') || d.contains('mosaic')) return 'viral';
    if (d.contains('spider_mite')) return 'pest';
    if (d.contains('haunglongbing') || d.contains('citrus_greening')) {
      return 'greening';
    }
    if (d.contains('bacterial')) return 'bacterial';
    return 'fungal';
  }

  static String _pretty(String value) => value
      .replaceAll('_', ' ')
      .replaceAll('  ', ' ')
      .replaceAll('(including sour)', '')
      .replaceAll('(maize)', '')
      .trim();

  static const Map<String, String> _healthyName = {
    'en': 'Healthy leaf',
    'ta': 'ஆரோக்கியமான இலை',
    'hi': 'स्वस्थ पत्ती',
    'ml': 'ആരോഗ്യമുള്ള ഇല',
    'kn': 'ಆರೋಗ್ಯಕರ ಎಲೆ',
  };

  static const Map<String, Map<String, String>> _cropNames = {
    'en': {
      'Apple': 'Apple', 'Blueberry': 'Blueberry', 'Cherry_(including_sour)': 'Cherry',
      'Corn_(maize)': 'Corn', 'Grape': 'Grape', 'Orange': 'Orange', 'Peach': 'Peach',
      'Pepper,_bell': 'Bell pepper', 'Potato': 'Potato', 'Raspberry': 'Raspberry',
      'Soybean': 'Soybean', 'Squash': 'Squash', 'Strawberry': 'Strawberry', 'Tomato': 'Tomato',
    },
    'ta': {
      'Apple': 'ஆப்பிள்', 'Blueberry': 'புளூபெர்ரி', 'Cherry_(including_sour)': 'செர்ரி',
      'Corn_(maize)': 'மக்காச்சோளம்', 'Grape': 'திராட்சை', 'Orange': 'ஆரஞ்சு', 'Peach': 'பீச்',
      'Pepper,_bell': 'குடைமிளகாய்', 'Potato': 'உருளைக்கிழங்கு', 'Raspberry': 'ராஸ்பெர்ரி',
      'Soybean': 'சோயாபீன்', 'Squash': 'ஸ்குவாஷ்', 'Strawberry': 'ஸ்ட்ராபெர்ரி', 'Tomato': 'தக்காளி',
    },
    'hi': {
      'Apple': 'सेब', 'Blueberry': 'ब्लूबेरी', 'Cherry_(including_sour)': 'चेरी',
      'Corn_(maize)': 'मक्का', 'Grape': 'अंगूर', 'Orange': 'संतरा', 'Peach': 'आड़ू',
      'Pepper,_bell': 'शिमला मिर्च', 'Potato': 'आलू', 'Raspberry': 'रास्पबेरी',
      'Soybean': 'सोयाबीन', 'Squash': 'स्क्वैश', 'Strawberry': 'स्ट्रॉबेरी', 'Tomato': 'टमाटर',
    },
    'ml': {
      'Apple': 'ആപ്പിൾ', 'Blueberry': 'ബ്ലൂബെറി', 'Cherry_(including_sour)': 'ചെറി',
      'Corn_(maize)': 'ചോളം', 'Grape': 'മുന്തിരി', 'Orange': 'ഓറഞ്ച്', 'Peach': 'പീച്ച്',
      'Pepper,_bell': 'കുടമുളക്', 'Potato': 'ഉരുളക്കിഴങ്ങ്', 'Raspberry': 'റാസ്പ്ബെറി',
      'Soybean': 'സോയാബീൻ', 'Squash': 'സ്ക്വാഷ്', 'Strawberry': 'സ്ട്രോബെറി', 'Tomato': 'തക്കാളി',
    },
    'kn': {
      'Apple': 'ಸೇಬು', 'Blueberry': 'ಬ್ಲೂಬೆರಿ', 'Cherry_(including_sour)': 'ಚೆರಿ',
      'Corn_(maize)': 'ಮೆಕ್ಕೆಜೋಳ', 'Grape': 'ದ್ರಾಕ್ಷಿ', 'Orange': 'ಕಿತ್ತಳೆ', 'Peach': 'ಪೀಚ್',
      'Pepper,_bell': 'ದೊಣ್ಣೆ ಮೆಣಸಿನಕಾಯಿ', 'Potato': 'ಆಲೂಗಡ್ಡೆ', 'Raspberry': 'ರಾಸ್ಪ್ಬೆರಿ',
      'Soybean': 'ಸೋಯಾಬೀನ್', 'Squash': 'ಸ್ಕ್ವಾಶ್', 'Strawberry': 'ಸ್ಟ್ರಾಬೆರಿ', 'Tomato': 'ಟೊಮೇಟೊ',
    },
  };

  static const Map<String, Map<String, String>> _diseaseNames = {
    'en': {},
    'ta': {
      'Apple_scab': 'ஆப்பிள் ஸ்கேப்', 'Black_rot': 'கருப்பு அழுகல்',
      'Cedar_apple_rust': 'சீடர் ஆப்பிள் ரஸ்ட்', 'Powdery_mildew': 'பவுடரி மில்டியூ',
      'Cercospora_leaf_spot Gray_leaf_spot': 'செர்கோஸ்போரா / சாம்பல் இலைப்புள்ளி',
      'Common_rust_': 'பொதுவான ரஸ்ட்', 'Northern_Leaf_Blight': 'வடக்கு இலை கருகல்',
      'Esca_(Black_Measles)': 'எஸ்கா (பிளாக் மீஸில்ஸ்)',
      'Leaf_blight_(Isariopsis_Leaf_Spot)': 'இலை கருகல் / இலைப்புள்ளி',
      'Haunglongbing_(Citrus_greening)': 'சிட்ரஸ் கிரீனிங்', 'Bacterial_spot': 'பாக்டீரியா புள்ளி',
      'Early_blight': 'ஆரம்ப இலை கருகல்', 'Late_blight': 'தாமத இலை கருகல்',
      'Leaf_scorch': 'இலை எரிச்சல்', 'Leaf_Mold': 'இலை பூஞ்சை',
      'Septoria_leaf_spot': 'செப்டோரியா இலைப்புள்ளி',
      'Spider_mites Two-spotted_spider_mite': 'இரண்டு புள்ளி சிலந்திப் பூச்சி',
      'Target_Spot': 'டார்கெட் ஸ்பாட்', 'Tomato_Yellow_Leaf_Curl_Virus': 'தக்காளி மஞ்சள் இலை சுருள் வைரஸ்',
      'Tomato_mosaic_virus': 'தக்காளி மோசைக் வைரஸ்',
    },
    'hi': {
      'Apple_scab': 'सेब स्कैब', 'Black_rot': 'ब्लैक रॉट', 'Cedar_apple_rust': 'सीडर एप्पल रस्ट',
      'Powdery_mildew': 'पाउडरी मिल्ड्यू', 'Cercospora_leaf_spot Gray_leaf_spot': 'सर्कोस्पोरा / ग्रे लीफ स्पॉट',
      'Common_rust_': 'कॉमन रस्ट', 'Northern_Leaf_Blight': 'नॉर्दर्न लीफ ब्लाइट',
      'Esca_(Black_Measles)': 'एस्का (ब्लैक मीजल्स)', 'Leaf_blight_(Isariopsis_Leaf_Spot)': 'लीफ ब्लाइट / लीफ स्पॉट',
      'Haunglongbing_(Citrus_greening)': 'सिट्रस ग्रीनिंग', 'Bacterial_spot': 'बैक्टीरियल स्पॉट',
      'Early_blight': 'अर्ली ब्लाइट', 'Late_blight': 'लेट ब्लाइट', 'Leaf_scorch': 'लीफ स्कॉर्च',
      'Leaf_Mold': 'लीफ मोल्ड', 'Septoria_leaf_spot': 'सेप्टोरिया लीफ स्पॉट',
      'Spider_mites Two-spotted_spider_mite': 'टू-स्पॉटेड स्पाइडर माइट', 'Target_Spot': 'टारगेट स्पॉट',
      'Tomato_Yellow_Leaf_Curl_Virus': 'टमाटर येलो लीफ कर्ल वायरस', 'Tomato_mosaic_virus': 'टमाटर मोज़ेक वायरस',
    },
    'ml': {
      'Apple_scab': 'ആപ്പിൾ സ്കാബ്', 'Black_rot': 'ബ്ലാക്ക് റോട്ട്', 'Cedar_apple_rust': 'സീഡർ ആപ്പിൾ റസ്റ്റ്',
      'Powdery_mildew': 'പൗഡറി മിൽഡ്യൂ', 'Cercospora_leaf_spot Gray_leaf_spot': 'സെർക്കോസ്പോറ / ഗ്രേ ലീഫ് സ്പോട്ട്',
      'Common_rust_': 'കോമൺ റസ്റ്റ്', 'Northern_Leaf_Blight': 'നോർത്തേൺ ലീഫ് ബ്ലൈറ്റ്',
      'Esca_(Black_Measles)': 'എസ്കാ (ബ്ലാക്ക് മീസിൽസ്)', 'Leaf_blight_(Isariopsis_Leaf_Spot)': 'ലീഫ് ബ്ലൈറ്റ് / ലീഫ് സ്പോട്ട്',
      'Haunglongbing_(Citrus_greening)': 'സിട്രസ് ഗ്രീനിംഗ്', 'Bacterial_spot': 'ബാക്ടീരിയൽ സ്പോട്ട്',
      'Early_blight': 'എർലി ബ്ലൈറ്റ്', 'Late_blight': 'ലേറ്റ് ബ്ലൈറ്റ്', 'Leaf_scorch': 'ലീഫ് സ്കോർച്ച്',
      'Leaf_Mold': 'ലീഫ് മോൾഡ്', 'Septoria_leaf_spot': 'സെപ്റ്റോറിയ ലീഫ് സ്പോട്ട്',
      'Spider_mites Two-spotted_spider_mite': 'ടു-സ്പോട്ടഡ് സ്പൈഡർ മൈറ്റ്', 'Target_Spot': 'ടാർഗറ്റ് സ്പോട്ട്',
      'Tomato_Yellow_Leaf_Curl_Virus': 'ടൊമാറ്റോ യെല്ലോ ലീഫ് കർൾ വൈറസ്', 'Tomato_mosaic_virus': 'ടൊമാറ്റോ മോസൈക് വൈറസ്',
    },
    'kn': {
      'Apple_scab': 'ಆಪಲ್ ಸ್ಕ್ಯಾಬ್', 'Black_rot': 'ಬ್ಲಾಕ್ ರಾಟ್', 'Cedar_apple_rust': 'ಸೀಡರ್ ಆಪಲ್ ರಸ್ಟ್',
      'Powdery_mildew': 'ಪೌಡರಿ ಮಿಲ್ಡ್ಯೂ', 'Cercospora_leaf_spot Gray_leaf_spot': 'ಸೆರ್ಕೋಸ್ಪೋರಾ / ಗ್ರೇ ಲೀಫ್ ಸ್ಪಾಟ್',
      'Common_rust_': 'ಕಾಮನ್ ರಸ್ಟ್', 'Northern_Leaf_Blight': 'ನಾರ್ದರ್ನ್ ಲೀಫ್ ಬ್ಲೈಟ್',
      'Esca_(Black_Measles)': 'ಎಸ್ಕಾ (ಬ್ಲಾಕ್ ಮೀಸಲ್ಸ್)', 'Leaf_blight_(Isariopsis_Leaf_Spot)': 'ಲೀಫ್ ಬ್ಲೈಟ್ / ಲೀಫ್ ಸ್ಪಾಟ್',
      'Haunglongbing_(Citrus_greening)': 'ಸಿಟ್ರಸ್ ಗ್ರೀನಿಂಗ್', 'Bacterial_spot': 'ಬ್ಯಾಕ್ಟೀರಿಯಲ್ ಸ್ಪಾಟ್',
      'Early_blight': 'ಎರ್ಲಿ ಬ್ಲೈಟ್', 'Late_blight': 'ಲೇಟ್ ಬ್ಲೈಟ್', 'Leaf_scorch': 'ಲೀಫ್ ಸ್ಕೋರ್ಚ್',
      'Leaf_Mold': 'ಲೀಫ್ ಮೋಲ್ಡ್', 'Septoria_leaf_spot': 'ಸೆಪ್ಟೋರಿಯಾ ಲೀಫ್ ಸ್ಪಾಟ್',
      'Spider_mites Two-spotted_spider_mite': 'ಟು-ಸ್ಪಾಟೆಡ್ ಸ್ಪೈಡರ್ ಮೈಟ್', 'Target_Spot': 'ಟಾರ್ಗೆಟ್ ಸ್ಪಾಟ್',
      'Tomato_Yellow_Leaf_Curl_Virus': 'ಟೊಮೇಟೊ ಯೆಲ್ಲೋ ಲೀಫ್ ಕರ್ಲ್ ವೈರಸ್', 'Tomato_mosaic_virus': 'ಟೊಮೇಟೊ ಮೊಸೈಕ್ ವೈರಸ್',
    },
  };

  static const Map<String, String> _notes = {
    'en': 'AI screening is an early indication, not a laboratory diagnosis. Before using any pesticide, confirm locally and follow the registered product label and agricultural guidance.',
    'ta': 'இது AI ஆரம்ப பரிசோதனை மட்டுமே; ஆய்வக உறுதி அல்ல. எந்த பூச்சிக்கொல்லி/பூஞ்சைக்கொல்லியும் பயன்படுத்தும் முன் உள்ளூர் வேளாண் ஆலோசனை மற்றும் பதிவு செய்யப்பட்ட லேபல் வழிமுறைகளை பின்பற்றவும்.',
    'hi': 'यह AI स्क्रीनिंग केवल प्रारंभिक संकेत है, लैब निदान नहीं। किसी भी कीटनाशक/फफूंदनाशक के उपयोग से पहले स्थानीय कृषि सलाह और पंजीकृत लेबल निर्देशों का पालन करें।',
    'ml': 'ഇത് AI പ്രാഥമിക സ്ക്രീനിംഗ് മാത്രമാണ്; ലാബ് സ്ഥിരീകരണം അല്ല. കീടനാശിനി/ഫംഗിസൈഡ് ഉപയോഗിക്കുന്നതിന് മുമ്പ് പ്രാദേശിക കാർഷിക നിർദ്ദേശവും രജിസ്റ്റർ ചെയ്ത ലേബൽ നിർദ്ദേശവും പാലിക്കുക.',
    'kn': 'ಇದು AI ಪ್ರಾಥಮಿಕ ಪರಿಶೀಲನೆ ಮಾತ್ರ; ಪ್ರಯೋಗಾಲಯ ದೃಢೀಕರಣವಲ್ಲ. ಯಾವುದೇ ಕೀಟನಾಶಕ/ಫಂಗಿಸೈಡ್ ಬಳಸುವ ಮೊದಲು ಸ್ಥಳೀಯ ಕೃಷಿ ಸಲಹೆ ಮತ್ತು ನೋಂದಾಯಿತ ಲೇಬಲ್ ಸೂಚನೆಗಳನ್ನು ಪಾಲಿಸಿ.',
  };

  static const Map<String, Map<String, _AdviceTemplate>> _templates = {
    'en': {
      'healthy': _AdviceTemplate(
        symptoms: ['Leaf colour and texture look broadly consistent with a healthy PlantVillage sample.', 'No strong disease pattern was detected by the model.'],
        treatment: ['No disease treatment is indicated from this scan.', 'Continue normal irrigation, nutrition and crop observation.'],
        prevention: ['Keep tools and growing area clean.', 'Inspect new leaves regularly and avoid prolonged leaf wetness.'],
      ),
      'fungal': _AdviceTemplate(
        symptoms: ['Look for expanding spots, blight, mould, rust, scorch or discoloured lesions.', 'Check both leaf surfaces and nearby leaves for similar patterns.'],
        treatment: ['Remove heavily affected leaves where practical and dispose of them away from the crop.', 'Improve airflow and keep foliage dry; if disease continues, use only a locally registered fungicide according to its label or agronomist advice.'],
        prevention: ['Avoid unnecessary overhead watering and long periods of leaf wetness.', 'Use clean tools, crop sanitation, spacing and rotation where applicable.'],
      ),
      'bacterial': _AdviceTemplate(
        symptoms: ['Look for water-soaked or dark spots, yellow halos and lesions that may merge.', 'Symptoms can spread faster during warm, wet conditions.'],
        treatment: ['Remove badly affected tissue and avoid working with plants while foliage is wet.', 'Sanitize tools; use only locally registered bacterial-disease products when recommended.'],
        prevention: ['Start with clean seed/transplants and reduce splash between plants.', 'Avoid overhead irrigation where possible and disinfect tools between affected areas.'],
      ),
      'viral': _AdviceTemplate(
        symptoms: ['Look for mosaic colour, yellowing, curling, distortion or stunted growth.', 'Virus symptoms may appear unevenly across the plant.'],
        treatment: ['There is usually no curative spray for a plant virus; isolate and remove strongly affected plants when appropriate.', 'Control insect vectors and weeds using local integrated pest-management guidance.'],
        prevention: ['Use healthy planting material and resistant varieties where available.', 'Clean tools and manage whiteflies/aphids or other vectors early.'],
      ),
      'pest': _AdviceTemplate(
        symptoms: ['Inspect the underside of leaves for mites, eggs, fine webbing, stippling or bronzing.', 'Damage may begin as many tiny pale dots before leaves dry.'],
        treatment: ['Remove heavily infested leaves and use a strong water wash where suitable.', 'Protect beneficial insects; if needed, use only a locally registered mite-control product according to label guidance.'],
        prevention: ['Check leaf undersides regularly, especially in hot and dry weather.', 'Avoid plant stress and prevent infestations from spreading between plants.'],
      ),
      'greening': _AdviceTemplate(
        symptoms: ['Look for irregular yellow mottling, weak growth and uneven fruit development.', 'Symptoms can resemble nutrient stress, so field confirmation is important.'],
        treatment: ['Seek local citrus/agriculture guidance; infected trees may need removal because there is no reliable cure.', 'Manage the psyllid vector with an integrated local control program.'],
        prevention: ['Use certified disease-free planting material.', 'Monitor citrus psyllids and nearby citrus trees routinely.'],
      ),
    },
    'ta': {
      'healthy': _AdviceTemplate(symptoms: ['இலையின் நிறமும் அமைப்பும் பொதுவாக ஆரோக்கியமான மாதிரியைப் போல் உள்ளது.', 'மாடல் வலுவான நோய் வடிவத்தை கண்டறியவில்லை.'], treatment: ['இந்த ஸ்கேன் அடிப்படையில் நோய் சிகிச்சை தேவையென தெரியவில்லை.', 'வழக்கமான பாசனம், ஊட்டச்சத்து மற்றும் கண்காணிப்பை தொடரவும்.'], prevention: ['கருவிகளையும் பயிர்ப்பகுதியையும் சுத்தமாக வைத்திருக்கவும்.', 'புதிய இலைகளை அடிக்கடி பார்க்கவும்; இலை நீண்ட நேரம் ஈரமாக இருப்பதை தவிர்க்கவும்.']),
      'fungal': _AdviceTemplate(symptoms: ['புள்ளிகள், கருகல், பூஞ்சை படலம், ரஸ்ட் அல்லது நிறமாற்றம் உள்ளதா பார்க்கவும்.', 'இலையின் இருபுறமும் அருகிலுள்ள இலைகளையும் சரிபார்க்கவும்.'], treatment: ['மிகவும் பாதிக்கப்பட்ட இலைகளை அகற்றி பயிரிலிருந்து தொலைவில் அகற்றவும்.', 'காற்றோட்டத்தை மேம்படுத்தி இலைகளை உலர வைத்திருக்கவும்; தேவைப்பட்டால் பதிவு செய்யப்பட்ட பூஞ்சைக்கொல்லியை லேபல்/வேளாண் ஆலோசனைப்படி மட்டும் பயன்படுத்தவும்.'], prevention: ['அதிக மேல்பாசனம் மற்றும் நீண்ட இலை ஈரப்பதத்தை தவிர்க்கவும்.', 'சுத்தமான கருவிகள், வயல் சுகாதாரம், சரியான இடைவெளி மற்றும் பயிர்மாற்றம் பின்பற்றவும்.']),
      'bacterial': _AdviceTemplate(symptoms: ['நீர்த்தன்மை கொண்ட அல்லது கருமையான புள்ளிகள், மஞ்சள் வளையங்கள் உள்ளதா பார்க்கவும்.', 'சூடான ஈரமான சூழலில் வேகமாக பரவலாம்.'], treatment: ['மிகவும் பாதிக்கப்பட்ட பகுதிகளை அகற்றி, இலை ஈரமாக இருக்கும்போது வேலை செய்வதை தவிர்க்கவும்.', 'கருவிகளை சுத்தம் செய்யவும்; உள்ளூர் பரிந்துரையுடன் பதிவு செய்யப்பட்ட தயாரிப்புகளை மட்டும் பயன்படுத்தவும்.'], prevention: ['சுத்தமான விதை/நாற்றுகளை பயன்படுத்தவும்; தண்ணீர் சிதறலை குறைக்கவும்.', 'முடிந்தால் மேல்பாசனத்தை தவிர்த்து கருவிகளை கிருமிநீக்கம் செய்யவும்.']),
      'viral': _AdviceTemplate(symptoms: ['மோசைக் நிறம், மஞ்சளாதல், இலை சுருட்டல், வடிவமாற்றம் அல்லது வளர்ச்சி குறைவு பார்க்கவும்.', 'அறிகுறிகள் செடியில் சமமில்லாமல் தோன்றலாம்.'], treatment: ['வைரஸ் நோய்களுக்கு பொதுவாக குணப்படுத்தும் தெளிப்பு இல்லை; கடுமையாக பாதித்த செடிகளை தனிமைப்படுத்தி அகற்றவும்.', 'வெள்ளைஈ/அஃபிட் போன்ற பரப்பும் பூச்சிகளை உள்ளூர் IPM வழிகாட்டுதல்படி கட்டுப்படுத்தவும்.'], prevention: ['ஆரோக்கியமான நடவு பொருள் மற்றும் எதிர்ப்பு வகைகள் கிடைத்தால் பயன்படுத்தவும்.', 'கருவிகளை சுத்தப்படுத்தி பரப்பும் பூச்சிகளை ஆரம்பத்திலேயே கட்டுப்படுத்தவும்.']),
      'pest': _AdviceTemplate(symptoms: ['இலையின் கீழ்புறத்தில் மைட், முட்டை, மெல்லிய வலை அல்லது சிறிய வெளிர் புள்ளிகள் உள்ளதா பார்க்கவும்.', 'பல சிறிய புள்ளிகளாக தொடங்கி இலை உலரலாம்.'], treatment: ['மிகவும் பாதிக்கப்பட்ட இலைகளை அகற்றி ஏற்ற சூழலில் தண்ணீர் அழுத்தத்தால் கழுவலாம்.', 'நன்மை பயக்கும் பூச்சிகளை பாதுகாக்கவும்; தேவையானால் பதிவு செய்யப்பட்ட மைட் கட்டுப்பாட்டு தயாரிப்பை லேபல் படி பயன்படுத்தவும்.'], prevention: ['வெப்பமான உலர் காலத்தில் இலை கீழ்புறத்தை அடிக்கடி பார்க்கவும்.', 'செடி அழுத்தத்தை குறைத்து தொற்று மற்ற செடிகளுக்கு பரவாமல் தடைக்கவும்.']),
      'greening': _AdviceTemplate(symptoms: ['ஒழுங்கற்ற மஞ்சள் புள்ளி, பலவீன வளர்ச்சி மற்றும் சமமற்ற பழ வளர்ச்சி பார்க்கவும்.', 'ஊட்டச்சத்து குறைபாட்டைப் போலவும் தோன்றலாம்; உள்ளூர் உறுதி முக்கியம்.'], treatment: ['உள்ளூர் சிட்ரஸ்/வேளாண் நிபுணரிடம் ஆலோசிக்கவும்; நம்பகமான குணமில்லை என்பதால் பாதித்த மரம் அகற்ற வேண்டியிருக்கலாம்.', 'ப்சில்லிட் பூச்சியை ஒருங்கிணைந்த முறையில் கட்டுப்படுத்தவும்.'], prevention: ['சான்றளிக்கப்பட்ட நோயில்லா நடவு பொருள் பயன்படுத்தவும்.', 'சிட்ரஸ் ப்சில்லிட் மற்றும் அருகிலுள்ள மரங்களை வழக்கமாக கண்காணிக்கவும்.']),
    },
    'hi': {
      'healthy': _AdviceTemplate(symptoms: ['पत्ती का रंग और बनावट सामान्य स्वस्थ नमूने जैसी दिखती है।', 'मॉडल ने कोई मजबूत रोग पैटर्न नहीं पाया।'], treatment: ['इस स्कैन से रोग उपचार की आवश्यकता नहीं दिखती।', 'सामान्य सिंचाई, पोषण और निगरानी जारी रखें।'], prevention: ['औजार और क्षेत्र साफ रखें।', 'नई पत्तियों को नियमित देखें और लंबे समय तक पत्ती गीली न रहने दें।']),
      'fungal': _AdviceTemplate(symptoms: ['फैलते धब्बे, ब्लाइट, फफूंदी, रस्ट या बदरंग घाव देखें।', 'पत्ती के दोनों तरफ और पास की पत्तियाँ भी जाँचें।'], treatment: ['बहुत प्रभावित पत्तियाँ हटाकर फसल से दूर नष्ट करें।', 'हवादार रखें और पत्तियाँ सूखी रखें; जरूरत पर केवल स्थानीय रूप से पंजीकृत फफूंदनाशक लेबल/कृषि सलाह के अनुसार उपयोग करें।'], prevention: ['अनावश्यक ऊपर से सिंचाई और लंबे समय की पत्ती नमी से बचें।', 'साफ औजार, स्वच्छता, उचित दूरी और फसल चक्र अपनाएँ।']),
      'bacterial': _AdviceTemplate(symptoms: ['पानी जैसे या गहरे धब्बे और पीले घेरे देखें।', 'गर्म और गीली स्थिति में तेजी से फैल सकता है।'], treatment: ['बहुत प्रभावित भाग हटाएँ और गीली पत्तियों पर काम न करें।', 'औजार साफ करें; केवल स्थानीय रूप से अनुमोदित उत्पाद सलाह के अनुसार उपयोग करें।'], prevention: ['स्वच्छ बीज/पौध सामग्री लें और पानी के छींटे कम करें।', 'जहाँ संभव हो ऊपर से सिंचाई से बचें और औजार कीटाणुरहित करें।']),
      'viral': _AdviceTemplate(symptoms: ['मोज़ेक रंग, पीलापन, पत्ती मुड़ना, विकृति या कम वृद्धि देखें।', 'लक्षण पूरे पौधे में समान नहीं हो सकते।'], treatment: ['वायरस के लिए सामान्यतः उपचारात्मक स्प्रे नहीं होता; गंभीर पौधों को अलग/हटाएँ।', 'वाहक कीटों और खरपतवार को स्थानीय IPM सलाह के अनुसार नियंत्रित करें।'], prevention: ['स्वस्थ रोपण सामग्री और उपलब्ध प्रतिरोधी किस्में उपयोग करें।', 'औजार साफ रखें और सफेद मक्खी/एफिड जैसे वाहकों को जल्दी नियंत्रित करें।']),
      'pest': _AdviceTemplate(symptoms: ['पत्ती के नीचे माइट, अंडे, महीन जाला या छोटे हल्के धब्बे देखें।', 'नुकसान कई छोटे बिंदुओं से शुरू होकर पत्ती सुखा सकता है।'], treatment: ['बहुत संक्रमित पत्तियाँ हटाएँ और उपयुक्त हो तो तेज पानी से धोएँ।', 'लाभकारी कीट बचाएँ; जरूरत पर केवल पंजीकृत माइट नियंत्रण उत्पाद लेबल अनुसार उपयोग करें।'], prevention: ['गर्म/सूखे मौसम में पत्ती का नीचे वाला हिस्सा नियमित देखें।', 'पौधे का तनाव कम रखें और संक्रमण फैलने न दें।']),
      'greening': _AdviceTemplate(symptoms: ['अनियमित पीला चितकबरापन, कमजोर वृद्धि और असमान फल देखें।', 'यह पोषक कमी जैसा लग सकता है, इसलिए स्थानीय पुष्टि जरूरी है।'], treatment: ['स्थानीय साइट्रस/कृषि विशेषज्ञ से संपर्क करें; विश्वसनीय इलाज न होने से संक्रमित पेड़ हटाना पड़ सकता है।', 'साइलिड वाहक को स्थानीय समेकित कार्यक्रम से नियंत्रित करें।'], prevention: ['प्रमाणित रोग-मुक्त रोपण सामग्री उपयोग करें।', 'साइट्रस साइलिड और पास के पेड़ों की नियमित निगरानी करें।']),
    },
    'ml': {
      'healthy': _AdviceTemplate(symptoms: ['ഇലയുടെ നിറവും രൂപവും പൊതുവെ ആരോഗ്യകരമായ മാതൃകയോട് സാമ്യമുണ്ട്.', 'മോഡൽ ശക്തമായ രോഗ മാതൃക കണ്ടെത്തിയില്ല.'], treatment: ['ഈ സ്കാനിൽ നിന്ന് രോഗചികിത്സ ആവശ്യമായി തോന്നുന്നില്ല.', 'സാധാരണ ജലസേചനം, പോഷണം, നിരീക്ഷണം തുടരുക.'], prevention: ['ഉപകരണങ്ങളും കൃഷിസ്ഥലവും ശുചിയായി സൂക്ഷിക്കുക.', 'പുതിയ ഇലകൾ പതിവായി പരിശോധിച്ച് നീണ്ടുനിൽക്കുന്ന ഇലനനവ് ഒഴിവാക്കുക.']),
      'fungal': _AdviceTemplate(symptoms: ['വളരുന്ന പാടുകൾ, ബ്ലൈറ്റ്, പൂപ്പൽ, റസ്റ്റ് അല്ലെങ്കിൽ നിറമാറ്റം ശ്രദ്ധിക്കുക.', 'ഇലയുടെ ഇരുവശവും സമീപ ഇലകളും പരിശോധിക്കുക.'], treatment: ['വളരെ ബാധിച്ച ഇലകൾ നീക്കി കൃഷിയിൽ നിന്ന് അകലെ സംസ്കരിക്കുക.', 'വായുസഞ്ചാരം മെച്ചപ്പെടുത്തി ഇലകൾ വരണ്ട നിലയിൽ സൂക്ഷിക്കുക; ആവശ്യമെങ്കിൽ രജിസ്റ്റർ ചെയ്ത ഫംഗിസൈഡ് ലേബൽ/കാർഷിക നിർദ്ദേശം പ്രകാരം മാത്രം ഉപയോഗിക്കുക.'], prevention: ['അനാവശ്യ മേൽജലസേചനവും ദീർഘ ഇലനനവും ഒഴിവാക്കുക.', 'ശുചിയായ ഉപകരണങ്ങൾ, ശുചിത്വം, ശരിയായ ഇടവിട്ട് നടീൽ, വിളമാറ്റം പാലിക്കുക.']),
      'bacterial': _AdviceTemplate(symptoms: ['വെള്ളം കയറിയപോലുള്ള/കറുത്ത പാടുകളും മഞ്ഞ വലയങ്ങളും ശ്രദ്ധിക്കുക.', 'ചൂടും ഈർപ്പവും കൂടുമ്പോൾ വേഗത്തിൽ പടരാം.'], treatment: ['വളരെ ബാധിച്ച ഭാഗങ്ങൾ നീക്കി ഇല നനഞ്ഞിരിക്കുമ്പോൾ കൈകാര്യം ചെയ്യരുത്.', 'ഉപകരണങ്ങൾ ശുചിയാക്കി പ്രാദേശികമായി രജിസ്റ്റർ ചെയ്ത ഉൽപ്പന്നങ്ങൾ നിർദ്ദേശമനുസരിച്ച് മാത്രം ഉപയോഗിക്കുക.'], prevention: ['ശുചിയായ വിത്ത്/തൈകൾ ഉപയോഗിച്ച് വെള്ളച്ചീറ്റൽ കുറയ്ക്കുക.', 'കഴിയുന്നിടത്ത് മേൽജലസേചനം ഒഴിവാക്കി ഉപകരണങ്ങൾ അണുവിമുക്തമാക്കുക.']),
      'viral': _AdviceTemplate(symptoms: ['മോസൈക്ക് നിറം, മഞ്ഞപ്പെടൽ, ഇലചുരുട്ടൽ, രൂപവൈകല്യം, വളർച്ച കുറവ് ശ്രദ്ധിക്കുക.', 'ലക്ഷണങ്ങൾ ചെടിയിലുടനീളം ഒരേപോലെ ഉണ്ടാകണമെന്നില്ല.'], treatment: ['വൈറസിന് സാധാരണ ചികിത്സാ സ്പ്രേ ഇല്ല; ഗുരുതരമായി ബാധിച്ച ചെടി വേർതിരിച്ച് നീക്കുക.', 'വെള്ളീച്ച/ആഫിഡ് പോലുള്ള വാഹക കീടങ്ങളെ പ്രാദേശിക IPM നിർദ്ദേശം പ്രകാരം നിയന്ത്രിക്കുക.'], prevention: ['ആരോഗ്യമുള്ള നടീൽ വസ്തുവും പ്രതിരോധ ഇനങ്ങളും ഉപയോഗിക്കുക.', 'ഉപകരണങ്ങൾ ശുചിയാക്കി വാഹക കീടങ്ങളെ തുടക്കത്തിൽ തന്നെ നിയന്ത്രിക്കുക.']),
      'pest': _AdviceTemplate(symptoms: ['ഇലയുടെ അടിവശത്ത് മൈറ്റ്, മുട്ട, നേർത്ത വല, ചെറിയ വെളുത്ത പുള്ളികൾ എന്നിവ നോക്കുക.', 'ചെറിയ പുള്ളികളായി തുടങ്ങി ഇല ഉണങ്ങാം.'], treatment: ['വളരെ ബാധിച്ച ഇലകൾ നീക്കി അനുയോജ്യമെങ്കിൽ വെള്ളം ഉപയോഗിച്ച് കഴുകുക.', 'ഉപകാരപ്രദ കീടങ്ങളെ സംരക്ഷിക്കുക; ആവശ്യമെങ്കിൽ രജിസ്റ്റർ ചെയ്ത മൈറ്റ് നിയന്ത്രണ ഉൽപ്പന്നം ലേബൽ പ്രകാരം ഉപയോഗിക്കുക.'], prevention: ['ചൂടും വരണ്ട കാലാവസ്ഥയിലും ഇലയുടെ അടിവശം പതിവായി പരിശോധിക്കുക.', 'ചെടിയുടെ സമ്മർദ്ദം കുറച്ച് ബാധ മറ്റുചെടികളിലേക്ക് പടരാതിരിക്കുക.']),
      'greening': _AdviceTemplate(symptoms: ['ക്രമരഹിത മഞ്ഞപ്പുള്ളികൾ, ദുർബല വളർച്ച, അസമമായ ഫലം എന്നിവ ശ്രദ്ധിക്കുക.', 'പോഷകക്കുറവുപോലെ തോന്നാം; പ്രാദേശിക സ്ഥിരീകരണം പ്രധാനമാണ്.'], treatment: ['പ്രാദേശിക സിട്രസ്/കാർഷിക വിദഗ്ധന്റെ സഹായം തേടുക; വിശ്വസനീയ ചികിത്സ ഇല്ലാത്തതിനാൽ ബാധിച്ച മരം നീക്കേണ്ടി വരാം.', 'സൈലിഡ് വാഹകത്തെ ഏകീകൃത പ്രാദേശിക നിയന്ത്രണത്തിലൂടെ കൈകാര്യം ചെയ്യുക.'], prevention: ['സർട്ടിഫൈഡ് രോഗരഹിത നടീൽ വസ്തു ഉപയോഗിക്കുക.', 'സിട്രസ് സൈലിഡുകളെയും സമീപ മരങ്ങളെയും പതിവായി നിരീക്ഷിക്കുക.']),
    },
    'kn': {
      'healthy': _AdviceTemplate(symptoms: ['ಎಲೆಯ ಬಣ್ಣ ಮತ್ತು ರಚನೆ ಸಾಮಾನ್ಯ ಆರೋಗ್ಯಕರ ಮಾದರಿಯಂತೆ ಕಾಣುತ್ತದೆ.', 'ಮಾದರಿ ಬಲವಾದ ರೋಗ ಮಾದರಿಯನ್ನು ಪತ್ತೆ ಮಾಡಿಲ್ಲ.'], treatment: ['ಈ ಸ್ಕ್ಯಾನ್ ಆಧಾರದಲ್ಲಿ ರೋಗ ಚಿಕಿತ್ಸೆ ಅಗತ್ಯವೆಂದು ಕಾಣುವುದಿಲ್ಲ.', 'ಸಾಮಾನ್ಯ ನೀರಾವರಿ, ಪೋಷಣೆ ಮತ್ತು ವೀಕ್ಷಣೆ ಮುಂದುವರಿಸಿ.'], prevention: ['ಉಪಕರಣ ಮತ್ತು ಬೆಳೆ ಪ್ರದೇಶವನ್ನು ಸ್ವಚ್ಛವಾಗಿ ಇಡಿ.', 'ಹೊಸ ಎಲೆಗಳನ್ನು ನಿಯಮಿತವಾಗಿ ನೋಡಿ ಮತ್ತು ದೀರ್ಘಕಾಲ ಎಲೆ ತೇವವಾಗದಂತೆ ನೋಡಿಕೊಳ್ಳಿ.']),
      'fungal': _AdviceTemplate(symptoms: ['ಹಬ್ಬುವ ಕಲೆಗಳು, ಬ್ಲೈಟ್, ಹುಳುಪು, ರಸ್ಟ್ ಅಥವಾ ಬಣ್ಣ ಬದಲಾದ ಗಾಯಗಳನ್ನು ನೋಡಿ.', 'ಎಲೆಯ ಎರಡೂ ಬದಿಗಳು ಮತ್ತು ಹತ್ತಿರದ ಎಲೆಗಳನ್ನು ಪರಿಶೀಲಿಸಿ.'], treatment: ['ತೀವ್ರವಾಗಿ ಬಾಧಿತ ಎಲೆಗಳನ್ನು ತೆಗೆದು ಬೆಳೆ ಪ್ರದೇಶದಿಂದ ದೂರ ವಿಲೇವಾರಿ ಮಾಡಿ.', 'ಗಾಳಿಚಲನೆ ಹೆಚ್ಚಿಸಿ ಎಲೆ ಒಣವಾಗಿರಲಿ; ಅಗತ್ಯವಿದ್ದರೆ ಸ್ಥಳೀಯವಾಗಿ ನೋಂದಾಯಿತ ಫಂಗಿಸೈಡ್ ಅನ್ನು ಲೇಬಲ್/ಕೃಷಿ ಸಲಹೆಯಂತೆ ಮಾತ್ರ ಬಳಸಿ.'], prevention: ['ಅನಗತ್ಯ ಮೇಲ್ನೀರಾವರಿ ಮತ್ತು ದೀರ್ಘ ಎಲೆ ತೇವ ತಪ್ಪಿಸಿ.', 'ಸ್ವಚ್ಛ ಉಪಕರಣ, ಕ್ಷೇತ್ರ ಸ್ವಚ್ಛತೆ, ಸರಿಯಾದ ಅಂತರ ಮತ್ತು ಬೆಳೆ ಪರಿವರ್ತನೆ ಅನುಸರಿಸಿ.']),
      'bacterial': _AdviceTemplate(symptoms: ['ನೀರಿನಂತಿರುವ ಅಥವಾ ಕಪ್ಪು ಕಲೆಗಳು ಮತ್ತು ಹಳದಿ ವಲಯಗಳನ್ನು ನೋಡಿ.', 'ಬಿಸಿ ಮತ್ತು ತೇವ ಪರಿಸ್ಥಿತಿಯಲ್ಲಿ ವೇಗವಾಗಿ ಹರಡಬಹುದು.'], treatment: ['ತೀವ್ರ ಬಾಧಿತ ಭಾಗಗಳನ್ನು ತೆಗೆದು ಎಲೆ ತೇವವಾಗಿರುವಾಗ ಕೆಲಸ ಮಾಡಬೇಡಿ.', 'ಉಪಕರಣ ಸ್ವಚ್ಛಗೊಳಿಸಿ; ಸ್ಥಳೀಯವಾಗಿ ನೋಂದಾಯಿತ ಉತ್ಪನ್ನಗಳನ್ನು ಸಲಹೆಯಂತೆ ಮಾತ್ರ ಬಳಸಿ.'], prevention: ['ಸ್ವಚ್ಛ ಬೀಜ/ಸಸಿಗಳನ್ನು ಬಳಸಿ ಮತ್ತು ನೀರಿನ ಚಿಮುಕಾಟ ಕಡಿಮೆ ಮಾಡಿ.', 'ಸಾಧ್ಯವಾದರೆ ಮೇಲ್ನೀರಾವರಿ ತಪ್ಪಿಸಿ ಮತ್ತು ಉಪಕರಣಗಳನ್ನು ಸೋಂಕುರಹಿತಗೊಳಿಸಿ.']),
      'viral': _AdviceTemplate(symptoms: ['ಮೊಸಾಯಿಕ್ ಬಣ್ಣ, ಹಳದಿ, ಎಲೆ ಮಡಚಿಕೆ, ವಿಕೃತಿ ಅಥವಾ ಬೆಳವಣಿಗೆ ಕಡಿಮೆ ಇರುವುದನ್ನು ನೋಡಿ.', 'ಲಕ್ಷಣಗಳು ಸಂಪೂರ್ಣ ಸಸ್ಯದಲ್ಲಿ ಸಮವಾಗಿರದೇ ಇರಬಹುದು.'], treatment: ['ವೈರಸ್‌ಗೆ ಸಾಮಾನ್ಯವಾಗಿ ಗುಣಪಡಿಸುವ ಸಿಂಪಡಣೆ ಇಲ್ಲ; ತೀವ್ರ ಬಾಧಿತ ಸಸಿಯನ್ನು ಪ್ರತ್ಯೇಕಿಸಿ/ತೆಗೆದುಹಾಕಿ.', 'ವಾಹಕ ಕೀಟ ಮತ್ತು ಕಳೆಯನ್ನು ಸ್ಥಳೀಯ IPM ಮಾರ್ಗದರ್ಶನದಂತೆ ನಿಯಂತ್ರಿಸಿ.'], prevention: ['ಆರೋಗ್ಯಕರ ನೆಡುವ ಸಾಮಗ್ರಿ ಮತ್ತು ಲಭ್ಯವಿದ್ದರೆ ಪ್ರತಿರೋಧಕ ಜಾತಿ ಬಳಸಿ.', 'ಉಪಕರಣ ಸ್ವಚ್ಛಗೊಳಿಸಿ ಮತ್ತು ಬಿಳಿಹುಳು/ಆಫಿಡ್ ಮುಂತಾದ ವಾಹಕರನ್ನು ಬೇಗ ನಿಯಂತ್ರಿಸಿ.']),
      'pest': _AdviceTemplate(symptoms: ['ಎಲೆಯ ಕೆಳಭಾಗದಲ್ಲಿ ಮೈಟ್, ಮೊಟ್ಟೆ, ಸಣ್ಣ ಜಾಲ ಅಥವಾ ಪುಟ್ಟ ತೆಳು ಕಲೆಗಳನ್ನು ನೋಡಿ.', 'ಹಾನಿ ಅನೇಕ ಸಣ್ಣ ಚುಕ್ಕೆಗಳಿಂದ ಆರಂಭವಾಗಿ ಎಲೆ ಒಣಗಿಸಬಹುದು.'], treatment: ['ತೀವ್ರ ಬಾಧಿತ ಎಲೆಗಳನ್ನು ತೆಗೆದು ಸೂಕ್ತವಾಗಿದ್ದರೆ ನೀರಿನಿಂದ ತೊಳೆಯಿರಿ.', 'ಉಪಕಾರಿ ಕೀಟಗಳನ್ನು ರಕ್ಷಿಸಿ; ಅಗತ್ಯವಿದ್ದರೆ ನೋಂದಾಯಿತ ಮೈಟ್ ನಿಯಂತ್ರಣ ಉತ್ಪನ್ನವನ್ನು ಲೇಬಲ್ ಪ್ರಕಾರ ಬಳಸಿ.'], prevention: ['ಬಿಸಿ/ಒಣ ಹವಾಮಾನದಲ್ಲಿ ಎಲೆಯ ಕೆಳಭಾಗವನ್ನು ನಿಯಮಿತವಾಗಿ ಪರಿಶೀಲಿಸಿ.', 'ಸಸ್ಯದ ಒತ್ತಡ ಕಡಿಮೆ ಮಾಡಿ ಮತ್ತು ಸೋಂಕು ಹರಡದಂತೆ ತಡೆಯಿರಿ.']),
      'greening': _AdviceTemplate(symptoms: ['ಅನಿಯಮಿತ ಹಳದಿ ಚುಕ್ಕೆ, ದುರ್ಬಲ ಬೆಳವಣಿಗೆ ಮತ್ತು ಅಸಮ ಹಣ್ಣುಗಳನ್ನು ನೋಡಿ.', 'ಪೋಷಕಾಂಶ ಕೊರತೆಯಂತೆ ಕಾಣಬಹುದು; ಸ್ಥಳೀಯ ದೃಢೀಕರಣ ಮುಖ್ಯ.'], treatment: ['ಸ್ಥಳೀಯ ಸಿಟ್ರಸ್/ಕೃಷಿ ತಜ್ಞರನ್ನು ಸಂಪರ್ಕಿಸಿ; ವಿಶ್ವಾಸಾರ್ಹ ಚಿಕಿತ್ಸೆ ಇಲ್ಲದ ಕಾರಣ ಬಾಧಿತ ಮರ ತೆಗೆದುಹಾಕಬೇಕಾಗಬಹುದು.', 'ಸೈಲಿಡ್ ವಾಹಕವನ್ನು ಸ್ಥಳೀಯ ಸಮಗ್ರ ನಿಯಂತ್ರಣದಿಂದ ನಿರ್ವಹಿಸಿ.'], prevention: ['ಪ್ರಮಾಣಿತ ರೋಗಮುಕ್ತ ನೆಡುವ ಸಾಮಗ್ರಿ ಬಳಸಿ.', 'ಸಿಟ್ರಸ್ ಸೈಲಿಡ್ ಮತ್ತು ಹತ್ತಿರದ ಮರಗಳನ್ನು ನಿಯಮಿತವಾಗಿ ಗಮನಿಸಿ.']),
    },
  };
}

class _AdviceTemplate {
  const _AdviceTemplate({
    required this.symptoms,
    required this.treatment,
    required this.prevention,
  });

  final List<String> symptoms;
  final List<String> treatment;
  final List<String> prevention;
}
