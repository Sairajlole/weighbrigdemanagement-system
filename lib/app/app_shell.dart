import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/features/profile/presentation/profile_screen.dart';
import 'package:weighbridgemanagement/features/setup/application/setup_wizard_provider.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';
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
import 'package:weighbridgemanagement/shared/providers/live_camera_feeds_provider.dart';
import 'package:weighbridgemanagement/shared/providers/system_stats_provider.dart';
import 'package:weighbridgemanagement/shared/widgets/background_art.dart';
import 'package:weighbridgemanagement/shared/widgets/inactivity_wrapper.dart';
import 'package:weighbridgemanagement/shared/widgets/security_overlay.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

final sidebarCollapsedProvider = StateProvider<bool>((ref) => false);

final _pendingOperatorsCountProvider = StreamProvider<int>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.operators.where('isVerified', isEqualTo: false).snapshots().map(
    (snap) => snap.docs.where((d) {
      final data = d.data();
      if (data['isArchived'] == true) return false;
      if ((data['uid'] as String? ?? '').isNotEmpty) return false;
      return true;
    }).length,
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
      if (item.path == '/operators' && !perms.isAdmin) return false;
      if (item.path == '/reports' && !perms.canViewReports) return false;
      if (item.path == '/customers' && !perms.canManageCustomers) return false;
      if (item.path == '/weighments' && !perms.canViewWeighments) return false;
      if (item.path == '/settings' && !perms.canAccessSettings) return false;
      if (item.path == '/weighment' && (perms.isDeactivated || perms.isAdmin)) return false;
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
    // Auto-start sidecar if not running, then sync embeddings
    ref.watch(sidecarAutoStartProvider);
    ref.watch(sidecarEmbeddingSyncProvider);
    // Eagerly start camera feeds so they're ready when navigating to weighment
    ref.watch(eagerCameraWarmupProvider);

    final perms = ref.watch(permissionServiceProvider);
    final strings = ref.watch(stringsProvider);
    final navItems = _filteredNavItems(perms, strings);
    final selectedIndex = _currentIndex(context, navItems);

    final location = GoRouterState.of(context).matchedLocation;
    final isWeighScreen = location == '/weighment' || location.startsWith('/weighment/');
    final collapsed = ref.watch(sidebarCollapsedProvider);
    final hideSidebar = isWeighScreen && collapsed;

    return Scaffold(
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: hideSidebar ? 0 : 64,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(),
            child: _Sidebar(
              navItems: navItems,
              selectedIndex: selectedIndex,
              onItemTap: (path) => context.go(path),
              onProfileTap: () => context.go('/profile'),
              isProfileSelected: GoRouterState.of(context).matchedLocation == '/profile',
            ),
          ),
          Expanded(
            child: Column(
              children: [
                if (perms.isDeactivated)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Row(
                      children: [
                        Icon(Icons.block_rounded, size: 16, color: Theme.of(context).colorScheme.error),
                        SizedBox(width: AppSpacing.sm),
                        Text(
                          'Your account has been deactivated. You cannot perform weighments. Contact your administrator.',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onErrorContainer),
                        ),
                      ],
                    ),
                  ),
                Expanded(child: BackgroundArt(child: InactivityWrapper(child: SecurityOverlay(child: child)))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerStatefulWidget {
  final List<_NavItem> navItems;
  final int selectedIndex;
  final ValueChanged<String> onItemTap;
  final VoidCallback onProfileTap;
  final bool isProfileSelected;

  const _Sidebar({
    required this.navItems,
    required this.selectedIndex,
    required this.onItemTap,
    required this.onProfileTap,
    required this.isProfileSelected,
  });

  @override
  ConsumerState<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<_Sidebar> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final profile = ref.watch(profileProvider).valueOrNull;

    return Container(
      width: 64,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(right: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.15))),
      ),
      child: Column(
        children: [
          SizedBox(height: AppSpacing.lg),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.primary.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10.rs),
              boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Icon(Icons.scale_rounded, color: scheme.onPrimary, size: 18),
          ),
          SizedBox(height: AppSpacing.md),
          Divider(height: 1, indent: 14, endIndent: 14, color: scheme.outlineVariant.withValues(alpha: 0.15)),
          SizedBox(height: AppSpacing.sm),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: [
                ...widget.navItems.asMap().entries.map((entry) {
                  final i = entry.key;
                  final item = entry.value;
                  final isSelected = i == widget.selectedIndex;
                  final badge = item.path == '/operators'
                      ? (ref.watch(_pendingOperatorsCountProvider).valueOrNull ?? 0)
                      : 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: _NavTile(
                      icon: isSelected ? item.selectedIcon : item.icon,
                      label: item.label,
                      isSelected: isSelected,
                      onTap: () => widget.onItemTap(item.path),
                      badge: badge,
                    ),
                  );
                }),
              ],
            ),
          ),
          Divider(height: 1, indent: 14, endIndent: 14, color: scheme.outlineVariant.withValues(alpha: 0.15)),
          SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _ProfileTile(
              isSelected: widget.isProfileSelected,
              onTap: widget.onProfileTap,
              profile: profile,
            ),
          ),
          SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _NavTile(
              icon: Icons.logout_rounded,
              label: 'Logout',
              isSelected: false,
              isDestructive: true,
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Sign out?'),
                    content: const Text('You will need to log in again to access this weighbridge.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
                    ],
                  ),
                );
                if (confirmed != true) return;
                await ref.read(firebaseAuthProvider).signOut();
                await ref.read(siteContextProvider.notifier).clear();
                await LocalCacheService.clearCurrentUser();
                ref.read(setupWizardProvider.notifier).reset();
                if (context.mounted) context.go('/setup');
              },
            ),
          ),
          SizedBox(height: AppSpacing.sm),
          _ConnectivityDot(ref: ref),
          SizedBox(height: 14.rs),
        ],
      ),
    );
  }

}

class _NavTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isDestructive;
  final VoidCallback onTap;
  final int badge;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isDestructive = false,
    this.badge = 0,
  });

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.isDestructive ? scheme.error : scheme.primary;
    final iconColor = widget.isSelected ? accent : _hovered ? scheme.onSurface : scheme.onSurfaceVariant;

    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.isSelected
            ? accent.withValues(alpha: 0.08)
            : _hovered
                ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(10.rs),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(widget.icon, size: 20, color: iconColor),
          if (widget.badge > 0)
            Positioned(
              right: -8, top: -6,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: scheme.error,
                  borderRadius: AppRadius.button,
                  border: Border.all(color: scheme.surface, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  widget.badge > 99 ? '99+' : '${widget.badge}',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: scheme.onError, height: 1),
                ),
              ),
            ),
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.label,
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 400),
        child: GestureDetector(onTap: widget.onTap, child: child),
      ),
    );
  }
}

class _ProfileTile extends StatefulWidget {
  final bool isSelected;
  final VoidCallback onTap;
  final Map<String, dynamic>? profile;

  const _ProfileTile({required this.isSelected, required this.onTap, this.profile});

  @override
  State<_ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends State<_ProfileTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = widget.profile?['name'] as String? ?? FirebaseAuth.instance.currentUser?.displayName ?? 'User';
    final pic = widget.profile?['profilePic'] as String?;

    Widget avatar;
    if (pic != null && pic.isNotEmpty) {
      String raw = pic;
      if (raw.contains(',')) raw = raw.split(',').last;
      avatar = CircleAvatar(
        radius: 15,
        backgroundImage: MemoryImage(Uint8List.fromList(base64Decode(raw))),
      );
    } else {
      avatar = CircleAvatar(
        radius: 15,
        backgroundColor: scheme.primary.withValues(alpha: 0.12),
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary)),
      );
    }

    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.isSelected
            ? scheme.primary.withValues(alpha: 0.08)
            : _hovered
                ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(10.rs),
      ),
      child: avatar,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: name,
        preferBelow: false,
        child: GestureDetector(onTap: widget.onTap, child: tile),
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
        width: 32,
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
                      borderRadius: AppRadius.chip,
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
          borderRadius: BorderRadius.circular(14.rs),
          color: scheme.surface,
          surfaceTintColor: scheme.surfaceTint,
          child: Container(
            width: 300,
            constraints: const BoxConstraints(maxHeight: 460),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14.rs),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: SingleChildScrollView(
              padding: AppSpacing.cardPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: isOnline ? AppTheme.successColor : scheme.error),
                      ),
                      SizedBox(width: 10.rs),
                      Text(isOnline ? 'Online' : 'Offline', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  SizedBox(height: AppSpacing.md),
                  Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
                  SizedBox(height: AppSpacing.md),

                  if (_pendingCount == 0)
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.successColor),
                        SizedBox(width: AppSpacing.sm),
                        Text('All data synced', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    )
                  else ...[
                    Text('Pending sync', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                    SizedBox(height: AppSpacing.sm),
                    ..._breakdown.entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(_iconForType(e.key), size: 14, color: scheme.onSurfaceVariant),
                          SizedBox(width: AppSpacing.sm),
                          Text(_labelForType(e.key), style: text.bodySmall),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(10.rs),
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
                          SizedBox(width: AppSpacing.sm),
                          Text(
                            'Last sync: ${_formatTime(queue.lastSyncAt!)}',
                            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),

                  if (_pendingCount > 0) ...[
                    SizedBox(height: AppSpacing.md),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.rs)),
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

                  // Alerts
                  Consumer(
                    builder: (_, ref2, __) {
                      final notifs = ref2.watch(unreadNotificationsProvider);
                      final items = notifs.valueOrNull ?? [];
                      if (items.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 14.rs),
                          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
                          SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Icon(Icons.shield_rounded, size: 14, color: scheme.error),
                              SizedBox(width: 6.rs),
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
                          SizedBox(height: AppSpacing.sm),
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
                              padding: EdgeInsets.all(10.rs),
                              decoration: BoxDecoration(
                                color: scheme.errorContainer.withValues(alpha: 0.12),
                                borderRadius: AppRadius.button,
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
                                    SizedBox(height: 2.rs),
                                    Text(body, style: text.bodySmall?.copyWith(fontSize: 11, color: scheme.onSurfaceVariant)),
                                  ],
                                ],
                              ),
                            );
                          }),
                          if (items.length > 5)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('+${items.length - 5} more', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                            ),
                        ],
                      );
                    },
                  ),

                  // Device stats
                  Consumer(
                    builder: (_, ref2, __) {
                      final stats = ref2.watch(systemStatsProvider).valueOrNull ?? SystemStats.zero;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 14.rs),
                          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
                          SizedBox(height: AppSpacing.md),
                          Text('Device', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                          SizedBox(height: 10.rs),
                          _DeviceStatRow(label: 'CPU', percent: stats.cpuPercent, scheme: scheme),
                          SizedBox(height: AppSpacing.sm),
                          _DeviceStatRow(label: 'RAM', percent: stats.memPercent, scheme: scheme),
                          if (stats.tempCelsius != null) ...[
                            SizedBox(height: AppSpacing.sm),
                            _DeviceStatRow(label: 'TEMP', percent: stats.tempCelsius!, maxVal: 100, suffix: '°C', scheme: scheme),
                          ],
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

  IconData _iconForType(String type) => switch (type) {
    'weighments' => Icons.scale_rounded,
    'audit' => Icons.security_rounded,
    'operator_updates' => Icons.person_rounded,
    'sessions' => Icons.devices_rounded,
    _ => Icons.data_object_rounded,
  };

  String _labelForType(String type) => switch (type) {
    'weighments' => 'Weighments',
    'audit' => 'Audit logs',
    'operator_updates' => 'Operator updates',
    'sessions' => 'Session records',
    _ => type,
  };
}

class _DeviceStatRow extends StatelessWidget {
  final String label;
  final double percent;
  final double maxVal;
  final String suffix;
  final ColorScheme scheme;

  const _DeviceStatRow({
    required this.label,
    required this.percent,
    this.maxVal = 100,
    this.suffix = '%',
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = (percent / maxVal).clamp(0.0, 1.0);
    final color = percent > 80 ? Colors.red : percent > 50 ? Colors.orange : Colors.green;
    final displayVal = suffix == '°C' ? '${percent.toStringAsFixed(0)}$suffix' : '${percent.toStringAsFixed(0)}$suffix';

    return Row(
      children: [
        SizedBox(
          width: 38,
          child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
        ),
        Expanded(
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(3.rs),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: ratio,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3.rs),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 32,
          child: Text(displayVal, textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
        ),
      ],
    );
  }
}
