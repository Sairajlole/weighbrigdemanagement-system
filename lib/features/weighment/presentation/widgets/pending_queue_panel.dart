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

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(right: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.queue_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Pending',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface),
                ),
                const Spacer(),
                pending.when(
                  data: (list) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${list.length}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.primary),
                    ),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.2)),
          Expanded(
            child: pending.when(
              loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              error: (e, _) => Center(child: Text('Error', style: TextStyle(color: scheme.error, fontSize: 12))),
              data: (list) {
                if (list.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline_rounded, size: 32, color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
                        const SizedBox(height: 8),
                        Text('No pending', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
                      ],
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
      ),
    );
  }
}

class _PendingTile extends StatefulWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _PendingTile({required this.data, required this.onTap});

  @override
  State<_PendingTile> createState() => _PendingTileState();
}

class _PendingTileState extends State<_PendingTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final vehicle = widget.data['vehicleNumber'] as String? ?? 'Unknown';
    final material = widget.data['material'] as String? ?? '';
    final grossWeight = (widget.data['grossWeight'] as num?)?.toDouble();
    final createdAt = widget.data['createdAt'];
    String timeStr = '';
    if (createdAt is Timestamp) {
      timeStr = DateFormat.jm().format(createdAt.toDate());
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered ? scheme.primary.withValues(alpha: 0.06) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: _hovered ? Border.all(color: scheme.primary.withValues(alpha: 0.2)) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      vehicle,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (timeStr.isNotEmpty)
                    Text(timeStr, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (material.isNotEmpty)
                    Text(material, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                  if (material.isNotEmpty && grossWeight != null)
                    Text(' · ', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                  if (grossWeight != null)
                    Text(
                      '${grossWeight.toStringAsFixed(0)} kg',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.primary),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
