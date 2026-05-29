import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

final _customFieldsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  final doc = await db.customFieldsSettings.get();
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
      'unit': '',
      'unitNumerator': '',
      'unitDenominator': '',
      'currency': 'INR',
      'decimalPlaces': 2,
    };

const _fieldTypes = ['Text', 'Number', 'Currency', 'Rate', 'Dropdown', 'Date', 'Boolean'];

const _weightUnits = ['kg', 'tonne', 'quintal', 'MT', 'lb', 'ton (US)'];
const _volumeUnits = ['litre', 'kL', 'gallon', 'm³'];
const _lengthUnits = ['m', 'km', 'ft', 'inch'];
const _areaUnits = ['m²', 'hectare', 'acre', 'sq ft'];
const _countUnits = ['pcs', 'bags', 'trips', 'loads', 'units'];
const _timeUnits = ['hr', 'min', 'day', 'month'];

const _allUnits = [..._weightUnits, ..._volumeUnits, ..._lengthUnits, ..._areaUnits, ..._countUnits, ..._timeUnits];

const _currencies = [
  ('INR', '₹'),
  ('USD', '\$'),
  ('EUR', '€'),
  ('GBP', '£'),
  ('AED', 'د.إ'),
  ('SAR', '﷼'),
  ('BDT', '৳'),
  ('NPR', 'रू'),
  ('LKR', 'Rs'),
];

String _currencyToDisplay(String code) {
  final match = _currencies.where((c) => c.$1 == code);
  if (match.isNotEmpty) return '${match.first.$1} (${match.first.$2})';
  return '${code} (${code})';
}

String _previewHint(Map<String, dynamic> field) {
  final type = field['type'] as String? ?? 'Text';
  switch (type) {
    case 'Number':
      return '0.00';
    case 'Currency':
      final cur = _currencies.firstWhere((c) => c.$1 == (field['currency'] ?? 'INR'), orElse: () => ('INR', '₹'));
      return '${cur.$2} 0.00';
    case 'Rate':
      final num = (field['unitNumerator'] as String?)?.isNotEmpty == true ? field['unitNumerator'] as String : 'INR (₹)';
      final den = (field['unitDenominator'] as String?)?.isNotEmpty == true ? field['unitDenominator'] as String : 'kg';
      final symbol = num.contains('(') ? num.split('(').last.replaceAll(')', '') : num;
      return '$symbol 0.00 / $den';
    case 'Date':
      return 'dd/mm/yyyy';
    case 'Boolean':
      return '';
    default:
      return 'Enter ${field['label'] ?? 'value'}';
  }
}

String _previewSuffix(Map<String, dynamic> field) {
  final type = field['type'] as String? ?? 'Text';
  if (type == 'Number') {
    final unit = field['unit'] as String? ?? '';
    return unit.isNotEmpty && unit != '(none)' ? unit : '';
  }
  if (type == 'Rate') {
    final den = (field['unitDenominator'] as String?)?.isNotEmpty == true ? field['unitDenominator'] as String : '';
    return den.isNotEmpty ? '/ $den' : '';
  }
  return '';
}

String _ratePreview(Map<String, dynamic> field) {
  final num = (field['unitNumerator'] as String?)?.isNotEmpty == true ? field['unitNumerator'] as String : 'INR (₹)';
  final den = (field['unitDenominator'] as String?)?.isNotEmpty == true ? field['unitDenominator'] as String : 'kg';
  final symbol = num.contains('(') ? num.split('(').last.replaceAll(')', '') : num;
  return 'Preview: $symbol 1,250.00 / $den  →  e.g. freight rate per $den';
}

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

  String? _headerMsg;
  bool _headerMsgIsError = false;

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

  void _showHeaderMsg(String msg, {bool isError = false}) {
    setState(() { _headerMsg = msg; _headerMsgIsError = isError; });
    Future.delayed(Duration(seconds: isError ? 5 : 3), () {
      if (mounted) setState(() => _headerMsg = null);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final db = ref.read(firestorePathsProvider);
      await db.customFieldsSettings.set({
        'fields': _fields,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      ref.invalidate(_customFieldsProvider);
      if (mounted) {
        setState(() => _dirty = false);
        _showHeaderMsg('Custom fields saved');
      }
    } catch (e) {
      if (mounted) _showHeaderMsg('Failed: $e', isError: true);
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => context.go('/settings'),
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                      style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs))),
                    ),
                    SizedBox(width: 12.rs),
                    Icon(Icons.text_fields_rounded, size: 20, color: scheme.primary),
                    SizedBox(width: 10.rs),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Custom Fields', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text('Additional fields on dockets', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                    const Spacer(),
                    if (_dirty) ...[
                      TextButton(onPressed: _resetDefaults, child: const Text('Cancel')),
                      SizedBox(width: 8.rs),
                    ],
                    FilledButton.icon(
                      onPressed: _dirty && !_saving ? _save : null,
                      icon: _saving
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded, size: 16),
                      label: Text(_saving ? 'Saving...' : 'Save'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
                      ),
                    ),
                  ],
                ),
                if (_headerMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _headerMsgIsError ? scheme.errorContainer.withValues(alpha: 0.6) : AppTheme.successColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8.rs),
                        border: Border.all(color: _headerMsgIsError ? scheme.error.withValues(alpha: 0.3) : AppTheme.successColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _headerMsgIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                            size: 15,
                            color: _headerMsgIsError ? scheme.error : AppTheme.successColor,
                          ),
                          SizedBox(width: 8.rs),
                          Expanded(child: Text(_headerMsg!, style: text.bodySmall?.copyWith(color: _headerMsgIsError ? scheme.error : AppTheme.successColor, fontWeight: FontWeight.w500))),
                        ],
                      ),
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
                      padding: EdgeInsets.all(28.rs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Info banner
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(14.rs),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10.rs),
                              border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline_rounded, size: 16, color: scheme.primary),
                                SizedBox(width: 10.rs),
                                Expanded(
                                  child: Text(
                                    'These fields will appear in the order configured below on the Transaction Entry screen. Ensure labels are concise for best UI display.',
                                    style: text.bodySmall?.copyWith(color: scheme.onSurface),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 24.rs),
                          Text('Field Configuration', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          SizedBox(height: 16.rs),
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
                    margin: EdgeInsets.all(28.rs),
                    padding: EdgeInsets.all(20.rs),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(14.rs),
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
                                borderRadius: BorderRadius.circular(4.rs),
                              ),
                              child: Text('LIVE PREVIEW', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer, letterSpacing: 0.5)),
                            ),
                          ],
                        ),
                        SizedBox(height: 16.rs),
                        Text('Transaction Entry', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                        SizedBox(height: 12.rs),
                        // Standard fields preview
                        _PreviewField(label: 'Vehicle Number', hint: 'MH-12-AB-1234', scheme: scheme, text: text),
                        SizedBox(height: 10.rs),
                        // Custom fields preview
                        ..._fields.where((f) => f['enabled'] == true && (f['label'] as String).isNotEmpty).map((f) {
                          final label = f['label'] as String;
                          final type = f['type'] as String;
                          final required = f['required'] == true;
                          final placeholder = (f['placeholder'] as String?)?.isNotEmpty == true ? f['placeholder'] as String : _previewHint(f);
                          final suffix = _previewSuffix(f);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _PreviewField(
                              label: '$label${required ? ' *' : ''}',
                              hint: placeholder,
                              suffix: suffix,
                              isDropdown: type == 'Dropdown',
                              isToggle: type == 'Boolean',
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
                                  borderRadius: BorderRadius.circular(6.rs),
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
                              borderRadius: BorderRadius.circular(8.rs),
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
  final String suffix;
  final bool isDropdown;
  final bool isToggle;
  final ColorScheme scheme;
  final TextTheme text;

  const _PreviewField({required this.label, required this.hint, this.suffix = '', this.isDropdown = false, this.isToggle = false, required this.scheme, required this.text});

  @override
  Widget build(BuildContext context) {
    if (isToggle) {
      return Row(
        children: [
          SizedBox(width: 28, height: 16, child: FittedBox(child: Switch(value: false, onChanged: null))),
          SizedBox(width: 6.rs),
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
        SizedBox(height: 3.rs),
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(5.rs),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(hint, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
              ),
              if (suffix.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3.rs),
                  ),
                  child: Text(suffix, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: scheme.primary)),
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
        borderRadius: BorderRadius.circular(12.rs),
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
                  SizedBox(width: 12.rs),
                  Text(
                    'Custom Field ${index + 1}',
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(width: 10.rs),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: enabled ? scheme.primaryContainer : scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(4.rs),
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
            Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
            Padding(
              padding: EdgeInsets.all(16.rs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Enable toggle
                  Row(
                    children: [
                      Text('Enable Field', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w500)),
                      SizedBox(width: 8.rs),
                      Switch(
                        value: enabled,
                        onChanged: (v) => _update('enabled', v),
                      ),
                    ],
                  ),
                  if (enabled) ...[
                    SizedBox(height: 16.rs),
                    Row(
                      children: [
                        Expanded(
                          child: _ConfigField(
                            label: 'Field Label',
                            value: field['label'] ?? '',
                            hint: 'e.g. Freight Rate',
                            onChanged: (v) => _update('label', v),
                          ),
                        ),
                        SizedBox(width: 14.rs),
                        Expanded(
                          child: _ConfigDropdown(
                            label: 'Field Type',
                            value: field['type'] ?? 'Text',
                            items: _fieldTypes,
                            onChanged: (v) => _update('type', v),
                          ),
                        ),
                      ],
                    ),

                    // ── Unit config for Number type ──
                    if (field['type'] == 'Number') ...[
                      SizedBox(height: 14.rs),
                      Row(
                        children: [
                          Expanded(
                            child: _ConfigDropdown(
                              label: 'Unit',
                              value: (field['unit'] as String?)?.isNotEmpty == true ? field['unit'] as String : '(none)',
                              items: ['(none)', ..._allUnits],
                              onChanged: (v) => _update('unit', v == '(none)' ? '' : v),
                            ),
                          ),
                          SizedBox(width: 14.rs),
                          SizedBox(
                            width: 100,
                            child: _ConfigField(
                              label: 'Decimals',
                              value: '${field['decimalPlaces'] ?? 2}',
                              hint: '2',
                              onChanged: (v) => _update('decimalPlaces', int.tryParse(v) ?? 2),
                            ),
                          ),
                        ],
                      ),
                    ],

                    // ── Currency config ──
                    if (field['type'] == 'Currency') ...[
                      SizedBox(height: 14.rs),
                      Row(
                        children: [
                          Expanded(
                            child: _ConfigDropdown(
                              label: 'Currency',
                              value: _currencyToDisplay(field['currency'] ?? 'INR'),
                              items: _currencies.map((c) => '${c.$1} (${c.$2})').toList(),
                              onChanged: (v) => _update('currency', v.split(' ').first),
                            ),
                          ),
                          SizedBox(width: 14.rs),
                          SizedBox(
                            width: 100,
                            child: _ConfigField(
                              label: 'Decimals',
                              value: '${field['decimalPlaces'] ?? 2}',
                              hint: '2',
                              onChanged: (v) => _update('decimalPlaces', int.tryParse(v) ?? 2),
                            ),
                          ),
                        ],
                      ),
                    ],

                    // ── Rate config (compound unit: currency / weight unit) ──
                    if (field['type'] == 'Rate') ...[
                      SizedBox(height: 14.rs),
                      Container(
                        padding: EdgeInsets.all(12.rs),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8.rs),
                          border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.functions_rounded, size: 14, color: scheme.primary),
                                SizedBox(width: 6.rs),
                                Text('Compound Unit', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary)),
                              ],
                            ),
                            SizedBox(height: 10.rs),
                            Row(
                              children: [
                                Expanded(
                                  child: _ConfigDropdown(
                                    label: 'Numerator (value)',
                                    value: (field['unitNumerator'] as String?)?.isNotEmpty == true ? field['unitNumerator'] : 'INR (₹)',
                                    items: _currencies.map((c) => '${c.$1} (${c.$2})').toList(),
                                    onChanged: (v) => _update('unitNumerator', v),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  child: Column(
                                    children: [
                                      SizedBox(height: 16.rs),
                                      Text('/', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w300, color: scheme.onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: _ConfigDropdown(
                                    label: 'Denominator (per)',
                                    value: (field['unitDenominator'] as String?)?.isNotEmpty == true ? field['unitDenominator'] : _weightUnits.first,
                                    items: _allUnits,
                                    onChanged: (v) => _update('unitDenominator', v),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8.rs),
                            Text(
                              _ratePreview(field),
                              style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 14.rs),
                      SizedBox(
                        width: 100,
                        child: _ConfigField(
                          label: 'Decimals',
                          value: '${field['decimalPlaces'] ?? 2}',
                          hint: '2',
                          onChanged: (v) => _update('decimalPlaces', int.tryParse(v) ?? 2),
                        ),
                      ),
                    ],

                    // ── Dropdown options ──
                    if (field['type'] == 'Dropdown') ...[
                      SizedBox(height: 14.rs),
                      _ConfigField(
                        label: 'Options (Comma separated)',
                        value: field['options'] ?? '',
                        hint: 'Internal, External, Contractor, Private',
                        onChanged: (v) => _update('options', v),
                      ),
                    ],

                    SizedBox(height: 14.rs),
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
                        SizedBox(width: 14.rs),
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
                    SizedBox(height: 16.rs),
                    Text('Validation', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(height: 8.rs),
                    Row(
                      children: [
                        Checkbox(
                          value: field['required'] == true,
                          onChanged: (v) => _update('required', v),
                        ),
                        Text('Required Field', style: text.bodySmall),
                        if (field['type'] == 'Text') ...[
                          SizedBox(width: 24.rs),
                          SizedBox(
                            width: 80,
                            child: _ConfigField(
                              label: 'Min Length',
                              value: '${field['minLength'] ?? 1}',
                              hint: '1',
                              onChanged: (v) => _update('minLength', int.tryParse(v) ?? 1),
                            ),
                          ),
                          SizedBox(width: 14.rs),
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
                      ],
                    ),
                    SizedBox(height: 16.rs),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => onChanged(_defaultField()),
                        icon: Icon(Icons.restart_alt_rounded, size: 14, color: scheme.error),
                        label: Text('Reset Field', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.error)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.rs)),
                        ),
                      ),
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
        SizedBox(height: 5.rs),
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
    final safeValue = items.contains(value) ? value : items.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: 5.rs),
        DropdownButtonFormField<String>(
          key: ValueKey('$label:$safeValue'),
          initialValue: safeValue,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: text.bodySmall))).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.rs), borderSide: BorderSide(color: scheme.outlineVariant)),
          ),
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
