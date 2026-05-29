import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import '../../application/setup_wizard_provider.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

class SiteStep extends ConsumerStatefulWidget {
  const SiteStep({super.key});

  @override
  ConsumerState<SiteStep> createState() => _SiteStepState();
}

class _SiteStepState extends ConsumerState<SiteStep> {
  int _subStep = 0; // 0=site, 1=weighbridge
  String? _selectedCompanyId;
  String? _selectedSiteId;
  String? _selectedWeighbridgeId;

  final _newSiteCtrl = TextEditingController();
  final _newLocationCtrl = TextEditingController();
  final _newWeighbridgeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  FirebaseFirestore get _db => ref.read(firestoreProvider);

  @override
  void initState() {
    super.initState();
    _resolveCompany();
  }

  @override
  void dispose() {
    _newSiteCtrl.dispose();
    _newLocationCtrl.dispose();
    _newWeighbridgeCtrl.dispose();
    super.dispose();
  }

  void _resolveCompany() {
    final companyId = ref.read(wizardCompanyIdProvider);
    if (companyId != null && companyId.isNotEmpty) {
      _selectedCompanyId = companyId;
    }
  }



  static const _maxSites = 1;
  static const _maxWeighbridges = 1;

  Future<String?> _createSite(String name, String location) async {
    final col = _db.collection('companies/$_selectedCompanyId/sites');

    final allSites = await col.get();
    if (allSites.docs.length >= _maxSites) {
      _setError('Maximum $_maxSites site allowed during setup.');
      return null;
    }

    final existing = await col.where('name', isEqualTo: name).limit(1).get();
    if (existing.docs.isNotEmpty) {
      _setError('Site "$name" already exists');
      return null;
    }
    final doc = await col.add({'name': name, 'location': location, 'createdAt': FieldValue.serverTimestamp()});
    return doc.id;
  }

  Future<String?> _createWeighbridge(String name) async {
    final col = _db.collection('companies/$_selectedCompanyId/sites/$_selectedSiteId/weighbridges');

    final allWb = await col.get();
    if (allWb.docs.length >= _maxWeighbridges) {
      _setError('Maximum $_maxWeighbridges weighbridges allowed during setup.');
      return null;
    }

    final existing = await col.where('name', isEqualTo: name).limit(1).get();
    if (existing.docs.isNotEmpty) {
      _setError('Weighbridge "$name" already exists');
      return null;
    }
    final doc = await col.add({'name': name, 'createdAt': FieldValue.serverTimestamp()});
    return doc.id;
  }

  Future<void> _deleteSite(String siteId) async {
    setState(() => _loading = true);
    try {
      final wbCol = _db.collection('companies/$_selectedCompanyId/sites/$siteId/weighbridges');
      final wbSnap = await wbCol.get();
      for (final wb in wbSnap.docs) {
        await wb.reference.delete();
      }
      await _db.doc('companies/$_selectedCompanyId/sites/$siteId').delete();
      if (_selectedSiteId == siteId) {
        _selectedSiteId = null;
        _selectedWeighbridgeId = null;
      }
    } catch (e) {
      _setError('Failed to delete site: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _deleteWeighbridge(String wbId) async {
    setState(() => _loading = true);
    try {
      await _db.doc('companies/$_selectedCompanyId/sites/$_selectedSiteId/weighbridges/$wbId').delete();
      if (_selectedWeighbridgeId == wbId) {
        _selectedWeighbridgeId = null;
      }
    } catch (e) {
      _setError('Failed to delete weighbridge: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _setError(String msg) => setState(() => _error = msg);
  void _clearError() { if (_error != null) setState(() => _error = null); }

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

    if (_selectedCompanyId == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 40, color: scheme.error),
            SizedBox(height: 12.rs),
            Text('No company configured. Go back to the Company step.', style: text.bodyMedium),
            SizedBox(height: 16.rs),
            TextButton.icon(
              onPressed: () => ref.read(setupWizardProvider.notifier).previousStep(),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Site & Weighbridge', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              SizedBox(height: 8.rs),
              Text(
                'Configure the physical location and weighbridge for this device.',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              SizedBox(height: 24.rs),

              // Progress stepper
              _StepIndicator(currentStep: _subStep, scheme: scheme, text: text),
              SizedBox(height: 32.rs),

              // Error
              if (_error != null) ...[
                Container(
                  padding: EdgeInsets.all(12.rs),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10.rs),
                    border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: scheme.error),
                      SizedBox(width: 8.rs),
                      Expanded(child: Text(_error!, style: TextStyle(fontSize: 12, color: scheme.error))),
                      IconButton(
                        icon: Icon(Icons.close, size: 14, color: scheme.error),
                        onPressed: _clearError,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20.rs),
              ],

              if (_loading) ...[
                const Center(child: CircularProgressIndicator()),
              ] else ...[
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(
                    key: ValueKey(_subStep),
                    child: switch (_subStep) {
                      0 => _buildSiteSubStep(scheme, text),
                      _ => _buildWeighbridgeSubStep(scheme, text),
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildSiteSubStep(ColorScheme scheme, TextTheme text) {
    final siteStream = _db.collection('companies/$_selectedCompanyId/sites').snapshots();

    return _SubStepCard(
      icon: Icons.location_on_rounded,
      title: 'Site',
      description: 'A site is a physical location with one or more weighbridges.',
      scheme: scheme,
      text: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CollectionSelector(
            stream: siteStream,
            selected: _selectedSiteId,
            onSelected: (id) { setState(() => _selectedSiteId = id); _clearError(); },
            onDelete: (id) => _deleteSite(id),
            emptyText: 'No sites yet — create one below.',
            icon: Icons.location_on_outlined,
            showLocation: true,
            maxItems: _maxSites,
          ),
          SizedBox(height: 20.rs),

          StreamBuilder<QuerySnapshot>(
            stream: siteStream,
            builder: (context, snap) {
              final atLimit = (snap.data?.docs.length ?? 0) >= _maxSites;
              if (atLimit) {
                return Container(
                  padding: EdgeInsets.all(12.rs),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10.rs),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: scheme.primary),
                      SizedBox(width: 8.rs),
                      Text('Maximum $_maxSites site allowed. Remove to add a different one.',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                );
              }
              return Container(
                padding: EdgeInsets.all(16.rs),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12.rs),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Create new site', style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(height: 12.rs),
                    _StyledTextField(
                      controller: _newSiteCtrl,
                      label: 'Site Name',
                      hint: 'e.g. Main Yard',
                      icon: Icons.location_on_outlined,
                      onChanged: (_) { _clearError(); setState(() {}); },
                    ),
                    SizedBox(height: 10.rs),
                    _StyledTextField(
                      controller: _newLocationCtrl,
                      label: 'Location (optional)',
                      hint: 'e.g. Mumbai, Maharashtra',
                      icon: Icons.map_outlined,
                    ),
                    SizedBox(height: 12.rs),
                    FilledButton.tonalIcon(
                      onPressed: _newSiteCtrl.text.trim().isNotEmpty && !_loading
                          ? () async {
                              _clearError();
                              setState(() => _loading = true);
                              final id = await _createSite(_newSiteCtrl.text.trim(), _newLocationCtrl.text.trim());
                              if (id != null && mounted) {
                                _newSiteCtrl.clear();
                                _newLocationCtrl.clear();
                                setState(() => _selectedSiteId = id);
                              }
                              if (mounted) setState(() => _loading = false);
                            }
                          : null,
                      icon: _loading
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Create Site'),
                    ),
                  ],
                ),
              );
            },
          ),

          SizedBox(height: 24.rs),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.icon(
                onPressed: _selectedSiteId != null ? () => setState(() => _subStep = 1) : null,
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeighbridgeSubStep(ColorScheme scheme, TextTheme text) {
    final wbStream = _db.collection('companies/$_selectedCompanyId/sites/$_selectedSiteId/weighbridges').snapshots();

    return _SubStepCard(
      icon: Icons.scale_rounded,
      title: 'Weighbridge',
      description: 'Choose which weighbridge this device will operate.',
      scheme: scheme,
      text: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CollectionSelector(
            stream: wbStream,
            selected: _selectedWeighbridgeId,
            onSelected: (id) { setState(() => _selectedWeighbridgeId = id); _clearError(); },
            onDelete: (id) => _deleteWeighbridge(id),
            emptyText: 'No weighbridges yet — create one below.',
            icon: Icons.scale_outlined,
            maxItems: _maxWeighbridges,
          ),
          SizedBox(height: 20.rs),

          StreamBuilder<QuerySnapshot>(
            stream: wbStream,
            builder: (context, snap) {
              final atLimit = (snap.data?.docs.length ?? 0) >= _maxWeighbridges;
              if (atLimit) {
                return Container(
                  padding: EdgeInsets.all(12.rs),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10.rs),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 16, color: scheme.primary),
                          SizedBox(width: 8.rs),
                          Expanded(child: Text('1 weighbridge configured. All scale settings in this wizard will apply to it.',
                              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
                        ],
                      ),
                      SizedBox(height: 8.rs),
                      Row(
                        children: [
                          Icon(Icons.add_circle_outline_rounded, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                          SizedBox(width: 8.rs),
                          Expanded(child: Text('Additional weighbridges can be added in Settings later, as per your license.',
                              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)))),
                        ],
                      ),
                    ],
                  ),
                );
              }
              return Container(
                padding: EdgeInsets.all(16.rs),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12.rs),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Create new weighbridge', style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(height: 12.rs),
                    _StyledTextField(
                      controller: _newWeighbridgeCtrl,
                      label: 'Weighbridge Name',
                      hint: 'e.g. WB-01',
                      icon: Icons.scale_outlined,
                      onChanged: (_) { _clearError(); setState(() {}); },
                    ),
                    SizedBox(height: 12.rs),
                    FilledButton.tonalIcon(
                      onPressed: _newWeighbridgeCtrl.text.trim().isNotEmpty && !_loading
                          ? () async {
                              _clearError();
                              setState(() => _loading = true);
                              final id = await _createWeighbridge(_newWeighbridgeCtrl.text.trim());
                              if (id != null && mounted) {
                                _newWeighbridgeCtrl.clear();
                                setState(() => _selectedWeighbridgeId = id);
                              }
                              if (mounted) setState(() => _loading = false);
                            }
                          : null,
                      icon: _loading
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Create Weighbridge'),
                    ),
                  ],
                ),
              );
            },
          ),

          SizedBox(height: 24.rs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _subStep = 0),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Back'),
              ),
              FilledButton.icon(
                onPressed: _selectedWeighbridgeId != null ? (_loading ? null : _finish) : null,
                icon: _loading
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_rounded, size: 16),
                label: const Text('Configure'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Reusable Widgets ────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  final ColorScheme scheme;
  final TextTheme text;

  const _StepIndicator({required this.currentStep, required this.scheme, required this.text});

  @override
  Widget build(BuildContext context) {
    const labels = ['Site', 'Weighbridge'];
    return Row(
      children: List.generate(2, (i) {
        final isActive = i <= currentStep;
        final isCurrent = i == currentStep;
        return Expanded(
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? scheme.primary : scheme.surfaceContainerHigh,
                  border: isCurrent ? Border.all(color: scheme.primary, width: 2) : null,
                ),
                child: Center(
                  child: i < currentStep
                      ? Icon(Icons.check_rounded, size: 14, color: scheme.onPrimary)
                      : Text('${i + 1}', style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isActive ? scheme.onPrimary : scheme.onSurfaceVariant,
                        )),
                ),
              ),
              SizedBox(width: 8.rs),
              Text(labels[i], style: TextStyle(
                fontSize: 12,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                color: isCurrent ? scheme.onSurface : scheme.onSurfaceVariant,
              )),
              if (i < 1) Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: i < currentStep ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _SubStepCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget child;
  final ColorScheme scheme;
  final TextTheme text;

  const _SubStepCard({
    required this.icon, required this.title, required this.description,
    required this.child, required this.scheme, required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(24.rs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(color: scheme.shadow.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10.rs),
                ),
                child: Icon(icon, size: 18, color: scheme.primary),
              ),
              SizedBox(width: 12.rs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text(description, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          SizedBox(height: 24.rs),
          child,
        ],
      ),
    );
  }
}

class _StyledTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final ValueChanged<String>? onChanged;

  const _StyledTextField({
    required this.controller, required this.label, required this.hint,
    required this.icon, this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.rs)),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
      ),
    );
  }
}

class _CollectionSelector extends StatelessWidget {
  final Stream<QuerySnapshot> stream;
  final String? selected;
  final ValueChanged<String> onSelected;
  final ValueChanged<String>? onDelete;
  final String emptyText;
  final IconData icon;
  final bool showLocation;
  final int? maxItems;

  const _CollectionSelector({
    required this.stream, required this.selected, required this.onSelected,
    required this.emptyText, required this.icon, this.showLocation = false,
    this.onDelete, this.maxItems,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Container(
            padding: EdgeInsets.all(16.rs),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10.rs),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: scheme.onSurfaceVariant),
                SizedBox(width: 8.rs),
                Text(emptyText, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          );
        }
        if (docs.length == 1 && selected == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onSelected(docs.first.id));
        }
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(10.rs),
          ),
          child: Column(
            children: [
              for (int i = 0; i < docs.length; i++) ...[
                if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.15)),
                _buildItem(docs[i], scheme),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildItem(QueryDocumentSnapshot doc, ColorScheme scheme) {
    final data = doc.data() as Map<String, dynamic>;
    final isSelected = doc.id == selected;
    final name = data['name'] as String? ?? doc.id;
    final location = showLocation ? data['location'] as String? : null;

    return InkWell(
      onTap: () => onSelected(doc.id),
      borderRadius: BorderRadius.circular(8.rs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? scheme.primary.withValues(alpha: 0.06) : null,
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 18,
              color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            SizedBox(width: 12.rs),
            Icon(icon, size: 16, color: isSelected ? scheme.primary : scheme.onSurfaceVariant),
            SizedBox(width: 8.rs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? scheme.primary : scheme.onSurface,
                  )),
                  if (location != null && location.isNotEmpty)
                    Text(location, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                onPressed: () => onDelete!(doc.id),
                icon: Icon(Icons.delete_outline_rounded, size: 16, color: scheme.error.withValues(alpha: 0.7)),
                tooltip: 'Remove',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
          ],
        ),
      ),
    );
  }
}
