import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import 'package:weighbridgemanagement/shared/providers/general_settings_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';

final _allWeighmentsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final db = ref.watch(firestoreProvider);
  return db.collection('weighments').orderBy('createdAt', descending: true).snapshots().map(
        (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
      );
});

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _search = '';
  String _statusFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final weighmentsAsync = ref.watch(_allWeighmentsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reports', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('All weighment records and history.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 20),

          // Filters
          Row(
            children: [
              SizedBox(
                width: 240,
                height: 38,
                child: TextField(
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search vehicle, customer, RST...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: scheme.outlineVariant)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('All')),
                  ButtonSegment(value: 'completed', label: Text('Completed')),
                  ButtonSegment(value: 'awaitingTare', label: Text('Pending')),
                ],
                selected: {_statusFilter},
                onSelectionChanged: (v) => setState(() => _statusFilter = v.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: scheme.primaryContainer,
                  textStyle: text.labelSmall,
                ),
              ),
              const Spacer(),
              if (ref.watch(permissionServiceProvider).canExportData)
                FilledButton.icon(
                  onPressed: () {
                    // TODO: implement export
                  },
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Export'),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Table
          Expanded(
            child: weighmentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (weighments) {
                var filtered = weighments;
                if (_statusFilter != 'all') {
                  filtered = filtered.where((w) => w['status'] == _statusFilter).toList();
                }
                if (_search.isNotEmpty) {
                  filtered = filtered.where((w) {
                    final vehicle = (w['vehicleNumber'] as String? ?? '').toLowerCase();
                    final customer = (w['customerName'] as String? ?? '').toLowerCase();
                    final rst = (w['rstNumber'] as String? ?? '').toLowerCase();
                    return vehicle.contains(_search) || customer.contains(_search) || rst.contains(_search);
                  }).toList();
                }

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 48, color: scheme.outlineVariant),
                        const SizedBox(height: 8),
                        Text('No records found', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  );
                }

                return Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 20,
                      horizontalMargin: 16,
                      columns: const [
                        DataColumn(label: Text('RST')),
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Vehicle')),
                        DataColumn(label: Text('Customer')),
                        DataColumn(label: Text('Material')),
                        DataColumn(label: Text('Gross'), numeric: true),
                        DataColumn(label: Text('Tare'), numeric: true),
                        DataColumn(label: Text('Net'), numeric: true),
                        DataColumn(label: Text('Status')),
                      ],
                      rows: filtered.map((w) {
                        final ts = w['createdAt'] as Timestamp?;
                        final date = ts != null ? formatTimestamp(ts, ref.read(timeFormatProvider), dateFormat: 'dd/MM/yy') : '--';
                        final gross = w['grossWeight'] as num?;
                        final tare = w['tareWeight'] as num?;
                        final net = w['netWeight'] as num?;
                        final fmt = NumberFormat('#,###');

                        return DataRow(cells: [
                          DataCell(Text('#${w['rstNumber'] ?? '--'}')),
                          DataCell(Text(date)),
                          DataCell(Text(w['vehicleNumber'] ?? '--')),
                          DataCell(Text(w['customerName'] ?? '--')),
                          DataCell(Text(w['material'] ?? '--')),
                          DataCell(Text(gross != null ? fmt.format(gross) : '--')),
                          DataCell(Text(tare != null ? fmt.format(tare) : '--')),
                          DataCell(Text(net != null ? fmt.format(net) : '--', style: const TextStyle(fontWeight: FontWeight.w600))),
                          DataCell(_badge(w['status'] as String? ?? 'pending', scheme)),
                        ]);
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String status, ColorScheme scheme) {
    final (Color bg, Color fg, String label) = switch (status) {
      'completed' => (scheme.primaryContainer, scheme.onPrimaryContainer, 'Done'),
      'awaitingTare' => (scheme.tertiaryContainer, scheme.onTertiaryContainer, 'Pending'),
      _ => (scheme.surfaceContainerHigh, scheme.onSurfaceVariant, status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}
