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

String get _configPath {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  final dir = Directory('$home/.weighbridge');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return '${dir.path}/site_context.json';
}

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
