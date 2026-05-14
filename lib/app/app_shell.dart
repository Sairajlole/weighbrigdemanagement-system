import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/auth_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import 'package:weighbridgemanagement/shared/providers/general_settings_provider.dart';
import 'package:weighbridgemanagement/shared/providers/notifications_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/l10n/app_strings.dart';
import 'package:weighbridgemanagement/shared/widgets/background_art.dart';
import 'package:weighbridgemanagement/shared/widgets/inactivity_wrapper.dart';
import 'package:weighbridgemanagement/shared/widgets/security_overlay.dart';

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String path;

  const _NavItem({required this.icon, required this.selectedIcon, required this.label, required this.path});
}

List<_NavItem> _buildNavItems(AppStrings s) => [
  _NavItem(icon: Icons.space_dashboard_outlined, selectedIcon: Icons.space_dashboard_rounded, label: s.dashboard, path: '/dashboard'),
  _NavItem(icon: Icons.scale_outlined, selectedIcon: Icons.scale_rounded, label: s.weighment, path: '/weighment'),
  _NavItem(icon: Icons.people_outline_rounded, selectedIcon: Icons.people_rounded, label: s.customers, path: '/customers'),
  _NavItem(icon: Icons.badge_outlined, selectedIcon: Icons.badge_rounded, label: s.operators, path: '/operators'),
  _NavItem(icon: Icons.assessment_outlined, selectedIcon: Icons.assessment_rounded, label: s.reports, path: '/reports'),
  _NavItem(icon: Icons.settings_outlined, selectedIcon: Icons.settings_rounded, label: s.settings, path: '/settings'),
];

class AppShell extends ConsumerWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  List<_NavItem> _filteredNavItems(PermissionService perms, AppStrings strings) {
    return _buildNavItems(strings).where((item) {
      if (item.path == '/reports' && !perms.canViewReports) return false;
      if (item.path == '/customers' && !perms.canManageCustomers) return false;
      if (item.path == '/settings' && !perms.canAccessSettings) return false;
      return true;
    }).toList();
  }

  int _currentIndex(BuildContext context, List<_NavItem> navItems) {
    final location = GoRouterState.of(context).matchedLocation;
    final idx = navItems.indexWhere((item) => location.startsWith(item.path));
    return idx == -1 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final perms = ref.watch(permissionServiceProvider);
    final strings = ref.watch(stringsProvider);
    final navItems = _filteredNavItems(perms, strings);
    final selectedIndex = _currentIndex(context, navItems);

    return Scaffold(
      body: Row(
        children: [
          // Navigation Rail
          Container(
            width: 76,
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(
                right: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2)),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 20),
                // Logo
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [scheme.primary, scheme.primary.withValues(alpha: 0.8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(Icons.scale_rounded, color: scheme.onPrimary, size: 22),
                ),
                const SizedBox(height: 32),
                // Nav items
                Expanded(
                  child: Column(
                    children: navItems.asMap().entries.map((entry) {
                      final i = entry.key;
                      final item = entry.value;
                      final isSelected = i == selectedIndex;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: _NavButton(
                          icon: isSelected ? item.selectedIcon : item.icon,
                          label: item.label,
                          isSelected: isSelected,
                          onTap: () => context.go(item.path),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                // Profile
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _NavButton(
                    icon: Icons.account_circle_rounded,
                    label: 'Profile',
                    isSelected: GoRouterState.of(context).matchedLocation == '/profile',
                    onTap: () => context.go('/profile'),
                  ),
                ),
                // Notifications bell
                _NotificationBell(ref: ref),
                const SizedBox(height: 4),
                // Logout
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: _NavButton(
                    icon: Icons.logout_rounded,
                    label: 'Logout',
                    isSelected: false,
                    isDestructive: true,
                    onTap: () async {
                      await ref.read(firebaseAuthProvider).signOut();
                    },
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(child: BackgroundArt(child: InactivityWrapper(child: SecurityOverlay(child: child)))),
        ],
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isDestructive;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> with SingleTickerProviderStateMixin {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeColor = widget.isDestructive ? scheme.error : scheme.primary;
    final iconColor = widget.isSelected
        ? activeColor
        : _hovered
            ? scheme.onSurface
            : scheme.onSurfaceVariant;

    return Tooltip(
      message: widget.label,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? activeColor.withValues(alpha: 0.08)
                  : _hovered
                      ? scheme.surfaceContainerHighest.withValues(alpha: 0.6)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Active indicator bar
                if (widget.isSelected)
                  Positioned(
                    left: 0,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      width: 3,
                      height: 24,
                      decoration: BoxDecoration(
                        color: activeColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(widget.icon, size: 22, color: iconColor),
                    const SizedBox(height: 3),
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: widget.isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: iconColor,
                        letterSpacing: -0.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  final WidgetRef ref;
  const _NotificationBell({required this.ref});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notifications = ref.watch(unreadNotificationsProvider);
    final count = notifications.valueOrNull?.length ?? 0;

    return Tooltip(
      message: 'Notifications',
      child: GestureDetector(
        onTap: () => _showNotificationsPanel(context),
        child: SizedBox(
          width: 56,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.notifications_outlined, size: 22, color: scheme.onSurfaceVariant),
              if (count > 0)
                Positioned(
                  top: 8,
                  right: 14,
                  child: Container(
                    width: 16, height: 16,
                    decoration: BoxDecoration(color: scheme.error, shape: BoxShape.circle),
                    child: Center(child: Text(count > 9 ? '9+' : '$count', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white))),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNotificationsPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        alignment: Alignment.centerLeft,
        insetPadding: const EdgeInsets.only(left: 90, top: 20, bottom: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 380,
          height: 500,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Icon(Icons.notifications_rounded, size: 20, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text('Security Alerts', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        final db = ref.read(firestoreProvider);
                        markAllNotificationsRead(db);
                        Navigator.pop(ctx);
                      },
                      child: const Text('Mark all read', style: TextStyle(fontSize: 11)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Consumer(
                  builder: (_, ref2, __) {
                    final notifs = ref2.watch(unreadNotificationsProvider);
                    return notifs.when(
                      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      error: (e, _) => Center(child: Text('Error: $e')),
                      data: (items) {
                        if (items.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_outline_rounded, size: 40, color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
                                const SizedBox(height: 8),
                                Text('No unread alerts', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final n = items[i];
                            final title = n['title'] as String? ?? '';
                            final body = n['body'] as String? ?? '';
                            final createdAt = n['createdAt'];
                            String timeStr = '';
                            if (createdAt is Timestamp) {
                              timeStr = formatTimestamp(createdAt, ref.read(timeFormatProvider), dateFormat: 'dd MMM');
                            }

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: scheme.errorContainer.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: scheme.error.withValues(alpha: 0.15)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.shield_rounded, size: 14, color: scheme.error),
                                      const SizedBox(width: 6),
                                      Expanded(child: Text(title, style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700))),
                                      Text(timeStr, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(body, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
