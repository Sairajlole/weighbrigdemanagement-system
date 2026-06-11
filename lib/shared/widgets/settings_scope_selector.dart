import 'package:flutter/material.dart';

import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/settings_scope_provider.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

/// A compact segmented control for choosing where a settings feature is stored:
/// this weighbridge, this site, or company-wide. Uses generic labels; the
/// actual names are only surfaced in the change-scope confirmation dialog.
class SettingsScopeSelector extends StatelessWidget {
  final CollectionScope scope;
  final ValueChanged<CollectionScope> onChanged;

  const SettingsScopeSelector({super.key, required this.scope, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.layers_rounded, size: 14, color: scheme.onSurfaceVariant),
        SizedBox(width: AppSpacing.xs),
        Text('Applies to', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
        SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
            borderRadius: AppRadius.button,
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in CollectionScope.values) _segment(s, scheme, text),
            ],
          ),
        ),
      ],
    );
  }

  Widget _segment(CollectionScope s, ColorScheme scheme, TextTheme text) {
    final selected = s == scope;
    return GestureDetector(
      onTap: selected ? null : () => onChanged(s),
      child: MouseRegion(
        cursor: selected ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : Colors.transparent,
            borderRadius: AppRadius.button,
          ),
          child: Text(
            s.shortLabel,
            style: text.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
