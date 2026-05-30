import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Color _migrateAccentColor(int? saved) {
  // Brand color is fixed — always use Tulanam teal
  return AppTheme.defaultAccent;
}

class AppearanceSettings {
  final ThemeMode themeMode;
  final Color accentColor;
  final String backgroundArt;
  final double fontScale;
  final String locale;

  const AppearanceSettings({
    this.themeMode = ThemeMode.light,
    this.accentColor = AppTheme.defaultAccent,
    this.backgroundArt = 'none',
    this.fontScale = 1.0,
    this.locale = 'en',
  });

  factory AppearanceSettings.fromMap(Map<String, dynamic> data) {
    return AppearanceSettings(
      themeMode: switch (data['themeMode'] as String? ?? 'light') {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      },
      accentColor: _migrateAccentColor(data['accentColor'] as int?),
      backgroundArt: data['backgroundArt'] as String? ?? 'none',
      fontScale: (data['fontScale'] as num? ?? 1.0).toDouble(),
      locale: data['locale'] as String? ?? 'en',
    );
  }

  Map<String, dynamic> toMap() => {
    'themeMode': switch (themeMode) {
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
      _ => 'light',
    },
    'accentColor': accentColor.toARGB32(),
    'backgroundArt': backgroundArt,
    'fontScale': fontScale,
    'locale': locale,
  };

  AppearanceSettings copyWith({
    ThemeMode? themeMode,
    Color? accentColor,
    String? backgroundArt,
    double? fontScale,
    String? locale,
  }) {
    return AppearanceSettings(
      themeMode: themeMode ?? this.themeMode,
      accentColor: accentColor ?? this.accentColor,
      backgroundArt: backgroundArt ?? this.backgroundArt,
      fontScale: fontScale ?? this.fontScale,
      locale: locale ?? this.locale,
    );
  }
}

String get _localPath {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  final dir = Directory('$home/.weighbridge');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return '${dir.path}/appearance.json';
}

AppearanceSettings _loadLocal() {
  try {
    final file = File(_localPath);
    if (file.existsSync()) {
      return AppearanceSettings.fromMap(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    }
  } catch (_) {}
  return const AppearanceSettings();
}

void _saveLocal(AppearanceSettings settings) {
  try {
    File(_localPath).writeAsStringSync(jsonEncode(settings.toMap()));
  } catch (_) {}
}

final appearanceProvider = StateNotifierProvider<AppearanceNotifier, AppearanceSettings>((ref) {
  final initial = _loadLocal();
  return AppearanceNotifier(initial);
});

class AppearanceNotifier extends StateNotifier<AppearanceSettings> {
  AppearanceNotifier(AppearanceSettings initial) : super(initial);

  Future<void> update(AppearanceSettings settings) async {
    state = settings;
    _saveLocal(settings);
  }

  void setThemeMode(ThemeMode mode) => update(state.copyWith(themeMode: mode));
  void setAccentColor(Color color) => update(state.copyWith(accentColor: color));
  void setBackgroundArt(String art) => update(state.copyWith(backgroundArt: art));
  void setFontScale(double scale) => update(state.copyWith(fontScale: scale));
  void setLocale(String locale) => update(state.copyWith(locale: locale));
}
