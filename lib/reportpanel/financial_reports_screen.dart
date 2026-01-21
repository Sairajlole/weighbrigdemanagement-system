import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class FinancialReportsScreen extends StatefulWidget {
  const FinancialReportsScreen({super.key});

  @override
  State<FinancialReportsScreen> createState() => _FinancialReportsScreenState();
}

class _FinancialReportsScreenState extends State<FinancialReportsScreen> {
  String selectedTab = 'Overview';
  String selectedDateRange = 'Jan 1 - Jan 31, 2024';
  String selectedPaymentStatus = 'All Status';
  String selectedCustomer = 'All Customers';

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  final List<Map<String, dynamic>> recentTransactions = [
    {'invoice': 'INV-2024-001', 'customer': 'Atlas Construction', 'amount': '\$4,250.00', 'status': 'Paid', 'date': 'Jan 28, 2024'},
    {'invoice': 'INV-2024-002', 'customer': 'Green Valley Farms', 'amount': '\$3,180.00', 'status': 'Pending', 'date': 'Jan 27, 2024'},
    {'invoice': 'INV-2024-003', 'customer': 'City Logistics', 'amount': '\$2,890.00', 'status': 'Paid', 'date': 'Jan 26, 2024'},
    {'invoice': 'INV-2024-004', 'customer': 'Metro Builders', 'amount': '\$5,420.00', 'status': 'Overdue', 'date': 'Jan 15, 2024'},
    {'invoice': 'INV-2024-005', 'customer': 'Roadworks Inc.', 'amount': '\$1,750.00', 'status': 'Paid', 'date': 'Jan 24, 2024'},
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
                  Text("Financial Reports", style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
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
                          "Financial Reports",
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Track revenue, invoices, payments, and financial performance.",
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
                    // Payment Status
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("PAYMENT STATUS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
                          const SizedBox(height: 6),
                          _buildDropdown(
                            value: selectedPaymentStatus,
                            items: ['All Status', 'Paid', 'Pending', 'Overdue'],
                            onChanged: (value) => setState(() => selectedPaymentStatus = value!),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Customer
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("CUSTOMER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
                          const SizedBox(height: 6),
                          _buildDropdown(
                            value: selectedCustomer,
                            items: ['All Customers', 'Atlas Construction', 'Green Valley Farms', 'City Logistics', 'Metro Builders'],
                            onChanged: (value) => setState(() => selectedCustomer = value!),
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
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Filters applied: $selectedPaymentStatus, $selectedCustomer'),
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
                  Expanded(child: _buildStatCard("Total Revenue", "\$48,250", "+12%", true, Icons.attach_money, emerald50, emerald500)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard("Pending Payments", "\$8,420", "-5%", true, Icons.schedule_outlined, const Color(0xFFFEF3C7), Colors.amber.shade600)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard("Overdue Amount", "\$2,180", "+8%", false, Icons.warning_amber_outlined, const Color(0xFFFFE4E6), Colors.red.shade400)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard("Collection Rate", "92%", "+3%", true, Icons.trending_up, emerald50, emerald500)),
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
                    _buildTab("Invoices"),
                    const SizedBox(width: 24),
                    _buildTab("Payments"),
                    const SizedBox(width: 24),
                    _buildTab("Revenue Analysis"),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Main Content Row - Chart and Recent Transactions
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Revenue Over Time Chart
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
                              const Text("Revenue Over Time", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
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
                                    Text("Revenue (\$)", style: TextStyle(fontSize: 12, color: emerald600)),
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
                              painter: RevenueBarChartPainter(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Payment Status Breakdown
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
                          const Text("Payment Status", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                          const SizedBox(height: 20),
                          Center(
                            child: SizedBox(
                              width: 140,
                              height: 140,
                              child: CustomPaint(
                                painter: PaymentDonutChartPainter(),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text("Total", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                      const Text("\$58.8K", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildPaymentStatusItem(emerald500, "Paid", "\$48,250", "82%"),
                          const SizedBox(height: 12),
                          _buildPaymentStatusItem(Colors.amber.shade500, "Pending", "\$8,420", "14%"),
                          const SizedBox(height: 12),
                          _buildPaymentStatusItem(Colors.red.shade400, "Overdue", "\$2,180", "4%"),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Recent Transactions Table
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
                    Row(
                      children: [
                        const Text("Recent Transactions", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                        const Spacer(),
                        Text("View All", style: TextStyle(fontSize: 13, color: emerald600, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Table Header
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(flex: 2, child: Text("INVOICE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                          Expanded(flex: 3, child: Text("CUSTOMER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                          Expanded(flex: 2, child: Text("AMOUNT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                          Expanded(flex: 2, child: Text("STATUS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                          Expanded(flex: 2, child: Text("DATE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                          const SizedBox(width: 40, child: Text("", style: TextStyle(fontSize: 10))),
                        ],
                      ),
                    ),
                    // Table Rows
                    ...recentTransactions.map((transaction) => _buildTransactionRow(transaction)),
                  ],
                ),
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

  Widget _buildTransactionRow(Map<String, dynamic> transaction) {
    Color statusColor;
    Color statusBgColor;
    switch (transaction['status']) {
      case 'Paid':
        statusColor = emerald600;
        statusBgColor = emerald50;
        break;
      case 'Pending':
        statusColor = Colors.amber.shade700;
        statusBgColor = const Color(0xFFFEF3C7);
        break;
      case 'Overdue':
        statusColor = Colors.red.shade600;
        statusBgColor = const Color(0xFFFFE4E6);
        break;
      default:
        statusColor = Colors.grey.shade600;
        statusBgColor = Colors.grey.shade100;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(transaction['invoice'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
          ),
          Expanded(
            flex: 3,
            child: Text(transaction['customer'], style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
          ),
          Expanded(
            flex: 2,
            child: Text(transaction['amount'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusBgColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                transaction['status'],
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: statusColor),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(transaction['date'], style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          ),
          SizedBox(
            width: 40,
            child: Icon(Icons.more_horiz, size: 18, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentStatusItem(Color color, String label, String amount, String percent) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
        const Spacer(),
        Text(amount, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
        const SizedBox(width: 8),
        Text(percent, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
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

// Revenue Bar Chart Painter
class RevenueBarChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = 40.0;
    final spacing = (size.width - (barWidth * 7)) / 8;
    final chartHeight = size.height - 30;

    // Draw grid lines
    final gridPaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = i * chartHeight / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Bar data (revenue values)
    final barValues = [0.65, 0.45, 0.8, 0.55, 0.9, 0.7, 0.85];
    final xLabels = ['Week 1', 'Week 2', 'Week 3', 'Week 4', 'Week 5', 'Week 6', 'Week 7'];

    // Draw bars
    for (int i = 0; i < barValues.length; i++) {
      final x = spacing + i * (barWidth + spacing);
      final barHeight = barValues[i] * chartHeight;
      final y = chartHeight - barHeight;

      // Bar gradient
      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        const Radius.circular(6),
      );

      final barPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF10B981), Color(0xFF059669)],
        ).createShader(Rect.fromLTWH(x, y, barWidth, barHeight));

      canvas.drawRRect(barRect, barPaint);

      // X-axis labels
      final textPainter = TextPainter(
        text: TextSpan(
          text: xLabels[i],
          style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + barWidth / 2 - textPainter.width / 2, size.height - 15));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Payment Donut Chart Painter
class PaymentDonutChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = 20.0;

    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    // Paid - 82%
    final paidPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Pending - 14%
    final pendingPaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Overdue - 4%
    final overduePaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Draw segments (with small gaps)
    final gap = 0.03;
    canvas.drawArc(rect, -math.pi / 2, math.pi * (1.64 - gap), false, paidPaint); // 82%
    canvas.drawArc(rect, -math.pi / 2 + math.pi * 1.64, math.pi * (0.28 - gap), false, pendingPaint); // 14%
    canvas.drawArc(rect, -math.pi / 2 + math.pi * 1.92, math.pi * (0.08 - gap), false, overduePaint); // 4%
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
