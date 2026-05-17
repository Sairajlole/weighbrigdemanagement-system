import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/l10n/app_strings.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final strings = ref.watch(stringsProvider);
    final sections = _buildSections(strings);

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.settings, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: sections.map((section) => _buildSection(context, section, scheme)).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, _SettingsSection section, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.5)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: section.items.map((item) => _SettingsTile(
              item: item,
              onTap: () => _navigate(context, item.route),
            )).toList(),
          ),
        ],
      ),
    );
  }

  void _navigate(BuildContext context, String route) {
    if (route.startsWith('/')) {
      context.go(route);
    } else {
      context.go('/settings/$route');
    }
  }
}

class _SettingsSection {
  final String label;
  final List<_SettingsItemData> items;
  const _SettingsSection(this.label, this.items);
}

class _SettingsItemData {
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final Color? accentColor;

  const _SettingsItemData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    this.accentColor,
  });
}

List<_SettingsSection> _buildSections(AppStrings s) => [
  _SettingsSection('GENERAL', [
    _SettingsItemData(
      icon: Icons.settings_rounded,
      title: s.general,
      subtitle: 'Company & site identity',
      route: 'general',
    ),
    _SettingsItemData(
      icon: Icons.palette_rounded,
      title: s.appearance,
      subtitle: 'Theme & language',
      route: 'appearance',
    ),
    _SettingsItemData(
      icon: Icons.text_fields_rounded,
      title: s.customFields,
      subtitle: 'Docket fields',
      route: 'custom-fields',
    ),
    _SettingsItemData(
      icon: Icons.inventory_2_rounded,
      title: s.materials,
      subtitle: 'Products & categories',
      route: 'materials',
    ),
  ]),
  _SettingsSection('HARDWARE', [
    _SettingsItemData(
      icon: Icons.scale_rounded,
      title: s.weighbridge,
      subtitle: 'Scale & indicator setup',
      route: 'weighbridge',
    ),
    _SettingsItemData(
      icon: Icons.sensor_door_rounded,
      title: s.gateControl,
      subtitle: 'Barriers & RFID',
      route: 'gate-control',
    ),
    _SettingsItemData(
      icon: Icons.videocam_rounded,
      title: s.cameras,
      subtitle: 'ANPR & CCTV',
      route: 'cameras',
      accentColor: AppTheme.defaultAccent,
    ),
    _SettingsItemData(
      icon: Icons.print_rounded,
      title: s.printing,
      subtitle: 'Dockets & printers',
      route: 'printing',
    ),
  ]),
  _SettingsSection('SYSTEM', [
    _SettingsItemData(
      icon: Icons.shield_rounded,
      title: s.security,
      subtitle: 'Access & audit',
      route: 'mfa',
    ),
    _SettingsItemData(
      icon: Icons.notifications_rounded,
      title: s.notifications,
      subtitle: 'Alerts & triggers',
      route: 'notifications',
    ),
    _SettingsItemData(
      icon: Icons.backup_rounded,
      title: s.dataBackup,
      subtitle: 'Backup & retention',
      route: 'backup',
    ),
    _SettingsItemData(
      icon: Icons.hub_rounded,
      title: s.integrations,
      subtitle: 'Tally & cloud sync',
      route: 'integrations',
    ),
  ]),
];

class _SettingsTile extends StatefulWidget {
  final _SettingsItemData item;
  final VoidCallback onTap;

  const _SettingsTile({required this.item, required this.onTap});

  @override
  State<_SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<_SettingsTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.item.accentColor ?? scheme.primary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          width: 240,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _hovered ? accent.withValues(alpha: 0.04) : scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered ? accent.withValues(alpha: 0.3) : scheme.outlineVariant.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.item.icon, size: 24, color: accent),
              const SizedBox(height: 14),
              Text(widget.item.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface)),
              const SizedBox(height: 4),
              Text(widget.item.subtitle, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}
