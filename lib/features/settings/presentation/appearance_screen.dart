import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/appearance_provider.dart';

const _accentColors = <Color>[
  Color(0xFF059669), // Emerald (default)
  Color(0xFF2563EB), // Blue
  Color(0xFF7C3AED), // Violet
  Color(0xFFDC2626), // Red
  Color(0xFFEA580C), // Orange
  Color(0xFFCA8A04), // Amber
  Color(0xFF0891B2), // Cyan
  Color(0xFF4F46E5), // Indigo
  Color(0xFFDB2777), // Pink
  Color(0xFF16A34A), // Green
  Color(0xFF475569), // Slate
  Color(0xFF1E293B), // Dark
];

const _accentLabels = <String>[
  'Emerald', 'Blue', 'Violet', 'Red', 'Orange', 'Amber',
  'Cyan', 'Indigo', 'Pink', 'Green', 'Slate', 'Dark',
];

const _backgroundArts = <String, String>{
  'none': 'None',
  'topography': 'Topography',
  'circuit': 'Circuit Board',
  'dots': 'Polka Dots',
  'waves': 'Waves',
  'grid': 'Grid Lines',
  'diagonal': 'Diagonal Stripes',
};

class AppearanceScreen extends ConsumerStatefulWidget {
  const AppearanceScreen({super.key});

  @override
  ConsumerState<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends ConsumerState<AppearanceScreen> {
  late ThemeMode _themeMode;
  late Color _accentColor;
  late String _backgroundArt;
  late double _fontScale;
  late String _locale;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(appearanceProvider);
    _themeMode = settings.themeMode;
    _accentColor = settings.accentColor;
    _backgroundArt = settings.backgroundArt;
    _fontScale = settings.fontScale;
    _locale = settings.locale;
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(appearanceProvider.notifier).update(
        AppearanceSettings(
          themeMode: _themeMode,
          accentColor: _accentColor,
          backgroundArt: _backgroundArt,
          fontScale: _fontScale,
          locale: _locale,
        ),
      );
      setState(() { _dirty = false; _saving = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Appearance settings saved'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 16),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => context.go('/settings'),
                  icon: Icon(Icons.arrow_back_rounded, size: 20, color: scheme.onSurface),
                ),
                const SizedBox(width: 8),
                Icon(Icons.palette_rounded, size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Appearance', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text('Theme, colors, and language', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
                const Spacer(),
                if (_dirty) ...[
                  TextButton(
                    onPressed: () {
                      final settings = ref.read(appearanceProvider);
                      setState(() {
                        _themeMode = settings.themeMode;
                        _accentColor = settings.accentColor;
                        _backgroundArt = settings.backgroundArt;
                        _fontScale = settings.fontScale;
                        _locale = settings.locale;
                        _dirty = false;
                      });
                    },
                    child: const Text('Discard'),
                  ),
                  const SizedBox(width: 8),
                ],
                FilledButton.icon(
                  onPressed: _dirty && !_saving ? _save : null,
                  icon: _saving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded, size: 16),
                  label: Text(_saving ? 'Saving...' : 'Save'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildThemeSection(scheme, text),
                  const SizedBox(height: 32),
                  _buildAccentSection(scheme, text),
                  const SizedBox(height: 32),
                  _buildBackgroundSection(scheme, text),
                  const SizedBox(height: 32),
                  _buildFontSection(scheme, text),
                  const SizedBox(height: 32),
                  _buildLanguageSection(scheme, text),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSection(ColorScheme scheme, TextTheme text) {
    return _Section(
      icon: Icons.dark_mode_rounded,
      title: 'Theme',
      scheme: scheme,
      text: text,
      children: [
        Row(
          children: [
            _ThemeOption(
              label: 'Light',
              icon: Icons.light_mode_rounded,
              selected: _themeMode == ThemeMode.light,
              onTap: () { setState(() => _themeMode = ThemeMode.light); _markDirty(); },
              scheme: scheme, text: text,
            ),
            const SizedBox(width: 12),
            _ThemeOption(
              label: 'Dark',
              icon: Icons.dark_mode_rounded,
              selected: _themeMode == ThemeMode.dark,
              onTap: () { setState(() => _themeMode = ThemeMode.dark); _markDirty(); },
              scheme: scheme, text: text,
            ),
            const SizedBox(width: 12),
            _ThemeOption(
              label: 'System',
              icon: Icons.settings_brightness_rounded,
              selected: _themeMode == ThemeMode.system,
              onTap: () { setState(() => _themeMode = ThemeMode.system); _markDirty(); },
              scheme: scheme, text: text,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAccentSection(ColorScheme scheme, TextTheme text) {
    return _Section(
      icon: Icons.color_lens_rounded,
      title: 'Accent Color',
      scheme: scheme,
      text: text,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: List.generate(_accentColors.length, (i) {
            final color = _accentColors[i];
            final selected = _accentColor.toARGB32() == color.toARGB32();
            return Tooltip(
              message: _accentLabels[i],
              child: GestureDetector(
                onTap: () { setState(() => _accentColor = color); _markDirty(); },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? scheme.onSurface : Colors.transparent,
                      width: selected ? 2.5 : 0,
                    ),
                    boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 2))] : null,
                  ),
                  child: selected ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildBackgroundSection(ColorScheme scheme, TextTheme text) {
    return _Section(
      icon: Icons.texture_rounded,
      title: 'Background Art',
      scheme: scheme,
      text: text,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _backgroundArts.entries.map((entry) {
            final selected = _backgroundArt == entry.key;
            return GestureDetector(
              onTap: () { setState(() => _backgroundArt = entry.key); _markDirty(); },
              child: Container(
                width: 100,
                height: 70,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4), width: selected ? 2 : 1),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(child: _ArtPreview(art: entry.key, color: scheme.primary.withValues(alpha: 0.15))),
                    Positioned(
                      bottom: 4,
                      left: 0, right: 0,
                      child: Text(entry.value, textAlign: TextAlign.center, style: text.labelSmall?.copyWith(fontSize: 9, color: scheme.onSurfaceVariant)),
                    ),
                    if (selected)
                      Positioned(
                        top: 4, right: 4,
                        child: Container(
                          width: 16, height: 16,
                          decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                          child: const Icon(Icons.check_rounded, color: Colors.white, size: 10),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildFontSection(ColorScheme scheme, TextTheme text) {
    return _Section(
      icon: Icons.text_fields_rounded,
      title: 'Font Size',
      subtitle: 'Does not affect print docket layout',
      scheme: scheme,
      text: text,
      children: [
        Row(
          children: [
            _FontOption(label: 'Small', scale: 0.85, selected: _fontScale == 0.85, onTap: () { setState(() => _fontScale = 0.85); _markDirty(); }, scheme: scheme, text: text),
            const SizedBox(width: 10),
            _FontOption(label: 'Default', scale: 1.0, selected: _fontScale == 1.0, onTap: () { setState(() => _fontScale = 1.0); _markDirty(); }, scheme: scheme, text: text),
            const SizedBox(width: 10),
            _FontOption(label: 'Large', scale: 1.15, selected: _fontScale == 1.15, onTap: () { setState(() => _fontScale = 1.15); _markDirty(); }, scheme: scheme, text: text),
            const SizedBox(width: 10),
            _FontOption(label: 'Extra Large', scale: 1.3, selected: _fontScale == 1.3, onTap: () { setState(() => _fontScale = 1.3); _markDirty(); }, scheme: scheme, text: text),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Text(
            'The quick brown fox jumps over the lazy dog. 0123456789',
            style: text.bodyMedium?.copyWith(fontSize: 14 * _fontScale),
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageSection(ColorScheme scheme, TextTheme text) {
    return _Section(
      icon: Icons.translate_rounded,
      title: 'Language',
      subtitle: 'Hindi labels with English searchability',
      scheme: scheme,
      text: text,
      children: [
        Row(
          children: [
            _LangOption(
              label: 'English',
              native: 'English',
              code: 'en',
              selected: _locale == 'en',
              onTap: () { setState(() => _locale = 'en'); _markDirty(); },
              scheme: scheme, text: text,
            ),
            const SizedBox(width: 12),
            _LangOption(
              label: 'Hindi',
              native: 'हिन्दी',
              code: 'hi',
              selected: _locale == 'hi',
              onTap: () { setState(() => _locale = 'hi'); _markDirty(); },
              scheme: scheme, text: text,
            ),
          ],
        ),
        if (_locale == 'hi') ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'UI labels shown in Hindi. Search, vehicle numbers, and data entry remain in English for compatibility.',
                    style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Widgets ────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final ColorScheme scheme;
  final TextTheme text;
  final List<Widget> children;

  const _Section({required this.icon, required this.title, this.subtitle, required this.scheme, required this.text, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.15))),
            ),
            child: Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(7)),
                  child: Icon(icon, size: 15, color: scheme.primary),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                    if (subtitle != null) Text(subtitle!, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme scheme;
  final TextTheme text;

  const _ThemeOption({required this.label, required this.icon, required this.selected, required this.onTap, required this.scheme, required this.text});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer.withValues(alpha: 0.4) : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4), width: selected ? 2 : 1),
          ),
          child: Column(
            children: [
              Icon(icon, size: 24, color: selected ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(height: 8),
              Text(label, style: text.labelMedium?.copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? scheme.primary : scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FontOption extends StatelessWidget {
  final String label;
  final double scale;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme scheme;
  final TextTheme text;

  const _FontOption({required this.label, required this.scale, required this.selected, required this.onTap, required this.scheme, required this.text});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer.withValues(alpha: 0.4) : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4), width: selected ? 2 : 1),
          ),
          child: Column(
            children: [
              Text('Aa', style: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w700, color: selected ? scheme.primary : scheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(label, style: text.labelSmall?.copyWith(fontSize: 10, color: selected ? scheme.primary : scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LangOption extends StatelessWidget {
  final String label;
  final String native;
  final String code;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme scheme;
  final TextTheme text;

  const _LangOption({required this.label, required this.native, required this.code, required this.selected, required this.onTap, required this.scheme, required this.text});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer.withValues(alpha: 0.4) : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4), width: selected ? 2 : 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(native, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: selected ? scheme.primary : scheme.onSurfaceVariant)),
              const SizedBox(width: 8),
              Text('($label)', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtPreview extends StatelessWidget {
  final String art;
  final Color color;

  const _ArtPreview({required this.art, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CustomPaint(
        size: const Size(90, 50),
        painter: _ArtPainter(art, color),
      ),
    );
  }
}

class _ArtPainter extends CustomPainter {
  final String art;
  final Color color;

  _ArtPainter(this.art, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1..style = PaintingStyle.stroke;

    switch (art) {
      case 'topography':
        for (double y = 8; y < size.height; y += 12) {
          final path = Path()..moveTo(0, y);
          for (double x = 0; x < size.width; x += 20) {
            path.quadraticBezierTo(x + 10, y + (x % 40 == 0 ? -6 : 6), x + 20, y);
          }
          canvas.drawPath(path, paint);
        }
      case 'circuit':
        for (double y = 5; y < size.height; y += 15) {
          for (double x = 5; x < size.width; x += 20) {
            canvas.drawCircle(Offset(x, y), 2, paint..style = PaintingStyle.fill);
            if (x + 20 < size.width) canvas.drawLine(Offset(x + 2, y), Offset(x + 18, y), paint..style = PaintingStyle.stroke);
          }
        }
      case 'dots':
        paint.style = PaintingStyle.fill;
        for (double y = 6; y < size.height; y += 10) {
          for (double x = 6; x < size.width; x += 10) {
            canvas.drawCircle(Offset(x, y), 1.5, paint);
          }
        }
      case 'waves':
        for (double y = 10; y < size.height; y += 14) {
          final path = Path()..moveTo(0, y);
          for (double x = 0; x < size.width; x += 30) {
            path.cubicTo(x + 7, y - 8, x + 23, y + 8, x + 30, y);
          }
          canvas.drawPath(path, paint);
        }
      case 'grid':
        for (double x = 0; x < size.width; x += 12) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        for (double y = 0; y < size.height; y += 12) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
      case 'diagonal':
        for (double d = -size.height; d < size.width + size.height; d += 10) {
          canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), paint);
        }
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ArtPainter old) => art != old.art || color != old.color;
}
