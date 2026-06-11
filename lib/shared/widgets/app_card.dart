import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

class AppCard extends StatefulWidget {
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
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  late bool _collapsed = widget.collapsible && widget.initiallyCollapsed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final w = widget;
    // A header is shown if there's a title OR the card can be collapsed (the
    // chevron lives in the header).
    final showHeader = w.title != null || w.collapsible;

    return Container(
      margin: w.margin ?? EdgeInsets.only(bottom: AppSpacing.lg),
      padding: w.padding ?? AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: w.dirty
              ? scheme.primary.withValues(alpha: 0.4)
              : scheme.outlineVariant.withValues(alpha: 0.25),
        ),
        boxShadow: AppElevation.card(scheme.shadow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: (w.stretch && !_collapsed) ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (showHeader) ...[
            Row(
              children: [
                if (w.icon != null) ...[
                  Icon(w.icon, size: 18, color: scheme.primary),
                  SizedBox(width: AppSpacing.sm),
                ],
                if (w.title != null)
                  Text(w.title!, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (w.dirty) ...[
                  SizedBox(width: AppSpacing.sm),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                  ),
                ],
                const Spacer(),
                if (w.actions != null) ...w.actions!,
                if (w.onReset != null)
                  TextButton(
                    onPressed: w.onReset,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.chip),
                    ),
                    child: Text('Reset', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                  ),
                if (w.onSave != null) ...[
                  SizedBox(width: AppSpacing.sm),
                  FilledButton.tonal(
                    onPressed: w.onSave,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    child: const Text('Save'),
                  ),
                ],
                if (w.collapsible) ...[
                  SizedBox(width: AppSpacing.xs),
                  IconButton(
                    icon: Icon(_collapsed ? Icons.expand_more_rounded : Icons.expand_less_rounded, size: 20),
                    onPressed: () => setState(() => _collapsed = !_collapsed),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    color: scheme.onSurfaceVariant,
                    tooltip: _collapsed ? 'Expand' : 'Collapse',
                  ),
                ],
              ],
            ),
            if (!_collapsed) SizedBox(height: AppSpacing.lg),
          ],
          if (!_collapsed) w.child,
        ],
      ),
    );
  }
}
