import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final List<Map<String, String>> recentWeighments = [
    {
      "rst": "#RST - 8821",
      "vehicle": "KA-01-HH-1234",
      "customer": "Apex Constructions Ltd.",
      "material": "Sand",
      "weight": "24,500",
      "status": "Completed"
    },
    {
      "rst": "#RST - 8820",
      "vehicle": "MH-12-AB-9988",
      "customer": "Global Cement Works",
      "material": "Cement",
      "weight": "18,200",
      "status": "Completed"
    },
    {
      "rst": "#RST - 8819",
      "vehicle": "TN-22-XY-4567",
      "customer": "Urban Infra",
      "material": "Steel",
      "weight": "12,100",
      "status": "Completed"
    },
    {
      "rst": "--",
      "vehicle": "Processing...",
      "customer": "--",
      "material": "--",
      "weight": "--",
      "status": "Weighing"
    },
  ];

  final List<Map<String, dynamic>> subscriptionFeatures = [
    {"label": "AI OCR", "active": true},
    {"label": "SMS Alerts", "active": true},
    {"label": "ERP Integration", "active": true},
  ];

  static const Color emerald = Color(0xFF059669);

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Dashboard",
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Color(0xFFE5E7EB)),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  "Dashboard Home",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const Spacer(),

                // Search
                SizedBox(
                  width: 260,
                  height: 40,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: "Search RST, Vehicle...",
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFFF3F4F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 12),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.notifications_none, color: Colors.grey),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.chat_bubble_outline, color: Colors.grey),
                ),
              ],
            ),
          ),

          // Body Scroll
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome + Button
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              "Welcome back, Operator John",
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                            ),
                            SizedBox(height: 6),
                            Row(
                              children: [
                                CircleAvatar(radius: 4, backgroundColor: emerald),
                                SizedBox(width: 8),
                                Text(
                                  "Shift started at 08:00 AM • 12 Oct 2023",
                                  style: TextStyle(fontSize: 13, color: Colors.grey),
                                )
                              ],
                            )
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pushNamed(context, '/startWeighment');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: emerald,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text("Start New Weighment"),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // LEFT
                      Expanded(
                        child: Column(
                          children: [
                            // Stats Cards
                            Row(
                              children: [
                                Expanded(
                                  child: _statCard(
                                    title: "Today's Weighments",
                                    value: "42",
                                    subText: "↑12% from yesterday",
                                    icon: Icons.scale_outlined,
                                    iconBg: const Color(0xFFD1FAE5),
                                    iconColor: emerald,
                                    valueColor: Colors.black,
                                    subTextColor: emerald,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _statCard(
                                    title: "Pending Queue",
                                    value: "5",
                                    subText: "High traffic detected",
                                    icon: Icons.warning_amber_rounded,
                                    iconBg: const Color(0xFFFEF3C7),
                                    iconColor: const Color(0xFFD97706),
                                    valueColor: const Color(0xFFD97706),
                                    subTextColor: const Color(0xFFD97706),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _statCard(
                                    title: "Active Cameras",
                                    value: "4/4",
                                    subText: "All systems operational",
                                    icon: Icons.videocam_outlined,
                                    iconBg: const Color(0xFFDBEAFE),
                                    iconColor: const Color(0xFF2563EB),
                                    valueColor: Colors.black,
                                    subTextColor: emerald,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _statCard(
                                    title: "Scale Status",
                                    value: "Connected",
                                    subText: "Ping: 12ms",
                                    icon: Icons.wifi,
                                    iconBg: const Color(0xFFF3F4F6),
                                    iconColor: Colors.grey,
                                    valueColor: emerald,
                                    subTextColor: Colors.grey,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Recent Weighments Table
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    decoration: const BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(color: Color(0xFFF3F4F6)),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Text(
                                          "Recent Weighments",
                                          style: TextStyle(fontWeight: FontWeight.w800),
                                        ),
                                        const Spacer(),
                                        TextButton(
                                          onPressed: () {},
                                          child: const Text(
                                            "View All History",
                                            style: TextStyle(color: emerald),
                                          ),
                                        )
                                      ],
                                    ),
                                  ),

                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
                                      columns: const [
                                        DataColumn(label: Text("RST Number")),
                                        DataColumn(label: Text("Vehicle No.")),
                                        DataColumn(label: Text("Customer")),
                                        DataColumn(label: Text("Material")),
                                        DataColumn(label: Text("Net Weight")),
                                        DataColumn(label: Text("Status")),
                                      ],
                                      rows: recentWeighments.map((item) {
                                        final status = item["status"] ?? "";
                                        final weight = item["weight"] ?? "--";

                                        return DataRow(
                                          cells: [
                                            DataCell(Text(item["rst"] ?? "")),
                                            DataCell(Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF3F4F6),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(item["vehicle"] ?? ""),
                                            )),
                                            DataCell(Text(item["customer"] ?? "")),
                                            DataCell(Text(item["material"] ?? "")),
                                            DataCell(Row(
                                              children: [
                                                Text(weight),
                                                if (weight != "--")
                                                  const Padding(
                                                    padding: EdgeInsets.only(left: 4),
                                                    child: Text(
                                                      "kg",
                                                      style: TextStyle(fontSize: 11, color: Colors.grey),
                                                    ),
                                                  ),
                                              ],
                                            )),
                                            DataCell(
                                              Row(
                                                children: [
                                                  if (status == "Completed")
                                                    const Icon(Icons.check_circle, size: 18, color: emerald)
                                                  else
                                                    const Icon(Icons.timelapse, size: 18, color: Color(0xFFD97706)),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    status,
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w600,
                                                      color: status == "Completed"
                                                          ? emerald
                                                          : const Color(0xFFD97706),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),

                      const SizedBox(width: 16),

                      // RIGHT
                      SizedBox(
                        width: 280,
                        child: Column(
                          children: [
                            // Subscription Card
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Subscription",
                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    "Status",
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD1FAE5),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: const Text(
                                      "Enterprise Plan",
                                      style: TextStyle(
                                        color: emerald,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Column(
                                    children: subscriptionFeatures.map((f) {
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 10),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                f["label"],
                                                style: const TextStyle(color: Colors.grey),
                                              ),
                                            ),
                                            Container(
                                              width: 22,
                                              height: 22,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: (f["active"] == true) ? emerald : Colors.grey.shade400,
                                              ),
                                              child: const Icon(Icons.check, size: 14, color: Colors.white),
                                            )
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton(
                                      onPressed: () {},
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: const Text("MANAGE PLAN"),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Quick Tip
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Row(
                                    children: [
                                      Icon(Icons.lightbulb_outline, color: Color(0xFFD97706), size: 18),
                                      SizedBox(width: 8),
                                      Text(
                                        "Quick Tip",
                                        style: TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 10),
                                  Text(
                                    "Use Alt + N to quickly start a new weighment from any screen.",
                                    style: TextStyle(color: Colors.grey),
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
          )
        ],
      ),
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required String subText,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required Color valueColor,
    required Color subTextColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              )
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subText,
            style: TextStyle(fontSize: 11, color: subTextColor),
          ),
        ],
      ),
    );
  }
}
