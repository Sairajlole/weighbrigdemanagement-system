import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/appearance_provider.dart';
import '../../application/setup_wizard_provider.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';


class AppearanceStep extends ConsumerStatefulWidget {
  const AppearanceStep({super.key});

  @override
  ConsumerState<AppearanceStep> createState() => _AppearanceStepState();
}

class _AppearanceStepState extends ConsumerState<AppearanceStep> {
  late ThemeMode _themeMode;
  late double _fontScale;
  late String _locale;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(appearanceProvider);
    _themeMode = settings.themeMode;
    _fontScale = settings.fontScale;
    _locale = settings.locale;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(stepSaveCallbackProvider.notifier).state = _save;
      // Appearance always has preferences to save
      ref.read(stepHasDataProvider.notifier).state = true;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<bool> _save() async {
    try {
      await ref.read(appearanceProvider.notifier).update(
        AppearanceSettings(
          themeMode: _themeMode,
          backgroundArt: ref.read(appearanceProvider).backgroundArt,
          fontScale: _fontScale,
          locale: _locale,
        ),
      );
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), behavior: SnackBarBehavior.floating),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: EdgeInsets.all(40.rs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Appearance', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: AppSpacing.sm),
          Text(
            'Personalize the look and feel of your weighbridge application.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          SizedBox(height: AppSpacing.xxl),

          // Theme mode
          Text('Theme', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _ThemeCard(icon: Icons.light_mode_rounded, label: 'Light', isSelected: _themeMode == ThemeMode.light,
                  onTap: () => setState(() => _themeMode = ThemeMode.light), scheme: scheme),
              SizedBox(width: AppSpacing.md),
              _ThemeCard(icon: Icons.dark_mode_rounded, label: 'Dark', isSelected: _themeMode == ThemeMode.dark,
                  onTap: () => setState(() => _themeMode = ThemeMode.dark), scheme: scheme),
              SizedBox(width: AppSpacing.md),
              _ThemeCard(icon: Icons.brightness_auto_rounded, label: 'System', isSelected: _themeMode == ThemeMode.system,
                  onTap: () => setState(() => _themeMode = ThemeMode.system), scheme: scheme),
            ],
          ),

          SizedBox(height: AppSpacing.xxl),

          // Font scale
          Text('Font Size', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Text('Aa', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              Expanded(
                child: Slider(
                  value: _fontScale,
                  min: 0.85,
                  max: 1.3,
                  divisions: 3,
                  label: '${(_fontScale * 100).round()}%',
                  onChanged: (v) => setState(() => _fontScale = v),
                ),
              ),
              Text('Aa', style: TextStyle(fontSize: 18, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
            ],
          ),
          Center(
            child: Text('${(_fontScale * 100).round()}%',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),

          SizedBox(height: AppSpacing.xxl),

          // Language
          Text('Language', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _LangChip(label: 'English', value: 'en', isSelected: _locale == 'en',
                  onTap: () => setState(() => _locale = 'en'), scheme: scheme),
            ],
          ),

          SizedBox(height: AppSpacing.xl),
          Container(
            padding: EdgeInsets.all(12.rs),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.2),
              borderRadius: AppRadius.button,
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: scheme.primary),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Background art and additional display options are available in Settings.',
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme scheme;

  const _ThemeCard({
    required this.icon, required this.label, required this.isSelected,
    required this.onTap, required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? scheme.primary.withValues(alpha: 0.05) : scheme.surface,
          borderRadius: BorderRadius.circular(10.rs),
          border: Border.all(
            color: isSelected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: isSelected ? scheme.primary : scheme.onSurfaceVariant),
            SizedBox(height: 6.rs),
            Text(label, style: TextStyle(
              fontSize: 12, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
            )),
          ],
        ),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  final String label;
  final String value;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme scheme;

  const _LangChip({
    required this.label, required this.value, required this.isSelected,
    required this.onTap, required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? scheme.primary.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: AppRadius.button,
          border: Border.all(
            color: isSelected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 13, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
        )),
      ),
    );
  }
}
