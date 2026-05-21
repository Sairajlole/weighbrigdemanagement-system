import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/l10n/app_strings.dart';
import 'package:weighbridgemanagement/shared/providers/license_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';

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
    final perms = ref.watch(permissionServiceProvider);
    final isAdmin = perms.isAdmin;
    final allSections = _buildSections(strings);

    final sections = allSections
        .map((s) => _SettingsSection(
              s.label,
              s.items.where((item) {
                if (!item.adminOnly) return true;
                if (isAdmin) return true;
                if (item.permissionKey != null) {
                  return switch (item.permissionKey) {
                    'printing' => perms.canAccessPrinting,
                    'gateControl' => perms.canAccessGateControl,
                    'cameras' => perms.canAccessCameras,
                    'weighbridge' => perms.canAccessWeighbridge,
                    _ => false,
                  };
                }
                return false;
              }).toList(),
            ))
        .where((s) => s.items.isNotEmpty)
        .toList();

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
              isFree: ref.watch(isFreeProvider),
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
  final bool proOnly;
  final bool adminOnly;
  final String? proDescription;
  final String? permissionKey;

  const _SettingsItemData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    this.proOnly = false,
    this.adminOnly = false,
    this.proDescription,
    this.permissionKey,
  });
}

List<_SettingsSection> _buildSections(AppStrings s) => [
  _SettingsSection('GENERAL', [
    _SettingsItemData(
      icon: Icons.settings_rounded,
      title: s.general,
      subtitle: 'Company & site identity',
      route: 'general',
      adminOnly: true,
    ),
    _SettingsItemData(
      icon: Icons.palette_rounded,
      title: s.appearance,
      subtitle: 'Theme & language',
      route: 'appearance',
      adminOnly: false,
    ),
    _SettingsItemData(
      icon: Icons.text_fields_rounded,
      title: s.customFields,
      subtitle: 'Docket fields',
      route: 'custom-fields',
      adminOnly: true,
    ),
    _SettingsItemData(
      icon: Icons.inventory_2_rounded,
      title: s.materials,
      subtitle: 'Products & categories',
      route: 'materials',
      adminOnly: true,
    ),
  ]),
  _SettingsSection('HARDWARE', [
    _SettingsItemData(
      icon: Icons.scale_rounded,
      title: s.weighbridge,
      subtitle: 'Scale & indicator setup',
      route: 'weighbridge',
      adminOnly: true,
      permissionKey: 'weighbridge',
    ),
    _SettingsItemData(
      icon: Icons.sensor_door_rounded,
      title: s.gateControl,
      subtitle: 'Barriers & RFID',
      route: 'gate-control',
      proOnly: true,
      adminOnly: true,
      permissionKey: 'gateControl',
      proDescription: 'Automated boom barrier control with RFID tag validation, vehicle queue management, interlock safety systems, and real-time gate event logging — prevents unauthorized entry/exit and ensures accurate vehicle tracking without manual intervention at busy weighbridge facilities.',
    ),
    _SettingsItemData(
      icon: Icons.videocam_rounded,
      title: s.cameras,
      subtitle: 'ANPR & CCTV',
      route: 'cameras',
      proOnly: true,
      adminOnly: true,
      permissionKey: 'cameras',
      proDescription: 'IP camera integration with automatic number plate recognition (ANPR), face detection for operator verification, tamper-evident video recording linked to each weighment, and AI-powered anomaly detection — provides irrefutable proof of vehicle identity and prevents fraud at scale.',
    ),
    _SettingsItemData(
      icon: Icons.print_rounded,
      title: s.printing,
      subtitle: 'Dockets & printers',
      route: 'printing',
      adminOnly: true,
      permissionKey: 'printing',
    ),
  ]),
  _SettingsSection('SYSTEM', [
    _SettingsItemData(
      icon: Icons.verified_rounded,
      title: 'License',
      subtitle: 'Plan & updates',
      route: 'license',
      adminOnly: true,
    ),
    _SettingsItemData(
      icon: Icons.shield_rounded,
      title: s.security,
      subtitle: 'Access & audit',
      route: 'mfa',
      proOnly: true,
      adminOnly: true,
      proDescription: 'Multi-factor authentication, IP whitelist with subnet/CIDR rules, role-based access control, operator shift enforcement, audit trail logging, session management, emergency lockdown, and password policies — essential for organizations handling high-value transactions across multiple weighbridges.',
    ),
    _SettingsItemData(
      icon: Icons.notifications_rounded,
      title: s.notifications,
      subtitle: 'Alerts & triggers',
      route: 'notifications',
      proOnly: true,
      adminOnly: true,
      proDescription: 'Real-time email and SMS alerts for overweight violations, unauthorized access attempts, scale drift detection, gate malfunctions, and daily summary reports — critical for compliance monitoring and instant incident response in commercial weighing operations.',
    ),
    _SettingsItemData(
      icon: Icons.backup_rounded,
      title: s.dataBackup,
      subtitle: 'Backup & retention',
      route: 'backup',
      adminOnly: true,
    ),
    _SettingsItemData(
      icon: Icons.hub_rounded,
      title: s.integrations,
      subtitle: 'Tally & cloud sync',
      route: 'integrations',
      proOnly: true,
      adminOnly: true,
      proDescription: 'Automatic synchronization with Tally ERP/Prime, cloud backup mirroring, webhook triggers for third-party systems, and API access for custom ERP integrations — eliminates double data entry and keeps your accounting system in sync with every weighment automatically.',
    ),
  ]),
];

class _SettingsTile extends StatefulWidget {
  final _SettingsItemData item;
  final bool isFree;
  final VoidCallback onTap;

  const _SettingsTile({required this.item, required this.isFree, required this.onTap});

  @override
  State<_SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<_SettingsTile> {
  bool _hovered = false;
  static const _proColor = AppTheme.proColor;

  void _showProUpsell() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF4C1D95), const Color(0xFF312E81)]
                        : AppTheme.proGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(widget.item.icon, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.item.title,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.item.subtitle,
                                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7)),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.workspace_premium_rounded, size: 12, color: Colors.amber),
                              SizedBox(width: 4),
                              Text('PRO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.8)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Body
              Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.item.proDescription != null) ...[
                      Text(
                        widget.item.proDescription!,
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.6),
                      ),
                      const SizedBox(height: 20),
                    ],
                    // Feature comparison
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? scheme.surfaceContainerHigh : const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        children: [
                          _comparisonHeader(isDark),
                          _comparisonRow('Basic weighing & reports', true, true, scheme, isDark),
                          _comparisonRow('Single weighbridge', true, true, scheme, isDark),
                          _comparisonRow('Customers & materials', true, true, scheme, isDark),
                          _comparisonDivider(scheme),
                          _comparisonRow('Multiple sites & weighbridges', false, true, scheme, isDark),
                          _comparisonRow('IP cameras & ANPR', false, true, scheme, isDark),
                          _comparisonRow('Gate barrier automation', false, true, scheme, isDark),
                          _comparisonRow('Advanced security & MFA', false, true, scheme, isDark),
                          _comparisonRow('Tally & cloud integrations', false, true, scheme, isDark),
                          _comparisonRow('Priority support', false, true, scheme, isDark),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // CTA
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              foregroundColor: scheme.onSurfaceVariant,
                            ),
                            child: const Text('Maybe Later'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              GoRouter.of(context).go('/settings/license');
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: _proColor,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.rocket_launch_rounded, size: 16),
                            label: const Text('Upgrade to Pro', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _comparisonHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1B2E) : const Color(0xFFF3F0FF),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 3, child: Text('Feature', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
          SizedBox(width: 50, child: Center(child: Text('Free', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)))),
          SizedBox(width: 50, child: Center(child: Text('Pro', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _proColor)))),
        ],
      ),
    );
  }

  Widget _comparisonRow(String feature, bool inFree, bool inPro, ColorScheme scheme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(feature, style: TextStyle(fontSize: 11, color: scheme.onSurface))),
          SizedBox(
            width: 50,
            child: Center(child: Icon(
              inFree ? Icons.check_rounded : Icons.close_rounded,
              size: 14,
              color: inFree ? Colors.green : scheme.onSurfaceVariant.withValues(alpha: 0.3),
            )),
          ),
          SizedBox(
            width: 50,
            child: Center(child: Icon(
              inPro ? Icons.check_rounded : Icons.close_rounded,
              size: 14,
              color: inPro ? _proColor : scheme.onSurfaceVariant.withValues(alpha: 0.3),
            )),
          ),
        ],
      ),
    );
  }

  Widget _comparisonDivider(ColorScheme scheme) {
    return Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.2), indent: 14, endIndent: 14);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final locked = widget.item.proOnly && widget.isFree;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: locked ? _showProUpsell : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          width: 240,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: locked
                ? _proColor.withValues(alpha: _hovered ? 0.06 : 0.02)
                : (_hovered ? accent.withValues(alpha: 0.04) : scheme.surface),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: locked
                  ? _proColor.withValues(alpha: _hovered ? 0.4 : 0.2)
                  : (_hovered ? accent.withValues(alpha: 0.3) : scheme.outlineVariant.withValues(alpha: 0.25)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(widget.item.icon, size: 24, color: locked ? _proColor.withValues(alpha: 0.6) : accent),
                  if (locked) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_rounded, size: 9, color: Colors.white),
                          SizedBox(width: 3),
                          Text('PRO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Text(widget.item.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: locked ? scheme.onSurface.withValues(alpha: 0.6) : scheme.onSurface)),
              const SizedBox(height: 4),
              Text(widget.item.subtitle, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (locked) ...[
                const SizedBox(height: 10),
                Text('Tap to learn more', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _proColor.withValues(alpha: 0.7))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
