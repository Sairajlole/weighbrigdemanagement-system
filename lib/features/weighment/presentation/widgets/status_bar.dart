import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';
import 'package:weighbridgemanagement/shared/providers/camera_provider.dart';
import 'package:weighbridgemanagement/shared/providers/gate_provider.dart';
import 'package:weighbridgemanagement/shared/providers/scale_provider.dart';
import 'package:weighbridgemanagement/shared/services/gate_service.dart';
import 'package:weighbridgemanagement/shared/services/scale_service.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/connection_badge.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

class WeighmentStatusBar extends ConsumerWidget {
  const WeighmentStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scaleStatus = ref.watch(scaleStatusProvider).valueOrNull ?? ScaleConnectionStatus.disconnected;
    final gateStates = ref.watch(gateStateProvider).valueOrNull ?? {};
    final cameras = ref.watch(activeWeighbridgeCamerasProvider).valueOrNull ?? [];
    final gateConfig = ref.watch(gateConfigProvider).valueOrNull;
    final aiAvailable = ref.watch(aiAvailableProvider).valueOrNull ?? false;
    final scheme = Theme.of(context).colorScheme;

    final scaleConnected = scaleStatus == ScaleConnectionStatus.connected;
    final gatesEnabled = gateConfig?.systemEnabled ?? false;
    final entryState = gateStates[GateId.entry] ?? GateState.unknown;
    final exitState = gateStates[GateId.exit] ?? GateState.unknown;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          // Scale status
          ConnectionBadge(
            status: scaleConnected ? ConnectionStatus.connected : ConnectionStatus.disconnected,
            label: 'Scale',
            detail: scaleConnected ? 'OK' : 'Off',
          ),
          SizedBox(width: AppSpacing.lg),
          // Gate status
          if (gatesEnabled) ...[
            ConnectionBadge(
              status: _gateConnectionStatus(entryState),
              label: 'Entry',
              detail: _gateLabel(entryState),
            ),
            SizedBox(width: AppSpacing.md),
            ConnectionBadge(
              status: _gateConnectionStatus(exitState),
              label: 'Exit',
              detail: _gateLabel(exitState),
            ),
            SizedBox(width: AppSpacing.lg),
          ],
          // Camera count
          ConnectionBadge(
            status: cameras.isNotEmpty ? ConnectionStatus.connected : ConnectionStatus.disconnected,
            label: 'Cameras',
            detail: '${cameras.length}',
          ),
          SizedBox(width: AppSpacing.lg),
          // AI sidecar
          ConnectionBadge(
            status: aiAvailable ? ConnectionStatus.connected : ConnectionStatus.disconnected,
            label: 'AI',
            detail: aiAvailable ? 'On' : 'Off',
          ),
          const Spacer(),
          // Keyboard shortcuts hint
          Text(
            'F2 New · F5 Capture · F4 Print · Esc Cancel',
            style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }

  String _gateLabel(GateState state) {
    return switch (state) {
      GateState.closed => 'Closed',
      GateState.open => 'Open',
      GateState.opening => 'Opening',
      GateState.closing => 'Closing',
      GateState.error => 'Error',
      GateState.unknown => '—',
    };
  }

  ConnectionStatus _gateConnectionStatus(GateState state) {
    return switch (state) {
      GateState.closed || GateState.open => ConnectionStatus.connected,
      GateState.opening || GateState.closing => ConnectionStatus.connecting,
      GateState.error => ConnectionStatus.error,
      GateState.unknown => ConnectionStatus.disconnected,
    };
  }
}

