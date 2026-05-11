import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/core/enums/weighment_enums.dart';
import 'package:weighbridgemanagement/core/models/camera_config.dart';
import 'package:weighbridgemanagement/core/models/weighment_session.dart';
import 'package:weighbridgemanagement/core/providers/providers.dart';
import 'package:weighbridgemanagement/core/services/weighment_engine.dart';

class WeighmentLiveScreen extends ConsumerStatefulWidget {
  const WeighmentLiveScreen({super.key});

  @override
  ConsumerState<WeighmentLiveScreen> createState() => _WeighmentLiveScreenState();
}

class _WeighmentLiveScreenState extends ConsumerState<WeighmentLiveScreen> {
  final TextEditingController _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final engineState = ref.read(weighmentEngineProvider);
      if (!engineState.isRunning) {
        ref.read(weighmentEngineProvider.notifier).startWeighment();
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engineState = ref.watch(weighmentEngineProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final session = engineState.session;

    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Navigate to complete screen when done
    if (session.status == WeighmentStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/weighmentComplete');
      });
    }

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: Row(
        children: [
          // LEFT: CCTV Grid (70% width)
          Expanded(
            flex: 7,
            child: Column(
              children: [
                // Top bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => _showCancelDialog(context),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Weighment in Progress",
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: _getProgress(engineState),
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "${(_getProgress(engineState) * 100).toInt()}%",
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onPrimaryContainer,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (session.rstNumber != null) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "RST #${session.rstNumber}",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSecondaryContainer,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // CCTV Grid
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _buildCctvGrid(colorScheme),
                  ),
                ),
              ],
            ),
          ),

          // RIGHT: Data Panel + Steps (30% width)
          Container(
            width: 360,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(left: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: Column(
              children: [
                // Live Weight Display
                _buildWeightDisplay(session, colorScheme),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Detected Data
                        _buildDetectedData(session, colorScheme),
                        const SizedBox(height: 20),

                        // Manual Input (when needed)
                        if (engineState.pendingInputField != null)
                          _buildManualInput(engineState, colorScheme),

                        if (engineState.pendingInputField != null) const SizedBox(height: 20),

                        // Step Progress
                        _buildStepProgress(engineState.steps, colorScheme),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _getProgress(EngineState state) {
    if (state.steps.isEmpty) return 0;
    final completed = state.steps.where((s) =>
        s.status == StepStatus.completed || s.status == StepStatus.skipped).length;
    return completed / state.steps.length;
  }

  Widget _buildCctvGrid(ColorScheme colorScheme) {
    final camerasAsync = ref.watch(camerasStreamProvider);
    final cameras = camerasAsync.when(
      data: (list) => list.where((c) => c.enabled && c.showOnWeighmentScreen).toList(),
      loading: () => CameraConfig.defaults(),
      error: (_, __) => CameraConfig.defaults(),
    );

    final crossAxisCount = cameras.length <= 2 ? 1 : 2;

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 16 / 9,
      ),
      itemCount: cameras.length,
      itemBuilder: (context, index) {
        final cam = cameras[index];
        final purposeIcon = switch (cam.purpose) {
          CameraPurpose.vehicleNumberPlate => Icons.directions_car,
          CameraPurpose.driverFace || CameraPurpose.customerFace || CameraPurpose.operatorFace => Icons.face,
          CameraPurpose.platformTopView => Icons.videocam,
          _ => Icons.videocam_outlined,
        };

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a2e),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(purposeIcon, size: 32, color: Colors.white.withValues(alpha: 0.3)),
                    const SizedBox(height: 8),
                    Text(
                      cam.streamUrl.isEmpty ? "No stream configured" : cam.streamUrl,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: cam.streamUrl.isEmpty ? Colors.amber : Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(cam.name, style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    cam.sourceType.name.toUpperCase(),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 9, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWeightDisplay(WeighmentSession session, ColorScheme colorScheme) {
    final isTare = session.grossWeight != null && session.tareWeight != null;
    final displayWeight = session.tareWeight ?? session.grossWeight;
    final weightLabel = isTare ? "TARE WEIGHT" : (session.grossWeight != null ? "GROSS WEIGHT" : "LIVE WEIGHT");

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        children: [
          Text(
            weightLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            displayWeight != null
                ? "${displayWeight.toStringAsFixed(0)} kg"
                : "-- kg",
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          if (session.weightStabilized)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                "STABLE",
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onPrimary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          if (isTare) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _weightPill("Gross", session.grossWeight!, colorScheme),
                const SizedBox(width: 8),
                Text("-", style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                _weightPill("Tare", session.tareWeight!, colorScheme),
                const SizedBox(width: 8),
                Text("=", style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "${session.netWeight?.toStringAsFixed(0) ?? '--'} kg",
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colorScheme.onPrimary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _weightPill(String label, double weight, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        "$label: ${weight.toStringAsFixed(0)}",
        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildDetectedData(WeighmentSession session, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "DETECTED DATA",
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        _dataRow("Vehicle", session.vehicleNumber, colorScheme),
        _dataRow("Material", session.material, colorScheme),
        _dataRow("Customer", session.customerName, colorScheme),
        _dataRow("Phone", session.customerPhone, colorScheme),
        _dataRow("Persons on platform", session.facesDetected > 0 ? "${session.facesDetected}" : null, colorScheme),
      ],
    );
  }

  Widget _dataRow(String label, String? value, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value ?? "--",
              style: TextStyle(
                fontSize: 13,
                fontWeight: value != null ? FontWeight.w600 : FontWeight.w400,
                color: value != null ? colorScheme.onSurface : colorScheme.outlineVariant,
              ),
            ),
          ),
          if (value != null)
            Icon(Icons.check_circle, size: 14, color: colorScheme.primary),
        ],
      ),
    );
  }

  Widget _buildManualInput(EngineState engineState, ColorScheme colorScheme) {
    final currentStep = engineState.currentStep;
    final field = engineState.pendingInputField!;
    final isOverride = field == 'override';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isOverride
            ? colorScheme.errorContainer.withValues(alpha: 0.3)
            : colorScheme.tertiaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOverride
              ? colorScheme.error.withValues(alpha: 0.3)
              : colorScheme.tertiary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isOverride ? Icons.warning_amber : Icons.edit_note,
                size: 18,
                color: isOverride ? colorScheme.error : colorScheme.tertiary,
              ),
              const SizedBox(width: 8),
              Text(
                isOverride ? "Attention Required" : "Input Required",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: isOverride ? colorScheme.error : colorScheme.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            currentStep?.message ?? "Please provide input",
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (isOverride)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  ref.read(weighmentEngineProvider.notifier).provideInput('override', 'approved');
                },
                icon: const Icon(Icons.check, size: 16),
                label: const Text("Override & Continue", style: TextStyle(fontSize: 12)),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _inputController,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: _getHintForField(field),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onSubmitted: (_) => _submitInput(field),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 40,
                  child: FilledButton(
                    onPressed: () => _submitInput(field),
                    child: const Text("OK", style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _submitInput(String field) {
    if (_inputController.text.trim().isEmpty) return;
    ref.read(weighmentEngineProvider.notifier).provideInput(field, _inputController.text.trim());
    _inputController.clear();
  }

  String _getHintForField(String field) {
    switch (field) {
      case 'vehicleNumber':
        return 'e.g. KA-01-HH-1234';
      case 'material':
        return 'e.g. Sand, Cement, Steel';
      case 'customerPhone':
        return '10-digit phone number';
      case 'customerName':
        return 'Customer name';
      default:
        return 'Enter value';
    }
  }

  Widget _buildStepProgress(List<WeighmentStepState> steps, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "PROCESS STATUS",
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        ...steps.map((s) => _stepRow(s, colorScheme)),
      ],
    );
  }

  Widget _stepRow(WeighmentStepState s, ColorScheme colorScheme) {
    final (IconData icon, Color iconColor) = switch (s.status) {
      StepStatus.completed => (Icons.check_circle, colorScheme.primary),
      StepStatus.running => (Icons.radio_button_checked, colorScheme.tertiary),
      StepStatus.needsInput => (Icons.edit, colorScheme.tertiary),
      StepStatus.failed => (Icons.error, colorScheme.error),
      StepStatus.skipped => (Icons.skip_next, colorScheme.outlineVariant),
      StepStatus.waiting => (Icons.circle_outlined, colorScheme.outlineVariant),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _stepLabel(s.step),
              style: TextStyle(
                fontSize: 11,
                color: s.status == StepStatus.waiting
                    ? colorScheme.outlineVariant
                    : colorScheme.onSurface,
                fontWeight: s.status == StepStatus.running || s.status == StepStatus.needsInput
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _stepLabel(WeighmentStep step) {
    switch (step) {
      case WeighmentStep.retryQueue:
        return 'Queue Check';
      case WeighmentStep.operatorVerification:
        return 'Operator Verified';
      case WeighmentStep.rfidDetection:
        return 'RFID Scan';
      case WeighmentStep.weightCheckBeforeEntry:
        return 'Scale Zero Check';
      case WeighmentStep.vehicleEntry:
        return 'Vehicle Entry';
      case WeighmentStep.stabilization:
        return 'Weight Stabilization';
      case WeighmentStep.cctvDetection:
        return 'Number Plate (AI)';
      case WeighmentStep.driverAssist:
        return 'Driver Verification (AI)';
      case WeighmentStep.materialRecognition:
        return 'Material Detection (AI)';
      case WeighmentStep.customerVerification:
        return 'Customer ID';
      case WeighmentStep.rstManagement:
        return 'RST Assignment';
      case WeighmentStep.saveWeighment:
        return 'Save Record';
      case WeighmentStep.pdfGeneration:
        return 'PDF Generation';
      case WeighmentStep.printing:
        return 'Print Receipt';
      case WeighmentStep.stickerPrint:
        return 'Sticker Print';
      case WeighmentStep.googleSheetsSync:
        return 'Sheets Sync';
      case WeighmentStep.whatsapp:
        return 'WhatsApp Notify';
      case WeighmentStep.billingSync:
        return 'Billing Sync';
      case WeighmentStep.exitSequence:
        return 'Exit Gate';
    }
  }

  void _showCancelDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Cancel Weighment?"),
        content: const Text("This will abort the current weighment session."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Continue")),
          FilledButton(
            onPressed: () {
              ref.read(weighmentEngineProvider.notifier).cancelWeighment();
              Navigator.pop(ctx);
              Navigator.pushReplacementNamed(context, '/dashboard');
            },
            child: const Text("Cancel Weighment"),
          ),
        ],
      ),
    );
  }
}
