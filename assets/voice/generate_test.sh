#!/bin/bash
API_KEY="ap2_299490ef-0a95-43fe-a51f-b0857f920cfe"
BASE_URL="https://api.murf.ai/v1/speech/generate"

declare -A TEXTS
TEXTS[en]="Drive forward onto the weighbridge"
TEXTS[hi]="गाड़ी आगे लाओ, काँटे पर चढ़ाओ"
TEXTS[ta]="வண்டியை மெதுவா முன்னாடி கொண்டு வாங்க"
TEXTS[te]="వాహనం ముందుకు తీసుకురండి, కాటా మీదకు ఎక్కించండి"
TEXTS[kn]="ಗಾಡಿ ಮುಂದೆ ತಗೊಂಡ್ ಬನ್ನಿ, ಕಾಂಟಾ ಮೇಲೆ ಹಾಕಿ"
TEXTS[mr]="गाडी पुढे आणा, काट्यावर चढवा"
TEXTS[gu]="ગાડી આગળ લાવો, કાંટા ઉપર ચડાવો"
TEXTS[bn]="গাড়ি সামনে আনো, কাঁটায় তোলো"
TEXTS[pa]="ਗੱਡੀ ਅੱਗੇ ਲਿਆਓ, ਕਾਂਟੇ ਤੇ ਚੜ੍ਹਾਓ"
TEXTS[ml]="വണ്ടി മുന്നോട്ട് കൊണ്ടുവരൂ, തൂക്കപ്പാലത്തിൽ കയറ്റൂ"

declare -A VOICES
VOICES[en]="en-IN-isha"
VOICES[hi]="hi-IN-ria"
VOICES[ta]="ta-IN-meena"
VOICES[te]="te-IN-priya"
VOICES[kn]="kn-IN-deepa"
VOICES[mr]="mr-IN-meera"
VOICES[gu]="gu-IN-dhwani"
VOICES[bn]="bn-IN-tanisha"
VOICES[pa]="pa-IN-simran"
VOICES[ml]="ml-IN-sobhana"

for lang in en hi ta te kn mr gu bn pa ml; do
  echo "Generating $lang..."
  curl -s -X POST "$BASE_URL" \
    -H "Content-Type: application/json" \
    -H "api-key: $API_KEY" \
    -d "{\"text\":\"${TEXTS[$lang]}\",\"voiceId\":\"${VOICES[$lang]}\",\"format\":\"mp3\"}" \
    -o "$lang/female/entry_proceed.mp3"
  
  # Check file size (if < 1KB, likely an error response)
  size=$(wc -c < "$lang/female/entry_proceed.mp3" 2>/dev/null || echo 0)
  if [ "$size" -lt 1000 ]; then
    echo "  WARNING: $lang file too small ($size bytes) - likely API error"
    cat "$lang/female/entry_proceed.mp3"
    echo ""
  else
    echo "  OK: $lang ($size bytes)"
  fi
done
echo "Done!"
