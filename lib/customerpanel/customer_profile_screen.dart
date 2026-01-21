import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class CustomerProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? customerData;

  const CustomerProfileScreen({super.key, this.customerData});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  static const Color emerald = Color(0xFF059669);
  static const Color emeraldLight = Color(0xFFD1FAE5);

  // Sample customer data
  late Map<String, dynamic> customer;

  final List<Map<String, dynamic>> recentWeighments = [
    {
      'rst': '#49281',
      'date': 'Oct 24,',
      'time': '14:30',
      'vehicle': 'KA-01-HH-1234',
      'material': 'Steel Scraps',
      'materialColor': const Color(0xFF6366F1),
      'weight': '12,450',
      'status': 'completed',
    },
    {
      'rst': '#49280',
      'date': 'Oct 23,',
      'time': '09:15',
      'vehicle': 'MH-04-AB-9876',
      'material': 'Coal',
      'materialColor': const Color(0xFF374151),
      'weight': '24,100',
      'status': 'completed',
    },
    {
      'rst': '#49278',
      'date': 'Oct 22,',
      'time': '16:45',
      'vehicle': 'TN-22-XY-4567',
      'material': 'Limestone',
      'materialColor': const Color(0xFF10B981),
      'weight': '18,350',
      'status': 'completed',
    },
    {
      'rst': '#49275',
      'date': 'Oct 21,',
      'time': '11:20',
      'vehicle': 'KA-53-ZZ-1122',
      'material': 'Iron Ore',
      'materialColor': const Color(0xFFEF4444),
      'weight': '31,000',
      'status': 'completed',
    },
  ];

  @override
  void initState() {
    super.initState();
    customer = widget.customerData ?? {
      'name': 'Acme Logistics Ltd.',
      'id': 'CUST-8291',
      'phone': '+1 (555) 019-2834',
      'email': 'accounts@acmelogis...',
      'address': '123 Industrial Park, Sector 4, Springfield, IL 62704',
      'totalWeighments': '1,245',
      'lastVisit': 'Oct 24',
      'lastVisitYear': '2023, 14:30 PM',
      'totalTonnage': '45.2k',
    };
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Customers",
      child: Container(
        color: const Color(0xFFF9FAFB),
        child: Column(
          children: [
            // Back Button Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: [
                  InkWell(
                    onTap: () {
                      Navigator.pushReplacementNamed(context, '/customers');
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: Row(
                        children: [
                          Icon(Icons.arrow_back, size: 18, color: Colors.grey.shade600),
                          const SizedBox(width: 8),
                          Text(
                            "Back to Customers",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Title and Badge
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Row(
                children: [
                  const Text(
                    "Customer Profile",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: emerald),
                    ),
                    child: const Text(
                      "Active Account",
                      style: TextStyle(
                        fontSize: 13,
                        color: emerald,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Main Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column - Customer Info
                    SizedBox(
                      width: 260,
                      child: Column(
                        children: [
                          // Customer Card
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Column(
                              children: [
                                // Avatar
                                Container(
                                  width: 90,
                                  height: 90,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: emerald, width: 3),
                                    color: Colors.white,
                                  ),
                                  child: ClipOval(
                                    child: Container(
                                      color: Colors.grey.shade200,
                                      child: Icon(
                                        Icons.business,
                                        size: 40,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Company Name
                                Text(
                                  customer['name'] ?? 'Acme Logistics Ltd.',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF111827),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "ID: ${customer['id'] ?? 'CUST-8291'}",
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade500,
                                  ),
                                ),

                                const SizedBox(height: 20),
                                const Divider(height: 1),
                                const SizedBox(height: 16),

                                // Contact Info
                                _buildContactRow(
                                  icon: Icons.phone_outlined,
                                  label: "PHONE",
                                  value: customer['phone'] ?? '+1 (555) 019-2834',
                                ),
                                const SizedBox(height: 14),
                                _buildContactRow(
                                  icon: Icons.email_outlined,
                                  label: "EMAIL",
                                  value: customer['email'] ?? 'accounts@acmelogis...',
                                ),
                                const SizedBox(height: 14),
                                _buildContactRow(
                                  icon: Icons.location_on_outlined,
                                  label: "BILLING ADDRESS",
                                  value: customer['address'] ?? '123 Industrial Park, Sector 4, Springfield, IL 62704',
                                  isMultiline: true,
                                ),

                                const SizedBox(height: 20),

                                // Edit Profile Button
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () {},
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: emerald,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      elevation: 0,
                                    ),
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    label: const Text(
                                      "Edit Profile",
                                      style: TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Map Preview
                          Container(
                            height: 140,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                children: [
                                  Container(
                                    color: const Color(0xFFE8F5E9),
                                    child: Center(
                                      child: Icon(
                                        Icons.map_outlined,
                                        size: 40,
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                  ),
                                  Center(
                                    child: Icon(
                                      Icons.location_on,
                                      size: 32,
                                      color: emerald,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 24),

                    // Right Column - Stats and Weighments
                    Expanded(
                      child: Column(
                        children: [
                          // Stats Cards Row
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  title: "Total Weighments",
                                  value: customer['totalWeighments'] ?? '1,245',
                                  icon: Icons.scale_outlined,
                                  iconBg: emeraldLight,
                                  iconColor: emerald,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildStatCard(
                                  title: "Last Visit",
                                  value: customer['lastVisit'] ?? 'Oct 24',
                                  subtitle: customer['lastVisitYear'] ?? '2023, 14:30 PM',
                                  icon: Icons.calendar_today_outlined,
                                  iconBg: const Color(0xFFF3F4F6),
                                  iconColor: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildStatCard(
                                  title: "Total Tonnage",
                                  value: customer['totalTonnage'] ?? '45.2k',
                                  subtitle: "Metric Tons",
                                  icon: Icons.inventory_2_outlined,
                                  iconBg: const Color(0xFFFEF3C7),
                                  iconColor: const Color(0xFFD97706),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // Recent Weighments Table
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Column(
                              children: [
                                // Table Header
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      const Text(
                                        "Recent Weighments",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF111827),
                                        ),
                                      ),
                                      const Spacer(),
                                      TextButton(
                                        onPressed: () {},
                                        child: Row(
                                          children: [
                                            Text(
                                              "View All History",
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: emerald,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(Icons.arrow_forward, size: 16, color: emerald),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Table Column Headers
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF9FAFB),
                                    border: Border(
                                      top: BorderSide(color: Colors.grey.shade200),
                                      bottom: BorderSide(color: Colors.grey.shade200),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      _buildTableHeader("RST #", flex: 2),
                                      _buildTableHeader("DATE &\nTIME", flex: 2),
                                      _buildTableHeader("VEHICLE", flex: 2),
                                      _buildTableHeader("MATERIAL", flex: 2),
                                      _buildTableHeader("NET\nWEIGHT", flex: 2),
                                      _buildTableHeader("STATUS", flex: 1),
                                    ],
                                  ),
                                ),

                                // Table Rows
                                ...recentWeighments.map((weighment) => _buildWeighmentRow(weighment)),

                                // Footer
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      "Showing recent 4 of 1,245 entries",
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildContactRow({
    required IconData icon,
    required String label,
    required String value,
    bool isMultiline = false,
  }) {
    return Row(
      crossAxisAlignment: isMultiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: emeraldLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: emerald),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF374151),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    String? subtitle,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
  }) {
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
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade400,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(String text, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade500,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _buildWeighmentRow(Map<String, dynamic> weighment) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade100),
        ),
      ),
      child: Row(
        children: [
          // RST #
          Expanded(
            flex: 2,
            child: Text(
              weighment['rst'],
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          // DATE & TIME
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  weighment['date'],
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
                Text(
                  weighment['time'],
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
          // VEHICLE
          Expanded(
            flex: 2,
            child: Text(
              weighment['vehicle'],
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF111827),
              ),
            ),
          ),
          // MATERIAL
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (weighment['materialColor'] as Color).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                weighment['material'],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: weighment['materialColor'],
                ),
              ),
            ),
          ),
          // NET WEIGHT
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  weighment['weight'],
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                Text(
                  "kg",
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
          // STATUS
          Expanded(
            flex: 1,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: emeraldLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check,
                size: 14,
                color: emerald,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
