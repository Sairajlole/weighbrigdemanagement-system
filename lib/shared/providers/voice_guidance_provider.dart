import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/voice_guidance_service.dart';

final voiceGuidanceConfigProvider = FutureProvider<VoiceGuidanceConfig>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const VoiceGuidanceConfig();
  try {
    final snap = await paths.camerasAiSettings.get();
    if (snap.exists) {
      final data = snap.data()!;
      final voiceData = data['voiceGuidance'] as Map<String, dynamic>? ?? {};
      return VoiceGuidanceConfig.fromMap(voiceData);
    }
  } catch (_) {}
  return const VoiceGuidanceConfig();
});

final voiceGuidanceServiceProvider = Provider<VoiceGuidanceService>((ref) {
  final configAsync = ref.watch(voiceGuidanceConfigProvider);
  final config = configAsync.valueOrNull ?? const VoiceGuidanceConfig();
  final service = VoiceGuidanceService(config);

  VoiceGuidanceService.ensureBundledVoices();

  ref.onDispose(() => service.dispose());
  return service;
});

final voiceGuidanceSpeakProvider = Provider<Future<void> Function(String, {Map<String, String>? replacements})>((ref) {
  final service = ref.watch(voiceGuidanceServiceProvider);
  return (String promptKey, {Map<String, String>? replacements}) =>
      service.speak(promptKey, replacements: replacements);
});

Future<void> saveVoiceGuidanceConfig(WidgetRef ref, VoiceGuidanceConfig config) async {
  final paths = ref.read(firestorePathsProvider);
  if (!paths.isConfigured) throw Exception('No weighbridge selected');
  await paths.camerasAiSettings.set({
    'voiceGuidance': config.toMap(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
  ref.invalidate(voiceGuidanceConfigProvider);
}
