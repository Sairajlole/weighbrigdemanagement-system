import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';
import 'package:weighbridgemanagement/shared/services/ai_sidecar_client.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/gate_provider.dart';
import 'package:weighbridgemanagement/shared/providers/integrations_provider.dart';
import 'package:weighbridgemanagement/shared/providers/scale_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/services/gate_service.dart';
import 'package:weighbridgemanagement/shared/services/scale_service.dart';
import 'package:weighbridgemanagement/app/app_shell.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

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
    final gateStates = ref.watch(gateStateProvider).valueOrNull ?? {};
    final gateConfig = ref.watch(gateConfigProvider).valueOrNull;
    final displayBoard = ref.watch(displayBoardServiceProvider);
    final aiAvailable = ref.watch(aiAvailableProvider).valueOrNull ?? false;
    final aiHealth = ref.watch(aiHealthProvider).valueOrNull;
    final user = FirebaseAuth.instance.currentUser;

    // Two theme tones for status chips: positive (good) and negative (bad).
    final positive = AppTheme.successColor;
    final negative = scheme.error;
    final scaleConnected = scaleStatus == ScaleConnectionStatus.connected;
    final gatesEnabled = gateConfig?.systemEnabled ?? false;
    final entryState = gateStates[GateId.entry] ?? GateState.unknown;
    final exitState = gateStates[GateId.exit] ?? GateState.unknown;
    final gateError = entryState == GateState.error || exitState == GateState.error;

    return Container(
      height: 64,
      // Top padding mirrors the footer's bottom padding (20); L/R match the cards (16).
      padding: const EdgeInsets.only(left: 16, right: 16, top: 20),
      // Transparent background — only the chips/buttons carry colour.
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Row(
        children: [
          _SidebarToggle(scheme: scheme, ref: ref),
          SizedBox(width: AppSpacing.sm),
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

          SizedBox(width: AppSpacing.lg),
          Container(width: 1, height: 20, color: scheme.outlineVariant.withValues(alpha: 0.3)),
          SizedBox(width: AppSpacing.lg),

          _DeviceChip(
            icon: Icons.memory_outlined,
            label: aiAvailable ? _aiChipLabel(aiHealth) : 'Recognition Off',
            color: aiAvailable ? positive : negative,
            isError: !aiAvailable,
          ),

          if (gatesEnabled) ...[
            SizedBox(width: AppSpacing.sm),
            _DeviceChip(
              icon: Icons.sensor_door_outlined,
              label: 'In:${_gateShort(entryState)} Out:${_gateShort(exitState)}',
              color: _gateColor(scheme, entryState, exitState),
              isError: gateError,
            ),
          ],

          const Spacer(),

          // Scale + Display indicators on the right.
          _DeviceChip(
            icon: Icons.scale_outlined,
            label: scaleConnected ? 'Scale OK' : 'Scale Off',
            color: scaleConnected ? positive : negative,
            isError: !scaleConnected,
          ),

          SizedBox(width: AppSpacing.sm),

          _DeviceChip(
            icon: Icons.tv_outlined,
            label: displayBoard.hasConnectedBoards ? 'Display OK' : 'Display Off',
            color: displayBoard.hasConnectedBoards ? positive : negative,
            isError: !displayBoard.hasConnectedBoards,
          ),

          if (user != null) ...[
            SizedBox(width: AppSpacing.lg),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_outlined, size: 15, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                SizedBox(width: AppSpacing.xs),
                Text(
                  user.displayName ?? user.email?.split('@').first ?? '',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _aiChipLabel(SidecarHealth? health) {
    if (health == null) return 'AI OK';
    final models = health.modelsLoaded;
    final parts = <String>[];
    if (models.any((m) => m.contains('plate') || m.contains('anpr') || m.contains('yolo'))) parts.add('ANPR');
    if (models.any((m) => m.contains('face') || m.contains('insightface'))) parts.add('Face');
    if (models.any((m) => m.contains('ocr') || m.contains('parseq'))) parts.add('OCR');
    if (parts.isEmpty) return 'AI OK';
    return parts.join(' · ');
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

  Color _gateColor(ColorScheme scheme, GateState entry, GateState exit) {
    if (entry == GateState.error || exit == GateState.error) return scheme.error;
    if (entry == GateState.open || exit == GateState.open) return scheme.onSurfaceVariant;
    return scheme.onSurface;
  }

}

class _SidebarToggle extends StatelessWidget {
  final ColorScheme scheme;
  final WidgetRef ref;

  const _SidebarToggle({required this.scheme, required this.ref});

  @override
  Widget build(BuildContext context) {
    final collapsed = ref.watch(sidebarCollapsedProvider);
    return GestureDetector(
      onTap: () => ref.read(sidebarCollapsedProvider.notifier).state = !collapsed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Tooltip(
          message: collapsed ? 'Show sidebar' : 'Hide sidebar',
          child: Icon(
            collapsed ? Icons.menu_rounded : Icons.menu_open_rounded,
            size: 22,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _DeviceChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isError;

  const _DeviceChip({required this.icon, required this.label, required this.color, this.isError = false});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isError ? 0.08 : 0.05),
            borderRadius: AppRadius.chip,
            border: Border.all(color: color.withValues(alpha: isError ? 0.4 : 0.2)),
          ),
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ),
    );
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
          Icon(Icons.scale_outlined, size: 17, color: scheme.primary),
          SizedBox(width: 6.rs),
          Text(
            current != null ? '${current!.siteName} / ${current!.wbName}' : 'Weighbridge',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.primary),
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
          borderRadius: AppRadius.chip,
          border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.scale_outlined, size: 15, color: scheme.primary),
            SizedBox(width: 6.rs),
            Text(
              current != null ? '${current!.siteName} / ${current!.wbName}' : 'Select',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.primary),
            ),
            SizedBox(width: AppSpacing.xs),
            Icon(Icons.keyboard_arrow_down_outlined, size: 17, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}
