import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  String selectedUser = 'All Users';
  String selectedActionType = 'All Actions';

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  final List<Map<String, dynamic>> auditLogs = [
    {
      'timestamp': '2023-10-27 14:30:22',
      'userInitials': 'JS',
      'userName': 'J. Smith',
      'userColor': const Color(0xFF3B82F6),
      'action': 'Manual Override',
      'actionColor': const Color(0xFFFBBF24),
      'actionIcon': Icons.warning_amber_rounded,
      'details': 'Changed gross weight 4500kg -> 4458kg. Reason: Debris on scale',
      'detailsHighlight': null,
      'ipAddress': '192.168.1.45',
    },
    {
      'timestamp': '2023-10-27 14:15:05',
      'userInitials': 'AD',
      'userName': 'Admin',
      'userColor': const Color(0xFFEF4444),
      'action': 'Login',
      'actionColor': const Color(0xFF10B981),
      'actionIcon': Icons.login,
      'details': 'Successful login via Web Portal',
      'detailsHighlight': null,
      'ipAddress': '192.168.1.10',
    },
    {
      'timestamp': '2023-10-27 13:45:12',
      'userInitials': 'KD',
      'userName': 'K. Doe',
      'userColor': const Color(0xFFF59E0B),
      'action': 'Weighing',
      'actionColor': const Color(0xFF3B82F6),
      'actionIcon': Icons.scale,
      'details': 'Vehicle AB-123-CD captured. Net: 12,400kg',
      'detailsHighlight': null,
      'ipAddress': '192.168.1.42',
    },
    {
      'timestamp': '2023-10-27 12:30:05',
      'userInitials': 'SY',
      'userName': 'System',
      'userColor': const Color(0xFF6B7280),
      'action': 'Backup',
      'actionColor': const Color(0xFF6B7280),
      'actionIcon': Icons.backup,
      'details': 'Automated database backup completed successfully (245MB)',
      'detailsHighlight': null,
      'ipAddress': 'Localhost',
    },
    {
      'timestamp': '2023-10-27 11:20:18',
      'userInitials': 'JS',
      'userName': 'J. Smith',
      'userColor': const Color(0xFF3B82F6),
      'action': 'Calibration',
      'actionColor': const Color(0xFF8B5CF6),
      'actionIcon': Icons.tune,
      'details': 'Zero point calibration executed on Scale 1',
      'detailsHighlight': null,
      'ipAddress': '192.168.1.45',
    },
    {
      'timestamp': '2023-10-27 10:05:33',
      'userInitials': 'KD',
      'userName': 'K. Doe',
      'userColor': const Color(0xFFF59E0B),
      'action': 'Error',
      'actionColor': const Color(0xFFEF4444),
      'actionIcon': Icons.error_outline,
      'details': 'Connection timeout on Scale 2 sensor interface',
      'detailsHighlight': 'Connection timeout',
      'ipAddress': '192.168.1.42',
    },
    {
      'timestamp': '2023-10-27 09:15:22',
      'userInitials': 'AD',
      'userName': 'Admin',
      'userColor': const Color(0xFFEF4444),
      'action': 'Config Change',
      'actionColor': const Color(0xFF6B7280),
      'actionIcon': Icons.settings,
      'details': 'Updated tare weight settings for fleet category B',
      'detailsHighlight': null,
      'ipAddress': '192.168.1.10',
    },
    {
      'timestamp': '2023-10-27 08:30:45',
      'userInitials': 'JS',
      'userName': 'J. Smith',
      'userColor': const Color(0xFF3B82F6),
      'action': 'Weighing',
      'actionColor': const Color(0xFF3B82F6),
      'actionIcon': Icons.scale,
      'details': 'Vehicle XY-987-ZZ captured. Net: 8,200kg',
      'detailsHighlight': null,
      'ipAddress': '192.168.1.45',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Audit Log",
      child: Container(
        color: const Color(0xFFF9FAFB),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Audit Log",
                                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Track and monitor all system activities and user interactions.",
                                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text("Export Log (CSV/Excel)"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: emerald500,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Filters
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
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF9FAFB),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFE5E7EB)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey.shade500),
                                      const SizedBox(width: 8),
                                      Text("Select dates...", style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          // User
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("USER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF9FAFB),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFE5E7EB)),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: selectedUser,
                                      isExpanded: true,
                                      icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade500),
                                      style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
                                      items: ['All Users', 'J. Smith', 'Admin', 'K. Doe', 'System']
                                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                          .toList(),
                                      onChanged: (val) => setState(() => selectedUser = val!),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Action Type
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("ACTION TYPE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF9FAFB),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFE5E7EB)),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: selectedActionType,
                                      isExpanded: true,
                                      icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade500),
                                      style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
                                      items: ['All Actions', 'Login', 'Weighing', 'Backup', 'Calibration', 'Error', 'Config Change', 'Manual Override']
                                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                          .toList(),
                                      onChanged: (val) => setState(() => selectedActionType = val!),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Buttons
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("", style: TextStyle(fontSize: 10)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  ElevatedButton(
                                    onPressed: () {},
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF1F2937),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      elevation: 0,
                                    ),
                                    child: const Text("Apply Filters"),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed: () {},
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.grey.shade700,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    child: const Text("Reset"),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Audit Log Table
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        children: [
                          // Table Header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF9FAFB),
                              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                            ),
                            child: Row(
                              children: [
                                _tableHeader("TIMESTAMP", flex: 2),
                                _tableHeader("USER", flex: 2),
                                _tableHeader("ACTION", flex: 2),
                                _tableHeader("DETAILS", flex: 4),
                                _tableHeader("IP ADDRESS", flex: 2),
                              ],
                            ),
                          ),
                          // Table Rows
                          ...auditLogs.asMap().entries.map((entry) {
                            final index = entry.key;
                            final log = entry.value;
                            final isLast = index == auditLogs.length - 1;
                            return _buildLogRow(log, isLast);
                          }),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Pagination
                    Row(
                      children: [
                        Text(
                          "Showing 1 to 8 of 1,248 results",
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                        ),
                        const Spacer(),
                        OutlinedButton(
                          onPressed: () {},
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey.shade500,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          child: const Text("Previous"),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () {},
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey.shade700,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          child: const Text("Next"),
                        ),
                      ],
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

  Widget _tableHeader(String text, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildLogRow(Map<String, dynamic> log, bool isLast) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          // Timestamp
          Expanded(
            flex: 2,
            child: Text(
              log['timestamp'],
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontFamily: 'monospace'),
            ),
          ),
          // User
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: log['userColor'].withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      log['userInitials'],
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: log['userColor']),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(log['userName'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
              ],
            ),
          ),
          // Action
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: log['actionColor'].withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(log['actionIcon'], size: 14, color: log['actionColor']),
                      const SizedBox(width: 6),
                      Text(
                        log['action'],
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: log['actionColor']),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Details
          Expanded(
            flex: 4,
            child: log['detailsHighlight'] != null
                ? RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      children: [
                        TextSpan(
                          text: log['detailsHighlight'],
                          style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w500),
                        ),
                        TextSpan(
                          text: log['details'].toString().replaceFirst(log['detailsHighlight'], ''),
                        ),
                      ],
                    ),
                  )
                : Text(
                    log['details'],
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
          ),
          // IP Address
          Expanded(
            flex: 2,
            child: Text(
              log['ipAddress'],
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
