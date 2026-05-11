import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/core/providers/providers.dart';

class MainLayout extends ConsumerStatefulWidget {
  final String activeNav;
  final Widget child;

  const MainLayout({
    super.key,
    required this.activeNav,
    required this.child,
  });

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<MainLayout> {
  final List<Map<String, dynamic>> sidebarItems = [
    {"icon": Icons.dashboard_outlined, "label": "Dashboard", "route": "/dashboard"},
    {"icon": Icons.scale_outlined, "label": "Weighments", "route": "/weighmentReports"},
    {"icon": Icons.people_outlined, "label": "Customers", "route": "/customers"},
    {"icon": Icons.description_outlined, "label": "Reports", "route": "/reports"},
    {"icon": Icons.manage_accounts_outlined, "label": "Operators", "route": "/operators"},
    {"icon": Icons.playlist_add_check_outlined, "label": "Audit Log", "route": "/auditLog"},
    {"icon": Icons.credit_card_outlined, "label": "Subscription & Billing", "route": "/subscriptionBilling"},
    {"icon": Icons.settings_outlined, "label": "Settings", "route": "/settings"},
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final operatorAsync = ref.watch(currentOperatorProvider);

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 224,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                right: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Column(
              children: [
                // Logo & Version
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.scale, color: colorScheme.onPrimary, size: 20),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Weighbridge MS",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      operatorAsync.when(
                        data: (op) => Text(
                          op?.role.name ?? "Operator",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "V3.2.1",
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),

                // Navigation
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: sidebarItems.map((item) {
                      final isActive = widget.activeNav == item["label"];

                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              if (item["route"] != null) {
                                Navigator.pushReplacementNamed(context, item["route"]);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    item["icon"],
                                    size: 20,
                                    color: isActive
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    item["label"],
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                                      color: isActive
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // User Profile at bottom
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                  ),
                  child: Column(
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            Navigator.pushReplacementNamed(context, '/accountSettings');
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: colorScheme.tertiaryContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: operatorAsync.when(
                                      data: (op) => Text(
                                        (op?.name ?? "U").substring(0, 1).toUpperCase(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: colorScheme.onTertiaryContainer,
                                        ),
                                      ),
                                      loading: () => const SizedBox.shrink(),
                                      error: (_, __) => const Text("?"),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      operatorAsync.when(
                                        data: (op) => Text(
                                          op?.name ?? "User",
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
                                        loading: () => const Text("...", style: TextStyle(fontSize: 13)),
                                        error: (_, __) => const Text("User", style: TextStyle(fontSize: 13)),
                                      ),
                                      Text(
                                        "My Account",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right, size: 18, color: colorScheme.onSurfaceVariant),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await ref.read(authServiceProvider).signOut();
                            if (context.mounted) {
                              Navigator.pushReplacementNamed(context, '/login');
                            }
                          },
                          icon: Icon(Icons.logout, size: 16, color: colorScheme.error),
                          label: Text("Logout", style: TextStyle(color: colorScheme.error)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
