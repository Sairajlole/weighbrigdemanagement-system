import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';
import 'package:weighbridgemanagement/shared/providers/camera_provider.dart';
import 'package:weighbridgemanagement/shared/providers/gate_provider.dart';
import 'package:weighbridgemanagement/shared/providers/scale_provider.dart';
import 'package:weighbridgemanagement/shared/services/gate_service.dart';
import 'package:weighbridgemanagement/shared/services/scale_service.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

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
          _StatusChip(
            icon: Icons.scale_outlined,
            label: scaleConnected ? 'Scale OK' : 'Scale Off',
            active: scaleConnected,
          ),
          SizedBox(width: 16.rs),
          // Gate status
          if (gatesEnabled) ...[
            _StatusChip(
              icon: Icons.sensor_door_outlined,
              label: 'Entry: ${_gateLabel(entryState)}',
              active: entryState == GateState.closed || entryState == GateState.open,
              warning: entryState == GateState.error,
            ),
            SizedBox(width: 12.rs),
            _StatusChip(
              icon: Icons.sensor_door_outlined,
              label: 'Exit: ${_gateLabel(exitState)}',
              active: exitState == GateState.closed || exitState == GateState.open,
              warning: exitState == GateState.error,
            ),
            SizedBox(width: 16.rs),
          ],
          // Camera count
          _StatusChip(
            icon: Icons.videocam_outlined,
            label: '${cameras.length} cam${cameras.length == 1 ? '' : 's'}',
            active: cameras.isNotEmpty,
          ),
          SizedBox(width: 16.rs),
          // AI sidecar
          _StatusChip(
            icon: Icons.memory_outlined,
            label: aiAvailable ? 'AI On' : 'AI Off',
            active: aiAvailable,
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
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool warning;

  const _StatusChip({required this.icon, required this.label, this.active = false, this.warning = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = warning ? scheme.onSurfaceVariant : (active ? scheme.onSurface : scheme.onSurfaceVariant.withValues(alpha: 0.4));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        SizedBox(width: 5.rs),
        Icon(icon, size: 12, color: color),
        SizedBox(width: 3.rs),
        Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
