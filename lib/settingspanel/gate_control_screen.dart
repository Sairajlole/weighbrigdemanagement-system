import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class GateControlScreen extends StatefulWidget {
  const GateControlScreen({super.key});

  @override
  State<GateControlScreen> createState() => _GateControlScreenState();
}

class _GateControlScreenState extends State<GateControlScreen> {
  // Master System
  bool systemActive = true;

  // Entry Gate Lane 01
  String entryConnectionType = 'TCP/IP (Ethernet)';
  final TextEditingController entryIpController = TextEditingController(text: '192.168.1.105:5000');
  final TextEditingController entryRelayPinController = TextEditingController(text: '4');
  final TextEditingController entryHoldDurationController = TextEditingController(text: '15');
  List<String> entryTriggers = ['RFID Scan', 'ANPR Recognition'];

  // Exit Gate Lane 02
  String exitConnectionType = 'RS485 Serial';
  final TextEditingController exitComPortController = TextEditingController(text: 'COM3');
  String exitBaudRate = '9600';
  final TextEditingController exitAutoCloseController = TextEditingController(text: '10');
  List<String> exitTriggers = ['Weight Completion', 'Manual Override'];

  // Safety & Alarms
  bool beamObstructionCheck = true;
  final TextEditingController debounceTimeController = TextEditingController(text: '250');
  bool buzzerOnError = true;
  String buzzerPattern = 'Continuous';
  bool openOnPowerLoss = false;
  bool autoLockOnTamper = true;

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  @override
  void dispose() {
    entryIpController.dispose();
    entryRelayPinController.dispose();
    entryHoldDurationController.dispose();
    exitComPortController.dispose();
    exitAutoCloseController.dispose();
    debounceTimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Settings",
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Gate Control Automation",
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Configure hardware integration for entry and exit barrier systems.",
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text("Reset Defaults"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF374151),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text("Test All Connections"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF374151),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Master Gate Control System
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: emerald50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.settings_input_component, color: emerald600, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Master Gate Control System",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Enable or disable the entire automation logic for both entry and exit gates.",
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  const Text("SYSTEM ACTIVE", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                  const SizedBox(width: 12),
                  Switch(value: systemActive, onChanged: (val) => setState(() => systemActive = val), activeColor: emerald500),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Gate Configuration
            const Text("Gate Configuration", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
            const SizedBox(height: 16),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Entry Gate Lane 01
                Expanded(child: _buildGateCard(
                  title: "Entry Gate Lane 01",
                  isConnected: true,
                  connectionType: entryConnectionType,
                  onConnectionTypeChanged: (val) => setState(() => entryConnectionType = val!),
                  connectionTypes: ['TCP/IP (Ethernet)', 'RS485 Serial', 'USB'],
                  secondaryLabel: "IP ADDRESS / PORT",
                  secondaryController: entryIpController,
                  relayLabel: "RELAY OUTPUT PIN",
                  relayController: entryRelayPinController,
                  durationLabel: "HOLD DURATION (S)",
                  durationController: entryHoldDurationController,
                  triggers: entryTriggers,
                  testButtonLabel: "Test Open Cycle",
                  testButtonIcon: Icons.play_circle_outline,
                )),
                const SizedBox(width: 24),
                // Exit Gate Lane 02
                Expanded(child: _buildGateCard(
                  title: "Exit Gate Lane 02",
                  isConnected: false,
                  connectionType: exitConnectionType,
                  onConnectionTypeChanged: (val) => setState(() => exitConnectionType = val!),
                  connectionTypes: ['RS485 Serial', 'TCP/IP (Ethernet)', 'USB'],
                  secondaryLabel: "COM PORT",
                  secondaryController: exitComPortController,
                  relayLabel: "BAUD RATE",
                  relayController: null,
                  baudRate: exitBaudRate,
                  onBaudRateChanged: (val) => setState(() => exitBaudRate = val!),
                  durationLabel: "AUTO-CLOSE DELAY",
                  durationController: exitAutoCloseController,
                  triggers: exitTriggers,
                  testButtonLabel: "Reconnect Hardware",
                  testButtonIcon: Icons.refresh,
                  isReconnect: true,
                )),
              ],
            ),

            const SizedBox(height: 32),

            // Safety & Alarms
            const Text("Safety & Alarms", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
            const SizedBox(height: 16),

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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Infrared Sensors
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.sensors, size: 20, color: Colors.grey.shade600),
                                const SizedBox(width: 8),
                                const Text("Infrared Sensors", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _checkboxRow("Beam Obstruction Check", beamObstructionCheck, (val) => setState(() => beamObstructionCheck = val!)),
                            const SizedBox(height: 12),
                            _smallInputField("Debounce Time (ms)", debounceTimeController),
                          ],
                        ),
                      ),
                      const SizedBox(width: 32),
                      // Audio/Visual Alarms
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.volume_up_outlined, size: 20, color: Colors.grey.shade600),
                                const SizedBox(width: 8),
                                const Text("Audio/Visual Alarms", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _checkboxRow("Buzzer on Error", buzzerOnError, (val) => setState(() => buzzerOnError = val!)),
                            const SizedBox(height: 12),
                            _smallDropdownField("Buzzer Pattern", buzzerPattern, ['Continuous', 'Intermittent', 'Single Beep'], (val) => setState(() => buzzerPattern = val!)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 32),
                      // Fail-Safe Protocols
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.security, size: 20, color: Colors.grey.shade600),
                                const SizedBox(width: 8),
                                const Text("Fail-Safe Protocols", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _checkboxRow("Open on Power Loss", openOnPowerLoss, (val) => setState(() => openOnPowerLoss = val!)),
                            const SizedBox(height: 12),
                            _checkboxRow("Auto-Lock on Tamper", autoLockOnTamper, (val) => setState(() => autoLockOnTamper = val!)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.amber.shade700),
                      const SizedBox(width: 8),
                      Text(
                        "Safety settings are applied globally to all active gates.",
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {},
                        child: const Text("View Hardware Manual", style: TextStyle(color: emerald600, fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGateCard({
    required String title,
    required bool isConnected,
    required String connectionType,
    required Function(String?) onConnectionTypeChanged,
    required List<String> connectionTypes,
    required String secondaryLabel,
    required TextEditingController? secondaryController,
    required String relayLabel,
    TextEditingController? relayController,
    String? baudRate,
    Function(String?)? onBaudRateChanged,
    required String durationLabel,
    required TextEditingController durationController,
    required List<String> triggers,
    required String testButtonLabel,
    required IconData testButtonIcon,
    bool isReconnect = false,
  }) {
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.door_sliding_outlined, color: Colors.grey.shade600, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isConnected ? emerald500 : Colors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isConnected ? "CONNECTED" : "OFFLINE",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isConnected ? emerald500 : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {},
                icon: Icon(Icons.settings_outlined, size: 20, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _labeledDropdown("CONNECTION TYPE", connectionType, connectionTypes, onConnectionTypeChanged)),
              const SizedBox(width: 16),
              Expanded(
                child: secondaryController != null
                    ? _labeledInput(secondaryLabel, secondaryController)
                    : _labeledDropdown(secondaryLabel, baudRate ?? '', ['COM1', 'COM2', 'COM3', 'COM4'], (val) {}),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: relayController != null
                    ? _labeledInput(relayLabel, relayController)
                    : _labeledDropdown(relayLabel, baudRate!, ['9600', '19200', '38400', '115200'], onBaudRateChanged!),
              ),
              const SizedBox(width: 16),
              Expanded(child: _labeledInput(durationLabel, durationController)),
            ],
          ),
          const SizedBox(height: 20),
          Text("TRIGGERS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...triggers.map((t) => _chip(t, true)),
              if (!isReconnect) _chip("+ Add", false),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: Icon(testButtonIcon, size: 18, color: isReconnect ? Colors.red : emerald600),
              label: Text(testButtonLabel, style: TextStyle(color: isReconnect ? Colors.red : emerald600)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: isReconnect ? Colors.red.shade200 : const Color(0xFFD1FAE5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _labeledInput(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
        const SizedBox(height: 6),
        TextField(
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
      ],
    );
  }

  Widget _labeledDropdown(String label, String value, List<String> items, Function(String?) onChanged) {
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
              items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? emerald50 : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isActive ? emerald500 : Colors.grey.shade300),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isActive ? emerald600 : Colors.grey.shade600)),
    );
  }

  Widget _checkboxRow(String label, bool value, Function(bool?) onChanged) {
    return Row(
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
        const Spacer(),
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(value: value, onChanged: onChanged, activeColor: emerald500, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
        ),
      ],
    );
  }

  Widget _smallInputField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        SizedBox(
          width: 100,
          child: TextField(
            controller: controller,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            ),
          ),
        ),
      ],
    );
  }

  Widget _smallDropdownField(String label, String value, List<String> items, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        Container(
          width: 150,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey.shade600),
              style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
              items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
