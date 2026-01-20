import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class WeighbridgeScreen extends StatefulWidget {
  const WeighbridgeScreen({super.key});

  @override
  State<WeighbridgeScreen> createState() => _WeighbridgeScreenState();
}

class _WeighbridgeScreenState extends State<WeighbridgeScreen> {
  // Weight Units
  bool isMetric = true;
  String decimalPrecision = '0.000 (3 places)';
  String displayRefreshRate = '200ms (Stable)';

  // Weight Capture Settings
  final TextEditingController minCapacityController = TextEditingController(text: '20');
  final TextEditingController maxCapacityController = TextEditingController(text: '60000');
  final TextEditingController stabilityDurationController = TextEditingController(text: '1500');
  final TextEditingController zeroToleranceController = TextEditingController(text: '5');

  // Weighment Rules
  bool allowManualWeightEntry = false;
  bool requireTareFirst = true;
  String storedTareValidity = '24 Hours';
  String overloadAction = 'Block Weighment';

  // Scale Connection
  String interfaceType = 'Serial/RS232';
  String comPort = 'COM3 (Scale Indicator)';
  String baudRate = '9600';
  String dataBits = '8';
  String parity = 'None';

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  @override
  void dispose() {
    minCapacityController.dispose();
    maxCapacityController.dispose();
    stabilityDurationController.dispose();
    zeroToleranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Settings",
      child: Row(
        children: [
          // Left Sidebar - System Settings
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("SYSTEM SETTINGS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey, letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Text("V4.2.0-WB-0", style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                    ],
                  ),
                ),
                _sidebarItem(Icons.straighten, "Weight Units", true),
                _sidebarItem(Icons.download_outlined, "Weight Capture", false),
                _sidebarItem(Icons.rule_outlined, "Weighment Rules", false),
                _sidebarItem(Icons.cable_outlined, "Scale Connection", false),
                _sidebarItem(Icons.tune_outlined, "Calibration", false),
              ],
            ),
          ),

          // Main Content
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
                            const Text("Weighbridge Scale & Rules", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text("Configure hardware connectivity parameters and core weighing business logic.", style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () {},
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF374151),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text("Discard"),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Changes saved!"), backgroundColor: emerald600),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: emerald500,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text("Save Changes"),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Weight Units & Display
                  _sectionTitle("Weight Units & Display"),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _unitCard("Metric (kg/t)", "Global standard (Kilograms and Tonnes). Recommended for international trade compliance.", Icons.scale, isMetric, () => setState(() => isMetric = true))),
                      const SizedBox(width: 16),
                      Expanded(child: _unitCard("Imperial (lb/st)", "Pounds and Stones. Used primarily in specific North American and regional markets.", Icons.monitor_weight_outlined, !isMetric, () => setState(() => isMetric = false))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _dropdown("DECIMAL PRECISION", decimalPrecision, ['0 (Whole)', '0.0 (1 place)', '0.00 (2 places)', '0.000 (3 places)'], (v) => setState(() => decimalPrecision = v!))),
                      const SizedBox(width: 16),
                      Expanded(child: _dropdown("DISPLAY REFRESH RATE", displayRefreshRate, ['100ms (Fast)', '200ms (Stable)', '500ms (Battery Saver)'], (v) => setState(() => displayRefreshRate = v!))),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Weight Capture Settings
                  _sectionTitle("Weight Capture Settings"),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _inputWithUnit("MIN CAPACITY", minCapacityController, "kg")),
                      const SizedBox(width: 16),
                      Expanded(child: _inputWithUnit("MAX CAPACITY", maxCapacityController, "kg")),
                      const SizedBox(width: 16),
                      Expanded(child: _inputWithUnit("STABILITY DURATION", stabilityDurationController, "ms")),
                      const SizedBox(width: 16),
                      Expanded(child: _inputWithUnit("ZERO TOLERANCE", zeroToleranceController, "kg")),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Weighment Rules
                  _sectionTitle("Weighment Rules"),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      children: [
                        _toggleRow("Allow Manual Weight Entry", "Enables the operator to override scale readings manually.", allowManualWeightEntry, (v) => setState(() => allowManualWeightEntry = v)),
                        const Divider(height: 32),
                        _toggleRow("Require Tare First", "Forces a tare weighment before any gross weighment can occur.", requireTareFirst, (v) => setState(() => requireTareFirst = v)),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(child: _dropdown("STORED TARE VALIDITY", storedTareValidity, ['1 Hour', '12 Hours', '24 Hours', '48 Hours', 'No Expiry'], (v) => setState(() => storedTareValidity = v!))),
                            const SizedBox(width: 16),
                            Expanded(child: _dropdown("OVERLOAD ACTION", overloadAction, ['Block Weighment', 'Show Warning', 'Allow with Note'], (v) => setState(() => overloadAction = v!))),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Scale Connection
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _sectionTitle("Scale Connection"),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(color: emerald50, borderRadius: BorderRadius.circular(12)),
                                  child: Row(
                                    children: [
                                      Container(width: 8, height: 8, decoration: BoxDecoration(color: emerald500, borderRadius: BorderRadius.circular(4))),
                                      const SizedBox(width: 6),
                                      const Text("CONNECTED", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: emerald600)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: _dropdown("INTERFACE TYPE", interfaceType, ['Serial/RS232', 'TCP/IP', 'USB'], (v) => setState(() => interfaceType = v!))),
                                      const SizedBox(width: 16),
                                      Expanded(child: _dropdown("COM PORT", comPort, ['COM1', 'COM2', 'COM3 (Scale Indicator)', 'COM4'], (v) => setState(() => comPort = v!))),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(child: _dropdown("BAUD RATE", baudRate, ['4800', '9600', '19200', '38400', '115200'], (v) => setState(() => baudRate = v!))),
                                      const SizedBox(width: 16),
                                      Expanded(child: _dropdown("DATA BITS", dataBits, ['7', '8'], (v) => setState(() => dataBits = v!))),
                                      const SizedBox(width: 16),
                                      Expanded(child: _dropdown("PARITY", parity, ['None', 'Even', 'Odd'], (v) => setState(() => parity = v!))),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      // Data Stream Monitor
                      SizedBox(
                        width: 200,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text("DATA STREAM MONITOR", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
                                const Spacer(),
                                TextButton(
                                  onPressed: () {},
                                  child: const Text("CLEAR", style: TextStyle(fontSize: 11, color: emerald600)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 120,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1F2937),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _streamLine("[14:02:12] ST,GS, + 01042.40 kg"),
                                  _streamLine("[14:02:12] ST,GS, + 01240.40 kg"),
                                  _streamLine("[14:02:13] ST,GS, + 01240.40 kg"),
                                  _streamLine("[14:02:13] ST,GS, + 01240.08 kg"),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {},
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: emerald500,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text("Test Connection"),
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
              border: isActive ? Border.all(color: emerald500, width: 1) : null,
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: isActive ? emerald600 : Colors.grey.shade600),
                const SizedBox(width: 10),
                Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isActive ? emerald600 : Colors.grey.shade700)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)));
  }

  Widget _unitCard(String title, String description, IconData icon, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? emerald500 : const Color(0xFFE5E7EB), width: isSelected ? 2 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected ? emerald50 : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: isSelected ? emerald600 : Colors.grey.shade600, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isSelected ? emerald600 : const Color(0xFF374151))),
                      if (isSelected) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(color: emerald500, shape: BoxShape.circle),
                          child: const Icon(Icons.check, size: 14, color: Colors.white),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(description, style: TextStyle(fontSize: 12, color: Colors.grey.shade500), maxLines: 2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown(String label, String value, List<String> items, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : items.first,
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600),
              style: const TextStyle(fontSize: 14, color: Color(0xFF374151)),
              items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _inputWithUnit(String label, TextEditingController controller, String unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
              ),
              child: Text(unit, style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _toggleRow(String title, String subtitle, bool value, Function(bool) onChanged) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged, activeColor: emerald500),
      ],
    );
  }

  Widget _streamLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: const TextStyle(fontSize: 10, color: Color(0xFF10B981), fontFamily: 'monospace')),
    );
  }
}
