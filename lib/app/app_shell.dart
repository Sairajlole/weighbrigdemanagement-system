import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/features/setup/application/setup_wizard_provider.dart';
import 'package:weighbridgemanagement/shared/providers/auth_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';
import 'package:weighbridgemanagement/shared/providers/general_settings_provider.dart';
import 'package:weighbridgemanagement/shared/providers/notifications_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/l10n/app_strings.dart';
import 'package:weighbridgemanagement/shared/providers/connectivity_provider.dart';
import 'package:weighbridgemanagement/shared/providers/offline_provider.dart';
import 'package:weighbridgemanagement/shared/widgets/background_art.dart';
import 'package:weighbridgemanagement/shared/widgets/inactivity_wrapper.dart';
import 'package:weighbridgemanagement/shared/widgets/security_overlay.dart';

final _pendingOperatorsCountProvider = StreamProvider<int>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.operators.where('isVerified', isEqualTo: false).snapshots().map(
    (snap) => snap.docs.where((d) => d.data()['isArchived'] != true).length,
  );
});

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
  _NavItem(icon: Icons.list_alt_outlined, selectedIcon: Icons.list_alt_rounded, label: s.weighments, path: '/weighments'),
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
    final idx = navItems.indexWhere((item) => location == item.path || location.startsWith('${item.path}/'));
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
                      final badge = item.path == '/operators'
                          ? (ref.watch(_pendingOperatorsCountProvider).valueOrNull ?? 0)
                          : 0;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: _NavButton(
                          icon: isSelected ? item.selectedIcon : item.icon,
                          label: item.label,
                          isSelected: isSelected,
                          onTap: () => context.go(item.path),
                          badge: badge,
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
                // Logout
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _NavButton(
                    icon: Icons.logout_rounded,
                    label: 'Logout',
                    isSelected: false,
                    isDestructive: true,
                    onTap: () async {
                      await ref.read(firebaseAuthProvider).signOut();
                      await ref.read(siteContextProvider.notifier).clear();
                      await LocalCacheService.clearCurrentUser();
                      ref.read(setupWizardProvider.notifier).reset();
                      if (context.mounted) context.go('/setup');
                    },
                  ),
                ),
                // Internet indicator
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: _ConnectivityDot(ref: ref),
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
  final int badge;

  const _NavButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isDestructive = false,
    this.badge = 0,
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
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(widget.icon, size: 22, color: iconColor),
                        if (widget.badge > 0)
                          Positioned(
                            right: -6,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${widget.badge}',
                                style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
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


class _ConnectivityDot extends StatefulWidget {
  final WidgetRef ref;
  const _ConnectivityDot({required this.ref});

  @override
  State<_ConnectivityDot> createState() => _ConnectivityDotState();
}

class _ConnectivityDotState extends State<_ConnectivityDot> {
  int _pendingCount = 0;
  Map<String, int> _breakdown = {};
  OverlayEntry? _overlayEntry;
  bool _hoveringDot = false;
  bool _hoveringPanel = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _refreshPending();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _removeOverlay();
    super.dispose();
  }

  void _refreshPending() async {
    final queue = widget.ref.read(offlineQueueProvider);
    final breakdown = await queue.pendingBreakdown;
    final count = breakdown.values.fold<int>(0, (a, b) => a + b);
    if (mounted && (count != _pendingCount || breakdown != _breakdown)) {
      setState(() { _pendingCount = count; _breakdown = breakdown; });
    }
    Future.delayed(const Duration(seconds: 10), () { if (mounted) _refreshPending(); });
  }

  final GlobalKey _dotKey = GlobalKey();

  void _showOverlay() {
    if (_overlayEntry != null) return;
    final renderBox = _dotKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final pos = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomFromScreen = screenHeight - pos.dy - size.height / 2;

    _overlayEntry = OverlayEntry(builder: (_) => _StatusPanelOverlay(
      left: pos.dx + size.width + 12,
      bottom: bottomFromScreen.clamp(20.0, screenHeight - 60),
      ref: widget.ref,
      pendingCount: _pendingCount,
      breakdown: _breakdown,
      onHoverChanged: (hovering) {
        _hoveringPanel = hovering;
        if (!hovering) _scheduleHide();
      },
      onSynced: () => _refreshPending(),
    ));
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 200), () {
      if (!_hoveringDot && !_hoveringPanel) _removeOverlay();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOnline = widget.ref.watch(connectivityProvider).valueOrNull ?? true;
    final alertCount = widget.ref.watch(unreadNotificationsProvider).valueOrNull?.length ?? 0;
    final badgeCount = _pendingCount + alertCount;

    return MouseRegion(
      key: _dotKey,
      onEnter: (_) {
        _hoveringDot = true;
        _hideTimer?.cancel();
        _showOverlay();
      },
      onExit: (_) {
        _hoveringDot = false;
        _scheduleHide();
      },
      child: SizedBox(
        width: 56,
        height: 28,
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline ? AppTheme.successColor : scheme.error,
                  boxShadow: [
                    BoxShadow(
                      color: (isOnline ? AppTheme.successColor : scheme.error).withValues(alpha: 0.4),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              if (badgeCount > 0)
                Positioned(
                  top: -6,
                  right: -10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: alertCount > 0 ? scheme.error : scheme.tertiary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeCount > 9 ? '9+' : '$badgeCount',
                      style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPanelOverlay extends ConsumerStatefulWidget {
  final double left;
  final double bottom;
  final WidgetRef ref;
  final int pendingCount;
  final Map<String, int> breakdown;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onSynced;

  const _StatusPanelOverlay({
    required this.left,
    required this.bottom,
    required this.ref,
    required this.pendingCount,
    required this.breakdown,
    required this.onHoverChanged,
    required this.onSynced,
  });

  @override
  ConsumerState<_StatusPanelOverlay> createState() => _StatusPanelOverlayState();
}

class _StatusPanelOverlayState extends ConsumerState<_StatusPanelOverlay> {
  late int _pendingCount = widget.pendingCount;
  late Map<String, int> _breakdown = widget.breakdown;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final queue = widget.ref.read(offlineQueueProvider);
    final isOnline = widget.ref.read(connectivityProvider).valueOrNull ?? true;

    return Positioned(
      left: widget.left,
      bottom: widget.bottom,
      child: MouseRegion(
        onEnter: (_) => widget.onHoverChanged(true),
        onExit: (_) => widget.onHoverChanged(false),
        child: Material(
          elevation: 8,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(14),
          color: scheme.surface,
          surfaceTintColor: scheme.surfaceTint,
          child: Container(
            width: 300,
            constraints: const BoxConstraints(maxHeight: 460),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isOnline ? AppTheme.successColor : scheme.error,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isOnline ? 'Online' : 'Offline',
                        style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),

                  if (_pendingCount == 0)
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.successColor),
                        const SizedBox(width: 8),
                        Text('All data synced', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    )
                  else ...[
                    Text('Pending sync', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    ..._breakdown.entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(_iconForType(e.key), size: 14, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Text(_labelForType(e.key), style: text.bodySmall),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('${e.value}', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    )),
                  ],

                  if (queue.lastSyncAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Icon(
                            queue.lastSyncSuccess ? Icons.sync_rounded : Icons.sync_problem_rounded,
                            size: 14,
                            color: queue.lastSyncSuccess ? scheme.onSurfaceVariant : scheme.error,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Last sync: ${_formatTime(queue.lastSyncAt!)}',
                            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),

                  if (_pendingCount > 0) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: isOnline ? () async {
                          await queue.flush();
                          widget.onSynced();
                          final newBreakdown = await queue.pendingBreakdown;
                          final newCount = newBreakdown.values.fold<int>(0, (a, b) => a + b);
                          if (mounted) setState(() { _pendingCount = newCount; _breakdown = newBreakdown; });
                        } : null,
                        icon: const Icon(Icons.sync_rounded, size: 16),
                        label: Text(queue.isSyncing ? 'Syncing...' : 'Sync Now'),
                        style: FilledButton.styleFrom(
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    if (!isOnline)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Waiting for connection to sync',
                          style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                        ),
                      ),
                  ],

                  // ── Alerts ──
                  Consumer(
                    builder: (_, ref2, __) {
                      final notifs = ref2.watch(unreadNotificationsProvider);
                      final items = notifs.valueOrNull ?? [];
                      if (items.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 14),
                          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.shield_rounded, size: 14, color: scheme.error),
                              const SizedBox(width: 6),
                              Text('Alerts', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                              const Spacer(),
                              GestureDetector(
                                onTap: () {
                                  final paths = ref2.read(firestorePathsProvider);
                                  markAllNotificationsRead(paths);
                                },
                                child: Text('Clear all', style: text.labelSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...items.take(5).map((n) {
                            final title = n['title'] as String? ?? '';
                            final body = n['body'] as String? ?? '';
                            final createdAt = n['createdAt'];
                            String timeStr = '';
                            if (createdAt is Timestamp) {
                              timeStr = formatTimestamp(createdAt, ref2.read(timeFormatProvider), dateFormat: 'dd MMM');
                            }
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: scheme.errorContainer.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: scheme.error.withValues(alpha: 0.1)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: Text(title, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700))),
                                      Text(timeStr, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 9)),
                                    ],
                                  ),
                                  if (body.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(body, style: text.bodySmall?.copyWith(fontSize: 11, color: scheme.onSurfaceVariant)),
                                  ],
                                ],
                              ),
                            );
                          }),
                          if (items.length > 5)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '+${items.length - 5} more',
                                style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'weighments': return Icons.scale_rounded;
      case 'audit': return Icons.security_rounded;
      case 'operator_updates': return Icons.person_rounded;
      case 'sessions': return Icons.devices_rounded;
      default: return Icons.data_object_rounded;
    }
  }

  String _labelForType(String type) {
    switch (type) {
      case 'weighments': return 'Weighments';
      case 'audit': return 'Audit logs';
      case 'operator_updates': return 'Operator updates';
      case 'sessions': return 'Session records';
      default: return type;
    }
  }
}
