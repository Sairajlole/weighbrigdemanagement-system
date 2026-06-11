import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/settings_scope_provider.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

/// Polished confirmation shown before changing a settings scope. The actual
/// weighbridge/site/company names appear ONLY on the CURRENT → NEW pills;
/// everything else is generic. Returns true if the user confirms.
///
/// [noun] is the thing being scoped, e.g. 'template', 'materials', 'fields'.
Future<bool> showScopeChangeDialog(
  BuildContext context,
  WidgetRef ref, {
  required CollectionScope from,
  required CollectionScope to,
  String noun = 'settings',
  bool saveGated = true,
}) async {
  final names = ref.read(scopeNamesProvider).valueOrNull;
  String nm(CollectionScope s) => names != null ? scopeName(names, s) : s.label;

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      final text = Theme.of(ctx).textTheme;
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.14)),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), borderRadius: AppRadius.button),
                      child: Icon(Icons.layers_rounded, size: 20, color: scheme.primary),
                    ),
                    SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Change $noun scope', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          SizedBox(height: 2.rs),
                          Text('Where these $noun settings apply', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _pill(nm(from), false, scheme, text)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.rs),
                          child: Icon(Icons.arrow_forward_rounded, size: 18, color: scheme.onSurfaceVariant),
                        ),
                        Expanded(child: _pill(nm(to), true, scheme, text)),
                      ],
                    ),
                    SizedBox(height: AppSpacing.lg),
                    Container(
                      width: double.infinity,
                      padding: AppSpacing.cardPadding,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh.withValues(alpha: 0.4),
                        borderRadius: AppRadius.card,
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('WHAT WILL CHANGE', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.5, color: scheme.onSurfaceVariant)),
                          SizedBox(height: AppSpacing.sm),
                          _bullet(Icons.content_copy_rounded, 'Your current $noun is copied to the new scope — nothing is lost.', scheme, text),
                          _bullet(Icons.groups_rounded, _summary(to), scheme, text),
                          if (to == CollectionScope.company || to == CollectionScope.site)
                            _bullet(Icons.history_rounded, 'Per-weighbridge $noun stays saved and returns if you switch back.', scheme, text),
                          _bullet(saveGated ? Icons.save_rounded : Icons.bolt_rounded,
                              saveGated ? 'Takes effect when you press Save — Cancel reverts it.' : 'Applies immediately when you confirm.',
                              scheme, text, highlight: true),
                        ],
                      ),
                    ),
                    SizedBox(height: AppSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        SizedBox(width: AppSpacing.sm),
                        FilledButton.icon(
                          onPressed: () => Navigator.pop(ctx, true),
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: Text('Use ${to.shortLabel}'),
                          style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  return result == true;
}

String _summary(CollectionScope scope) => switch (scope) {
      CollectionScope.weighbridge => 'Applies to the current weighbridge only.',
      CollectionScope.site => 'Shared by every weighbridge in this site.',
      CollectionScope.company => 'Shared by every weighbridge in the company.',
    };

Widget _pill(String label, bool active, ColorScheme scheme, TextTheme text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: active ? scheme.primary.withValues(alpha: 0.10) : scheme.surfaceContainerHigh.withValues(alpha: 0.5),
      borderRadius: AppRadius.button,
      border: Border.all(color: active ? scheme.primary.withValues(alpha: 0.4) : scheme.outlineVariant.withValues(alpha: 0.3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(active ? 'NEW' : 'CURRENT', style: text.labelSmall?.copyWith(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: active ? scheme.primary : scheme.onSurfaceVariant)),
        SizedBox(height: 2.rs),
        Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: active ? scheme.primary : scheme.onSurface)),
      ],
    ),
  );
}

Widget _bullet(IconData icon, String label, ColorScheme scheme, TextTheme text, {bool highlight = false}) {
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: highlight ? scheme.primary : scheme.onSurfaceVariant),
        SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: text.bodySmall?.copyWith(height: 1.4, fontWeight: highlight ? FontWeight.w700 : FontWeight.w500, color: highlight ? scheme.primary : scheme.onSurface),
          ),
        ),
      ],
    ),
  );
}
