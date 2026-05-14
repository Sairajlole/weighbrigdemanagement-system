import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/l10n/app_strings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final strings = ref.watch(stringsProvider);

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.settings,
            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
          ),
          const SizedBox(height: 4),
          Text(
            'Configure your weighbridge system preferences',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          // Search bar
          SizedBox(
            width: 400,
            child: TextField(
              style: text.bodySmall,
              decoration: InputDecoration(
                hintText: 'Search settings categories or fields...',
                prefixIcon: Icon(Icons.search_rounded, size: 18, color: scheme.onSurfaceVariant),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: _settingsItems(strings).map((item) => _SettingsTile(
                  item: item,
                  onTap: () => _navigate(context, item.route),
                )).toList(),
              ),
            ),
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

class _SettingsItemData {
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final Color? badgeColor;
  final String? badge;

  const _SettingsItemData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    this.badgeColor,
    this.badge,
  });
}

List<_SettingsItemData> _settingsItems(AppStrings s) => [
  _SettingsItemData(
    icon: Icons.settings_rounded,
    title: s.general,
    subtitle: 'Company, region, and site identity',
    route: 'general',
  ),
  _SettingsItemData(
    icon: Icons.text_fields_rounded,
    title: s.customFields,
    subtitle: 'Additional fields on dockets',
    route: 'custom-fields',
  ),
  _SettingsItemData(
    icon: Icons.inventory_2_rounded,
    title: s.materials,
    subtitle: 'Product list and categories',
    route: 'materials',
  ),
  _SettingsItemData(
    icon: Icons.sensor_door_rounded,
    title: s.gateControl,
    subtitle: 'Barriers, RFID, and safety',
    route: 'gate-control',
  ),
  _SettingsItemData(
    icon: Icons.scale_rounded,
    title: s.weighbridge,
    subtitle: 'Scale and indicator setup',
    route: 'weighbridge',
  ),
  _SettingsItemData(
    icon: Icons.videocam_rounded,
    title: s.cameras,
    subtitle: 'ANPR, CCTV, and detection',
    route: 'cameras',
    badge: 'AI',
    badgeColor: const Color(0xFF059669),
  ),
  _SettingsItemData(
    icon: Icons.notifications_rounded,
    title: s.notifications,
    subtitle: 'Alerts and event triggers',
    route: 'notifications',
  ),
  _SettingsItemData(
    icon: Icons.print_rounded,
    title: s.printing,
    subtitle: 'Docket layout and printers',
    route: 'printing',
  ),
  _SettingsItemData(
    icon: Icons.backup_rounded,
    title: s.dataBackup,
    subtitle: 'Backups and data retention',
    route: 'backup',
  ),
  _SettingsItemData(
    icon: Icons.shield_rounded,
    title: s.security,
    subtitle: 'Access control and audit',
    route: 'mfa',
  ),
  _SettingsItemData(
    icon: Icons.hub_rounded,
    title: s.integrations,
    subtitle: 'Tally, displays, and cloud sync',
    route: 'integrations',
  ),
  _SettingsItemData(
    icon: Icons.palette_rounded,
    title: s.appearance,
    subtitle: 'Theme, colors, and language',
    route: 'appearance',
  ),
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
    final text = Theme.of(context).textTheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: 260,
          height: 88,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovered ? scheme.primary.withValues(alpha: 0.3) : scheme.outlineVariant.withValues(alpha: 0.25),
            ),
            boxShadow: [
              BoxShadow(
                color: _hovered ? scheme.primary.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.02),
                blurRadius: _hovered ? 16 : 6,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Stack(
                  children: [
                    Center(child: Icon(widget.item.icon, size: 20, color: scheme.primary)),
                    if (widget.item.badge != null)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: widget.item.badgeColor ?? scheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.item.badge!,
                            style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.title,
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.item.subtitle,
                      style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}
