import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

enum ConnectionStatus { connected, connecting, disconnected, error }

class ConnectionBadge extends StatelessWidget {
  final ConnectionStatus status;
  final String label;
  final String? detail;
  final bool compact;

  const ConnectionBadge({
    super.key,
    required this.status,
    required this.label,
    this.detail,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      ConnectionStatus.connected => const Color(0xFF16A34A),
      ConnectionStatus.connecting => scheme.tertiary,
      ConnectionStatus.disconnected => scheme.outlineVariant,
      ConnectionStatus.error => scheme.error,
    };

    if (compact) {
      return Tooltip(
        message: '$label: ${status.name}${detail != null ? ' — $detail' : ''}',
        child: Container(
          width: 8.rs,
          height: 8.rs,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: status == ConnectionStatus.connected
                ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 4)]
                : null,
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadius.chip,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == ConnectionStatus.connecting)
            SizedBox(
              width: 10.rs,
              height: 10.rs,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            )
          else
            Container(
              width: 6.rs,
              height: 6.rs,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: status == ConnectionStatus.connected
                    ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 4)]
                    : null,
              ),
            ),
          SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          if (detail != null) ...[
            SizedBox(width: AppSpacing.xs),
            Text(
              detail!,
              style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.7)),
            ),
          ],
        ],
      ),
    );
  }
}
