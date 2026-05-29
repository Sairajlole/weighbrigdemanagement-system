import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/license_provider.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

class ProFeatureBanner extends ConsumerWidget {
  final String feature;
  const ProFeatureBanner({super.key, required this.feature});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFree = ref.watch(isFreeProvider);
    if (!isFree) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    const proColor = AppTheme.proColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [proColor.withValues(alpha: 0.06), proColor.withValues(alpha: 0.02)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(10.rs),
        border: Border.all(color: proColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.workspace_premium_rounded, size: 20, color: proColor),
          SizedBox(width: 12.rs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pro Feature', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: proColor)),
                Text(
                  '$feature requires a Pro license. Upgrade to unlock.',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          SizedBox(width: 12.rs),
          FilledButton.tonal(
            onPressed: () => context.go('/settings/license'),
            style: FilledButton.styleFrom(
              backgroundColor: proColor.withValues(alpha: 0.1),
              foregroundColor: proColor,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }
}
