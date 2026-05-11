import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:weighbridgemanagement/core/enums/weighment_enums.dart';
import 'package:weighbridgemanagement/core/models/operator_model.dart';
import 'package:weighbridgemanagement/core/providers/providers.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class OperatorRequestsScreen extends ConsumerWidget {
  const OperatorRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentOp = ref.watch(currentOperatorProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return MainLayout(
      activeNav: "Operators",
      child: currentOp.when(
        data: (op) {
          if (op == null) return const Center(child: Text("Not logged in"));
          final operatorsAsync = ref.watch(operatorsStreamProvider(op.companyId));
          return operatorsAsync.when(
            data: (operators) => _buildBody(context, ref, operators, colorScheme),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text("Error: $e")),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text("Error loading profile")),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, List<Operator> operators, ColorScheme colorScheme) {
    final pending = operators.where((o) => !o.isVerified).toList();
    final active = operators.where((o) => o.isVerified && o.isActive).toList();
    final all = operators;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: Row(
            children: [
              Icon(Icons.manage_accounts_outlined, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Operator Management",
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text("Approve, manage, and monitor operators in your company",
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats
                Row(
                  children: [
                    _statCard(context, "Pending Approval", "${pending.length}", Icons.hourglass_top, colorScheme.tertiaryContainer, colorScheme.onTertiaryContainer),
                    const SizedBox(width: 12),
                    _statCard(context, "Active Operators", "${active.length}", Icons.check_circle_outline, colorScheme.primaryContainer, colorScheme.onPrimaryContainer),
                    const SizedBox(width: 12),
                    _statCard(context, "Total Registered", "${all.length}", Icons.people_outlined, colorScheme.secondaryContainer, colorScheme.onSecondaryContainer),
                  ],
                ),

                const SizedBox(height: 24),

                // Pending Requests
                if (pending.isNotEmpty) ...[
                  Text("PENDING APPROVAL",
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  ...pending.map((op) => _pendingCard(context, ref, op, colorScheme)),
                  const SizedBox(height: 24),
                ],

                // Active Operators Table
                Text("ALL OPERATORS",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),

                Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: operators.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(40),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.people_outlined, size: 48, color: colorScheme.outlineVariant),
                                const SizedBox(height: 12),
                                Text("No operators yet", style: TextStyle(color: colorScheme.onSurfaceVariant)),
                                const SizedBox(height: 4),
                                Text("Share your company linkage code to invite operators.",
                                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text("Name")),
                              DataColumn(label: Text("Email")),
                              DataColumn(label: Text("Phone")),
                              DataColumn(label: Text("Role")),
                              DataColumn(label: Text("Status")),
                              DataColumn(label: Text("Joined")),
                              DataColumn(label: Text("Actions")),
                            ],
                            rows: operators.map((op) => DataRow(cells: [
                              DataCell(Text(op.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                              DataCell(Text(op.email)),
                              DataCell(Text(op.phone ?? '--')),
                              DataCell(_roleBadge(op.role, colorScheme)),
                              DataCell(_statusBadge(op, colorScheme)),
                              DataCell(Text(DateFormat('dd MMM yyyy').format(op.createdAt))),
                              DataCell(Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!op.isVerified)
                                    IconButton(
                                      icon: Icon(Icons.check_circle, size: 18, color: colorScheme.primary),
                                      tooltip: "Approve",
                                      onPressed: () => _approve(ref, op),
                                    ),
                                  if (op.isVerified && op.isActive)
                                    IconButton(
                                      icon: Icon(Icons.block, size: 18, color: colorScheme.error),
                                      tooltip: "Deactivate",
                                      onPressed: () => _deactivate(ref, op),
                                    ),
                                  if (op.isVerified && !op.isActive)
                                    IconButton(
                                      icon: Icon(Icons.restore, size: 18, color: colorScheme.primary),
                                      tooltip: "Reactivate",
                                      onPressed: () => _activate(ref, op),
                                    ),
                                ],
                              )),
                            ])).toList(),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _statCard(BuildContext context, String title, String value, IconData icon, Color bgColor, Color fgColor) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 20, color: fgColor),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text(title, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingCard(BuildContext context, WidgetRef ref, Operator op, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: colorScheme.tertiaryContainer,
            child: Text(op.name.isNotEmpty ? op.name[0].toUpperCase() : "?",
                style: TextStyle(fontWeight: FontWeight.w700, color: colorScheme.onTertiaryContainer)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(op.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text("${op.email}${op.phone != null ? ' • ${op.phone}' : ''}",
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                Text("Joined ${DateFormat('dd MMM yyyy').format(op.createdAt)}",
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: () => _approve(ref, op),
            icon: const Icon(Icons.check, size: 16),
            label: const Text("Approve"),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => _reject(context, ref, op),
            style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
            child: const Text("Reject"),
          ),
        ],
      ),
    );
  }

  Widget _roleBadge(UserRole role, ColorScheme colorScheme) {
    final label = switch (role) {
      UserRole.companyAdmin => "Admin",
      UserRole.operator => "Operator",
      UserRole.systemAdmin => "System",
      UserRole.support => "Support",
    };
    final isAdmin = role == UserRole.companyAdmin || role == UserRole.systemAdmin;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isAdmin ? colorScheme.primaryContainer : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: isAdmin ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
      )),
    );
  }

  Widget _statusBadge(Operator op, ColorScheme colorScheme) {
    final (String label, Color bg, Color fg) = !op.isVerified
        ? ("Pending", colorScheme.tertiaryContainer, colorScheme.onTertiaryContainer)
        : op.isActive
            ? ("Active", colorScheme.primaryContainer, colorScheme.onPrimaryContainer)
            : ("Inactive", colorScheme.errorContainer, colorScheme.onErrorContainer);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  void _approve(WidgetRef ref, Operator op) {
    ref.read(firestoreServiceProvider).updateOperator(op.id, {'isVerified': true, 'isActive': true});
  }

  void _deactivate(WidgetRef ref, Operator op) {
    ref.read(firestoreServiceProvider).updateOperator(op.id, {'isActive': false});
  }

  void _activate(WidgetRef ref, Operator op) {
    ref.read(firestoreServiceProvider).updateOperator(op.id, {'isActive': true});
  }

  void _reject(BuildContext context, WidgetRef ref, Operator op) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reject Operator?"),
        content: Text("Reject access for ${op.name}? They will need to re-register."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          FilledButton(
            onPressed: () {
              ref.read(firestoreServiceProvider).deleteOperator(op.id);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text("Reject"),
          ),
        ],
      ),
    );
  }
}
