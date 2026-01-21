import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class OperatorReportsScreen extends StatefulWidget {
  const OperatorReportsScreen({super.key});

  @override
  State<OperatorReportsScreen> createState() => _OperatorReportsScreenState();
}

class _OperatorReportsScreenState extends State<OperatorReportsScreen> {
  String selectedDateRange = 'Last 7 Days';
  String selectedOperator = 'All Operators';
  String selectedShift = 'All Shifts';

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  final List<Map<String, dynamic>> operatorData = [
    {'name': 'Sarah Jenkins', 'initials': 'SJ', 'id': 'ID: #OP-4421', 'shift': 'Morning A', 'shiftColor': emerald500, 'weighments': 145, 'avgTime': '3m 42s', 'efficiency': 92},
    {'name': 'Mike Ross', 'initials': 'MR', 'id': 'ID: #OP-8823', 'shift': 'Afternoon', 'shiftColor': const Color(0xFFFBBF24), 'weighments': 132, 'avgTime': '4m 15s', 'efficiency': 85},
    {'name': 'David Chen', 'initials': 'DC', 'id': 'ID: #OP-1102', 'shift': 'Night', 'shiftColor': const Color(0xFF6366F1), 'weighments': 98, 'avgTime': '5m 02s', 'efficiency': 72},
    {'name': 'Elena Rodriguez', 'initials': 'ER', 'id': 'ID: #OP-5592', 'shift': 'Morning B', 'shiftColor': emerald500, 'weighments': 137, 'avgTime': '4m 05s', 'efficiency': 88},
  ];

  // Heatmap data (hours x days)
  final List<List<double>> heatmapData = [
    [0.2, 0.3, 0.4, 0.5, 0.6, 0.8, 0.9, 0.7],  // 06:00
    [0.3, 0.5, 0.6, 0.7, 0.8, 0.9, 0.8, 0.6],  // 09:00
    [0.4, 0.6, 0.7, 0.8, 0.9, 1.0, 0.9, 0.7],  // 12:00
    [0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.7, 0.5],  // 15:00
    [0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.6, 0.4],  // 18:00
    [0.1, 0.2, 0.3, 0.4, 0.5, 0.5, 0.4, 0.3],  // 21:00
  ];

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Reports",
      child: Container(
        color: const Color(0xFFF9FAFB),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Breadcrumb
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text("Reports", style: TextStyle(fontSize: 13, color: emerald600)),
                  ),
                  Text("  /  ", style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                  Text("Operator Performance", style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                ],
              ),

              const SizedBox(height: 20),

              // Header Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Operator Performance Metrics",
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Track weighbridge operator efficiency, throughput, and accuracy",
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  // Action Buttons
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: Icon(Icons.download_outlined, size: 16, color: Colors.grey.shade700),
                    label: const Text("Export"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text("Refresh Data"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: emerald500,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Filter Row
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    // Date Range
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Date Range", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey.shade500),
                                const SizedBox(width: 8),
                                Text(selectedDateRange, style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
                                const Spacer(),
                                Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey.shade500),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Operator
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Operator", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.person_outline, size: 16, color: Colors.grey.shade500),
                                const SizedBox(width: 8),
                                Text(selectedOperator, style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
                                const Spacer(),
                                Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey.shade500),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Shift
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Shift", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.access_time, size: 16, color: Colors.grey.shade500),
                                const SizedBox(width: 8),
                                Text(selectedShift, style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
                                const Spacer(),
                                Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey.shade500),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Apply Button
                    Padding(
                      padding: const EdgeInsets.only(top: 22),
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF374151),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        child: const Text("Apply"),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Stats Cards Row
              Row(
                children: [
                  Expanded(child: _buildStatCard("Active Operators", "4", "On shift now", Icons.people_outline, emerald50, emerald500, true)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCardWithTrend("Total Weighments", "512", "+12% vs last week", Icons.scale_outlined, emerald50, emerald500)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard("Avg per Operator", "128", "Daily average", Icons.bar_chart, emerald50, emerald500, false)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCardWithStar("Fastest Avg Time", "3m 42s", "Top performer: S. Jenkins", Icons.timer_outlined, emerald50, emerald500)),
                ],
              ),

              const SizedBox(height: 24),

              // Main Content Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hourly Activity Heatmap
                  Expanded(
                    child: Container(
                      height: 400,
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
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Hourly Activity", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                                  const SizedBox(height: 4),
                                  Text("Heatmap of weighments by hour", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                ],
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: emerald50,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text("Peak: 10:00 AM", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: emerald600)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          // Heatmap Grid
                          Expanded(child: _buildHeatmap()),
                          const SizedBox(height: 16),
                          // Legend
                          Row(
                            children: [
                              Text("Low Activity", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                              const SizedBox(width: 8),
                              Container(
                                width: 100,
                                height: 8,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  gradient: LinearGradient(
                                    colors: [
                                      emerald50,
                                      emerald500.withOpacity(0.5),
                                      emerald500,
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text("High Activity", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Operator Performance Table
                  Expanded(
                    flex: 2,
                    child: Container(
                      height: 400,
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
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Operator Performance", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                                  const SizedBox(height: 4),
                                  Text("Detailed metrics per operator for selected range", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                ],
                              ),
                              const Spacer(),
                              // Search
                              Container(
                                width: 180,
                                height: 36,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF9FAFB),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFE5E7EB)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.search, size: 16, color: Colors.grey.shade400),
                                    const SizedBox(width: 8),
                                    Text("Search operator...", style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Table Header
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
                            ),
                            child: Row(
                              children: [
                                Expanded(flex: 3, child: Text("OPERATOR", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                                Expanded(flex: 2, child: Text("SHIFT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                                Expanded(flex: 2, child: Text("WEIGHMENTS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                                Expanded(flex: 2, child: Text("AVG TIME", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                                Expanded(flex: 3, child: Text("EFFICIENCY SCORE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                                const SizedBox(width: 40, child: Text("ACTION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey, letterSpacing: 0.5))),
                              ],
                            ),
                          ),
                          // Table Rows
                          Expanded(
                            child: ListView.builder(
                              itemCount: operatorData.length,
                              itemBuilder: (context, index) => _buildOperatorRow(operatorData[index]),
                            ),
                          ),
                          // Pagination
                          Container(
                            padding: const EdgeInsets.only(top: 12),
                            decoration: const BoxDecoration(
                              border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                            ),
                            child: Row(
                              children: [
                                Text("Showing 1-4 of 12 operators", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFE5E7EB)),
                                  ),
                                  child: Icon(Icons.chevron_left, size: 16, color: Colors.grey.shade400),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFE5E7EB)),
                                  ),
                                  child: Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade600),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, String subtext, IconData icon, Color bgColor, Color iconColor, bool showIndicator) {
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const Spacer(),
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 16),
          Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
          const SizedBox(height: 4),
          Row(
            children: [
              if (showIndicator) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: emerald500,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(subtext, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCardWithTrend(String label, String value, String trend, IconData icon, Color bgColor, Color iconColor) {
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const Spacer(),
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 16),
          Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.trending_up, size: 14, color: emerald600),
              const SizedBox(width: 4),
              Text(trend, style: TextStyle(fontSize: 12, color: emerald600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCardWithStar(String label, String value, String subtext, IconData icon, Color bgColor, Color iconColor) {
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const Spacer(),
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 16),
          Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.star, size: 14, color: Colors.amber.shade500),
              const SizedBox(width: 4),
              Text(subtext, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeatmap() {
    final hours = ['06:00', '09:00', '12:00', '15:00', '18:00', '21:00'];
    
    return Column(
      children: List.generate(heatmapData.length, (rowIndex) {
        return Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(hours[rowIndex], style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              ),
              ...List.generate(heatmapData[rowIndex].length, (colIndex) {
                final intensity = heatmapData[rowIndex][colIndex];
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: emerald500.withOpacity(intensity * 0.8 + 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildOperatorRow(Map<String, dynamic> operator) {
    final efficiency = operator['efficiency'] as int;
    final efficiencyColor = efficiency >= 85 ? emerald500 : (efficiency >= 70 ? Colors.amber.shade500 : Colors.red.shade400);
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          // Operator Info
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: emerald50,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Text(
                      operator['initials'],
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: emerald600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(operator['name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
                    Text(operator['id'], style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ],
            ),
          ),
          // Shift
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (operator['shiftColor'] as Color).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                operator['shift'],
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: operator['shiftColor']),
              ),
            ),
          ),
          // Weighments
          Expanded(
            flex: 2,
            child: Text(operator['weighments'].toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
          ),
          // Avg Time
          Expanded(
            flex: 2,
            child: Text(operator['avgTime'], style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          ),
          // Efficiency Score
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: efficiency / 100,
                      child: Container(
                        decoration: BoxDecoration(
                          color: efficiencyColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text("$efficiency%", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: efficiencyColor)),
              ],
            ),
          ),
          // Action
          SizedBox(
            width: 40,
            child: Icon(Icons.more_vert, size: 18, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}
