import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

class AppCard extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Widget child;
  final bool dirty;
  final bool collapsible;
  final bool initiallyCollapsed;
  final VoidCallback? onSave;
  final VoidCallback? onReset;
  final List<Widget>? actions;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final bool stretch;

  const AppCard({
    super.key,
    this.title,
    this.icon,
    required this.child,
    this.dirty = false,
    this.collapsible = false,
    this.initiallyCollapsed = false,
    this.onSave,
    this.onReset,
    this.actions,
    this.padding,
    this.margin,
    this.stretch = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      margin: margin ?? EdgeInsets.only(bottom: AppSpacing.lg),
      padding: padding ?? AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: dirty
              ? scheme.primary.withValues(alpha: 0.4)
              : scheme.outlineVariant.withValues(alpha: 0.25),
        ),
        boxShadow: AppElevation.card(scheme.shadow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: stretch ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: scheme.primary),
                  SizedBox(width: AppSpacing.sm),
                ],
                Text(title!, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (dirty) ...[
                  SizedBox(width: AppSpacing.sm),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                  ),
                ],
                const Spacer(),
                if (actions != null) ...actions!,
                if (onReset != null)
                  TextButton(
                    onPressed: onReset,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.chip),
                    ),
                    child: Text('Reset', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                  ),
                if (onSave != null) ...[
                  SizedBox(width: AppSpacing.sm),
                  FilledButton.tonal(
                    onPressed: onSave,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ],
            ),
            SizedBox(height: AppSpacing.lg),
          ],
          child,
        ],
      ),
    );
  }
}
