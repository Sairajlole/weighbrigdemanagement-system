import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class PrintingScreen extends StatefulWidget {
  const PrintingScreen({super.key});

  @override
  State<PrintingScreen> createState() => _PrintingScreenState();
}

class _PrintingScreenState extends State<PrintingScreen> {
  // Automation & Logic
  bool autoPrintOnCompletion = true;
  String multiCopyCount = '2 Copies';

  // Security & Compliance
  bool requireManagerPin = true;
  final TextEditingController watermarkController = TextEditingController(text: 'DUPLICATE COPY');

  // Barcode Configuration
  String barcodeStandard = 'Code 128 (Standard)';

  // Print Queue Items
  final List<Map<String, dynamic>> printQueue = [
    {'name': 'TICKET_WB_102.pdf', 'status': 'pending', 'icon': Icons.description_outlined},
    {'name': 'STICKER_002.zpl', 'status': 'waiting', 'icon': Icons.description_outlined},
  ];

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  @override
  void dispose() {
    watermarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Settings",
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF9FAFB), Color(0xFFF0FDF9)],
          ),
        ),
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
                        Icon(Icons.settings_outlined, size: 16, color: emerald600),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Text(
                            "Settings",
                            style: TextStyle(fontSize: 13, color: emerald600, fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text("/", style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                        const SizedBox(width: 8),
                        Text(
                          "Printer & RST Layout",
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Title
                    const Text(
                      "Printer & RST Layout Settings",
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Manage hardware connectivity, receipt/sticker templates, automated print rules, and security protocols for weight transaction records.",
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade500, height: 1.5),
                    ),

                    const SizedBox(height: 32),

                    // Main Content Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Column
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Printer Connectivity & Status
                              _buildPrinterConnectivitySection(),

                              const SizedBox(height: 24),

                              // Automation & Logic
                              _buildAutomationSection(),

                              const SizedBox(height: 24),

                              // Sticker & Barcode Configuration
                              _buildBarcodeSection(),
                            ],
                          ),
                        ),

                        const SizedBox(width: 24),

                        // Right Column - Print Queue & Security
                        SizedBox(
                          width: 280,
                          child: Column(
                            children: [
                              // Print Queue
                              _buildPrintQueuePanel(),

                              const SizedBox(height: 24),

                              // Security & Compliance
                              _buildSecurityPanel(),

                              const SizedBox(height: 24),

                              // Hardware Help
                              _buildHardwareHelpCard(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Status Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: emerald500),
                  const SizedBox(width: 8),
                  Text(
                    "Last configuration sync: 2 mins ago",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
                    child: const Text("Discard Changes"),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: emerald500,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: const Text("Publish Layouts"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrinterConnectivitySection() {
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
              Icon(Icons.print_outlined, size: 20, color: emerald600),
              const SizedBox(width: 10),
              const Text(
                "Printer Connectivity & Status",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {},
                child: Text(
                  "Scan for Hardware",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: emerald600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              // Default Ticket Printer
              Expanded(
                child: _buildPrinterCard(
                  icon: Icons.print_outlined,
                  title: "Default Ticket Printer",
                  status: "ONLINE (USB-001)",
                  isOnline: true,
                  actions: ["Configure", "Test"],
                ),
              ),
              const SizedBox(width: 16),
              // Sticker Printer
              Expanded(
                child: _buildPrinterCard(
                  icon: Icons.print_outlined,
                  title: "Sticker Printer",
                  status: "OFFLINE (ETHERNET-192.1)",
                  isOnline: false,
                  actions: ["Reconnect", "Settings"],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrinterCard({
    required IconData icon,
    required String title,
    required String status,
    required bool isOnline,
    required List<String> actions,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Icon(icon, size: 22, color: Colors.grey.shade600),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isOnline ? emerald500 : Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 12,
                          color: isOnline ? emerald600 : Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: actions.map((action) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      action,
                      style: TextStyle(
                        fontSize: 12,
                        color: isOnline ? emerald600 : Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutomationSection() {
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
              Icon(Icons.settings_outlined, size: 20, color: emerald600),
              const SizedBox(width: 10),
              const Text(
                "Automation & Logic",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Auto-print on RST Completion
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
                        "Auto-print on RST Completion",
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Automatically print the final weight ticket when a transaction is saved.",
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: autoPrintOnCompletion,
                  onChanged: (val) => setState(() => autoPrintOnCompletion = val),
                  activeColor: emerald500,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Multi-Copy Printing
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
                        "Multi-Copy Printing",
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Print 2 copies by default (1 for driver, 1 for records).",
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: multiCopyCount,
                      icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600),
                      style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
                      items: ['1 Copy', '2 Copies', '3 Copies', '4 Copies']
                          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                          .toList(),
                      onChanged: (val) => setState(() => multiCopyCount = val!),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarcodeSection() {
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
              Icon(Icons.qr_code_2_outlined, size: 20, color: emerald600),
              const SizedBox(width: 10),
              const Text(
                "Sticker & Barcode Configuration",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Barcode Standard Dropdown
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Barcode Standard",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600),
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
                          value: barcodeStandard,
                          isExpanded: true,
                          icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600),
                          style: const TextStyle(fontSize: 14, color: Color(0xFF374151)),
                          items: ['Code 128 (Standard)', 'Code 39', 'QR Code', 'EAN-13']
                              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                              .toList(),
                          onChanged: (val) => setState(() => barcodeStandard = val!),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              // Live Sticker Reference
              Expanded(
                flex: 2,
                child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "LIVE STICKER REFERENCE",
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade400, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Column(
                          children: [
                            // Barcode representation
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(20, (i) => Container(
                                width: i % 3 == 0 ? 2 : 1,
                                height: 30,
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                color: Colors.black,
                              )),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "0718-2024-001",
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontFamily: 'monospace'),
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
        ],
      ),
    );
  }

  Widget _buildPrintQueuePanel() {
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
              const Text(
                "Print Queue",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  "3 Pending",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber.shade700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Queue Items
          ...printQueue.map((item) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                Icon(item['icon'], size: 18, color: Colors.grey.shade500),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['name'],
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151)),
                      ),
                      Text(
                        item['status'] == 'pending' ? 'Ready for print...' : 'Waiting for printer...',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.more_horiz, size: 18, color: Colors.grey.shade400),
              ],
            ),
          )).toList(),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () {},
              child: Text(
                "Purge All Queues",
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: emerald600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(12),
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
                child: const Icon(Icons.shield_outlined, size: 14, color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Text(
                "Security & Compliance",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Reprint Authorization
          Text(
            "REPRINT AUTHORIZATION",
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Require Manager PIN",
                style: TextStyle(fontSize: 13, color: Colors.white),
              ),
              Switch(
                value: requireManagerPin,
                onChanged: (val) => setState(() => requireManagerPin = val),
                activeColor: emerald500,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Reprint Watermark
          Text(
            "REPRINT WATERMARK",
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: watermarkController,
            style: const TextStyle(fontSize: 13, color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: emerald600.withOpacity(0.3),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "This text will be printed across any reprinted tickets.",
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildHardwareHelpCard() {
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
          const Text(
            "Need Hardware Help?",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
          ),
          const SizedBox(height: 6),
          Text(
            "Visit our knowledge base for drivers and ESC/POS integration guides.",
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500, height: 1.4),
          ),
        ],
      ),
    );
  }
}
