import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import 'package:weighbridgemanagement/shared/providers/general_settings_provider.dart';

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

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
            ),
            child: Row(
              children: [
                Icon(Icons.people_rounded, size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                Text('Operators', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _showAddOperatorDialog(context, ref),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add Operator'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: operatorsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (operators) {
                final pending = operators.where((o) => o['isVerified'] == false).toList();
                final verified = operators.where((o) => o['isVerified'] == true).toList();

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (pending.isNotEmpty) ...[
                        _buildPendingSection(context, ref, pending, scheme, text),
                        const SizedBox(height: 28),
                      ],
                      _buildOperatorsTable(context, ref, verified, scheme, text),
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

  Widget _buildPendingSection(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, dynamic>> pending,
    ColorScheme scheme,
    TextTheme text,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.pending_actions_rounded, size: 16, color: Colors.amber),
              ),
              const SizedBox(width: 12),
              Text('Pending Approval', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${pending.length}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...pending.map((op) => _PendingCard(operator: op, ref: ref, scheme: scheme, text: text)),
        ],
      ),
    );
  }

  Widget _buildOperatorsTable(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, dynamic>> operators,
    ColorScheme scheme,
    TextTheme text,
  ) {
    if (operators.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(60),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        ),
        child: Center(
          child: Text('No operators yet.', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DataTable(
          columnSpacing: 24,
          horizontalMargin: 20,
          headingRowColor: WidgetStateProperty.all(scheme.surfaceContainerLow),
          columns: const [
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Shift')),
            DataColumn(label: Text('ID Status')),
            DataColumn(label: Text('Last Active')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Actions')),
          ],
          rows: operators.map((op) {
            final isActive = op['isActive'] == true;
            final idStatus = op['idStatus'] as String? ?? 'not_submitted';

            return DataRow(cells: [
              // Name + email
              DataCell(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(op['name'] ?? '--', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      op['email'] ?? '--',
                      style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),

              // Shift
              DataCell(Text(
                _formatShift(op),
                style: text.bodySmall,
              )),

              // ID Status
              DataCell(_buildIdStatusChip(idStatus, scheme)),

              // Last Active
              DataCell(Text(
                _formatTimestamp(op['lastLoginAt'], ref.read(timeFormatProvider)),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              )),

              // Status
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

              // Actions
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Edit',
                    onPressed: () => _showEditOperatorDialog(context, ref, op),
                  ),
                  IconButton(
                    icon: Icon(
                      isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                      size: 18,
                      color: isActive ? scheme.error : scheme.primary,
                    ),
                    tooltip: isActive ? 'Deactivate' : 'Activate',
                    onPressed: () {
                      ref.read(firestoreProvider).collection('operators').doc(op['id']).update({'isActive': !isActive});
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, size: 18, color: scheme.error),
                    tooltip: 'Delete',
                    onPressed: () => _confirmDelete(context, ref, op),
                  ),
                ],
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildIdStatusChip(String status, ColorScheme scheme) {
    Color bgColor;
    Color fgColor;
    String label;

    switch (status) {
      case 'verified':
        bgColor = Colors.green.withValues(alpha: 0.12);
        fgColor = Colors.green;
        label = 'Verified';
        break;
      case 'pending':
        bgColor = Colors.amber.withValues(alpha: 0.12);
        fgColor = Colors.amber.shade800;
        label = 'Pending';
        break;
      case 'rejected':
        bgColor = scheme.errorContainer;
        fgColor = scheme.onErrorContainer;
        label = 'Rejected';
        break;
      default:
        bgColor = scheme.surfaceContainerHigh;
        fgColor = scheme.onSurfaceVariant;
        label = 'Not Submitted';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fgColor),
      ),
    );
  }

  String _formatShift(Map<String, dynamic> op) {
    final restricted = op['shiftRestricted'] == true;
    if (!restricted) return 'No restriction';

    final start = op['shiftStart'] as String? ?? '';
    final end = op['shiftEnd'] as String? ?? '';
    final days = (op['shiftDays'] as List<dynamic>?)?.cast<String>() ?? [];

    if (start.isEmpty && end.isEmpty) return 'No restriction';

    String dayRange = '';
    if (days.isNotEmpty) {
      if (days.length == 7) {
        dayRange = 'All days';
      } else {
        dayRange = '(${days.first}-${days.last})';
      }
    }

    return '$start–$end $dayRange'.trim();
  }

  String _formatTimestamp(dynamic timestamp, String timeFormat) {
    if (timestamp == null) return 'Never';
    if (timestamp is Timestamp) {
      return formatTimestamp(timestamp, timeFormat);
    }
    return 'Never';
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Map<String, dynamic> op) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Operator'),
        content: Text('Are you sure you want to delete "${op['name']}"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              ref.read(firestoreProvider).collection('operators').doc(op['id']).delete();
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddOperatorDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => _AddOperatorDialog(ref: ref),
    );
  }

  void _showEditOperatorDialog(BuildContext context, WidgetRef ref, Map<String, dynamic> op) {
    showDialog(
      context: context,
      builder: (ctx) => _EditOperatorDialog(ref: ref, operator: op),
    );
  }
}

// ─── Pending Card ─────────────────────────────────────────────────────────────

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
        color: scheme.surfaceContainerLow,
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

// ─── Add Operator Dialog ──────────────────────────────────────────────────────

class _AddOperatorDialog extends StatefulWidget {
  final WidgetRef ref;

  const _AddOperatorDialog({required this.ref});

  @override
  State<_AddOperatorDialog> createState() => _AddOperatorDialogState();
}

class _AddOperatorDialogState extends State<_AddOperatorDialog> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final db = widget.ref.read(firestoreProvider);
      await db.collection('operators').add({
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim().toLowerCase(),
        'isVerified': true,
        'isActive': true,
        'mustChangePassword': true,
        'createdAt': FieldValue.serverTimestamp(),
        'role': 'operator',
        'idStatus': 'not_submitted',
        'shiftRestricted': false,
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add operator: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 440,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_add_rounded, size: 20, color: scheme.primary),
                    const SizedBox(width: 10),
                    Text('Add Operator', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Name', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameCtrl,
                  style: text.bodySmall,
                  decoration: const InputDecoration(
                    hintText: 'Enter full name',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 16),
                Text('Email', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _emailCtrl,
                  style: text.bodySmall,
                  decoration: const InputDecoration(
                    hintText: 'Enter email address',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email is required';
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Add Operator'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Edit Operator Dialog ─────────────────────────────────────────────────────

class _EditOperatorDialog extends StatefulWidget {
  final WidgetRef ref;
  final Map<String, dynamic> operator;

  const _EditOperatorDialog({required this.ref, required this.operator});

  @override
  State<_EditOperatorDialog> createState() => _EditOperatorDialogState();
}

class _EditOperatorDialogState extends State<_EditOperatorDialog> {
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _idDocNumberCtrl;

  late bool _shiftRestricted;
  late TimeOfDay _shiftStart;
  late TimeOfDay _shiftEnd;
  late List<String> _shiftDays;

  late String _idStatus;
  late String _idDocumentType;

  late bool _mustChangePassword;

  bool _saving = false;

  static const _allDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _documentTypes = ['Aadhaar', 'PAN', 'Driving License', 'Voter ID'];

  @override
  void initState() {
    super.initState();
    final op = widget.operator;

    _phoneCtrl = TextEditingController(text: op['phone'] as String? ?? '');
    _idDocNumberCtrl = TextEditingController(text: op['idDocumentNumber'] as String? ?? '');

    _shiftRestricted = op['shiftRestricted'] == true;
    _shiftStart = _parseTime(op['shiftStart'] as String?) ?? const TimeOfDay(hour: 6, minute: 0);
    _shiftEnd = _parseTime(op['shiftEnd'] as String?) ?? const TimeOfDay(hour: 14, minute: 0);
    _shiftDays = (op['shiftDays'] as List<dynamic>?)?.cast<String>() ?? List.from(_allDays.sublist(0, 5));

    _idStatus = op['idStatus'] as String? ?? 'not_submitted';
    _idDocumentType = op['idDocumentType'] as String? ?? 'Aadhaar';
    if (!_documentTypes.contains(_idDocumentType)) {
      _idDocumentType = 'Aadhaar';
    }

    _mustChangePassword = op['mustChangePassword'] == true;
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _idDocNumberCtrl.dispose();
    super.dispose();
  }

  TimeOfDay? _parseTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return null;
    final parts = timeStr.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _formatTimeOfDay(TimeOfDay t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  String _formatTimestamp(dynamic timestamp, String timeFormat) {
    if (timestamp == null) return 'Never';
    if (timestamp is Timestamp) {
      return formatTimestamp(timestamp, timeFormat);
    }
    return 'Never';
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart ? _shiftStart : _shiftEnd;
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        if (isStart) {
          _shiftStart = picked;
        } else {
          _shiftEnd = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    try {
      final db = widget.ref.read(firestoreProvider);
      final updateData = <String, dynamic>{
        'phone': _phoneCtrl.text.trim(),
        'shiftRestricted': _shiftRestricted,
        'mustChangePassword': _mustChangePassword,
        'idDocumentType': _idDocumentType,
        'idDocumentNumber': _idDocNumberCtrl.text.trim(),
        'idStatus': _idStatus,
      };

      if (_shiftRestricted) {
        updateData['shiftStart'] = _formatTimeOfDay(_shiftStart);
        updateData['shiftEnd'] = _formatTimeOfDay(_shiftEnd);
        updateData['shiftDays'] = _shiftDays;
      }

      await db.collection('operators').doc(widget.operator['id']).update(updateData);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _verifyId() async {
    final adminEmail = FirebaseAuth.instance.currentUser?.email ?? 'admin';
    final db = widget.ref.read(firestoreProvider);
    await db.collection('operators').doc(widget.operator['id']).update({
      'idStatus': 'verified',
      'idVerifiedAt': FieldValue.serverTimestamp(),
      'idVerifiedBy': adminEmail,
    });
    setState(() => _idStatus = 'verified');
  }

  Future<void> _rejectId() async {
    final db = widget.ref.read(firestoreProvider);
    await db.collection('operators').doc(widget.operator['id']).update({
      'idStatus': 'rejected',
    });
    setState(() => _idStatus = 'rejected');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final op = widget.operator;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Dialog header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.edit_rounded, size: 20, color: scheme.primary),
                  const SizedBox(width: 10),
                  Text('Edit Operator', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
            const Divider(),

            // Scrollable content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Basic Info
                    _sectionHeader('Basic Info', Icons.person_rounded, scheme, text),
                    const SizedBox(height: 12),
                    _readOnlyField('Name', op['name'] ?? '--', text, scheme),
                    const SizedBox(height: 12),
                    _readOnlyField('Email', op['email'] ?? '--', text, scheme),
                    const SizedBox(height: 12),
                    Text('Phone', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _phoneCtrl,
                      style: text.bodySmall,
                      decoration: const InputDecoration(
                        hintText: 'Enter phone number',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Shift Schedule
                    _sectionHeader('Shift Schedule', Icons.schedule_rounded, scheme, text),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text('No restriction', style: text.bodySmall),
                        const SizedBox(width: 8),
                        Switch(
                          value: !_shiftRestricted,
                          onChanged: (v) => setState(() => _shiftRestricted = !v),
                        ),
                      ],
                    ),
                    if (_shiftRestricted) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _timePickerTile('Start', _shiftStart, () => _pickTime(isStart: true), scheme, text),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _timePickerTile('End', _shiftEnd, () => _pickTime(isStart: false), scheme, text),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _allDays.map((day) {
                          final selected = _shiftDays.contains(day);
                          return FilterChip(
                            label: Text(day),
                            selected: selected,
                            onSelected: (v) {
                              setState(() {
                                if (v) {
                                  _shiftDays.add(day);
                                } else {
                                  _shiftDays.remove(day);
                                }
                              });
                            },
                            labelStyle: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            visualDensity: VisualDensity.compact,
                          );
                        }).toList(),
                      ),
                    ],

                    const SizedBox(height: 28),

                    // ID Verification (KYC)
                    _sectionHeader('ID Verification (KYC)', Icons.verified_user_rounded, scheme, text),
                    const SizedBox(height: 12),
                    Text('Document Type', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _idDocumentType,
                      items: _documentTypes
                          .map((e) => DropdownMenuItem(value: e, child: Text(e, style: text.bodySmall)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _idDocumentType = v);
                      },
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: scheme.outlineVariant),
                        ),
                      ),
                      style: text.bodySmall,
                      icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Text('Document Number', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _idDocNumberCtrl,
                      style: text.bodySmall,
                      decoration: const InputDecoration(
                        hintText: 'Enter document number',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text('Status: ', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                        _buildKycStatusChip(_idStatus, scheme),
                        if (_idStatus == 'verified' && op['idVerifiedAt'] != null) ...[
                          const SizedBox(width: 12),
                          Text(
                            'Verified on ${_formatTimestamp(op['idVerifiedAt'], widget.ref.read(timeFormatProvider))}',
                            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                    if (_idStatus == 'pending') ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton.tonal(
                            onPressed: _verifyId,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green.withValues(alpha: 0.12),
                              foregroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            ),
                            child: const Text('Verify'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _rejectId,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: scheme.error,
                              side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            ),
                            child: const Text('Reject'),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 28),

                    // Password & Security
                    _sectionHeader('Password & Security', Icons.lock_rounded, scheme, text),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text('Force password change on next login', style: text.bodySmall),
                        ),
                        Switch(
                          value: _mustChangePassword,
                          onChanged: (v) => setState(() => _mustChangePassword = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _infoRow('Password last changed', _formatTimestamp(op['passwordLastChanged'], widget.ref.read(timeFormatProvider)), text, scheme),
                    const SizedBox(height: 4),
                    _infoRow(
                      'First login completed',
                      (op['loginCount'] != null && (op['loginCount'] as int) > 0) ? 'Yes' : 'No',
                      text,
                      scheme,
                    ),

                    const SizedBox(height: 28),

                    // Activity
                    _sectionHeader('Activity', Icons.insights_rounded, scheme, text),
                    const SizedBox(height: 12),
                    _infoRow('Last login', _formatTimestamp(op['lastLoginAt'], widget.ref.read(timeFormatProvider)), text, scheme),
                    const SizedBox(height: 4),
                    _infoRow('Total logins', '${op['loginCount'] ?? 0}', text, scheme),

                    const SizedBox(height: 28),

                    // Face Enrollment
                    _sectionHeader('Face Enrollment', Icons.face_rounded, scheme, text),
                    const SizedBox(height: 12),
                    _FaceEnrollmentWidget(
                      ref: widget.ref,
                      operatorId: widget.operator['id'] as String,
                      existingFacePhoto: widget.operator['facePhoto'] as String?,
                    ),
                  ],
                ),
              ),
            ),

            // Save button
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save Changes'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, ColorScheme scheme, TextTheme text) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _readOnlyField(String label, String value, TextTheme text, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Text(value, style: text.bodySmall),
        ),
      ],
    );
  }

  Widget _timePickerTile(String label, TimeOfDay time, VoidCallback onTap, ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                Expanded(child: Text(_formatTimeOfDay(time), style: text.bodySmall)),
                Icon(Icons.access_time_rounded, size: 16, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKycStatusChip(String status, ColorScheme scheme) {
    Color bgColor;
    Color fgColor;
    String label;

    switch (status) {
      case 'verified':
        bgColor = Colors.green.withValues(alpha: 0.12);
        fgColor = Colors.green;
        label = 'Verified';
        break;
      case 'pending':
        bgColor = Colors.amber.withValues(alpha: 0.12);
        fgColor = Colors.amber.shade800;
        label = 'Pending Review';
        break;
      case 'rejected':
        bgColor = scheme.errorContainer;
        fgColor = scheme.onErrorContainer;
        label = 'Rejected';
        break;
      default:
        bgColor = scheme.surfaceContainerHigh;
        fgColor = scheme.onSurfaceVariant;
        label = 'Not Submitted';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fgColor),
      ),
    );
  }

  Widget _infoRow(String label, String value, TextTheme text, ColorScheme scheme) {
    return Row(
      children: [
        Text('$label: ', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        Text(value, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ─── Face Enrollment Widget ─────────────────────────────────────────────────

class _FaceEnrollmentWidget extends StatefulWidget {
  final WidgetRef ref;
  final String operatorId;
  final String? existingFacePhoto;

  const _FaceEnrollmentWidget({
    required this.ref,
    required this.operatorId,
    this.existingFacePhoto,
  });

  @override
  State<_FaceEnrollmentWidget> createState() => _FaceEnrollmentWidgetState();
}

class _FaceEnrollmentWidgetState extends State<_FaceEnrollmentWidget> {
  Uint8List? _capturedFrame;
  bool _capturing = false;
  bool _enrolled = false;
  String? _error;

  String get _frameCachePath {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    final dir = Directory('$home/.weighbridge/frames');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  @override
  void initState() {
    super.initState();
    _enrolled = widget.existingFacePhoto != null && widget.existingFacePhoto!.isNotEmpty;
  }

  Future<void> _capturePhoto() async {
    setState(() { _capturing = true; _error = null; });

    final framePath = '$_frameCachePath/enroll_${widget.operatorId}.jpg';

    try {
      // Determine camera index from settings
      int deviceIndex = 0;
      try {
        final db = widget.ref.read(firestoreProvider);
        final camDoc = await db.collection('settings').doc('camerasAi').get();
        if (camDoc.exists) {
          final cameras = camDoc.data()?['cameras'] as Map<String, dynamic>?;
          final operatorCam = cameras?['operator'] as Map<String, dynamic>?;
          if (operatorCam != null && operatorCam['enabled'] == true) {
            final source = operatorCam['source'] as String? ?? 'Built-in';
            final deviceName = source == 'USB'
                ? operatorCam['usbDevice'] as String? ?? ''
                : operatorCam['builtInDevice'] as String? ?? '';
            if (deviceName.isNotEmpty) {
              final result = await Process.run('system_profiler', ['SPCameraDataType', '-json']);
              if (result.exitCode == 0) {
                final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
                final cams = data['SPCameraDataType'] as List<dynamic>? ?? [];
                final names = cams.map((c) => (c as Map<String, dynamic>)['_name'] as String? ?? '').toList();
                final idx = names.indexOf(deviceName);
                if (idx >= 0) deviceIndex = idx;
              }
            }
          }
        }
      } catch (_) {}

      final result = await Process.run('ffmpeg', [
        '-y',
        '-f', 'avfoundation',
        '-framerate', '30',
        '-i', '$deviceIndex:none',
        '-frames:v', '1',
        '-update', '1',
        '-q:v', '2',
        framePath,
      ], stdoutEncoding: utf8, stderrEncoding: utf8);

      if (!mounted) return;

      final file = File(framePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          setState(() => _capturedFrame = bytes);
        } else {
          setState(() => _error = 'Empty frame captured');
        }
      } else {
        final err = (result.stderr as String).toLowerCase();
        if (err.contains('permission') || err.contains('denied')) {
          setState(() => _error = 'Camera permission denied');
        } else {
          setState(() => _error = 'Capture failed. Is ffmpeg installed?');
        }
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'ffmpeg not found. Install via: brew install ffmpeg');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _enrollFace() async {
    if (_capturedFrame == null) return;
    setState(() => _capturing = true);

    try {
      // Save photo locally and store path in Firestore
      final photoPath = '$_frameCachePath/face_${widget.operatorId}.jpg';
      await File(photoPath).writeAsBytes(_capturedFrame!);

      final db = widget.ref.read(firestoreProvider);
      await db.collection('operators').doc(widget.operatorId).update({
        'facePhoto': photoPath,
        'faceEnrolledAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() { _enrolled = true; _error = null; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Face enrolled successfully'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to save: $e');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _removeFace() async {
    setState(() => _capturing = true);
    try {
      final db = widget.ref.read(firestoreProvider);
      await db.collection('operators').doc(widget.operatorId).update({
        'facePhoto': FieldValue.delete(),
        'faceEnrolledAt': FieldValue.delete(),
      });

      // Delete local file
      final photoPath = '$_frameCachePath/face_${widget.operatorId}.jpg';
      final file = File(photoPath);
      if (await file.exists()) await file.delete();

      if (mounted) {
        setState(() { _enrolled = false; _capturedFrame = null; });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to remove: $e');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_enrolled && _capturedFrame == null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Face enrolled', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.primary)),
                const Spacer(),
                TextButton(
                  onPressed: _capturing ? null : _removeFace,
                  child: Text('Remove', style: TextStyle(fontSize: 11, color: scheme.error)),
                ),
              ],
            ),
          ),

        if (_capturedFrame != null)
          Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  _capturedFrame!,
                  width: double.infinity,
                  height: 160,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _capturing ? null : _capturePhoto,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Retake'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _capturing ? null : _enrollFace,
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('Enroll'),
                    ),
                  ),
                ],
              ),
            ],
          ),

        if (_capturedFrame == null && !_enrolled)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Capture a face photo for quick switch via face scan.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _capturing ? null : _capturePhoto,
                  icon: _capturing
                      ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary))
                      : const Icon(Icons.camera_alt_rounded, size: 16),
                  label: Text(_capturing ? 'Capturing...' : 'Capture Face Photo'),
                ),
              ),
            ],
          ),

        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: text.labelSmall?.copyWith(color: scheme.error)),
        ],
      ],
    );
  }
}
