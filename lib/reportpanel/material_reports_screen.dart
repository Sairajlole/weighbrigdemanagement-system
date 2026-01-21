import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class MaterialReportsScreen extends StatefulWidget {
  const MaterialReportsScreen({super.key});

  @override
  State<MaterialReportsScreen> createState() => _MaterialReportsScreenState();
}

class _MaterialReportsScreenState extends State<MaterialReportsScreen> {
  String selectedDateRange = 'Oct 10 - Nov 10';
  String selectedMaterialType = 'All Materials';

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  final List<Map<String, dynamic>> materialBreakdown = [
    {'name': 'Limestone', 'weight': '2,055 T', 'truckCount': '142', 'avgWeight': '14.5 T', 'trend': '+8%', 'isPositive': true},
    {'name': 'Iron Ore', 'weight': '1,142 T', 'truckCount': '89', 'avgWeight': '12.8 T', 'trend': '+12%', 'isPositive': true},
    {'name': 'Coal', 'weight': '685 T', 'truckCount': '52', 'avgWeight': '13.2 T', 'trend': '-3%', 'isPositive': false},
    {'name': 'Sand', 'weight': '412 T', 'truckCount': '38', 'avgWeight': '10.8 T', 'trend': '+5%', 'isPositive': true},
    {'name': 'Gravel', 'weight': '273 T', 'truckCount': '24', 'avgWeight': '11.4 T', 'trend': '+2%', 'isPositive': true},
  ];

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Reports",
      child: Container(
        color: const Color(0xFFF9FAFB),
        child: Column(
          children: [
            // Top Header Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Row(
                children: [
                  const Text(
                    "Material Reports",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                  ),
                  const Spacer(),
                  // Search Bar
                  Container(
                    width: 220,
                    height: 38,
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
                  // Notification icons
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Icon(Icons.person_outline, size: 20, color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Icon(Icons.chat_bubble_outline, size: 18, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            
            // Main Content
            Expanded(
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
                        Text("Material Analytics", style: TextStyle(fontSize: 13, color: emerald600, fontWeight: FontWeight.w500)),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Header Row with Title and Filters
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title Section
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Material Breakdown\nAnalytics",
                                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFF111827), height: 1.2),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                "Detailed insights into material flow, weight statistics, and trends.",
                                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        ),

                        // Filters
                        Row(
                          children: [
                            // Date Range
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("DATE RANGE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFE5E7EB)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey.shade600),
                                      const SizedBox(width: 8),
                                      Text(selectedDateRange, style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            // Material Type
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("MATERIAL TYPE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFE5E7EB)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.layers_outlined, size: 16, color: Colors.grey.shade600),
                                      const SizedBox(width: 8),
                                      Text(selectedMaterialType, style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
                                      const SizedBox(width: 8),
                                      Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey.shade500),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            // Filter Button
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 22),
                                ElevatedButton.icon(
                                  onPressed: () {},
                                  icon: const Icon(Icons.filter_alt, size: 16),
                                  label: const Text("Filter"),
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
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Stat Cards Row
                    Row(
                      children: [
                        Expanded(child: _buildStatCard("Materials Tracked", "5", "Active categories", Icons.grid_view_outlined, const Color(0xFFF3F4F6), Colors.grey.shade700)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildStatCardWithTrend("Total Weight", "4,567 T", "+12% vs last month", Icons.inventory_2_outlined, const Color(0xFF111827))),
                        const SizedBox(width: 16),
                        Expanded(child: _buildStatCardHighlight("Most Popular", "Limestone", "32% of total loads", Icons.star_outline, const Color(0xFFFEF3C7), Colors.amber.shade700)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildStatCardHighlight("Heaviest Load", "Iron Ore", "Avg 32T per truck", Icons.fitness_center, const Color(0xFFF3F4F6), Colors.grey.shade700)),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Charts Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Distribution by Weight - Donut Chart
                        Expanded(
                          child: Container(
                            height: 340,
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
                                    const Text("Distribution by Weight", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                                    const Spacer(),
                                    Icon(Icons.more_horiz, size: 20, color: Colors.grey.shade400),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                Expanded(
                                  child: Row(
                                    children: [
                                      // Donut Chart
                                      Expanded(
                                        child: Center(
                                          child: SizedBox(
                                            width: 180,
                                            height: 180,
                                            child: CustomPaint(
                                              painter: MaterialDonutChartPainter(),
                                              child: Center(
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    const Text("4.5k", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                                                    Text("TOTAL TONS", style: TextStyle(fontSize: 10, color: Colors.grey.shade500, letterSpacing: 0.5)),
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
                                          _buildLegendItem(const Color(0xFFD1FAE5), "Limestone", "(45%)"),
                                          const SizedBox(height: 16),
                                          _buildLegendItem(emerald500, "Iron Ore", "(25%)"),
                                          const SizedBox(height: 16),
                                          _buildLegendItem(const Color(0xFF111827), "Coal (15%)"),
                                          const SizedBox(height: 16),
                                          _buildLegendItem(const Color(0xFFE5E7EB), "Others", "(15%)"),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Material Trends Over Time - Line Chart
                        Expanded(
                          flex: 2,
                          child: Container(
                            height: 340,
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
                                    const Text("Material Trends Over Time", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                                    const Spacer(),
                                    _buildChartLegendPill(const Color(0xFFD1FAE5), "Limestone"),
                                    const SizedBox(width: 12),
                                    _buildChartLegendPill(emerald500, "Iron Ore"),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                Expanded(
                                  child: CustomPaint(
                                    size: const Size(double.infinity, 220),
                                    painter: MaterialTrendChartPainter(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Detailed Breakdown Table
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        children: [
                          // Header
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                            child: Row(
                              children: [
                                const Text("Detailed Breakdown", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () {},
                                  child: Row(
                                    children: [
                                      Text("Export Report", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: emerald600)),
                                      const SizedBox(width: 6),
                                      Icon(Icons.download, size: 16, color: emerald600),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Table Header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF9FAFB),
                              border: Border(
                                top: BorderSide(color: Color(0xFFE5E7EB)),
                                bottom: BorderSide(color: Color(0xFFE5E7EB)),
                              ),
                            ),
                            child: Row(
                              children: [
                                _tableHeader("MATERIAL NAME", flex: 2),
                                _tableHeader("TOTAL WEIGHT (T)", flex: 2),
                                _tableHeader("TRUCK COUNT", flex: 1),
                                _tableHeader("AVG WEIGHT / LOAD", flex: 2),
                                _tableHeader("TREND (MOM)", flex: 1),
                              ],
                            ),
                          ),
                          // Table Rows
                          ...materialBreakdown.asMap().entries.map((entry) {
                            final index = entry.key;
                            final row = entry.value;
                            final isLast = index == materialBreakdown.length - 1;
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
      ),
    );
  }

  Widget _buildStatCard(String label, String value, String subtext, IconData icon, Color bgColor, Color iconColor) {
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
          Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
          const SizedBox(height: 4),
          Text(subtext, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildStatCardWithTrend(String label, String value, String trend, IconData icon, Color iconColor) {
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
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
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

  Widget _buildStatCardHighlight(String label, String value, String subtext, IconData icon, Color bgColor, Color iconColor) {
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
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
          const SizedBox(height: 4),
          Text(subtext, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, [String? percent]) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
        if (percent != null) ...[
          const SizedBox(width: 4),
          Text(percent, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ],
      ],
    );
  }

  Widget _buildChartLegendPill(Color color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _tableHeader(String text, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
    );
  }

  Widget _buildTableRow(Map<String, dynamic> row, bool isLast) {
    final isPositive = row['isPositive'] as bool;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _getMaterialColor(row['name']),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Text(row['name'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(row['weight'], style: const TextStyle(fontSize: 14, color: Color(0xFF374151))),
          ),
          Expanded(
            flex: 1,
            child: Text(row['truckCount'], style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
          ),
          Expanded(
            flex: 2,
            child: Text(row['avgWeight'], style: const TextStyle(fontSize: 14, color: Color(0xFF374151))),
          ),
          Expanded(
            flex: 1,
            child: Row(
              children: [
                Icon(
                  isPositive ? Icons.trending_up : Icons.trending_down,
                  size: 14,
                  color: isPositive ? emerald600 : Colors.red.shade500,
                ),
                const SizedBox(width: 4),
                Text(
                  row['trend'],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isPositive ? emerald600 : Colors.red.shade500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getMaterialColor(String name) {
    switch (name) {
      case 'Limestone':
        return const Color(0xFFD1FAE5);
      case 'Iron Ore':
        return emerald500;
      case 'Coal':
        return const Color(0xFF111827);
      case 'Sand':
        return const Color(0xFFFCD34D);
      case 'Gravel':
        return const Color(0xFFE5E7EB);
      default:
        return Colors.grey;
    }
  }
}

// Donut Chart Painter
class MaterialDonutChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = 28.0;

    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    // Limestone - 45%
    final limestonePaint = Paint()
      ..color = const Color(0xFFD1FAE5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Iron Ore - 25%
    final ironOrePaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Coal - 15%
    final coalPaint = Paint()
      ..color = const Color(0xFF111827)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Others - 15%
    final othersPaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Draw segments
    canvas.drawArc(rect, -math.pi / 2, math.pi * 0.9, false, limestonePaint); // 45%
    canvas.drawArc(rect, -math.pi / 2 + math.pi * 0.9, math.pi * 0.5, false, ironOrePaint); // 25%
    canvas.drawArc(rect, -math.pi / 2 + math.pi * 1.4, math.pi * 0.3, false, coalPaint); // 15%
    canvas.drawArc(rect, -math.pi / 2 + math.pi * 1.7, math.pi * 0.3, false, othersPaint); // 15%
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Material Trend Line Chart Painter
class MaterialTrendChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final limestonePaint = Paint()
      ..color = const Color(0xFFD1FAE5)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final ironOrePaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw grid lines
    final gridPaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;

    final chartHeight = size.height - 30;
    
    for (int i = 0; i <= 4; i++) {
      final y = i * chartHeight / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Y-axis labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final yLabels = ['100T', '75T', '50T', '25T', '0T'];
    for (int i = 0; i < yLabels.length; i++) {
      textPainter.text = TextSpan(
        text: yLabels[i],
        style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
      );
      textPainter.layout();
      // Don't paint Y labels for cleaner look matching the reference
    }

    // X-axis labels
    final xLabels = ['Oct 10', 'Oct 15', 'Oct 20', 'Oct 25', 'Oct 30', 'Nov 05'];
    final xStep = size.width / (xLabels.length - 1);
    for (int i = 0; i < xLabels.length; i++) {
      textPainter.text = TextSpan(
        text: xLabels[i],
        style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(i * xStep - textPainter.width / 2, size.height - 12));
    }

    // Limestone data points (light green line)
    final limestonePoints = [
      Offset(0, chartHeight * 0.6),
      Offset(xStep, chartHeight * 0.55),
      Offset(xStep * 2, chartHeight * 0.45),
      Offset(xStep * 3, chartHeight * 0.35),
      Offset(xStep * 4, chartHeight * 0.25),
      Offset(xStep * 5, chartHeight * 0.15),
    ];

    // Iron Ore data points (green line with peak)
    final ironOrePoints = [
      Offset(0, chartHeight * 0.75),
      Offset(xStep, chartHeight * 0.65),
      Offset(xStep * 2, chartHeight * 0.55),
      Offset(xStep * 3, chartHeight * 0.45),
      Offset(xStep * 4, chartHeight * 0.35),
      Offset(xStep * 5, chartHeight * 0.40),
    ];

    // Draw limestone curve
    final limestonePath = Path();
    limestonePath.moveTo(limestonePoints.first.dx, limestonePoints.first.dy);
    for (int i = 0; i < limestonePoints.length - 1; i++) {
      final p0 = limestonePoints[i];
      final p1 = limestonePoints[i + 1];
      final controlX = (p0.dx + p1.dx) / 2;
      limestonePath.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
    }
    canvas.drawPath(limestonePath, limestonePaint);

    // Draw iron ore curve
    final ironOrePath = Path();
    ironOrePath.moveTo(ironOrePoints.first.dx, ironOrePoints.first.dy);
    for (int i = 0; i < ironOrePoints.length - 1; i++) {
      final p0 = ironOrePoints[i];
      final p1 = ironOrePoints[i + 1];
      final controlX = (p0.dx + p1.dx) / 2;
      ironOrePath.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
    }
    canvas.drawPath(ironOrePath, ironOrePaint);

    // Draw dots on limestone line
    for (var point in limestonePoints) {
      canvas.drawCircle(point, 4, Paint()..color = const Color(0xFFD1FAE5));
      canvas.drawCircle(point, 2, Paint()..color = Colors.white);
    }

    // Draw dots on iron ore line
    for (var point in ironOrePoints) {
      canvas.drawCircle(point, 4, Paint()..color = const Color(0xFF10B981));
      canvas.drawCircle(point, 2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
