import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

final _weighbridgeListProvider = FutureProvider<List<WbEntry>>((ref) async {
  final ctx = ref.watch(siteContextProvider);
  if (ctx.companyId.isEmpty) return [];
  final db = FirebaseFirestore.instance;
  final sitesSnap = await db.collection('companies/${ctx.companyId}/sites').get();
  final list = <WbEntry>[];
  for (final site in sitesSnap.docs) {
    final siteName = site.data()['name'] as String? ?? 'Unnamed Site';
    final wbSnap = await db.collection('companies/${ctx.companyId}/sites/${site.id}/weighbridges').get();
    for (final wb in wbSnap.docs) {
      list.add(WbEntry(siteId: site.id, siteName: siteName, wbId: wb.id, wbName: wb.data()['name'] as String? ?? 'Unnamed WB'));
    }
  }
  return list;
});

class WbEntry {
  final String siteId;
  final String siteName;
  final String wbId;
  final String wbName;

  const WbEntry({required this.siteId, required this.siteName, required this.wbId, required this.wbName});
}

class WeighbridgeContextBar extends ConsumerWidget {
  final String label;
  final VoidCallback? onSwitched;

  const WeighbridgeContextBar({super.key, required this.label, this.onSwitched});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final ctx = ref.watch(siteContextProvider);
    final wbListAsync = ref.watch(_weighbridgeListProvider);
    final allWbs = wbListAsync.valueOrNull ?? [];
    final current = allWbs.where((w) => w.siteId == ctx.siteId && w.wbId == ctx.weighbridgeId).firstOrNull;
    final hasMultiple = allWbs.length > 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.08),
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.15))),
      ),
      child: Row(
        children: [
          Icon(Icons.scale_rounded, size: 14, color: scheme.primary),
          SizedBox(width: 8.rs),
          Text('$label:', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          SizedBox(width: 8.rs),
          if (hasMultiple)
            _WbDropdown(
              allWbs: allWbs,
              currentSiteId: ctx.siteId,
              currentWbId: ctx.weighbridgeId,
              scheme: scheme,
              text: text,
              onSelected: (wb) async {
                await ref.read(siteContextProvider.notifier).configure(
                  companyId: ctx.companyId,
                  siteId: wb.siteId,
                  weighbridgeId: wb.wbId,
                );
                ref.invalidate(firestorePathsProvider);
                ref.invalidate(_weighbridgeListProvider);
                onSwitched?.call();
              },
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6.rs),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
              ),
              child: Text(
                current != null ? '${current.siteName} / ${current.wbName}' : 'Current Weighbridge',
                style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary),
              ),
            ),
          const Spacer(),
          if (hasMultiple)
            Text(
              '${allWbs.length} weighbridges · ${allWbs.map((w) => w.siteId).toSet().length} site${allWbs.map((w) => w.siteId).toSet().length != 1 ? 's' : ''}',
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _WbDropdown extends StatefulWidget {
  final List<WbEntry> allWbs;
  final String currentSiteId;
  final String currentWbId;
  final ColorScheme scheme;
  final TextTheme text;
  final void Function(WbEntry) onSelected;

  const _WbDropdown({
    required this.allWbs,
    required this.currentSiteId,
    required this.currentWbId,
    required this.scheme,
    required this.text,
    required this.onSelected,
  });

  @override
  State<_WbDropdown> createState() => _WbDropdownState();
}

class _WbDropdownState extends State<_WbDropdown> {
  final _overlayController = OverlayPortalController();
  final _link = LayerLink();
  bool _open = false;

  WbEntry? get _current => widget.allWbs
      .where((w) => w.siteId == widget.currentSiteId && w.wbId == widget.currentWbId)
      .firstOrNull;

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      _overlayController.show();
    } else {
      _overlayController.hide();
    }
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    _overlayController.hide();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;
    final text = widget.text;
    final current = _current;

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (_) => _buildOverlay(scheme, text),
        child: GestureDetector(
          onTap: _toggle,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _open ? scheme.primary.withValues(alpha: 0.12) : scheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8.rs),
                border: Border.all(color: _open ? scheme.primary.withValues(alpha: 0.5) : scheme.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5.rs),
                    ),
                    child: Icon(Icons.scale_rounded, size: 11, color: scheme.primary),
                  ),
                  SizedBox(width: 8.rs),
                  if (current != null) ...[
                    Text(current.siteName, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.chevron_right_rounded, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                    ),
                    Text(current.wbName, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary)),
                  ] else
                    Text('Select Weighbridge', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  SizedBox(width: 6.rs),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: scheme.primary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(ColorScheme scheme, TextTheme text) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(onTap: _close, behavior: HitTestBehavior.opaque),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 6),
          child: Material(
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12.rs),
            color: scheme.surface,
            child: Container(
              constraints: const BoxConstraints(minWidth: 240, maxWidth: 320, maxHeight: 300),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.rs),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.rs),
                child: _buildList(scheme, text),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildList(ColorScheme scheme, TextTheme text) {
    final grouped = <String, List<WbEntry>>{};
    for (final wb in widget.allWbs) {
      grouped.putIfAbsent(wb.siteId, () => []).add(wb);
    }
    final siteIds = grouped.keys.toList();
    final multiSite = siteIds.length > 1;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var si = 0; si < siteIds.length; si++) ...[
            if (multiSite) ...[
              if (si > 0) Divider(height: 8, indent: 12, endIndent: 12, color: scheme.outlineVariant.withValues(alpha: 0.2)),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
                child: Row(
                  children: [
                    Icon(Icons.location_on_rounded, size: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                    SizedBox(width: 6.rs),
                    Text(
                      grouped[siteIds[si]]!.first.siteName,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.3),
                    ),
                  ],
                ),
              ),
            ],
            for (final wb in grouped[siteIds[si]]!) ...[
              _buildWbItem(wb, scheme, text),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildWbItem(WbEntry wb, ColorScheme scheme, TextTheme text) {
    final isCurrent = wb.siteId == widget.currentSiteId && wb.wbId == widget.currentWbId;

    return InkWell(
      onTap: isCurrent ? null : () {
        _close();
        widget.onSelected(wb);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        color: isCurrent ? scheme.primaryContainer.withValues(alpha: 0.15) : null,
        child: Row(
          children: [
            Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                color: isCurrent ? scheme.primary.withValues(alpha: 0.12) : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(7.rs),
              ),
              child: Icon(Icons.scale_rounded, size: 13, color: isCurrent ? scheme.primary : scheme.onSurfaceVariant),
            ),
            SizedBox(width: 10.rs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    wb.wbName,
                    style: text.bodySmall?.copyWith(
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                      color: isCurrent ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                  if (widget.allWbs.map((w) => w.siteId).toSet().length <= 1)
                    Text(wb.siteName, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (isCurrent)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4.rs),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 10, color: scheme.primary),
                    SizedBox(width: 3.rs),
                    Text('Active', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: scheme.primary)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
