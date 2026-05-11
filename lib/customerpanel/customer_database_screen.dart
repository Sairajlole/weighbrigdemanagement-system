import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:weighbridgemanagement/core/providers/providers.dart';
import 'package:weighbridgemanagement/core/models/customer.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';
import 'package:weighbridgemanagement/customerpanel/add_customer_dialog.dart';

class CustomerDatabaseScreen extends ConsumerStatefulWidget {
  const CustomerDatabaseScreen({super.key});

  @override
  ConsumerState<CustomerDatabaseScreen> createState() => _CustomerDatabaseScreenState();
}

class _CustomerDatabaseScreenState extends ConsumerState<CustomerDatabaseScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersStreamProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return MainLayout(
      activeNav: "Customers",
      child: Column(
        children: [
          // Page Header
          Container(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Customer Database",
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Manage client records, view history, and update details.",
                        style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => showAddCustomerDialog(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text("Add Customer"),
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: "Search customers by name or phone...",
                  hintStyle: const TextStyle(fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Table
          Expanded(
            child: customersAsync.when(
              data: (customers) {
                final query = _searchController.text.toLowerCase();
                final filtered = query.isEmpty
                    ? customers
                    : customers.where((c) {
                        return c.name.toLowerCase().contains(query) ||
                            c.phone.contains(query);
                      }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline, size: 48, color: colorScheme.outlineVariant),
                        const SizedBox(height: 12),
                        Text(
                          customers.isEmpty ? "No customers yet" : "No results found",
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                        if (customers.isEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            "Add your first customer to get started.",
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return _buildCustomerTable(filtered, colorScheme);
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text("Error loading customers: $e"),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerTable(List<Customer> customers, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant),
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 50, child: Text("#", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
                const Expanded(flex: 3, child: Text("NAME", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
                const Expanded(flex: 2, child: Text("PHONE", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
                const Expanded(flex: 3, child: Text("ADDRESS", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
                const SizedBox(width: 80, child: Text("VISITS", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
                const SizedBox(width: 100, child: Text("LAST ACTIVE", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
                const SizedBox(width: 60, child: Text("", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
              ],
            ),
          ),

          // Rows
          Expanded(
            child: ListView.builder(
              itemCount: customers.length,
              itemBuilder: (context, index) {
                final c = customers[index];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 50,
                        child: Text(
                          "${index + 1}",
                          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: colorScheme.primaryContainer,
                              child: Text(
                                c.name.isNotEmpty ? c.name[0].toUpperCase() : "?",
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                c.name,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(c.phone, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          c.address ?? '--',
                          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text(
                          "${c.totalWeighments}",
                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        child: Text(
                          DateFormat('dd MMM yyyy').format(c.updatedAt),
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                      SizedBox(
                        width: 60,
                        child: IconButton(
                          icon: Icon(Icons.visibility_outlined, size: 18, color: colorScheme.primary),
                          onPressed: () {
                            Navigator.pushNamed(context, '/customerProfile', arguments: c);
                          },
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
