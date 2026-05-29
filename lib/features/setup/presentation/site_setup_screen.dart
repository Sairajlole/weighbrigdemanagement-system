import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

class SiteSetupScreen extends ConsumerStatefulWidget {
  const SiteSetupScreen({super.key});

  @override
  ConsumerState<SiteSetupScreen> createState() => _SiteSetupScreenState();
}

class _SiteSetupScreenState extends ConsumerState<SiteSetupScreen> {
  int _step = 0; // 0=company, 1=site, 2=weighbridge
  bool _loading = false;

  // Company
  String? _selectedCompanyId;
  String _newCompanyName = '';

  // Site
  String? _selectedSiteId;
  String _newSiteName = '';
  String _newSiteLocation = '';

  // Weighbridge
  String? _selectedWeighbridgeId;
  String _newWeighbridgeName = '';

  FirebaseFirestore get _db => ref.read(firestoreProvider);

  Future<void> _finish() async {
    if (_selectedCompanyId == null || _selectedSiteId == null || _selectedWeighbridgeId == null) return;
    setState(() => _loading = true);
    await ref.read(siteContextProvider.notifier).configure(
      companyId: _selectedCompanyId!,
      siteId: _selectedSiteId!,
      weighbridgeId: _selectedWeighbridgeId!,
    );
    if (mounted) context.go('/dashboard');
  }

  Future<String?> _createCompany(String name) async {
    final existing = await _db.collection('companies')
        .where('name', isEqualTo: name).limit(1).get();
    if (existing.docs.isNotEmpty) {
      if (mounted) _showDuplicateError('Company "$name" already exists');
      return null;
    }
    final doc = await _db.collection('companies').add({
      'name': name,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<String?> _createSite(String name, String location) async {
    final col = _db.collection('companies/$_selectedCompanyId/sites');
    final existing = await col.where('name', isEqualTo: name).limit(1).get();
    if (existing.docs.isNotEmpty) {
      if (mounted) _showDuplicateError('Site "$name" already exists');
      return null;
    }
    final doc = await col.add({
      'name': name,
      'location': location,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<String?> _createWeighbridge(String name) async {
    final col = _db.collection('companies/$_selectedCompanyId/sites/$_selectedSiteId/weighbridges');
    final existing = await col.where('name', isEqualTo: name).limit(1).get();
    if (existing.docs.isNotEmpty) {
      if (mounted) _showDuplicateError('Weighbridge "$name" already exists');
      return null;
    }
    final doc = await col.add({
      'name': name,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  void _showDuplicateError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: Container(
          width: 480,
          padding: EdgeInsets.all(40.rs),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20.rs),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Progress
              Row(
                children: List.generate(3, (i) => Expanded(
                  child: Container(
                    height: 4,
                    margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                    decoration: BoxDecoration(
                      color: i <= _step ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                )),
              ),
              SizedBox(height: AppSpacing.xxl),

              if (_step == 0) _buildCompanyStep(scheme, text),
              if (_step == 1) _buildSiteStep(scheme, text),
              if (_step == 2) _buildWeighbridgeStep(scheme, text),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompanyStep(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Select Company', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        SizedBox(height: AppSpacing.sm),
        Text('Choose an existing company or create a new one.', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        SizedBox(height: AppSpacing.xl),
        _CompanySelector(
          db: _db,
          selected: _selectedCompanyId,
          onSelected: (id) => setState(() => _selectedCompanyId = id),
        ),
        SizedBox(height: AppSpacing.lg),
        // Or create new
        ExpansionTile(
          title: Text('Create new company', style: text.labelLarge),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Company Name', border: OutlineInputBorder()),
              onChanged: (v) => setState(() => _newCompanyName = v),
            ),
            SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: _newCompanyName.trim().isEmpty ? null : () async {
                setState(() => _loading = true);
                final id = await _createCompany(_newCompanyName.trim());
                setState(() { if (id != null) _selectedCompanyId = id; _loading = false; });
              },
              child: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create'),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.xl),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _selectedCompanyId != null ? () => setState(() => _step = 1) : null,
            child: const Text('Next'),
          ),
        ),
      ],
    );
  }

  Widget _buildSiteStep(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Select Site', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        SizedBox(height: AppSpacing.sm),
        Text('A site represents a physical location with one or more weighbridges.', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        SizedBox(height: AppSpacing.xl),
        _SiteSelector(
          db: _db,
          companyId: _selectedCompanyId!,
          selected: _selectedSiteId,
          onSelected: (id) => setState(() => _selectedSiteId = id),
        ),
        SizedBox(height: AppSpacing.lg),
        ExpansionTile(
          title: Text('Create new site', style: text.labelLarge),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Site Name', border: OutlineInputBorder()),
              onChanged: (v) => setState(() => _newSiteName = v),
            ),
            SizedBox(height: AppSpacing.md),
            TextField(
              decoration: const InputDecoration(labelText: 'Location (optional)', border: OutlineInputBorder()),
              onChanged: (v) => setState(() => _newSiteLocation = v),
            ),
            SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: _newSiteName.trim().isEmpty ? null : () async {
                setState(() => _loading = true);
                final id = await _createSite(_newSiteName.trim(), _newSiteLocation.trim());
                setState(() { if (id != null) _selectedSiteId = id; _loading = false; });
              },
              child: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create'),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.xl),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(onPressed: () => setState(() => _step = 0), child: const Text('Back')),
            FilledButton(
              onPressed: _selectedSiteId != null ? () => setState(() => _step = 2) : null,
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWeighbridgeStep(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Select Weighbridge', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        SizedBox(height: AppSpacing.sm),
        Text('Choose which weighbridge this device will operate.', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        SizedBox(height: AppSpacing.xl),
        _WeighbridgeSelector(
          db: _db,
          companyId: _selectedCompanyId!,
          siteId: _selectedSiteId!,
          selected: _selectedWeighbridgeId,
          onSelected: (id) => setState(() => _selectedWeighbridgeId = id),
        ),
        SizedBox(height: AppSpacing.lg),
        ExpansionTile(
          title: Text('Create new weighbridge', style: text.labelLarge),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Weighbridge Name', hintText: 'e.g. WB-01', border: OutlineInputBorder()),
              onChanged: (v) => setState(() => _newWeighbridgeName = v),
            ),
            SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: _newWeighbridgeName.trim().isEmpty ? null : () async {
                setState(() => _loading = true);
                final id = await _createWeighbridge(_newWeighbridgeName.trim());
                setState(() { if (id != null) _selectedWeighbridgeId = id; _loading = false; });
              },
              child: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create'),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.xl),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(onPressed: () => setState(() => _step = 1), child: const Text('Back')),
            FilledButton(
              onPressed: _selectedWeighbridgeId != null ? _finish : null,
              child: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Complete Setup'),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Selector widgets ──────────────────────────────────────────────────────

class _CompanySelector extends StatelessWidget {
  final FirebaseFirestore db;
  final String? selected;
  final ValueChanged<String> onSelected;

  const _CompanySelector({required this.db, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('companies').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const LinearProgressIndicator();
        final docs = snap.data!.docs;
        if (docs.isEmpty) return Text('No companies yet — create one below.', style: Theme.of(context).textTheme.bodySmall);
        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final isSelected = doc.id == selected;
            return ListTile(
              title: Text(data['name'] ?? doc.id),
              leading: Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
              selected: isSelected,
              onTap: () => onSelected(doc.id),
            );
          }).toList(),
        );
      },
    );
  }
}

class _SiteSelector extends StatelessWidget {
  final FirebaseFirestore db;
  final String companyId;
  final String? selected;
  final ValueChanged<String> onSelected;

  const _SiteSelector({required this.db, required this.companyId, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('companies/$companyId/sites').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const LinearProgressIndicator();
        final docs = snap.data!.docs;
        if (docs.isEmpty) return Text('No sites yet — create one below.', style: Theme.of(context).textTheme.bodySmall);
        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final isSelected = doc.id == selected;
            return ListTile(
              title: Text(data['name'] ?? doc.id),
              subtitle: data['location'] != null ? Text(data['location']) : null,
              leading: Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
              selected: isSelected,
              onTap: () => onSelected(doc.id),
            );
          }).toList(),
        );
      },
    );
  }
}

class _WeighbridgeSelector extends StatelessWidget {
  final FirebaseFirestore db;
  final String companyId;
  final String siteId;
  final String? selected;
  final ValueChanged<String> onSelected;

  const _WeighbridgeSelector({required this.db, required this.companyId, required this.siteId, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('companies/$companyId/sites/$siteId/weighbridges').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const LinearProgressIndicator();
        final docs = snap.data!.docs;
        if (docs.isEmpty) return Text('No weighbridges yet — create one below.', style: Theme.of(context).textTheme.bodySmall);
        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final isSelected = doc.id == selected;
            return ListTile(
              title: Text(data['name'] ?? doc.id),
              leading: Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
              selected: isSelected,
              onTap: () => onSelected(doc.id),
            );
          }).toList(),
        );
      },
    );
  }
}
