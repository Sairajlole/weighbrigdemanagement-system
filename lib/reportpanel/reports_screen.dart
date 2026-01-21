import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String selectedTimeRange = 'Today';

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  final List<Map<String, dynamic>> reportCategories = [
    {'icon': Icons.scale_outlined, 'title': 'Weighment Reports', 'description': 'Daily logs, ticket summaries, and transaction details.', 'color': const Color(0xFF10B981)},
    {'icon': Icons.people_outlined, 'title': 'Customer Reports', 'description': 'Client activity, top customers, and credit limits.', 'color': const Color(0xFF10B981)},
    {'icon': Icons.local_shipping_outlined, 'title': 'Vehicle Reports', 'description': 'Truck utilization, tare weights, and turn-around time.', 'color': const Color(0xFF10B981)},
    {'icon': Icons.inventory_2_outlined, 'title': 'Material Reports', 'description': 'Inventory flow, material totals, and stock adjustments.', 'color': const Color(0xFF10B981)},
    {'icon': Icons.badge_outlined, 'title': 'Operator Reports', 'description': 'Shift performance, manual entries, and audit logs.', 'color': const Color(0xFF10B981)},
    {'icon': Icons.attach_money, 'title': 'Financial Reports', 'description': 'Invoicing, cash collection, and revenue analysis.', 'color': const Color(0xFF10B981)},
    {'icon': Icons.access_time, 'title': 'Time Analysis', 'description': 'Peak hours, operational delays, and time efficiency.', 'color': const Color(0xFF10B981)},
    {'icon': Icons.compare_arrows, 'title': 'Comparison', 'description': 'Year-over-year, month-over-month, and site benchmarks.', 'color': const Color(0xFF10B981)},
    {'icon': Icons.dashboard_customize_outlined, 'title': 'Custom Builder', 'description': 'Create your own report with specific parameters.', 'color': const Color(0xFF10B981)},
  ];

  final List<Map<String, dynamic>> recentReports = [
    {'name': 'Daily Weigh-in Log', 'type': 'PDF', 'generatedBy': 'Admin User', 'date': 'Oct 24, 10:30 AM'},
  ];

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Reports",
      child: Container(
        color: const Color(0xFFF9FAFB),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Reports",
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Analytics and insights for your operations",
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text("Generate New Report"),
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

              const SizedBox(height: 24),

              // Time Range Filters
              Row(
                children: [
                  _buildTimeRangeButton('Today', Icons.calendar_today_outlined),
                  const SizedBox(width: 8),
                  _buildTimeRangeButton('Last 7 Days', null),
                  const SizedBox(width: 8),
                  _buildTimeRangeButton('This Month', null),
                  const SizedBox(width: 8),
                  _buildTimeRangeButton('Last Month', null),
                  const SizedBox(width: 8),
                  _buildTimeRangeButton('Custom Range', Icons.date_range_outlined),
                ],
              ),

              const SizedBox(height: 24),

              // Stats Cards
              Row(
                children: [
                  Expanded(child: _buildStatCard(Icons.scale_outlined, "Today's Weighments", "124", "+12%", true, "vs 111 yesterday")),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard(Icons.inventory_2_outlined, "Total Weight", "4,500 Tons", "+5%", true, "vs 4,280 yesterday")),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard(Icons.people_outlined, "Active Customers", "85", "— 0%", false, "Stable vs yesterday")),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard(Icons.attach_money, "Revenue", "\$12,450", "+8%", true, "vs \$11,500 yesterday")),
                ],
              ),

              const SizedBox(height: 32),

              // Report Categories
              Row(
                children: [
                  const Text(
                    "Report Categories",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {},
                    child: Text("View All", style: TextStyle(fontSize: 13, color: emerald600)),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Categories Grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 2.5,
                ),
                itemCount: reportCategories.length,
                itemBuilder: (context, index) {
                  final category = reportCategories[index];
                  return _buildCategoryCard(category);
                },
              ),

              const SizedBox(height: 32),

              // Recent Reports and Scheduled
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Recent Reports
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              "Recent Reports",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () {},
                              child: Text("View History", style: TextStyle(fontSize: 13, color: emerald600)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Column(
                            children: [
                              // Header
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF9FAFB),
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(flex: 3, child: Text("REPORT NAME", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                                    Expanded(flex: 1, child: Text("TYPE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                                    Expanded(flex: 2, child: Text("GENERATED BY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                                    Expanded(flex: 2, child: Text("DATE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                                    const Expanded(flex: 1, child: Text("ACTION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey, letterSpacing: 0.5))),
                                  ],
                                ),
                              ),
                              // Row
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF3B82F6),
                                              borderRadius: BorderRadius.circular(2),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          const Text("Daily Weigh-in Log", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEF4444).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text("PDF", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFEF4444))),
                                      ),
                                    ),
                                    const Expanded(flex: 2, child: Text("Admin User", style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)))),
                                    const Expanded(flex: 2, child: Text("Oct 24, 10:30 AM", style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)))),
                                    Expanded(
                                      flex: 1,
                                      child: Icon(Icons.download_outlined, size: 18, color: Colors.grey.shade500),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Scheduled
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              "Scheduled",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () {},
                              child: Icon(Icons.add, size: 20, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Row(
                            children: [
                              // Calendar Date
                              Container(
                                width: 48,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF9FAFB),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFE5E7EB)),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text("OCT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
                                    const Text("25", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF374151))),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("Weekly Executive Summary", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                                    const SizedBox(height: 4),
                                    Text("Recipients: Management Team", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                  ],
                                ),
                              ),
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: emerald500,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.check, size: 14, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeRangeButton(String label, IconData? icon) {
    final isSelected = selectedTimeRange == label;
    return GestureDetector(
      onTap: () => setState(() => selectedTimeRange = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? emerald500 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? emerald500 : const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey.shade600),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String label, String value, String change, bool isPositive, String comparison) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: emerald50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: emerald600),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isPositive ? emerald50 : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isPositive)
                      Icon(Icons.trending_up, size: 14, color: emerald600),
                    const SizedBox(width: 4),
                    Text(
                      change,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isPositive ? emerald600 : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
          const SizedBox(height: 4),
          Text(comparison, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(Map<String, dynamic> category) {
    return GestureDetector(
      onTap: () {
        if (category['title'] == 'Weighment Reports') {
          Navigator.pushNamed(context, '/weighmentReports');
        } else if (category['title'] == 'Customer Reports') {
          Navigator.pushNamed(context, '/customerReports');
        } else if (category['title'] == 'Vehicle Reports') {
          Navigator.pushNamed(context, '/vehicleReports');
        } else if (category['title'] == 'Material Reports') {
          Navigator.pushNamed(context, '/materialReports');
        } else if (category['title'] == 'Operator Reports') {
          Navigator.pushNamed(context, '/operatorReports');
        } else if (category['title'] == 'Comparison') {
          Navigator.pushNamed(context, '/comparisonReports');
        } else if (category['title'] == 'Custom Builder') {
          Navigator.pushNamed(context, '/customReports');
        } else if (category['title'] == 'Time Analysis') {
          Navigator.pushNamed(context, '/timeAnalysisReports');
        } else if (category['title'] == 'Financial Reports') {
          Navigator.pushNamed(context, '/financialReports');
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: emerald50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(category['icon'], size: 20, color: emerald600),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(category['title'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                  const SizedBox(height: 4),
                  Text(
                    category['description'],
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
