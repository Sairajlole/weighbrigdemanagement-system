import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:weighbridgemanagement/shared/providers/auth_provider.dart';

class LinkagePendingScreen extends ConsumerWidget {
  const LinkagePendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8F5E9),
      body: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 24, offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Check icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Color(0xFF4A8C5C), size: 32),
              ),
              const SizedBox(height: 20),
              const Text(
                'Linkage Request Submitted',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
              ),
              const SizedBox(height: 10),
              Text.rich(
                TextSpan(
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  children: const [
                    TextSpan(text: 'Your request to join '),
                    TextSpan(text: 'your company', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                    TextSpan(text: ' has been sent to the administrator. Please wait for approval.'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // Info rows
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    _infoRow('Request Date', DateFormat('MMM dd, yyyy').format(DateTime.now())),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Refresh button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    // Refresh will happen automatically via auth state
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A8C5C),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Refresh Status'),
                ),
              ),
              const SizedBox(height: 14),

              // Sign out
              TextButton(
                onPressed: () async {
                  await ref.read(firebaseAuthProvider).signOut();
                },
                child: const Text('Sign Out', style: TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
        ],
      ),
    );
  }
}
