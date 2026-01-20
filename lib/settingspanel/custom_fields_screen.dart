import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class CustomFieldsScreen extends StatefulWidget {
  const CustomFieldsScreen({super.key});

  @override
  State<CustomFieldsScreen> createState() => _CustomFieldsScreenState();
}

class _CustomFieldsScreenState extends State<CustomFieldsScreen> {
  // Field States
  bool primaryFieldEnabled = true;
  bool secondaryFieldEnabled = false;
  bool tertiaryFieldEnabled = false;
  
  bool primaryMandatory = true;

  // Field Controllers
  final TextEditingController primaryLabelController = TextEditingController(text: 'Driver License No.');
  final TextEditingController primaryMaxLengthController = TextEditingController(text: '15');
  final TextEditingController secondaryLabelController = TextEditingController(text: 'Material Grade');
  final TextEditingController tertiaryLabelController = TextEditingController();

  String primaryDataType = 'Text Input';
  String secondaryDataType = 'Dropdown Selection';
  String tertiaryDataType = 'Text Input';

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  @override
  void dispose() {
    primaryLabelController.dispose();
    primaryMaxLengthController.dispose();
    secondaryLabelController.dispose();
    tertiaryLabelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Settings",
      child: Row(
        children: [
          // ==================== MAIN CONTENT ====================
          Expanded(
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
                        child: Text(
                          "Settings",
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text("/", style: TextStyle(color: Colors.grey.shade400)),
                      const SizedBox(width: 8),
                      const Text(
                        "Custom Fields",
                        style: TextStyle(fontSize: 14, color: Color(0xFF374151)),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Title
                  const Text(
                    "Custom Fields Configuration",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    "Add custom data points to your weighment process.",
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                  ),

                  const SizedBox(height: 24),

                  // Usage Information Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: emerald50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD1FAE5)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: emerald500,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.info_outline, color: Colors.white, size: 14),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Usage Information",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "These fields will appear in the Weighing Ticket and Reports. Customizing these allows for specialized data capture like Driver ID, Material Quality codes, or Vehicle inspection results. You can configure up to 3 additional fields.",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Primary Custom Field
                  _buildCustomFieldCard(
                    number: "01",
                    title: "Primary Custom Field",
                    enabled: primaryFieldEnabled,
                    onEnabledChanged: (val) => setState(() => primaryFieldEnabled = val),
                    labelController: primaryLabelController,
                    dataType: primaryDataType,
                    onDataTypeChanged: (val) => setState(() => primaryDataType = val!),
                    showMandatory: true,
                    isMandatory: primaryMandatory,
                    onMandatoryChanged: (val) => setState(() => primaryMandatory = val ?? false),
                    maxLengthController: primaryMaxLengthController,
                  ),

                  const SizedBox(height: 20),

                  // Secondary Custom Field
                  _buildCustomFieldCard(
                    number: "02",
                    title: "Secondary Custom Field",
                    enabled: secondaryFieldEnabled,
                    onEnabledChanged: (val) => setState(() => secondaryFieldEnabled = val),
                    labelController: secondaryLabelController,
                    dataType: secondaryDataType,
                    onDataTypeChanged: (val) => setState(() => secondaryDataType = val!),
                  ),

                  const SizedBox(height: 20),

                  // Tertiary Custom Field
                  _buildCustomFieldCard(
                    number: "03",
                    title: "Tertiary Custom Field",
                    enabled: tertiaryFieldEnabled,
                    onEnabledChanged: (val) => setState(() => tertiaryFieldEnabled = val),
                    labelController: tertiaryLabelController,
                    dataType: tertiaryDataType,
                    onDataTypeChanged: (val) => setState(() => tertiaryDataType = val!),
                  ),
                ],
              ),
            ),
          ),

          // ==================== LIVE PREVIEW PANEL ====================
          Container(
            width: 320,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                left: BorderSide(color: Color(0xFFE5E7EB)),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: emerald500,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "LIVE FIELD PREVIEW",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: emerald500,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          "REAL-TIME",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Standard Form Fields
                  Text(
                    "STANDARD FORM FIELDS",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade400,
                      letterSpacing: 0.5,
                    ),
                  ),

                  const SizedBox(height: 12),

                  _previewField("VEHICLE NUMBER", "", enabled: false),
                  const SizedBox(height: 16),
                  _previewField("GROSS WEIGHT (KG)", "", enabled: false),

                  const SizedBox(height: 32),

                  // Configured Custom Fields
                  Text(
                    "CONFIGURED CUSTOM FIELDS",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade400,
                      letterSpacing: 0.5,
                    ),
                  ),

                  const SizedBox(height: 12),

                  if (primaryFieldEnabled)
                    Column(
                      children: [
                        _previewField(
                          "${primaryLabelController.text} *",
                          "Enter license...",
                          enabled: true,
                          hasCheck: true,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),

                  _previewField("Entry Date", "Select date...", enabled: true, hasCalendar: true),

                  const SizedBox(height: 32),

                  // Tip
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lightbulb_outline, size: 16, color: Colors.amber.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Tip: Keep labels short and descriptive for better clarity on",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber.shade800,
                            ),
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
    );
  }

  Widget _buildCustomFieldCard({
    required String number,
    required String title,
    required bool enabled,
    required Function(bool) onEnabledChanged,
    required TextEditingController labelController,
    required String dataType,
    required Function(String?) onDataTypeChanged,
    bool showMandatory = false,
    bool isMandatory = false,
    Function(bool?)? onMandatoryChanged,
    TextEditingController? maxLengthController,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: enabled ? emerald50 : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    number,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: enabled ? emerald600 : Colors.grey.shade400,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
              const Spacer(),
              Text(
                "Enable Field",
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: enabled,
                onChanged: onEnabledChanged,
                activeColor: emerald500,
              ),
            ],
          ),

          if (enabled) ...[
            const SizedBox(height: 24),

            // Field Label and Data Type
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Field Label",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: labelController,
                        style: const TextStyle(fontSize: 14),
                        onChanged: (_) => setState(() {}),
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
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Data Type",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: dataType,
                            isExpanded: true,
                            icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600),
                            style: const TextStyle(fontSize: 14, color: Color(0xFF374151)),
                            items: ["Text Input", "Dropdown Selection", "Number Input", "Date Picker"]
                                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                                .toList(),
                            onChanged: onDataTypeChanged,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (showMandatory) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: isMandatory,
                      onChanged: onMandatoryChanged,
                      activeColor: emerald500,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Mark as Mandatory",
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(width: 32),
                  Text(
                    "Max Length:",
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 60,
                    child: TextField(
                      controller: maxLengthController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 14),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _previewField(String label, String placeholder, {bool enabled = true, bool hasCheck = false, bool hasCalendar = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: enabled ? Colors.white : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled ? emerald500 : const Color(0xFFE5E7EB),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  placeholder,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
              if (hasCheck)
                Icon(Icons.check, size: 16, color: emerald500),
              if (hasCalendar)
                Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey.shade400),
            ],
          ),
        ),
      ],
    );
  }
}
