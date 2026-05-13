import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';

// ─── Provider ────────────────────────────────────────────────────────────────

final _generalSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestoreProvider);
  final doc = await db.collection('settings').doc('general').get();
  return doc.exists ? doc.data()! : {};
});

// ─── Screen ──────────────────────────────────────────────────────────────────

class GeneralSettingsScreen extends ConsumerStatefulWidget {
  const GeneralSettingsScreen({super.key});

  @override
  ConsumerState<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends ConsumerState<GeneralSettingsScreen> {
  final _companyName = TextEditingController();
  final _address1 = TextEditingController();
  final _address2 = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _gstin = TextEditingController();
  final _pan = TextEditingController();
  final _weighbridgeName = TextEditingController();
  final _locationNotes = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _officeLatitude = TextEditingController();
  final _officeLongitude = TextEditingController();

  String _dateFormat = 'DD/MM/YYYY';
  String _timeFormat = '24-hour';
  String _currency = 'INR';
  String _systemCode = '';
  bool _loaded = false;
  bool _saving = false;
  bool _dirty = false;

  String? _gstinError;
  String? _panError;

  @override
  void dispose() {
    _companyName.dispose();
    _address1.dispose();
    _address2.dispose();
    _phone.dispose();
    _email.dispose();
    _gstin.dispose();
    _pan.dispose();
    _weighbridgeName.dispose();
    _locationNotes.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _officeLatitude.dispose();
    _officeLongitude.dispose();
    super.dispose();
  }

  void _loadData(Map<String, dynamic> data) {
    if (_loaded) return;
    _loaded = true;
    _companyName.text = data['companyName'] ?? '';
    _address1.text = data['address1'] ?? '';
    _address2.text = data['address2'] ?? '';
    _phone.text = data['phone'] ?? '';
    _email.text = data['email'] ?? '';
    _gstin.text = data['gstin'] ?? '';
    _pan.text = data['pan'] ?? '';
    _weighbridgeName.text = data['weighbridgeName'] ?? '';
    _locationNotes.text = data['locationNotes'] ?? '';
    _latitude.text = data['latitude']?.toString() ?? '';
    _longitude.text = data['longitude']?.toString() ?? '';
    _officeLatitude.text = data['officeLatitude']?.toString() ?? '';
    _officeLongitude.text = data['officeLongitude']?.toString() ?? '';
    _dateFormat = data['dateFormat'] ?? 'DD/MM/YYYY';
    _timeFormat = data['timeFormat'] ?? '24-hour';
    _currency = data['currency'] ?? 'INR';
    _systemCode = data['systemCode'] ?? _generateSystemCode();
  }

  String _generateSystemCode() {
    final now = DateTime.now();
    return 'WB-${now.year}-${now.millisecondsSinceEpoch.toRadixString(16).substring(4, 8).toUpperCase()}';
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  bool _validateGstin(String value) {
    if (value.isEmpty) return true;
    final regex = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$');
    return regex.hasMatch(value.toUpperCase());
  }

  bool _validatePan(String value) {
    if (value.isEmpty) return true;
    final regex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
    return regex.hasMatch(value.toUpperCase());
  }

  Future<void> _save() async {
    // Validate
    final gstin = _gstin.text.trim().toUpperCase();
    final pan = _pan.text.trim().toUpperCase();

    setState(() {
      _gstinError = !_validateGstin(gstin) ? 'Invalid GSTIN format (e.g. 22AAAAA0000A1Z5)' : null;
      _panError = !_validatePan(pan) ? 'Invalid PAN format (e.g. ABCDE1234F)' : null;
    });

    if (_gstinError != null || _panError != null) return;

    setState(() => _saving = true);

    try {
      final db = ref.read(firestoreProvider);
      await db.collection('settings').doc('general').set({
        'companyName': _toTitleCase(_companyName.text.trim()),
        'address1': _toTitleCase(_address1.text.trim()),
        'address2': _toTitleCase(_address2.text.trim()),
        'phone': _phone.text.trim(),
        'email': _email.text.trim().toLowerCase(),
        'gstin': gstin,
        'pan': pan,
        'weighbridgeName': _toTitleCase(_weighbridgeName.text.trim()),
        'systemCode': _systemCode,
        'locationNotes': _locationNotes.text.trim(),
        'latitude': double.tryParse(_latitude.text.trim()),
        'longitude': double.tryParse(_longitude.text.trim()),
        'officeLatitude': double.tryParse(_officeLatitude.text.trim()),
        'officeLongitude': double.tryParse(_officeLongitude.text.trim()),
        'dateFormat': _dateFormat,
        'timeFormat': _timeFormat,
        'currency': _currency,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      ref.invalidate(_generalSettingsProvider);
      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully')),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final settingsAsync = ref.watch(_generalSettingsProvider);

    settingsAsync.whenData(_loadData);

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
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.settings_rounded, size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('General Settings', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      'Company information, regional preferences, and identity',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
                if (_dirty) ...[
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _loaded = false;
                        _dirty = false;
                      });
                      ref.invalidate(_generalSettingsProvider);
                    },
                    child: const Text('Discard'),
                  ),
                  const SizedBox(width: 8),
                ],
                FilledButton.icon(
                  onPressed: _dirty && !_saving ? _save : null,
                  icon: _saving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded, size: 16),
                  label: const Text('Save Changes'),
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
            child: settingsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) => SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCompanySection(scheme, text),
                    const SizedBox(height: 28),
                    _buildRegionalSection(scheme, text),
                    const SizedBox(height: 28),
                    _buildWeighbridgeIdentity(scheme, text),
                    const SizedBox(height: 28),
                    _buildLocationSection(scheme, text),
                    const SizedBox(height: 28),
                    _buildDocumentsSection(scheme, text),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Company Information ─────────────────────────────────────────────────

  Widget _buildCompanySection(ColorScheme scheme, TextTheme text) {
    return _SettingsCard(
      icon: Icons.business_rounded,
      title: 'Company Information',
      scheme: scheme,
      text: text,
      child: Column(
        children: [
          _Field(
            label: 'Company Name',
            controller: _companyName,
            hint: 'e.g. Industrial Weighing Solutions Ltd.',
            onChanged: (_) => _markDirty(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _Field(label: 'Address Line 1', controller: _address1, hint: 'Street, building', onChanged: (_) => _markDirty())),
              const SizedBox(width: 14),
              Expanded(child: _Field(label: 'Address Line 2', controller: _address2, hint: 'Area, city, state', onChanged: (_) => _markDirty())),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _Field(label: 'Phone Number', controller: _phone, hint: '+91 98765 43210', onChanged: (_) => _markDirty())),
              const SizedBox(width: 14),
              Expanded(child: _Field(label: 'Email Address', controller: _email, hint: 'admin@company.com', onChanged: (_) => _markDirty())),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Field(
                  label: 'GSTIN',
                  controller: _gstin,
                  hint: '22AAAAA0000A1Z5',
                  error: _gstinError,
                  onChanged: (_) {
                    _markDirty();
                    if (_gstinError != null) setState(() => _gstinError = null);
                  },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _Field(
                  label: 'PAN',
                  controller: _pan,
                  hint: 'ABCDE1234F',
                  error: _panError,
                  onChanged: (_) {
                    _markDirty();
                    if (_panError != null) setState(() => _panError = null);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Regional Settings ───────────────────────────────────────────────────

  Widget _buildRegionalSection(ColorScheme scheme, TextTheme text) {
    return _SettingsCard(
      icon: Icons.language_rounded,
      title: 'Regional Settings',
      scheme: scheme,
      text: text,
      child: Row(
        children: [
          Expanded(
            child: _DropdownField(
              label: 'Date Format',
              value: _dateFormat,
              items: const ['DD/MM/YYYY', 'MM/DD/YYYY', 'YYYY-MM-DD'],
              onChanged: (v) {
                setState(() => _dateFormat = v!);
                _markDirty();
              },
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Time Format', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _RadioChip(label: '12-hour', selected: _timeFormat == '12-hour', onTap: () { setState(() => _timeFormat = '12-hour'); _markDirty(); }),
                    const SizedBox(width: 8),
                    _RadioChip(label: '24-hour', selected: _timeFormat == '24-hour', onTap: () { setState(() => _timeFormat = '24-hour'); _markDirty(); }),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _DropdownField(
              label: 'Currency',
              value: _currency,
              items: const ['INR', 'USD', 'EUR', 'GBP'],
              onChanged: (v) {
                setState(() => _currency = v!);
                _markDirty();
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Weighbridge Identity ────────────────────────────────────────────────

  Widget _buildWeighbridgeIdentity(ColorScheme scheme, TextTheme text) {
    return _SettingsCard(
      icon: Icons.hub_rounded,
      title: 'Weighbridge Identity',
      scheme: scheme,
      text: text,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Field(
                  label: 'Weighbridge Name',
                  controller: _weighbridgeName,
                  hint: 'Main Entrance Gate - WB01',
                  onChanged: (_) => _markDirty(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('System Code (Read-Only)', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _systemCode,
                              style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
                            ),
                          ),
                          Icon(Icons.lock_rounded, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Field(
            label: 'Location Notes',
            controller: _locationNotes,
            hint: 'Specific notes about the weighbridge installation point...',
            maxLines: 3,
            onChanged: (_) => _markDirty(),
          ),
        ],
      ),
    );
  }

  // ─── Location (Coordinates) ──────────────────────────────────────────────

  Widget _buildLocationSection(ColorScheme scheme, TextTheme text) {
    return _SettingsCard(
      icon: Icons.location_on_rounded,
      title: 'GPS Coordinates',
      subtitle: 'Used for satellite verification and mapping',
      scheme: scheme,
      text: text,
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.scale_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Text('Weighbridge Location', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _Field(label: 'Latitude', controller: _latitude, hint: '19.0760', onChanged: (_) => _markDirty())),
              const SizedBox(width: 14),
              Expanded(child: _Field(label: 'Longitude', controller: _longitude, hint: '72.8777', onChanged: (_) => _markDirty())),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(' ', style: text.labelSmall),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.map_rounded, size: 16),
                        label: const Text('Pick on Map'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(Icons.business_rounded, size: 16, color: scheme.secondary),
              const SizedBox(width: 8),
              Text('Company Office Location', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _Field(label: 'Latitude', controller: _officeLatitude, hint: '19.0760', onChanged: (_) => _markDirty())),
              const SizedBox(width: 14),
              Expanded(child: _Field(label: 'Longitude', controller: _officeLongitude, hint: '72.8777', onChanged: (_) => _markDirty())),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(' ', style: text.labelSmall),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.map_rounded, size: 16),
                        label: const Text('Pick on Map'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Documents ───────────────────────────────────────────────────────────

  Widget _buildDocumentsSection(ColorScheme scheme, TextTheme text) {
    return _SettingsCard(
      icon: Icons.folder_rounded,
      title: 'Documents & Certificates',
      subtitle: 'Upload official documents for record-keeping',
      scheme: scheme,
      text: text,
      child: Row(
        children: [
          Expanded(child: _UploadTile(label: 'Company Logo', icon: Icons.image_rounded, scheme: scheme, text: text)),
          const SizedBox(width: 14),
          Expanded(child: _UploadTile(label: 'GSTIN Certificate', icon: Icons.description_rounded, scheme: scheme, text: text)),
          const SizedBox(width: 14),
          Expanded(child: _UploadTile(label: 'PAN Card', icon: Icons.credit_card_rounded, scheme: scheme, text: text)),
        ],
      ),
    );
  }
}

// ─── Reusable Widgets ────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final ColorScheme scheme;
  final TextTheme text;
  final Widget child;

  const _SettingsCard({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.scheme,
    required this.text,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
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
                  color: scheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  if (subtitle != null)
                    Text(subtitle!, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final String? error;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    this.error,
    this.maxLines = 1,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: text.bodySmall,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            errorText: error,
            errorStyle: TextStyle(fontSize: 10, color: scheme.error),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            isDense: true,
          ),
        ),
      ],
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: value,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: text.bodySmall))).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          style: text.bodySmall,
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _RadioChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RadioChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? scheme.primary : scheme.outline, width: selected ? 4 : 1.5),
                color: selected ? scheme.onPrimary : Colors.transparent,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final ColorScheme scheme;
  final TextTheme text;

  const _UploadTile({required this.label, required this.icon, required this.scheme, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3), style: BorderStyle.solid),
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: scheme.primary),
          ),
          const SizedBox(height: 10),
          Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'Click to upload',
            style: text.labelSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w500),
          ),
          Text(
            'PNG, JPG, PDF (max 2MB)',
            style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}
