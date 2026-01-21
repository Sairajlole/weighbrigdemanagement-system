import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class CustomReportsScreen extends StatefulWidget {
  const CustomReportsScreen({super.key});

  @override
  State<CustomReportsScreen> createState() => _CustomReportsScreenState();
}

class _CustomReportsScreenState extends State<CustomReportsScreen> {
  int currentStep = 3; // Fields step
  String searchFields = '';

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  // Available fields with expanded state
  Map<String, bool> expandedSections = {
    'Ticket Info': true,
    'Weight Data': true,
    'Time & Date': true,
  };

  // Available fields
  final Map<String, List<Map<String, dynamic>>> availableFields = {
    'Ticket Info': [
      {'name': 'Ticket ID', 'selected': true},
      {'name': 'Vehicle Number', 'selected': true},
      {'name': 'Transporter', 'selected': false},
    ],
    'Weight Data': [
      {'name': 'Gross Weight', 'selected': false},
      {'name': 'Tare Weight', 'selected': false},
      {'name': 'Net Weight', 'selected': true},
    ],
    'Time & Date': [
      {'name': 'Time In', 'selected': false},
      {'name': 'Time Out', 'selected': false},
    ],
  };

  // Report columns with labels and aggregations
  final List<Map<String, dynamic>> reportColumns = [
    {'field': 'Ticket ID', 'label': 'ID', 'aggregation': 'None'},
    {'field': 'Vehicle Number', 'label': 'Vehicle', 'aggregation': 'None'},
    {'field': 'Net Weight', 'label': 'Net Weight (kg)', 'aggregation': 'Sum'},
  ];

  // Preview data
  final List<Map<String, String>> previewData = [
    {'id': '#T-1824', 'vehicle': 'KA-01-EA-1234', 'netWt': '12, 580'},
    {'id': '#T-1825', 'vehicle': 'MH-04-CD-9876', 'netWt': '24, 180'},
    {'id': '#T-1826', 'vehicle': 'KA-55-Z-5555', 'netWt': '8, 450'},
    {'id': '#T-1827', 'vehicle': 'TN-22-AX-1122', 'netWt': '18, 280'},
    {'id': '#T-1828', 'vehicle': 'AP-09-Q-5344', 'netWt': '14, 380'},
    {'id': '#T-1829', 'vehicle': 'KA-05-MM-9999', 'netWt': '22, 880'},
  ];

  // Saved reports
  final List<Map<String, dynamic>> savedReports = [
    {'icon': Icons.calendar_month, 'iconColor': const Color(0xFF3B82F6), 'title': 'Monthly Weighbridge Summary', 'description': 'Detailed log of all weigh-ins for the current month aggregated by...', 'lastRun': '2 hours ago'},
    {'icon': Icons.bar_chart, 'iconColor': Colors.red.shade400, 'title': 'Truck Turnaround Times', 'description': 'Average time spent in premises per vehicle type over the last 30 days.', 'lastRun': 'Yesterday'},
    {'icon': Icons.pie_chart, 'iconColor': Colors.red.shade400, 'title': 'Material Distribution', 'description': 'Breakdown of inbound materials by weight percentage.', 'lastRun': '3 days ago'},
    {'icon': Icons.fact_check_outlined, 'iconColor': Colors.red.shade400, 'title': 'Weekly Supplier Audit', 'description': 'Automated report sent to QA department every Friday.', 'lastRun': 'Weekly'},
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
                        Text("Custom Builder", style: TextStyle(fontSize: 13, color: emerald600, fontWeight: FontWeight.w500)),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Header Row
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Custom Report Builder",
                                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Design custom analytics from your weighbridge data.",
                                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {},
                          icon: Icon(Icons.history, size: 16, color: Colors.grey.shade700),
                          label: const Text("Recent Drafts"),
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
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text("Create New Report"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: emerald500,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Step Wizard
                    Row(
                      children: [
                        _buildStepCircle(1, "Basics", true, false),
                        _buildStepLine(true),
                        _buildStepCircle(2, "Data Source", true, false),
                        _buildStepLine(true),
                        _buildStepCircle(3, "Fields", false, true),
                        _buildStepLine(false),
                        _buildStepCircle(4, "Filters", false, false),
                        _buildStepLine(false),
                        _buildStepCircle(5, "Visualize", false, false),
                        _buildStepLine(false),
                        _buildStepCircle(6, "Schedule", false, false),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text("Auto-saved", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                            Text("2m ago", style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Main Builder Area
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Available Fields Panel
                        Container(
                          width: 200,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("AVAILABLE FIELDS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
                                    const SizedBox(height: 12),
                                    // Search
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF9FAFB),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFE5E7EB)),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.search, size: 14, color: Colors.grey.shade400),
                                          const SizedBox(width: 6),
                                          Text("Search fields...", style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Field Groups
                              ...availableFields.entries.map((entry) => _buildFieldGroup(entry.key, entry.value)),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Report Columns Panel
                        Expanded(
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
                                    const Text("Report Columns", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                                    const Spacer(),
                                    Text("Drag fields here to add columns", style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                // Column Rows
                                ...reportColumns.map((col) => _buildColumnRow(col)),
                                const SizedBox(height: 16),
                                // Drop Zone
                                Container(
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFAFAFA),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFE5E7EB), style: BorderStyle.solid),
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: emerald50,
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: Icon(Icons.add, size: 18, color: emerald500),
                                        ),
                                        const SizedBox(height: 6),
                                        Text("Drop next field here", style: TextStyle(fontSize: 12, color: emerald600)),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                // Footer Buttons
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: () {},
                                      child: Text("Back", style: TextStyle(color: Colors.grey.shade600)),
                                    ),
                                    const Spacer(),
                                    OutlinedButton(
                                      onPressed: () {},
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.grey.shade700,
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: const Text("Save Draft"),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: () {},
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: emerald500,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        elevation: 0,
                                      ),
                                      child: Row(
                                        children: const [
                                          Text("Next: Filters"),
                                          SizedBox(width: 4),
                                          Icon(Icons.arrow_forward, size: 16),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Live Preview Panel
                        Container(
                          width: 260,
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
                                  Text("LIVE PREVIEW", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
                                  const Spacer(),
                                  Text("Refresh Data", style: TextStyle(fontSize: 11, color: emerald600, fontWeight: FontWeight.w500)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Preview Table
                              _buildPreviewTable(),
                              const SizedBox(height: 16),
                              // Visual Preview
                              Text("VISUAL PREVIEW", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
                              const SizedBox(height: 12),
                              _buildVisualPreview(),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // Saved Reports Section
                    Row(
                      children: [
                        const Text("Saved Reports", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                        const Spacer(),
                        Container(
                          width: 200,
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.search, size: 16, color: Colors.grey.shade400),
                              const SizedBox(width: 8),
                              Text("Search saved reports...", style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Saved Reports Grid
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: savedReports.map((report) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: _buildSavedReportCard(report),
                        ),
                      )).toList(),
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

  Widget _buildStepCircle(int number, String label, bool isCompleted, bool isActive) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isCompleted ? emerald500 : (isActive ? Colors.white : const Color(0xFFF3F4F6)),
            borderRadius: BorderRadius.circular(14),
            border: isActive ? Border.all(color: emerald500, width: 2) : null,
          ),
          child: Center(
            child: isCompleted 
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : Text(
                  number.toString(), 
                  style: TextStyle(
                    fontSize: 12, 
                    fontWeight: FontWeight.w600, 
                    color: isActive ? emerald600 : Colors.grey.shade500,
                  ),
                ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label, 
          style: TextStyle(
            fontSize: 13, 
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500, 
            color: isActive || isCompleted ? const Color(0xFF111827) : Colors.grey.shade500,
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(bool isCompleted) {
    return Container(
      width: 50,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: isCompleted ? emerald500 : const Color(0xFFE5E7EB),
    );
  }

  Widget _buildFieldGroup(String title, List<Map<String, dynamic>> fields) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            border: Border(
              top: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          child: Row(
            children: [
              Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
              const Spacer(),
              Text("All", style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
            ],
          ),
        ),
        ...fields.map((field) => _buildFieldItem(field)),
      ],
    );
  }

  Widget _buildFieldItem(Map<String, dynamic> field) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: field['selected'] ? emerald500 : Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: field['selected'] ? emerald500 : const Color(0xFFD1D5DB)),
            ),
            child: field['selected'] 
              ? const Icon(Icons.check, size: 12, color: Colors.white)
              : null,
          ),
          const SizedBox(width: 10),
          Text(field['name'], style: const TextStyle(fontSize: 13, color: Color(0xFF374151))),
          const Spacer(),
          Icon(Icons.schedule, size: 14, color: Colors.grey.shade400),
        ],
      ),
    );
  }

  Widget _buildColumnRow(Map<String, dynamic> col) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          // Field column
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("FIELD", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.grey.shade400, letterSpacing: 0.3)),
                const SizedBox(height: 4),
                Text(col['field'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
              ],
            ),
          ),
          // Label column
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("LABEL", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.grey.shade400, letterSpacing: 0.3)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Text(col['label'], style: const TextStyle(fontSize: 12, color: Color(0xFF374151))),
                ),
              ],
            ),
          ),
          // Aggregation column
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("AGGREGATION", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.grey.shade400, letterSpacing: 0.3)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(col['aggregation'], style: const TextStyle(fontSize: 12, color: Color(0xFF374151))),
                      const SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey.shade500),
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

  Widget _buildPreviewTable() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: Row(
            children: [
              SizedBox(width: 50, child: Text("ID", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500))),
              Expanded(child: Text("VEHICLE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500))),
              SizedBox(width: 60, child: Text("NET WT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500), textAlign: TextAlign.right)),
            ],
          ),
        ),
        // Rows
        ...previewData.map((row) => Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
          ),
          child: Row(
            children: [
              SizedBox(width: 50, child: Text(row['id']!, style: TextStyle(fontSize: 11, color: Colors.grey.shade500))),
              Expanded(child: Text(row['vehicle']!, style: const TextStyle(fontSize: 11, color: Color(0xFF374151)))),
              SizedBox(width: 60, child: Text(row['netWt']!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF374151)), textAlign: TextAlign.right)),
            ],
          ),
        )),
        // Total
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Text("Total (6 rows)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const Spacer(),
              Text("99,550", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: emerald600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVisualPreview() {
    return SizedBox(
      height: 70,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(6, (index) {
          final heights = [0.45, 0.65, 0.35, 0.55, 0.4, 0.7];
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 70 * heights[index],
              decoration: BoxDecoration(
                color: emerald50,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSavedReportCard(Map<String, dynamic> report) {
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
          Icon(report['icon'], size: 22, color: report['iconColor']),
          const SizedBox(height: 12),
          Text(report['title'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
          const SizedBox(height: 4),
          Text(
            report['description'],
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500, height: 1.4),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.access_time, size: 12, color: Colors.grey.shade400),
              const SizedBox(width: 4),
              Text("Last run: ${report['lastRun']}", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text("Edit", style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: emerald50,
                    foregroundColor: emerald600,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    elevation: 0,
                  ),
                  child: const Text("Run Now", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
