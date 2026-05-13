import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/auth_provider.dart';

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String path;

  const _NavItem({required this.icon, required this.selectedIcon, required this.label, required this.path});
}

const _navItems = [
  _NavItem(icon: Icons.space_dashboard_outlined, selectedIcon: Icons.space_dashboard_rounded, label: 'Dashboard', path: '/dashboard'),
  _NavItem(icon: Icons.scale_outlined, selectedIcon: Icons.scale_rounded, label: 'Weighment', path: '/weighment'),
  _NavItem(icon: Icons.people_outline_rounded, selectedIcon: Icons.people_rounded, label: 'Customers', path: '/customers'),
  _NavItem(icon: Icons.badge_outlined, selectedIcon: Icons.badge_rounded, label: 'Operators', path: '/operators'),
  _NavItem(icon: Icons.assessment_outlined, selectedIcon: Icons.assessment_rounded, label: 'Reports', path: '/reports'),
  _NavItem(icon: Icons.settings_outlined, selectedIcon: Icons.settings_rounded, label: 'Settings', path: '/settings'),
];

class AppShell extends ConsumerWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final idx = _navItems.indexWhere((item) => location.startsWith(item.path));
    return idx == -1 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final selectedIndex = _currentIndex(context);

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
                    children: _navItems.asMap().entries.map((entry) {
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
          Expanded(child: child),
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
