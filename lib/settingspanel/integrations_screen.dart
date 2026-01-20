import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  final TextEditingController baseUrlController = TextEditingController(text: 'https://api.weighbridge.sys/v1/client_44928');
  final TextEditingController apiKeyController = TextEditingController(text: '••••••••••••••••');

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  @override
  void dispose() {
    baseUrlController.dispose();
    apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Settings",
      child: Row(
        children: [
          // Left Sidebar
          Container(
            width: 200,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F2937),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Text("A", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Admin Panel", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                          Text("WEIGHBRIDGE SYSTEM", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _sidebarItem(Icons.dashboard_outlined, "Dashboard", false),
                _sidebarItem(Icons.scale_outlined, "Weighbridge", false),
                _sidebarItem(Icons.bar_chart_outlined, "Reports", false),
                _sidebarItem(Icons.people_outline, "Users", false),
                _sidebarItem(Icons.settings_outlined, "Settings", true),
                const Spacer(),
                // Help & Support
                Container(
                  margin: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.help_outline, size: 16, color: Colors.grey.shade600),
                      ),
                      const SizedBox(width: 10),
                      Text("Help & Support", style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: Container(
              color: const Color(0xFFF9FAFB),
              child: Column(
                children: [
                  // Top Bar with Search
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    color: Colors.white,
                    child: Row(
                      children: [
                        const Text(
                          "Integrations & Cloud Sync",
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                        ),
                        const Spacer(),
                        Container(
                          width: 200,
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.search, size: 18, color: Colors.grey.shade400),
                              const SizedBox(width: 8),
                              Text("Search settings...", style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: emerald500,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(Icons.person, size: 20, color: Colors.white),
                        ),
                      ],
                    ),
                  ),

                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Breadcrumb
                          Row(
                            children: [
                              Text("Home", style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                              const SizedBox(width: 8),
                              Text("/", style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                              const SizedBox(width: 8),
                              Text("Settings", style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                              const SizedBox(width: 8),
                              Text("/", style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                              const SizedBox(width: 8),
                              Text("Integrations", style: TextStyle(fontSize: 13, color: emerald600, fontWeight: FontWeight.w500)),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // ERP Sync Pack Banner
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: emerald500,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text("PREMIUM", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("ERP Sync Pack", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Automate your billing by syncing weighbridge data directly with Tally, SAP, or Oracle. Eliminate manual entry errors.",
                                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                ElevatedButton.icon(
                                  onPressed: () {},
                                  icon: const Icon(Icons.diamond_outlined, size: 18),
                                  label: const Text("Upgrade Now"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: emerald500,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    elevation: 0,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 32),

                          // ERP / Billing Integration Section
                          Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: emerald500,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(Icons.grid_view_rounded, size: 14, color: Colors.white),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                "ERP / Billing Integration",
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Locked Integration Card
                          Container(
                            height: 300,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1F2937),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Stack(
                              children: [
                                // Background grid pattern (simulated with faded content)
                                Positioned.fill(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  _fadedLabel("ERP Provider"),
                                                  const SizedBox(height: 8),
                                                  _fadedField(),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  _fadedLabel("Sync Frequency"),
                                                  const SizedBox(height: 8),
                                                  _fadedField(),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  _fadedLabel("API Endpoint"),
                                                  const SizedBox(height: 8),
                                                  _fadedField(),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            const Expanded(child: SizedBox()),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        _fadedLabel("Auth Token"),
                                        const SizedBox(height: 8),
                                        _fadedField(),
                                      ],
                                    ),
                                  ),
                                ),
                                // Lock overlay
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 56,
                                        height: 56,
                                        decoration: BoxDecoration(
                                          color: emerald50,
                                          borderRadius: BorderRadius.circular(28),
                                        ),
                                        child: Icon(Icons.lock_outline, size: 28, color: emerald600),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        "Integration Locked",
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        "Upgrade to the ERP Sync Pack to configure direct\nconnections to Tally, SAP, and enable custom API webhooks.",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 13, color: Colors.grey.shade400, height: 1.5),
                                      ),
                                      const SizedBox(height: 20),
                                      ElevatedButton(
                                        onPressed: () {},
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF374151),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          elevation: 0,
                                        ),
                                        child: const Text("View Plans & Pricing"),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 32),

                          // API Access Section
                          Row(
                            children: [
                              Icon(Icons.code, size: 20, color: emerald600),
                              const SizedBox(width: 10),
                              const Text(
                                "API Access",
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Base URL
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text("Base URL", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF9FAFB),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: const Color(0xFFE5E7EB)),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    baseUrlController.text,
                                                    style: const TextStyle(fontSize: 13, color: Color(0xFF374151), fontFamily: 'monospace'),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                GestureDetector(
                                                  onTap: () {},
                                                  child: Container(
                                                    width: 28,
                                                    height: 28,
                                                    decoration: BoxDecoration(
                                                      color: emerald50,
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Icon(Icons.copy, size: 14, color: emerald600),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text("Rate limit: 1000 requests / minute", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    // API Key
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text("API Key", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF9FAFB),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: const Color(0xFFE5E7EB)),
                                            ),
                                            child: Row(
                                              children: [
                                                const Expanded(
                                                  child: Text(
                                                    "••••••••••••••••",
                                                    style: TextStyle(fontSize: 13, color: Color(0xFF374151)),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                GestureDetector(
                                                  onTap: () {},
                                                  child: Icon(Icons.refresh, size: 18, color: emerald600),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red.shade400),
                                              const SizedBox(width: 4),
                                              Text("Never share this key", style: TextStyle(fontSize: 11, color: Colors.red.shade400)),
                                            ],
                                          ),
                                        ],
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String label, bool isActive) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {},
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isActive ? emerald50 : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isActive ? Border.all(color: emerald500) : null,
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: isActive ? emerald600 : Colors.grey.shade600),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isActive ? emerald600 : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fadedLabel(String text) {
    return Text(
      text,
      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
    );
  }

  Widget _fadedField() {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: Colors.grey.shade800.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
