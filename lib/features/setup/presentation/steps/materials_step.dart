import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import '../../application/setup_wizard_provider.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/app_loading.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

class MaterialsStep extends ConsumerStatefulWidget {
  const MaterialsStep({super.key});

  @override
  ConsumerState<MaterialsStep> createState() => _MaterialsStepState();
}

class _MaterialsStepState extends ConsumerState<MaterialsStep> {
  final _nameCtrl = TextEditingController();
  bool _allowOther = true;
  bool _loaded = false;
  bool _adding = false;
  List<Map<String, dynamic>> _materials = [];


  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(stepSaveCallbackProvider.notifier).state = _save;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _updateHasData() {
    ref.read(stepHasDataProvider.notifier).state = _materials.isNotEmpty;
  }

  Future<void> _loadData() async {
    final paths = ref.read(firestorePathsProvider);
    if (!paths.isConfigured) {
      setState(() => _loaded = true);
      return;
    }

    try {
      final snap = await paths.materials.orderBy('order').get();
      final settingsSnap = await paths.materialsSettings.get();
      final settingsData = settingsSnap.data() ?? {};

      if (mounted) {
        setState(() {
          _materials = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          _allowOther = settingsData['allowOther'] as bool? ?? true;
          _loaded = true;
        });
        _updateHasData();
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _addMaterial(String name) async {
    if (name.trim().isEmpty) return;
    setState(() => _adding = true);

    try {
      final paths = ref.read(firestorePathsProvider);
      final docRef = await paths.materials.add({
        'name': name.trim(),
        'active': true,
        'isDefault': _materials.isEmpty,
        'order': _materials.length,
        'createdAt': FieldValue.serverTimestamp(),
      });
      setState(() {
        _materials.add({'id': docRef.id, 'name': name.trim(), 'active': true, 'isDefault': _materials.isEmpty});
        _nameCtrl.clear();
      });
      _updateHasData();
    } catch (_) {}
    setState(() => _adding = false);
  }

  Future<void> _removeMaterial(int index) async {
    final item = _materials[index];
    final wasDefault = item['isDefault'] == true;
    final paths = ref.read(firestorePathsProvider);
    try {
      await paths.materials.doc(item['id'] as String).delete();
      setState(() => _materials.removeAt(index));
      if (wasDefault && _materials.isNotEmpty) {
        _setDefault(0);
      }
      _updateHasData();
    } catch (_) {}
  }

  Future<void> _setDefault(int index) async {
    final paths = ref.read(firestorePathsProvider);
    final batch = paths.firestore.batch();
    for (int i = 0; i < _materials.length; i++) {
      final id = _materials[i]['id'] as String;
      batch.update(paths.materials.doc(id), {'isDefault': i == index});
      _materials[i]['isDefault'] = i == index;
    }
    setState(() {});
    try {
      await batch.commit();
    } catch (_) {}
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final item = _materials.removeAt(oldIndex);
    _materials.insert(newIndex, item);
    setState(() {});

    final paths = ref.read(firestorePathsProvider);
    final batch = paths.firestore.batch();
    for (int i = 0; i < _materials.length; i++) {
      final id = _materials[i]['id'] as String;
      batch.update(paths.materials.doc(id), {'order': i});
    }
    try {
      await batch.commit();
    } catch (_) {}
  }


  Future<bool> _save() async {
    try {
      final paths = ref.read(firestorePathsProvider);
      await paths.materialsSettings.set({
        'allowOther': _allowOther,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), behavior: SnackBarBehavior.floating),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (!_loaded) return const AppLoading();

    return SingleChildScrollView(
      padding: EdgeInsets.all(40.rs),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text('Materials', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: AppSpacing.sm),
          Text(
            'Define the materials your weighbridge handles. These appear in the weighment form.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          SizedBox(height: AppSpacing.xxl),

          // Add material
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    hintText: 'Material name (e.g. Sand, Gravel)',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.rs)),
                  ),
                  onSubmitted: _addMaterial,
                ),
              ),
              SizedBox(width: AppSpacing.md),
              FilledButton.icon(
                onPressed: _adding ? null : () => _addMaterial(_nameCtrl.text),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add'),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md),


          // Material list
          if (_materials.isNotEmpty) ...[
            SizedBox(height: AppSpacing.sm),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(10.rs),
              ),
              clipBehavior: Clip.antiAlias,
              child: ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _materials.length,
                onReorder: _onReorder,
                proxyDecorator: (child, index, animation) => Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8.rs),
                  child: child,
                ),
                itemBuilder: (context, i) {
                  final mat = _materials[i];
                  final isDefault = mat['isDefault'] == true;
                  return Container(
                    key: ValueKey(mat['id']),
                    decoration: BoxDecoration(
                      border: i > 0 ? Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))) : null,
                    ),
                    child: ListTile(
                      dense: true,
                      leading: ReorderableDragStartListener(
                        index: i,
                        child: Icon(Icons.drag_handle_rounded, size: 18, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                      ),
                      title: Row(
                        children: [
                          Text(mat['name'] as String, style: const TextStyle(fontSize: 13)),
                          if (isDefault) ...[
                            SizedBox(width: 8.rs),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer.withValues(alpha: 0.4),
                                borderRadius: AppRadius.chip,
                              ),
                              child: Text('Default', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: scheme.primary)),
                            ),
                          ],
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: Icon(
                                isDefault ? Icons.star_rounded : Icons.star_outline_rounded,
                                size: 16,
                                color: isDefault ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                              ),
                              tooltip: isDefault ? 'Default' : 'Set as default',
                              onPressed: isDefault ? null : () => _setDefault(i),
                            ),
                          ),
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: Icon(Icons.close_rounded, size: 16, color: scheme.error),
                              onPressed: () => _removeMaterial(i),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: 4.rs),
            Text('Drag to reorder. Tap the star to set default material.', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            SizedBox(height: 16.rs),
          ],

          // Allow Other toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10.rs),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Allow "Other" material', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        'Operators can type a material name not in the list',
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Switch(value: _allowOther, onChanged: (v) => setState(() => _allowOther = v)),
              ],
            ),
          ),

          SizedBox(height: AppSpacing.xl),
          Container(
            padding: EdgeInsets.all(12.rs),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.2),
              borderRadius: AppRadius.button,
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: scheme.primary),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'You can rename materials and manage AI training in Settings later.',
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
          ),
        ),
      ),
    );
  }
}
