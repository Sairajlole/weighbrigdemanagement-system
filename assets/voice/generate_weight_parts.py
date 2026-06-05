import json, time, os, urllib.request

API_KEY = "sk_46cc3f544d5f5731522e2db1cbf74c3d77f54e7eb2c36de2"
FEMALE_VOICE = "x10bHF3yCZnNux9YbtTY"  # Nidhi
MALE_VOICE = "T93rAO1cXVhnf5IQIf9X"    # Raj

# weight_captured prefix = everything before the number
# weight_captured suffix = the unit after the number
WEIGHT_PARTS_NORMAL = {
    "en": {"prefix": "Weight is", "suffix": "kilograms"},
    "hi": {"prefix": "वज़न है", "suffix": "किलो"},
    "ta": {"prefix": "எடை", "suffix": "கிலோ"},
    "te": {"prefix": "బరువు", "suffix": "కిలోలు"},
    "kn": {"prefix": "ತೂಕ", "suffix": "ಕೆಜಿ"},
    "mr": {"prefix": "वजन", "suffix": "किलो"},
    "gu": {"prefix": "વજન", "suffix": "કિલો"},
    "bn": {"prefix": "ওজন", "suffix": "কিলো"},
    "pa": {"prefix": "ਭਾਰ", "suffix": "ਕਿਲੋ"},
    "ml": {"prefix": "തൂക്കം", "suffix": "കിലോ"},
}

WEIGHT_PARTS_POLITE = {
    "en": {"prefix": "The weight is", "suffix": "kilograms"},
    "hi": {"prefix": "वज़न है", "suffix": "किलोग्राम"},
    "ta": {"prefix": "எடை", "suffix": "கிலோகிராம்"},
    "te": {"prefix": "బరువు", "suffix": "కిలోగ్రాములు"},
    "kn": {"prefix": "ತೂಕ", "suffix": "ಕೆಜಿ"},
    "mr": {"prefix": "वजन आहे", "suffix": "किलोग्रॅम"},
    "gu": {"prefix": "વજન છે", "suffix": "કિલોગ્રામ"},
    "bn": {"prefix": "ওজন হলো", "suffix": "কিলোগ্রাম"},
    "pa": {"prefix": "ਭਾਰ ਹੈ", "suffix": "ਕਿਲੋਗ੍ਰਾਮ"},
    "ml": {"prefix": "തൂക്കം", "suffix": "കിലോഗ്രാം"},
}

LANG_CODES = {
    "en": "en", "hi": "hi", "ta": "ta", "te": "te", "kn": "kn",
    "mr": "mr", "gu": "gu", "bn": "bn", "pa": "pa", "ml": "ml"
}

def generate(text, voice_id, lang_code, outfile):
    os.makedirs(os.path.dirname(outfile), exist_ok=True)
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
    for tone, parts_map in [("normal", WEIGHT_PARTS_NORMAL), ("polite", WEIGHT_PARTS_POLITE)]:
        for gender, voice_id in [("female", FEMALE_VOICE), ("male", MALE_VOICE)]:
            for part in ["prefix", "suffix"]:
                text = parts_map[lang][part]
                outfile = f"{lang}/{gender}/{tone}/weight_captured_{part}.mp3"
                total += 1
                ok = generate(text, voice_id, LANG_CODES[lang], outfile)
                status = "OK" if ok else "FAIL"
                print(f"  [{total}] {lang}/{gender}/{tone}/weight_captured_{part}: {status}")
                if ok:
                    success += 1
                time.sleep(0.3)

print(f"\nDone: {success}/{total} generated successfully")
