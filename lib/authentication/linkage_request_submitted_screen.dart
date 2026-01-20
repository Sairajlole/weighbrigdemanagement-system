import 'package:flutter/material.dart';

class LinkageRequestSubmittedScreen extends StatelessWidget {
  const LinkageRequestSubmittedScreen({super.key});

  void handleRefreshStatus() {
    debugPrint("Refreshing status...");
  }

//  void handleSignOut() {
//   debugPrint("Signing out...");
  
// }


  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFFC5D9D0);
    const greenColor = Color(0xFF5A8A6F);

    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 420,
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
              children: [
                // ✅ Success Icon
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFE8F0EC),
                  ),
                  child: Center(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: greenColor,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // ✅ Title
                const Text(
                  "Linkage Request Submitted",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 12),

                // ✅ Description
                RichText(
                  textAlign: TextAlign.center,
                  text: const TextSpan(
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                    children: [
                      TextSpan(text: "Your request to join "),
                      TextSpan(
                        text: "Global Logistics Ltd.",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                      TextSpan(text: " has been sent\n"),
                      TextSpan(
                        text:
                            "to the administrator. Please wait for approval.",
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // ✅ Info Box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text(
                            "Company Code",
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                          Text(
                            "AX-9928",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text(
                            "Request Date",
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                          Text(
                            "Oct 24, 2023",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // ✅ Refresh Status Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: handleRefreshStatus,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: greenColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      "Refresh Status",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // ✅ Sign Out Button
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text(
                      "Sign Out",
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
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
}
