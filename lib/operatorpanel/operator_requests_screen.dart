import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class OperatorRequestsScreen extends StatefulWidget {
  const OperatorRequestsScreen({super.key});

  @override
  State<OperatorRequestsScreen> createState() => _OperatorRequestsScreenState();
}

class _OperatorRequestsScreenState extends State<OperatorRequestsScreen> {
  int currentPage = 1;
  int totalPages = 3;

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  final List<Map<String, dynamic>> pendingRequests = [
    {'name': 'John Doe', 'email': 'john@logistics.co', 'phone': '+1 555-0123', 'companyCode': 'WMS-8821', 'date': 'Oct 24, 2023'},
    {'name': 'Sarah Smith', 'email': 'sarah@trucks.com', 'phone': '+1 555-0124', 'companyCode': 'TRK-9902', 'date': 'Oct 24, 2023'},
    {'name': 'Mike Johnson', 'email': 'mike@haul.net', 'phone': '+1 555-0125', 'companyCode': 'HAUL-211', 'date': 'Oct 23, 2023'},
    {'name': 'Emma Wilson', 'email': 'emma@cargo.io', 'phone': '+1 555-0126', 'companyCode': 'WMS-8824', 'date': 'Oct 23, 2023'},
    {'name': 'David Brown', 'email': 'david@freight.com', 'phone': '+1 555-0127', 'companyCode': 'FRT-551', 'date': 'Oct 22, 2023'},
  ];

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Operators",
      child: Container(
        color: const Color(0xFFF9FAFB),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const Text(
                "Operator Requests",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
              ),
              const SizedBox(height: 4),
              Text(
                "Manage and approve operator access requests for the Weighbridge system.",
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
              ),

              const SizedBox(height: 24),

              // Stats Cards
              Row(
                children: [
                  Expanded(child: _buildStatCard("PENDING REQUESTS", "12", "Requires attention", Icons.content_paste_outlined, const Color(0xFFFEF3C7), Colors.amber.shade600)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard("APPROVED TODAY", "4", "Processed successfully", Icons.check_circle_outline, emerald50, emerald500)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard("TOTAL OPERATORS", "142", "Active in system", Icons.people_outlined, emerald50, emerald500)),
                ],
              ),

              const SizedBox(height: 32),

              // Pending Review Section
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section Header
                    Row(
                      children: [
                        const Text(
                          "Pending Review",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: () {},
                          icon: Icon(Icons.filter_list, size: 16, color: Colors.grey.shade600),
                          label: Text("Filter", style: TextStyle(color: Colors.grey.shade600)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Table Header
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
                      ),
                      child: Row(
                        children: [
                          Expanded(flex: 2, child: Text("NAME", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                          Expanded(flex: 3, child: Text("EMAIL", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                          Expanded(flex: 2, child: Text("PHONE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                          Expanded(flex: 2, child: Text("COMPANY CODE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                          Expanded(flex: 2, child: Text("DATE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5))),
                          const SizedBox(width: 140, child: Text("ACTIONS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey, letterSpacing: 0.5))),
                        ],
                      ),
                    ),

                    // Table Rows
                    ...pendingRequests.map((request) => _buildRequestRow(request)),

                    const SizedBox(height: 20),

                    // Pagination
                    Row(
                      children: [
                        Text(
                          "Showing 1 to 5 of 12 results",
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            _buildPaginationButton("Previous", false),
                            const SizedBox(width: 8),
                            _buildPaginationButton("Next", true),
                          ],
                        ),
                      ],
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

  Widget _buildStatCard(String label, String value, String subtitle, IconData icon, Color bgColor, Color iconColor) {
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
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5),
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestRow(Map<String, dynamic> request) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              request['name'],
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF111827)),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              request['email'],
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              request['phone'],
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: emerald50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                request['companyCode'],
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: emerald600),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              request['date'],
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ),
          SizedBox(
            width: 140,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _handleApprove(request['name']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: emerald500,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      elevation: 0,
                    ),
                    child: const Text("Approve", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _handleReject(request['name']),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade500,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: BorderSide(color: Colors.red.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text("Reject", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationButton(String label, bool isNext) {
    return OutlinedButton(
      onPressed: () {
        setState(() {
          if (isNext && currentPage < totalPages) {
            currentPage++;
          } else if (!isNext && currentPage > 1) {
            currentPage--;
          }
        });
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.grey.shade700,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }

  void _handleApprove(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Approved request for $name'),
        backgroundColor: emerald500,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _handleReject(String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Reject Request"),
        content: Text("Are you sure you want to reject the request from $name?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Rejected request for $name'),
                  backgroundColor: Colors.red.shade500,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade500,
              foregroundColor: Colors.white,
            ),
            child: const Text("Reject"),
          ),
        ],
      ),
    );
  }
}
