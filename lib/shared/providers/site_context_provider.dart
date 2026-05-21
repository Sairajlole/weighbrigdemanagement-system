import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class SiteContext {
  final String companyId;
  final String siteId;
  final String weighbridgeId;

  const SiteContext({
    required this.companyId,
    required this.siteId,
    required this.weighbridgeId,
  });

  bool get isConfigured =>
      companyId.isNotEmpty && siteId.isNotEmpty && weighbridgeId.isNotEmpty;

  String get companyPath => 'companies/$companyId';
  String get sitePath => '$companyPath/sites/$siteId';
  String get weighbridgePath => '$sitePath/weighbridges/$weighbridgeId';

  Map<String, String> toMap() => {
        'companyId': companyId,
        'siteId': siteId,
        'weighbridgeId': weighbridgeId,
      };

  factory SiteContext.fromMap(Map<String, dynamic> map) => SiteContext(
        companyId: map['companyId'] as String? ?? '',
        siteId: map['siteId'] as String? ?? '',
        weighbridgeId: map['weighbridgeId'] as String? ?? '',
      );

  static const empty = SiteContext(companyId: '', siteId: '', weighbridgeId: '');
}

String get _configDir {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  final dir = Directory('$home/.weighbridge');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir.path;
}

String get _configPath => '$_configDir/site_context.json';
String get _wizardProgressPath => '$_configDir/wizard_progress.json';

class SiteContextNotifier extends StateNotifier<SiteContext> {
  SiteContextNotifier() : super(_loadSync());

  static SiteContext _loadSync() {
    try {
      final file = File(_configPath);
      if (file.existsSync()) {
        final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        return SiteContext.fromMap(data);
      }
    } catch (_) {}
    return SiteContext.empty;
  }

  Future<void> configure({
    required String companyId,
    required String siteId,
    required String weighbridgeId,
  }) async {
    final ctx = SiteContext(
      companyId: companyId,
      siteId: siteId,
      weighbridgeId: weighbridgeId,
    );
    state = ctx;
    await File(_configPath).writeAsString(jsonEncode(ctx.toMap()));
  }

  Future<void> clear() async {
    state = SiteContext.empty;
    final file = File(_configPath);
    if (await file.exists()) await file.delete();
  }
}

final siteContextProvider =
    StateNotifierProvider<SiteContextNotifier, SiteContext>((ref) {
  return SiteContextNotifier();
});

// ─── Wizard Progress Persistence ────────────────────────────────────────────

class WizardProgress {
  final int currentStepIndex;
  final String role;
  final String licenseTier;
  final bool setupComplete;

  const WizardProgress({
    this.currentStepIndex = 0,
    this.role = 'undecided',
    this.licenseTier = 'free',
    this.setupComplete = false,
  });

  Map<String, dynamic> toMap() => {
    'currentStepIndex': currentStepIndex,
    'role': role,
    'licenseTier': licenseTier,
    'setupComplete': setupComplete,
  };

  factory WizardProgress.fromMap(Map<String, dynamic> map) => WizardProgress(
    currentStepIndex: map['currentStepIndex'] as int? ?? 0,
    role: map['role'] as String? ?? 'undecided',
    licenseTier: map['licenseTier'] as String? ?? 'free',
    setupComplete: map['setupComplete'] as bool? ?? false,
  );

  static const empty = WizardProgress();
}

class WizardProgressNotifier extends StateNotifier<WizardProgress> {
  WizardProgressNotifier() : super(_loadSync());

  static WizardProgress _loadSync() {
    try {
      final file = File(_wizardProgressPath);
      if (file.existsSync()) {
        final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        return WizardProgress.fromMap(data);
      }
    } catch (_) {}
    return WizardProgress.empty;
  }

  Future<void> saveProgress({
    required int stepIndex,
    required String role,
    required String licenseTier,
  }) async {
    final progress = WizardProgress(
      currentStepIndex: stepIndex,
      role: role,
      licenseTier: licenseTier,
      setupComplete: state.setupComplete,
    );
    state = progress;
    await File(_wizardProgressPath).writeAsString(jsonEncode(progress.toMap()));
  }

  Future<void> markComplete() async {
    state = WizardProgress(
      currentStepIndex: state.currentStepIndex,
      role: state.role,
      licenseTier: state.licenseTier,
      setupComplete: true,
    );
    await File(_wizardProgressPath).writeAsString(jsonEncode(state.toMap()));
  }

  Future<void> clear() async {
    state = WizardProgress.empty;
    final file = File(_wizardProgressPath);
    if (file.existsSync()) await file.delete();
  }
}

final wizardProgressProvider =
    StateNotifierProvider<WizardProgressNotifier, WizardProgress>((ref) {
  return WizardProgressNotifier();
});
