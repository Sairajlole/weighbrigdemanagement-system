import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import '../../application/setup_wizard_provider.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

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
        _materials.add({'id': docRef.id, 'name': name.trim(), 'active': true});
        _nameCtrl.clear();
      });
      _updateHasData();
    } catch (_) {}
    setState(() => _adding = false);
  }

  Future<void> _removeMaterial(int index) async {
    final item = _materials[index];
    final paths = ref.read(firestorePathsProvider);
    try {
      await paths.materials.doc(item['id'] as String).delete();
      setState(() => _materials.removeAt(index));
      _updateHasData();
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

    if (!_loaded) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: EdgeInsets.all(40.rs),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text('Materials', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: 8.rs),
          Text(
            'Define the materials your weighbridge handles. These appear in the weighment form.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          SizedBox(height: 32.rs),

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
              SizedBox(width: 12.rs),
              FilledButton.icon(
                onPressed: _adding ? null : () => _addMaterial(_nameCtrl.text),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add'),
              ),
            ],
          ),
          SizedBox(height: 12.rs),


          // Material list
          if (_materials.isNotEmpty) ...[
            SizedBox(height: 8.rs),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(10.rs),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < _materials.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.2)),
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: scheme.primaryContainer,
                        child: Text('${i + 1}', style: TextStyle(fontSize: 11, color: scheme.primary)),
                      ),
                      title: Text(_materials[i]['name'] as String, style: const TextStyle(fontSize: 13)),
                      trailing: IconButton(
                        icon: Icon(Icons.close_rounded, size: 16, color: scheme.error),
                        onPressed: () => _removeMaterial(i),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: 20.rs),
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

          SizedBox(height: 24.rs),
          Container(
            padding: EdgeInsets.all(12.rs),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8.rs),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: scheme.primary),
                SizedBox(width: 8.rs),
                Expanded(
                  child: Text(
                    'You can reorder, rename, and manage AI training for materials in Settings later.',
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
