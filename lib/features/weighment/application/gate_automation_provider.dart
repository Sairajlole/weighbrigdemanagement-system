import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/gate_provider.dart';
import 'package:weighbridgemanagement/shared/providers/scale_provider.dart';
import 'package:weighbridgemanagement/shared/services/app_notifier.dart';
import 'package:weighbridgemanagement/shared/services/gate_service.dart';

const _weightThreshold = 500.0;

class GateAutomationService {
  final GateService _gateService;
  final GateSystemConfig _config;
  final FirestorePaths _paths;

  GateAutomationService(this._gateService, this._config, this._paths);

  bool get isEnabled => _config.systemEnabled;

  Future<void> onWeightDetected(double weight) async {
    if (!isEnabled) return;
    if (!_config.entry.enabled) return;
    if (_config.entry.trigger != 'Weight Detected') return;

    if (weight >= _weightThreshold) {
      final result = await _gateService.closeGate(GateId.entry);
      logGateEvent(
        gateId: 'entry',
        action: 'auto_close',
        success: result.success,
        message: 'Weight detected: ${weight.toStringAsFixed(0)}kg',
      );
    }
  }

  Future<void> onFirstWeightCaptured({String? vehicleNumber}) async {
    if (!isEnabled) return;
    // Close entry gate after first weight captured (vehicle is committed)
    if (_config.entry.enabled) {
      final result = await _gateService.closeGate(GateId.entry);
      logGateEvent(
        gateId: 'entry',
        action: 'auto_close',
        success: result.success,
        message: 'First weight captured',
        vehicleNumber: vehicleNumber,
      );
    }
  }

  Future<void> onWeighmentComplete({String? vehicleNumber, String? weighmentId}) async {
    if (!isEnabled) return;
    if (!_config.exit.enabled) return;

    final trigger = _config.exit.trigger;
    if (trigger != 'Weighment Complete' && trigger != 'Print Complete') return;
    if (trigger == 'Weighment Complete') {
      await _openExitGate(vehicleNumber: vehicleNumber, weighmentId: weighmentId);
    }
  }

  Future<void> onPrintComplete({String? vehicleNumber, String? weighmentId}) async {
    if (!isEnabled) return;
    if (!_config.exit.enabled) return;
    if (_config.exit.trigger != 'Print Complete') return;

    await _openExitGate(vehicleNumber: vehicleNumber, weighmentId: weighmentId);
  }

  Future<void> _openExitGate({String? vehicleNumber, String? weighmentId}) async {
    final result = await _gateService.openGate(GateId.exit);
    logGateEvent(
      gateId: 'exit',
      action: 'open',
      success: result.success,
      message: 'Weighment complete - auto open',
      vehicleNumber: vehicleNumber,
      weighmentId: weighmentId,
    );
    // Interlock trip: the gate couldn't open because the other gate was open.
    // Throttled heavily — it's the safety system working, surfaced for awareness.
    if (!result.success && result.message.toLowerCase().contains('interlock')) {
      AppNotifier.raise(
        _paths,
        category: 'security',
        severity: 'warn',
        link: '/settings/gate-control',
        title: 'Gate interlock blocked an open',
        body: "The exit gate couldn't open because the other gate was still open (interlock). Vehicles may be waiting — check the gates.",
        throttleKey: 'gate-interlock',
        throttle: const Duration(hours: 1),
      );
    }
  }
}

final gateAutomationProvider = Provider<GateAutomationService>((ref) {
  final gateService = ref.watch(gateServiceProvider);
  final config = ref.watch(gateConfigProvider).valueOrNull ?? const GateSystemConfig();
  final paths = ref.watch(firestorePathsProvider);
  return GateAutomationService(gateService, config, paths);
});

// Auto-trigger: monitors scale readings for weight detection
final gateWeightTriggerProvider = Provider<void>((ref) {
  final config = ref.watch(gateConfigProvider).valueOrNull;
  if (config == null || !config.systemEnabled) return;
  if (!config.entry.enabled) return;
  if (config.entry.trigger != 'Weight Detected') return;

  final automation = ref.watch(gateAutomationProvider);
  double lastWeight = 0;

  ref.listen(scaleReadingProvider, (prev, next) {
    final reading = next.valueOrNull;
    if (reading == null) return;
    if (lastWeight < _weightThreshold && reading.weight >= _weightThreshold) {
      automation.onWeightDetected(reading.weight);
    }
    lastWeight = reading.weight;
  });
});
