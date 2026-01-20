import 'package:flutter/material.dart';

class MainLayout extends StatefulWidget {
  final String activeNav;
  final Widget child;

  const MainLayout({
    super.key,
    required this.activeNav,
    required this.child,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald700 = Color(0xFF047857);
  static const Color emerald50 = Color(0xFFECFDF5);

  final List<Map<String, dynamic>> sidebarItems = [
    {"icon": Icons.dashboard_outlined, "label": "Dashboard", "route": "/dashboard"},
    {"icon": Icons.scale_outlined, "label": "Weighments", "route": "/weighments"},
    {"icon": Icons.people_outlined, "label": "Customers", "route": "/customers"},
    {"icon": Icons.description_outlined, "label": "Reports", "route": "/reports"},
    {"icon": Icons.manage_accounts_outlined, "label": "Operators", "route": "/operators"},
    {"icon": Icons.playlist_add_check_outlined, "label": "Audit Log", "route": "/auditLog"},
    {"icon": Icons.credit_card_outlined, "label": "Subscription & Billing", "route": "/subscriptionBilling"},
    {"icon": Icons.settings_outlined, "label": "Settings", "route": "/settings"},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Row(
        children: [
          // ==================== SIDEBAR ====================
          Container(
            width: 224,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                right: BorderSide(color: Color(0xFFE5E7EB)),
              ),
            ),
            child: Column(
              children: [
                // Logo & Version
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFF3F4F6)),
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
                              color: emerald600,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.scale, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            "Weighbridge MS",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "System Admin",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "V3.2.1-Standard",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
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
                              padding: EdgeInsets.only(
                                left: isActive ? 8 : 12,
                                right: 12,
                                top: 10,
                                bottom: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isActive ? emerald50 : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: isActive
                                    ? const Border(
                                        left: BorderSide(color: emerald600, width: 4),
                                      )
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    item["icon"],
                                    size: 20,
                                    color: isActive ? emerald700 : const Color(0xFF4B5563),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    item["label"],
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: isActive ? emerald700 : const Color(0xFF4B5563),
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
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Color(0xFFF3F4F6)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFEF3C7),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text(
                            "SA",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "System Admin",
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            Text(
                              "Logout",
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.logout, size: 18, color: Colors.grey.shade500),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ==================== MAIN CONTENT ====================
          Expanded(
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
