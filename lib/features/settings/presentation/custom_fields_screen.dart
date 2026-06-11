import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/app_loading.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:weighbridgemanagement/shared/providers/settings_scope_provider.dart';
import 'package:weighbridgemanagement/shared/widgets/settings_scope_selector.dart';
import 'package:weighbridgemanagement/shared/widgets/scope_change_dialog.dart';
import 'package:weighbridgemanagement/shared/widgets/weighbridge_context_bar.dart';

const _cfScopeArg = (feature: 'customFields', fallback: CollectionScope.company);

final _customFieldsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  if (!db.isConfigured) return List.generate(3, (_) => _defaultField());
  final scope = await ref.watch(settingsScopeProvider(_cfScopeArg).future);
  final doc = await scopedSettingDoc(db, 'customFields', scope).get();
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
  return '$code ($code)';
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
  Timer? _saveDebounce;
  int _expandedIndex = 0;

  String? _headerMsg;
  bool _headerMsgIsError = false;

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  void _loadData(List<Map<String, dynamic>> data) {
    if (_loaded) return;
    _loaded = true;
    _fields = data.map((f) => Map<String, dynamic>.from(f)).toList();
    while (_fields.length < 3) {
      _fields.add(_defaultField());
    }
  }

  void _markDirty() {
    // Auto-save shortly after the last edit (no Save button).
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _save();
    });
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
      final scope = ref.read(settingsScopeProvider(_cfScopeArg)).valueOrNull ?? CollectionScope.company;
      await scopedSettingDoc(db, 'customFields', scope).set({
        'fields': _fields,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      ref.invalidate(_customFieldsProvider);
      if (mounted) _showHeaderMsg('Saved');
    } catch (e) {
      if (mounted) _showHeaderMsg('Failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Scope change applies right away after confirmation (like Materials),
  /// copying the current fields up/down to the new scope.
  Future<void> _changeScope(CollectionScope to) async {
    final saved = ref.read(settingsScopeProvider(_cfScopeArg)).valueOrNull ?? CollectionScope.company;
    if (saved == to) return;
    final ok = await showScopeChangeDialog(context, ref, from: saved, to: to, noun: 'fields', saveGated: false);
    if (!ok) return;
    final db = ref.read(firestorePathsProvider);
    try {
      final src = await scopedSettingDoc(db, 'customFields', saved).get();
      if (src.exists && src.data() != null) {
        await scopedSettingDoc(db, 'customFields', to).set(src.data()!, SetOptions(merge: true));
      }
      await db.companySetting('settingsScope').set({'customFields': to.name}, SetOptions(merge: true));
      ref.invalidate(_customFieldsProvider);
      ref.invalidate(settingsScopeProvider(_cfScopeArg));
      if (mounted) setState(() => _loaded = false);
      _showHeaderMsg('Custom fields now apply to ${to.label}');
    } catch (e) {
      if (mounted) _showHeaderMsg('Failed to change scope: $e', isError: true);
    }
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
            margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: AppRadius.card,
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
              boxShadow: AppElevation.card(scheme.shadow),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => context.go('/settings'),
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                      style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
                    ),
                    SizedBox(width: AppSpacing.md),
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
                    if (_saving)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: AppSpacing.sm),
                          Text('Saving…', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_done_rounded, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                          SizedBox(width: 6.rs),
                          Text('Saved automatically', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
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
                        borderRadius: AppRadius.button,
                        border: Border.all(color: _headerMsgIsError ? scheme.error.withValues(alpha: 0.3) : AppTheme.successColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _headerMsgIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                            size: 15,
                            color: _headerMsgIsError ? scheme.error : AppTheme.successColor,
                          ),
                          SizedBox(width: AppSpacing.sm),
                          Expanded(child: Text(_headerMsg!, style: text.bodySmall?.copyWith(color: _headerMsgIsError ? scheme.error : AppTheme.successColor, fontWeight: FontWeight.w500))),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          WeighbridgeContextBar(
            label: 'Custom fields for',
            onSwitched: () {
              setState(() => _loaded = false);
              ref.invalidate(_customFieldsProvider);
            },
            trailing: SettingsScopeSelector(
              scope: ref.watch(settingsScopeProvider(_cfScopeArg)).valueOrNull ?? CollectionScope.company,
              onChanged: (to) => _changeScope(to),
            ),
          ),

          // Content
          Expanded(
            child: fieldsAsync.when(
              loading: () => const AppLoading(),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) => SingleChildScrollView(
                      padding: AppSpacing.pagePadding,
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
                          SizedBox(height: AppSpacing.xl),
                          Text('Field Configuration', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          SizedBox(height: AppSpacing.lg),
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
          ),
        ],
      ),
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
        borderRadius: AppRadius.card,
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
                  SizedBox(width: AppSpacing.md),
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
              padding: AppSpacing.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Enable toggle
                  Row(
                    children: [
                      Text('Enable Field', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w500)),
                      SizedBox(width: AppSpacing.sm),
                      Switch(
                        value: enabled,
                        onChanged: (v) => _update('enabled', v),
                      ),
                    ],
                  ),
                  if (enabled) ...[
                    SizedBox(height: AppSpacing.lg),
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
                          borderRadius: AppRadius.button,
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
                                      SizedBox(height: AppSpacing.lg),
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
                            SizedBox(height: AppSpacing.sm),
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
                    SizedBox(height: AppSpacing.lg),
                    Text('Validation', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Checkbox(
                          value: field['required'] == true,
                          onChanged: (v) => _update('required', v),
                        ),
                        Text('Required Field', style: text.bodySmall),
                        if (field['type'] == 'Text') ...[
                          SizedBox(width: AppSpacing.xl),
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
                    SizedBox(height: AppSpacing.lg),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => onChanged(_defaultField()),
                        icon: Icon(Icons.restart_alt_rounded, size: 14, color: scheme.error),
                        label: Text('Reset Field', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.error)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: AppRadius.chip),
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
            border: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: scheme.outlineVariant)),
          ),
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
