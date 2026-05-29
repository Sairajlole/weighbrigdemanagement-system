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
import 'package:weighbridgemanagement/features/weighment/application/weighment_providers.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
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
    final scaleConfig = ref.watch(scaleConfigProvider).valueOrNull ?? const ScaleConfig();
    final gateStates = ref.watch(gateStateProvider).valueOrNull ?? {};
    final gateConfig = ref.watch(gateConfigProvider).valueOrNull;
    final displayBoard = ref.watch(displayBoardServiceProvider);
    final aiAvailable = ref.watch(aiAvailableProvider).valueOrNull ?? false;
    final aiHealth = ref.watch(aiHealthProvider).valueOrNull;
    final user = FirebaseAuth.instance.currentUser;

    final scaleConnected = scaleStatus == ScaleConnectionStatus.connected;
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
            icon: Icons.scale_outlined,
            label: scaleConnected ? 'Scale OK' : 'Scale Off',
            color: scaleConnected ? scheme.onSurface : scheme.error,
            isError: !scaleConnected,
            onTap: () => _showStatusPopup(
              context: context,
              title: 'Scale',
              rows: [
                _InfoRow('Status', scaleConnected ? 'Connected' : 'Disconnected'),
                _InfoRow('Port', scaleConfig.port.isNotEmpty ? scaleConfig.port : 'Not configured'),
                _InfoRow('Baud rate', '${scaleConfig.baudRate}'),
                _InfoRow('Connection', scaleConfig.connectionType),
              ],
            ),
          ),

          SizedBox(width: AppSpacing.sm),

          _DeviceChip(
            icon: Icons.memory_outlined,
            label: aiAvailable ? _aiChipLabel(aiHealth) : 'AI Off',
            color: aiAvailable ? scheme.onSurface : scheme.onSurfaceVariant.withValues(alpha: 0.4),
            onTap: () => _showStatusPopup(
              context: context,
              title: 'AI Sidecar',
              rows: [
                _InfoRow('Status', aiAvailable ? 'Running' : 'Offline'),
                if (aiHealth != null) ...[
                  _InfoRow('Models', aiHealth.modelsLoaded.join(', ')),
                  _InfoRow('Inference', '${aiHealth.avgInferenceMs.toStringAsFixed(0)} ms'),
                  _InfoRow('Hardware', aiHealth.hardwareTier),
                ],
              ],
            ),
          ),

          SizedBox(width: AppSpacing.sm),

          if (gatesEnabled) ...[
            _DeviceChip(
              icon: Icons.sensor_door_outlined,
              label: 'In:${_gateShort(entryState)} Out:${_gateShort(exitState)}',
              color: _gateColor(scheme, entryState, exitState),
              isError: gateError,
              onTap: () => _showStatusPopup(
                context: context,
                title: 'Gates',
                rows: [
                  _InfoRow('Entry gate', _gateLabel(entryState)),
                  _InfoRow('Exit gate', _gateLabel(exitState)),
                  _InfoRow('Protocol', gateConfig?.entry.protocol ?? '—'),
                ],
              ),
            ),
            SizedBox(width: AppSpacing.sm),
          ],

          _DeviceChip(
            icon: Icons.tv_outlined,
            label: displayBoard.hasConnectedBoards ? 'Display OK' : 'Display Off',
            color: displayBoard.hasConnectedBoards ? scheme.onSurface : scheme.onSurfaceVariant.withValues(alpha: 0.4),
            onTap: () => _showStatusPopup(
              context: context,
              title: 'Display Board',
              rows: [
                _InfoRow('Status', displayBoard.hasConnectedBoards ? 'Connected' : 'Not connected'),
                _InfoRow('Configured', displayBoard.hasEnabledBoards ? 'Yes' : 'No'),
              ],
            ),
          ),

          const Spacer(),

          _FormDensityToggle(ref: ref, scheme: scheme),

          SizedBox(width: AppSpacing.md),

          if (user != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_outlined, size: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                SizedBox(width: AppSpacing.xs),
                Text(
                  user.displayName ?? user.email?.split('@').first ?? '',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                ),
              ],
            ),
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

  String _gateLabel(GateState state) {
    return switch (state) {
      GateState.closed => 'Closed',
      GateState.open => 'Open',
      GateState.opening => 'Opening...',
      GateState.closing => 'Closing...',
      GateState.error => 'Error',
      GateState.unknown => 'Unknown',
    };
  }

  Color _gateColor(ColorScheme scheme, GateState entry, GateState exit) {
    if (entry == GateState.error || exit == GateState.error) return scheme.error;
    if (entry == GateState.open || exit == GateState.open) return scheme.onSurfaceVariant;
    return scheme.onSurface;
  }

  void _showStatusPopup({
    required BuildContext context,
    required String title,
    required List<_InfoRow> rows,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => entry.remove(),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Positioned(
            left: offset.dx,
            top: offset.dy + renderBox.size.height + 4,
            child: Material(
              elevation: 4,
              borderRadius: AppRadius.button,
              color: scheme.surfaceContainerHigh,
              child: Container(
                constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
                padding: EdgeInsets.all(12.rs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                    SizedBox(height: AppSpacing.sm),
                    for (final row in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(row.label, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                            SizedBox(width: AppSpacing.md),
                            Flexible(
                              child: Text(row.value, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurface), textAlign: TextAlign.end, overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(entry);
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
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _InfoRow {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
}

class _DeviceChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isError;
  final VoidCallback? onTap;

  const _DeviceChip({required this.icon, required this.label, required this.color, this.isError = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isError ? 0.08 : 0.05),
            borderRadius: AppRadius.chip,
            border: Border.all(color: color.withValues(alpha: isError ? 0.4 : 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
              SizedBox(width: 5.rs),
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
          Icon(Icons.scale_outlined, size: 14, color: scheme.primary),
          SizedBox(width: 6.rs),
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
          borderRadius: AppRadius.chip,
          border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.scale_outlined, size: 12, color: scheme.primary),
            SizedBox(width: 6.rs),
            Text(
              current != null ? '${current!.siteName} / ${current!.wbName}' : 'Select',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.primary),
            ),
            SizedBox(width: AppSpacing.xs),
            Icon(Icons.keyboard_arrow_down_outlined, size: 14, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

class _FormDensityToggle extends StatelessWidget {
  final WidgetRef ref;
  final ColorScheme scheme;

  const _FormDensityToggle({required this.ref, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final scale = ref.watch(formScaleProvider);
    final isCompact = scale < 0.75;

    return GestureDetector(
      onTap: () {
        ref.read(formScaleProvider.notifier).state = isCompact ? 0.85 : 0.6;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.05),
            borderRadius: AppRadius.chip,
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isCompact ? Icons.density_small_outlined : Icons.density_medium_outlined,
                size: 12,
                color: scheme.onSurfaceVariant,
              ),
              SizedBox(width: AppSpacing.xs),
              Text(
                isCompact ? 'Compact' : 'Regular',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
