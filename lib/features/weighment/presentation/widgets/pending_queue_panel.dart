import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_providers.dart';

class PendingQueuePanel extends ConsumerWidget {
  /// Resume a pending (first-weight-done) weighment into the form.
  final void Function(Map<String, dynamic> data, String docId)? onSelect;

  /// Print a saved weighment (first-weight slip or final slip, by status).
  final void Function(Map<String, dynamic> data, String docId)? onPrint;

  const PendingQueuePanel({super.key, this.onSelect, this.onPrint});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final collapsed = ref.watch(pendingPanelCollapsedProvider);
    final mode = ref.watch(leftPanelModeProvider);

    // Match the cameras card's width so the two side panels carry equal weight.
    // Read the size from MediaQuery (reactive) rather than Responsive's static
    // cache, so the width is correct on first paint and updates when the window
    // resizes — otherwise the panel keeps a stale width until it's rebuilt.
    final expandedWidth = (MediaQuery.sizeOf(context).width * 0.28).clamp(280.0, 500.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: collapsed ? 48 : expandedWidth,
      margin: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, 0, AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: AppElevation.card(scheme.shadow),
      ),
      clipBehavior: Clip.antiAlias,
      child: collapsed
          ? _buildCollapsedState(context, ref)
          : OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: expandedWidth,
              maxWidth: expandedWidth,
              child: mode == LeftPanelMode.browse
                  ? _BrowseView(onPrint: onPrint)
                  : _PendingView(onSelect: onSelect),
            ),
    );
  }

  Widget _buildCollapsedState(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final mode = ref.watch(leftPanelModeProvider);
    final count = mode == LeftPanelMode.browse
        ? (ref.watch(browseWeighmentsProvider).valueOrNull?.length ?? 0)
        : (ref.watch(pendingWeighmentsProvider).valueOrNull?.length ?? 0);

    return GestureDetector(
      onTap: () => ref.read(pendingPanelCollapsedProvider.notifier).state = false,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Badge(
              label: Text('$count'),
              backgroundColor: scheme.primaryContainer,
              textColor: scheme.onPrimaryContainer,
            ),
            const SizedBox(height: 12),
            RotatedBox(
              quarterTurns: 3,
              child: Text(
                mode == LeftPanelMode.browse ? 'BROWSE' : 'PENDING',
                style: textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared header: a Pending | Browse segmented toggle + collapse chevron.
class _PanelHeader extends ConsumerWidget {
  final Widget? trailing;
  const _PanelHeader({this.trailing});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final mode = ref.watch(leftPanelModeProvider);

    Widget tab(String label, LeftPanelMode m) {
      final selected = mode == m;
      return InkWell(
        onTap: () => ref.read(leftPanelModeProvider.notifier).state = m,
        borderRadius: AppRadius.chip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: AppRadius.chip,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 6),
      child: Row(
        children: [
          tab('Pending', LeftPanelMode.pending),
          const SizedBox(width: 4),
          tab('Browse', LeftPanelMode.browse),
          const Spacer(),
          if (trailing != null) trailing!,
          InkWell(
            onTap: () {
              // Collapsing always resets to Pending, so re-opening shows Pending
              // (never the Browse view).
              ref.read(leftPanelModeProvider.notifier).state = LeftPanelMode.pending;
              ref.read(pendingPanelCollapsedProvider.notifier).state = true;
            },
            borderRadius: BorderRadius.circular(4),
            child: Icon(Icons.chevron_left, size: 18, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PendingView extends ConsumerWidget {
  final void Function(Map<String, dynamic> data, String docId)? onSelect;
  const _PendingView({this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final pending = ref.watch(pendingWeighmentsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeader(
          trailing: pending.when(
            data: (list) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Badge(
                label: Text('${list.length}'),
                backgroundColor: scheme.primaryContainer,
                textColor: scheme.onPrimaryContainer,
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: pending.when(
            loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) => Center(child: Text('Error', style: textTheme.bodySmall?.copyWith(color: scheme.error))),
            data: (list) {
              if (list.isEmpty) {
                return Center(
                  child: Text('No pending weighments',
                      style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
                );
              }
              return Scrollbar(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _WeighmentTile(
                    data: list[i],
                    onTap: () => onSelect?.call(list[i], list[i]['id'] as String),
                    draggable: false,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BrowseView extends ConsumerStatefulWidget {
  final void Function(Map<String, dynamic> data, String docId)? onPrint;
  const _BrowseView({this.onPrint});

  @override
  ConsumerState<_BrowseView> createState() => _BrowseViewState();
}

class _BrowseViewState extends ConsumerState<_BrowseView> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _customChipKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(browseSearchProvider);
    // Put the cursor straight in the search box when Browse opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool _matches(Map<String, dynamic> w, String q) {
    if (q.isEmpty) return true;
    final hay = [
      w['rstNumber'], w['vehicleNumber'], w['customerName'], w['customerPhone'], w['phone'],
    ].map((v) => (v as String? ?? '').toLowerCase()).join(' ');
    return hay.contains(q);
  }

  // Same tap-start-then-end CalendarDatePicker the Weighments screen uses —
  // anchored just below the Custom chip with their LEFT edges aligned.
  Future<void> _pickCustomRange() async {
    final scheme = Theme.of(context).colorScheme;
    final renderBox = _customChipKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final chipSize = renderBox.size;
    final chipOffset = renderBox.localToGlobal(Offset.zero);
    const dialogWidth = 320.0;
    final screenW = MediaQuery.of(context).size.width;
    final maxLeft = (screenW - dialogWidth - 8).clamp(8.0, screenW);
    final left = chipOffset.dx.clamp(8.0, maxLeft).toDouble();
    final top = chipOffset.dy + chipSize.height + 6;

    DateTime? start;
    DateTime? end;
    // Picking a year fires onDisplayedMonthChanged then onDateChanged synchronously
    // — suppress that auto-selection so navigating years doesn't pre-pick a date.
    bool suppressNext = false;
    await showDialog(
      context: context,
      barrierColor: Colors.black12,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                elevation: 8,
                borderRadius: AppRadius.card,
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: dialogWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Row(
                          children: [
                            Text(
                              start != null && end != null
                                  ? _rangeLabel(start!, end!, base: 'dd MMM')
                                  : start != null
                                      ? '${DateFormat('dd MMM').format(start!)} – select end'
                                      : 'Select date range',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface),
                            ),
                          ],
                        ),
                      ),
                      CalendarDatePicker(
                        initialDate: null, // nothing pre-selected — user picks freely
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        onDisplayedMonthChanged: (_) {
                          suppressNext = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) => suppressNext = false);
                        },
                        onDateChanged: (date) {
                          if (suppressNext) { suppressNext = false; return; } // year/month jump — not a pick
                          if (start == null || end != null) {
                            setDialogState(() {
                              start = date;
                              end = null;
                            });
                          } else {
                            if (date.isBefore(start!)) {
                              setDialogState(() {
                                end = start;
                                start = date;
                              });
                            } else {
                              setDialogState(() => end = date);
                            }
                            ref.read(browseDateRangeProvider.notifier).state = (start!, end!);
                            Navigator.pop(ctx);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final all = ref.watch(browseWeighmentsProvider);
    final query = ref.watch(browseSearchProvider).trim().toLowerCase();
    final range = ref.watch(browseDateRangeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PanelHeader(),
        // Search + date filter
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                onChanged: (v) => ref.read(browseSearchProvider.notifier).state = v,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'RST / vehicle / name / phone',
                  hintStyle: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                  prefixIcon: Icon(Icons.search, size: 16, color: scheme.onSurfaceVariant),
                  prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  filled: true,
                  fillColor: scheme.surfaceContainerHigh,
                  border: OutlineInputBorder(borderRadius: AppRadius.chip, borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _DateChip(
                    label: 'Today',
                    selected: range == null,
                    onTap: () => ref.read(browseDateRangeProvider.notifier).state = null,
                  ),
                  const SizedBox(width: 6),
                  _DateChip(
                    key: _customChipKey,
                    label: range == null ? 'Custom' : _rangeLabel(range.$1, range.$2),
                    selected: range != null,
                    icon: Icons.calendar_today_outlined,
                    onTap: _pickCustomRange,
                  ),
                  if (range != null) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => ref.read(browseDateRangeProvider.notifier).state = null,
                      borderRadius: BorderRadius.circular(10),
                      child: Icon(Icons.close, size: 14, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: all.when(
            loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) => Center(child: Text('Error', style: textTheme.bodySmall?.copyWith(color: scheme.error))),
            data: (list) {
              final filtered = list.where((w) => _matches(w, query)).toList();
              if (filtered.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      query.isEmpty ? 'No saved weighments in this range' : 'No matches',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                    ),
                  ),
                );
              }
              return Scrollbar(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _WeighmentTile(
                    data: filtered[i],
                    onTap: () => widget.onPrint?.call(filtered[i], filtered[i]['id'] as String),
                    draggable: true,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Formats a date range "a – b", adding the year unless both dates fall in the
/// current year — so cross-year and any not-this-year range isn't ambiguous.
String _rangeLabel(DateTime a, DateTime b, {String base = 'd MMM'}) {
  final thisYear = DateTime.now().year;
  final showYear = a.year != thisYear || b.year != thisYear;
  final f = DateFormat(showYear ? '$base yyyy' : base);
  return '${f.format(a)} – ${f.format(b)}';
}

class _DateChip extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;
  const _DateChip({super.key, required this.label, required this.selected, this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.chip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.14) : scheme.surfaceContainerHigh,
          borderRadius: AppRadius.chip,
          border: Border.all(color: selected ? scheme.primary.withValues(alpha: 0.4) : scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: selected ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? scheme.primary : scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeighmentTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final bool draggable;

  const _WeighmentTile({required this.data, required this.onTap, required this.draggable});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final vehicle = data['vehicleNumber'] as String? ?? 'Unknown';
    final rst = data['rstNumber'] as String? ?? '';
    final customer = data['customerName'] as String? ?? '';
    final material = data['material'] as String? ?? '';
    final isCompleted = (data['status'] as String? ?? '') == 'completed';
    final grossWeight = (data['grossWeight'] as num?)?.toDouble();
    final netWeight = (data['netWeight'] as num?)?.toDouble();
    final createdAt = data['createdAt'];
    String timeStr = '';
    if (createdAt is Timestamp) timeStr = DateFormat.jm().format(createdAt.toDate());

    // Pending (first weight only) = amber; completed = green.
    final statusColor = isCompleted ? const Color(0xFF2E9E5B) : const Color(0xFFE0982E);

    final weightStr = isCompleted
        ? (netWeight != null ? 'Net ${netWeight.toStringAsFixed(0)} kg' : '')
        : (grossWeight != null ? '1st ${grossWeight.toStringAsFixed(0)} kg' : 'Awaiting 2nd');
    final subtitle = [if (material.isNotEmpty) material, if (weightStr.isNotEmpty) weightStr, if (rst.isNotEmpty) 'RST $rst']
        .join('  ·  ');

    final tile = ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: Container(
        width: 6,
        height: 36,
        decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(3)),
      ),
      title: Text(
        customer.isNotEmpty ? '$vehicle  ·  $customer' : vehicle,
        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(subtitle, style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis)
          : null,
      trailing: draggable
          ? Icon(Icons.print_outlined, size: 18, color: statusColor)
          : (timeStr.isNotEmpty ? Text(timeStr, style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)) : null),
      onTap: onTap,
    );

    if (!draggable) return tile;

    // Browse rows: click prints, drag onto the form fills the fields.
    return Draggable<Map<String, dynamic>>(
      data: data,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        elevation: 6,
        borderRadius: AppRadius.chip,
        color: scheme.surfaceContainerHighest,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(borderRadius: AppRadius.chip, border: Border.all(color: statusColor)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.drag_indicator, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(vehicle, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );
  }
}
