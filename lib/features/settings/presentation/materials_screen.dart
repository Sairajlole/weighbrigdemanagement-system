import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/widgets/weighbridge_context_bar.dart';
import 'package:weighbridgemanagement/shared/utils/title_case.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

final _materialsMigrationProvider = FutureProvider<void>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  if (!db.isConfigured) return;
  final wbSnap = await db.materials.limit(1).get();
  if (wbSnap.docs.isNotEmpty) return;
  final flatRef = db.firestore.collection('companies/${db.context.companyId}/materials');
  final flatSnap = await flatRef.get();
  if (flatSnap.docs.isEmpty) return;
  if (flatSnap.docs.first.data()['_migratedTo'] != null) return;
  final batch = db.batch();
  for (final doc in flatSnap.docs) {
    final data = Map<String, dynamic>.from(doc.data());
    data.remove('_migratedTo');
    batch.set(db.materials.doc(doc.id), {...data, 'migratedFrom': 'company', 'migratedAt': FieldValue.serverTimestamp()});
  }
  batch.update(flatSnap.docs.first.reference, {'_migratedTo': db.materials.path});
  await batch.commit();
});

final _materialsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  ref.watch(_materialsMigrationProvider);
  final db = ref.watch(firestorePathsProvider);
  return db.materials.orderBy('order').snapshots().map(
      (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

final _materialsSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  if (!db.isConfigured) return {};
  final doc = await db.materialsSettings.get();
  return doc.exists ? doc.data()! : {};
});

class MaterialsScreen extends ConsumerStatefulWidget {
  const MaterialsScreen({super.key});

  @override
  ConsumerState<MaterialsScreen> createState() => _MaterialsScreenState();
}

class _MaterialsScreenState extends ConsumerState<MaterialsScreen> {
  final _nameCtrl = TextEditingController();
  bool _allowOther = true;
  bool _saving = false;
  bool _settingsLoaded = false;
  List<Map<String, dynamic>>? _localMaterials;
  bool _reordering = false;

  String? _headerMsg;
  bool _headerMsgIsError = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _loadSettings(Map<String, dynamic> data) {
    if (_settingsLoaded) return;
    _settingsLoaded = true;
    _allowOther = data['allowOther'] as bool? ?? true;
  }

  void _showHeaderMsg(String msg, {bool isError = false}) {
    setState(() { _headerMsg = msg; _headerMsgIsError = isError; });
    Future.delayed(Duration(seconds: isError ? 5 : 3), () {
      if (mounted) setState(() => _headerMsg = null);
    });
  }

  Future<void> _saveAllowOther(bool value) async {
    setState(() => _allowOther = value);
    final db = ref.read(firestorePathsProvider);
    await db.materialsSettings.set({
      'allowOther': value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _addMaterial() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);
    try {
      final db = ref.read(firestorePathsProvider);
      final materials = ref.read(_materialsProvider).valueOrNull ?? [];
      await db.materials.add({
        'name': toTitleCase(name),
        'active': true,
        'isDefault': materials.isEmpty,
        'order': materials.length,
        'trainingImages': 0,
        'aiEnabled': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _nameCtrl.clear();
    } catch (e) {
      if (mounted) _showHeaderMsg('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleActive(String id, bool active) async {
    final db = ref.read(firestorePathsProvider);
    await db.materials.doc(id).update({'active': active});
  }

  Future<void> _setDefault(String id) async {
    final db = ref.read(firestorePathsProvider);
    final materials = ref.read(_materialsProvider).valueOrNull ?? [];
    final batch = db.batch();
    for (final m in materials) {
      batch.update(db.materials.doc(m['id']), {'isDefault': m['id'] == id});
    }
    await batch.commit();
  }

  Future<void> _confirmDelete(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final s = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
          title: Text('Delete "$name"?', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          content: const Text('This material will be permanently removed. Existing weighments using it will keep the name.', style: TextStyle(fontSize: 13)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: s.error),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      final db = ref.read(firestorePathsProvider);
      await db.materials.doc(id).delete();
    }
  }

  Future<void> _rename(String id, String currentName) async {
    final ctrl = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
          title: const Text('Rename Material', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Material Name', isDense: true),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
          ],
        );
      },
    );
    ctrl.dispose();
    if (newName != null && newName.isNotEmpty && newName != currentName) {
      final db = ref.read(firestorePathsProvider);
      await db.materials.doc(id).update({'name': toTitleCase(newName)});
    }
  }

  Future<void> _reorderMaterial(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final materials = List<Map<String, dynamic>>.from(_localMaterials ?? ref.read(_materialsProvider).valueOrNull ?? []);
    final item = materials.removeAt(oldIndex);
    materials.insert(newIndex, item);

    setState(() {
      _localMaterials = materials;
      _reordering = true;
    });

    final db = ref.read(firestorePathsProvider);
    final batch = db.batch();
    for (var i = 0; i < materials.length; i++) {
      batch.update(db.materials.doc(materials[i]['id']), {'order': i});
    }
    await batch.commit();

    if (mounted) setState(() => _reordering = false);
  }


  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final materialsAsync = ref.watch(_materialsProvider);
    final allMaterials = _reordering ? (_localMaterials ?? []) : (materialsAsync.valueOrNull ?? []);
    if (!_reordering) _localMaterials = null;
    ref.watch(_materialsSettingsProvider).whenData(_loadSettings);

    final activeMaterials = allMaterials.where((m) => m['active'] != false).toList();
    final inactiveMaterials = allMaterials.where((m) => m['active'] == false).toList();

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Column(
        children: [
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
                      onPressed: () {
                        context.go('/settings');
                      },
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                      style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
                    ),
                    SizedBox(width: AppSpacing.md),
                    Icon(Icons.inventory_2_rounded, size: 20, color: scheme.primary),
                    SizedBox(width: 10.rs),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Materials Management', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text('Product list and categories', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
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
            label: 'Materials for',
            onSwitched: () {
              setState(() { _settingsLoaded = false; _localMaterials = null; });
              ref.invalidate(_materialsMigrationProvider);
              ref.invalidate(_materialsProvider);
              ref.invalidate(_materialsSettingsProvider);
            },
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: AppSpacing.pagePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Materials List
                  _SettingsCard(
                    icon: Icons.inventory_2_rounded,
                    title: 'Material List',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.successColor,
                          ),
                        ),
                        SizedBox(width: 6.rs),
                        Text('${activeMaterials.length} active', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                        if (inactiveMaterials.isNotEmpty) ...[
                          SizedBox(width: 10.rs),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: scheme.outlineVariant,
                            ),
                          ),
                          SizedBox(width: 6.rs),
                          Text('${inactiveMaterials.length} hidden', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                        ],
                      ],
                    ),
                    scheme: scheme,
                    text: text,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _nameCtrl,
                                style: text.bodySmall,
                                decoration: InputDecoration(
                                  hintText: 'e.g. Gitti, Reti, Coal, Iron Ore',
                                  hintStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  filled: true,
                                  fillColor: scheme.surfaceContainerLow,
                                  border: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
                                  enabledBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
                                  focusedBorder: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: scheme.primary, width: 1.5)),
                                ),
                                onSubmitted: (_) => _addMaterial(),
                              ),
                            ),
                            SizedBox(width: AppSpacing.md),
                            FilledButton.icon(
                              onPressed: _saving ? null : _addMaterial,
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('Add'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 20.rs),
                        if (activeMaterials.isEmpty)
                          Center(
                            child: Padding(
                              padding: EdgeInsets.all(32.rs),
                              child: Column(
                                children: [
                                  Icon(Icons.inventory_2_outlined, size: 40, color: scheme.outlineVariant),
                                  SizedBox(height: AppSpacing.sm),
                                  Text('No materials added yet', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                                  SizedBox(height: AppSpacing.xs),
                                  Text('Type a name above and press Add', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
                                ],
                              ),
                            ),
                          )
                        else
                          ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerLow,
                                borderRadius: AppRadius.chip,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(width: 32.rs),
                                  Expanded(child: Text('MATERIAL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.5))),
                                  Text('ACTIONS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.5)),
                                  SizedBox(width: AppSpacing.md),
                                ],
                              ),
                            ),
                            SizedBox(height: AppSpacing.xs),
                            SizedBox(
                              height: activeMaterials.length * 56.0,
                              child: ReorderableListView.builder(
                                physics: const NeverScrollableScrollPhysics(),
                                padding: EdgeInsets.zero,
                                buildDefaultDragHandles: false,
                                itemCount: activeMaterials.length,
                                onReorder: _reorderMaterial,
                                proxyDecorator: (child, index, animation) {
                                  return Material(
                                    elevation: 4,
                                    borderRadius: AppRadius.button,
                                    child: child,
                                  );
                                },
                                itemBuilder: (context, index) {
                                  final m = activeMaterials[index];
                                  return _MaterialRow(
                                    key: ValueKey(m['id']),
                                    material: m,
                                    index: index,
                                    scheme: scheme,
                                    text: text,
                                    onToggle: (v) => _toggleActive(m['id'], v),
                                    onSetDefault: () => _setDefault(m['id']),
                                    onDelete: () => _confirmDelete(m['id'], m['name'] ?? ''),
                                    onRename: () => _rename(m['id'], m['name'] ?? ''),
                                    onUploadImages: () => _showUploadDialog(m),
                                  );
                                },
                              ),
                            ),
                          ],
                        SizedBox(height: 20.rs),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(10.rs),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.edit_note_rounded, size: 18, color: scheme.onSurfaceVariant),
                              SizedBox(width: 10.rs),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Allow 'Other' option", style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                                    Text("Operators can type a custom material not in this list", style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                              Switch(value: _allowOther, onChanged: _saveAllowOther),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Inactive Materials
                  if (inactiveMaterials.isNotEmpty) ...[
                    SizedBox(height: AppSpacing.xl),
                    _SettingsCard(
                      icon: Icons.visibility_off_rounded,
                      title: 'Inactive',
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(10.rs)),
                        child: Text('${inactiveMaterials.length}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
                      ),
                      scheme: scheme,
                      text: text,
                      child: Column(
                        children: inactiveMaterials.map((m) => Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.15))),
                          ),
                          child: Row(
                            children: [
                              Text(m['name'] ?? '', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                              const Spacer(),
                              TextButton(
                                onPressed: () => _toggleActive(m['id'], true),
                                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), minimumSize: const Size(0, 28)),
                                child: Text('Reactivate', style: TextStyle(fontSize: 11, color: scheme.primary)),
                              ),
                              IconButton(
                                onPressed: () => _confirmDelete(m['id'], m['name'] ?? ''),
                                icon: Icon(Icons.delete_outline_rounded, size: 16, color: scheme.error),
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                padding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        )).toList(),
                      ),
                    ),
                  ],
                  SizedBox(height: AppSpacing.xl),

                  // AI Training
                  _SettingsCard(
                    icon: Icons.model_training_rounded,
                    title: 'AI Material Recognition',
                    scheme: scheme,
                    text: text,
                    iconColor: AppTheme.successColor,
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(14.rs),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10.rs),
                        border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 15, color: scheme.primary),
                          SizedBox(width: 10.rs),
                          Expanded(
                            child: Text(
                              'Upload top-view images of loaded trucks via the camera icon on each material row. 20+ varied images per material recommended.',
                              style: text.bodySmall?.copyWith(color: scheme.onSurface, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 40.rs),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTrainingImages(String materialId, String materialName) async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select Training Images',
      type: FileType.image,
      allowMultiple: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final paths = picked.files.map((f) => f.path).where((p) => p != null && p.isNotEmpty).cast<String>().toList();
    if (paths.isEmpty) return;

    final db = ref.read(firestorePathsProvider);
    var uploaded = 0;

    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      if (file.lengthSync() > 10 * 1024 * 1024) continue;

      final bytes = file.readAsBytesSync();
      final ext = path.split('.').last.toLowerCase();
      final b64 = base64Encode(bytes);
      final fileName = path.split('/').last;

      await db.trainingData.add({
        'materialId': materialId,
        'materialName': materialName,
        'data': 'data:image/$ext;base64,$b64',
        'fileName': fileName,
        'uploadedAt': FieldValue.serverTimestamp(),
      });
      uploaded++;
    }

    if (uploaded > 0) {
      await db.materials.doc(materialId).update({
        'trainingImages': FieldValue.increment(uploaded),
      });
      if (mounted) {
        _showHeaderMsg('$uploaded image${uploaded > 1 ? 's' : ''} uploaded for training');
      }
    }
  }

  void _showUploadDialog(Map<String, dynamic> material) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = material['name'] ?? 'Material';
    final id = material['id'] as String;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        child: Container(
          width: 440,
          padding: AppSpacing.pagePadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.photo_camera_rounded, size: 20, color: scheme.primary),
                  SizedBox(width: 10.rs),
                  Expanded(child: Text('Upload Training Images — $name', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, size: 18)),
                ],
              ),
              SizedBox(height: AppSpacing.lg),
              Container(
                width: double.infinity,
                height: 150,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: AppRadius.card,
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_upload_rounded, size: 36, color: scheme.primary.withValues(alpha: 0.5)),
                    SizedBox(height: 10.rs),
                    Text('Select top-view images of loaded trucks', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(height: AppSpacing.xs),
                    Text('PNG, JPG (max 10MB each, multiple allowed)', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                    SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _pickTrainingImages(id, name);
                      },
                      icon: const Icon(Icons.folder_open_rounded, size: 16),
                      label: const Text('Browse Files'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 14.rs),
              Container(
                padding: EdgeInsets.all(10.rs),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                  borderRadius: AppRadius.button,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline_rounded, size: 14, color: Color(0xFFF59E0B)),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Upload 20+ varied images per material for best accuracy. All images go to a shared training server.',
                        style: text.labelSmall?.copyWith(color: scheme.onSurface),
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

class _MaterialRow extends StatelessWidget {
  final Map<String, dynamic> material;
  final int index;
  final ColorScheme scheme;
  final TextTheme text;
  final ValueChanged<bool> onToggle;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;
  final VoidCallback onRename;
  final VoidCallback onUploadImages;

  const _MaterialRow({
    super.key,
    required this.material,
    required this.index,
    required this.scheme,
    required this.text,
    required this.onToggle,
    required this.onSetDefault,
    required this.onDelete,
    required this.onRename,
    required this.onUploadImages,
  });

  @override
  Widget build(BuildContext context) {
    final isDefault = material['isDefault'] == true;
    final trainingCount = material['trainingImages'] as int? ?? 0;

    return SizedBox(
      height: 56,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.15))),
        ),
        child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Icon(Icons.drag_indicator_rounded, size: 16, color: scheme.outlineVariant),
            ),
          ),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Row(
              children: [
                GestureDetector(
                  onDoubleTap: onRename,
                  child: Text(material['name'] ?? '', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (isDefault) ...[
                  SizedBox(width: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4.rs),
                      border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Text('Default', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: scheme.primary)),
                  ),
                ],
              ],
            ),
          ),
          if (!isDefault)
            _actionChip(
              icon: Icons.star_outline_rounded,
              label: 'Default',
              color: scheme.tertiary,
              onTap: onSetDefault,
            )
          else
            const SizedBox(width: 0),
          SizedBox(width: 6.rs),
          _actionChip(
            icon: Icons.photo_camera_rounded,
            label: trainingCount > 0 ? '$trainingCount imgs' : 'Upload',
            color: trainingCount > 0 ? AppTheme.successColor : scheme.primary,
            onTap: onUploadImages,
          ),
          SizedBox(width: 6.rs),
          _actionChip(
            icon: Icons.edit_rounded,
            label: 'Rename',
            color: scheme.primary,
            onTap: onRename,
          ),
          SizedBox(width: 6.rs),
          _actionChip(
            icon: Icons.visibility_off_rounded,
            label: 'Hide',
            color: scheme.onSurfaceVariant,
            onTap: () => onToggle(false),
          ),
          SizedBox(width: 6.rs),
          _actionChip(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            color: scheme.error,
            onTap: onDelete,
          ),
        ],
        ),
      ),
    );
  }

  Widget _actionChip({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: AppRadius.chip,
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              SizedBox(width: AppSpacing.xs),
              Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final ColorScheme scheme;
  final TextTheme text;
  final Widget child;
  final Color? iconColor;

  const _SettingsCard({
    required this.icon,
    required this.title,
    this.trailing,
    required this.scheme,
    required this.text,
    required this.child,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? scheme.primary;
    return Container(
      width: double.infinity,
      padding: AppSpacing.pagePadding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.dialog,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7.rs),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              SizedBox(width: AppSpacing.md),
              Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              if (trailing != null) ...[
                const Spacer(),
                trailing!,
              ],
            ],
          ),
          SizedBox(height: 20.rs),
          child,
        ],
      ),
    );
  }
}
