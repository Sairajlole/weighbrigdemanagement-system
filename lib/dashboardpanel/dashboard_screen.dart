import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:weighbridgemanagement/core/providers/providers.dart';
import 'package:weighbridgemanagement/core/models/weighment.dart';
import 'package:weighbridgemanagement/core/enums/weighment_enums.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weighmentsAsync = ref.watch(weighmentsStreamProvider);
    final operatorAsync = ref.watch(currentOperatorProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return MainLayout(
      activeNav: "Dashboard",
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Text(
                  "Dashboard Home",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                SizedBox(
                  width: 260,
                  height: 40,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: "Search RST, Vehicle...",
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: () {},
                  icon: Icon(Icons.notifications_none, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),

          // Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome + Button
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            operatorAsync.when(
                              data: (op) => Text(
                                "Welcome back, ${op?.name ?? 'Operator'}",
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              loading: () => Text(
                                "Welcome back",
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              error: (_, __) => Text(
                                "Welcome back",
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                CircleAvatar(radius: 4, backgroundColor: colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  "Active session • ${DateFormat('dd MMM yyyy').format(DateTime.now())}",
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                )
                              ],
                            )
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pushNamed(context, '/startWeighment');
                        },
                        icon: const Icon(Icons.add),
                        label: const Text("Start New Weighment"),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Stats Cards
                  weighmentsAsync.when(
                    data: (weighments) => _buildStatsAndTable(context, weighments, colorScheme),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => _buildStatsAndTable(context, [], colorScheme),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatsAndTable(
      BuildContext context, List<Weighment> weighments, ColorScheme colorScheme) {
    final today = DateTime.now();
    final todaysWeighments = weighments.where((w) {
      return w.createdAt.year == today.year &&
          w.createdAt.month == today.month &&
          w.createdAt.day == today.day;
    }).toList();

    final completed = todaysWeighments.where((w) => w.status == WeighmentStatus.completed).length;
    final pending = todaysWeighments.where((w) => w.status == WeighmentStatus.inProgress).length;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _statCard(
                context: context,
                title: "Today's Weighments",
                value: "$completed",
                subText: "${todaysWeighments.length} total today",
                icon: Icons.scale_outlined,
                iconBg: colorScheme.primaryContainer,
                iconColor: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                context: context,
                title: "Pending / In Progress",
                value: "$pending",
                subText: pending > 3 ? "High traffic" : "Normal",
                icon: Icons.hourglass_top_rounded,
                iconBg: colorScheme.tertiaryContainer,
                iconColor: colorScheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                context: context,
                title: "Total Records",
                value: "${weighments.length}",
                subText: "All time",
                icon: Icons.inventory_2_outlined,
                iconBg: colorScheme.secondaryContainer,
                iconColor: colorScheme.onSecondaryContainer,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Recent Weighments Table
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: colorScheme.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      "Recent Weighments",
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/weighmentReports'),
                      child: const Text("View All History"),
                    )
                  ],
                ),
              ),
              if (weighments.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(Icons.scale_outlined, size: 48, color: colorScheme.outlineVariant),
                      const SizedBox(height: 12),
                      Text(
                        "No weighments yet",
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Start a new weighment to see data here.",
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text("RST Number")),
                      DataColumn(label: Text("Vehicle No.")),
                      DataColumn(label: Text("Customer")),
                      DataColumn(label: Text("Material")),
                      DataColumn(label: Text("Net Weight")),
                      DataColumn(label: Text("Status")),
                    ],
                    rows: weighments.take(10).map((w) {
                      return DataRow(
                        cells: [
                          DataCell(Text("#RST-${w.rstNumber}")),
                          DataCell(Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(w.vehicleNumber),
                          )),
                          DataCell(Text(w.customerName)),
                          DataCell(Text(w.material)),
                          DataCell(Row(
                            children: [
                              Text(w.netWeight != null
                                  ? NumberFormat('#,###').format(w.netWeight)
                                  : '--'),
                              if (w.netWeight != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Text(
                                    "kg",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          )),
                          DataCell(_statusChip(w.status, colorScheme)),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              const SizedBox(height: 10),
            ],
          ),
        )
      ],
    );
  }

  Widget _statusChip(WeighmentStatus status, ColorScheme colorScheme) {
    final isComplete = status == WeighmentStatus.completed;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isComplete ? Icons.check_circle : Icons.timelapse,
          size: 18,
          color: isComplete ? colorScheme.primary : colorScheme.tertiary,
        ),
        const SizedBox(width: 6),
        Text(
          status.name[0].toUpperCase() + status.name.substring(1),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isComplete ? colorScheme.primary : colorScheme.tertiary,
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required BuildContext context,
    required String title,
    required String value,
    required String subText,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                ),
              )
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            subText,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
