import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';

final _customFieldsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final db = ref.watch(firestoreProvider);
  final doc = await db.collection('settings').doc('customFields').get();
  if (!doc.exists) return List.generate(3, (_) => _defaultField());
  final fields = doc.data()?['fields'] as List<dynamic>?;
  if (fields == null || fields.isEmpty) return List.generate(3, (_) => _defaultField());
  return fields.map((f) => Map<String, dynamic>.from(f as Map)).toList();
});

Map<String, dynamic> _defaultField() => {
      'enabled': false,
      'label': '',
      'type': 'Text',
      'options': '',
      'defaultValue': '',
      'placeholder': '',
      'required': false,
      'minLength': 1,
      'maxLength': 50,
    };

class CustomFieldsScreen extends ConsumerStatefulWidget {
  const CustomFieldsScreen({super.key});

  @override
  ConsumerState<CustomFieldsScreen> createState() => _CustomFieldsScreenState();
}

class _CustomFieldsScreenState extends ConsumerState<CustomFieldsScreen> {
  List<Map<String, dynamic>> _fields = [];
  bool _loaded = false;
  bool _saving = false;
  bool _dirty = false;
  int _expandedIndex = 0;

  void _loadData(List<Map<String, dynamic>> data) {
    if (_loaded) return;
    _loaded = true;
    _fields = data.map((f) => Map<String, dynamic>.from(f)).toList();
    while (_fields.length < 3) {
      _fields.add(_defaultField());
    }
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final db = ref.read(firestoreProvider);
      await db.collection('settings').doc('customFields').set({
        'fields': _fields,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      ref.invalidate(_customFieldsProvider);
      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Custom fields saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetDefaults() {
    setState(() {
      _fields = List.generate(3, (_) => _defaultField());
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fieldsAsync = ref.watch(_customFieldsProvider);

    fieldsAsync.whenData(_loadData);

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
                IconButton(
                  onPressed: () => context.go('/settings'),
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                ),
                const SizedBox(width: 12),
                Icon(Icons.text_fields_rounded, size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Custom Fields', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Additional fields on dockets', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
                const Spacer(),
                if (_dirty) ...[
                  TextButton(onPressed: _resetDefaults, child: const Text('Reset Defaults')),
                  const SizedBox(width: 8),
                ],
                FilledButton.icon(
                  onPressed: _dirty && !_saving ? _save : null,
                  icon: _saving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded, size: 16),
                  label: Text(_saving ? 'Saving...' : 'Save'),
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
            child: fieldsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Field configuration
                  Expanded(
                    flex: 3,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Info banner
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline_rounded, size: 16, color: scheme.primary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'These fields will appear in the order configured below on the Transaction Entry screen. Ensure labels are concise for best UI display.',
                                    style: text.bodySmall?.copyWith(color: scheme.onSurface),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text('Field Configuration', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 16),
                          ...List.generate(3, (i) => _FieldConfig(
                                index: i,
                                field: _fields[i],
                                expanded: _expandedIndex == i,
                                onToggleExpand: () => setState(() => _expandedIndex = _expandedIndex == i ? -1 : i),
                                onChanged: (updated) {
                                  setState(() => _fields[i] = updated);
                                  _markDirty();
                                },
                              )),
                        ],
                      ),
                    ),
                  ),

                  // Live preview
                  Container(
                    width: 280,
                    margin: const EdgeInsets.all(28),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('LIVE PREVIEW', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer, letterSpacing: 0.5)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text('Transaction Entry', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        // Standard fields preview
                        _PreviewField(label: 'Vehicle Number', hint: 'MH-12-AB-1234', scheme: scheme, text: text),
                        const SizedBox(height: 10),
                        // Custom fields preview
                        ..._fields.where((f) => f['enabled'] == true && (f['label'] as String).isNotEmpty).map((f) {
                          final label = f['label'] as String;
                          final type = f['type'] as String;
                          final required = f['required'] == true;
                          final placeholder = (f['placeholder'] as String?)?.isNotEmpty == true ? f['placeholder'] as String : 'Enter $label';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _PreviewField(
                              label: '$label${required ? ' *' : ''}',
                              hint: placeholder,
                              isDropdown: type == 'Dropdown',
                              scheme: scheme,
                              text: text,
                            ),
                          );
                        }),
                        // Disabled fields shown muted
                        ..._fields.where((f) => f['enabled'] != true).map((_) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Container(
                                height: 36,
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHigh.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Center(
                                  child: Icon(Icons.block_rounded, size: 14, color: scheme.outlineVariant),
                                ),
                              ),
                            )),
                        const Spacer(),
                        SizedBox(
                          width: double.infinity,
                          child: Container(
                            height: 36,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text('Complete Transaction', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onPrimary)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewField extends StatelessWidget {
  final String label;
  final String hint;
  final bool isDropdown;
  final ColorScheme scheme;
  final TextTheme text;

  const _PreviewField({required this.label, required this.hint, this.isDropdown = false, required this.scheme, required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 3),
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(hint, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
              ),
              if (isDropdown) Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ],
    );
  }
}

class _FieldConfig extends StatelessWidget {
  final int index;
  final Map<String, dynamic> field;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const _FieldConfig({
    required this.index,
    required this.field,
    required this.expanded,
    required this.onToggleExpand,
    required this.onChanged,
  });

  void _update(String key, dynamic value) {
    final updated = Map<String, dynamic>.from(field);
    updated[key] = value;
    onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final enabled = field['enabled'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: expanded ? scheme.primary.withValues(alpha: 0.3) : scheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: onToggleExpand,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text('${index + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.primary)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Custom Field ${index + 1}',
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: enabled ? scheme.primaryContainer : scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      enabled ? 'ACTIVE' : 'DISABLED',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: enabled ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          if (expanded) ...[
            Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.2)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Enable toggle
                  Row(
                    children: [
                      Text('Enable Field', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(width: 8),
                      Switch(
                        value: enabled,
                        onChanged: (v) => _update('enabled', v),
                      ),
                    ],
                  ),
                  if (enabled) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _ConfigField(
                            label: 'Field Label',
                            value: field['label'] ?? '',
                            hint: 'e.g. Vehicle Source',
                            onChanged: (v) => _update('label', v),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _ConfigDropdown(
                            label: 'Field Type',
                            value: field['type'] ?? 'Text',
                            items: const ['Text', 'Dropdown', 'Number'],
                            onChanged: (v) => _update('type', v),
                          ),
                        ),
                      ],
                    ),
                    if (field['type'] == 'Dropdown') ...[
                      const SizedBox(height: 14),
                      _ConfigField(
                        label: 'Options (Comma separated)',
                        value: field['options'] ?? '',
                        hint: 'Internal, External, Contractor, Private',
                        onChanged: (v) => _update('options', v),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _ConfigField(
                            label: 'Default Value',
                            value: field['defaultValue'] ?? '',
                            hint: 'Optional default',
                            onChanged: (v) => _update('defaultValue', v),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _ConfigField(
                            label: 'Placeholder Text',
                            value: field['placeholder'] ?? '',
                            hint: 'Shown when empty',
                            onChanged: (v) => _update('placeholder', v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Validation', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: field['required'] == true,
                          onChanged: (v) => _update('required', v),
                        ),
                        Text('Required Field', style: text.bodySmall),
                        const SizedBox(width: 24),
                        SizedBox(
                          width: 80,
                          child: _ConfigField(
                            label: 'Min Length',
                            value: '${field['minLength'] ?? 1}',
                            hint: '1',
                            onChanged: (v) => _update('minLength', int.tryParse(v) ?? 1),
                          ),
                        ),
                        const SizedBox(width: 14),
                        SizedBox(
                          width: 80,
                          child: _ConfigField(
                            label: 'Max Length',
                            value: '${field['maxLength'] ?? 50}',
                            hint: '50',
                            onChanged: (v) => _update('maxLength', int.tryParse(v) ?? 50),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConfigField extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final ValueChanged<String> onChanged;

  const _ConfigField({required this.label, required this.value, required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        TextFormField(
          initialValue: value,
          style: text.bodySmall,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
        ),
      ],
    );
  }
}

class _ConfigDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  const _ConfigDropdown({required this.label, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          initialValue: value,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: text.bodySmall))).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: scheme.outlineVariant)),
          ),
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
