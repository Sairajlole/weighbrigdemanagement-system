import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/gate_provider.dart';
import 'package:weighbridgemanagement/shared/providers/integrations_provider.dart';
import 'package:weighbridgemanagement/shared/providers/scale_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/services/gate_service.dart';
import 'package:weighbridgemanagement/shared/services/scale_service.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

final _weighbridgeListProvider = FutureProvider<List<_WbEntry>>((ref) async {
  final ctx = ref.watch(siteContextProvider);
  if (ctx.companyId.isEmpty) return [];
  final db = FirebaseFirestore.instance;
  final sitesSnap = await db.collection('companies/${ctx.companyId}/sites').get();
  final list = <_WbEntry>[];
  for (final site in sitesSnap.docs) {
    final siteName = site.data()['name'] as String? ?? 'Unnamed Site';
    final wbSnap = await db.collection('companies/${ctx.companyId}/sites/${site.id}/weighbridges').get();
    for (final wb in wbSnap.docs) {
      list.add(_WbEntry(siteId: site.id, siteName: siteName, wbId: wb.id, wbName: wb.data()['name'] as String? ?? 'Unnamed WB'));
    }
  }
  return list;
});

class _WbEntry {
  final String siteId;
  final String siteName;
  final String wbId;
  final String wbName;
  const _WbEntry({required this.siteId, required this.siteName, required this.wbId, required this.wbName});
}

class DeviceContextBar extends ConsumerWidget {
  const DeviceContextBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final ctx = ref.watch(siteContextProvider);
    final wbListAsync = ref.watch(_weighbridgeListProvider);
    final allWbs = wbListAsync.valueOrNull ?? [];
    final current = allWbs.where((w) => w.siteId == ctx.siteId && w.wbId == ctx.weighbridgeId).firstOrNull;

    final scaleStatus = ref.watch(scaleStatusProvider).valueOrNull ?? ScaleConnectionStatus.disconnected;
    final scaleReading = ref.watch(scaleReadingProvider).valueOrNull;
    final gateStates = ref.watch(gateStateProvider).valueOrNull ?? {};
    final gateConfig = ref.watch(gateConfigProvider).valueOrNull;
    final displayBoard = ref.watch(displayBoardServiceProvider);

    final scaleConnected = scaleStatus == ScaleConnectionStatus.connected;
    final scaleStable = scaleReading?.stable ?? false;
    final gatesEnabled = gateConfig?.systemEnabled ?? false;
    final entryState = gateStates[GateId.entry] ?? GateState.unknown;
    final exitState = gateStates[GateId.exit] ?? GateState.unknown;
    final gateError = entryState == GateState.error || exitState == GateState.error;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.15))),
      ),
      child: Row(
        children: [
          _WbChip(
            current: current,
            allWbs: allWbs,
            scheme: scheme,
            onSelected: (wb) async {
              await ref.read(siteContextProvider.notifier).configure(
                companyId: ctx.companyId,
                siteId: wb.siteId,
                weighbridgeId: wb.wbId,
              );
              ref.invalidate(firestorePathsProvider);
              ref.invalidate(_weighbridgeListProvider);
            },
          ),

          const SizedBox(width: 16),
          Container(width: 1, height: 20, color: scheme.outlineVariant.withValues(alpha: 0.3)),
          const SizedBox(width: 16),

          _DeviceChip(
            icon: Icons.scale_rounded,
            label: scaleConnected ? (scaleStable ? 'Stable' : 'Unstable') : 'Disconnected',
            color: scaleConnected
                ? (scaleStable ? Colors.green : Colors.orange)
                : Colors.red,
            isError: !scaleConnected,
            tooltip: !scaleConnected ? 'Scale disconnected — check serial port connection' : null,
            onTap: () => context.go('/settings/weighbridge'),
          ),

          const SizedBox(width: 12),

          if (gatesEnabled) ...[
            _DeviceChip(
              icon: Icons.sensor_door_rounded,
              label: 'In:${_gateShort(entryState)} Out:${_gateShort(exitState)}',
              color: _gateColor(entryState, exitState),
              isError: gateError,
              tooltip: gateError ? 'Gate hardware error — check connections' : null,
              onTap: () => context.go('/settings/gate-control'),
            ),
            const SizedBox(width: 12),
          ],

          _DeviceChip(
            icon: Icons.tv_rounded,
            label: displayBoard.hasConnectedBoards ? 'Display OK' : 'Display Off',
            color: displayBoard.hasConnectedBoards ? Colors.green : scheme.onSurfaceVariant.withValues(alpha: 0.4),
            onTap: () => context.go('/settings/integrations'),
          ),

          const Spacer(),
        ],
      ),
    );
  }

  String _gateShort(GateState state) {
    return switch (state) {
      GateState.closed => 'C',
      GateState.open => 'O',
      GateState.opening => '..O',
      GateState.closing => '..C',
      GateState.error => 'E',
      GateState.unknown => '-',
    };
  }

  Color _gateColor(GateState entry, GateState exit) {
    if (entry == GateState.error || exit == GateState.error) return Colors.red;
    if (entry == GateState.open || exit == GateState.open) return Colors.orange;
    return Colors.green;
  }
}

class _DeviceChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isError;
  final String? tooltip;
  final VoidCallback? onTap;

  const _DeviceChip({required this.icon, required this.label, required this.color, this.isError = false, this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    final chip = GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isError ? Colors.red.withValues(alpha: 0.12) : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isError ? Colors.red.withValues(alpha: 0.5) : color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
              const SizedBox(width: 5),
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: chip);
    }
    return chip;
  }
}

class _WbChip extends StatelessWidget {
  final _WbEntry? current;
  final List<_WbEntry> allWbs;
  final ColorScheme scheme;
  final void Function(_WbEntry) onSelected;

  const _WbChip({required this.current, required this.allWbs, required this.scheme, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    if (allWbs.length <= 1) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.scale_rounded, size: 14, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            current != null ? '${current!.siteName} / ${current!.wbName}' : 'Weighbridge',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.primary),
          ),
        ],
      );
    }

    return PopupMenuButton<_WbEntry>(
      tooltip: 'Switch weighbridge',
      offset: const Offset(0, 36),
      onSelected: onSelected,
      itemBuilder: (_) => allWbs.map((wb) => PopupMenuItem(
        value: wb,
        enabled: !(wb.siteId == current?.siteId && wb.wbId == current?.wbId),
        child: Text('${wb.siteName} / ${wb.wbName}', style: const TextStyle(fontSize: 12)),
      )).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.scale_rounded, size: 12, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              current != null ? '${current!.siteName} / ${current!.wbName}' : 'Select',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.primary),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}
