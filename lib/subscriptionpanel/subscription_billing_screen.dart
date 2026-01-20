import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class SubscriptionBillingScreen extends StatefulWidget {
  const SubscriptionBillingScreen({super.key});

  @override
  State<SubscriptionBillingScreen> createState() => _SubscriptionBillingScreenState();
}

class _SubscriptionBillingScreenState extends State<SubscriptionBillingScreen> {
  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  final List<Map<String, dynamic>> billingHistory = [
    {'date': 'Oct 01, 2023', 'description': 'Monthly Subscription (Standard)', 'amount': '₹2,999.00', 'status': 'Paid'},
    {'date': 'Sept 01, 2023', 'description': 'SMS Top-up Pack', 'amount': '₹500.00', 'status': 'Paid'},
    {'date': 'Aug 01, 2023', 'description': 'AI Pack Trial', 'amount': '₹0.00', 'status': 'Completed'},
  ];

  void _showSubscribeDialog(String packName, String price, List<String> features) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (context) => SubscribeDialog(
        packName: packName,
        monthlyPrice: price,
        features: features,
        onSuccess: () {
          Navigator.pop(context);
          _showPaymentSuccessDialog(packName, price);
        },
      ),
    );
  }

  void _showPaymentSuccessDialog(String packName, String amount) {
    showDialog(
      context: context,
      barrierColor: emerald50.withOpacity(0.9),
      barrierDismissible: false,
      builder: (context) => PaymentSuccessDialog(
        packName: packName,
        amount: amount,
        onDashboard: () {
          Navigator.pop(context);
          Navigator.pushReplacementNamed(context, '/dashboard');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Subscription & Billing",
      child: Container(
        color: const Color(0xFFF9FAFB),
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
                          "Subscription & Billing",
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Manage your feature packs and billing details",
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      "Current Plan: Pro Enterprise",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Feature Packs
              const Text(
                "Feature Packs",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
              ),

              const SizedBox(height: 16),

              // Pricing Cards
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // AI Features Pack
                  Expanded(
                    child: _buildPricingCard(
                      title: "AI Features Pack",
                      price: "₹999",
                      isActive: true,
                      features: [
                        "Automatic Number Plate Recognition",
                        "Camera Integration",
                        "AI Anomaly Detection",
                      ],
                      buttonText: "Manage",
                      isPrimary: false,
                      onPressed: () {},
                    ),
                  ),
                  const SizedBox(width: 16),
                  // SMS/WhatsApp Pack
                  Expanded(
                    child: _buildPricingCard(
                      title: "SMS/WhatsApp Pack",
                      price: "₹499",
                      isActive: true,
                      features: [
                        "Driver Notifications",
                        "Digital Receipts via WhatsApp",
                        "Daily Summary SMS",
                      ],
                      buttonText: "Manage",
                      isPrimary: false,
                      onPressed: () {},
                    ),
                  ),
                  const SizedBox(width: 16),
                  // ERP Automation
                  Expanded(
                    child: _buildPricingCard(
                      title: "ERP Automation",
                      price: "₹1,499",
                      isActive: false,
                      features: [
                        "SAP/Tally Integration",
                        "Auto-Invoicing",
                        "Tax Calculation Automation",
                      ],
                      buttonText: "Subscribe",
                      isPrimary: true,
                      onPressed: () => _showSubscribeDialog(
                        "AI Features Pack",
                        "₹2,999",
                        [
                          "Automated License Plate Recognition",
                          "Smart Weighing Anomaly Detection",
                          "Predictive Maintenance Alerts",
                          "Cloud Data Sync & Analytics",
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Payment Method
              const Text(
                "Payment Method",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
              ),

              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    // Visa Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1F71),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              "VISA",
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 1),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Visa ending in 4242", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF374151))),
                              Text("Expires 12/2025", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Billing Contact
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("BILLING CONTACT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.5)),
                        const SizedBox(height: 4),
                        Text("finance@weighbridge.com", style: TextStyle(fontSize: 13, color: emerald600)),
                      ],
                    ),
                    const SizedBox(width: 24),
                    OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF374151),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text("Update"),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Billing History
              Row(
                children: [
                  const Text(
                    "Billing History",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {},
                    child: Text("View All", style: TextStyle(fontSize: 13, color: emerald600)),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  children: [
                    // Table Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      child: Row(
                        children: [
                          Expanded(flex: 2, child: Text("Date", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500))),
                          Expanded(flex: 4, child: Text("Description", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500))),
                          Expanded(flex: 2, child: Text("Amount", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500))),
                          Expanded(flex: 2, child: Text("Status", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500))),
                          const Expanded(flex: 1, child: Text("Invoice", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey))),
                        ],
                      ),
                    ),
                    // Table Rows
                    ...billingHistory.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final isLast = index == billingHistory.length - 1;
                      return _buildBillingRow(item, isLast);
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPricingCard({
    required String title,
    required String price,
    required bool isActive,
    required List<String> features,
    required String buttonText,
    required bool isPrimary,
    required VoidCallback onPressed,
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
          // Header
          Row(
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive ? emerald50 : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isActive ? emerald500 : Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isActive ? "ACTIVE" : "INACTIVE",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isActive ? emerald600 : Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Price
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(price, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: isActive ? const Color(0xFF111827) : Colors.grey.shade500)),
              Text("/month", style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 20),

          // Features
          ...features.map((feature) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle, size: 16, color: isActive ? emerald500 : Colors.grey.shade400),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(feature, style: TextStyle(fontSize: 13, color: isActive ? Colors.grey.shade700 : Colors.grey.shade500)),
                ),
              ],
            ),
          )),

          const SizedBox(height: 16),

          // Button
          SizedBox(
            width: double.infinity,
            child: isPrimary
                ? ElevatedButton(
                    onPressed: onPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: emerald500,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: Text(buttonText),
                  )
                : OutlinedButton(
                    onPressed: onPressed,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF374151),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(buttonText),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillingRow(Map<String, dynamic> item, bool isLast) {
    final isPaid = item['status'] == 'Paid';
    final isCompleted = item['status'] == 'Completed';
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(item['date'], style: const TextStyle(fontSize: 13, color: Color(0xFF374151)))),
          Expanded(flex: 4, child: Text(item['description'], style: const TextStyle(fontSize: 13, color: Color(0xFF374151)))),
          Expanded(flex: 2, child: Text(item['amount'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151)))),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isPaid ? emerald50 : (isCompleted ? const Color(0xFFF3F4F6) : const Color(0xFFFEF3C7)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isPaid ? emerald500 : (isCompleted ? Colors.grey.shade500 : Colors.amber.shade600),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        item['status'],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isPaid ? emerald600 : (isCompleted ? Colors.grey.shade600 : Colors.amber.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: GestureDetector(
              onTap: () {},
              child: Icon(Icons.download_outlined, size: 18, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== SUBSCRIBE DIALOG ====================
class SubscribeDialog extends StatefulWidget {
  final String packName;
  final String monthlyPrice;
  final List<String> features;
  final VoidCallback onSuccess;

  const SubscribeDialog({
    super.key,
    required this.packName,
    required this.monthlyPrice,
    required this.features,
    required this.onSuccess,
  });

  @override
  State<SubscribeDialog> createState() => _SubscribeDialogState();
}

class _SubscribeDialogState extends State<SubscribeDialog> {
  String selectedPlan = 'yearly';
  bool agreedToTerms = false;

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald50 = Color(0xFFECFDF5);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Close Button
            Align(
              alignment: Alignment.topRight,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.close, size: 20, color: Colors.grey.shade400),
              ),
            ),

            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: emerald500,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
            ),

            const SizedBox(height: 20),

            // Title
            Text(
              "Subscribe to ${widget.packName}",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
            ),
            const SizedBox(height: 8),
            Text(
              "Unlock advanced analytics and automation for your weighbridge operations.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.5),
            ),

            const SizedBox(height: 24),

            // Features
            ...widget.features.map((feature) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(Icons.check_circle, size: 18, color: emerald500),
                  const SizedBox(width: 10),
                  Text(feature, style: const TextStyle(fontSize: 14, color: Color(0xFF374151))),
                ],
              ),
            )),

            const SizedBox(height: 20),

            // Plan Selection
            // Monthly
            GestureDetector(
              onTap: () => setState(() => selectedPlan = 'monthly'),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: selectedPlan == 'monthly' ? emerald50 : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: selectedPlan == 'monthly' ? emerald500 : const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: selectedPlan == 'monthly' ? emerald500 : Colors.grey.shade400, width: 2),
                      ),
                      child: selectedPlan == 'monthly'
                          ? Center(child: Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: emerald500)))
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Monthly", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                        Text("Pay as you go", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      ],
                    ),
                    const Spacer(),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(text: "₹2,999", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
                          TextSpan(text: "/mo", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Yearly
            GestureDetector(
              onTap: () => setState(() => selectedPlan = 'yearly'),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: selectedPlan == 'yearly' ? emerald50 : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: selectedPlan == 'yearly' ? emerald500 : const Color(0xFFE5E7EB), width: selectedPlan == 'yearly' ? 2 : 1),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: selectedPlan == 'yearly' ? emerald500 : Colors.grey.shade400, width: 2),
                      ),
                      child: selectedPlan == 'yearly'
                          ? Center(child: Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: emerald500)))
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text("Yearly", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: emerald500, borderRadius: BorderRadius.circular(4)),
                              child: const Text("Save 17%", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
                            ),
                          ],
                        ),
                        Text("Billed annually", style: TextStyle(fontSize: 12, color: emerald600)),
                      ],
                    ),
                    const Spacer(),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(text: "₹29,990", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
                          TextSpan(text: "/yr", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Total Due
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Total due today", style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                Text(selectedPlan == 'yearly' ? "₹29,990" : "₹2,999", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
              ],
            ),

            const SizedBox(height: 20),

            // Terms Checkbox
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: agreedToTerms,
                    onChanged: (val) => setState(() => agreedToTerms = val ?? false),
                    activeColor: emerald500,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
                      children: [
                        const TextSpan(text: "I agree to the "),
                        TextSpan(text: "Terms of Service", style: TextStyle(color: emerald600, fontWeight: FontWeight.w500)),
                        const TextSpan(text: " and "),
                        TextSpan(text: "Privacy Policy", style: TextStyle(color: emerald600, fontWeight: FontWeight.w500)),
                        const TextSpan(text: ". I understand my subscription will renew automatically."),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Secure Payment Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 6),
                Text("SECURE PAYMENT VIA RAZORPAY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade400, letterSpacing: 0.5)),
              ],
            ),

            const SizedBox(height: 20),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text("Cancel"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: agreedToTerms ? widget.onSuccess : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: emerald500,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                      disabledBackgroundColor: Colors.grey.shade300,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Subscribe Now"),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward, size: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== PAYMENT SUCCESS DIALOG ====================
class PaymentSuccessDialog extends StatelessWidget {
  final String packName;
  final String amount;
  final VoidCallback onDashboard;

  const PaymentSuccessDialog({
    super.key,
    required this.packName,
    required this.amount,
    required this.onDashboard,
  });

  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Success Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: emerald500,
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 36),
            ),

            const SizedBox(height: 24),

            // Title
            const Text(
              "Payment Successful",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
            ),
            const SizedBox(height: 8),
            Text(
              "Your subscription to $packName is now active.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),

            const SizedBox(height: 24),

            // Receipt Details
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _receiptRow("Pack Name", packName),
                  const SizedBox(height: 12),
                  _receiptRow("Amount Paid", "\$199.00"),
                  const SizedBox(height: 12),
                  _receiptRow("Next Billing Date", "October 24, 2024"),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Go to Dashboard Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onDashboard,
                style: ElevatedButton.styleFrom(
                  backgroundColor: emerald500,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: const Text("Go to Dashboard"),
              ),
            ),

            const SizedBox(height: 12),

            // Download Receipt
            TextButton(
              onPressed: () {},
              child: Text("Download Receipt PDF", style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
      ],
    );
  }
}
