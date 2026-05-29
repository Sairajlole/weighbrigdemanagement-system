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
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      margin: margin ?? EdgeInsets.only(bottom: AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: dirty
              ? scheme.primary.withValues(alpha: 0.4)
              : scheme.outlineVariant.withValues(alpha: 0.3),
        ),
        boxShadow: AppElevation.card(scheme.shadow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            _CardHeader(
              title: title!,
              icon: icon,
              dirty: dirty,
              scheme: scheme,
              text: text,
              onSave: onSave,
              onReset: onReset,
              actions: actions,
            ),
          Padding(
            padding: padding ?? AppSpacing.cardPadding,
            child: child,
          ),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final bool dirty;
  final ColorScheme scheme;
  final TextTheme text;
  final VoidCallback? onSave;
  final VoidCallback? onReset;
  final List<Widget>? actions;

  const _CardHeader({
    required this.title,
    this.icon,
    required this.dirty,
    required this.scheme,
    required this.text,
    this.onSave,
    this.onReset,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppRadius.lg - 1),
          topRight: Radius.circular(AppRadius.lg - 1),
        ),
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppSizes.iconSm, color: scheme.primary),
            SizedBox(width: AppSpacing.sm),
          ],
          Text(
            title,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (dirty) ...[
            SizedBox(width: AppSpacing.sm),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
          const Spacer(),
          if (actions != null) ...actions!,
          if (onReset != null)
            TextButton(
              onPressed: onReset,
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Reset', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ),
          if (onSave != null) ...[
            SizedBox(width: AppSpacing.xs),
            FilledButton(
              onPressed: onSave,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              child: const Text('Save'),
            ),
          ],
        ],
      ),
    );
  }
}
