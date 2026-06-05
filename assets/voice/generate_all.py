import json, subprocess, time, os

API_KEY = "sk_46cc3f544d5f5731522e2db1cbf74c3d77f54e7eb2c36de2"
FEMALE_VOICE = "x10bHF3yCZnNux9YbtTY"  # Nidhi
MALE_VOICE = "T93rAO1cXVhnf5IQIf9X"    # Raj

PROMPTS_NORMAL = {
    "en": {
        "entry_proceed": "Drive forward onto the weighbridge",
        "stop_on_platform": "Stop here. Your vehicle is being weighed.",
        "engine_off": "Turn off your engine and wait",
        "scanning": "Hold on, reading your number plate",
        "exit_proceed": "Done. You may leave now.",
        "driver_missing": "Driver, please stay inside the vehicle",
    },
    "hi": {
        "entry_proceed": "गाड़ी आगे लाओ, काँटे पर चढ़ाओ",
        "stop_on_platform": "रुको। तौल हो रही है।",
        "engine_off": "इंजन बंद करो, रुके रहो",
        "scanning": "रुको, नंबर पढ़ा जा रहा है",
        "exit_proceed": "हो गया। निकल सकते हो।",
        "driver_missing": "ड्राइवर गाड़ी में ही रहे",
    },
    "ta": {
        "entry_proceed": "வண்டியை மெதுவா முன்னாடி கொண்டு வாங்க",
        "stop_on_platform": "நிறுத்துங்க. எடை பார்க்கப்படுது.",
        "engine_off": "என்ஜின் ஆஃப் பண்ணுங்க, காத்திருங்க",
        "scanning": "நம்பர் படிக்கப்படுது, காத்திருங்க",
        "exit_proceed": "முடிஞ்சுடுச்சு. போகலாம்.",
        "driver_missing": "டிரைவர் வண்டிக்குள்ளேயே இருங்க",
    },
    "te": {
        "entry_proceed": "వాహనం ముందుకు తీసుకురండి, కాటా మీదకు ఎక్కించండి",
        "stop_on_platform": "ఆపండి. తూకం వేస్తున్నాం.",
        "engine_off": "ఇంజిన్ ఆపండి, ఆగండి",
        "scanning": "ఆగండి, నంబర్ చదువుతున్నాం",
        "exit_proceed": "అయిపోయింది. వెళ్ళొచ్చు.",
        "driver_missing": "డ్రైవర్ గాడీలోనే ఉండాలి",
    },
    "kn": {
        "entry_proceed": "ಗಾಡಿ ಮುಂದೆ ತಗೊಂಡ್ ಬನ್ನಿ, ಕಾಂಟಾ ಮೇಲೆ ಹಾಕಿ",
        "stop_on_platform": "ನಿಲ್ಲಿ. ತೂಕ ಮಾಡ್ತಿದ್ದೀವಿ.",
        "engine_off": "ಎಂಜಿನ್ ಆಫ್ ಮಾಡಿ, ಇರಿ",
        "scanning": "ನಂಬರ್ ಓದ್ತಿದ್ದೀವಿ, ಇರಿ",
        "exit_proceed": "ಆಯ್ತು. ಹೋಗ್ಬಹುದು.",
        "driver_missing": "ಡ್ರೈವರ್ ಗಾಡಿಯಲ್ಲೇ ಇರಿ",
    },
    "mr": {
        "entry_proceed": "गाडी पुढे आणा, काट्यावर चढवा",
        "stop_on_platform": "थांबा. वजन होतंय.",
        "engine_off": "इंजिन बंद करा, थांबा",
        "scanning": "थांबा, नंबर वाचला जातोय",
        "exit_proceed": "झालं. जाऊ शकता.",
        "driver_missing": "ड्रायव्हर गाडीतच राहा",
    },
    "gu": {
        "entry_proceed": "ગાડી આગળ લાવો, કાંટા ઉપર ચડાવો",
        "stop_on_platform": "ઊભા રહો. વજન થાય છે.",
        "engine_off": "એન્જિન બંધ કરો, ઊભા રહો",
        "scanning": "ઊભા રહો, નંબર વંચાય છે",
        "exit_proceed": "થઈ ગયું. જઈ શકો છો.",
        "driver_missing": "ડ્રાઇવર ગાડીમાં જ રહે",
    },
    "bn": {
        "entry_proceed": "গাড়ি সামনে আনো, কাঁটায় তোলো",
        "stop_on_platform": "দাঁড়াও। ওজন হচ্ছে।",
        "engine_off": "ইঞ্জিন বন্ধ করো, দাঁড়িয়ে থাকো",
        "scanning": "দাঁড়াও, নম্বর পড়া হচ্ছে",
        "exit_proceed": "হয়ে গেছে। যেতে পারো।",
        "driver_missing": "ড্রাইভার গাড়িতেই থাকবে",
    },
    "pa": {
        "entry_proceed": "ਗੱਡੀ ਅੱਗੇ ਲਿਆਓ, ਕਾਂਟੇ ਤੇ ਚੜ੍ਹਾਓ",
        "stop_on_platform": "ਰੁਕੋ। ਤੋਲ ਹੋ ਰਹੀ ਏ।",
        "engine_off": "ਇੰਜਣ ਬੰਦ ਕਰੋ, ਖੜ੍ਹੇ ਰਹੋ",
        "scanning": "ਰੁਕੋ, ਨੰਬਰ ਪੜ੍ਹਿਆ ਜਾ ਰਿਹਾ",
        "exit_proceed": "ਹੋ ਗਿਆ। ਜਾ ਸਕਦੇ ਹੋ।",
        "driver_missing": "ਡਰਾਈਵਰ ਗੱਡੀ ਵਿੱਚ ਹੀ ਰਹੇ",
    },
    "ml": {
        "entry_proceed": "വണ്ടി മുന്നോട്ട് കൊണ്ടുവരൂ, തൂക്കപ്പാലത്തിൽ കയറ്റൂ",
        "stop_on_platform": "നിർത്തൂ. തൂക്കം നോക്കുന്നു.",
        "engine_off": "എഞ്ചിൻ ഓഫ് ചെയ്യൂ, നിൽക്കൂ",
        "scanning": "നിൽക്കൂ, നമ്പർ വായിക്കുന്നു",
        "exit_proceed": "കഴിഞ്ഞു. പോകാം.",
        "driver_missing": "ഡ്രൈവർ വണ്ടിയിൽ തന്നെ ഇരിക്കണം",
    },
}

PROMPTS_POLITE = {
    "en": {
        "entry_proceed": "Please drive forward onto the weighbridge",
        "stop_on_platform": "Please stop here. Your vehicle is being weighed.",
        "engine_off": "Kindly turn off your engine and wait",
        "scanning": "Please hold on, we are reading your number plate",
        "exit_proceed": "Thank you. You may leave now.",
        "driver_missing": "Please stay inside the vehicle, driver",
    },
    "hi": {
        "entry_proceed": "कृपया गाड़ी आगे लाइए, काँटे पर चढ़ाइए",
        "stop_on_platform": "कृपया रुकिए। तौल हो रही है।",
        "engine_off": "कृपया इंजन बंद कीजिए, रुकिए",
        "scanning": "कृपया रुकिए, नंबर पढ़ा जा रहा है",
        "exit_proceed": "धन्यवाद। अब जा सकते हैं।",
        "driver_missing": "कृपया ड्राइवर गाड़ी में ही रहें",
    },
    "ta": {
        "entry_proceed": "தயவுசெய்து வண்டியை மெதுவா முன்னாடி கொண்டு வாங்க",
        "stop_on_platform": "தயவுசெய்து நிறுத்துங்க. எடை பார்க்கப்படுது.",
        "engine_off": "தயவுசெய்து என்ஜின் ஆஃப் பண்ணுங்க, காத்திருங்க",
        "scanning": "தயவுசெய்து காத்திருங்க, நம்பர் படிக்கப்படுது",
        "exit_proceed": "நன்றி. போகலாம்.",
        "driver_missing": "தயவுசெய்து டிரைவர் வண்டிக்குள்ளேயே இருங்க",
    },
    "te": {
        "entry_proceed": "దయచేసి వాహనం ముందుకు తీసుకురండి, కాటా మీదకు ఎక్కించండి",
        "stop_on_platform": "దయచేసి ఆపండి. తూకం వేస్తున్నాం.",
        "engine_off": "దయచేసి ఇంజిన్ ఆపండి, ఆగండి",
        "scanning": "దయచేసి ఆగండి, నంబర్ చదువుతున్నాం",
        "exit_proceed": "ధన్యవాదాలు. వెళ్ళొచ్చు.",
        "driver_missing": "దయచేసి డ్రైవర్ గాడీలోనే ఉండండి",
    },
    "kn": {
        "entry_proceed": "ದಯವಿಟ್ಟು ಗಾಡಿ ಮುಂದೆ ತಗೊಂಡ್ ಬನ್ನಿ, ಕಾಂಟಾ ಮೇಲೆ ಹಾಕಿ",
        "stop_on_platform": "ದಯವಿಟ್ಟು ನಿಲ್ಲಿ. ತೂಕ ಮಾಡ್ತಿದ್ದೀವಿ.",
        "engine_off": "ದಯವಿಟ್ಟು ಎಂಜಿನ್ ಆಫ್ ಮಾಡಿ, ಇರಿ",
        "scanning": "ದಯವಿಟ್ಟು ಇರಿ, ನಂಬರ್ ಓದ್ತಿದ್ದೀವಿ",
        "exit_proceed": "ಧನ್ಯವಾದ. ಹೋಗ್ಬಹುದು.",
        "driver_missing": "ದಯವಿಟ್ಟು ಡ್ರೈವರ್ ಗಾಡಿಯಲ್ಲೇ ಇರಿ",
    },
    "mr": {
        "entry_proceed": "कृपया गाडी पुढे आणा, काट्यावर चढवा",
        "stop_on_platform": "कृपया थांबा. वजन होतंय.",
        "engine_off": "कृपया इंजिन बंद करा, थांबा",
        "scanning": "कृपया थांबा, नंबर वाचला जातोय",
        "exit_proceed": "धन्यवाद. जाऊ शकता.",
        "driver_missing": "कृपया ड्रायव्हर गाडीतच राहा",
    },
    "gu": {
        "entry_proceed": "મહેરબાની કરી ગાડી આગળ લાવો, કાંટા ઉપર ચડાવો",
        "stop_on_platform": "મહેરબાની કરી ઊભા રહો. વજન થાય છે.",
        "engine_off": "મહેરબાની કરી એન્જિન બંધ કરો, ઊભા રહો",
        "scanning": "મહેરબાની કરી ઊભા રહો, નંબર વંચાય છે",
        "exit_proceed": "આભાર. જઈ શકો છો.",
        "driver_missing": "મહેરબાની કરી ડ્રાઇવર ગાડીમાં જ રહે",
    },
    "bn": {
        "entry_proceed": "দয়া করে গাড়ি সামনে আনুন, কাঁটায় তুলুন",
        "stop_on_platform": "দয়া করে দাঁড়ান। ওজন হচ্ছে।",
        "engine_off": "দয়া করে ইঞ্জিন বন্ধ করুন, দাঁড়িয়ে থাকুন",
        "scanning": "দয়া করে দাঁড়ান, নম্বর পড়া হচ্ছে",
        "exit_proceed": "ধন্যবাদ। যেতে পারেন।",
        "driver_missing": "দয়া করে ড্রাইভার গাড়িতেই থাকুন",
    },
    "pa": {
        "entry_proceed": "ਕਿਰਪਾ ਕਰਕੇ ਗੱਡੀ ਅੱਗੇ ਲਿਆਓ, ਕਾਂਟੇ ਤੇ ਚੜ੍ਹਾਓ",
        "stop_on_platform": "ਕਿਰਪਾ ਕਰਕੇ ਰੁਕੋ। ਤੋਲ ਹੋ ਰਹੀ ਏ।",
        "engine_off": "ਕਿਰਪਾ ਕਰਕੇ ਇੰਜਣ ਬੰਦ ਕਰੋ, ਖੜ੍ਹੇ ਰਹੋ",
        "scanning": "ਕਿਰਪਾ ਕਰਕੇ ਰੁਕੋ, ਨੰਬਰ ਪੜ੍ਹਿਆ ਜਾ ਰਿਹਾ",
        "exit_proceed": "ਧੰਨਵਾਦ। ਜਾ ਸਕਦੇ ਹੋ।",
        "driver_missing": "ਕਿਰਪਾ ਕਰਕੇ ਡਰਾਈਵਰ ਗੱਡੀ ਵਿੱਚ ਹੀ ਰਹੇ",
    },
    "ml": {
        "entry_proceed": "ദയവായി വണ്ടി മുന്നോട്ട് കൊണ്ടുവരൂ, തൂക്കപ്പാലത്തിൽ കയറ്റൂ",
        "stop_on_platform": "ദയവായി നിർത്തൂ. തൂക്കം നോക്കുന്നു.",
        "engine_off": "ദയവായി എഞ്ചിൻ ഓഫ് ചെയ്യൂ, നിൽക്കൂ",
        "scanning": "ദയവായി നിൽക്കൂ, നമ്പർ വായിക്കുന്നു",
        "exit_proceed": "നന്ദി. പോകാം.",
        "driver_missing": "ദയവായി ഡ്രൈവർ വണ്ടിയിൽ തന്നെ ഇരിക്കണം",
    },
}

LANG_CODES = {
    "en": "en", "hi": "hi", "ta": "ta", "te": "te", "kn": "kn",
    "mr": "mr", "gu": "gu", "bn": "bn", "pa": "pa", "ml": "ml"
}

def generate(text, voice_id, lang_code, outfile):
    import urllib.request
    body = json.dumps({
        "text": text,
        "model_id": "eleven_v3",
        "language_code": lang_code,
        "voice_settings": {"stability": 0.75, "similarity_boost": 0.85}
    }).encode()
    req = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}",
        data=body,
        headers={"xi-api-key": API_KEY, "Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            with open(outfile, "wb") as f:
                f.write(resp.read())
        size = os.path.getsize(outfile)
        return size > 5000
    except Exception as e:
        print(f"  FAILED: {e}")
        return False

total = 0
success = 0

for lang in LANG_CODES:
    for tone, prompts in [("normal", PROMPTS_NORMAL), ("polite", PROMPTS_POLITE)]:
        for gender, voice_id in [("female", FEMALE_VOICE), ("male", MALE_VOICE)]:
            for key, text in prompts[lang].items():
                outfile = f"{lang}/{gender}/{tone}/{key}.mp3"
                total += 1
                ok = generate(text, voice_id, LANG_CODES[lang], outfile)
                status = "OK" if ok else "FAIL"
                print(f"  [{total}] {lang}/{gender}/{tone}/{key}: {status}")
                if ok:
                    success += 1
                time.sleep(0.3)  # rate limit

print(f"\nDone: {success}/{total} generated successfully")
