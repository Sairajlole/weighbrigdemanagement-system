import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class TimeAnalysisReportsScreen extends StatefulWidget {
  const TimeAnalysisReportsScreen({super.key});

  @override
  State<TimeAnalysisReportsScreen> createState() => _TimeAnalysisReportsScreenState();
}

class _TimeAnalysisReportsScreenState extends State<TimeAnalysisReportsScreen> {
  String selectedPeriod = 'Last 7 Days';

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  // Hourly traffic data (06:00 - 17:00)
  final List<Map<String, dynamic>> hourlyData = [
    {'hour': '06:00', 'value': 15, 'highlight': false},
    {'hour': '09:00', 'value': 22, 'highlight': false},
    {'hour': '10:00', 'value': 35, 'highlight': false},
    {'hour': '11:00', 'value': 42, 'highlight': false},
    {'hour': '12:00', 'value': 38, 'highlight': false},
    {'hour': '13:00', 'value': 55, 'highlight': false},
    {'hour': '14:00', 'value': 72, 'highlight': true},
    {'hour': '15:00', 'value': 48, 'highlight': false},
    {'hour': '16:00', 'value': 32, 'highlight': false},
    {'hour': '17:00', 'value': 20, 'highlight': false},
  ];

  // Daily distribution data
  final List<Map<String, dynamic>> dailyData = [
    {'day': 'Mon', 'value': 45},
    {'day': 'Tue', 'value': 62},
    {'day': 'Wed', 'value': 58},
    {'day': 'Thu', 'value': 70},
    {'day': 'Fri', 'value': 55},
    {'day': 'Sat', 'value': 35},
    {'day': 'Sun', 'value': 25},
  ];

  // Processing duration frequency
  final List<Map<String, dynamic>> durationData = [
    {'range': '0-5m', 'value': 18, 'highlight': false},
    {'range': '5-10m', 'value': 32, 'highlight': false},
    {'range': '10-15m', 'value': 45, 'highlight': true},
    {'range': '15-20m', 'value': 28, 'highlight': false},
    {'range': '20-30m', 'value': 15, 'highlight': false},
    {'range': '>30m', 'value': 8, 'highlight': false},
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
                    onTap: () => Navigator.pushNamed(context, '/dashboard'),
                    child: Text("Home", style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                  ),
                  Text("  /  ", style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text("Reports", style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                  ),
                  Text("  /  ", style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                  Text("Operation Timing Analysis", style: TextStyle(fontSize: 13, color: emerald600, fontWeight: FontWeight.w500)),
                ],
              ),

              const SizedBox(height: 20),

              // Header Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Operation Timing Analysis",
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Analyze operational efficiency, identify bottlenecks, and optimize traffic patterns over time.",
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  // Period Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 8),
                        Text(selectedPeriod, style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
                        const SizedBox(width: 8),
                        Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey.shade500),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text("Export Report"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: emerald500,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Stat Cards Row
              Row(
                children: [
                  Expanded(child: _buildStatCard("Busiest Hour", "14:00 - 15:00", "+15%", true, "Compared to last week average", Icons.access_time, emerald50, emerald600)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCardSimple("Slowest Day", "Sunday", "Avg. 12 trucks per day", Icons.calendar_today_outlined, const Color(0xFFF3F4F6), Colors.grey.shade700)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard("Avg Processing Time", "12m 30s", "+2.5%", false, "Target: < 10m 00s", Icons.timer_outlined, emerald50, emerald600)),
                ],
              ),

              const SizedBox(height: 24),

              // Main Content Row - Hourly Chart + Insights
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hourly Traffic Distribution
                  Expanded(
                    flex: 2,
                    child: Container(
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
                                  const Text("Hourly Traffic Distribution", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                                  const SizedBox(height: 2),
                                  Text("Average vehicles per hour over selected period", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                ],
                              ),
                              const Spacer(),
                              Icon(Icons.more_horiz, size: 20, color: Colors.grey.shade400),
                            ],
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 200,
                            child: _buildHourlyChart(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Insights & Actions
                  Expanded(
                    child: Container(
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
                              Icon(Icons.lightbulb_outline, size: 20, color: Colors.amber.shade600),
                              const SizedBox(width: 8),
                              const Text("Insights & Actions", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                            ],
                          ),
                          const SizedBox(height: 20),
                          // Staffing Shortage Alert
                          _buildInsightItem(
                            Icons.warning_amber_rounded,
                            Colors.amber.shade600,
                            "Staffing Shortage Alert",
                            "High volume detected between 14:00 - 15:00. Consider adding 1 extra weighbridge operator during this shift.",
                          ),
                          const SizedBox(height: 16),
                          // Efficiency Opportunity
                          _buildInsightItem(
                            Icons.trending_up,
                            emerald600,
                            "Efficiency Opportunity",
                            "Traffic volume on Sundays is consistently low (< 15 trucks). Consider reducing gate hours to 08:00 - 12:00.",
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () {},
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey.shade700,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: const BorderSide(color: Color(0xFFE5E7EB)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text("Generate Staffing Schedule"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Bottom Charts Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Daily Distribution
                  Expanded(
                    child: Container(
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
                              const Text("Daily Distribution", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                              const Spacer(),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: emerald500,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text("Vehicles", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ],
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 160,
                            child: _buildDailyChart(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Processing Duration Frequency
                  Expanded(
                    child: Container(
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
                              const Text("Processing Duration Frequency", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                              const Spacer(),
                              Text("View Details", style: TextStyle(fontSize: 12, color: emerald600, fontWeight: FontWeight.w500)),
                            ],
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 160,
                            child: _buildDurationChart(),
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

  Widget _buildStatCard(String label, String value, String change, bool isPositive, String subtext, IconData icon, Color bgColor, Color iconColor) {
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
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const Spacer(),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isPositive ? emerald50 : const Color(0xFFFFE4E6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(
                      isPositive ? Icons.trending_up : Icons.trending_down,
                      size: 12,
                      color: isPositive ? emerald600 : Colors.red.shade500,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      change,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: isPositive ? emerald600 : Colors.red.shade500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtext, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildStatCardSimple(String label, String value, String subtext, IconData icon, Color bgColor, Color iconColor) {
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
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const Spacer(),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
          const SizedBox(height: 6),
          Text(subtext, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildInsightItem(IconData icon, Color iconColor, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(
            color: iconColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHourlyChart() {
    final maxValue = 72.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: hourlyData.map((data) {
        final height = (data['value'] / maxValue) * 180;
        final isHighlight = data['highlight'] as bool;
        return Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: height,
                decoration: BoxDecoration(
                  color: isHighlight ? emerald500 : const Color(0xFFD1FAE5),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ),
              const SizedBox(height: 8),
              Text(data['hour'], style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDailyChart() {
    final maxValue = 70.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: dailyData.map((data) {
        final height = (data['value'] / maxValue) * 130;
        return Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                height: height,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1FAE5),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ),
              const SizedBox(height: 8),
              Text(data['day'], style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDurationChart() {
    final maxValue = 45.0;
    final colors = [
      const Color(0xFFD1FAE5),
      const Color(0xFFD1FAE5),
      emerald500, // Highlighted
      const Color(0xFFFED7AA),
      const Color(0xFFFED7AA),
      Colors.red.shade300,
    ];
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: durationData.asMap().entries.map((entry) {
        final index = entry.key;
        final data = entry.value;
        final height = (data['value'] / maxValue) * 130;
        return Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: height,
                decoration: BoxDecoration(
                  color: colors[index],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ),
              const SizedBox(height: 8),
              Text(data['range'], style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
            ],
          ),
        );
      }).toList(),
    );
  }
}
