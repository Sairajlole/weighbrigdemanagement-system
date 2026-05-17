import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';
import '../../application/setup_wizard_provider.dart';
import '../../application/setup_wizard_state.dart';

class SiteStep extends ConsumerStatefulWidget {
  const SiteStep({super.key});

  @override
  ConsumerState<SiteStep> createState() => _SiteStepState();
}

class _SiteStepState extends ConsumerState<SiteStep> {
  int _subStep = 0;
  String? _selectedCompanyId;
  String? _selectedSiteId;
  String? _selectedWeighbridgeId;

  String _newCompanyName = '';
  String _newSiteName = '';
  String _newSiteLocation = '';
  String _newWeighbridgeName = '';
  bool _loading = false;

  FirebaseFirestore get _db => ref.read(firestoreProvider);

  @override
  void initState() {
    super.initState();
    _resolveUserCompany();
  }

  Future<void> _resolveUserCompany() async {
    final wizardState = ref.read(setupWizardProvider);
    final email = await LocalCacheService.getCachedCurrentUserEmail();
    if (email == null) return;

    // Find the operator's record to get their company
    final opSnap = await _db.collection('operators').where('email', isEqualTo: email).limit(1).get();
    if (opSnap.docs.isEmpty) return;

    final opData = opSnap.docs.first.data();
    final role = opData['role'] as String?;

    if (wizardState.role == WizardRole.admin || role == 'companyAdmin') {
      // Admin — find the company they own
      final uid = opData['uid'] as String?;
      if (uid != null) {
        final companySnap = await _db.collection('companies').where('adminUid', isEqualTo: uid).limit(1).get();
        if (companySnap.docs.isNotEmpty && mounted) {
          setState(() {
            _selectedCompanyId = companySnap.docs.first.id;
            _subStep = 1; // Skip company selection, go to site
            });
          return;
        }
      }
    } else {
      // Operator — use companyId from their record
      final companyId = opData['companyId'] as String?;
      if (companyId != null && companyId.isNotEmpty && mounted) {
        setState(() {
          _selectedCompanyId = companyId;
          _subStep = 1;
        });
      }
    }
  }

  Future<String?> _createCompany(String name) async {
    final existing = await _db.collection('companies').where('name', isEqualTo: name).limit(1).get();
    if (existing.docs.isNotEmpty) {
      if (mounted) _showError('Company "$name" already exists');
      return null;
    }
    final doc = await _db.collection('companies').add({'name': name, 'createdAt': FieldValue.serverTimestamp()});
    return doc.id;
  }

  Future<String?> _createSite(String name, String location) async {
    final col = _db.collection('companies/$_selectedCompanyId/sites');
    final existing = await col.where('name', isEqualTo: name).limit(1).get();
    if (existing.docs.isNotEmpty) {
      if (mounted) _showError('Site "$name" already exists');
      return null;
    }
    final doc = await col.add({'name': name, 'location': location, 'createdAt': FieldValue.serverTimestamp()});
    return doc.id;
  }

  Future<String?> _createWeighbridge(String name) async {
    final col = _db.collection('companies/$_selectedCompanyId/sites/$_selectedSiteId/weighbridges');
    final existing = await col.where('name', isEqualTo: name).limit(1).get();
    if (existing.docs.isNotEmpty) {
      if (mounted) _showError('Weighbridge "$name" already exists');
      return null;
    }
    final doc = await col.add({'name': name, 'createdAt': FieldValue.serverTimestamp()});
    return doc.id;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  Future<void> _finish() async {
    if (_selectedCompanyId == null || _selectedSiteId == null || _selectedWeighbridgeId == null) return;
    setState(() => _loading = true);
    await ref.read(siteContextProvider.notifier).configure(
      companyId: _selectedCompanyId!,
      siteId: _selectedSiteId!,
      weighbridgeId: _selectedWeighbridgeId!,
    );
    if (mounted) {
      ref.read(setupWizardProvider.notifier).nextStep();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Site Configuration', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Set up your company, site, and weighbridge hierarchy.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          // Sub-step indicator
          Row(
            children: List.generate(3, (i) => Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                decoration: BoxDecoration(
                  color: i <= _subStep ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            )),
          ),
          const SizedBox(height: 28),

          if (_subStep == 0) _buildCompanySubStep(scheme, text),
          if (_subStep == 1) _buildSiteSubStep(scheme, text),
          if (_subStep == 2) _buildWeighbridgeSubStep(scheme, text),
        ],
      ),
    );
  }

  Widget _buildCompanySubStep(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Create Company', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(
          'Your company was not found. Create one to continue.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        _buildInput('Company Name', (v) => setState(() => _newCompanyName = v)),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _newCompanyName.trim().isNotEmpty && !_loading
                ? () async {
                    setState(() => _loading = true);
                    final id = await _createCompany(_newCompanyName.trim());
                    if (id != null && mounted) {
                      setState(() { _selectedCompanyId = id; _subStep = 1; });
                    }
                    if (mounted) setState(() => _loading = false);
                  }
                : null,
            child: _loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Create & Continue'),
          ),
        ),
      ],
    );
  }

  Widget _buildSiteSubStep(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select Site', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text('A site is a physical location with one or more weighbridges.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        _CollectionSelector(
          stream: _db.collection('companies/$_selectedCompanyId/sites').snapshots(),
          selected: _selectedSiteId,
          onSelected: (id) => setState(() => _selectedSiteId = id),
          emptyText: 'No sites yet — create one below.',
          showLocation: true,
        ),
        const SizedBox(height: 16),
        _CreateNewSection(
          label: 'Create new site',
          fields: [
            _buildInput('Site Name', (v) => setState(() => _newSiteName = v)),
            const SizedBox(height: 10),
            _buildInput('Location (optional)', (v) => setState(() => _newSiteLocation = v)),
          ],
          canCreate: _newSiteName.trim().isNotEmpty,
          loading: _loading,
          onCreate: () async {
            setState(() => _loading = true);
            final id = await _createSite(_newSiteName.trim(), _newSiteLocation.trim());
            setState(() { if (id != null) _selectedSiteId = id; _loading = false; });
          },
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(onPressed: () => setState(() => _subStep = 0), child: const Text('Back')),
            FilledButton(
              onPressed: _selectedSiteId != null ? () => setState(() => _subStep = 2) : null,
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWeighbridgeSubStep(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select Weighbridge', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text('Choose which weighbridge this device will operate.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        _CollectionSelector(
          stream: _db.collection('companies/$_selectedCompanyId/sites/$_selectedSiteId/weighbridges').snapshots(),
          selected: _selectedWeighbridgeId,
          onSelected: (id) => setState(() => _selectedWeighbridgeId = id),
          emptyText: 'No weighbridges yet — create one below.',
        ),
        const SizedBox(height: 16),
        _CreateNewSection(
          label: 'Create new weighbridge',
          fields: [
            _buildInput('Weighbridge Name', (v) => setState(() => _newWeighbridgeName = v), hint: 'e.g. WB-01'),
          ],
          canCreate: _newWeighbridgeName.trim().isNotEmpty,
          loading: _loading,
          onCreate: () async {
            setState(() => _loading = true);
            final id = await _createWeighbridge(_newWeighbridgeName.trim());
            setState(() { if (id != null) _selectedWeighbridgeId = id; _loading = false; });
          },
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(onPressed: () => setState(() => _subStep = 1), child: const Text('Back')),
            FilledButton(
              onPressed: _selectedWeighbridgeId != null ? (_loading ? null : _finish) : null,
              child: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Configure'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInput(String label, ValueChanged<String> onChanged, {String? hint}) {
    return TextField(
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      ),
      onChanged: onChanged,
    );
  }
}

class _CollectionSelector extends StatelessWidget {
  final Stream<QuerySnapshot> stream;
  final String? selected;
  final ValueChanged<String> onSelected;
  final String emptyText;
  final bool showLocation;

  const _CollectionSelector({
    required this.stream,
    required this.selected,
    required this.onSelected,
    required this.emptyText,
    this.showLocation = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) return const LinearProgressIndicator();
        final docs = snap.data!.docs;
        if (docs.isEmpty) return Text(emptyText, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant));
        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final isSelected = doc.id == selected;
            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                title: Text(data['name'] ?? doc.id),
                subtitle: showLocation && data['location'] != null && (data['location'] as String).isNotEmpty
                    ? Text(data['location'])
                    : null,
                leading: Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off, color: isSelected ? scheme.primary : null),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                selected: isSelected,
                selectedTileColor: scheme.primary.withValues(alpha: 0.06),
                onTap: () => onSelected(doc.id),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _CreateNewSection extends StatelessWidget {
  final String label;
  final List<Widget> fields;
  final bool canCreate;
  final bool loading;
  final VoidCallback onCreate;

  const _CreateNewSection({
    required this.label,
    required this.fields,
    required this.canCreate,
    required this.loading,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(label, style: Theme.of(context).textTheme.labelLarge),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        ...fields,
        const SizedBox(height: 12),
        FilledButton(
          onPressed: canCreate && !loading ? onCreate : null,
          child: loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create'),
        ),
      ],
    );
  }
}
