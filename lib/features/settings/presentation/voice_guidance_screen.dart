import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/voice_guidance_provider.dart';
import 'package:weighbridgemanagement/shared/services/voice_guidance_service.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/app_card.dart';
import 'package:weighbridgemanagement/shared/widgets/weighbridge_context_bar.dart';

class VoiceGuidanceScreen extends ConsumerStatefulWidget {
  const VoiceGuidanceScreen({super.key});

  @override
  ConsumerState<VoiceGuidanceScreen> createState() => _VoiceGuidanceScreenState();
}

class _VoiceGuidanceScreenState extends ConsumerState<VoiceGuidanceScreen> {
  bool _loaded = false;
  bool _saving = false;

  bool _enabled = false;
  String _language = 'en';
  String _gender = 'female';
  String _tone = 'polite';
  String _pace = 'medium';
  String _weightAnnounceMode = 'captured';
  double _volume = 0.8;
  String _outputDevice = '';
  final List<Map<String, dynamic>> _speakers = []; // {device, volume, delayMs}
  List<String> _disabledPrompts = [];

  List<String> _availableDevices = ['System Default'];
  bool _loadingDevices = true;

  String? _headerMsg;
  bool _headerMsgIsError = false;
  Timer? _headerMsgTimer;

  static const _languages = <String, String>{
    'en': 'English',
    'hi': 'Hindi',
    'hr': 'Haryanvi',
    'ta': 'Tamil',
    'te': 'Telugu',
    'kn': 'Kannada',
    'mr': 'Marathi',
    'gu': 'Gujarati',
    'bn': 'Bengali',
    'pa': 'Punjabi',
    'ml': 'Malayalam',
  };

  static const _promptLabels = <String, String>{
    'entry_proceed': 'Drive forward onto weighbridge',
    'stop_on_platform': 'Stop — vehicle being weighed',
    'engine_off': 'Turn off engine and wait',
    'weight_captured': 'Weight announcement',
    'scanning': 'Reading number plate',
    'exit_proceed': 'Done — may leave',
    'driver_missing': 'Stay inside vehicle',
  };

  late final VoiceGuidanceService _voiceService;

  @override
  void initState() {
    super.initState();
    _voiceService = ref.read(voiceGuidanceServiceProvider);
    _loadOutputDevices();
  }

  Future<void> _loadOutputDevices() async {
    final devices = await VoiceGuidanceService.listOutputDevices();
    if (mounted) setState(() { _availableDevices = devices; _loadingDevices = false; });
  }

  @override
  void dispose() {
    _voiceService.stop();
    _headerMsgTimer?.cancel();
    super.dispose();
  }

  void _loadConfig(VoiceGuidanceConfig config) {
    if (_loaded) return;
    _loaded = true;
    _enabled = config.enabled;
    _language = config.language;
    _gender = config.gender;
    _tone = config.tone;
    _pace = config.pace;
    _weightAnnounceMode = config.weightAnnounceMode;
    _volume = config.volume;
    _outputDevice = config.outputDevice;
    _speakers.clear();
    _speakers.addAll(config.speakers.map((s) => <String, dynamic>{'device': s.device, 'volume': s.volume, 'delayMs': s.delayMs}));
    if (_speakers.isEmpty) {
      final firstDevice = _availableDevices.where((d) => d != 'System Default').firstOrNull ?? '';
      _speakers.add(<String, dynamic>{'device': firstDevice, 'volume': _volume, 'delayMs': 0});
    }
    // Fix any empty device entries — assign next unused device
    final usedDevices = <String>{};
    for (final s in _speakers) {
      final dev = s['device'] as String;
      if (dev.isNotEmpty) {
        usedDevices.add(dev);
      }
    }
    for (final s in _speakers) {
      if ((s['device'] as String).isEmpty) {
        final next = _availableDevices.where((d) => d != 'System Default' && !usedDevices.contains(d)).firstOrNull ?? '';
        s['device'] = next;
        if (next.isNotEmpty) usedDevices.add(next);
      }
    }
    _disabledPrompts = List<String>.from(config.disabledPrompts);
  }

  void _showHeaderMsg(String msg, {bool isError = false}) {
    _headerMsgTimer?.cancel();
    setState(() {
      _headerMsg = msg;
      _headerMsgIsError = isError;
    });
    _headerMsgTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _headerMsg = null);
    });
  }

  VoiceGuidanceConfig _buildConfig() {
    return VoiceGuidanceConfig(
      enabled: _enabled,
      language: _language,
      gender: _gender,
      tone: _tone,
      pace: _pace,
      weightAnnounceMode: _weightAnnounceMode,
      volume: _speakers.length > 1 ? _volume : (_speakers.isNotEmpty ? (_speakers.first['volume'] as double) : _volume),
      outputDevice: _speakers.isNotEmpty ? (_speakers.first['device'] as String) : _outputDevice,
      speakers: _speakers.map((s) => SpeakerConfig(device: s['device'] as String, volume: s['volume'] as double, delayMs: s['delayMs'] as int? ?? 0)).toList(),
      disabledPrompts: _disabledPrompts,
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final config = _buildConfig();
      await saveVoiceGuidanceConfig(ref, config).timeout(const Duration(seconds: 10));
      if (mounted) _showHeaderMsg('Voice guidance settings saved');
    } catch (e) {
      if (mounted) _showHeaderMsg('Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  Future<void> _testSpeaker(int idx) async {
    _stopAll();
    await Future.delayed(const Duration(milliseconds: 400));
    final speaker = _speakers[idx];
    final vol = _speakers.length > 1 ? _volume : (speaker['volume'] as double);
    final service = ref.read(voiceGuidanceServiceProvider);
    final testConfig = VoiceGuidanceConfig(
      enabled: true,
      language: _language,
      gender: _gender,
      tone: _tone,
      pace: _pace,
      volume: vol,
      outputDevice: speaker['device'] as String,
      speakers: [SpeakerConfig(device: speaker['device'] as String, volume: vol, delayMs: speaker['delayMs'] as int? ?? 0)],
    );
    service.updateConfig(testConfig);
    await service.speak('entry_proceed');
  }

  bool _playingAll = false;

  Future<void> _testAllSpeakers() async {
    _stopAll();
    await Future.delayed(const Duration(milliseconds: 400));
    _playingAll = true;
    if (mounted) setState(() {});
    final service = ref.read(voiceGuidanceServiceProvider);
    debugPrint('[Voice] Test All — raw speakers: ${_speakers.map((s) => s['device']).toList()}');
    final activeSpeakers = _speakers.where((s) => (s['device'] as String).isNotEmpty).toList();
    debugPrint('[Voice] Test All — active speakers: ${activeSpeakers.map((s) => s['device']).toList()}');
    final testConfig = VoiceGuidanceConfig(
      enabled: true,
      language: _language,
      gender: _gender,
      tone: _tone,
      pace: _pace,
      weightAnnounceMode: _weightAnnounceMode,
      volume: activeSpeakers.length > 1 ? _volume : (activeSpeakers.isNotEmpty ? (activeSpeakers.first['volume'] as double) : _volume),
      speakers: activeSpeakers.map((s) => SpeakerConfig(device: s['device'] as String, volume: s['volume'] as double)).toList(),
    );
    service.updateConfig(testConfig);
    for (final key in _promptLabels.keys) {
      if (!mounted || !_playingAll) break;
      if (_disabledPrompts.contains(key)) continue;
      if (key == 'weight_captured') {
        final base = DateTime.now().millisecondsSinceEpoch % 9860 + 140;
        final weight = base * 5;
        final net = (weight * 0.65).round();
        await service.speakWeight('$weight', netWeight: '$net');
      } else {
        await service.speak(key);
      }
    }
    _playingAll = false;
    if (mounted) setState(() {});
  }

  void _stopAll() {
    _playingAll = false;
    _voiceService.stop();
    if (mounted) setState(() {});
  }

  Future<void> _testPrompt(String key) async {
    _stopAll();
    await Future.delayed(const Duration(milliseconds: 100));
    final service = ref.read(voiceGuidanceServiceProvider);
    final testConfig = VoiceGuidanceConfig(
      enabled: true,
      language: _language,
      gender: _gender,
      tone: _tone,
      pace: _pace,
      weightAnnounceMode: _weightAnnounceMode,
      volume: _speakers.length > 1 ? _volume : (_speakers.isNotEmpty ? (_speakers.first['volume'] as double) : _volume),
      speakers: _speakers.map((s) => SpeakerConfig(device: s['device'] as String, volume: s['volume'] as double, delayMs: s['delayMs'] as int? ?? 0)).toList(),
    );
    service.updateConfig(testConfig);
    if (key == 'weight_captured') {
      final base = DateTime.now().millisecondsSinceEpoch % 9860 + 140;
      final weight = base * 5;
      final net = (weight * 0.65).round(); // simulate net = ~65% of gross
      await service.speakWeight('$weight', netWeight: '$net');
    } else {
      await service.speak(key);
    }
  }


  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final configAsync = ref.watch(voiceGuidanceConfigProvider);
    configAsync.whenData(_loadConfig);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Column(
        children: [
          _buildHeader(scheme, text),
          WeighbridgeContextBar(
            label: 'Voice config for',
            onSwitched: () {
              _stopAll();
              ref.invalidate(voiceGuidanceConfigProvider);
              setState(() => _loaded = false);
            },
          ),
          Expanded(
            child: configAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) => SingleChildScrollView(
                padding: AppSpacing.pagePadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildGeneralCard(scheme, text),
                    SizedBox(height: AppSpacing.xl),
                    _buildPromptsCard(scheme, text),
                    SizedBox(height: 40.rs),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme, TextTheme text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      decoration: BoxDecoration(color: scheme.surface, borderRadius: AppRadius.card, border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)), boxShadow: AppElevation.card(scheme.shadow)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(onPressed: () => context.go('/settings'), icon: const Icon(Icons.arrow_back_rounded, size: 20), style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: AppRadius.button))),
              SizedBox(width: AppSpacing.md),
              Icon(Icons.record_voice_over_rounded, size: 20, color: scheme.primary),
              SizedBox(width: 10.rs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Voice Guidance', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text('Speaker announcements for drivers', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded, size: 16),
                label: Text(_saving ? 'Saving...' : 'Save'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
              ),
            ],
          ),
          if (_headerMsg != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _headerMsgIsError ? scheme.errorContainer.withValues(alpha: 0.6) : AppTheme.successColor.withValues(alpha: 0.1),
                  borderRadius: AppRadius.button,
                  border: Border.all(color: _headerMsgIsError ? scheme.error.withValues(alpha: 0.3) : AppTheme.successColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _headerMsgIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                      size: 15,
                      color: _headerMsgIsError ? scheme.error : AppTheme.successColor,
                    ),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(_headerMsg!, style: text.bodySmall?.copyWith(color: _headerMsgIsError ? scheme.error : AppTheme.successColor, fontWeight: FontWeight.w500))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGeneralCard(ColorScheme scheme, TextTheme text) {
    return AppCard(
      title: 'General',
      icon: Icons.volume_up_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Enable Voice Guidance', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    Text('Play audio prompts for drivers at each stage', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Switch(value: _enabled, onChanged: (v) => setState(() => _enabled = v)),
            ],
          ),
          if (_enabled) ...[
          SizedBox(height: AppSpacing.lg),
          Text('Language', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: 5.rs),
          DropdownButtonFormField<String>(
            value: _language,
            items: _languages.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: text.bodySmall)))
                .toList(),
            onChanged: (v) { if (v != null) setState(() => _language = v); },
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
          ),
          SizedBox(height: AppSpacing.lg),
          Text('Voice', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: 5.rs),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _gender = 'female'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _gender == 'female' ? AppTheme.brandTeal.withValues(alpha: 0.1) : scheme.surface,
                      borderRadius: BorderRadius.circular(8.rs),
                      border: Border.all(color: _gender == 'female' ? AppTheme.brandTeal : scheme.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    child: Center(child: Text('Female', style: TextStyle(fontSize: 12, fontWeight: _gender == 'female' ? FontWeight.w700 : FontWeight.w500, color: _gender == 'female' ? AppTheme.brandTeal : scheme.onSurfaceVariant))),
                  ),
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _gender = 'male'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _gender == 'male' ? AppTheme.brandTeal.withValues(alpha: 0.1) : scheme.surface,
                      borderRadius: BorderRadius.circular(8.rs),
                      border: Border.all(color: _gender == 'male' ? AppTheme.brandTeal : scheme.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    child: Center(child: Text('Male', style: TextStyle(fontSize: 12, fontWeight: _gender == 'male' ? FontWeight.w700 : FontWeight.w500, color: _gender == 'male' ? AppTheme.brandTeal : scheme.onSurfaceVariant))),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Text('Speakers', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                onPressed: _loadingDevices ? null : _loadOutputDevices,
                icon: Icon(Icons.refresh_rounded, size: 14, color: scheme.onSurfaceVariant),
                tooltip: 'Refresh devices',
                style: IconButton.styleFrom(padding: const EdgeInsets.all(4)),
              ),
              SizedBox(width: AppSpacing.xs),
              FilledButton.tonal(
                onPressed: () {
                  if (_playingAll || _voiceService.isSpeaking) {
                    _stopAll();
                  } else {
                    _testAllSpeakers();
                  }
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                ),
                child: Text(_playingAll || _voiceService.isSpeaking ? 'Stop' : 'Test All'),
              ),
              SizedBox(width: AppSpacing.xs),
              Builder(builder: (_) {
                final realDevices = _availableDevices.where((d) => d != 'System Default').length;
                final canAdd = _speakers.length < realDevices;
                return FilledButton.tonal(
                  onPressed: canAdd ? () {
                    final used = _speakers.map((s) => s['device'] as String).toSet();
                    final nextDevice = _availableDevices.where((d) => d != 'System Default' && !used.contains(d)).firstOrNull ?? '';
                    setState(() => _speakers.add(<String, dynamic>{'device': nextDevice, 'volume': 0.8, 'delayMs': 0}));
                  } : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('+ Add'),
                );
              }),
            ],
          ),
          SizedBox(height: 6.rs),
          LayoutBuilder(builder: (context, constraints) {
            final tileWidth = (constraints.maxWidth - 8) / 2;
            return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _speakers.asMap().entries.map((entry) {
              final idx = entry.key;
              final speaker = entry.value;
              final device = speaker['device'] as String;
              final vol = speaker['volume'] as double;
              return SizedBox(
                width: tileWidth,
                child: Container(
                  padding: EdgeInsets.all(10.rs),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
                    borderRadius: AppRadius.button,
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      // Device selector
                      Icon(Icons.speaker_rounded, size: 14, color: scheme.onSurfaceVariant),
                      SizedBox(width: 4.rs),
                      Expanded(
                        flex: 3,
                        child: _loadingDevices
                            ? Text('Detecting...', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant))
                            : Builder(builder: (_) {
                                final usedByOthers = _speakers.asMap().entries
                                    .where((e) => e.key != idx)
                                    .map((e) => (e.value['device'] as String).isEmpty ? 'System Default' : e.value['device'] as String)
                                    .toSet();
                                final available = _availableDevices.where((d) => d != 'System Default' && !usedByOthers.contains(d)).toList();
                                final currentVal = device.isEmpty ? 'System Default' : device;
                                var dropVal = available.contains(currentVal) ? currentVal : (available.isNotEmpty ? available.first : 'System Default');
                                // Persist fallback selection back to state
                                if (device.isEmpty && dropVal != 'System Default' && available.isNotEmpty) {
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (_speakers[idx]['device'] != dropVal) {
                                      _speakers[idx]['device'] = dropVal;
                                    }
                                  });
                                }
                                return DropdownButtonFormField<String>(
                                  value: available.contains(dropVal) ? dropVal : null,
                                  items: available.map((d) => DropdownMenuItem(value: d, child: Text(d, style: text.bodySmall))).toList(),
                                  onChanged: (v) => setState(() => _speakers[idx]['device'] = v ?? ''),
                                  decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
                                );
                              }),
                      ),
                      if (_speakers.length == 1) ...[
                        SizedBox(width: 8.rs),
                        Expanded(
                          flex: 2,
                          child: Row(
                            children: [
                              Expanded(
                                child: SliderTheme(
                                  data: SliderThemeData(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
                                  child: Slider(
                                    value: vol,
                                    divisions: 20,
                                    onChanged: (v) => setState(() => _speakers[idx]['volume'] = v),
                                  ),
                                ),
                              ),
                              SizedBox(width: 4.rs),
                              Text('${(vol * 100).round()}%', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                      SizedBox(width: 12.rs),
                      // Play button
                      SizedBox(
                        height: 28,
                        width: 28,
                        child: IconButton(
                          onPressed: () => _testSpeaker(idx),
                          icon: Icon(Icons.play_arrow_rounded, size: 16, color: scheme.onSurfaceVariant),
                          padding: EdgeInsets.zero,
                          style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh, shape: RoundedRectangleBorder(borderRadius: AppRadius.chip)),
                        ),
                      ),
                      if (_speakers.length > 1) ...[
                        SizedBox(width: 4.rs),
                        SizedBox(
                          height: 28,
                          width: 28,
                          child: IconButton(
                            onPressed: () => setState(() => _speakers.removeAt(idx)),
                            icon: Icon(Icons.close_rounded, size: 14, color: scheme.error),
                            padding: EdgeInsets.zero,
                            style: IconButton.styleFrom(backgroundColor: scheme.errorContainer.withValues(alpha: 0.3), shape: RoundedRectangleBorder(borderRadius: AppRadius.chip)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          );
          }),
          if (_speakers.length > 1) ...[
            SizedBox(height: 10.rs),
            Row(
              children: [
                Text('Master Volume', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                SizedBox(width: 8.rs),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
                    child: Slider(
                      value: _volume,
                      divisions: 20,
                      onChanged: (v) => setState(() => _volume = v),
                    ),
                  ),
                ),
                SizedBox(width: 4.rs),
                Text('${(_volume * 100).round()}%', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ],
          SizedBox(height: 6.rs),
          Text(
            _speakers.length > 1
                ? 'All speakers play simultaneously at master volume.'
                : 'Add multiple speakers for simultaneous playback.',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
          ),
          ],
        ],
      ),
    );
  }

  static const _promptIcons = <String, IconData>{
    'entry_proceed': Icons.login_rounded,
    'stop_on_platform': Icons.pause_circle_rounded,
    'engine_off': Icons.power_settings_new_rounded,
    'weight_captured': Icons.scale_rounded,
    'scanning': Icons.qr_code_scanner_rounded,
    'exit_proceed': Icons.logout_rounded,
    'driver_missing': Icons.person_off_rounded,
  };

  static const _promptPhase = <String, String>{
    'entry_proceed': 'Truck arriving',
    'stop_on_platform': 'On platform',
    'engine_off': 'Before capture',
    'weight_captured': 'Weight done',
    'scanning': 'ANPR active',
    'exit_proceed': 'After save',
    'driver_missing': 'Alert',
  };

  Widget _buildPromptsCard(ColorScheme scheme, TextTheme text) {
    final prompts = VoiceGuidanceService.defaultPrompts[_language] ?? VoiceGuidanceService.defaultPrompts['en']!;
    final hasAudio = VoiceGuidanceService.hasVoicePack(_language, _gender, 'polite');

    return AppCard(
      title: 'Weighment Announcements',
      icon: Icons.campaign_rounded,
      actions: [
        GestureDetector(
          onTap: _testAllSpeakers,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: AppRadius.chip,
              border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow_rounded, size: 13, color: scheme.primary),
                SizedBox(width: 4.rs),
                Text('Play All', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.primary)),
              ],
            ),
          ),
        ),
        SizedBox(width: 6.rs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: hasAudio ? AppTheme.successColor.withValues(alpha: 0.1) : scheme.surfaceContainerHigh,
            borderRadius: AppRadius.chip,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(hasAudio ? Icons.graphic_eq_rounded : Icons.record_voice_over_rounded, size: 11, color: hasAudio ? AppTheme.successColor : scheme.onSurfaceVariant),
              SizedBox(width: 4.rs),
              Text(hasAudio ? 'AI Voice' : 'System TTS', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: hasAudio ? AppTheme.successColor : scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Builder(builder: (_) {
            final entries = _promptLabels.entries.toList();
            final leftCol = entries.sublist(0, (entries.length + 1) ~/ 2);
            final rightCol = entries.sublist((entries.length + 1) ~/ 2);
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Column(
                    children: leftCol.map((e) => _buildPromptTile(e.key, e.value, prompts[e.key] ?? '', scheme, text)).toList(),
                  )),
                  SizedBox(width: 8.rs),
                  Expanded(child: Column(
                    children: rightCol.map((e) => _buildPromptTile(e.key, e.value, prompts[e.key] ?? '', scheme, text)).toList(),
                  )),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPromptTile(String key, String label, String promptText, ColorScheme scheme, TextTheme text) {
    final icon = _promptIcons[key] ?? Icons.volume_up_rounded;
    final phase = _promptPhase[key] ?? '';
    final disabled = _disabledPrompts.contains(key);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: EdgeInsets.all(10.rs),
        decoration: BoxDecoration(
          color: disabled ? scheme.surfaceContainerLow.withValues(alpha: 0.3) : scheme.surfaceContainerLow.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8.rs),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: disabled ? 0.1 : 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: disabled ? scheme.outlineVariant : scheme.primary),
                SizedBox(width: 6.rs),
                Expanded(child: Text(phase, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: disabled ? scheme.outlineVariant : scheme.onSurface))),
                SizedBox(
                  height: 28,
                  width: 28,
                  child: IconButton(
                    onPressed: () => _testPrompt(key),
                    icon: Icon(Icons.play_arrow_rounded, size: 16, color: scheme.onSurfaceVariant),
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh, shape: RoundedRectangleBorder(borderRadius: AppRadius.chip)),
                  ),
                ),
                SizedBox(width: 4.rs),
                SizedBox(
                  height: 28,
                  child: Switch(
                    value: !disabled,
                    onChanged: (v) => setState(() {
                      if (v) { _disabledPrompts.remove(key); } else { _disabledPrompts.add(key); }
                    }),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            SizedBox(height: 4.rs),
            Text(
              promptText,
              style: text.bodySmall?.copyWith(color: disabled ? scheme.outlineVariant : scheme.onSurfaceVariant, height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (key == 'weight_captured') ...[
              SizedBox(height: 6.rs),
              Row(
                children: [
                  Text('Cadence:', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                  SizedBox(width: 4.rs),
                  for (final p in ['fast', 'medium', 'slow'])
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: GestureDetector(
                        onTap: () => setState(() => _pace = p),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _pace == p ? scheme.primaryContainer.withValues(alpha: 0.4) : Colors.transparent,
                            borderRadius: BorderRadius.circular(4.rs),
                            border: Border.all(color: _pace == p ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            switch (p) { 'fast' => 'Rapid', 'slow' => 'Deliberate', _ => 'Natural' },
                            style: text.labelSmall?.copyWith(fontWeight: _pace == p ? FontWeight.w700 : FontWeight.w500, color: _pace == p ? scheme.primary : scheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 6.rs),
              Row(
                children: [
                  Text('Announce:', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                  SizedBox(width: 4.rs),
                  for (final m in ['captured', 'captured_and_net'])
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: GestureDetector(
                        onTap: () => setState(() => _weightAnnounceMode = m),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _weightAnnounceMode == m ? scheme.primaryContainer.withValues(alpha: 0.4) : Colors.transparent,
                            borderRadius: BorderRadius.circular(4.rs),
                            border: Border.all(color: _weightAnnounceMode == m ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            m == 'captured' ? 'Weight Only' : 'Weight + Net',
                            style: text.labelSmall?.copyWith(fontWeight: _weightAnnounceMode == m ? FontWeight.w700 : FontWeight.w500, color: _weightAnnounceMode == m ? scheme.primary : scheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
