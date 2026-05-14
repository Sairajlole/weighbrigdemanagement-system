import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';

final _materialsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final db = ref.watch(firestoreProvider);
  return db.collection('materials').orderBy('order').snapshots().map(
      (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

final _materialsSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestoreProvider);
  final doc = await db.collection('settings').doc('materials').get();
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

  Future<void> _saveAllowOther(bool value) async {
    setState(() => _allowOther = value);
    final db = ref.read(firestoreProvider);
    await db.collection('settings').doc('materials').set({
      'allowOther': value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _addMaterial() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);
    try {
      final db = ref.read(firestoreProvider);
      final materials = ref.read(_materialsProvider).valueOrNull ?? [];
      await db.collection('materials').add({
        'name': _toTitleCase(name),
        'active': true,
        'isDefault': materials.isEmpty,
        'order': materials.length,
        'trainingImages': 0,
        'aiEnabled': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _nameCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleActive(String id, bool active) async {
    final db = ref.read(firestoreProvider);
    await db.collection('materials').doc(id).update({'active': active});
  }

  Future<void> _setDefault(String id) async {
    final db = ref.read(firestoreProvider);
    final materials = ref.read(_materialsProvider).valueOrNull ?? [];
    final batch = db.batch();
    for (final m in materials) {
      batch.update(db.collection('materials').doc(m['id']), {'isDefault': m['id'] == id});
    }
    await batch.commit();
  }

  Future<void> _delete(String id) async {
    final db = ref.read(firestoreProvider);
    await db.collection('materials').doc(id).delete();
  }

  String _toTitleCase(String text) {
    return text.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final materialsAsync = ref.watch(_materialsProvider);
    final materials = materialsAsync.valueOrNull ?? [];
    ref.watch(_materialsSettingsProvider).whenData(_loadSettings);

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
                Icon(Icons.inventory_2_rounded, size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Materials Management', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Product list and categories', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quick Add
                  _Card(
                    scheme: scheme,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Quick Add Material', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _nameCtrl,
                                style: text.bodySmall,
                                decoration: const InputDecoration(
                                  hintText: 'e.g. Gitti, Reti, Coal, Iron Ore',
                                  labelText: 'Material Name',
                                  isDense: true,
                                ),
                                onSubmitted: (_) => _addMaterial(),
                              ),
                            ),
                            const SizedBox(width: 14),
                            FilledButton.icon(
                              onPressed: _saving ? null : _addMaterial,
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('Add Material'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Active Materials Table
                  _Card(
                    scheme: scheme,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Active Materials', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                              child: Text('${materials.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.primary)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (materials.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                children: [
                                  Icon(Icons.inventory_2_outlined, size: 40, color: scheme.outlineVariant),
                                  const SizedBox(height: 8),
                                  Text('No materials added yet', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          )
                        else
                          // Header row
                          ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(width: 32),
                                  Expanded(flex: 3, child: Text('MATERIAL NAME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.5))),
                                  SizedBox(width: 60, child: Text('DEFAULT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.5))),
                                  SizedBox(width: 60, child: Text('STATUS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.5))),
                                  SizedBox(width: 60, child: Text('AI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.5))),
                                  const SizedBox(width: 80),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            ...materials.map((m) => _MaterialRow(
                                  material: m,
                                  scheme: scheme,
                                  text: text,
                                  onToggle: (v) => _toggleActive(m['id'], v),
                                  onSetDefault: () => _setDefault(m['id']),
                                  onDelete: () => _delete(m['id']),
                                  onUploadImages: () => _showUploadDialog(m),
                                )),
                          ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Global Display Settings
                  _Card(
                    scheme: scheme,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Global Display Settings', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('Manage how materials appear to operators in the weighbridge interface', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Enable 'Other' Material Option", style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                                  Text("Allow operators to manually type a material if it's not in the list", style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            Switch(value: _allowOther, onChanged: _saveAllowOther),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // AI Training Info
                  _Card(
                    scheme: scheme,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('AI', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF059669))),
                            ),
                            const SizedBox(width: 10),
                            Text('Material Recognition Training', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 16, color: scheme.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Upload top-view images of materials for AI training. Images are sent to the backend team for model training. Once trained, automatic material recognition will be available for that material.',
                                  style: text.bodySmall?.copyWith(color: scheme.onSurface),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.photo_library_outlined, size: 14, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(
                              'Click the camera icon on any material row to upload training images',
                              style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTrainingImages(String materialId) async {
    final result = await Process.run('osascript', [
      '-e',
      'set theFiles to choose file of type {"public.image"} with prompt "Select Training Images" with multiple selections allowed',
      '-e',
      'set posixPaths to ""',
      '-e',
      'repeat with f in theFiles',
      '-e',
      'set posixPaths to posixPaths & POSIX path of f & linefeed',
      '-e',
      'end repeat',
      '-e',
      'posixPaths',
    ]);
    final output = (result.stdout as String).trim();
    if (output.isEmpty) return;

    final paths = output.split('\n').where((p) => p.isNotEmpty).toList();
    if (paths.isEmpty) return;

    final db = ref.read(firestoreProvider);
    var uploaded = 0;

    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      if (file.lengthSync() > 10 * 1024 * 1024) continue;

      final bytes = file.readAsBytesSync();
      final ext = path.split('.').last.toLowerCase();
      final b64 = base64Encode(bytes);
      final fileName = path.split('/').last;

      await db.collection('materials').doc(materialId).collection('training_images').add({
        'data': 'data:image/$ext;base64,$b64',
        'fileName': fileName,
        'uploadedAt': FieldValue.serverTimestamp(),
      });
      uploaded++;
    }

    if (uploaded > 0) {
      await db.collection('materials').doc(materialId).update({
        'trainingImages': FieldValue.increment(uploaded),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$uploaded image${uploaded > 1 ? 's' : ''} uploaded for training')),
        );
      }
    }
  }

  void _showUploadDialog(Map<String, dynamic> material) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = material['name'] ?? 'Material';
    final images = (material['trainingImages'] as num?) ?? 0;
    final id = material['id'] as String;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.photo_camera_rounded, size: 20, color: scheme.primary),
                  const SizedBox(width: 10),
                  Text('Upload Training Images', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, size: 18)),
                ],
              ),
              const SizedBox(height: 8),
              Text('Material: $name', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              Text('Current images: $images', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                height: 160,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_upload_rounded, size: 36, color: scheme.primary.withValues(alpha: 0.5)),
                    const SizedBox(height: 10),
                    Text('Select top-view images', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('PNG, JPG (max 10MB each, multiple allowed)', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _pickTrainingImages(id);
                      },
                      icon: const Icon(Icons.folder_open_rounded, size: 16),
                      label: const Text('Browse Files'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline_rounded, size: 14, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Upload 20+ varied images for best recognition accuracy. Include different lighting and load levels.',
                        style: text.labelSmall?.copyWith(color: scheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
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
  final ColorScheme scheme;
  final TextTheme text;
  final ValueChanged<bool> onToggle;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;
  final VoidCallback onUploadImages;

  const _MaterialRow({
    required this.material,
    required this.scheme,
    required this.text,
    required this.onToggle,
    required this.onSetDefault,
    required this.onDelete,
    required this.onUploadImages,
  });

  @override
  Widget build(BuildContext context) {
    final active = material['active'] == true;
    final isDefault = material['isDefault'] == true;
    final aiEnabled = material['aiEnabled'] == true;
    final trainingImages = (material['trainingImages'] as num?) ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.15))),
      ),
      child: Row(
        children: [
          Icon(Icons.drag_indicator_rounded, size: 16, color: scheme.outlineVariant),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(material['name'] ?? '', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            width: 60,
            child: GestureDetector(
              onTap: isDefault ? null : onSetDefault,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDefault ? scheme.primary : Colors.transparent,
                  border: Border.all(color: isDefault ? scheme.primary : scheme.outline, width: isDefault ? 5 : 1.5),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Switch(value: active, onChanged: onToggle, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ),
          SizedBox(
            width: 60,
            child: aiEnabled
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFF059669).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                    child: const Text('Active', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF059669))),
                  )
                : Text('$trainingImages img', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          ),
          SizedBox(
            width: 80,
            child: Row(
              children: [
                IconButton(
                  onPressed: onUploadImages,
                  icon: Icon(Icons.photo_camera_rounded, size: 16, color: scheme.primary),
                  tooltip: 'Upload training images',
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline_rounded, size: 16, color: scheme.error),
                  tooltip: 'Delete',
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final ColorScheme scheme;
  final Widget child;

  const _Card({required this.scheme, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }
}
