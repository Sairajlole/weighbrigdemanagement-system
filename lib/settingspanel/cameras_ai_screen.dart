import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class CamerasAiScreen extends StatefulWidget {
  const CamerasAiScreen({super.key});

  @override
  State<CamerasAiScreen> createState() => _CamerasAiScreenState();
}

class _CamerasAiScreenState extends State<CamerasAiScreen> {
  // LPR Settings
  String lprCameraSource = 'Axis P1455-LE (Entry Gate)';
  double confidenceThreshold = 0.85;
  bool ocrNightEnhancement = true;

  // Driver Assist
  String detectionMode = 'Realtime (GPU)';
  double alertnessSensitivity = 0.65;
  bool driverHelmetDetection = false;

  // Customer Booth Card
  bool autoPrintReceipt = false;
  bool uploadToCentralRegistry = true;

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Settings",
      child: Row(
        children: [
          // Left Sidebar
          Container(
            width: 180,
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
                      const Text("System Settings", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Text("V1.5 RAETNA", style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                    ],
                  ),
                ),
                _sidebarItem(Icons.settings_outlined, "General", false),
                _sidebarItem(Icons.videocam_outlined, "Cameras & AI", true),
                _sidebarItem(Icons.people_outline, "Users", false),
                _sidebarItem(Icons.extension_outlined, "Integrations", false),
                _sidebarItem(Icons.support_agent_outlined, "Support", false),
              ],
            ),
          ),

          // Main Content
          Expanded(
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
                                  const Text("Cameras & AI Vision Settings", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text("Manage intelligent detection modules and hardware streams.", style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                                ],
                              ),
                            ),
                            OutlinedButton(
                              onPressed: () {},
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF374151),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                side: const BorderSide(color: Color(0xFFE5E7EB)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text("Export Config"),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text("Save All Changes"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: emerald500,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Subscription Banner
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: emerald50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFD1FAE5)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(color: emerald500, borderRadius: BorderRadius.circular(10)),
                                child: const Icon(Icons.star, color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("Subscription Status: Professional AI Suite", style: TextStyle(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    RichText(
                                      text: TextSpan(
                                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                        children: const [
                                          TextSpan(text: "Active: License Plate Recognition & Driver Assist. Upgrade to "),
                                          TextSpan(text: "Enterprise Plan", style: TextStyle(fontWeight: FontWeight.w600, color: emerald600)),
                                          TextSpan(text: " to unlock Material Recognition, Advanced Deep Learning Analytics, and Unlimited API Integration."),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              ElevatedButton(
                                onPressed: () {},
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: emerald500,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text("Upgrade Now"),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // LPR and Driver Assist Row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // License Plate Recognition
                            Expanded(child: _cameraCard(
                              icon: Icons.document_scanner_outlined,
                              title: "License Plate Recognition (LPR)",
                              status: "LIVE",
                              isActive: true,
                              cameraId: "CAM_01_ENTRY_GATE",
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _dropdown("CAMERA SOURCE", lprCameraSource, ['Axis P1455-LE (Entry Gate)', 'Axis P1455-LE (Exit Gate)', 'Hikvision DS-2CD'], (v) => setState(() => lprCameraSource = v!)),
                                  const SizedBox(height: 16),
                                  _sliderField("CONFIDENCE THRESHOLD", confidenceThreshold, "${(confidenceThreshold * 100).toInt()}%", (v) => setState(() => confidenceThreshold = v)),
                                  const SizedBox(height: 16),
                                  _toggleRow("OCR Night Enhancement", ocrNightEnhancement, (v) => setState(() => ocrNightEnhancement = v)),
                                ],
                              ),
                            )),
                            const SizedBox(width: 24),
                            // Driver Assist
                            Expanded(child: _cameraCard(
                              icon: Icons.person_outline,
                              title: "Driver Assist & Cabin Safety",
                              status: "ACTIVE",
                              isActive: true,
                              cameraId: "CAM_02_CABIN_CHECK",
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("DETECTION MODE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      _modeButton("Realtime (GPU)", detectionMode == "Realtime (GPU)", () => setState(() => detectionMode = "Realtime (GPU)")),
                                      const SizedBox(width: 8),
                                      _modeButton("Standard", detectionMode == "Standard", () => setState(() => detectionMode = "Standard")),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  _sliderField("ALERTNESS SENSITIVITY", alertnessSensitivity, "Medium (65%)", (v) => setState(() => alertnessSensitivity = v)),
                                  const SizedBox(height: 16),
                                  _toggleRow("Driver Helmet Detection", driverHelmetDetection, (v) => setState(() => driverHelmetDetection = v)),
                                ],
                              ),
                            )),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Material Recognition and Customer Booth
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Material Recognition (Locked)
                            Expanded(child: _lockedCard(
                              icon: Icons.inventory_2_outlined,
                              title: "Material Recognition",
                              description: "Unlock automated material classification and volume estimation with the Enterprise Plan.",
                            )),
                            const SizedBox(width: 24),
                            // Customer Booth Card
                            Expanded(child: _settingsCard(
                              icon: Icons.badge_outlined,
                              title: "Customer Booth Card",
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF3F4F6),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(Icons.camera_alt_outlined, color: Colors.grey.shade600),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text("Manual ID Photo Capture", style: TextStyle(fontWeight: FontWeight.w500)),
                                            const SizedBox(height: 4),
                                            Text("Configured to capture high-res snapshot of driver/document at the weighbridge booth.", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      TextButton(onPressed: () {}, child: const Text("Trigger Test Shot", style: TextStyle(color: emerald600))),
                                      const SizedBox(width: 8),
                                      TextButton(onPressed: () {}, child: Text("Refresh Stream", style: TextStyle(color: Colors.grey.shade600))),
                                    ],
                                  ),
                                  const Divider(height: 24),
                                  _toggleRow("Auto-print Receipt with Image", autoPrintReceipt, (v) => setState(() => autoPrintReceipt = v)),
                                  const SizedBox(height: 12),
                                  _toggleRow("Upload to Central Registry", uploadToCentralRegistry, (v) => setState(() => uploadToCentralRegistry = v)),
                                ],
                              ),
                            )),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom Status Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                  ),
                  child: Row(
                    children: [
                      _statusChip(Icons.memory, "PROCESSOR: OK", true),
                      const SizedBox(width: 16),
                      _statusChip(Icons.cloud_outlined, "VISION API: ONLINE", true),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: () {},
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF374151),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text("Reset to Defaults"),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: emerald500,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text("Deploy Configurations"),
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
                Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isActive ? emerald600 : Colors.grey.shade700)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cameraCard({required IconData icon, required String title, required String status, required bool isActive, required String cameraId, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE5E7EB))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: emerald600),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: emerald50, borderRadius: BorderRadius.circular(4)),
                child: Text(status, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: emerald600)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(color: const Color(0xFF374151), borderRadius: BorderRadius.circular(8)),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam, color: Colors.grey.shade600, size: 32),
                  const SizedBox(height: 8),
                  Text(cameraId, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontFamily: 'monospace')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _lockedCard({required IconData icon, required String title, required String description}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE5E7EB))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: Colors.grey.shade500),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade500))),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(32)),
                  child: Icon(Icons.lock_outline, color: Colors.grey.shade400, size: 28),
                ),
                const SizedBox(height: 16),
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                const SizedBox(height: 8),
                Text(description, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: emerald500,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("Unlock Module"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsCard({required IconData icon, required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE5E7EB))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 20, color: emerald600), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.w600))]),
          const SizedBox(height: 16),
          child,
        ],
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
          decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE5E7EB))),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(value: value, isExpanded: true, icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600), style: const TextStyle(fontSize: 14, color: Color(0xFF374151)), items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(), onChanged: onChanged),
          ),
        ),
      ],
    );
  }

  Widget _sliderField(String label, double value, String displayValue, Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500)), Text(displayValue, style: const TextStyle(fontSize: 12, color: emerald600, fontWeight: FontWeight.w500))],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(activeTrackColor: emerald500, inactiveTrackColor: const Color(0xFFE5E7EB), thumbColor: emerald500, overlayColor: emerald500.withOpacity(0.2), trackHeight: 6),
          child: Slider(value: value, min: 0, max: 1, onChanged: onChanged),
        ),
      ],
    );
  }

  Widget _toggleRow(String label, bool value, Function(bool) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF374151))), Switch(value: value, onChanged: onChanged, activeColor: emerald500)],
    );
  }

  Widget _modeButton(String label, bool isActive, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? emerald50 : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isActive ? emerald500 : const Color(0xFFE5E7EB)),
          ),
          child: Center(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isActive ? emerald600 : Colors.grey.shade600))),
        ),
      ),
    );
  }

  Widget _statusChip(IconData icon, String label, bool isOk) {
    return Row(
      children: [
        Icon(icon, size: 16, color: isOk ? emerald500 : Colors.red),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isOk ? emerald600 : Colors.red)),
      ],
    );
  }
}
