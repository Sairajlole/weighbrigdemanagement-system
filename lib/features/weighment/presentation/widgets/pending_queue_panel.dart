import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_providers.dart';

class PendingQueuePanel extends ConsumerWidget {
  final void Function(Map<String, dynamic> data, String docId)? onSelect;

  const PendingQueuePanel({super.key, this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingWeighmentsProvider);
    final scheme = Theme.of(context).colorScheme;
    final collapsed = ref.watch(pendingPanelCollapsedProvider);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: collapsed ? 48 : 280,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: collapsed
          ? _buildCollapsedState(context, ref, pending)
          : _buildExpandedState(context, ref, pending),
    );
  }

  Widget _buildCollapsedState(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Map<String, dynamic>>> pending,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final count = pending.whenOrNull(data: (list) => list.length) ?? 0;

    return GestureDetector(
      onTap: () => ref.read(pendingPanelCollapsedProvider.notifier).state = false,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Badge(
              label: Text('$count'),
              backgroundColor: scheme.primaryContainer,
              textColor: scheme.onPrimaryContainer,
            ),
            const SizedBox(height: 12),
            RotatedBox(
              quarterTurns: 3,
              child: Text(
                'PENDING',
                style: textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedState(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Map<String, dynamic>>> pending,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.queue_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Pending',
                style: textTheme.titleSmall?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
              const Spacer(),
              pending.when(
                data: (list) => Badge(
                  label: Text('${list.length}'),
                  backgroundColor: scheme.primaryContainer,
                  textColor: scheme.onPrimaryContainer,
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => ref.read(pendingPanelCollapsedProvider.notifier).state = true,
                borderRadius: BorderRadius.circular(4),
                child: Icon(Icons.chevron_left, size: 18, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: pending.when(
            loading: () => const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (e, _) => Center(
              child: Text(
                'Error',
                style: textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
            data: (list) {
              if (list.isEmpty) {
                return Center(
                  child: Text(
                    'No pending weighments',
                    style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: list.length,
                itemBuilder: (_, i) => _PendingTile(
                  data: list[i],
                  onTap: () => onSelect?.call(list[i], list[i]['id'] as String),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PendingTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _PendingTile({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final vehicle = data['vehicleNumber'] as String? ?? 'Unknown';
    final material = data['material'] as String? ?? '';
    final grossWeight = (data['grossWeight'] as num?)?.toDouble();
    final createdAt = data['createdAt'];
    String timeStr = '';
    if (createdAt is Timestamp) {
      timeStr = DateFormat.jm().format(createdAt.toDate());
    }

    final subtitleParts = <String>[
      if (material.isNotEmpty) material,
      if (grossWeight != null) '${grossWeight.toStringAsFixed(0)} kg',
    ];
    final subtitle = subtitleParts.join(' · ');

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Text(
        vehicle,
        style: textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle.isNotEmpty
          ? Text.rich(
              TextSpan(
                children: [
                  if (material.isNotEmpty)
                    TextSpan(
                      text: material,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (material.isNotEmpty && grossWeight != null)
                    TextSpan(
                      text: ' · ',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (grossWeight != null)
                    TextSpan(
                      text: '${grossWeight.toStringAsFixed(0)} kg',
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                ],
              ),
            )
          : null,
      trailing: timeStr.isNotEmpty
          ? Text(
              timeStr,
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}
