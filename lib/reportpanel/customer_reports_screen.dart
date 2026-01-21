import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class CustomerReportsScreen extends StatefulWidget {
  const CustomerReportsScreen({super.key});

  @override
  State<CustomerReportsScreen> createState() => _CustomerReportsScreenState();
}

class _CustomerReportsScreenState extends State<CustomerReportsScreen> {
  String selectedTab = 'Overview';
  String selectedDateRange = 'Jan 1 - Jan 31, 2024';
  String selectedSegment = 'All Segments';
  String selectedMaterial = 'All Materials';

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  final List<Map<String, dynamic>> topCustomers = [
    {'customer': 'Atlas Construction', 'type': 'Industrial', 'weight': '1,240t', 'trips': '42'},
    {'customer': 'Green Valley Farms', 'type': 'Commercial', 'weight': '980t', 'trips': '35'},
    {'customer': 'City Logistics', 'type': 'Commercial', 'weight': '850t', 'trips': '28'},
    {'customer': 'Metro Builders', 'type': 'Industrial', 'weight': '720t', 'trips': '19'},
    {'customer': 'Roadworks Inc.', 'type': 'Industrial', 'weight': '650t', 'trips': '15'},
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
              // Breadcrumb
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text("Reports", style: TextStyle(fontSize: 13, color: emerald600)),
                  ),
                  Text("  /  ", style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                  Text("Analytics", style: TextStyle(fontSize: 13, color: emerald600)),
                  Text("  /  ", style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                  Text("Customer Analytics Report", style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                ],
              ),

              const SizedBox(height: 16),

              // Header with Title and Actions
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Customer Analytics Report",
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Analyze customer performance, weighbridge trends, and segments.",
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.print, size: 16),
                    label: const Text("Print"),
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
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text("Export Report"),
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
                          Text("DATE RANGE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () => _showDateRangePicker(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: Row(
                                children: [
                                  Text(selectedDateRange, style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
                                  const Spacer(),
                                  Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey.shade500),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Customer Segment
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("CUSTOMER SEGMENT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
                          const SizedBox(height: 6),
                          _buildDropdown(
                            value: selectedSegment,
                            items: ['All Segments', 'Industrial', 'Commercial', 'Private'],
                            onChanged: (value) => setState(() => selectedSegment = value!),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Material
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("MATERIAL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
                          const SizedBox(height: 6),
                          _buildDropdown(
                            value: selectedMaterial,
                            items: ['All Materials', 'Coal', 'Iron Ore', 'Limestone', 'Sand', 'Gravel'],
                            onChanged: (value) => setState(() => selectedMaterial = value!),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Apply Button
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: ElevatedButton(
                        onPressed: () {
                          // Apply filters - show snackbar for feedback
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Filters applied: $selectedSegment, $selectedMaterial'),
                              backgroundColor: emerald500,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
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

              // Stats Cards
              Row(
                children: [
                  Expanded(child: _buildStatCard("Total Customers", "156", "+5%", true, Icons.people_outlined, emerald50, emerald500)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard("Active This Period", "89", "+12%", true, Icons.trending_up, const Color(0xFFFEF3C7), Colors.amber.shade600)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard("New Customers", "12", "-2%", false, Icons.person_add_outlined, const Color(0xFFFFE4E6), Colors.red.shade400)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard("Returning Rate", "78%", "+4%", true, Icons.replay_outlined, emerald50, emerald500)),
                ],
              ),

              const SizedBox(height: 24),

              // Tabs
              Container(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
                ),
                child: Row(
                  children: [
                    _buildTab("Overview"),
                    const SizedBox(width: 24),
                    _buildTab("Top Customers"),
                    const SizedBox(width: 24),
                    _buildTab("Activity Analysis"),
                    const SizedBox(width: 24),
                    _buildTab("Customer List"),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Main Content Row - Chart and Top Customers
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Activity Over Time Chart
                  Expanded(
                    flex: 3,
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
                              const Text("Customer Activity Over Time", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: emerald50,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: emerald500,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text("Total Weight (Tons)", style: TextStyle(fontSize: 12, color: emerald600)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 240,
                            child: CustomPaint(
                              size: const Size(double.infinity, 240),
                              painter: CustomerAreaChartPainter(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Top Customers List
                  Expanded(
                    flex: 2,
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
                              const Text("Top Customers", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                              const Spacer(),
                              Text("View All", style: TextStyle(fontSize: 13, color: emerald600, fontWeight: FontWeight.w500)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Header
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
                            ),
                            child: Row(
                              children: [
                                Expanded(flex: 2, child: Text("CUSTOMER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                                Expanded(child: Text("WEIGHT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                                SizedBox(width: 50, child: Text("TRIPS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                              ],
                            ),
                          ),
                          // Rows
                          ...topCustomers.map((customer) => _buildTopCustomerRow(customer)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Bottom Row - Segments and Breakdown
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Customer Segments Donut
                  Expanded(
                    child: Container(
                      height: 280,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Customer Segments", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                          const SizedBox(height: 20),
                          Expanded(
                            child: Center(
                              child: SizedBox(
                                width: 160,
                                height: 160,
                                child: CustomPaint(
                                  painter: CustomerDonutChartPainter(),
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text("Total", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                        const Text("100%", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Segment Breakdown
                  Expanded(
                    child: Container(
                      height: 280,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Segment Breakdown", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                          const SizedBox(height: 24),
                          _buildSegmentItem(emerald500, "Industrial", "45%", "70 Customers"),
                          const SizedBox(height: 20),
                          _buildSegmentItem(const Color(0xFF6EE7B7), "Commercial", "30%", "47 Customers"),
                          const SizedBox(height: 20),
                          _buildSegmentItem(const Color(0xFFD1FAE5), "Private", "25%", "39 Customers"),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Download CSV Card
                  Expanded(
                    child: Container(
                      height: 280,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("Need a detailed breakdown?", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                          const SizedBox(height: 8),
                          Text(
                            "Download the full CSV report to analyze individual transaction logs for all customers.",
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.5),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {},
                              icon: Icon(Icons.download, size: 16, color: emerald600),
                              label: Text("Download CSV", style: TextStyle(color: emerald600)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: BorderSide(color: emerald500),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
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

  Widget _buildStatCard(String label, String value, String change, bool isPositive, IconData icon, Color bgColor, Color iconColor) {
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
              Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
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
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 12,
                      color: isPositive ? emerald600 : Colors.red.shade500,
                    ),
                    Text(
                      change,
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
        ],
      ),
    );
  }

  Widget _buildTab(String label) {
    final isActive = selectedTab == label;
    return GestureDetector(
      onTap: () => setState(() => selectedTab = label),
      child: Container(
        padding: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? emerald500 : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            color: isActive ? const Color(0xFF111827) : Colors.grey.shade500,
          ),
        ),
      ),
    );
  }

  Widget _buildTopCustomerRow(Map<String, dynamic> customer) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(customer['customer'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
                Text(customer['type'], style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Expanded(
            child: Text(customer['weight'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
          ),
          SizedBox(
            width: 50,
            child: Text(customer['trips'], style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentItem(Color color, String label, String percent, String count) {
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
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
        const Spacer(),
        Text(percent, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
        const SizedBox(width: 12),
        Text(count, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey.shade500),
          style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
          items: items.map((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(item),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Future<void> _showDateRangePicker(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(
        start: DateTime(2024, 1, 1),
        end: DateTime(2024, 1, 31),
      ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF10B981),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF374151),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        final startMonth = _getMonthName(picked.start.month);
        final endMonth = _getMonthName(picked.end.month);
        selectedDateRange = '$startMonth ${picked.start.day} - $endMonth ${picked.end.day}, ${picked.end.year}';
      });
    }
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }
}

// Area Chart Painter for Customer Activity
class CustomerAreaChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFF10B981).withOpacity(0.2), const Color(0xFF10B981).withOpacity(0.02)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    // Draw grid lines
    final gridPaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = i * (size.height - 30) / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // X-axis labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final xLabels = ['Jan 1', 'Jan 7', 'Jan 14', 'Jan 21', 'Jan 28'];
    final xStep = size.width / (xLabels.length - 1);
    for (int i = 0; i < xLabels.length; i++) {
      textPainter.text = TextSpan(
        text: xLabels[i],
        style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(i * xStep - textPainter.width / 2, size.height - 15));
    }

    // Chart data points
    final chartHeight = size.height - 30;
    final points = [
      Offset(0, chartHeight * 0.7),
      Offset(xStep * 0.5, chartHeight * 0.65),
      Offset(xStep, chartHeight * 0.55),
      Offset(xStep * 1.5, chartHeight * 0.45),
      Offset(xStep * 2, chartHeight * 0.25), // Peak with tooltip
      Offset(xStep * 2.5, chartHeight * 0.35),
      Offset(xStep * 3, chartHeight * 0.4),
      Offset(xStep * 3.5, chartHeight * 0.38),
      Offset(xStep * 4, chartHeight * 0.45),
    ];

    // Draw fill area
    final fillPath = Path();
    fillPath.moveTo(0, chartHeight);
    for (var point in points) {
      fillPath.lineTo(point.dx, point.dy);
    }
    fillPath.lineTo(size.width, chartHeight);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);

    // Draw smooth curve
    final linePath = Path();
    linePath.moveTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlX = (p0.dx + p1.dx) / 2;
      linePath.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
    }
    canvas.drawPath(linePath, paint);

    // Draw tooltip at peak point (Jan 14 area)
    final peakPoint = points[4];
    
    // Tooltip background
    final tooltipRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(peakPoint.dx, peakPoint.dy - 35), width: 80, height: 28),
      const Radius.circular(6),
    );
    canvas.drawRRect(tooltipRect, Paint()..color = const Color(0xFF374151));
    
    // Tooltip text
    textPainter.text = const TextSpan(
      text: '480 Tons',
      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(peakPoint.dx - textPainter.width / 2, peakPoint.dy - 42));

    // Highlight dot at peak
    canvas.drawCircle(peakPoint, 6, Paint()..color = const Color(0xFF10B981));
    canvas.drawCircle(peakPoint, 4, Paint()..color = Colors.white);
    canvas.drawCircle(peakPoint, 3, Paint()..color = const Color(0xFF10B981));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Donut Chart Painter for Customer Segments
class CustomerDonutChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = 24.0;

    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    // Industrial - 45%
    final industrialPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Commercial - 30%
    final commercialPaint = Paint()
      ..color = const Color(0xFF6EE7B7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Private - 25%
    final privatePaint = Paint()
      ..color = const Color(0xFFD1FAE5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Draw segments (with small gaps)
    final gap = 0.03;
    canvas.drawArc(rect, -math.pi / 2, math.pi * (0.9 - gap), false, industrialPaint); // 45%
    canvas.drawArc(rect, -math.pi / 2 + math.pi * 0.9, math.pi * (0.6 - gap), false, commercialPaint); // 30%
    canvas.drawArc(rect, -math.pi / 2 + math.pi * 1.5, math.pi * (0.5 - gap), false, privatePaint); // 25%
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
