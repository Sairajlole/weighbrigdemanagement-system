import 'package:flutter/material.dart';

class AdminSignupScreen extends StatefulWidget {
  const AdminSignupScreen({super.key});

  @override
  State<AdminSignupScreen> createState() => _AdminSignupScreenState();
}

class _AdminSignupScreenState extends State<AdminSignupScreen> {
  String accountType = "admin";
  bool agreedToTerms = false;

  final TextEditingController companyNameController =
      TextEditingController(text: "ABC Company Pvt Ltd");
  final TextEditingController emailController =
      TextEditingController(text: "admin@company.com");
  final TextEditingController gstinController =
      TextEditingController(text: "27ABCDE1234F1Z5");
  final TextEditingController companyCodeController =
      TextEditingController(text: "CMP - XXXX");
  final TextEditingController passwordController =
      TextEditingController(text: "........");
  final TextEditingController confirmPasswordController =
      TextEditingController(text: "........");

  void handleCreateAccount() {
    debugPrint("Create Admin account:");
    debugPrint("Account Type: $accountType");
    debugPrint("Company Name: ${companyNameController.text}");
    debugPrint("Email: ${emailController.text}");
    debugPrint("GSTIN: ${gstinController.text}");
    debugPrint("Company Code: ${companyCodeController.text}");
    debugPrint("Agreed: $agreedToTerms");
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFFC5D9D0);
    const greenColor = Color(0xFF5A8A6F);

    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 720,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo + Title
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.scale, size: 30, color: greenColor),
                    SizedBox(width: 10),
                    Text(
                      "Weighbridge Manager",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Tabs
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(context);
                        },
                        child: Column(
                          children: [
                            const Text(
                              "Log In",
                              style: TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 8),
                            Container(height: 2, color: Colors.transparent),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          const Text(
                            "Sign Up",
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Container(height: 2, color: greenColor),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Header
                const Text(
                  "Create Admin Account",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Enter your details to register as a weighbridge admin.",
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 20),

                // Account Type
                const Text(
                  "ACCOUNT TYPE",
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),

                // ✅ UPDATED HERE (Operator = back to Operator screen)
                Row(
                  children: [
                    Expanded(
                      child: accountCard(
                        title: "Operator Account",
                        subtitle: "Standard access",
                        icon: Icons.local_shipping,
                        selected: accountType == "operator",
                        onTap: () {
                           Navigator.pop(context); // ✅ back to Operator Signup
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: accountCard(
                        title: "Admin Account",
                        subtitle: "Full access",
                        icon: Icons.scale,
                        selected: accountType == "admin",
                        onTap: () {
                          setState(() {
                            accountType = "admin";
                          });
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Form Fields (Row 1) ✅ Company Name
                Row(
                  children: [
                    Expanded(
                      child: inputField("Company Name", companyNameController),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: inputField("Email Address", emailController),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Form Fields (Row 2) ✅ GSTIN No
                Row(
                  children: [
                    Expanded(
                      child: inputField("GSTIN No", gstinController),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          inputField(
                            "Ph No",
                            companyCodeController,
                            //suffixIcon: const Text("🔑"),
                          ),
                          const SizedBox(height: 4),
                          // const Text(
                          //   "Enter the code provided by your company administrator.",
                          //   style: TextStyle(fontSize: 12, color: Colors.grey),
                          // ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Form Fields (Row 3)
                Row(
                  children: [
                    Expanded(
                      child: inputField(
                        "Password",
                        passwordController,
                        obscure: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: inputField(
                        "Confirm Password",
                        confirmPasswordController,
                        obscure: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Terms
                Row(
                  children: [
                    Checkbox(
                      value: agreedToTerms,
                      onChanged: (val) {
                        setState(() {
                          agreedToTerms = val ?? false;
                        });
                      },
                    ),
                    Expanded(
                      child: Wrap(
                        children: const [
                          Text("I agree to the "),
                          Text(
                            "Terms of Service",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: greenColor,
                            ),
                          ),
                          Text(" and "),
                          Text(
                            "Privacy Policy",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: greenColor,
                            ),
                          ),
                          Text("."),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Create Account Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: handleCreateAccount,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: greenColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Create Account",
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // Login link
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text(
                      "Already have an account? Log in",
                      style: TextStyle(
                        color: greenColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Footer
                const Center(
                  child: Text(
                    "Weighbridge Management System v3.0",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------- WIDGETS --------------------

  Widget inputField(
    String label,
    TextEditingController controller, {
    bool obscure = false,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            suffixIcon: suffixIcon != null
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: suffixIcon,
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget accountCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    const greenColor = Color(0xFF5A8A6F);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            width: 2,
            color: selected ? greenColor : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? greenColor : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: greenColor,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(icon, color: greenColor),
          ],
        ),
      ),
    );
  }
}
