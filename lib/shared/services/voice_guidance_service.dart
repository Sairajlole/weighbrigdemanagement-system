import 'dart:io';

import 'package:flutter/foundation.dart';

class SpeakerConfig {
  final String device;
  final double volume;
  final int delayMs;

  const SpeakerConfig({this.device = '', this.volume = 0.8, this.delayMs = 0});

  factory SpeakerConfig.fromMap(Map<String, dynamic> data) {
    var device = data['device'] as String? ?? '';
    if (VoiceGuidanceService._isVirtualDevice(device)) device = '';
    return SpeakerConfig(
      device: device,
      volume: (data['volume'] as num?)?.toDouble() ?? 0.8,
      delayMs: data['delayMs'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {'device': device, 'volume': volume, 'delayMs': delayMs};
}

class VoiceGuidanceConfig {
  final bool enabled;
  final String language;
  final String gender;
  final String tone;
  final double volume;
  final String outputDevice;
  final String pace; // 'fast', 'medium', 'slow'
  final String weightAnnounceMode; // 'captured', 'captured_and_net'
  final List<SpeakerConfig> speakers;
  final List<String> disabledPrompts;

  const VoiceGuidanceConfig({
    this.enabled = false,
    this.language = 'en',
    this.gender = 'female',
    this.tone = 'polite',
    this.volume = 0.8,
    this.outputDevice = '',
    this.pace = 'medium',
    this.weightAnnounceMode = 'captured',
    this.speakers = const [],
    this.disabledPrompts = const [],
  });

  factory VoiceGuidanceConfig.fromMap(Map<String, dynamic> data) {
    var device = data['outputDevice'] as String? ?? '';
    if (VoiceGuidanceService._isVirtualDevice(device)) device = '';
    final speakersList = (data['speakers'] as List<dynamic>?)
        ?.map((s) => SpeakerConfig.fromMap(s as Map<String, dynamic>))
        .toList() ?? [];
    return VoiceGuidanceConfig(
      enabled: data['enabled'] as bool? ?? false,
      language: data['language'] as String? ?? 'en',
      gender: data['gender'] as String? ?? 'female',
      tone: data['tone'] as String? ?? 'polite',
      volume: (data['volume'] as num?)?.toDouble() ?? 0.8,
      outputDevice: device,
      pace: data['pace'] as String? ?? 'medium',
      weightAnnounceMode: data['weightAnnounceMode'] as String? ?? 'captured',
      speakers: speakersList,
      disabledPrompts: (data['disabledPrompts'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'language': language,
    'gender': gender,
    'tone': tone,
    'volume': volume,
    'outputDevice': outputDevice,
    'pace': pace,
    'weightAnnounceMode': weightAnnounceMode,
    'speakers': speakers.map((s) => s.toMap()).toList(),
    'disabledPrompts': disabledPrompts,
  };
}

class VoiceGuidanceService {
  static const defaultPrompts = <String, Map<String, String>>{
    'en': {
      'entry_proceed': 'Please drive forward onto the weighbridge',
      'stop_on_platform': 'Please stop here. Your vehicle is being weighed.',
      'engine_off': 'Kindly turn off your engine and wait',
      'weight_captured': 'The weight is {weight} kilograms',
      'scanning': 'Please hold on, we are reading your number plate',
      'exit_proceed': 'Thank you. You may leave now.',
      'driver_missing': 'Please stay inside the vehicle, driver',
    },
    'hi': {
      'entry_proceed': 'कृपया गाड़ी आगे लाइए, काँटे पर चढ़ाइए',
      'stop_on_platform': 'कृपया यहीं रुकिए। वज़न हो रहा है।',
      'engine_off': 'कृपया इंजन बंद कीजिए और रुकिए',
      'weight_captured': 'वज़न है {weight} किलोग्राम',
      'scanning': 'कृपया रुकिए, नंबर प्लेट पढ़ी जा रही है',
      'exit_proceed': 'धन्यवाद। अब आप जा सकते हैं।',
      'driver_missing': 'कृपया चालक गाड़ी के अंदर ही रहें',
    },
    'hr': {
      'entry_proceed': 'भाई गाड़ी आगै ला, काँटे पै चढ़ा दे',
      'stop_on_platform': 'इब रुक जा भाई। तोल हो रही सै।',
      'engine_off': 'इंजन बंद कर दे, थोड़ा रुक',
      'weight_captured': 'वज़न सै {weight} किलो',
      'scanning': 'रुक भाई, नंबर पढ़या जा रहा सै',
      'exit_proceed': 'हो गया भाई। जा सकै सै अब।',
      'driver_missing': 'भाई ड्राइवर गाड़ी मैं ही रहै',
    },
    'ta': {
      'entry_proceed': 'தயவுசெய்து வண்டியை முன்னாடி கொண்டு வாங்க, பாலத்துல ஏத்துங்க',
      'stop_on_platform': 'இங்கேயே நிறுத்துங்க. எடை பார்க்கப்படுது.',
      'engine_off': 'எஞ்சினை அணைச்சிட்டு காத்திருங்க',
      'weight_captured': 'எடை {weight} கிலோ',
      'scanning': 'கொஞ்சம் காத்திருங்க, நம்பர் படிக்கப்படுது',
      'exit_proceed': 'நன்றி. இப்போ போகலாம்.',
      'driver_missing': 'ட்ரைவர் வண்டிக்குள்ளேயே இருங்க',
    },
    'te': {
      'entry_proceed': 'దయచేసి వాహనాన్ని ముందుకు తీసుకురండి, కాటా మీదకు ఎక్కించండి',
      'stop_on_platform': 'ఇక్కడ ఆపండి. మీ వాహనం తూకం వేయబడుతోంది.',
      'engine_off': 'దయచేసి ఇంజిన్ ఆపి వేచి ఉండండి',
      'weight_captured': 'బరువు {weight} కిలోలు',
      'scanning': 'దయచేసి ఆగండి, నంబర్ ప్లేట్ చదవబడుతోంది',
      'exit_proceed': 'ధన్యవాదాలు. ఇప్పుడు వెళ్ళవచ్చు.',
      'driver_missing': 'దయచేసి డ్రైవర్ వాహనంలోనే ఉండండి',
    },
    'kn': {
      'entry_proceed': 'ದಯವಿಟ್ಟು ವಾಹನವನ್ನು ಮುಂದೆ ತನ್ನಿ, ತೂಕದ ಸೇತುವೆ ಮೇಲೆ ಹಾಕಿ',
      'stop_on_platform': 'ಇಲ್ಲೇ ನಿಲ್ಲಿಸಿ. ತೂಕ ಮಾಡಲಾಗುತ್ತಿದೆ.',
      'engine_off': 'ದಯವಿಟ್ಟು ಇಂಜಿನ್ ಆಫ್ ಮಾಡಿ, ಕಾಯಿರಿ',
      'weight_captured': 'ತೂಕ {weight} ಕೆಜಿ',
      'scanning': 'ದಯವಿಟ್ಟು ಕಾಯಿರಿ, ನಂಬರ್ ಪ್ಲೇಟ್ ಓದಲಾಗುತ್ತಿದೆ',
      'exit_proceed': 'ಧನ್ಯವಾದ. ಈಗ ಹೋಗಬಹುದು.',
      'driver_missing': 'ದಯವಿಟ್ಟು ಚಾಲಕರು ವಾಹನದಲ್ಲೇ ಇರಿ',
    },
    'mr': {
      'entry_proceed': 'कृपया गाडी पुढे आणा, काट्यावर चढवा',
      'stop_on_platform': 'इथेच थांबा. वजन होत आहे.',
      'engine_off': 'कृपया इंजिन बंद करा आणि थांबा',
      'weight_captured': 'वजन आहे {weight} किलो',
      'scanning': 'कृपया थांबा, नंबर प्लेट वाचली जात आहे',
      'exit_proceed': 'धन्यवाद. आता जाऊ शकता.',
      'driver_missing': 'कृपया चालक गाडीतच राहा',
    },
    'gu': {
      'entry_proceed': 'મહેરબાની કરી ગાડી આગળ લાવો, કાંટા ઉપર ચડાવો',
      'stop_on_platform': 'અહીં ઊભા રહો. વજન થઈ રહ્યું છે.',
      'engine_off': 'મહેરબાની કરી એન્જિન બંધ કરો અને ઊભા રહો',
      'weight_captured': 'વજન છે {weight} કિલો',
      'scanning': 'મહેરબાની કરી ઊભા રહો, નંબર પ્લેટ વંચાઈ રહી છે',
      'exit_proceed': 'આભાર. હવે જઈ શકો છો.',
      'driver_missing': 'મહેરબાની કરી ડ્રાઇવર ગાડીમાં જ રહો',
    },
    'bn': {
      'entry_proceed': 'দয়া করে গাড়ি এগিয়ে আনুন, কাঁটায় তুলুন',
      'stop_on_platform': 'এখানে দাঁড়ান। ওজন নেওয়া হচ্ছে।',
      'engine_off': 'দয়া করে ইঞ্জিন বন্ধ করুন এবং অপেক্ষা করুন',
      'weight_captured': 'ওজন হলো {weight} কিলোগ্রাম',
      'scanning': 'দয়া করে অপেক্ষা করুন, নম্বর প্লেট পড়া হচ্ছে',
      'exit_proceed': 'ধন্যবাদ। এখন যেতে পারেন।',
      'driver_missing': 'দয়া করে চালক গাড়ির ভেতরে থাকুন',
    },
    'pa': {
      'entry_proceed': 'ਕਿਰਪਾ ਕਰਕੇ ਗੱਡੀ ਅੱਗੇ ਲਿਆਓ, ਕਾਂਟੇ ਤੇ ਚੜ੍ਹਾਓ',
      'stop_on_platform': 'ਇੱਥੇ ਰੁਕੋ ਜੀ। ਵਜ਼ਨ ਹੋ ਰਿਹਾ ਏ।',
      'engine_off': 'ਕਿਰਪਾ ਕਰਕੇ ਇੰਜਣ ਬੰਦ ਕਰੋ ਤੇ ਉਡੀਕ ਕਰੋ',
      'weight_captured': 'ਵਜ਼ਨ ਹੈ {weight} ਕਿਲੋਗ੍ਰਾਮ',
      'scanning': 'ਕਿਰਪਾ ਕਰਕੇ ਰੁਕੋ, ਨੰਬਰ ਪਲੇਟ ਪੜ੍ਹੀ ਜਾ ਰਹੀ ਏ',
      'exit_proceed': 'ਧੰਨਵਾਦ ਜੀ। ਹੁਣ ਜਾ ਸਕਦੇ ਹੋ।',
      'driver_missing': 'ਕਿਰਪਾ ਕਰਕੇ ਡਰਾਈਵਰ ਗੱਡੀ ਵਿੱਚ ਹੀ ਰਹੋ',
    },
    'ml': {
      'entry_proceed': 'ദയവായി വണ്ടി മുന്നോട്ട് എടുത്ത് പാലത്തിൽ കയറ്റൂ',
      'stop_on_platform': 'ഇവിടെ നിർത്തൂ. തൂക്കം എടുക്കുകയാണ്.',
      'engine_off': 'ദയവായി എഞ്ചിൻ ഓഫ് ചെയ്ത് കാത്തിരിക്കൂ',
      'weight_captured': 'തൂക്കം {weight} കിലോഗ്രാം',
      'scanning': 'ദയവായി കാത്തിരിക്കൂ, നമ്പർ പ്ലേറ്റ് വായിക്കുകയാണ്',
      'exit_proceed': 'നന്ദി. ഇപ്പോൾ പോകാം.',
      'driver_missing': 'ദയവായി ഡ്രൈവർ വണ്ടിയിൽ തന്നെ ഇരിക്കണം',
    },
  };

  // macOS voices: `say -v ?` lists all. These are the authentic Indian language voices.
  // Fallback chain: language-specific → Indian English → Samantha
  static const _macVoices = <String, String>{
    'en': 'Rishi',       // Indian English male (macOS 13+)
    'hi': 'Lekha',       // Hindi female
    'ta': 'Veena',       // Tamil/South Indian female
    'te': 'Veena',       // Telugu — no dedicated voice, use South Indian
    'kn': 'Veena',       // Kannada — no dedicated voice, use South Indian
    'hr': 'Lekha',       // Haryanvi — use Hindi voice
    'mr': 'Lekha',       // Marathi — no dedicated voice, use Hindi
    'gu': 'Lekha',       // Gujarati — no dedicated voice, use Hindi
    'bn': 'Lekha',       // Bengali — no dedicated voice, use Hindi
    'pa': 'Lekha',       // Punjabi — no dedicated voice, use Hindi
    'ml': 'Veena',       // Malayalam — no dedicated voice, use South Indian
  };

  // Windows: SAPI5 voice tokens for Indian languages
  // These are installed with language packs. Fallback: Microsoft Heera (Indian English)
  static const _windowsVoices = <String, String>{
    'en': 'Microsoft Heera',       // Indian English female
    'hi': 'Microsoft Hemant',      // Hindi male
    'hr': 'Microsoft Hemant',      // Haryanvi — use Hindi
    'ta': 'Microsoft Valluvar',    // Tamil male
    'te': 'Microsoft Heera',       // Telugu — fallback to Indian English
    'kn': 'Microsoft Heera',       // Kannada — fallback
    'mr': 'Microsoft Heera',       // Marathi — fallback
    'gu': 'Microsoft Heera',       // Gujarati — fallback
    'bn': 'Microsoft Heera',       // Bengali — fallback
    'pa': 'Microsoft Heera',       // Punjabi — fallback
    'ml': 'Microsoft Heera',       // Malayalam — fallback
  };

  VoiceGuidanceConfig _config;
  bool _isSpeaking = false;
  bool _stopRequested = false;
  Process? _activeProcess;

  VoiceGuidanceService(this._config);

  VoiceGuidanceConfig get config => _config;
  bool get isSpeaking => _isSpeaking;

  /// Stop any ongoing playback immediately
  void stop() {
    _stopRequested = true;
    try { _activeProcess?.kill(ProcessSignal.sigkill); } catch (_) {}
    _activeProcess = null;
    _isSpeaking = false;
    if (Platform.isMacOS) {
      Process.runSync('killall', ['-9', 'afplay']);
      Process.runSync('killall', ['-9', 'say']);
      Process.runSync('killall', ['-9', 'ffmpeg']);
    }
  }

  static const _virtualDeviceKeywords = [
    'zoom', 'teams', 'obs', 'virtual', 'loopback', 'soundflower',
    'blackhole', 'vb-audio', 'voicemeeter', 'screenaudio', 'discord',
    'webex', 'skype', 'krisp', 'loom', 'screenflow', 'camtasia',
    'zoomaudio', 'weighbridge all',
  ];

  static bool _isVirtualDevice(String name) {
    final lower = name.toLowerCase();
    return _virtualDeviceKeywords.any((kw) => lower.contains(kw));
  }

  /// List available physical audio output devices on the system
  static Future<List<String>> listOutputDevices() async {
    try {
      if (Platform.isMacOS) {
        final result = await Process.run('system_profiler', ['SPAudioDataType']);
        if (result.exitCode != 0) return ['System Default'];
        final lines = (result.stdout as String).split('\n');
        final devices = <String>['System Default'];
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].contains('Output Channels:') || lines[i].contains('Output Source:')) {
            for (int j = i - 1; j >= 0; j--) {
              final line = lines[j].trim();
              if (line.endsWith(':') && !line.startsWith('Devices:') && !line.startsWith('Audio:')) {
                final name = line.substring(0, line.length - 1);
                if (!devices.contains(name) && !_isVirtualDevice(name)) {
                  devices.add(name);
                }
                break;
              }
            }
          }
        }
        return devices;
      } else if (Platform.isWindows) {
        final result = await Process.run('powershell', ['-NoProfile', '-Command',
          'Get-AudioDevice -List | Where-Object { \$_.Type -eq "Playback" } | ForEach-Object { \$_.Name }']);
        if (result.exitCode != 0) {
          final fallback = await Process.run('powershell', ['-NoProfile', '-Command',
            '(New-Object -ComObject MMDeviceEnumerator.MMDeviceEnumerator).EnumAudioEndpoints(0, 1) | ForEach-Object { \$_.FriendlyName }']);
          if (fallback.exitCode != 0) return ['System Default'];
          final names = (fallback.stdout as String).split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty && !_isVirtualDevice(l)).toList();
          return ['System Default', ...names];
        }
        final names = (result.stdout as String).split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty && !_isVirtualDevice(l)).toList();
        return ['System Default', ...names];
      }
    } catch (e) {
      debugPrint('[Voice] Failed to list output devices: $e');
    }
    return ['System Default'];
  }

  void updateConfig(VoiceGuidanceConfig config) {
    _config = config;
  }

  /// Copy bundled voice assets to local cache on first run.
  /// All 10 languages × 2 genders × 2 tones ship with the app.
  static Future<void> ensureBundledVoices() async {
    final localBase = Directory(_voiceBasePath);
    if (localBase.existsSync() && localBase.listSync().isNotEmpty) {
      // Already populated — check if at least one full pack exists
      if (hasVoicePack('en', 'female', 'normal')) return;
    }

    final bundleBase = _bundledVoiceBasePath;
    if (bundleBase == null) {
      debugPrint('[Voice] Cannot locate bundled voice assets');
      return;
    }

    final sourceDir = Directory(bundleBase);
    if (!sourceDir.existsSync()) {
      debugPrint('[Voice] Bundled voice directory not found: $bundleBase');
      return;
    }

    // Copy all mp3 files from bundle to local cache
    int copied = 0;
    await for (final entity in sourceDir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.mp3')) {
        final relativePath = entity.path.substring(bundleBase.length);
        final destFile = File('$_voiceBasePath$relativePath');
        if (!destFile.existsSync()) {
          destFile.parent.createSync(recursive: true);
          await entity.copy(destFile.path);
          copied++;
        }
      }
    }
    debugPrint('[Voice] Copied $copied bundled voice files to local cache');
  }

  static String? get _bundledVoiceBasePath {
    final exe = Platform.resolvedExecutable;
    final exeDir = File(exe).parent.path;

    final candidates = [
      // macOS release build
      '${File(exe).parent.parent.path}/Frameworks/App.framework/Resources/flutter_assets/assets/voice',
      // macOS dev (flutter run)
      '${File(exe).parent.parent.path}/Resources/flutter_assets/assets/voice',
      // Windows release
      '$exeDir/data/flutter_assets/assets/voice',
      // Dev mode (running from source)
      '${Directory.current.path}/assets/voice',
    ];

    for (final path in candidates) {
      if (Directory(path).existsSync()) return path;
    }
    return null;
  }

  /// Announce weight — optionally followed by net weight based on config
  Future<void> speakWeight(String capturedWeight, {String? netWeight}) async {
    await speak('weight_captured', replacements: {'weight': capturedWeight});
    if (_stopRequested) return;
    if (netWeight != null && _config.weightAnnounceMode == 'captured_and_net') {
      await Future.delayed(const Duration(milliseconds: 500));
      if (_stopRequested) return;
      await _speakFullWeightAnnouncement('net_weight', netWeight);
    }
  }

  Future<void> speak(String promptKey, {Map<String, String>? replacements}) async {
    if (!_config.enabled) return;
    if (_config.disabledPrompts.contains(promptKey)) return;

    // Stop any ongoing playback before starting new
    if (_isSpeaking) stop();

    _isSpeaking = true;
    _stopRequested = false;
    try {
      final hasDynamicContent = replacements != null && replacements.isNotEmpty;

      if (!hasDynamicContent) {
        // Static prompts: play pre-bundled Murf audio
        final audioPlayed = await _playPreGenerated(promptKey);
        if (audioPlayed) return;
      } else {
        // Dynamic prompt (e.g., weight_captured with {weight}):
        // Merge prefix + number chunks + suffix into one seamless announcement
        final value = replacements.values.first;
        final played = await _speakFullWeightAnnouncement(promptKey, value);
        if (played) return;
      }

      // Full fallback: system TTS for the complete sentence
      final text = _resolvePrompt(promptKey, replacements);
      if (text == null || text.isEmpty) return;

      if (Platform.isMacOS) {
        await _speakMac(text);
      } else if (Platform.isWindows) {
        await _speakWindows(text);
      } else {
        debugPrint('[Voice] TTS not supported on this platform');
      }
    } catch (e) {
      debugPrint('[Voice] TTS error: $e');
    } finally {
      _isSpeaking = false;
    }
  }

  /// Build and play full announcement: prefix + number + suffix as one merged file.
  /// Tight gap after prefix (50ms), natural gap between number chunks (120ms).
  Future<bool> _speakFullWeightAnnouncement(String promptKey, String numberStr) async {
    final tone = _config.tone;
    final gender = _config.gender;
    final langDir = '$_voiceBasePath/${_config.language}/$gender/$tone';

    // Use promptKey-specific prefix (weight_captured_prefix or net_weight_prefix)
    final prefixPath = '$langDir/${promptKey}_prefix.mp3';
    if (!File(prefixPath).existsSync()) return false;

    // Suffix is shared (kilograms)
    final suffixPath = '$langDir/weight_captured_suffix.mp3';
    if (!File(suffixPath).existsSync()) return false;

    // Decompose number into chunk keys
    final n = int.tryParse(numberStr.replaceAll(',', '').trim());
    if (n == null) return false;

    final keys = _decomposeToChunkKeys(n);
    final numberPaths = <String>[];
    for (final key in keys) {
      final path = _findNumberClipPath(key);
      if (path != null) numberPaths.add(path);
    }
    if (numberPaths.isEmpty) return false;

    // Merge all: prefix (tight gap 50ms) + number chunks (120ms between) + (50ms) suffix
    final tmpDir = Directory.systemTemp;
    final ts = DateTime.now().millisecondsSinceEpoch;

    // Pace controls all gaps in the announcement
    final tightMs = switch (_config.pace) { 'fast' => '0.05', 'slow' => '0.25', _ => '0.12' };
    final normalMs = switch (_config.pace) { 'fast' => '0.15', 'slow' => '0.70', _ => '0.45' };

    final tightGap = '${tmpDir.path}/gap_tight_$ts.mp3';
    final normalGap = '${tmpDir.path}/gap_normal_$ts.mp3';
    await Process.run('ffmpeg', ['-y', '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=mono', '-t', tightMs, '-q:a', '2', tightGap]);
    await Process.run('ffmpeg', ['-y', '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=mono', '-t', normalMs, '-q:a', '2', normalGap]);

    // Trim all clips
    final allPaths = [prefixPath, ...numberPaths, suffixPath];
    final trimmedPaths = <String>[];
    for (int i = 0; i < allPaths.length; i++) {
      final trimmed = '${tmpDir.path}/wa_trim_${ts}_$i.mp3';
      final result = await Process.run('ffmpeg', [
        '-y', '-i', allPaths[i],
        '-af', 'silenceremove=start_periods=1:start_threshold=-35dB:start_duration=0.01,areverse,silenceremove=start_periods=1:start_threshold=-35dB:start_duration=0.01,areverse',
        '-q:a', '2', trimmed,
      ]);
      trimmedPaths.add(result.exitCode == 0 && File(trimmed).existsSync() ? trimmed : allPaths[i]);
    }

    // Build concat list with appropriate gaps
    // Structure: prefix + tightGap + num1 + normalGap + num2 + ... + tightGap + suffix
    final listFile = File('${tmpDir.path}/wa_list_$ts.txt');
    final buffer = StringBuffer();
    buffer.writeln("file '${trimmedPaths[0].replaceAll("'", "'\\''")}'"); // prefix
    buffer.writeln("file '${tightGap.replaceAll("'", "'\\''")}'");
    for (int i = 1; i < trimmedPaths.length - 1; i++) { // number chunks
      buffer.writeln("file '${trimmedPaths[i].replaceAll("'", "'\\''")}'");
      if (i < trimmedPaths.length - 2) {
        buffer.writeln("file '${normalGap.replaceAll("'", "'\\''")}'");
      }
    }
    buffer.writeln("file '${tightGap.replaceAll("'", "'\\''")}'");
    buffer.writeln("file '${trimmedPaths.last.replaceAll("'", "'\\''")}'"); // suffix
    listFile.writeAsStringSync(buffer.toString());

    final outFile = '${tmpDir.path}/wa_merged_$ts.mp3';
    final result = await Process.run('ffmpeg', [
      '-y', '-f', 'concat', '-safe', '0', '-i', listFile.path, '-q:a', '2', outFile,
    ]);

    // Cleanup
    for (int i = 0; i < trimmedPaths.length; i++) {
      if (trimmedPaths[i] != allPaths[i]) try { File(trimmedPaths[i]).deleteSync(); } catch (_) {}
    }
    try { listFile.deleteSync(); } catch (_) {}
    try { File(tightGap).deleteSync(); } catch (_) {}
    try { File(normalGap).deleteSync(); } catch (_) {}

    if (result.exitCode == 0 && File(outFile).existsSync()) {
      await _playFile(outFile);
      try { File(outFile).deleteSync(); } catch (_) {}
      return true;
    }
    return false;
  }

  /// Speak a number using pre-generated chunk clips (Indian numbering).
  /// Uses natural phrase clips: "12k" = "twelve thousand", "5h" = "five hundred", etc.
  /// Trims silence and merges into one seamless file.
  Future<void> _speakNumberFromClips(String numberStr) async {
    final n = int.tryParse(numberStr.replaceAll(',', '').trim());
    if (n == null) return;

    final keys = _decomposeToChunkKeys(n);
    final clipPaths = <String>[];

    for (final key in keys) {
      final path = _findNumberClipPath(key);
      if (path != null) clipPaths.add(path);
    }

    if (clipPaths.isEmpty) {
      if (Platform.isMacOS) {
        await _speakMac(numberStr);
      } else if (Platform.isWindows) {
        await _speakWindows(numberStr);
      }
      return;
    }

    final merged = await _mergeNumberClips(clipPaths);
    if (merged != null) {
      await _playFile(merged);
      try { File(merged).deleteSync(); } catch (_) {}
    }
  }

  /// Decompose number into chunk keys for pre-generated phrases.
  /// e.g., 12500 → ['12k', '5h'] (twelve thousand, five hundred)
  /// e.g., 345000 → ['3L', '45k'] (three lakh, forty-five thousand)
  static List<String> _decomposeToChunkKeys(int n) {
    if (n == 0) return ['0'];
    final keys = <String>[];

    // Lakhs (1,00,000+)
    if (n >= 100000) {
      final lakhs = n ~/ 100000;
      keys.add('${lakhs}L');
      n %= 100000;
    }

    // Thousands (1,000 - 99,999)
    if (n >= 1000) {
      final thousands = n ~/ 1000;
      keys.add('${thousands}k');
      n %= 1000;
    }

    // Hundreds (100-900)
    if (n >= 100) {
      final hundreds = n ~/ 100;
      keys.add('${hundreds}h');
      n %= 100;
    }

    // Remainder (0-99): use single clip if available (10,15,20,25,...,95)
    if (n > 0) {
      if (n % 5 == 0 || n <= 9) {
        keys.add('$n');
      } else {
        // Split into tens + units
        final tens = (n ~/ 10) * 10;
        final units = n % 10;
        if (tens > 0) keys.add('$tens');
        if (units > 0) keys.add('$units');
      }
    }

    return keys;
  }

  String? _findNumberClipPath(String key) {
    final tone = _config.tone;
    final gender = _config.gender;
    // Use language-specific clips if available, else fall back to Hindi
    final lang = _config.language == 'en' ? 'en' : _config.language;

    // Check language-specific
    final f = File('$_voiceBasePath/$lang/$gender/$tone/numbers/$key.mp3');
    if (f.existsSync() && f.lengthSync() > 5000) return f.path;

    // Fallback to Hindi (if not already Hindi/English)
    if (lang != 'hi' && lang != 'en') {
      final hf = File('$_voiceBasePath/hi/$gender/$tone/numbers/$key.mp3');
      if (hf.existsSync() && hf.lengthSync() > 5000) return hf.path;
    }

    // Check bundled
    final bundleBase = _bundledVoiceBasePath;
    if (bundleBase != null) {
      final bundled = '$bundleBase/$lang/$gender/$tone/numbers/$key.mp3';
      if (File(bundled).existsSync() && File(bundled).lengthSync() > 5000) return bundled;
      if (lang != 'hi' && lang != 'en') {
        final hBundled = '$bundleBase/hi/$gender/$tone/numbers/$key.mp3';
        if (File(hBundled).existsSync() && File(hBundled).lengthSync() > 5000) return hBundled;
      }
    }
    return null;
  }

  /// Trim silence from each clip, add short gaps between number chunks,
  /// and concatenate into one mp3.
  Future<String?> _mergeNumberClips(List<String> paths) async {
    final tmpDir = Directory.systemTemp;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final listFile = File('${tmpDir.path}/voice_concat_$ts.txt');
    final outFile = '${tmpDir.path}/voice_merged_$ts.mp3';

    try {
      final trimmedPaths = <String>[];
      for (int i = 0; i < paths.length; i++) {
        final trimmed = '${tmpDir.path}/voice_trim_${ts}_$i.mp3';
        final result = await Process.run('ffmpeg', [
          '-y', '-i', paths[i],
          '-af', 'silenceremove=start_periods=1:start_threshold=-35dB:start_duration=0.01,areverse,silenceremove=start_periods=1:start_threshold=-35dB:start_duration=0.01,areverse',
          '-q:a', '2',
          trimmed,
        ]);
        if (result.exitCode == 0 && File(trimmed).existsSync()) {
          trimmedPaths.add(trimmed);
        } else {
          trimmedPaths.add(paths[i]);
        }
      }

      // Generate a short silence gap (120ms) between number chunks
      final gapFile = '${tmpDir.path}/voice_gap_$ts.mp3';
      await Process.run('ffmpeg', [
        '-y', '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=mono', '-t', '0.12', '-q:a', '2', gapFile,
      ]);
      final gapExists = File(gapFile).existsSync();

      // Build concat list with gaps between clips
      final buffer = StringBuffer();
      for (int i = 0; i < trimmedPaths.length; i++) {
        buffer.writeln("file '${trimmedPaths[i].replaceAll("'", "'\\''")}'");
        if (i < trimmedPaths.length - 1 && gapExists) {
          buffer.writeln("file '${gapFile.replaceAll("'", "'\\''")}'");
        }
      }
      listFile.writeAsStringSync(buffer.toString());

      final result = await Process.run('ffmpeg', [
        '-y', '-f', 'concat', '-safe', '0', '-i', listFile.path,
        '-q:a', '2',
        outFile,
      ]);

      for (int i = 0; i < trimmedPaths.length; i++) {
        if (trimmedPaths[i] != paths[i]) {
          try { File(trimmedPaths[i]).deleteSync(); } catch (_) {}
        }
      }
      try { listFile.deleteSync(); } catch (_) {}
      try { File(gapFile).deleteSync(); } catch (_) {}

      if (result.exitCode == 0 && File(outFile).existsSync()) {
        return outFile;
      }
    } catch (e) {
      debugPrint('[Voice] Merge failed: $e');
    }
    return null;
  }



  Future<bool> _playPreGenerated(String promptKey) async {
    final tone = _config.tone;

    // Check local cache first
    final localDir = Directory('${_voiceBasePath}/${_config.language}/${_config.gender}/$tone');
    File? mp3;
    if (localDir.existsSync()) {
      final f = File('${localDir.path}/$promptKey.mp3');
      if (f.existsSync() && f.lengthSync() > 5000) {
        mp3 = f;
        debugPrint('[Voice] Found: ${f.path}');
      }
    } else {
      debugPrint('[Voice] Dir not found: ${localDir.path}');
    }

    // Fallback: check bundled assets path (where the app was built from)
    if (mp3 == null) {
      final bundledPath = _findBundledAudio(promptKey, tone);
      if (bundledPath != null) {
        mp3 = File(bundledPath);
        debugPrint('[Voice] Found bundled: $bundledPath');
      }
    }

    if (mp3 == null || !mp3.existsSync()) {
      if (!promptKey.endsWith('_prefix') && !promptKey.endsWith('_suffix')) {
        debugPrint('[Voice] No audio for $promptKey (${_config.language}/${_config.gender}/$tone)');
      }
      return false;
    }

    try {
      await _playFile(mp3.path);
      return true;
    } catch (e) {
      debugPrint('[Voice] Audio playback failed: $e');
      return false;
    }
  }

  Future<void> _playFile(String path) async {
    if (_config.speakers.isEmpty) {
      await _playOnDevice(path, _config.outputDevice, _config.volume);
      return;
    }

    // Deduplicate by device name
    final deviceMap = <String, SpeakerConfig>{};
    for (final speaker in _config.speakers) {
      final key = speaker.device;
      if (key.isEmpty) continue;
      if (!deviceMap.containsKey(key) || speaker.volume > deviceMap[key]!.volume) {
        deviceMap[key] = speaker;
      }
    }

    // If all speakers had empty device, play on system default
    if (deviceMap.isEmpty) {
      await _playOnDevice(path, '', _config.volume);
      return;
    }

    debugPrint('[Voice] Playing on ${deviceMap.length} unique device(s): ${deviceMap.keys.toList()}');

    if (deviceMap.length == 1) {
      final entry = deviceMap.entries.first;
      if (entry.value.delayMs > 0) await Future.delayed(Duration(milliseconds: entry.value.delayMs));
      if (_stopRequested) return;
      await _playOnDevice(path, entry.key, entry.value.volume);
    } else if (Platform.isMacOS) {
      // Create a multi-output device combining all speakers, then play once
      final deviceNames = deviceMap.keys.toList();
      final helperPath = '${Platform.environment['HOME'] ?? ''}/.weighbridge/multi_output_helper';
      if (File(helperPath).existsSync()) {
        final result = await Process.run(helperPath, deviceNames);
        final output = (result.stdout as String).trim();
        debugPrint('[Voice] Multi-output helper: $output');
        if (output.startsWith('OK:')) {
          await Future.delayed(const Duration(milliseconds: 300));
          if (_stopRequested) return;
          final vol = _config.volume;
          debugPrint('[Voice] Playing at volume: $vol');
          _activeProcess = await Process.start('afplay', ['-v', vol.toString(), path]);
          await _activeProcess?.exitCode;
          _activeProcess = null;
          // Destroy multi-output and revert to first speaker
          final destroyPath = '${Platform.environment['HOME'] ?? ''}/.weighbridge/destroy_multi_output';
          if (File(destroyPath).existsSync()) {
            await Process.run(destroyPath, [deviceMap.keys.first]);
          }
        }
      } else {
        // Fallback: sequential
        for (final entry in deviceMap.entries) {
          if (_stopRequested) return;
          await _playOnDevice(path, entry.key, entry.value.volume);
        }
      }
    } else if (Platform.isWindows) {
      // Windows: play simultaneously on all devices via parallel PowerShell processes
      final futures = <Future>[];
      for (final entry in deviceMap.entries) {
        if (_stopRequested) return;
        futures.add(_playOnWindowsDevice(path, entry.key, entry.value.volume));
      }
      await Future.wait(futures);
    } else {
      // Fallback: sequential
      for (final entry in deviceMap.entries) {
        if (_stopRequested) return;
        await _playOnDevice(path, entry.key, entry.value.volume);
      }
    }
  }

  static Future<String> _getSystemDefaultDevice() async {
    try {
      if (Platform.isMacOS) {
        final result = await Process.run('SwitchAudioSource', ['-c']);
        if (result.exitCode == 0) return (result.stdout as String).trim();
      }
    } catch (_) {}
    return '';
  }

  Future<void> _playOnDevice(String path, String device, double volume) async {
    if (_stopRequested) return;
    if (Platform.isMacOS) {
      if (device.isNotEmpty) {
        debugPrint('[Voice] Switching output to: "$device"');
        await _setMacOutputDevice(device);
        await Future.delayed(const Duration(milliseconds: 300));
      }
      _activeProcess = await Process.start('afplay', ['-v', volume.toString(), path]);
      await _activeProcess?.exitCode;
      _activeProcess = null;
    } else if (Platform.isWindows) {
      if (device.isNotEmpty) {
        await _setWindowsOutputDevice(device);
      }
      final vol = (volume * 100).round();
      final script = '''
Add-Type -AssemblyName presentationCore
\$player = New-Object System.Windows.Media.MediaPlayer
\$player.Open([Uri]"$path")
\$player.Volume = ${vol / 100}
\$player.Play()
Start-Sleep -Milliseconds 5000
''';
      _activeProcess = await Process.start('powershell', ['-NoProfile', '-Command', script]);
      await _activeProcess?.exitCode;
      _activeProcess = null;
    }
  }

  static Future<void> _setMacOutputDevice(String deviceName) async {
    try {
      final result = await Process.run('SwitchAudioSource', ['-s', deviceName]);
      debugPrint('[Voice] SwitchAudioSource result: ${(result.stdout as String).trim()}');
    } catch (e) {
      debugPrint('[Voice] SwitchAudioSource failed: $e');
    }
  }

  /// Play audio on a specific Windows device using COM audio endpoint selection
  Future<void> _playOnWindowsDevice(String path, String device, double volume) async {
    if (_stopRequested) return;
    final vol = (volume * 100).round();
    final escaped = path.replaceAll('\\', '\\\\').replaceAll('"', '`"');
    final devEscaped = device.replaceAll('"', '`"');
    // Use .NET MediaFoundation to target specific endpoint
    // First switch default, then play via MediaPlayer, both in one script
    final script = '''
try { Set-AudioDevice -PlaybackDevice "$devEscaped" 2>\$null } catch {}
Add-Type -AssemblyName presentationCore
\$player = New-Object System.Windows.Media.MediaPlayer
\$player.Open([Uri]"$escaped")
\$player.Volume = ${vol / 100}
\$player.Play()
while (\$player.NaturalDuration.TimeSpan -eq [TimeSpan]::Zero) { Start-Sleep -Milliseconds 100 }
Start-Sleep -Milliseconds (\$player.NaturalDuration.TimeSpan.TotalMilliseconds)
\$player.Close()
''';
    final proc = await Process.start('powershell', ['-NoProfile', '-Command', script]);
    await proc.exitCode;
  }

  static Future<void> _setWindowsOutputDevice(String deviceName) async {
    try {
      final escaped = deviceName.replaceAll('"', '`"');
      // Try AudioDeviceCmdlets (Install-Module AudioDeviceCmdlets)
      var result = await Process.run('powershell', ['-NoProfile', '-Command', 'Set-AudioDevice -PlaybackDevice "$escaped"']);
      if (result.exitCode != 0) {
        // Fallback: nircmd (nircmd.exe setdefaultsounddevice "DeviceName")
        result = await Process.run('nircmd', ['setdefaultsounddevice', deviceName]);
        if (result.exitCode != 0) {
          debugPrint('[Voice] Windows: Cannot switch device. Install AudioDeviceCmdlets or nircmd.');
        }
      }
    } catch (_) {}
  }

  static String get _voiceBasePath {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    return '$home/.weighbridge/voice';
  }

  String? _findBundledAudio(String promptKey, String tone) {
    // On macOS: app bundle is at <exe_dir>/../Resources/flutter_assets/assets/voice/...
    // On Windows: <exe_dir>/data/flutter_assets/assets/voice/...
    final exe = Platform.resolvedExecutable;
    final exeDir = File(exe).parent.path;

    final candidates = [
      // macOS bundle
      '${File(exe).parent.parent.path}/Resources/flutter_assets/assets/voice/${_config.language}/${_config.gender}/$tone/$promptKey.mp3',
      // macOS dev (flutter run)
      '$exeDir/../Resources/flutter_assets/assets/voice/${_config.language}/${_config.gender}/$tone/$promptKey.mp3',
      // Windows
      '$exeDir/data/flutter_assets/assets/voice/${_config.language}/${_config.gender}/$tone/$promptKey.mp3',
      // Direct path (dev mode / source tree)
      '${Directory.current.path}/assets/voice/${_config.language}/${_config.gender}/$tone/$promptKey.mp3',
      // Flat structure (gender folder directly has mp3s — matches what we generated)
      '${Directory.current.path}/assets/voice/${_config.language}/female/$tone/$promptKey.mp3',
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  /// Check if voice pack exists locally for a language+gender+tone combo
  static bool hasVoicePack(String language, String gender, [String tone = 'normal']) {
    final dir = Directory('$_voiceBasePath/$language/$gender/$tone');
    if (!dir.existsSync()) return false;
    return dir.listSync().whereType<File>().where((f) => f.path.endsWith('.mp3')).length >= 5;
  }

  /// Download voice pack from cloud storage (Firebase Storage / CDN)
  /// Only downloads the 6 files for the selected language+gender+tone
  static Future<int> downloadVoicePack({
    required String language,
    required String gender,
    required String tone,
    required String baseUrl,
  }) async {
    final dir = Directory('$_voiceBasePath/$language/$gender/$tone');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    const promptKeys = ['entry_proceed', 'stop_on_platform', 'engine_off', 'scanning', 'exit_proceed', 'driver_missing'];
    int downloaded = 0;

    for (final key in promptKeys) {
      final url = '$baseUrl/$language/$gender/$tone/$key.mp3';
      final outFile = File('${dir.path}/$key.mp3');

      try {
        final result = await Process.run('curl', ['-s', '-f', '-o', outFile.path, url]);
        if (result.exitCode == 0 && outFile.existsSync() && outFile.lengthSync() > 5000) {
          downloaded++;
        }
      } catch (e) {
        debugPrint('[Voice] Download failed for $key: $e');
      }
    }
    debugPrint('[Voice] Downloaded $downloaded/${promptKeys.length} files for $language/$gender/$tone');
    return downloaded;
  }

  /// Delete local voice pack
  static void deleteVoicePack(String language, String gender, String tone) {
    final dir = Directory('$_voiceBasePath/$language/$gender/$tone');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  static const murfVoices = <String, Map<String, String>>{
    'en': {'female': 'en-IN-isha', 'male': 'en-IN-arjun'},
    'hi': {'female': 'hi-IN-ria', 'male': 'hi-IN-raj'},
    'ta': {'female': 'ta-IN-meena', 'male': 'ta-IN-kumar'},
    'te': {'female': 'te-IN-priya', 'male': 'te-IN-mohan'},
    'kn': {'female': 'kn-IN-deepa', 'male': 'kn-IN-ganesh'},
    'mr': {'female': 'mr-IN-meera', 'male': 'mr-IN-sachin'},
    'gu': {'female': 'gu-IN-dhwani', 'male': 'gu-IN-ketan'},
    'bn': {'female': 'bn-IN-tanisha', 'male': 'bn-IN-arnab'},
    'pa': {'female': 'pa-IN-simran', 'male': 'pa-IN-amrit'},
    'ml': {'female': 'ml-IN-sobhana', 'male': 'ml-IN-vijay'},
  };

  String? _resolvePrompt(String key, Map<String, String>? replacements) {
    var text = defaultPrompts[_config.language]?[key] ?? defaultPrompts['en']?[key];

    if (text == null) return null;

    if (replacements != null) {
      for (final entry in replacements.entries) {
        text = text!.replaceAll('{${entry.key}}', entry.value);
      }
    }
    return text;
  }

  Future<void> _speakMac(String text) async {
    if (_config.outputDevice.isNotEmpty) {
      await _setMacOutputDevice(_config.outputDevice);
    }
    final voice = _macVoices[_config.language] ?? 'Rishi';
    final escaped = text.replaceAll('"', r'\"');
    var result = await Process.run('say', ['-v', voice, '-r', '180', escaped]);
    if (result.exitCode != 0) {
      result = await Process.run('say', ['-v', 'Rishi', '-r', '180', escaped]);
      if (result.exitCode != 0) {
        result = await Process.run('say', ['-r', '180', escaped]);
      }
    }
    if (result.exitCode != 0) {
      debugPrint('[Voice] macOS say failed: ${result.stderr}');
    }
  }

  Future<void> _speakWindows(String text) async {
    if (_config.outputDevice.isNotEmpty) {
      await _setWindowsOutputDevice(_config.outputDevice);
    }
    final escaped = text.replaceAll('"', '`"');
    final volume = (_config.volume * 100).round();
    final voice = _windowsVoices[_config.language] ?? 'Microsoft Heera';
    final script = '''
Add-Type -AssemblyName System.Speech
\$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
\$synth.Volume = $volume
try { \$synth.SelectVoice("$voice") } catch { }
\$synth.Speak("$escaped")
''';
    final result = await Process.run('powershell', ['-NoProfile', '-Command', script]);
    if (result.exitCode != 0) {
      debugPrint('[Voice] Windows TTS failed: ${result.stderr}');
    }
  }

  void dispose() {}
}
