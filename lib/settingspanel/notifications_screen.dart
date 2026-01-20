import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  // SMS Gateway Settings
  bool smsEnabled = true;
  String smsProvider = 'Twilio Global Service';
  final TextEditingController apiTokenController = TextEditingController(text: '••••••••••••••••••••••••••••');
  final TextEditingController smsTemplateController = TextEditingController(
    text: 'Your Truck: [Truck #] has cleared weighing. Net Weight: [NetWeight]Kg.',
  );

  // WhatsApp Business API Settings
  bool whatsappEnabled = false;
  final TextEditingController whatsappPhoneController = TextEditingController(text: '');
  final TextEditingController whatsappDisplayNameController = TextEditingController(text: 'Logistics Alerting System');

  // Email SMTP Settings
  bool emailEnabled = true;
  final TextEditingController emailHostController = TextEditingController(text: 'smtp.office365.com');
  final TextEditingController emailPortController = TextEditingController(text: '587');
  String emailEncryption = 'STARTTLS';
  final TextEditingController emailTemplateController = TextEditingController(
    text: '<div style="font-family: Arial;">\n<h2>Daily Weighment Report</h2>\n<p>Location: Main Gate B1</p>\n<br/>\n{Content_Placeholder}\n</div>',
  );

  // Notification Triggers Matrix
  Map<String, Map<String, bool>> notificationMatrix = {
    'Vehicle Check-in': {'sms': true, 'whatsapp': false, 'email': false, 'push': false},
    'Overload Warning': {'sms': false, 'whatsapp': true, 'email': true, 'push': true},
    'Calibration Due': {'sms': false, 'whatsapp': false, 'email': true, 'push': true},
    'Transaction Cancelled': {'sms': false, 'whatsapp': false, 'email': false, 'push': true},
  };

  Map<String, String> eventDescriptions = {
    'Vehicle Check-in': 'Triggered when SMD, any is detected',
    'Overload Warning': 'Triggered when limits are exceeded',
    'Calibration Due': 'Triggered 7 days before due date',
    'Transaction Cancelled': 'When a transaction is cancelled by a user',
  };

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  @override
  void dispose() {
    apiTokenController.dispose();
    smsTemplateController.dispose();
    whatsappPhoneController.dispose();
    whatsappDisplayNameController.dispose();
    emailHostController.dispose();
    emailPortController.dispose();
    emailTemplateController.dispose();
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("System Settings", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                      Text("v4.1.1", style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),
                _sidebarItem(Icons.settings_outlined, "General Settings", false),
                _sidebarItem(Icons.people_outline, "User Management", false),
                _sidebarItem(Icons.monitor_weight_outlined, "Weighbridge Setup", false),
                _sidebarItem(Icons.notifications_outlined, "Notifications", true),
                _sidebarItem(Icons.history_outlined, "Activity Logs", false),
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
                        // Breadcrumb
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Text(
                                "Settings",
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(">", style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                            const SizedBox(width: 8),
                            Text(
                              "Notification & Messaging Setup",
                              style: TextStyle(fontSize: 13, color: emerald600, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Header Row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Notification Channels",
                                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    "Configure SMS gateways, WhatsApp Business API, and SMTP email services for automated dispatch alerts.",
                                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            ElevatedButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text("Save All Changes"),
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

                        // SMS/WhatsApp Pack Status Banner
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
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: emerald500,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.sms_outlined, color: Colors.white, size: 22),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "SMS/WhatsApp Pack Status",
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                                    ),
                                    const SizedBox(height: 4),
                                    RichText(
                                      text: TextSpan(
                                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
                                        children: const [
                                          TextSpan(text: "Your message credit balance is low "),
                                          TextSpan(text: "(543 / 5000)", style: TextStyle(fontWeight: FontWeight.w600)),
                                          TextSpan(text: ". Please recharge your SMS/WhatsApp pack to avoid service interruption for automated reports."),
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
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
                                child: const Text("Renew Subscription"),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // SMS Gateway and WhatsApp Business API Row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // SMS Gateway Card
                            Expanded(
                              child: _buildSmsGatewayCard(),
                            ),
                            const SizedBox(width: 24),
                            // WhatsApp Business API Card
                            Expanded(
                              child: _buildWhatsAppCard(),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Email SMTP Configuration
                        _buildEmailSmtpCard(),

                        const SizedBox(height: 32),

                        // Notification Triggers Matrix
                        _buildNotificationMatrix(),
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
                      Row(
                        children: [
                          Icon(Icons.check_circle, size: 16, color: emerald500),
                          const SizedBox(width: 6),
                          Text("All services synced.", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                      const SizedBox(width: 24),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 16, color: Colors.grey.shade400),
                          const SizedBox(width: 6),
                          Text("Last Sync: An hour ago", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: emerald50,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
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
                              "Pro Subscription: 10 Days",
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: emerald600),
                            ),
                          ],
                        ),
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

  Widget _buildSmsGatewayCard() {
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
          // Header
          Row(
            children: [
              Icon(Icons.sms_outlined, size: 20, color: emerald600),
              const SizedBox(width: 10),
              const Text(
                "SMS Gateway",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: emerald50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  "CONNECTED",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: emerald600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Provider Dropdown
          _buildLabel("PROVIDER"),
          const SizedBox(height: 8),
          _buildDropdownField(
            value: smsProvider,
            items: ['Twilio Global Service', 'MSG91', 'Nexmo', 'AWS SNS'],
            onChanged: (val) => setState(() => smsProvider = val!),
          ),
          
          const SizedBox(height: 16),
          
          // API Token
          _buildLabel("API/AUTH TOKEN"),
          const SizedBox(height: 8),
          TextField(
            controller: apiTokenController,
            obscureText: true,
            style: const TextStyle(fontSize: 14),
            decoration: _inputDecoration(),
          ),
          
          const SizedBox(height: 16),
          
          // Template Editor
          _buildLabel("TEMPLATE EDITOR (FOR DEFAULT CHECKOUTS)"),
          const SizedBox(height: 8),
          TextField(
            controller: smsTemplateController,
            maxLines: 3,
            style: const TextStyle(fontSize: 13),
            decoration: _inputDecoration(),
          ),
          
          const SizedBox(height: 8),
          Text(
            "Available Tags: [Truck #], [NetWeight], [Time], [Operator]",
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildWhatsAppCard() {
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
          // Header
          Row(
            children: [
              Icon(Icons.chat_outlined, size: 20, color: Colors.grey.shade500),
              const SizedBox(width: 10),
              Text(
                "WhatsApp Business API",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  "DRAFT",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Phone Number ID
          _buildLabel("PHONE NUMBER ID"),
          const SizedBox(height: 8),
          TextField(
            controller: whatsappPhoneController,
            style: const TextStyle(fontSize: 14),
            decoration: _inputDecoration(hintText: "e.g. 9350657461"),
          ),
          
          const SizedBox(height: 16),
          
          // System Display Name
          _buildLabel("SYSTEM DISPLAY NAME"),
          const SizedBox(height: 8),
          TextField(
            controller: whatsappDisplayNameController,
            style: const TextStyle(fontSize: 14),
            decoration: _inputDecoration(),
          ),
          
          const SizedBox(height: 20),
          
          // Integration Info Box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "WhatsApp Integration",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 6),
                Text(
                  "Automated PDF slips can be sent directly to the driver's phone upon weighment completion.",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.link, size: 14, color: emerald600),
                    const SizedBox(width: 6),
                    Text(
                      "SYNC TEMPLATES FROM META",
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: emerald600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailSmtpCard() {
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
          // Header
          Row(
            children: [
              Icon(Icons.mail_outline, size: 20, color: emerald600),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "Email SMTP Configuration",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                ),
              ),
              TextButton(
                onPressed: () {},
                child: Text(
                  "Test SMTP Connection",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: emerald600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column - SMTP Settings
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel("HOST SERVER"),
                    const SizedBox(height: 8),
                    TextField(
                      controller: emailHostController,
                      style: const TextStyle(fontSize: 14),
                      decoration: _inputDecoration(),
                    ),
                    const SizedBox(height: 16),
                    _buildLabel("PORT"),
                    const SizedBox(height: 8),
                    TextField(
                      controller: emailPortController,
                      style: const TextStyle(fontSize: 14),
                      decoration: _inputDecoration(),
                    ),
                    const SizedBox(height: 16),
                    _buildLabel("ENCRYPTION"),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _encryptionButton("STARTTLS", emailEncryption == "STARTTLS"),
                        const SizedBox(width: 8),
                        _encryptionButton("SSL/TLS", emailEncryption == "SSL/TLS"),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              // Right Column - Email Template
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildLabel("EMAIL HEADER TEMPLATE [HTML]"),
                        const Spacer(),
                        _formatButton(Icons.format_bold),
                        const SizedBox(width: 4),
                        _formatButton(Icons.format_italic),
                        const SizedBox(width: 4),
                        _formatButton(Icons.format_underlined),
                        const SizedBox(width: 4),
                        _formatButton(Icons.image_outlined),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: TextField(
                        controller: emailTemplateController,
                        maxLines: null,
                        expands: true,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: Colors.grey.shade700,
                          height: 1.5,
                        ),
                        decoration: const InputDecoration(
                          filled: true,
                          fillColor: Color(0xFFF9FAFB),
                          contentPadding: EdgeInsets.all(14),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationMatrix() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Notification Triggers Matrix",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
        ),
        const SizedBox(height: 6),
        Text(
          "Select which events trigger messages on specific channels.",
          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            children: [
              // Header Row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        "SYSTEM EVENT",
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500),
                      ),
                    ),
                    ...['SMS', 'WHATSAPP', 'EMAIL', 'PUSH (APP)'].map((channel) => Expanded(
                      child: Center(
                        child: Text(
                          channel,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500),
                        ),
                      ),
                    )),
                  ],
                ),
              ),
              // Event Rows
              ...notificationMatrix.keys.toList().asMap().entries.map((entry) {
                int index = entry.key;
                String event = entry.value;
                bool isLast = index == notificationMatrix.length - 1;
                return _buildMatrixRow(event, isLast);
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.check_circle, size: 16, color: emerald500),
            const SizedBox(width: 8),
            Text("All selected events synced.", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const Spacer(),
            Text("Last Sync: Moments ago", style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ],
        ),
      ],
    );
  }

  Widget _buildMatrixRow(String event, bool isLast) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF374151)),
                ),
                const SizedBox(height: 2),
                Text(
                  eventDescriptions[event] ?? '',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          ...['sms', 'whatsapp', 'email', 'push'].map((channel) => Expanded(
            child: Center(
              child: _buildCheckbox(
                value: notificationMatrix[event]![channel]!,
                onChanged: (val) {
                  setState(() {
                    notificationMatrix[event]![channel] = val ?? false;
                  });
                },
              ),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.3),
    );
  }

  InputDecoration _inputDecoration({String? hintText}) {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      hintText: hintText,
      hintStyle: TextStyle(color: Colors.grey.shade400),
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
    );
  }

  Widget _buildDropdownField({
    required String value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Container(
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
    );
  }

  Widget _encryptionButton(String label, bool isActive) {
    return GestureDetector(
      onTap: () => setState(() => emailEncryption = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? emerald500 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? emerald500 : const Color(0xFFE5E7EB)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isActive ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _formatButton(IconData icon) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, size: 16, color: Colors.grey.shade600),
    );
  }

  Widget _buildCheckbox({required bool value, required Function(bool?) onChanged}) {
    return SizedBox(
      width: 20,
      height: 20,
      child: Checkbox(
        value: value,
        onChanged: onChanged,
        activeColor: emerald500,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: value ? emerald500 : Colors.grey.shade400, width: 1.5),
      ),
    );
  }
}
