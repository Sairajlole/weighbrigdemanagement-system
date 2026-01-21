import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class VehicleReportsScreen extends StatefulWidget {
  const VehicleReportsScreen({super.key});

  @override
  State<VehicleReportsScreen> createState() => _VehicleReportsScreenState();
}

class _VehicleReportsScreenState extends State<VehicleReportsScreen> {
  String selectedDateRange = 'Select dates';
  String searchVehicle = '';

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  final List<Map<String, dynamic>> vehicleData = [
    {'vehicleNo': 'KA-01-AB-1234', 'owner': 'Raj Transport Services', 'totalTrips': 48, 'totalTonnage': '1,248 T', 'lastActivity': 'Oct 24, 2023 10:30 AM', 'status': 'Active'},
    {'vehicleNo': 'TN-45-X-9988', 'owner': 'Southern Logistics Co.', 'totalTrips': 42, 'totalTonnage': '988 T', 'lastActivity': 'Oct 23, 2023 04:15 PM', 'status': 'Idle'},
    {'vehicleNo': 'AP-29-CD-5678', 'owner': 'Venkata Movers', 'totalTrips': 35, 'totalTonnage': '828 T', 'lastActivity': 'Oct 22, 2023 09:00 AM', 'status': 'Active'},
    {'vehicleNo': 'KL-07-EF-9012', 'owner': 'Cochin Freight', 'totalTrips': 28, 'totalTonnage': '658 T', 'lastActivity': 'Oct 24, 2023 11:45 AM', 'status': 'Active'},
    {'vehicleNo': 'MH-12-GH-3456', 'owner': 'Pune Express', 'totalTrips': 22, 'totalTonnage': '418 T', 'lastActivity': 'Oct 20, 2023 02:20 PM', 'status': 'Inactive'},
  ];

  final List<Map<String, dynamic>> topVehicles = [
    {'vehicleNo': 'KA-01-AB-1234', 'trips': 48},
    {'vehicleNo': 'TN-45-X-9988', 'trips': 42},
    {'vehicleNo': 'AP-29-CD-5678', 'trips': 35},
    {'vehicleNo': 'KL-07-EF-9012', 'trips': 28},
    {'vehicleNo': 'MH-12-GH-3456', 'trips': 22},
  ];

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Reports",
      child: Container(
        color: const Color(0xFFF9FAFB),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Main Content
              Padding(
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
                        Text("Vehicle Activity", style: TextStyle(fontSize: 13, color: emerald600, fontWeight: FontWeight.w500)),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Header Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title Section
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Vehicle Activity Reports",
                                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Monitor fleet performance, trip logs, and operational efficiency.",
                                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        ),

                        // Filter Section
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
                                      Text(selectedDateRange, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            // Search Vehicle
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("SEARCH VEHICLE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
                                const SizedBox(height: 6),
                                Container(
                                  width: 180,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFE5E7EB)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.search, size: 16, color: Colors.grey.shade400),
                                      const SizedBox(width: 8),
                                      Text("Enter vehicle no.", style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            // Buttons
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 22),
                                Row(
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: () {},
                                      icon: const Icon(Icons.filter_list, size: 16),
                                      label: const Text("Apply"),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: emerald500,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        elevation: 0,
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
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Stats Cards Row
                    Row(
                      children: [
                        Expanded(child: _buildStatCard("Unique Vehicles", "234", "+5% vs last month", Icons.local_shipping_outlined, true)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildStatCard("Total Trips", "512", "+12% vs last month", Icons.swap_vert, true)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildStatCard("Avg Trips/Vehicle", "2.1", "Stable vs last month", Icons.show_chart, null)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildStatCardWithVehicle("Most Active", "KA-01-AB-1234", "48 Trips this month", Icons.emoji_events_outlined)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildStatCard("Avg Load", "18.5 Tons", "+2% efficiency", Icons.monitor_weight_outlined, true)),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Charts Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Bar Chart - Vehicle Activity Over Time
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
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text("Vehicle Activity Over Time", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                                        const SizedBox(height: 2),
                                        Text("Daily trips breakdown (Inbound/Outbound)", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                      ],
                                    ),
                                    const Spacer(),
                                    Row(
                                      children: [
                                        Container(width: 12, height: 12, decoration: BoxDecoration(color: emerald500, borderRadius: BorderRadius.circular(2))),
                                        const SizedBox(width: 6),
                                        Text("Inbound", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                        const SizedBox(width: 16),
                                        Container(width: 12, height: 12, decoration: BoxDecoration(color: const Color(0xFF6EE7B7), borderRadius: BorderRadius.circular(2))),
                                        const SizedBox(width: 6),
                                        Text("Outbound", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Expanded(child: _buildBarChart()),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Top 5 Vehicles
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
                                const Text("Top 5 Vehicles", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                                const SizedBox(height: 4),
                                Text("By trip frequency", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                const SizedBox(height: 16),
                                Expanded(
                                  child: Column(
                                    children: topVehicles.map((v) => _buildTopVehicleItem(v['vehicleNo'], v['trips'])).toList(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Detailed Vehicle List Table
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
                                const Text("Detailed Vehicle List", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () {},
                                  child: Row(
                                    children: [
                                      Text("View All", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: emerald600)),
                                      const SizedBox(width: 4),
                                      Icon(Icons.arrow_forward, size: 14, color: emerald600),
                                    ],
                                  ),
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
                                _tableHeader("VEHICLE NUMBER", flex: 2),
                                _tableHeader("OWNER / TRANSPORTER", flex: 2),
                                _tableHeader("TOTAL TRIPS", flex: 1),
                                _tableHeader("TOTAL TONNAGE", flex: 1),
                                _tableHeader("LAST ACTIVITY", flex: 2),
                                _tableHeader("STATUS", flex: 1),
                              ],
                            ),
                          ),
                          // Table Rows
                          ...vehicleData.asMap().entries.map((entry) {
                            final index = entry.key;
                            final row = entry.value;
                            final isLast = index == vehicleData.length - 1;
                            return _buildTableRow(row, isLast);
                          }),
                          // Pagination
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            decoration: const BoxDecoration(
                              border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  "Showing 1-5 of 234 vehicles",
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                                ),
                                const Spacer(),
                                _buildPaginationButton("Previous", false),
                                const SizedBox(width: 8),
                                _buildPaginationButton("Next", true),
                              ],
                            ),
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
      ),
    );
  }

  Widget _buildStatCard(String label, String value, String? subtext, IconData icon, bool? isPositive) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              const Spacer(),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: emerald50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: emerald600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
          if (subtext != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if (isPositive != null) ...[
                  Text(
                    isPositive ? "↗" : "↘",
                    style: TextStyle(fontSize: 12, color: isPositive ? emerald600 : Colors.red.shade500),
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    subtext,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCardWithVehicle(String label, String vehicleNo, String subtext, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              const Spacer(),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: Colors.amber.shade700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(vehicleNo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
          const SizedBox(height: 4),
          Text(subtext, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildBarChart() {
    return CustomPaint(
      size: const Size(double.infinity, 200),
      painter: BarChartPainter(),
    );
  }

  Widget _buildTopVehicleItem(String vehicleNo, int trips) {
    final maxTrips = 48;
    final percentage = trips / maxTrips;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(vehicleNo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
              const Spacer(),
              Text(trips.toString(), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: emerald600)),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: percentage,
              child: Container(
                decoration: BoxDecoration(
                  color: emerald500,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
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
    Color statusColor;
    Color statusBgColor;
    switch (row['status']) {
      case 'Active':
        statusColor = emerald600;
        statusBgColor = emerald50;
        break;
      case 'Idle':
        statusColor = Colors.amber.shade700;
        statusBgColor = const Color(0xFFFEF3C7);
        break;
      default:
        statusColor = Colors.grey.shade600;
        statusBgColor = const Color(0xFFF3F4F6);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(row['vehicleNo'], style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: emerald600)),
          ),
          Expanded(
            flex: 2,
            child: Text(row['owner'], style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          ),
          Expanded(
            flex: 1,
            child: Text(row['totalTrips'].toString(), style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
          ),
          Expanded(
            flex: 1,
            child: Text(row['totalTonnage'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
          ),
          Expanded(
            flex: 2,
            child: Text(row['lastActivity'], style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          ),
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusBgColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(row['status'], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: statusColor)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationButton(String label, bool isPrimary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey.shade700),
      ),
    );
  }
}

class BarChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final inboundData = [35, 45, 30, 55, 40, 25, 20];
    final outboundData = [25, 35, 25, 40, 30, 20, 15];
    
    final barWidth = 24.0;
    final groupWidth = barWidth * 2 + 8;
    final spacing = (size.width - 40 - groupWidth * days.length) / (days.length - 1);
    
    final maxValue = 60.0;
    final chartHeight = size.height - 40;
    
    // Draw grid lines
    final gridPaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;
    
    for (int i = 0; i <= 4; i++) {
      final y = i * chartHeight / 4;
      canvas.drawLine(Offset(30, y), Offset(size.width, y), gridPaint);
    }
    
    // Draw bars
    for (int i = 0; i < days.length; i++) {
      final x = 40 + i * (groupWidth + spacing);
      
      // Inbound bar
      final inboundHeight = (inboundData[i] / maxValue) * chartHeight;
      final inboundRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, chartHeight - inboundHeight, barWidth, inboundHeight),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(inboundRect, Paint()..color = const Color(0xFF10B981));
      
      // Outbound bar
      final outboundHeight = (outboundData[i] / maxValue) * chartHeight;
      final outboundRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x + barWidth + 4, chartHeight - outboundHeight, barWidth, outboundHeight),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(outboundRect, Paint()..color = const Color(0xFF6EE7B7));
      
      // X-axis labels
      final textPainter = TextPainter(
        text: TextSpan(
          text: days[i],
          style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + groupWidth / 2 - textPainter.width / 2, size.height - 20));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
