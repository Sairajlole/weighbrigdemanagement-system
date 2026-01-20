import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({super.key});

  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  // Form Controllers
  final TextEditingController companyNameController = TextEditingController(text: 'Global Logistics Corp');
  final TextEditingController addressController = TextEditingController(text: '123 Industrial Parkway, Sector 4, Metro City, 56001');
  final TextEditingController taxIdController = TextEditingController(text: 'TX-9988-221');
  final TextEditingController bridgeNameController = TextEditingController(text: 'Main Exit WB-01');
  final TextEditingController uniqueCodeController = TextEditingController(text: 'WB-MC-001');
  final TextEditingController locationController = TextEditingController(text: '40.7128° N, 74.0060° W');

  // Dropdown values
  String selectedCountry = 'United States';
  String selectedTimezone = '(GMT-05:00) Eastern Time';
  String selectedCurrency = 'USD (\$)';
  String selectedLanguage = 'English (US)';
  String selectedDateFormat = 'DD/MM/YYYY';

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);

  @override
  void dispose() {
    companyNameController.dispose();
    addressController.dispose();
    taxIdController.dispose();
    bridgeNameController.dispose();
    uniqueCodeController.dispose();
    locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Settings",
      child: Column(
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
                        child: Row(
                          children: [
                            Icon(Icons.arrow_back, size: 16, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(
                              "Settings",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text("/", style: TextStyle(color: Colors.grey.shade400)),
                      const SizedBox(width: 8),
                      const Text(
                        "General Settings",
                        style: TextStyle(fontSize: 14, color: Color(0xFF374151)),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Title
                  const Text(
                    "General Settings",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    "Manage your organization details, local preferences, and weighbridge identification.",
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                  ),

                  const SizedBox(height: 32),

                  // ==================== COMPANY INFORMATION ====================
                  _sectionCard(
                    icon: Icons.business_outlined,
                    title: "Company Information",
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left side - Form fields
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _inputField("Company Name", companyNameController),
                              const SizedBox(height: 20),
                              _inputField("Address", addressController, maxLines: 2),
                              const SizedBox(height: 20),
                              _inputField("Tax Registration ID (VAT/GST)", taxIdController),
                            ],
                          ),
                        ),
                        const SizedBox(width: 40),
                        // Right side - Logo upload
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Company Logo",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF374151),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                height: 160,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF9FAFB),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFE5E7EB),
                                    style: BorderStyle.solid,
                                  ),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFD1FAE5),
                                          borderRadius: BorderRadius.circular(24),
                                        ),
                                        child: const Icon(
                                          Icons.cloud_upload_outlined,
                                          color: emerald600,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        "Click or drag to upload logo",
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF374151),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Recommended: 512x512px (PNG, JPG)",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ==================== REGIONAL SETTINGS ====================
                  _sectionCard(
                    icon: Icons.language_outlined,
                    title: "Regional Settings",
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _dropdownField(
                                "Country",
                                selectedCountry,
                                ["United States", "Canada", "United Kingdom", "India", "Australia"],
                                (value) => setState(() => selectedCountry = value!),
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: _dropdownField(
                                "Timezone",
                                selectedTimezone,
                                [
                                  "(GMT-05:00) Eastern Time",
                                  "(GMT-06:00) Central Time",
                                  "(GMT-07:00) Mountain Time",
                                  "(GMT-08:00) Pacific Time",
                                  "(GMT+05:30) India Standard Time",
                                ],
                                (value) => setState(() => selectedTimezone = value!),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Date Format",
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF374151),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      _radioOption("DD/MM/YYYY"),
                                      const SizedBox(width: 16),
                                      _radioOption("MM/DD/YYYY"),
                                      const SizedBox(width: 16),
                                      _radioOption("YYYY-MM-DD"),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: _dropdownField(
                                "Currency",
                                selectedCurrency,
                                ["USD (\$)", "EUR (€)", "GBP (£)", "INR (₹)", "CAD (\$)"],
                                (value) => setState(() => selectedCurrency = value!),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: 280,
                          child: _dropdownField(
                            "Default Language",
                            selectedLanguage,
                            ["English (US)", "English (UK)", "Spanish", "French", "German"],
                            (value) => setState(() => selectedLanguage = value!),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ==================== WEIGHBRIDGE IDENTITY ====================
                  _sectionCard(
                    icon: Icons.pin_drop_outlined,
                    title: "Weighbridge Identity",
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _inputField("Bridge Name", bridgeNameController),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: _inputField("Unique Code", uniqueCodeController),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _inputField("Location Coordinates", locationController),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 40,
                                    height: 40,
                                    margin: const EdgeInsets.only(top: 24),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF3F4F6),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(Icons.my_location, color: Colors.grey.shade600, size: 20),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          "Map Preview",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF374151),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 200,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Center(
                            child: Text(
                              "300×300",
                              style: TextStyle(
                                fontSize: 32,
                                color: Colors.grey.shade400,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 100), // Space for bottom bar
                ],
              ),
            ),
          ),

          // ==================== BOTTOM ACTION BAR ====================
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: const Border(
                top: BorderSide(color: Color(0xFFE5E7EB)),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.amber.shade600),
                    const SizedBox(width: 8),
                    Text(
                      "Changes will affect all generated tickets and reports.",
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    "Discard Changes",
                    style: TextStyle(
                      color: Color(0xFF374151),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Settings saved successfully!"),
                        backgroundColor: emerald600,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: emerald500,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    "Save Settings",
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: emerald600, size: 18),
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
            ],
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }

  Widget _inputField(String label, TextEditingController controller, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
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
      ],
    );
  }

  Widget _dropdownField(
    String label,
    String value,
    List<String> items,
    void Function(String?) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
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
              value: value,
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600),
              style: const TextStyle(fontSize: 14, color: Color(0xFF374151)),
              items: items.map((String item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(item),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _radioOption(String value) {
    final isSelected = selectedDateFormat == value;
    return GestureDetector(
      onTap: () => setState(() => selectedDateFormat = value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? emerald500 : Colors.grey.shade400,
                width: 2,
              ),
            ),
            child: isSelected
                ? Center(
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: emerald500,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: isSelected ? const Color(0xFF374151) : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
