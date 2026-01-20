import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  // Authentication
  bool twoFactorEnabled = true;
  String primaryMethod = 'authenticator';
  bool ssoEnabled = false;

  // Password Policy
  String minLength = '12';
  String passwordExpiry = '90 Days';
  bool requireUppercase = true;
  bool requireNumber = true;
  bool requireSpecialChar = true;
  bool prohibitCommonPasswords = false;

  // PIN Verification Settings
  String pinLength = '6 Digits';
  bool pinManualWeightEntry = true;
  bool pinDeleteWeighment = true;
  bool pinTareOverride = false;
  bool pinReprintTicket = false;

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
            width: 200,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
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
                        child: const Icon(Icons.diamond_outlined, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Text("WeighSys", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                    ],
                  ),
                ),
                // Admin Console
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: emerald100,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Text("AC", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: emerald600)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Admin Console", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                          Text("System Administrator", style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _sidebarItem(Icons.dashboard_outlined, "Dashboard", false),
                _sidebarItem(Icons.scale_outlined, "Weighments", false),
                _sidebarItem(Icons.bar_chart_outlined, "Reports", false),
                _sidebarItem(Icons.inventory_2_outlined, "Master Data", false),
                _sidebarItem(Icons.people_outline, "Users", false),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text("CONFIGURATION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
                ),
                const SizedBox(height: 8),
                _sidebarItem(Icons.settings_outlined, "Settings", true),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: Container(
              color: const Color(0xFFF9FAFB),
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
                              Text("Settings", style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                              const SizedBox(width: 8),
                              Text("/", style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                              const SizedBox(width: 8),
                              Text("Security & Access", style: TextStyle(fontSize: 13, color: emerald600, fontWeight: FontWeight.w500)),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Title
                          const Text(
                            "Security & Access Configuration",
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Manage system-wide security protocols, authentication, and access controls for the weighbridge system.",
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                          ),

                          const SizedBox(height: 32),

                          // Authentication and Password Policy Row
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildAuthenticationCard()),
                              const SizedBox(width: 24),
                              Expanded(child: _buildPasswordPolicyCard()),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // PIN Verification Settings
                          _buildPinVerificationCard(),
                        ],
                      ),
                    ),
                  ),

                  // Bottom Action Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                    ),
                    child: Row(
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey.shade700,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text("Cancel"),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.lock_outline, size: 18),
                          label: const Text("Save Security Settings"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: emerald500,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
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

  static const Color emerald100 = Color(0xFFD1FAE5);

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

  Widget _buildAuthenticationCard() {
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
                child: const Icon(Icons.shield_outlined, size: 14, color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Text(
                "Authentication",
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
                  "Active",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: emerald600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Two-Factor Authentication
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Two-Factor Authentication (2FA)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                    const SizedBox(height: 4),
                    Text("Require additional verification code", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Switch(
                value: twoFactorEnabled,
                onChanged: (val) => setState(() => twoFactorEnabled = val),
                activeColor: emerald500,
              ),
            ],
          ),

          if (twoFactorEnabled) ...[
            const SizedBox(height: 20),
            Text("PRIMARY METHOD", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
            const SizedBox(height: 12),
            _buildRadioOption("email", "Email Verification", primaryMethod == 'email', () => setState(() => primaryMethod = 'email')),
            const SizedBox(height: 8),
            _buildRadioOption("authenticator", "Authenticator App (Recommended)", primaryMethod == 'authenticator', () => setState(() => primaryMethod = 'authenticator'), isRecommended: true),
            const SizedBox(height: 8),
            _buildRadioOption("sms", "SMS / Text Message", primaryMethod == 'sms', () => setState(() => primaryMethod = 'sms')),
          ],

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // Single Sign-On
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Single Sign-On (SSO)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                    const SizedBox(height: 4),
                    Text("Allow login via SAML/OIDC providers", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Switch(
                value: ssoEnabled,
                onChanged: (val) => setState(() => ssoEnabled = val),
                activeColor: emerald500,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRadioOption(String value, String label, bool isSelected, VoidCallback onTap, {bool isRecommended = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: isSelected ? emerald500 : Colors.grey.shade400, width: 2),
            ),
            child: isSelected
                ? Center(
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: emerald500),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isSelected ? const Color(0xFF374151) : Colors.grey.shade600,
              fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordPolicyCard() {
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
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.grid_view_rounded, size: 14, color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Text(
                "Password Policy",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Minimum Length and Password Expiry
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Minimum Length", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
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
                          Text(minLength, style: const TextStyle(fontSize: 14, color: Color(0xFF374151))),
                          const Spacer(),
                          Text("chars", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Password Expiry", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
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
                          value: passwordExpiry,
                          isExpanded: true,
                          icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600),
                          style: const TextStyle(fontSize: 14, color: Color(0xFF374151)),
                          items: ['30 Days', '60 Days', '90 Days', '180 Days', 'Never'].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                          onChanged: (val) => setState(() => passwordExpiry = val!),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Requirements
          Text("Requirements", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildRequirementCheckbox("Require uppercase letter", requireUppercase, (val) => setState(() => requireUppercase = val ?? false))),
              Expanded(child: _buildRequirementCheckbox("Require number", requireNumber, (val) => setState(() => requireNumber = val ?? false))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildRequirementCheckbox("Require special character", requireSpecialChar, (val) => setState(() => requireSpecialChar = val ?? false))),
              Expanded(child: _buildRequirementCheckbox("Prohibit common passwords", prohibitCommonPasswords, (val) => setState(() => prohibitCommonPasswords = val ?? false))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementCheckbox(String label, bool value, Function(bool?) onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: emerald500,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            side: BorderSide(color: value ? emerald500 : Colors.grey.shade400, width: 1.5),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ),
      ],
    );
  }

  Widget _buildPinVerificationCard() {
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
                child: const Icon(Icons.dialpad, size: 14, color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Text(
                "PIN Verification Settings",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
              ),
              const Spacer(),
              Text("For sensitive operations", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 24),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // PIN Length
              SizedBox(
                width: 200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("PIN Length", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
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
                          value: pinLength,
                          isExpanded: true,
                          icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600),
                          style: const TextStyle(fontSize: 14, color: Color(0xFF374151)),
                          items: ['4 Digits', '6 Digits', '8 Digits'].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                          onChanged: (val) => setState(() => pinLength = val!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 14, color: emerald600),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "PINs are required for operators to override automated weighbridge readings.",
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 40),

              // Require PIN Entry For
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Require PIN Entry For:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildPinOptionCard("Manual Weight Entry", "Typing weight instead of scale read", pinManualWeightEntry, (val) => setState(() => pinManualWeightEntry = val))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildPinOptionCard("Delete Weighment", "Permanently removing a record", pinDeleteWeighment, (val) => setState(() => pinDeleteWeighment = val), isDestructive: true)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildPinOptionCard("Tare Override", "Manually changing tare weight", pinTareOverride, (val) => setState(() => pinTareOverride = val))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildPinOptionCard("Reprint Ticket", "Printing a duplicate slip", pinReprintTicket, (val) => setState(() => pinReprintTicket = val))),
                      ],
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

  Widget _buildPinOptionCard(String title, String description, bool isEnabled, Function(bool) onChanged, {bool isDestructive = false}) {
    final bgColor = isEnabled
        ? (isDestructive ? const Color(0xFFFEE2E2) : emerald50)
        : const Color(0xFFF9FAFB);
    final borderColor = isEnabled
        ? (isDestructive ? const Color(0xFFFCA5A5) : const Color(0xFFD1FAE5))
        : const Color(0xFFE5E7EB);
    final iconColor = isEnabled
        ? (isDestructive ? Colors.red.shade600 : emerald600)
        : Colors.grey.shade400;
    final textColor = isEnabled
        ? (isDestructive ? Colors.red.shade700 : emerald600)
        : Colors.grey.shade600;

    return GestureDetector(
      onTap: () => onChanged(!isEnabled),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(
              isEnabled ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
              color: iconColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                  const SizedBox(height: 2),
                  Text(description, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
