import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/features/weighment/application/inline_verification_provider.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';
import 'package:weighbridgemanagement/shared/providers/camera_provider.dart';

class DeviceStatusBar extends ConsumerWidget {
  final Duration elapsed;
  final bool sessionActive;
  final bool isVerified;
  final String? verificationMethod;

  const DeviceStatusBar({
    super.key,
    this.elapsed = Duration.zero,
    this.sessionActive = false,
    this.isVerified = false,
    this.verificationMethod,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameras = ref.watch(activeWeighbridgeCamerasProvider).valueOrNull ?? [];
    final aiAvailable = ref.watch(aiAvailableProvider).valueOrNull ?? false;
    final inlineVerify = ref.watch(inlineVerificationProvider);
    final scheme = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;

    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.15))),
      ),
      child: Row(
        children: [
          // Verification status
          _StatusChip(
            icon: isVerified
                ? Icons.verified_user_rounded
                : inlineVerify.phase == VerificationUIPhase.background
                    ? Icons.hourglass_top_rounded
                    : inlineVerify.phase == VerificationUIPhase.pinRequired
                        ? Icons.pin_rounded
                        : Icons.shield_rounded,
            label: isVerified
                ? 'Verified${verificationMethod != null ? ' ($verificationMethod)' : ''}'
                : inlineVerify.phase == VerificationUIPhase.background
                    ? 'Verifying...'
                    : inlineVerify.phase == VerificationUIPhase.pinRequired
                        ? 'PIN Required'
                        : 'Ready',
            color: isVerified
                ? Colors.green
                : inlineVerify.phase == VerificationUIPhase.background
                    ? Colors.blue
                    : inlineVerify.phase == VerificationUIPhase.pinRequired
                        ? Colors.orange
                        : scheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),

          const SizedBox(width: 20),

          // Cameras
          _StatusChip(
            icon: Icons.videocam_rounded,
            label: '${cameras.length} cam${cameras.length == 1 ? '' : 's'}',
            color: cameras.isNotEmpty ? Colors.green : scheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),

          const SizedBox(width: 20),

          // AI
          _StatusChip(
            icon: Icons.smart_toy_rounded,
            label: aiAvailable ? 'AI Ready' : 'AI Off',
            color: aiAvailable ? Colors.green : scheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),

          // Timer
          if (sessionActive) ...[
            const SizedBox(width: 20),
            _StatusChip(
              icon: Icons.timer_outlined,
              label: '$minutes:$seconds',
              color: scheme.onSurfaceVariant,
            ),
          ],

          const Spacer(),

          // Operator name
          if (user?.displayName != null || user?.email != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_rounded, size: 13, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                const SizedBox(width: 4),
                Text(
                  user?.displayName ?? user!.email!.split('@').first,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.7), fontWeight: FontWeight.w500),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7, height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 5),
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
