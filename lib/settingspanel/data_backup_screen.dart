import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class DataBackupScreen extends StatefulWidget {
  const DataBackupScreen({super.key});

  @override
  State<DataBackupScreen> createState() => _DataBackupScreenState();
}

class _DataBackupScreenState extends State<DataBackupScreen> {
  // Automatic Backup Scheduling
  bool autoBackupEnabled = true;
  String backupFrequency = 'Daily';
  String backupTime = '02:00 AM';
  bool storageLocationLocal = true;
  final TextEditingController targetPathController = TextEditingController(text: '/var/www/wms/backups/');

  // Data Retention Policy
  String weighmentRecordsRetention = '5 Years';
  String auditSystemLogsRetention = '1 Year';
  String customerActivityDataRetention = '3 Years';

  // Data Management - Bulk Export
  bool exportWeighment = true;
  bool exportCustomers = false;
  bool exportAuditLogs = false;
  bool exportSettings = false;

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  @override
  void dispose() {
    targetPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Settings",
      child: Row(
        children: [
          // Left Sidebar
          Container(
            width: 200,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: emerald500,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("WMS Admin", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                          Text("System Settings", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),
                _sidebarItem(Icons.settings_outlined, "General Settings", false),
                _sidebarItem(Icons.people_outline, "User Management", false),
                _sidebarItem(Icons.monitor_weight_outlined, "Weighbridge Config", false),
                _sidebarItem(Icons.storage_outlined, "Data & Backup", true),
                _sidebarItem(Icons.history_outlined, "Audit Logs", false),
                const Spacer(),
                // User Info at Bottom
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: emerald50,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Center(
                          child: Text("AU", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: emerald600)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Admin User", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
                            Text("superadmin@wms.com", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          ],
                        ),
                      ),
                      Icon(Icons.logout_outlined, size: 18, color: Colors.grey.shade500),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: Container(
              color: const Color(0xFFF9FAFB),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    const Text(
                      "Data Retention & Backup Setup",
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Manage automated backups, data archival policies, and database health for system integrity.",
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                    ),

                    const SizedBox(height: 32),

                    // Automatic Backup Scheduling
                    _buildAutomaticBackupSection(),

                    const SizedBox(height: 24),

                    // Data Retention Policy and Data Management Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Data Retention Policy
                        Expanded(
                          child: _buildDataRetentionSection(),
                        ),
                        const SizedBox(width: 24),
                        // Data Management
                        Expanded(
                          child: _buildDataManagementSection(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String label, bool isActive) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {},
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isActive ? emerald50 : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isActive ? Border.all(color: emerald500) : null,
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: isActive ? emerald600 : Colors.grey.shade600),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isActive ? emerald600 : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAutomaticBackupSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: emerald500,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.cloud_upload_outlined, size: 14, color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Text(
                "Automatic Backup Scheduling",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
              ),
              const Spacer(),
              Text("Auto-Backup Enabled", style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(width: 8),
              Switch(
                value: autoBackupEnabled,
                onChanged: (val) => setState(() => autoBackupEnabled = val),
                activeColor: emerald500,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Backup Frequency, Time, Storage Location Row
          Row(
            children: [
              // Backup Frequency
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Backup Frequency", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: backupFrequency,
                                icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600),
                                style: const TextStyle(fontSize: 14, color: Color(0xFF374151)),
                                items: ['Daily', 'Weekly', 'Monthly'].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                                onChanged: (val) => setState(() => backupFrequency = val!),
                              ),
                            ),
                          ),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: emerald500,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Backup Time (UTC)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Backup Time (UTC)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(backupTime, style: const TextStyle(fontSize: 14, color: Color(0xFF374151))),
                          ),
                          Icon(Icons.access_time, size: 18, color: Colors.grey.shade500),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Storage Location
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Storage Location", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text("Local Directory", style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
                          ),
                          Switch(
                            value: storageLocationLocal,
                            onChanged: (val) => setState(() => storageLocationLocal = val),
                            activeColor: emerald500,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Target Path / Endpoint
          Text("Target Path / Endpoint", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: targetPathController,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: emerald500, width: 2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF374151),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text("Test"),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Manual Backup Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Manual Backup",
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Last successful backup: 2023-10-24 02:00:04",
                        style: TextStyle(fontSize: 12, color: emerald600),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text("Run Backup Now"),
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
          ),
        ],
      ),
    );
  }

  Widget _buildDataRetentionSection() {
    return Container(
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
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: emerald500,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.schedule_outlined, size: 14, color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Text(
                "Data Retention Policy",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Weighment Records
          _buildRetentionRow("Weighment Records", weighmentRecordsRetention, ['1 Year', '3 Years', '5 Years', '10 Years'], (val) => setState(() => weighmentRecordsRetention = val!)),
          const SizedBox(height: 16),

          // Audit & System Logs
          _buildRetentionRow("Audit & System Logs", auditSystemLogsRetention, ['6 Months', '1 Year', '3 Years', '5 Years'], (val) => setState(() => auditSystemLogsRetention = val!)),
          const SizedBox(height: 16),

          // Customer Activity Data
          _buildRetentionRow("Customer Activity Data", customerActivityDataRetention, ['1 Year', '3 Years', '5 Years', '10 Years'], (val) => setState(() => customerActivityDataRetention = val!)),

          const SizedBox(height: 24),

          // Warning
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber.shade700),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "WARNING",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber.shade800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Data deleted via retention policies cannot be recovered. Ensure off-site backups are configured before applying changes.",
                        style: TextStyle(fontSize: 12, color: Colors.amber.shade800, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRetentionRow(String label, String value, List<String> options, Function(String?) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF374151))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value,
                  icon: Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey.shade600),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
                  items: options.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: emerald500,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDataManagementSection() {
    return Container(
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
              Icon(Icons.swap_horiz, size: 20, color: emerald600),
              const SizedBox(width: 10),
              const Text(
                "Data Management",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Bulk Export
          Text("Bulk Export", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildExportCheckbox("Weighment", exportWeighment, (val) => setState(() => exportWeighment = val ?? false)),
              ),
              Expanded(
                child: _buildExportCheckbox("Customers", exportCustomers, (val) => setState(() => exportCustomers = val ?? false)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildExportCheckbox("Audit Logs", exportAuditLogs, (val) => setState(() => exportAuditLogs = val ?? false)),
              ),
              Expanded(
                child: _buildExportCheckbox("Settings", exportSettings, (val) => setState(() => exportSettings = val ?? false)),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Download CSV Export Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                foregroundColor: emerald600,
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: emerald500),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text("Download CSV Export", style: TextStyle(fontWeight: FontWeight.w500)),
            ),
          ),

          const SizedBox(height: 24),

          // Data Import
          Text("Data Import", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB), style: BorderStyle.solid),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: emerald50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.cloud_upload_outlined, size: 20, color: emerald500),
                ),
                const SizedBox(height: 12),
                Text(
                  "Drag and drop CSV or SQL files here",
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportCheckbox(String label, bool value, Function(bool?) onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: emerald500,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            side: BorderSide(color: value ? emerald500 : Colors.grey.shade400, width: 1.5),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
      ],
    );
  }
}
