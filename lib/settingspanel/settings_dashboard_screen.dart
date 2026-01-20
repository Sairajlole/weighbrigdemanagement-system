import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class SettingsDashboardScreen extends StatefulWidget {
  const SettingsDashboardScreen({super.key});

  @override
  State<SettingsDashboardScreen> createState() => _SettingsDashboardScreenState();
}

class _SettingsDashboardScreenState extends State<SettingsDashboardScreen> {
  // Settings cards
  final List<Map<String, dynamic>> settingsCards = [
    {
      "icon": Icons.language_outlined,
      "title": "General",
      "description": "System language, timezone, and facility basic information.",
      "route": "/generalSettings",
    },
    {
      "icon": Icons.playlist_add_outlined,
      "title": "Custom Fields",
      "description": "Manage extra data points for tickets and vehicle registrations.",
      "route": "/customFields",
    },
    {
      "icon": Icons.inventory_2_outlined,
      "title": "Materials",
      "description": "Define commodity types, pricing tiers, and weight categories.",
      "route": "/materials",
    },
    {
      "icon": Icons.door_sliding_outlined,
      "title": "Gate Control",
      "description": "Configure barrier automation, RFID readers, and sensors.",
      "route": "/gateControl",
    },
    {
      "icon": Icons.scale_outlined,
      "title": "Weighbridge",
      "description": "Hardware protocols, COM port settings, and scale calibration.",
      "route": "/weighbridge",
    },
    {
      "icon": Icons.videocam_outlined,
      "title": "Cameras & AI",
      "description": "ANPR configuration, snapshot triggers, and AI vehicle detection.",
      "route": "/camerasAi",
    },
    {
      "icon": Icons.notifications_active_outlined,
      "title": "Notifications",
      "description": "SMS, Email, and Push alerts for weight violations or departures.",
      "route": "/notifications",
    },
    {
      "icon": Icons.print_outlined,
      "title": "Printing",
      "description": "Ticket templates, thermal printer drivers, and auto-print rules.",
      "route": "/printing",
    },
    {
      "icon": Icons.storage_outlined,
      "title": "Data & Backup",
      "description": "Scheduled backups, database cleanup, and CSV/Excel exports.",
      "route": "/dataBackup",
    },
    {
      "icon": Icons.shield_outlined,
      "title": "Security",
      "description": "Role-based access control, password policies, and audit logs.",
      "route": "/security",
    },
    {
      "icon": Icons.link_outlined,
      "title": "Integrations",
      "description": "Connect with ERP systems (SAP, Oracle) and Cloud API sync.",
      "route": "/integrations",
    },
    {
      "icon": Icons.palette_outlined,
      "title": "Appearance",
      "description": "Theme selection, company branding logo, and display preferences.",
      "route": null,
    },
    {
      "icon": Icons.monitor_heart_outlined,
      "title": "System Health",
      "description": "Monitor hardware connectivity, storage usage, and system uptime.",
      "route": null,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Settings",
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF9FAFB),
              Color(0xFFF0FDF9),
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Breadcrumb
              Row(
                children: [
                  Text(
                    "Home",
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                  ),
                  const SizedBox(width: 8),
                  Text("/", style: TextStyle(color: Colors.grey.shade500)),
                  const SizedBox(width: 8),
                  const Text(
                    "Settings",
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF374151),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Title
              const Text(
                "Settings Dashboard",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),

              const SizedBox(height: 4),

              Text(
                "Configure system preferences, hardware integrations, and security protocols for your weighbridge facility.",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                ),
              ),

              const SizedBox(height: 24),

              // Search Bar
              Container(
                constraints: const BoxConstraints(maxWidth: 672),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: "Search for specific settings (e.g., weighbridge, AI, printing...)",
                      hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 16, right: 12),
                        child: Icon(Icons.search, size: 20, color: Colors.grey.shade400),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Settings Grid
              LayoutBuilder(
                builder: (context, constraints) {
                  int crossAxisCount = 3;
                  if (constraints.maxWidth < 900) {
                    crossAxisCount = 2;
                  }
                  if (constraints.maxWidth < 600) {
                    crossAxisCount = 1;
                  }

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 2.4,
                    ),
                    itemCount: settingsCards.length,
                    itemBuilder: (context, index) {
                      final card = settingsCards[index];
                      return _SettingsCard(
                        icon: card["icon"],
                        title: card["title"],
                        description: card["description"],
                        onTap: () {
                          if (card["route"] != null) {
                            Navigator.pushNamed(context, card["route"]);
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.description,
    this.onTap,
  });

  @override
  State<_SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<_SettingsCard> {
  bool isHovered = false;

  static const Color emerald100 = Color(0xFFD1FAE5);
  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald300 = Color(0xFF6EE7B7);
  static const Color emerald500 = Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => isHovered = true),
        onExit: (_) => setState(() => isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHovered ? emerald300 : const Color(0xFFE5E7EB),
            ),
            boxShadow: isHovered
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: emerald100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(widget.icon, color: emerald600, size: 20),
              ),
              const SizedBox(width: 16),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                        height: 1.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Arrow
              Icon(
                Icons.chevron_right,
                size: 20,
                color: isHovered ? emerald500 : Colors.grey.shade300,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
