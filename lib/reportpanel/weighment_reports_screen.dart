import 'package:flutter/material.dart';
import 'dart:math' as math;

class WeighmentReportsScreen extends StatefulWidget {
  const WeighmentReportsScreen({super.key});

  @override
  State<WeighmentReportsScreen> createState() => _WeighmentReportsScreenState();
}

class _WeighmentReportsScreenState extends State<WeighmentReportsScreen> {
  String selectedTab = 'Overview';
  String selectedDateRange = 'Last 30 Days';

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  final List<Map<String, dynamic>> tableData = [
    {'ticketId': '#WB-2023-001', 'dateTime': 'Oct 24, 10:42 AM', 'vehicleNo': 'KA-01-AB-1234', 'material': 'Coal', 'netWeight': '24.5 T'},
    {'ticketId': '#WB-2023-002', 'dateTime': 'Oct 24, 11:15 AM', 'vehicleNo': 'MH-12-CD-5678', 'material': 'Sand', 'netWeight': '18.2 T'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          // Top Navigation Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Row(
              children: [
                // Logo
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: emerald500,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.scale, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 8),
                const Text("WeighSys", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                const SizedBox(width: 32),
                // Nav Items
                _navItem("Dashboard", false),
                _navItem("Reports", true),
                _navItem("Weighments", false),
                _navItem("Settings", false),
                const Spacer(),
                // Search
                Container(
                  width: 200,
                  height: 36,
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
                      Text("Search report...", style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
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
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Text("Reports", style: TextStyle(fontSize: 13, color: emerald600)),
                      ),
                      const SizedBox(width: 8),
                      Text("/", style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                      const SizedBox(width: 8),
                      Text("Weighment Reports", style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Title
                  const Text(
                    "Detailed Weighment Reports",
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Analyze weighbridge performance, track material flow trends, and export compliance data.",
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                  ),

                  const SizedBox(height: 24),

                  // Filters Row
                  Row(
                    children: [
                      // Date Range Dropdown
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("DATE RANGE", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(selectedDateRange, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
                                    const SizedBox(width: 4),
                                    Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey.shade500),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // More Filters
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.tune, size: 16, color: Colors.grey.shade600),
                            const SizedBox(width: 6),
                            Text("More Filters", style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Material Chip
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.add, size: 16, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text("Material", style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Customer Chip
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.add, size: 16, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text("Customer", style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Reset
                      Row(
                        children: [
                          Icon(Icons.refresh, size: 16, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text("Reset", style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Stats Cards
                  Row(
                    children: [
                      Expanded(child: _buildStatCard("Total Weighments", "312", "+12%", true, Icons.scale_outlined)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildStatCard("Total Net Weight", "4,567 T", null, false, Icons.inventory_2_outlined)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildStatCard("Avg Net Weight", "14.6 T", "+2%", true, Icons.analytics_outlined)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildStatCard("Avg Processing Time", "4m 12s", null, false, Icons.timer_outlined)),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Tabs
                  Row(
                    children: [
                      _buildTab("Overview"),
                      const SizedBox(width: 24),
                      _buildTab("Trends"),
                      const SizedBox(width: 24),
                      _buildTab("Distribution"),
                      const SizedBox(width: 24),
                      _buildTab("Details Table"),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Charts Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Line Chart
                      Expanded(
                        flex: 2,
                        child: Container(
                          height: 280,
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
                                  const Text("Weighments Over Time", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                                  const Spacer(),
                                  Icon(Icons.bar_chart, size: 18, color: Colors.grey.shade400),
                                  const SizedBox(width: 8),
                                  Icon(Icons.show_chart, size: 18, color: emerald500),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Expanded(child: _buildLineChart()),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Pie Chart
                      Expanded(
                        child: Container(
                          height: 280,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Weight Volume", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                              const SizedBox(height: 20),
                              Expanded(
                                child: Row(
                                  children: [
                                    // Donut Chart
                                    Expanded(
                                      child: Center(
                                        child: SizedBox(
                                          width: 120,
                                          height: 120,
                                          child: CustomPaint(
                                            painter: DonutChartPainter(),
                                            child: Center(
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Text("4.5k", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: emerald600)),
                                                  Text("TONNES", style: TextStyle(fontSize: 9, color: Colors.grey.shade500, letterSpacing: 0.5)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Legend
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildLegendItem(emerald500, "Coal", "45%"),
                                        const SizedBox(height: 12),
                                        _buildLegendItem(const Color(0xFF6EE7B7), "Iron Ore", "30%"),
                                        const SizedBox(height: 12),
                                        _buildLegendItem(const Color(0xFFD1FAE5), "Limestone", "25%"),
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

                  const SizedBox(height: 24),

                  // Export Row
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: emerald500),
                      const SizedBox(width: 6),
                      Text("Data updated: Just now", style: TextStyle(fontSize: 12, color: emerald600)),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: () {},
                        icon: Icon(Icons.picture_as_pdf, size: 16, color: Colors.red.shade500),
                        label: const Text("Export PDF"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () {},
                        icon: Icon(Icons.table_chart, size: 16, color: Colors.green.shade600),
                        label: const Text("Export Excel"),
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
                        icon: const Icon(Icons.schedule, size: 16),
                        label: const Text("Schedule"),
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

                  // Data Table
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
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                          ),
                          child: Row(
                            children: [
                              _tableHeader("TICKET ID", flex: 2),
                              _tableHeader("DATE & TIME", flex: 2),
                              _tableHeader("VEHICLE NO.", flex: 2),
                              _tableHeader("MATERIAL", flex: 2),
                              _tableHeader("NET WEIGHT", flex: 1),
                            ],
                          ),
                        ),
                        // Rows
                        ...tableData.asMap().entries.map((entry) {
                          final index = entry.key;
                          final row = entry.value;
                          final isLast = index == tableData.length - 1;
                          return _buildTableRow(row, isLast);
                        }),
                      ],
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

  Widget _navItem(String label, bool isActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          color: isActive ? emerald600 : Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, String? change, bool showChange, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                    if (showChange && change != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: emerald50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(change, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: emerald600)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: emerald50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: emerald600),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String label) {
    final isActive = selectedTab == label;
    return GestureDetector(
      onTap: () => setState(() => selectedTab = label),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isActive ? emerald600 : Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 2,
            width: 60,
            color: isActive ? emerald500 : Colors.transparent,
          ),
        ],
      ),
    );
  }

  Widget _buildLineChart() {
    return CustomPaint(
      size: const Size(double.infinity, 180),
      painter: LineChartPainter(),
    );
  }

  Widget _buildLegendItem(Color color, String label, String percent) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(width: 12),
        Text(percent, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
      ],
    );
  }

  Widget _tableHeader(String text, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
    );
  }

  Widget _buildTableRow(Map<String, dynamic> row, bool isLast) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(row['ticketId'], style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: emerald600)),
          ),
          Expanded(
            flex: 2,
            child: Text(row['dateTime'], style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          ),
          Expanded(
            flex: 2,
            child: Text(row['vehicleNo'], style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: row['material'] == 'Coal' ? emerald50 : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    row['material'],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: row['material'] == 'Coal' ? emerald600 : Colors.amber.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(row['netWeight'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
          ),
        ],
      ),
    );
  }
}

// Custom Painters for Charts
class LineChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFF10B981).withOpacity(0.2), const Color(0xFF10B981).withOpacity(0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    // Draw grid lines
    final gridPaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = i * size.height / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw x-axis labels area
    final axisPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height - 20), Offset(size.width, size.height - 20), axisPaint);

    // Chart data points
    final points = [
      Offset(0, size.height * 0.7),
      Offset(size.width * 0.15, size.height * 0.5),
      Offset(size.width * 0.3, size.height * 0.6),
      Offset(size.width * 0.45, size.height * 0.35),
      Offset(size.width * 0.6, size.height * 0.45),
      Offset(size.width * 0.75, size.height * 0.25),
      Offset(size.width * 0.9, size.height * 0.3),
      Offset(size.width, size.height * 0.2),
    ];

    // Draw fill
    final fillPath = Path();
    fillPath.moveTo(0, size.height - 20);
    for (var point in points) {
      fillPath.lineTo(point.dx, point.dy);
    }
    fillPath.lineTo(size.width, size.height - 20);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);

    // Draw line
    final linePath = Path();
    linePath.moveTo(points.first.dx, points.first.dy);
    for (var point in points.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(linePath, paint);

    // Draw dots
    final dotPaint = Paint()..color = const Color(0xFF10B981);
    for (var point in points) {
      canvas.drawCircle(point, 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DonutChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = 18.0;

    // Coal - 45%
    final coalPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Iron Ore - 30%
    final ironOrePaint = Paint()
      ..color = const Color(0xFF6EE7B7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Limestone - 25%
    final limestonePaint = Paint()
      ..color = const Color(0xFFD1FAE5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    // Draw segments
    canvas.drawArc(rect, -math.pi / 2, math.pi * 0.9, false, coalPaint); // 45%
    canvas.drawArc(rect, -math.pi / 2 + math.pi * 0.9, math.pi * 0.6, false, ironOrePaint); // 30%
    canvas.drawArc(rect, -math.pi / 2 + math.pi * 1.5, math.pi * 0.5, false, limestonePaint); // 25%
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
