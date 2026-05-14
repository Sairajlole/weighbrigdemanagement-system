// ignore_for_file: unused_element

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';

final _customersProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final db = ref.watch(firestoreProvider);
  return db.collection('customers').snapshots().map(
        (snap) {
          final list = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          list.sort((a, b) => (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));
          return list;
        },
      );
});

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _search = '';

  /// Masks a phone number to show only last 4 digits: ****1234
  String _maskPhone(String? phone) {
    if (phone == null || phone.isEmpty) return '--';
    if (phone.length <= 4) return '****$phone';
    return '****${phone.substring(phone.length - 4)}';
  }

  /// Masks a PAN field to show only last 5 chars: *****1234A
  String _maskPan(String? pan) {
    if (pan == null || pan.isEmpty) return '--';
    if (pan.length <= 5) return '*****$pan';
    return '*****${pan.substring(pan.length - 5)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final customersAsync = ref.watch(_customersProvider);
    final shouldMask = ref.watch(permissionServiceProvider).shouldMaskSensitive;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Customers', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              SizedBox(
                width: 220,
                height: 38,
                child: TextField(
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: scheme.outlineVariant)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _showAddDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Customer'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: customersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (customers) {
                final filtered = _search.isEmpty
                    ? customers
                    : customers.where((c) =>
                        (c['name'] as String? ?? '').toLowerCase().contains(_search) ||
                        (c['phone'] as String? ?? '').contains(_search)).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline, size: 48, color: scheme.outlineVariant),
                        const SizedBox(height: 8),
                        Text('No customers found', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
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
                      columnSpacing: 32,
                      horizontalMargin: 16,
                      columns: const [
                        DataColumn(label: Text('Name')),
                        DataColumn(label: Text('Phone')),
                        DataColumn(label: Text('Address')),
                        DataColumn(label: Text('Weighments'), numeric: true),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: filtered.map((c) => DataRow(cells: [
                            DataCell(Text(c['name'] ?? '--')),
                            DataCell(Text(shouldMask ? _maskPhone(c['phone'] as String?) : (c['phone'] ?? '--'))),
                            DataCell(Text(c['address'] ?? '--')),
                            DataCell(Text('${c['totalWeighments'] ?? 0}')),
                            DataCell(IconButton(
                              icon: Icon(Icons.edit_outlined, size: 18, color: scheme.primary),
                              onPressed: () => _showEditDialog(context, c),
                            )),
                          ])).toList(),
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

  void _showAddDialog(BuildContext context) {
    final nameC = TextEditingController();
    final phoneC = TextEditingController();
    final addressC = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Customer'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 12),
              TextField(controller: phoneC, decoration: const InputDecoration(labelText: 'Phone')),
              const SizedBox(height: 12),
              TextField(controller: addressC, decoration: const InputDecoration(labelText: 'Address')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (nameC.text.trim().isEmpty || phoneC.text.trim().isEmpty) return;
              final db = ref.read(firestoreProvider);
              final now = Timestamp.now();
              await db.collection('customers').add({
                'name': nameC.text.trim(),
                'phone': phoneC.text.trim(),
                'address': addressC.text.trim().isEmpty ? null : addressC.text.trim(),
                'totalWeighments': 0,
                'totalNetWeight': 0,
                'createdAt': now,
                'updatedAt': now,
              });
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, Map<String, dynamic> customer) {
    final nameC = TextEditingController(text: customer['name']);
    final phoneC = TextEditingController(text: customer['phone']);
    final addressC = TextEditingController(text: customer['address'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Customer'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 12),
              TextField(controller: phoneC, decoration: const InputDecoration(labelText: 'Phone')),
              const SizedBox(height: 12),
              TextField(controller: addressC, decoration: const InputDecoration(labelText: 'Address')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final db = ref.read(firestoreProvider);
              await db.collection('customers').doc(customer['id']).update({
                'name': nameC.text.trim(),
                'phone': phoneC.text.trim(),
                'address': addressC.text.trim().isEmpty ? null : addressC.text.trim(),
                'updatedAt': Timestamp.now(),
              });
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
