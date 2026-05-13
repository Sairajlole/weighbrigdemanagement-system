import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';

final _operatorsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final db = ref.watch(firestoreProvider);
  return db.collection('operators').snapshots().map(
        (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
      );
});

class OperatorsScreen extends ConsumerWidget {
  const OperatorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final operatorsAsync = ref.watch(_operatorsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Operators', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Manage team members and access control.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          Expanded(
            child: operatorsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (operators) {
                final pending = operators.where((o) => o['isVerified'] == false).toList();
                final active = operators.where((o) => o['isVerified'] == true).toList();

                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (pending.isNotEmpty) ...[
                        Text('Pending Approval', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        ...pending.map((op) => _PendingCard(operator: op, ref: ref, scheme: scheme, text: text)),
                        const SizedBox(height: 24),
                      ],
                      Text('Team Members', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      if (active.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(40),
                            child: Text('No operators yet.', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                          ),
                          child: DataTable(
                            columnSpacing: 24,
                            horizontalMargin: 16,
                            columns: const [
                              DataColumn(label: Text('Name')),
                              DataColumn(label: Text('Email')),
                              DataColumn(label: Text('Role')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Actions')),
                            ],
                            rows: active.map((op) {
                              final isActive = op['isActive'] == true;
                              return DataRow(cells: [
                                DataCell(Text(op['name'] ?? '--')),
                                DataCell(Text(op['email'] ?? '--')),
                                DataCell(Text(op['role'] ?? 'operator')),
                                DataCell(Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isActive ? scheme.primaryContainer : scheme.errorContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isActive ? 'Active' : 'Inactive',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isActive ? scheme.onPrimaryContainer : scheme.onErrorContainer,
                                    ),
                                  ),
                                )),
                                DataCell(IconButton(
                                  icon: Icon(
                                    isActive ? Icons.block : Icons.check_circle_outline,
                                    size: 18,
                                    color: isActive ? scheme.error : scheme.primary,
                                  ),
                                  tooltip: isActive ? 'Deactivate' : 'Activate',
                                  onPressed: () {
                                    ref.read(firestoreProvider).collection('operators').doc(op['id']).update({'isActive': !isActive});
                                  },
                                )),
                              ]);
                            }).toList(),
                          ),
                        ),
                    ],
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

class _PendingCard extends StatelessWidget {
  final Map<String, dynamic> operator;
  final WidgetRef ref;
  final ColorScheme scheme;
  final TextTheme text;

  const _PendingCard({required this.operator, required this.ref, required this.scheme, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: scheme.secondaryContainer,
            child: Text(
              (operator['name'] as String? ?? 'U').substring(0, 1).toUpperCase(),
              style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSecondaryContainer),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(operator['name'] ?? 'Unknown', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(operator['email'] ?? '', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: () {
              ref.read(firestoreProvider).collection('operators').doc(operator['id']).update({'isVerified': true});
            },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
            ),
            child: const Text('Approve'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () {
              ref.read(firestoreProvider).collection('operators').doc(operator['id']).delete();
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }
}
