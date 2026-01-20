import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class MaterialsScreen extends StatefulWidget {
  const MaterialsScreen({super.key});

  @override
  State<MaterialsScreen> createState() => _MaterialsScreenState();
}

class _MaterialsScreenState extends State<MaterialsScreen> {
  // Quick Add Material
  final TextEditingController materialNameController = TextEditingController();
  String selectedCategory = 'Aggregates';

  // Active Materials
  List<Map<String, dynamic>> materials = [
    {"name": "Type 1 Sub-base", "default": true, "status": true},
    {"name": "6F2 Capped Recycled", "default": false, "status": true},
    {"name": "Concrete Sand", "default": false, "status": false},
  ];

  // Global Display Settings
  bool enableOtherMaterial = true;
  String referenceVisibility = 'Always Visible';
  String sourceVisibility = 'Always Visible';
  String targetVisibility = 'Always Visible';

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);

  @override
  void dispose() {
    materialNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Settings",
      child: Column(
        children: [
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
                        child: Text("Settings", style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                      ),
                      _breadcrumbSeparator(),
                      Text("Weighbridge", style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                      _breadcrumbSeparator(),
                      const Text("Materials", style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Title
                  const Text(
                    "Materials Management",
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    "Configure and manage materials for the weighbridge system.",
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                  ),

                  const SizedBox(height: 32),

                  // Quick Add Material Card
                  _sectionCard(
                    title: "Quick Add Material",
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _inputField("Material Name", materialNameController, hint: "e.g. Recycled Aggregates"),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _dropdownField(
                            "Category",
                            selectedCategory,
                            ["Aggregates", "Sand", "Cement", "Steel", "Other"],
                            (val) => setState(() => selectedCategory = val!),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: ElevatedButton.icon(
                            onPressed: _addMaterial,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text("Add Material"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: emerald500,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Active Materials Table
                  _sectionCard(
                    title: "Active Materials",
                    child: Column(
                      children: [
                        // Table Header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
                          ),
                          child: Row(
                            children: [
                              SizedBox(width: 40, child: Text("ORDER", style: _headerStyle())),
                              Expanded(child: Text("MATERIAL NAME", style: _headerStyle().copyWith(color: emerald600))),
                              SizedBox(width: 100, child: Center(child: Text("DEFAULT", style: _headerStyle()))),
                              SizedBox(width: 100, child: Center(child: Text("STATUS", style: _headerStyle()))),
                              SizedBox(width: 80, child: Center(child: Text("ACTIONS", style: _headerStyle()))),
                            ],
                          ),
                        ),
                        // Table Rows
                        ...materials.asMap().entries.map((entry) {
                          final index = entry.key;
                          final material = entry.value;
                          return _materialRow(index, material);
                        }),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Global Display Settings
                  _sectionCard(
                    title: "Global Display Settings",
                    subtitle: "Manage how materials appear to operators in the weighbridge interface.",
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Enable Other Material Option
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Enable 'Other' Material Option",
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF374151)),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Allow operators to manually type in a material name if it's not in the list.",
                                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: enableOtherMaterial,
                              onChanged: (val) => setState(() => enableOtherMaterial = val),
                              activeColor: emerald500,
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // RST Display Rules
                        Row(
                          children: [
                            const Text(
                              "RST Display Rules",
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF374151)),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: emerald500,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: const Icon(Icons.info_outline, size: 12, color: Colors.white),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: _dropdownField(
                                "Reference (R)",
                                referenceVisibility,
                                ["Always Visible", "Hidden", "Conditional"],
                                (val) => setState(() => referenceVisibility = val!),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _dropdownField(
                                "Source (S)",
                                sourceVisibility,
                                ["Always Visible", "Hidden", "Conditional"],
                                (val) => setState(() => sourceVisibility = val!),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _dropdownField(
                                "Target (T)",
                                targetVisibility,
                                ["Always Visible", "Hidden", "Conditional"],
                                (val) => setState(() => targetVisibility = val!),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: const Border(top: BorderSide(color: Color(0xFFE5E7EB))),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4)),
              ],
            ),
            child: Row(
              children: [
                Text(
                  "Unsaved changes in material list.",
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("Discard Changes", style: TextStyle(color: Color(0xFF374151), fontWeight: FontWeight.w500)),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Materials saved successfully!"), backgroundColor: emerald600),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: emerald500,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Text("Save Materials", style: TextStyle(fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _breadcrumbSeparator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(">", style: TextStyle(color: Colors.grey.shade400)),
    );
  }

  TextStyle _headerStyle() {
    return TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5);
  }

  Widget _materialRow(int index, Map<String, dynamic> material) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          // Drag Handle
          SizedBox(
            width: 40,
            child: Icon(Icons.drag_indicator, size: 20, color: Colors.grey.shade400),
          ),
          // Material Name
          Expanded(
            child: Text(material["name"], style: const TextStyle(fontSize: 14, color: Color(0xFF374151))),
          ),
          // Default Radio
          SizedBox(
            width: 100,
            child: Center(
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: material["default"] ? emerald500 : Colors.grey.shade300, width: 2),
                ),
                child: material["default"]
                    ? Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: emerald500),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          // Status Toggle
          SizedBox(
            width: 100,
            child: Center(
              child: Switch(
                value: material["status"],
                onChanged: (val) {
                  setState(() {
                    materials[index]["status"] = val;
                  });
                },
                activeColor: emerald500,
              ),
            ),
          ),
          // Actions
          SizedBox(
            width: 80,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () {},
                  icon: Icon(Icons.edit_outlined, size: 18, color: Colors.grey.shade600),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      materials.removeAt(index);
                    });
                  },
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addMaterial() {
    if (materialNameController.text.isNotEmpty) {
      setState(() {
        materials.add({"name": materialNameController.text, "default": false, "status": true});
        materialNameController.clear();
      });
    }
  }

  Widget _sectionCard({required String title, String? subtitle, required Widget child}) {
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
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          ],
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _inputField(String label, TextEditingController controller, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: emerald500, width: 2)),
          ),
        ),
      ],
    );
  }

  Widget _dropdownField(String label, String value, List<String> items, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
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
              items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
