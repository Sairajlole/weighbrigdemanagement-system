import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class ComparisonReportsScreen extends StatefulWidget {
  const ComparisonReportsScreen({super.key});

  @override
  State<ComparisonReportsScreen> createState() => _ComparisonReportsScreenState();
}

class _ComparisonReportsScreenState extends State<ComparisonReportsScreen> {
  String selectedPreset = 'This Week vs Last Week';
  String p1StartDate = '10/01/2023';
  String p1EndDate = '10/31/2023';
  String p2StartDate = '11/01/2023';
  String p2EndDate = '11/30/2023';

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  final List<Map<String, dynamic>> varianceData = [
    {'material': 'Limestone', 'p1Weight': '450t', 'p2Weight': '580t', 'variance': '+130t', 'change': '+28%', 'isPositive': true},
    {'material': 'Granite', 'p1Weight': '300t', 'p2Weight': '280t', 'variance': '-20t', 'change': '-6%', 'isPositive': false},
    {'material': 'Sand', 'p1Weight': '200t', 'p2Weight': '240t', 'variance': '+40t', 'change': '+20%', 'isPositive': true},
    {'material': 'Coal', 'p1Weight': '100t', 'p2Weight': '100t', 'variance': '0t', 'change': '0%', 'isPositive': true},
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
                  Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text("Reports", style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400),
                  Text("Period Comparison", style: TextStyle(fontSize: 13, color: emerald600, fontWeight: FontWeight.w500)),
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
                          "Period Comparison Report",
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Analyze weighbridge performance variance between two distinct timeframes to identify trends and anomalies.",
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: Icon(Icons.print, size: 16, color: Colors.grey.shade700),
                    label: const Text("Print"),
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
                    icon: Icon(Icons.download_outlined, size: 16, color: Colors.grey.shade700),
                    label: const Text("Export"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Filter Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Quick Presets
                    Text("QUICK PRESETS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildPresetButton("This Week vs Last Week", true),
                        const SizedBox(width: 8),
                        _buildPresetButton("Month over Month", false),
                        const SizedBox(width: 8),
                        _buildPresetButton("Year over Year", false),
                        const SizedBox(width: 8),
                        _buildPresetButton("Last 30 Days", false),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Date Ranges
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Baseline Period (P1)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: emerald50,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(Icons.calendar_today, size: 12, color: emerald600),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text("Baseline Period (P1)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(child: _buildDateField("Start Date", p1StartDate)),
                                  const SizedBox(width: 12),
                                  Expanded(child: _buildDateField("End Date", p1EndDate)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // VS Divider
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Text("vs", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
                            ),
                          ),
                        ),
                        // Comparison Period (P2)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: emerald500,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.calendar_today, size: 12, color: Colors.white),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text("Comparison Period (P2)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(child: _buildDateField("Start Date", p2StartDate)),
                                  const SizedBox(width: 12),
                                  Expanded(child: _buildDateField("End Date", p2EndDate)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        // Run Comparison Button
                        ElevatedButton(
                          onPressed: () {},
                          style: ElevatedButton.styleFrom(
                            backgroundColor: emerald500,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                          child: const Text("Run Comparison"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Stats Cards
              Row(
                children: [
                  Expanded(child: _buildComparisonCard("Total Tonnage", "1,200t", "vs 1,050t", "+14.2%", true)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildComparisonCard("Truck Volume", "45", "vs 50", "-10.0%", false)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildComparisonCard("Avg Turnaround", "12m", "vs 15m", "-20%", true)),
                ],
              ),

              const SizedBox(height: 24),

              // Charts Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Daily Tonnage Trend
                  Expanded(
                    flex: 2,
                    child: Container(
                      height: 320,
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
                              const Text("Daily Tonnage Trend", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                              const Spacer(),
                              _buildChartLegend(emerald50, "Baseline (P1)"),
                              const SizedBox(width: 16),
                              _buildChartLegend(emerald500, "Comparison (P2)"),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Expanded(
                            child: CustomPaint(
                              size: const Size(double.infinity, 220),
                              painter: ComparisonChartPainter(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Contribution Analysis
                  Expanded(
                    child: Container(
                      height: 320,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Contribution Analysis", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                          const SizedBox(height: 4),
                          Text("Factors contributing to +150t net change", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                          const SizedBox(height: 32),
                          _buildContributionBar("Baseline", 0.7, "1,050", false),
                          const SizedBox(height: 20),
                          _buildContributionBar("New Contracts", 0.3, "+100", true),
                          const SizedBox(height: 20),
                          _buildContributionBar("Seasonality", 0.15, "+50", true),
                          const Spacer(),
                          Row(
                            children: [
                              const Text("Comparison", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: emerald500,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text("1,200", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Detailed Variance Table
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
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Row(
                        children: [
                          const Text("Detailed Variance by Material", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {},
                            child: Text("View Full Report", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: emerald600)),
                          ),
                        ],
                      ),
                    ),
                    // Table Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF9FAFB),
                        border: Border(
                          top: BorderSide(color: Color(0xFFE5E7EB)),
                          bottom: BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                      ),
                      child: Row(
                        children: [
                          _tableHeader("Material", flex: 2),
                          _tableHeader("P1 Weight", flex: 2),
                          _tableHeader("P2 Weight", flex: 2),
                          _tableHeader("Variance", flex: 2),
                          _tableHeader("% Change", flex: 1),
                        ],
                      ),
                    ),
                    // Table Rows
                    ...varianceData.asMap().entries.map((entry) {
                      final index = entry.key;
                      final row = entry.value;
                      final isLast = index == varianceData.length - 1;
                      return _buildVarianceRow(row, isLast);
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetButton(String label, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isSelected ? const Color(0xFF111827) : const Color(0xFFE5E7EB)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: isSelected ? Colors.white : Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _buildDateField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.grey.shade500)),
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
              Text(value, style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
              const Spacer(),
              Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade400),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonCard(String label, String value, String comparison, String change, bool isPositive) {
    final changeColor = isPositive ? emerald600 : Colors.red.shade500;
    final changeBgColor = isPositive ? emerald50 : const Color(0xFFFFE4E6);
    
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: changeBgColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(
                      isPositive ? Icons.trending_up : Icons.trending_down,
                      size: 12,
                      color: changeColor,
                    ),
                    const SizedBox(width: 4),
                    Text(change, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: changeColor)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(comparison, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartLegend(Color color, String label) {
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
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildContributionBar(String label, double widthFactor, String value, bool isPositive) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ),
        Expanded(
          child: Container(
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: widthFactor,
              child: Container(
                decoration: BoxDecoration(
                  color: isPositive ? emerald500 : const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isPositive ? Colors.white : emerald600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tableHeader(String text, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
    );
  }

  Widget _buildVarianceRow(Map<String, dynamic> row, bool isLast) {
    final isPositive = row['isPositive'] as bool;
    final changeColor = row['change'] == '0%' ? Colors.grey.shade500 : (isPositive ? emerald600 : Colors.red.shade500);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(row['material'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
          ),
          Expanded(
            flex: 2,
            child: Text(row['p1Weight'], style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          ),
          Expanded(
            flex: 2,
            child: Text(row['p2Weight'], style: const TextStyle(fontSize: 14, color: Color(0xFF374151))),
          ),
          Expanded(
            flex: 2,
            child: Text(
              row['variance'],
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: row['variance'] == '0t' ? Colors.grey.shade500 : (isPositive ? emerald600 : Colors.red.shade500),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: row['change'] == '0%' ? const Color(0xFFF3F4F6) : (isPositive ? emerald50 : const Color(0xFFFFE4E6)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                row['change'],
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: changeColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Comparison Line Chart Painter
class ComparisonChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final baselinePaint = Paint()
      ..color = const Color(0xFFD1FAE5)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final comparisonPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFF10B981).withOpacity(0.15), const Color(0xFF10B981).withOpacity(0.02)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    // Draw grid lines
    final gridPaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;

    final chartHeight = size.height - 30;
    
    for (int i = 0; i <= 3; i++) {
      final y = i * chartHeight / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Y-axis labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final yLabels = ['150t', '100t', '50t', '0t'];
    for (int i = 0; i < yLabels.length; i++) {
      textPainter.text = TextSpan(
        text: yLabels[i],
        style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
      );
      textPainter.layout();
      // Y labels positioned to the left
    }

    // X-axis labels
    final xLabels = ['Day 1', 'Day 7', 'Day 14', 'Day 21', 'Day 30'];
    final xStep = size.width / (xLabels.length - 1);
    for (int i = 0; i < xLabels.length; i++) {
      textPainter.text = TextSpan(
        text: xLabels[i],
        style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(i * xStep - textPainter.width / 2, size.height - 12));
    }

    // Baseline (P1) data points
    final baselinePoints = [
      Offset(0, chartHeight * 0.65),
      Offset(xStep, chartHeight * 0.55),
      Offset(xStep * 2, chartHeight * 0.50),
      Offset(xStep * 3, chartHeight * 0.45),
      Offset(xStep * 4, chartHeight * 0.40),
    ];

    // Comparison (P2) data points
    final comparisonPoints = [
      Offset(0, chartHeight * 0.60),
      Offset(xStep, chartHeight * 0.45),
      Offset(xStep * 2, chartHeight * 0.35),
      Offset(xStep * 3, chartHeight * 0.25),
      Offset(xStep * 4, chartHeight * 0.20),
    ];

    // Draw fill for comparison
    final fillPath = Path();
    fillPath.moveTo(0, chartHeight);
    for (var point in comparisonPoints) {
      fillPath.lineTo(point.dx, point.dy);
    }
    fillPath.lineTo(size.width, chartHeight);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);

    // Draw baseline curve
    final baselinePath = Path();
    baselinePath.moveTo(baselinePoints.first.dx, baselinePoints.first.dy);
    for (int i = 0; i < baselinePoints.length - 1; i++) {
      final p0 = baselinePoints[i];
      final p1 = baselinePoints[i + 1];
      final controlX = (p0.dx + p1.dx) / 2;
      baselinePath.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
    }
    canvas.drawPath(baselinePath, baselinePaint);

    // Draw comparison curve
    final comparisonPath = Path();
    comparisonPath.moveTo(comparisonPoints.first.dx, comparisonPoints.first.dy);
    for (int i = 0; i < comparisonPoints.length - 1; i++) {
      final p0 = comparisonPoints[i];
      final p1 = comparisonPoints[i + 1];
      final controlX = (p0.dx + p1.dx) / 2;
      comparisonPath.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
    }
    canvas.drawPath(comparisonPath, comparisonPaint);

    // Draw tooltip at peak
    final peakPoint = comparisonPoints[3];
    
    // Tooltip background
    final tooltipRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(peakPoint.dx, peakPoint.dy - 35), width: 80, height: 40),
      const Radius.circular(6),
    );
    canvas.drawRRect(tooltipRect, Paint()..color = const Color(0xFF374151));
    
    // Tooltip text
    textPainter.text = const TextSpan(
      text: 'Nov 22\nP1: 110t\nP2: 145t',
      style: TextStyle(color: Colors.white, fontSize: 9, height: 1.3),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(peakPoint.dx - textPainter.width / 2, peakPoint.dy - 55));

    // Draw dots on lines
    for (var point in baselinePoints) {
      canvas.drawCircle(point, 4, Paint()..color = const Color(0xFFD1FAE5));
      canvas.drawCircle(point, 2, Paint()..color = Colors.white);
    }
    for (var point in comparisonPoints) {
      canvas.drawCircle(point, 4, Paint()..color = const Color(0xFF10B981));
      canvas.drawCircle(point, 2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
