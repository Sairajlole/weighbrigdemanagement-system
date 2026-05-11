import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/core/enums/weighment_enums.dart';
import 'package:weighbridgemanagement/core/models/camera_config.dart';
import 'package:weighbridgemanagement/core/providers/providers.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class CamerasAiScreen extends ConsumerStatefulWidget {
  const CamerasAiScreen({super.key});

  @override
  ConsumerState<CamerasAiScreen> createState() => _CamerasAiScreenState();
}

class _CamerasAiScreenState extends ConsumerState<CamerasAiScreen> {
  double confidenceThreshold = 0.85;
  double materialThreshold = 0.80;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final camerasAsync = ref.watch(camerasStreamProvider);

    return MainLayout(
      activeNav: "Settings",
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(Icons.videocam_outlined, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Cameras & AI Configuration",
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text("Manage camera feeds and AI detection settings",
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _showAddCameraDialog(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text("Add Camera"),
                ),
              ],
            ),
          ),

          // Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Camera Grid
                  Text("CAMERA FEEDS",
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),

                  camerasAsync.when(
                    data: (cameras) => cameras.isEmpty
                        ? _emptyState(colorScheme)
                        : _cameraGrid(cameras, colorScheme),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (_, __) => _emptyState(colorScheme),
                  ),

                  const SizedBox(height: 32),

                  // AI Settings Section
                  Text("AI DETECTION SETTINGS",
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _aiCard(
                        colorScheme: colorScheme,
                        icon: Icons.document_scanner_outlined,
                        title: "License Plate Recognition",
                        subtitle: "YOLO + OCR pipeline",
                        children: [
                          _sliderRow("Confidence Threshold", confidenceThreshold, colorScheme,
                              (v) => setState(() => confidenceThreshold = v)),
                          const SizedBox(height: 8),
                          Text("Plates below this confidence will prompt manual entry.",
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                        ],
                      )),
                      const SizedBox(width: 16),
                      Expanded(child: _aiCard(
                        colorScheme: colorScheme,
                        icon: Icons.inventory_2_outlined,
                        title: "Material Detection",
                        subtitle: "YOLO classification model",
                        children: [
                          _sliderRow("Confidence Threshold", materialThreshold, colorScheme,
                              (v) => setState(() => materialThreshold = v)),
                          const SizedBox(height: 8),
                          Text("Materials below this confidence will prompt manual entry.",
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                        ],
                      )),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _aiCard(
                        colorScheme: colorScheme,
                        icon: Icons.person_outline,
                        title: "Person Detection",
                        subtitle: "Platform safety check",
                        children: [
                          Text("Counts persons on platform. Expected: 1 (driver only).",
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 8),
                          Text("Multi-camera fusion from all platform cameras.",
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                        ],
                      )),
                      const SizedBox(width: 16),
                      Expanded(child: _aiCard(
                        colorScheme: colorScheme,
                        icon: Icons.crop_free,
                        title: "Vehicle Boundary Check",
                        subtitle: "Platform coverage analysis",
                        children: [
                          Text("Verifies vehicle is fully within weighbridge platform boundaries.",
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 8),
                          Text("Uses top and side cameras for boundary estimation.",
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                        ],
                      )),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // YOLO Server Status
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.dns_outlined, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("YOLO Inference Server", style: TextStyle(fontWeight: FontWeight.w600)),
                              Text("http://localhost:8420", style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text("OFFLINE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: colorScheme.error)),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () {},
                          child: const Text("Test Connection"),
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

  Widget _emptyState(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.videocam_off_outlined, size: 48, color: colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Text("No cameras configured", style: TextStyle(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => _showAddCameraDialog(context),
            icon: const Icon(Icons.add, size: 16),
            label: const Text("Add First Camera"),
          ),
        ],
      ),
    );
  }

  Widget _cameraGrid(List<CameraConfig> cameras, ColorScheme colorScheme) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.4,
      ),
      itemCount: cameras.length,
      itemBuilder: (context, index) {
        final cam = cameras[index];
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              // Camera preview area
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1a1a2e),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Icon(Icons.videocam, size: 28, color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cam.enabled ? Colors.green.withValues(alpha: 0.8) : Colors.red.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            cam.enabled ? "ON" : "OFF",
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            cam.sourceType.name.toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontSize: 9),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Camera info
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cam.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          Text(cam.purpose.name, style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      onSelected: (action) {
                        if (action == 'edit') _showEditCameraDialog(context, cam);
                        if (action == 'delete') _deleteCamera(cam);
                        if (action == 'toggle') _toggleCamera(cam);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'edit', child: Text(cam.enabled ? 'Edit' : 'Edit')),
                        PopupMenuItem(value: 'toggle', child: Text(cam.enabled ? 'Disable' : 'Enable')),
                        const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _aiCard({
    required ColorScheme colorScheme,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(subtitle, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _sliderRow(String label, double value, ColorScheme colorScheme, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
            Text("${(value * 100).toInt()}%", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.primary)),
          ],
        ),
        Slider(value: value, min: 0.5, max: 1.0, onChanged: onChanged),
      ],
    );
  }

  void _showAddCameraDialog(BuildContext context) {
    _showCameraFormDialog(context, null);
  }

  void _showEditCameraDialog(BuildContext context, CameraConfig camera) {
    _showCameraFormDialog(context, camera);
  }

  void _showCameraFormDialog(BuildContext context, CameraConfig? existing) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final urlCtrl = TextEditingController(text: existing?.streamUrl ?? '');
    var purpose = existing?.purpose ?? CameraPurpose.platformTopView;
    var sourceType = existing?.sourceType ?? CameraSourceType.rtsp;
    var showOnWeighment = existing?.showOnWeighmentScreen ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing == null ? "Add Camera" : "Edit Camera"),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: "Camera Name", hintText: "e.g. Front Gate"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlCtrl,
                  decoration: InputDecoration(
                    labelText: "Stream URL",
                    hintText: sourceType == CameraSourceType.usb ? "/dev/video0" : "rtsp://192.168.1.x/stream",
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<CameraSourceType>(
                  value: sourceType,
                  decoration: const InputDecoration(labelText: "Source Type"),
                  items: CameraSourceType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.name.toUpperCase())))
                      .toList(),
                  onChanged: (v) => setDialogState(() => sourceType = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<CameraPurpose>(
                  value: purpose,
                  decoration: const InputDecoration(labelText: "Purpose"),
                  items: CameraPurpose.values
                      .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => purpose = v!),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text("Show on Weighment Screen", style: TextStyle(fontSize: 13)),
                  value: showOnWeighment,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setDialogState(() => showOnWeighment = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final fs = ref.read(firestoreServiceProvider);
                if (existing == null) {
                  await fs.createCamera(CameraConfig(
                    id: '',
                    name: nameCtrl.text.trim(),
                    purpose: purpose,
                    sourceType: sourceType,
                    streamUrl: urlCtrl.text.trim(),
                    showOnWeighmentScreen: showOnWeighment,
                    gridOrder: 99,
                  ));
                } else {
                  await fs.updateCamera(existing.id, {
                    'name': nameCtrl.text.trim(),
                    'purpose': purpose.name,
                    'sourceType': sourceType.name,
                    'streamUrl': urlCtrl.text.trim(),
                    'showOnWeighmentScreen': showOnWeighment,
                  });
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(existing == null ? "Add" : "Save"),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteCamera(CameraConfig cam) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Camera?"),
        content: Text("Remove '${cam.name}' from configuration?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          FilledButton(
            onPressed: () {
              ref.read(firestoreServiceProvider).deleteCamera(cam.id);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  void _toggleCamera(CameraConfig cam) {
    ref.read(firestoreServiceProvider).updateCamera(cam.id, {'enabled': !cam.enabled});
  }
}
