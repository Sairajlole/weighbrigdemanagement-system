import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/general_settings_provider.dart';
import 'package:weighbridgemanagement/shared/providers/print_provider.dart';
import 'package:weighbridgemanagement/shared/utils/title_case.dart';

void showWeighmentDetailDialog(BuildContext context, WidgetRef ref, Map<String, dynamic> w) {
  final state = context.findAncestorStateOfType<_WeighmentsScreenState>();
  if (state != null) {
    state._showDetailDialog(context, w);
  } else {
    showDialog(
      context: context,
      builder: (_) => _StandaloneWeighmentDetail(weighment: w),
    );
  }
}

final _weighmentsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.weighments.orderBy('createdAt', descending: true).snapshots().map(
    (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
  );
});

final _customerAddressMapProvider = StreamProvider<Map<String, String>>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.customers.snapshots().map(
    (snap) => { for (final d in snap.docs) (d.data()['name'] as String? ?? ''): d.data()['address'] as String? ?? '' },
  );
});

final _materialsProvider = Provider<List<String>>((ref) {
  final weighments = ref.watch(_weighmentsProvider).valueOrNull ?? [];
  final materials = <String>{};
  for (final w in weighments) {
    final mat = w['material'] as String? ?? '';
    if (mat.isNotEmpty) materials.add(mat);
  }
  final list = materials.toList()..sort();
  return list;
});

enum _DateRange { today, thisWeek, thisMonth, thisYear, thisFY, all, custom }
enum _StatusFilter { all, completed, pending }
enum _SortCol { rst, dateTime, vehicle, customer, customerPhone, address, material, gross, tare, net, grossDateTime, tareDateTime, operator }

enum _Col { rst, dateTime, vehicle, customer, customerPhone, address, material, gross, tare, net, grossDateTime, tareDateTime, operator }

class WeighmentsScreen extends ConsumerStatefulWidget {
  const WeighmentsScreen({super.key});

  @override
  ConsumerState<WeighmentsScreen> createState() => _WeighmentsScreenState();
}

class _WeighmentsScreenState extends ConsumerState<WeighmentsScreen> {
  static _DateRange _persistedDateRange = _DateRange.today;
  static _StatusFilter _persistedStatusFilter = _StatusFilter.all;
  static Set<String> _persistedMaterials = {};
  static DateTimeRange? _persistedCustomRange;

  late _DateRange _dateRange = _persistedDateRange;
  late _StatusFilter _statusFilter = _persistedStatusFilter;
  Set<String> _selectedMaterials = Set.of(_persistedMaterials);
  String _customerSearch = '';
  String _vehicleSearch = '';
  String _operatorSearch = '';
  DateTimeRange? _customRange = _persistedCustomRange;
  _SortCol _sortCol = _SortCol.dateTime;
  bool _sortAsc = false;
  final Set<_Col> _visibleCols = {_Col.rst, _Col.dateTime, _Col.vehicle, _Col.customer, _Col.address, _Col.material, _Col.gross, _Col.tare, _Col.net, _Col.operator};

  static const _colsPrefKey = 'weighments_visible_cols';

  @override
  void initState() {
    super.initState();
    _loadPersistedCols();
  }

  Future<void> _loadPersistedCols() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_colsPrefKey);
    if (saved != null && saved.isNotEmpty) {
      final restored = saved.map((n) => _Col.values.firstWhere((c) => c.name == n, orElse: () => _Col.rst)).toSet();
      if (restored.length >= 3) {
        setState(() {
          _visibleCols.clear();
          _visibleCols.addAll(restored);
        });
      }
    }
  }

  void _persistCols() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setStringList(_colsPrefKey, _visibleCols.map((c) => c.name).toList());
    });
  }

  void _setDateRange(_DateRange range, {DateTimeRange? custom}) {
    setState(() {
      _dateRange = range;
      if (custom != null) _customRange = custom;
    });
    _persistedDateRange = range;
    if (custom != null) _persistedCustomRange = custom;
  }

  void _setStatusFilter(_StatusFilter filter) {
    setState(() => _statusFilter = filter);
    _persistedStatusFilter = filter;
  }

  void _setMaterials(Set<String> materials) {
    setState(() => _selectedMaterials = materials);
    _persistedMaterials = Set.of(materials);
  }

  DateTimeRange _getDateRange() {
    final now = DateTime.now();
    switch (_dateRange) {
      case _DateRange.today:
        return DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case _DateRange.thisWeek:
        final weekday = now.weekday;
        final start = now.subtract(Duration(days: weekday - 1));
        return DateTimeRange(
          start: DateTime(start.year, start.month, start.day),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case _DateRange.thisMonth:
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case _DateRange.thisYear:
        return DateTimeRange(
          start: DateTime(now.year, 1, 1),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case _DateRange.thisFY:
        final fyStart = now.month >= 4 ? DateTime(now.year, 4, 1) : DateTime(now.year - 1, 4, 1);
        return DateTimeRange(start: fyStart, end: now);
      case _DateRange.all:
        return DateTimeRange(start: DateTime(2000), end: DateTime(2100));
      case _DateRange.custom:
        return _customRange ?? DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
    }
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> all) {
    final range = _getDateRange();
    var filtered = all.where((w) {
      final ts = w['createdAt'];
      if (ts is! Timestamp) return false;
      final dt = ts.toDate();
      return !dt.isBefore(range.start) && !dt.isAfter(range.end);
    }).toList();

    if (_statusFilter == _StatusFilter.completed) {
      filtered = filtered.where((w) => w['status'] == 'completed').toList();
    } else if (_statusFilter == _StatusFilter.pending) {
      filtered = filtered.where((w) => w['status'] == 'awaitingTare').toList();
    }

    if (_selectedMaterials.isNotEmpty) {
      filtered = filtered.where((w) => _selectedMaterials.contains(w['material'] as String? ?? '')).toList();
    }

    if (_customerSearch.isNotEmpty) {
      filtered = filtered.where((w) =>
        (w['customerName'] as String? ?? '').toLowerCase().contains(_customerSearch)).toList();
    }

    if (_vehicleSearch.isNotEmpty) {
      filtered = filtered.where((w) =>
        (w['vehicleNumber'] as String? ?? '').toLowerCase().contains(_vehicleSearch)).toList();
    }

    if (_operatorSearch.isNotEmpty) {
      filtered = filtered.where((w) =>
        (w['operatorName'] as String? ?? '').toLowerCase().contains(_operatorSearch)).toList();
    }

    return filtered;
  }

  List<Map<String, dynamic>> _applySort(List<Map<String, dynamic>> list) {
    final pending = list.where((w) => w['status'] == 'awaitingTare').toList();
    final rest = list.where((w) => w['status'] != 'awaitingTare').toList();

    rest.sort((a, b) {
      int cmp;
      switch (_sortCol) {
        case _SortCol.rst:
          cmp = (a['rstNumber'] as String? ?? '').compareTo(b['rstNumber'] as String? ?? '');
        case _SortCol.dateTime:
          final ta = a['createdAt'] is Timestamp ? (a['createdAt'] as Timestamp).millisecondsSinceEpoch : 0;
          final tb = b['createdAt'] is Timestamp ? (b['createdAt'] as Timestamp).millisecondsSinceEpoch : 0;
          cmp = ta.compareTo(tb);
        case _SortCol.vehicle:
          cmp = (a['vehicleNumber'] as String? ?? '').compareTo(b['vehicleNumber'] as String? ?? '');
        case _SortCol.customer:
          cmp = (a['customerName'] as String? ?? '').compareTo(b['customerName'] as String? ?? '');
        case _SortCol.address:
          cmp = (a['customerAddress'] as String? ?? '').compareTo(b['customerAddress'] as String? ?? '');
        case _SortCol.material:
          cmp = (a['material'] as String? ?? '').compareTo(b['material'] as String? ?? '');
        case _SortCol.gross:
          cmp = ((a['grossWeight'] as num?) ?? 0).compareTo((b['grossWeight'] as num?) ?? 0);
        case _SortCol.tare:
          cmp = ((a['tareWeight'] as num?) ?? 0).compareTo((b['tareWeight'] as num?) ?? 0);
        case _SortCol.net:
          cmp = ((a['netWeight'] as num?) ?? 0).compareTo((b['netWeight'] as num?) ?? 0);
        case _SortCol.customerPhone:
          cmp = (a['customerPhone'] as String? ?? '').compareTo(b['customerPhone'] as String? ?? '');
        case _SortCol.grossDateTime:
          final ga = a['grossDateTime'] is Timestamp ? (a['grossDateTime'] as Timestamp).millisecondsSinceEpoch : 0;
          final gb = b['grossDateTime'] is Timestamp ? (b['grossDateTime'] as Timestamp).millisecondsSinceEpoch : 0;
          cmp = ga.compareTo(gb);
        case _SortCol.tareDateTime:
          final ta2 = a['tareDateTime'] is Timestamp ? (a['tareDateTime'] as Timestamp).millisecondsSinceEpoch : 0;
          final tb2 = b['tareDateTime'] is Timestamp ? (b['tareDateTime'] as Timestamp).millisecondsSinceEpoch : 0;
          cmp = ta2.compareTo(tb2);
        case _SortCol.operator:
          cmp = (a['operatorName'] as String? ?? '').compareTo(b['operatorName'] as String? ?? '');
      }
      return _sortAsc ? cmp : -cmp;
    });

    return [...pending, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final weighmentsAsync = ref.watch(_weighmentsProvider);
    final materials = ref.watch(_materialsProvider);
    final addressMap = ref.watch(_customerAddressMapProvider).valueOrNull ?? {};

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Weighments', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          weighmentsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (all) => _buildStatsBar(all, scheme),
          ),
          const SizedBox(height: 16),
          _buildFilterRow(scheme, materials),
          const SizedBox(height: 16),
          Expanded(
            child: weighmentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (all) {
                final filtered = _applyFilters(all);
                final sorted = _applySort(filtered);

                if (sorted.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.scale_outlined, size: 48, color: scheme.outlineVariant),
                        const SizedBox(height: 8),
                        Text('No weighments found', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Text('Try adjusting your date range or filters', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    Expanded(child: _buildTable(sorted, scheme, addressMap)),
                    const SizedBox(height: 12),
                    _buildBottomBar(sorted, scheme),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar(List<Map<String, dynamic>> all, ColorScheme scheme) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final todayWeighments = all.where((w) {
      final ts = w['createdAt'];
      if (ts is! Timestamp) return false;
      final dt = ts.toDate();
      return !dt.isBefore(todayStart) && !dt.isAfter(todayEnd);
    }).toList();

    final todayCount = todayWeighments.length;
    final pendingCount = all.where((w) => w['status'] == 'awaitingTare').length;

    double todayNet = 0;
    for (final w in todayWeighments) {
      if (w['status'] == 'completed') {
        todayNet += (w['netWeight'] as num? ?? 0).toDouble();
      }
    }

    Duration totalTurnaround = Duration.zero;
    int turnaroundCount = 0;
    for (final w in todayWeighments) {
      if (w['status'] == 'completed' && w['grossDateTime'] is Timestamp && w['tareDateTime'] is Timestamp) {
        final gross = (w['grossDateTime'] as Timestamp).toDate();
        final tare = (w['tareDateTime'] as Timestamp).toDate();
        totalTurnaround += tare.difference(gross).abs();
        turnaroundCount++;
      }
    }
    final avgTurnaround = turnaroundCount > 0
        ? Duration(milliseconds: totalTurnaround.inMilliseconds ~/ turnaroundCount)
        : Duration.zero;

    return Row(
      children: [
        _statCard('Today', todayCount.toString(), Icons.today_rounded, scheme.primary, scheme),
        const SizedBox(width: 12),
        _statCard('Pending', pendingCount.toString(), Icons.hourglass_bottom_rounded, Colors.amber.shade700, scheme),
        const SizedBox(width: 12),
        _statCard('Today Net', '${(todayNet / 1000).toStringAsFixed(2)} T', Icons.monitor_weight_rounded, todayNet < 0 ? scheme.error : Colors.green.shade700, scheme),
        const SizedBox(width: 12),
        _statCard('Avg Turnaround', _formatDuration(avgTurnaround), Icons.timer_rounded, Colors.deepPurple, scheme),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color, ColorScheme scheme) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d == Duration.zero) return '--';
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  Widget _buildFilterRow(ColorScheme scheme, List<String> materials) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildDateRangeChips(scheme),
        const SizedBox(width: 8),
        _buildStatusChips(scheme),
        const SizedBox(width: 8),
        _buildMaterialButton(scheme, materials),
        const SizedBox(width: 8),
        SizedBox(
          width: 150,
          height: 32,
          child: Center(
            child: TextField(
              onChanged: (v) => setState(() => _customerSearch = v.toLowerCase()),
              expands: true,
              maxLines: null,
              decoration: InputDecoration(
                hintText: 'Customer...',
                hintStyle: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                filled: true,
                fillColor: scheme.surfaceContainerHigh,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: scheme.primary, width: 1.5)),
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
        SizedBox(
          width: 140,
          height: 32,
          child: Center(
            child: TextField(
              onChanged: (v) => setState(() => _vehicleSearch = v.toLowerCase()),
              expands: true,
              maxLines: null,
              decoration: InputDecoration(
                hintText: 'Vehicle...',
                hintStyle: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                filled: true,
                fillColor: scheme.surfaceContainerHigh,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: scheme.primary, width: 1.5)),
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
        SizedBox(
          width: 140,
          height: 32,
          child: Center(
            child: TextField(
              onChanged: (v) => setState(() => _operatorSearch = v.toLowerCase()),
              expands: true,
              maxLines: null,
              decoration: InputDecoration(
                hintText: 'Operator...',
                hintStyle: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                filled: true,
                fillColor: scheme.surfaceContainerHigh,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: scheme.primary, width: 1.5)),
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  final GlobalKey _customChipKey = GlobalKey();
  final GlobalKey _materialKey = GlobalKey();

  void _showCustomDatePicker(ColorScheme scheme) async {
    final renderBox = _customChipKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final chipSize = renderBox.size;
    final chipOffset = renderBox.localToGlobal(Offset.zero);
    const dialogWidth = 320.0;
    final left = chipOffset.dx + (chipSize.width / 2) - (dialogWidth / 2);
    final top = chipOffset.dy + chipSize.height + 6;

    DateTime? start;
    DateTime? end;

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
                borderRadius: BorderRadius.circular(12),
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
                                  ? '${DateFormat('dd MMM').format(start!)} – ${DateFormat('dd MMM').format(end!)}'
                                  : start != null
                                      ? '${DateFormat('dd MMM').format(start!)} – select end'
                                      : 'Select date range',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface),
                            ),
                          ],
                        ),
                      ),
                      CalendarDatePicker(
                        initialDate: _customRange?.start ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        onDateChanged: (date) {
                          if (start == null || end != null) {
                            setDialogState(() { start = date; end = null; });
                          } else {
                            if (date.isBefore(start!)) {
                              setDialogState(() { end = start; start = date; });
                            } else {
                              setDialogState(() { end = date; });
                            }
                            _setDateRange(_DateRange.custom, custom: DateTimeRange(start: start!, end: end!));
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

  Widget _buildDateRangeChips(ColorScheme scheme) {
    Widget chip(String label, _DateRange range, {Key? key}) {
      final selected = _dateRange == range;
      return GestureDetector(
        key: key,
        onTap: () {
          if (range == _DateRange.custom) {
            _showCustomDatePicker(scheme);
          } else {
            _setDateRange(range);
          }
        },
        child: Container(
          height: 32,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            range == _DateRange.custom && _dateRange == _DateRange.custom && _customRange != null
                ? '${DateFormat('dd/MM').format(_customRange!.start)} – ${DateFormat('dd/MM').format(_customRange!.end)}'
                : label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? scheme.onPrimary : scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip('Today', _DateRange.today),
        const SizedBox(width: 4),
        chip('Week', _DateRange.thisWeek),
        const SizedBox(width: 4),
        chip('Month', _DateRange.thisMonth),
        const SizedBox(width: 4),
        chip('Year', _DateRange.thisYear),
        const SizedBox(width: 4),
        chip('FY ${DateTime.now().month >= 4 ? '${DateTime.now().year % 100}-${(DateTime.now().year + 1) % 100}' : '${(DateTime.now().year - 1) % 100}-${DateTime.now().year % 100}'}', _DateRange.thisFY),
        const SizedBox(width: 4),
        chip('All', _DateRange.all),
        const SizedBox(width: 4),
        chip('Custom', _DateRange.custom, key: _customChipKey),
      ],
    );
  }

  Widget _buildStatusChips(ColorScheme scheme) {
    Widget chip(String label, _StatusFilter status) {
      final selected = _statusFilter == status;
      return GestureDetector(
        onTap: () => _setStatusFilter(status),
        child: Container(
          height: 32,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? scheme.tertiary : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? scheme.onTertiary : scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip('All', _StatusFilter.all),
        const SizedBox(width: 4),
        chip('Completed', _StatusFilter.completed),
        const SizedBox(width: 4),
        chip('Pending', _StatusFilter.pending),
      ],
    );
  }

  Widget _buildMaterialButton(ColorScheme scheme, List<String> materials) {
    if (materials.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      key: _materialKey,
      onTap: () => _showMaterialPicker(scheme, materials),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _selectedMaterials.isNotEmpty ? scheme.tertiaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _selectedMaterials.isEmpty ? 'Material' : 'Material (${_selectedMaterials.length})',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _selectedMaterials.isNotEmpty ? scheme.onTertiaryContainer : scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  void _showMaterialPicker(ColorScheme scheme, List<String> materials) {
    final renderBox = _materialKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final chipSize = renderBox.size;
    final chipOffset = renderBox.localToGlobal(Offset.zero);
    final left = chipOffset.dx;
    final top = chipOffset.dy + chipSize.height + 6;

    showDialog(
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
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  width: 280,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Filter by material', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                          const Spacer(),
                          if (_selectedMaterials.isNotEmpty)
                            GestureDetector(
                              onTap: () { _setMaterials({}); setDialogState(() {}); },
                              child: Text('Clear', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.primary)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: materials.map((m) {
                          final active = _selectedMaterials.contains(m);
                          return GestureDetector(
                            onTap: () {
                              final updated = Set.of(_selectedMaterials);
                              if (active) { updated.remove(m); } else { updated.add(m); }
                              _setMaterials(updated);
                              setDialogState(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: active ? scheme.tertiary.withValues(alpha: 0.15) : scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(6),
                                border: active ? Border.all(color: scheme.tertiary.withValues(alpha: 0.6)) : null,
                              ),
                              child: Text(
                                toTitleCase(m),
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: active ? scheme.tertiary : scheme.onSurfaceVariant),
                              ),
                            ),
                          );
                        }).toList(),
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

  Widget _buildTable(List<Map<String, dynamic>> sorted, ColorScheme scheme, Map<String, String> addressMap) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            _buildTableHeader(scheme),
            Expanded(
              child: ListView.builder(
                itemCount: sorted.length,
                itemBuilder: (_, i) => _buildTableRow(sorted[i], i, scheme, sorted.length, addressMap),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onSortTap(_SortCol col) {
    setState(() {
      if (_sortCol == col) {
        _sortAsc = !_sortAsc;
      } else {
        _sortCol = col;
        _sortAsc = true;
      }
    });
  }

  Widget _sortableHeader(String label, _SortCol col, ColorScheme scheme, {double? width}) {
    final active = _sortCol == col;
    return GestureDetector(
      onTap: () => _onSortTap(col),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
            if (active)
              Icon(_sortAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: scheme.primary),
          ],
        ),
      ),
    );
  }

  String _colLabel(_Col col) {
    switch (col) {
      case _Col.rst: return 'RST';
      case _Col.dateTime: return 'Date/Time';
      case _Col.vehicle: return 'Vehicle';
      case _Col.customer: return 'Customer';
      case _Col.customerPhone: return 'Phone';
      case _Col.address: return 'Address';
      case _Col.material: return 'Material';
      case _Col.gross: return 'Gross';
      case _Col.tare: return 'Tare';
      case _Col.net: return 'Net';
      case _Col.grossDateTime: return 'Gross Time';
      case _Col.tareDateTime: return 'Tare Time';
      case _Col.operator: return 'Operator';
    }
  }

  _SortCol _colToSort(_Col col) {
    switch (col) {
      case _Col.rst: return _SortCol.rst;
      case _Col.dateTime: return _SortCol.dateTime;
      case _Col.vehicle: return _SortCol.vehicle;
      case _Col.customer: return _SortCol.customer;
      case _Col.customerPhone: return _SortCol.customerPhone;
      case _Col.address: return _SortCol.address;
      case _Col.material: return _SortCol.material;
      case _Col.gross: return _SortCol.gross;
      case _Col.tare: return _SortCol.tare;
      case _Col.net: return _SortCol.net;
      case _Col.grossDateTime: return _SortCol.grossDateTime;
      case _Col.tareDateTime: return _SortCol.tareDateTime;
      case _Col.operator: return _SortCol.operator;
    }
  }

  int _colFlex(_Col col) {
    switch (col) {
      case _Col.dateTime:
      case _Col.vehicle:
      case _Col.customer:
      case _Col.address:
        return 3;
      case _Col.rst:
      case _Col.customerPhone:
      case _Col.material:
      case _Col.gross:
      case _Col.tare:
      case _Col.net:
      case _Col.grossDateTime:
      case _Col.tareDateTime:
      case _Col.operator:
        return 2;
    }
  }


  final GlobalKey _tableColumnsKey = GlobalKey();

  Widget _buildTableHeader(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          SizedBox(width: 42, child: Text('#', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant))),
          for (final col in _Col.values)
            if (_visibleCols.contains(col))
              Expanded(flex: _colFlex(col), child: _sortableHeader(_colLabel(col), _colToSort(col), scheme)),
          SizedBox(
            width: 32,
            child: IconButton(
              key: _tableColumnsKey,
              icon: Icon(Icons.view_column_rounded, size: 16, color: scheme.onSurfaceVariant),
              tooltip: 'Select columns',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => _showTableColumnPicker(scheme),
            ),
          ),
        ],
      ),
    );
  }

  void _showTableColumnPicker(ColorScheme scheme) {
    final renderBox = _tableColumnsKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final chipSize = renderBox.size;
    final chipOffset = renderBox.localToGlobal(Offset.zero);
    final right = MediaQuery.of(context).size.width - chipOffset.dx - chipSize.width;
    final top = chipOffset.dy + chipSize.height + 6;

    final cols = _Col.values.toList();
    final perRow = (cols.length / 4).ceil();

    showDialog(
      context: context,
      barrierColor: Colors.black12,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Stack(
          children: [
            Positioned(
              right: right,
              top: top,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Toggle columns (min 3)', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      for (int row = 0; row < 4; row++)
                        Padding(
                          padding: EdgeInsets.only(bottom: row < 3 ? 8 : 0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (int i = row * perRow; i < (row + 1) * perRow && i < cols.length; i++) ...[
                                if (i > row * perRow) const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      final active = _visibleCols.contains(cols[i]);
                                      if (active) {
                                        if (_visibleCols.length > 3) _visibleCols.remove(cols[i]);
                                      } else {
                                        _visibleCols.add(cols[i]);
                                      }
                                    });
                                    _persistCols();
                                    setDialogState(() {});
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: _visibleCols.contains(cols[i]) ? scheme.primary.withValues(alpha: 0.12) : scheme.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(6),
                                      border: _visibleCols.contains(cols[i]) ? Border.all(color: scheme.primary.withValues(alpha: 0.5)) : null,
                                    ),
                                    child: Text(
                                      _colLabel(cols[i]),
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _visibleCols.contains(cols[i]) ? scheme.primary : scheme.onSurfaceVariant),
                                    ),
                                  ),
                                ),
                              ],
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
      ),
    );
  }

  Widget _buildTableRow(Map<String, dynamic> w, int index, ColorScheme scheme, int total, Map<String, String> addressMap) {
    final isPending = w['status'] == 'awaitingTare';
    final isEvenRow = index % 2 == 0;
    final isBoldDivider = index > 0 && index % 5 == 0;

    final createdAt = w['createdAt'] is Timestamp
        ? DateFormat('dd MMM yy HH:mm').format((w['createdAt'] as Timestamp).toDate())
        : '--';

    final grossWeight = w['grossWeight'] as num? ?? 0;
    final tareWeight = w['tareWeight'] as num? ?? 0;
    final netWeight = w['netWeight'] as num? ?? 0;

    return GestureDetector(
      onTap: () => _showDetailDialog(context, w),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isPending
              ? Colors.amber.withValues(alpha: 0.08)
              : isEvenRow
                  ? scheme.surface
                  : scheme.surfaceContainerLow.withValues(alpha: 0.5),
          border: Border(
            left: BorderSide(
              color: isPending ? Colors.amber.shade700 : scheme.primary.withValues(alpha: isEvenRow ? 0.15 : 0.35),
              width: 3,
            ),
            top: isBoldDivider
                ? BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6), width: 2)
                : BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2)),
          ),
        ),
        child: Row(
          children: [
            SizedBox(width: 42, child: Text('${index + 1}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
            for (final col in _Col.values)
              if (_visibleCols.contains(col))
                Expanded(flex: _colFlex(col), child: _buildCell(col, w, createdAt, grossWeight, tareWeight, netWeight, scheme, addressMap)),
          ],
        ),
      ),
    );
  }

  Widget _buildCell(_Col col, Map<String, dynamic> w, String createdAt, num grossWeight, num tareWeight, num netWeight, ColorScheme scheme, Map<String, String> addressMap) {
    switch (col) {
      case _Col.rst:
        return Text(w['rstNumber'] as String? ?? '--', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis, maxLines: 1);
      case _Col.dateTime:
        return Text(createdAt, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis, maxLines: 1);
      case _Col.vehicle:
        return Text(w['vehicleNumber'] as String? ?? '--', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis, maxLines: 1);
      case _Col.customer:
        final name = w['customerName'] as String? ?? '--';
        final isArchived = name == '[Archived]';
        return Text(isArchived ? '[Archived]' : toTitleCase(name), style: TextStyle(fontSize: 13, fontStyle: isArchived ? FontStyle.italic : null, color: isArchived ? scheme.onSurfaceVariant : null), overflow: TextOverflow.ellipsis, maxLines: 1);
      case _Col.customerPhone:
        return Text(w['customerPhone'] as String? ?? '--', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis, maxLines: 1);
      case _Col.address:
        final customerName = w['customerName'] as String? ?? '';
        if (customerName == '[Archived]') {
          return Text('[Archived]', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis, maxLines: 1);
        }
        final addr = w['customerAddress'] as String? ?? '';
        final resolved = addr.isNotEmpty ? addr : (addressMap[customerName] ?? '--');
        return Text(resolved, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis, maxLines: 1);
      case _Col.material:
        return Text(toTitleCase(w['material'] as String? ?? '--'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis, maxLines: 1);
      case _Col.gross:
        return Text(grossWeight != 0 ? grossWeight.toStringAsFixed(0) : '--', style: TextStyle(fontSize: 13, color: grossWeight < 0 ? scheme.error : null));
      case _Col.tare:
        return Text(tareWeight != 0 ? tareWeight.toStringAsFixed(0) : '--', style: TextStyle(fontSize: 13, color: tareWeight < 0 ? scheme.error : null));
      case _Col.net:
        return Text(netWeight != 0 ? netWeight.toStringAsFixed(0) : '--', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: netWeight < 0 ? scheme.error : netWeight != 0 ? scheme.primary : null));
      case _Col.grossDateTime:
        final gdt = w['grossDateTime'];
        return Text(gdt is Timestamp ? DateFormat('dd MMM HH:mm').format(gdt.toDate()) : '--', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis, maxLines: 1);
      case _Col.tareDateTime:
        final tdt = w['tareDateTime'];
        return Text(tdt is Timestamp ? DateFormat('dd MMM HH:mm').format(tdt.toDate()) : '--', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis, maxLines: 1);
      case _Col.operator:
        return Text(toTitleCase(w['operatorName'] as String? ?? '--'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis, maxLines: 1);
    }
  }

  Widget _statusChip(String status, ColorScheme scheme) {
    final isCompleted = status == 'completed';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isCompleted ? scheme.primaryContainer.withValues(alpha: 0.5) : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isCompleted ? 'Done' : 'Pending',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isCompleted ? scheme.primary : scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildBottomBar(List<Map<String, dynamic>> sorted, ColorScheme scheme) {
    double sumGross = 0, sumTare = 0, sumNet = 0;
    final materialBreakdown = <String, int>{};

    for (final w in sorted) {
      sumGross += (w['grossWeight'] as num? ?? 0).toDouble();
      sumTare += (w['tareWeight'] as num? ?? 0).toDouble();
      sumNet += (w['netWeight'] as num? ?? 0).toDouble();
      final mat = w['material'] as String? ?? 'Unknown';
      materialBreakdown[mat] = (materialBreakdown[mat] ?? 0) + 1;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Text('${sorted.length} entries', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
          const SizedBox(width: 20),
          _summaryPill('Gross', '${(sumGross / 1000).toStringAsFixed(1)}T', scheme, isNegative: sumGross < 0),
          const SizedBox(width: 8),
          _summaryPill('Tare', '${(sumTare / 1000).toStringAsFixed(1)}T', scheme, isNegative: sumTare < 0),
          const SizedBox(width: 8),
          _summaryPill('Net', '${(sumNet / 1000).toStringAsFixed(1)}T', scheme, isNegative: sumNet < 0),
          const SizedBox(width: 20),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: materialBreakdown.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${toTitleCase(e.key)}: ${e.value}',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSecondaryContainer),
                    ),
                  ),
                )).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryPill(String label, String value, ColorScheme scheme, {bool isNegative = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isNegative ? scheme.errorContainer.withValues(alpha: 0.5) : scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$label: $value', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isNegative ? scheme.error : scheme.onPrimaryContainer)),
    );
  }

  void _showDetailDialog(BuildContext context, Map<String, dynamic> w) {
    final scheme = Theme.of(context).colorScheme;
    final grossDt = w['grossDateTime'] is Timestamp ? (w['grossDateTime'] as Timestamp).toDate() : null;
    final tareDt = w['tareDateTime'] is Timestamp ? (w['tareDateTime'] as Timestamp).toDate() : null;
    String fmtDateTime(DateTime? dt) => dt != null ? DateFormat('dd/MM/yyyy HH:mm').format(dt) : '--';

    final company = ref.read(generalSettingsProvider).valueOrNull ?? {};
    final scalePort = ref.read(scaleSettingsProvider).valueOrNull?['port'] as String? ?? '';
    final customerName = w['customerName'] as String? ?? '';
    final snapData = _extractSnapshots(w);
    const excludeLabels = ['Operator', 'Customer'];
    int countEvidence(List<String> labels) => labels.where((l) => !excludeLabels.contains(l)).length;
    final int grossEvidence = countEvidence(snapData.grossLabels);
    final int tareEvidence = countEvidence(snapData.tareLabels);

    showDialog(
      context: context,
      builder: (dialogCtx) {
    final screenH = MediaQuery.of(dialogCtx).size.height;
    final int maxEvidence = grossEvidence > tareEvidence ? grossEvidence : tareEvidence;
    final bool hasCameras = maxEvidence > 0;
    final int cols = maxEvidence <= 1 ? 1 : 2;
    final int rows = hasCameras ? (maxEvidence / cols).ceil() : 0;
    final double dialogH = hasCameras
        ? (screenH * (rows <= 1 ? 0.72 : rows == 2 ? 0.84 : 0.96))
        : 380.0;
    var viewMode = snapData.grossPaths.isNotEmpty ? 'gross' : 'tare';
    String? dialogMsg;
    bool dialogMsgIsError = false;

    return StatefulBuilder(
      builder: (dialogCtx2, setDialogState) {

    return Dialog(
        alignment: Alignment.topCenter,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
        child: SizedBox(
          width: 900,
          height: dialogH,
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(24, 14, 16, 14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
                        child: Text('#${w['rstNumber'] ?? '--'}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                        child: Text(w['vehicleNumber'] as String? ?? '--', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface, letterSpacing: 0.3)),
                      ),
                      const SizedBox(width: 10),
                      // PDF417
                      GestureDetector(
                        onTap: () => _showEnlargedBarcode(context, w, company),
                        child: SizedBox(
                          width: 140,
                          height: 28,
                          child: _buildBarcodeWidget(w, company, scheme),
                        ),
                      ),
                      const Spacer(),
                      _statusChip(w['status'] as String? ?? '', scheme),
                      const SizedBox(width: 10),
                      if (w['status'] == 'awaitingTare') ...[
                        FilledButton(
                          onPressed: () {
                            Navigator.pop(dialogCtx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Navigate to weighment screen')),
                            );
                          },
                          child: Text(
                            w['grossWeight'] != null ? 'Complete Tare' : 'Complete Gross',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      _QuickPrintButton(
                        weighmentId: w['id'] as String,
                        onResult: (msg, isError) {
                          setDialogState(() { dialogMsg = msg; dialogMsgIsError = isError; });
                          Future.delayed(Duration(seconds: isError ? 5 : 3), () {
                            setDialogState(() { dialogMsg = null; });
                          });
                        },
                      ),
                      const SizedBox(width: 6),
                      _PrintToButton(
                        weighmentId: w['id'] as String,
                        onResult: (msg, isError) {
                          setDialogState(() { dialogMsg = msg; dialogMsgIsError = isError; });
                          Future.delayed(Duration(seconds: isError ? 5 : 3), () {
                            setDialogState(() { dialogMsg = null; });
                          });
                        },
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogCtx),
                        icon: const Icon(Icons.close, size: 22),
                      ),
                    ],
                  ),
                ),
              ),
              if (dialogMsg != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  color: dialogMsgIsError
                      ? scheme.errorContainer
                      : const Color(0xFF2E7D32).withAlpha(25),
                  child: Row(
                    children: [
                      Icon(
                        dialogMsgIsError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
                        size: 16,
                        color: dialogMsgIsError ? scheme.error : const Color(0xFF2E7D32),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        dialogMsg!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: dialogMsgIsError ? scheme.onErrorContainer : const Color(0xFF2E7D32),
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              // Body
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    children: [
                      // Company header
                      Builder(builder: (_) {
                        final hasGstin = (company['gstin'] as String?)?.isNotEmpty == true;
                        final hasPan = (company['pan'] as String?)?.isNotEmpty == true;
                        final hasPhone = (company['phone'] as String?)?.isNotEmpty == true;
                        final hasWb = (company['weighbridgeName'] as String?)?.isNotEmpty == true;
                        final hasPort = scalePort.isNotEmpty;
                        final overflowToSecondLine = hasGstin || hasPan;

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: scheme.primary.withValues(alpha: 0.1)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.business_rounded, size: 14, color: scheme.primary),
                                  const SizedBox(width: 8),
                                  Text(company['companyName'] as String? ?? '--', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                                  const SizedBox(width: 12),
                                  Expanded(child: Text('${company['address1'] ?? ''} ${company['address2'] ?? ''}'.trim(), style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
                                  if (hasPhone) Text('Ph: ${company['phone']}', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                                  if (!overflowToSecondLine && hasGstin) ...[const SizedBox(width: 14), Text('GSTIN: ${company['gstin']}', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))],
                                  if (!overflowToSecondLine && hasPan) ...[const SizedBox(width: 14), Text('PAN: ${company['pan']}', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))],
                                  if (hasPort) ...[const SizedBox(width: 14), Text('Port: $scalePort', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))],
                                  if (hasWb) ...[const SizedBox(width: 14), Text('WB: ${company['weighbridgeName']}', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))],
                                ],
                              ),
                              if (overflowToSecondLine) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    if (hasGstin) Text('GSTIN: ${company['gstin']}', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                                    if (hasGstin && hasPan) const SizedBox(width: 14),
                                    if (hasPan) Text('PAN: ${company['pan']}', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(child: _weightBlock('GROSS', w['grossWeight'], fmtDateTime(grossDt), scheme)),
                          const SizedBox(width: 8),
                          Expanded(child: _weightBlock('TARE', w['tareWeight'], fmtDateTime(tareDt), scheme)),
                          const SizedBox(width: 8),
                          Expanded(child: _weightBlock('NET', w['netWeight'], null, scheme, highlight: true)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 5, child: _buildCustomerCard(w, customerName, scheme, onTransferred: () {
                              Navigator.pop(dialogCtx2);
                            })),
                            const SizedBox(width: 8),
                            Expanded(flex: 5, child: _buildOperatorCard(w, scheme)),
                          ],
                        ),
                      ),
                      if (hasCameras) ...[
                        const SizedBox(height: 8),
                        Expanded(
                          child: _buildVisualEvidenceSection(w, scheme, viewMode, (mode) => setDialogState(() => viewMode = mode)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      },  // StatefulBuilder builder
    );   // StatefulBuilder
      },
    );
  }


  Widget _weightBlock(String label, dynamic value, String? dateTime, ColorScheme scheme, {bool highlight = false}) {
    final display = value != null ? '${_formatNum(value)} kg' : '--';
    final isNegative = value is num && value < 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlight ? scheme.primaryContainer.withValues(alpha: 0.35) : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: highlight ? Border.all(color: scheme.primary.withValues(alpha: 0.3), width: 1.5) : null,
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.4)),
              const SizedBox(height: 2),
              Text(display, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isNegative ? scheme.error : highlight ? scheme.primary : scheme.onSurface)),
            ],
          ),
          if (dateTime != null) ...[
            const Spacer(),
            Text(dateTime, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  // ─── Visual Evidence Grid (0–6 weighbridge cameras) ─────────────────────────

  Widget _buildVisualEvidenceSection(Map<String, dynamic> w, ColorScheme scheme, String viewMode, ValueChanged<String> onModeChange) {
    final snapData = _extractSnapshots(w);
    final grossPaths = snapData.grossPaths;
    final tarePaths = snapData.tarePaths;
    final grossLabels = snapData.grossLabels;
    final tareLabels = snapData.tareLabels;
    final bool hasTare = w['status'] == 'completed';

    // Exclude operator and customer from evidence grid (up to 5 weighbridge + customer = 6 max)
    const excludeKeys = ['Operator', 'Customer'];
    final grossTiles = <_TileData>[];
    for (var i = 0; i < grossPaths.length; i++) {
      final label = i < grossLabels.length ? grossLabels[i] : 'Cam ${i + 1}';
      if (excludeKeys.contains(label)) continue;
      grossTiles.add(_TileData(label, _networkImage(grossPaths, i, scheme)));
    }

    final tareTiles = <_TileData>[];
    for (var i = 0; i < tarePaths.length; i++) {
      final label = i < tareLabels.length ? tareLabels[i] : 'Cam ${i + 1}';
      if (excludeKeys.contains(label)) continue;
      tareTiles.add(_TileData(label, hasTare ? _networkImage(tarePaths, i, scheme) : _noImagePlaceholder(Icons.videocam_off_outlined, scheme)));
    }

    if (grossTiles.isEmpty && tareTiles.isEmpty) {
      return const SizedBox.shrink();
    }

    final activeTiles = viewMode == 'tare' ? tareTiles : grossTiles;
    final int count = activeTiles.length;
    final int cols = count <= 1 ? 1 : 2;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(6)),
                child: Icon(Icons.grid_view_rounded, size: 12, color: scheme.primary),
              ),
              const SizedBox(width: 8),
              Text('Visual Evidence', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface)),
              const SizedBox(width: 8),
              Text('$count cameras', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
              const Spacer(),
              if (hasTare) ...[
                _phaseToggle('GROSS', viewMode == 'gross', scheme, () => onModeChange('gross')),
                const SizedBox(width: 4),
                _phaseToggle('TARE', viewMode == 'tare', scheme, () => onModeChange('tare')),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final availH = constraints.maxHeight;
                final availW = constraints.maxWidth;
                if (availH <= 0 || availW <= 0) return const SizedBox.shrink();
                final int gridRows = (count / cols).ceil();
                final double hGaps = 6.0 * (cols - 1);
                final double vGaps = 6.0 * (gridRows - 1);
                final double maxTileW = (availW - hGaps) / cols;
                final double maxTileH = (availH - vGaps) / gridRows;
                final double tileW = (maxTileH * 16 / 9) < maxTileW ? (maxTileH * 16 / 9) : maxTileW;
                final double tileH = tileW * 9 / 16;

                int idx = 0;
                final rowWidgets = <Widget>[];
                for (int r = 0; r < gridRows; r++) {
                  final rowChildren = <Widget>[];
                  for (int c = 0; c < cols && idx < count; c++) {
                    final tile = activeTiles[idx++];
                    rowChildren.add(SizedBox(
                      width: tileW,
                      height: tileH,
                      child: _visualTile(label: tile.label, scheme: scheme, child: tile.child, onTap: () => _showEnlargedTile(ctx, tile.label, tile.child)),
                    ));
                  }
                  rowWidgets.add(Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 0; i < rowChildren.length; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        rowChildren[i],
                      ],
                    ],
                  ));
                }

                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int i = 0; i < rowWidgets.length; i++) ...[
                      if (i > 0) const SizedBox(height: 6),
                      rowWidgets[i],
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _phaseToggle(String label, bool active, ColorScheme scheme, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? scheme.primary : scheme.outlineVariant, width: 1.2),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: active ? scheme.onPrimary : scheme.onSurfaceVariant, letterSpacing: 0.5)),
      ),
    );
  }

  Widget _buildCustomerCard(Map<String, dynamic> w, String customerName, ColorScheme scheme, {VoidCallback? onTransferred}) {
    final customerSnapUrl = _getCustomerSnapshot(w);
    final isArchived = customerName == '[Archived]';
    final archivedFace = w['archivedCustomerFace'] as String?;

    return GestureDetector(
      onTap: isArchived ? null : () => _showCustomerDialog(w, customerName, scheme),
      child: MouseRegion(
        cursor: isArchived ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isArchived ? scheme.surfaceContainerHighest.withValues(alpha: 0.5) : scheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isArchived ? scheme.outlineVariant.withValues(alpha: 0.4) : scheme.outlineVariant.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isArchived && archivedFace != null && archivedFace.isNotEmpty) ...[
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: scheme.surfaceContainerHighest,
                      backgroundImage: MemoryImage(_tryDecodeBase64(archivedFace) ?? Uint8List(0)),
                      onBackgroundImageError: (_, __) {},
                    ),
                    const SizedBox(width: 8),
                  ] else if (isArchived) ...[
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: scheme.errorContainer.withValues(alpha: 0.5),
                      child: Icon(Icons.person_off_rounded, size: 14, color: scheme.error),
                    ),
                    const SizedBox(width: 8),
                  ] else if (customerSnapUrl != null) ...[
                    CircleAvatar(
                      radius: 14,
                      backgroundImage: NetworkImage(customerSnapUrl),
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: Text(
                    isArchived ? '[Archived Customer]' : toTitleCase(customerName.isEmpty ? '--' : customerName),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: isArchived ? scheme.onSurfaceVariant : scheme.onSurface),
                  )),
                  if (!isArchived)
                    Tooltip(
                      message: 'Transfer to another customer',
                      child: InkWell(
                        onTap: () => _showTransferWeighmentDialog(w, onTransferred),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.swap_horiz_rounded, size: 16, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.phone_outlined, size: 13, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(isArchived ? 'Redacted' : (w['customerPhone'] as String? ?? '--'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontStyle: isArchived ? FontStyle.italic : null)),
                  const SizedBox(width: 14),
                  Icon(Icons.inventory_2_outlined, size: 13, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(toTitleCase(w['material'] as String? ?? '--'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                  const Spacer(),
                  if (!isArchived)
                    Icon(Icons.open_in_new_rounded, size: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _getCustomerSnapshot(Map<String, dynamic> w) {
    final csRaw = w['cameraSnapshots'] as Map<String, dynamic>?;
    if (csRaw == null) return null;
    final grossMap = csRaw['gross'] as Map<String, dynamic>?;
    final tareMap = csRaw['tare'] as Map<String, dynamic>?;
    final url = grossMap?['customer']?.toString() ?? tareMap?['customer']?.toString();
    return (url != null && url.isNotEmpty) ? url : null;
  }

  void _showCustomerDialog(Map<String, dynamic> w, String customerName, ColorScheme scheme) {
    final customerSnapUrl = _getCustomerSnapshot(w);
    final db = ref.read(firestorePathsProvider);
    final phone = w['customerPhone'] as String? ?? '';

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  ),
                  child: Row(
                    children: [
                      if (customerSnapUrl != null) ...[
                        CircleAvatar(
                          radius: 22,
                          backgroundImage: NetworkImage(customerSnapUrl),
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                        const SizedBox(width: 12),
                      ] else ...[
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: scheme.primaryContainer,
                          child: Icon(Icons.person_rounded, size: 22, color: scheme.primary),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(toTitleCase(customerName.isEmpty ? 'Unknown' : customerName), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                            if (phone.isNotEmpty)
                              Text(phone, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, size: 20)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (customerSnapUrl != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.network(customerSnapUrl, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                FutureBuilder<QuerySnapshot>(
                  future: db.customers.where('name', isEqualTo: customerName).limit(1).get(),
                  builder: (ctx, snap) {
                    if (snap.connectionState != ConnectionState.done || snap.data == null || snap.data!.docs.isEmpty) {
                      return const SizedBox(height: 8);
                    }
                    final cust = snap.data!.docs.first.data() as Map<String, dynamic>;
                    final address = cust['address'] as String? ?? '';
                    final totalWeighments = cust['totalWeighments'] as int? ?? 0;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            if (address.isNotEmpty) ...[
                              Icon(Icons.location_on_outlined, size: 12, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Flexible(child: Text(address, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 14),
                            ],
                            const Spacer(),
                            Icon(Icons.scale_outlined, size: 12, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text('$totalWeighments weighments', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Row(
                    children: [
                      Text('Recent Activity', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                      const Spacer(),
                      Text('by this customer', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                SizedBox(
                  height: 200,
                  child: FutureBuilder<QuerySnapshot>(
                    future: db.weighments
                        .where('customerName', isEqualTo: customerName)
                        .orderBy('createdAt', descending: true)
                        .limit(8)
                        .get(),
                    builder: (ctx, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
                      }
                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return Center(child: Text('No history', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.5))));
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.15)),
                        itemBuilder: (_, i) {
                          final d = docs[i].data() as Map<String, dynamic>;
                          final ts = d['createdAt'];
                          final date = ts is Timestamp ? DateFormat('dd MMM yy').format(ts.toDate()) : '--';
                          final status = d['status'] as String? ?? '';
                          final net = d['netWeight'];
                          final material = d['material'] as String? ?? '';
                          final vehicle = d['vehicleNumber'] as String? ?? '';
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Text(date, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                                const SizedBox(width: 10),
                                Text(vehicle, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                                const SizedBox(width: 10),
                                Text(toTitleCase(material), style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                                const Spacer(),
                                if (net != null)
                                  Text('${_formatNum(net)} kg', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: net is num && net < 0 ? scheme.error : scheme.primary)),
                                const SizedBox(width: 8),
                                Container(
                                  width: 6, height: 6,
                                  decoration: BoxDecoration(
                                    color: status == 'completed' ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTransferWeighmentDialog(Map<String, dynamic> w, VoidCallback? onTransferred) {
    final scheme = Theme.of(context).colorScheme;
    final db = ref.read(firestorePathsProvider);
    final weighmentId = w['id'] as String;
    final currentCustomer = w['customerName'] as String? ?? '';
    String searchQuery = '';
    String? selectedCustomerId;
    String? selectedCustomerName;
    String? selectedCustomerPhone;
    bool isTransferring = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.swap_horiz_rounded, size: 20, color: scheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Transfer Weighment', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                                Text('RST #${w['rstNumber'] ?? '--'} · ${w['vehicleNumber'] ?? '--'}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, size: 20)),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: Row(
                        children: [
                          Text('From: ', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: scheme.errorContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(6)),
                            child: Text(toTitleCase(currentCustomer), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onErrorContainer)),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, size: 14, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          if (selectedCustomerName != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(6)),
                              child: Text(toTitleCase(selectedCustomerName!), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onPrimaryContainer)),
                            )
                          else
                            Text('Select target', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: TextField(
                        onChanged: (v) => setState(() => searchQuery = v),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Search customer by name or phone...',
                          hintStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                          prefixIcon: Icon(Icons.search_rounded, size: 18, color: scheme.onSurfaceVariant),
                          filled: true,
                          fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    SizedBox(
                      height: 220,
                      child: FutureBuilder<QuerySnapshot>(
                        future: db.customers.orderBy('name').limit(100).get(),
                        builder: (ctx3, snap) {
                          if (snap.connectionState != ConnectionState.done) {
                            return const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
                          }
                          final docs = snap.data?.docs ?? [];
                          final filtered = docs.where((d) {
                            final data = d.data() as Map<String, dynamic>;
                            final name = (data['name'] as String? ?? '').toLowerCase();
                            final phone = (data['phone'] as String? ?? '').toLowerCase();
                            if (name == currentCustomer.toLowerCase()) return false;
                            if (searchQuery.isEmpty) return true;
                            return name.contains(searchQuery.toLowerCase()) || phone.contains(searchQuery.toLowerCase());
                          }).toList();

                          if (filtered.isEmpty) {
                            return Center(child: Text('No matching customers', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.5))));
                          }

                          return ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.15)),
                            itemBuilder: (_, i) {
                              final d = filtered[i].data() as Map<String, dynamic>;
                              final id = filtered[i].id;
                              final name = d['name'] as String? ?? '';
                              final phone = d['phone'] as String? ?? '';
                              final isSelected = id == selectedCustomerId;
                              return InkWell(
                                onTap: () => setState(() {
                                  selectedCustomerId = id;
                                  selectedCustomerName = name;
                                  selectedCustomerPhone = phone;
                                }),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSelected ? scheme.primaryContainer.withValues(alpha: 0.3) : null,
                                    borderRadius: BorderRadius.circular(8),
                                    border: isSelected ? Border.all(color: scheme.primary.withValues(alpha: 0.4)) : null,
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundColor: isSelected ? scheme.primary : scheme.surfaceContainerHighest,
                                        child: isSelected
                                            ? Icon(Icons.check_rounded, size: 14, color: scheme.onPrimary)
                                            : Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(toTitleCase(name), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                                            if (phone.isNotEmpty) Text(phone, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                                          ],
                                        ),
                                      ),
                                      if (isSelected)
                                        Icon(Icons.check_circle_rounded, size: 16, color: scheme.primary),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                          const SizedBox(width: 6),
                          Expanded(child: Text('This updates the customer on this weighment only.', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)))),
                          const SizedBox(width: 12),
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(fontSize: 13))),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: selectedCustomerId == null || isTransferring
                                ? null
                                : () async {
                                    setState(() => isTransferring = true);
                                    final targetName = selectedCustomerName!;
                                    await db.weighments.doc(weighmentId).update({
                                      'customerName': targetName,
                                      'customerPhone': selectedCustomerPhone ?? '',
                                    });
                                    if (!ctx.mounted) return;
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(content: Text('Weighment transferred to ${toTitleCase(targetName)}')),
                                    );
                                    onTransferred?.call();
                                  },
                            child: isTransferring
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Transfer', style: TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOperatorCard(Map<String, dynamic> w, ColorScheme scheme) {
    final operatorSnapUrl = _getOperatorSnapshot(w);
    return GestureDetector(
      onTap: () => _showOperatorDialog(w, scheme),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (operatorSnapUrl != null) ...[
                    CircleAvatar(
                      radius: 14,
                      backgroundImage: NetworkImage(operatorSnapUrl),
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: Text(toTitleCase(w['operatorName'] as String? ?? '--'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scheme.onSurface))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: scheme.secondaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(4)),
                    child: Text((w['operatorRole'] as String? ?? 'OPERATOR').toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSecondaryContainer, letterSpacing: 0.5)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.computer_outlined, size: 13, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('${w['deviceId'] ?? '--'} / ${Platform.localHostname}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  if (operatorSnapUrl != null) ...[
                    const Spacer(),
                    Icon(Icons.photo_camera_rounded, size: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                    const SizedBox(width: 3),
                    Text('Tap to view', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOperatorDialog(Map<String, dynamic> w, ColorScheme scheme) {
    final operatorSnapUrl = _getOperatorSnapshot(w);
    final db = ref.read(firestorePathsProvider);
    final operatorName = w['operatorName'] as String? ?? '';
    final operatorId = w['operatorId'] as String? ?? '';
    final operatorRole = w['operatorRole'] as String? ?? 'operator';

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  ),
                  child: Row(
                    children: [
                      if (operatorSnapUrl != null) ...[
                        CircleAvatar(
                          radius: 22,
                          backgroundImage: NetworkImage(operatorSnapUrl),
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                        const SizedBox(width: 12),
                      ] else ...[
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: scheme.secondaryContainer,
                          child: Icon(Icons.badge_rounded, size: 22, color: scheme.secondary),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(toTitleCase(operatorName.isEmpty ? 'Unknown' : operatorName), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                            Text(operatorRole.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant, letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                      IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, size: 20)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (operatorSnapUrl != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.network(operatorSnapUrl, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                // Operator info from Firestore
                FutureBuilder<DocumentSnapshot>(
                  future: operatorId.isNotEmpty ? db.operators.doc(operatorId).get() : null,
                  builder: (ctx, snap) {
                    if (snap.connectionState != ConnectionState.done || snap.data == null || !snap.data!.exists) {
                      return const SizedBox(height: 8);
                    }
                    final op = snap.data!.data() as Map<String, dynamic>;
                    final email = op['email'] as String? ?? '';
                    final phone = op['phone'] as String? ?? '';
                    final verified = op['isVerified'] == true;
                    final loginCount = op['loginCount'] as int? ?? 0;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            if (email.isNotEmpty) ...[
                              Icon(Icons.email_outlined, size: 12, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(email, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                              const SizedBox(width: 14),
                            ],
                            if (phone.isNotEmpty) ...[
                              Icon(Icons.phone_outlined, size: 12, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(phone, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                            ],
                            const Spacer(),
                            if (verified) ...[
                              Icon(Icons.verified_rounded, size: 13, color: const Color(0xFF22C55E)),
                              const SizedBox(width: 4),
                              Text('Verified', style: TextStyle(fontSize: 10, color: const Color(0xFF22C55E), fontWeight: FontWeight.w600)),
                              const SizedBox(width: 12),
                            ],
                            Icon(Icons.login_rounded, size: 12, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text('$loginCount logins', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                // Recent activity
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Row(
                    children: [
                      Text('Recent Activity', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                      const Spacer(),
                      Text('by this operator', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                SizedBox(
                  height: 200,
                  child: FutureBuilder<QuerySnapshot>(
                    future: db.weighments
                        .where('operatorId', isEqualTo: operatorId)
                        .orderBy('createdAt', descending: true)
                        .limit(8)
                        .get(),
                    builder: (ctx, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
                      }
                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return Center(child: Text('No activity', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.5))));
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.15)),
                        itemBuilder: (_, i) {
                          final d = docs[i].data() as Map<String, dynamic>;
                          final ts = d['createdAt'];
                          final date = ts is Timestamp ? DateFormat('dd MMM yy HH:mm').format(ts.toDate()) : '--';
                          final status = d['status'] as String? ?? '';
                          final net = d['netWeight'];
                          final material = d['material'] as String? ?? '';
                          final vehicle = d['vehicleNumber'] as String? ?? '';
                          final customer = d['customerName'] as String? ?? '';
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Text(date, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                                const SizedBox(width: 8),
                                Text(vehicle, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                                const SizedBox(width: 8),
                                Expanded(child: Text('${toTitleCase(material)} • ${toTitleCase(customer)}', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))),
                                if (net != null)
                                  Text('${_formatNum(net)} kg', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: net is num && net < 0 ? scheme.error : scheme.primary)),
                                const SizedBox(width: 8),
                                Container(
                                  width: 6, height: 6,
                                  decoration: BoxDecoration(
                                    color: status == 'completed' ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String? _getOperatorSnapshot(Map<String, dynamic> w) {
    final csRaw = w['cameraSnapshots'] as Map<String, dynamic>?;
    if (csRaw == null) return null;
    final grossMap = csRaw['gross'] as Map<String, dynamic>?;
    final tareMap = csRaw['tare'] as Map<String, dynamic>?;
    final url = grossMap?['operator']?.toString() ?? tareMap?['operator']?.toString();
    return (url != null && url.isNotEmpty) ? url : null;
  }


  Widget _visualTile({required String label, required ColorScheme scheme, required Widget child, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: scheme.surfaceContainerHighest),
            child,
            Positioned(
              left: 5, top: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(label, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEnlargedTile(BuildContext context, String label, Widget child) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(ctx).size.width * 0.7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: scheme.surfaceContainerHighest),
                      child,
                      Positioned(
                        left: 12, top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
                          child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      Positioned(
                        right: 8, top: 8,
                        child: IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.5)),
                          icon: const Icon(Icons.close, size: 18, color: Colors.white),
                        ),
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

  void _showEnlargedBarcode(BuildContext context, Map<String, dynamic> w, Map<String, dynamic> company) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(40),
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Container(
            width: 600,
            height: 180,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 16)],
            ),
            child: _buildBarcodeWidget(w, company, scheme),
          ),
        ),
      ),
    );
  }


  Widget _networkImage(List<String> paths, int i, ColorScheme scheme) {
    if (i >= paths.length) {
      return _noFeedPlaceholder(scheme);
    }
    return Image.network(paths[i], fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _noImagePlaceholder(Icons.broken_image_outlined, scheme),
    );
  }

  Widget _noFeedPlaceholder(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam_off_outlined, size: 22, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
          const SizedBox(height: 4),
          Text('No capture', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
        ],
      ),
    );
  }

  Widget _noImagePlaceholder(IconData icon, ColorScheme scheme) {
    return Center(child: Icon(icon, size: 28, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)));
  }

  Widget _buildBarcodeWidget(Map<String, dynamic> w, Map<String, dynamic> company, ColorScheme scheme) {
    final parts = <String>[];
    void add(String key, dynamic val) {
      final v = val?.toString().trim() ?? '';
      if (v.isNotEmpty && v != '--') parts.add('$key=$v');
    }
    add('rst', w['rstNumber']);
    add('vehicle', w['vehicleNumber']);
    add('customer', w['customerName']);
    add('material', w['material']);
    add('gross', w['grossWeight']);
    add('tare', w['tareWeight']);
    add('net', w['netWeight']);
    add('operator', w['operatorName']);
    add('weighbridge', company['weighbridgeName']);

    final barcodeData = parts.join('|');
    if (barcodeData.isEmpty) {
      return Center(child: Text('No data', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)));
    }

    return BarcodeWidget(
      barcode: Barcode.pdf417(),
      data: barcodeData,
      drawText: false,
    );
  }

  String _formatNum(dynamic v) {
    if (v == null) return '--';
    final n = v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0;
    final str = n.toString();
    if (str.length <= 3) return str;
    final lastThree = str.substring(str.length - 3);
    final rest = str.substring(0, str.length - 3);
    final formatted = rest.replaceAllMapped(RegExp(r'(\d)(?=(\d{2})+$)'), (m) => '${m[1]},');
    return '$formatted,$lastThree';
  }
}

class _TileData {
  final String label;
  final Widget child;
  const _TileData(this.label, this.child);
}

class _SnapshotData {
  final List<String> grossPaths;
  final List<String> tarePaths;
  final List<String> grossLabels;
  final List<String> tareLabels;
  const _SnapshotData({required this.grossPaths, required this.tarePaths, required this.grossLabels, required this.tareLabels});
}

_SnapshotData _extractSnapshots(Map<String, dynamic> w) {
  final csRaw = w['cameraSnapshots'] as Map<String, dynamic>? ?? {};
  final labelsMap = w['cameraLabels'] is Map ? (w['cameraLabels'] as Map).cast<String, dynamic>() : <String, dynamic>{};
  const defaultOrder = ['cam1', 'cam2', 'cam3', 'cam4', 'cam5', 'operator', 'customer'];

  List<String> orderedKeys(Map<String, dynamic> phaseMap) {
    final keys = defaultOrder.where((k) => phaseMap.containsKey(k)).toList();
    for (final k in phaseMap.keys) {
      if (!keys.contains(k)) keys.add(k);
    }
    return keys;
  }

  final grossMap = csRaw['gross'] is Map ? (csRaw['gross'] as Map).cast<String, dynamic>() : <String, dynamic>{};
  final tareMap = csRaw['tare'] is Map ? (csRaw['tare'] as Map).cast<String, dynamic>() : <String, dynamic>{};
  final grossKeys = orderedKeys(grossMap);
  final tareKeys = orderedKeys(tareMap);

  return _SnapshotData(
    grossPaths: grossKeys.map((k) => grossMap[k]?.toString() ?? '').toList(),
    tarePaths: tareKeys.map((k) => tareMap[k]?.toString() ?? '').toList(),
    grossLabels: grossKeys.map((k) => labelsMap[k]?.toString() ?? k).toList(),
    tareLabels: tareKeys.map((k) => labelsMap[k]?.toString() ?? k).toList(),
  );
}

// "Print" — uses default printer assignment from settings (one-click action)
class _QuickPrintButton extends ConsumerWidget {
  final String weighmentId;
  final void Function(String message, bool isError)? onResult;

  const _QuickPrintButton({required this.weighmentId, this.onResult});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(printSettingsProvider).valueOrNull ?? {};
    final printers = (settings['printers'] as List?)
        ?.map((p) => Map<String, dynamic>.from(p as Map))
        .toList() ?? [];

    if (printers.isEmpty) {
      return FilledButton.tonal(
        onPressed: () => onResult?.call('No printers configured. Go to Settings → Printing.', true),
        child: Text('Print', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
      );
    }

    return FilledButton(
      onPressed: () => _doPrint(context, ref),
      child: const Text('Print', style: TextStyle(fontSize: 13)),
    );
  }

  void _doPrint(BuildContext context, WidgetRef ref) async {
    final printService = ref.read(printServiceProvider);
    final result = await printService.printWeighment(weighmentId: weighmentId);
    if (context.mounted) {
      if (result.success) {
        final msg = result.warning != null
            ? 'Printed to default printer — ${result.warning}'
            : 'Printed to default printer';
        onResult?.call(msg, result.warning != null);
      } else {
        onResult?.call('Print failed: ${result.error}', true);
      }
    }
  }
}

// "Print To..." — shows all configured printers with type & paper size
class _PrintToButton extends ConsumerWidget {
  final String weighmentId;
  final void Function(String message, bool isError)? onResult;

  const _PrintToButton({required this.weighmentId, this.onResult});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(printSettingsProvider).valueOrNull ?? {};
    final printers = (settings['printers'] as List?)
        ?.map((p) => Map<String, dynamic>.from(p as Map))
        .toList() ?? [];

    if (printers.isEmpty) return const SizedBox.shrink();

    final options = <_PrintOption>[];
    for (final p in printers) {
      final type = p['type'] as String? ?? 'normal';
      final nickname = p['nickname'] as String? ?? '';
      final sysName = p['name'] as String? ?? '';
      final displayName = nickname.isNotEmpty ? nickname : sysName;
      final trayMapping = p['trayMapping'] as Map<String, dynamic>?;
      final paperSize = trayMapping != null && trayMapping.isNotEmpty
          ? (trayMapping.values.first as String? ?? p['paperSize'] as String? ?? '')
          : (p['paperSize'] as String? ?? '');
      final thermalWidth = p['thermalWidth'] as String? ?? '';

      final String subtitle;
      final IconData icon;
      final String printType;
      switch (type) {
        case 'dotMatrix':
          subtitle = 'Dot Matrix';
          icon = Icons.receipt_long_rounded;
          printType = 'dm';
        case 'thermal':
          subtitle = thermalWidth.isNotEmpty ? 'Thermal · $thermalWidth' : 'Thermal';
          icon = Icons.receipt_rounded;
          printType = 'thermal';
        default:
          subtitle = paperSize.isNotEmpty ? 'PDF · $paperSize' : 'PDF';
          icon = Icons.picture_as_pdf_rounded;
          printType = 'normal';
      }

      options.add(_PrintOption(
        type: printType,
        label: displayName,
        subtitle: subtitle,
        icon: icon,
        printerName: displayName,
      ));
    }

    final savePdfOption = _PrintOption(
      type: 'share',
      label: 'Save PDF',
      subtitle: 'Share or save to file',
      icon: Icons.ios_share_rounded,
    );

    return PopupMenuButton<_PrintOption>(
      onSelected: (option) => _doPrint(context, ref, option),
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 8,
      itemBuilder: (_) => [
        ...options.map((o) => PopupMenuItem(
          value: o,
          height: 48,
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withAlpha(120),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(o.icon, size: 16, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(o.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(o.subtitle, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        )),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: savePdfOption,
          height: 48,
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer.withAlpha(120),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.ios_share_rounded, size: 16, color: scheme.tertiary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Save PDF', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text('Share or save to file', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('Print to...', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant)),
      ),
    );
  }

  void _doPrint(BuildContext context, WidgetRef ref, _PrintOption option) async {
    final printService = ref.read(printServiceProvider);
    if (option.type == 'share') {
      final result = await printService.printWeighment(
        weighmentId: weighmentId,
        printerType: 'normal',
        printerName: '__share__',
      );
      if (!context.mounted) return;
      if (result.success && result.pdfBytes != null) {
        final tmpFile = File('${Directory.systemTemp.path}/weighment_$weighmentId.pdf');
        await tmpFile.writeAsBytes(result.pdfBytes!);
        await Process.run('open', ['-R', tmpFile.path]);
        final msg = result.warning != null
            ? 'PDF saved — ${result.warning}'
            : 'PDF saved — opened in Finder';
        onResult?.call(msg, result.warning != null);
      } else {
        onResult?.call('PDF generation failed: ${result.error}', true);
      }
      return;
    }
    final result = await printService.printWeighment(
      weighmentId: weighmentId,
      printerType: option.type,
      printerName: option.printerName,
    );
    if (context.mounted) {
      if (result.success) {
        final msg = result.warning != null
            ? 'Printed to ${option.label} — ${result.warning}'
            : 'Printed to ${option.label}';
        onResult?.call(msg, result.warning != null);
      } else {
        onResult?.call('Print failed: ${result.error}', true);
      }
    }
  }
}

class _PrintOption {
  final String type;
  final String label;
  final String subtitle;
  final IconData icon;
  final String? printerName;
  const _PrintOption({required this.type, required this.label, required this.subtitle, required this.icon, this.printerName});
}

class _StandaloneWeighmentDetail extends ConsumerStatefulWidget {
  final Map<String, dynamic> weighment;
  const _StandaloneWeighmentDetail({required this.weighment});

  @override
  ConsumerState<_StandaloneWeighmentDetail> createState() => _StandaloneWeighmentDetailState();
}

class _StandaloneWeighmentDetailState extends ConsumerState<_StandaloneWeighmentDetail> {
  @override
  Widget build(BuildContext context) {
    final w = widget.weighment;
    final scheme = Theme.of(context).colorScheme;
    final grossDt = w['grossDateTime'] is Timestamp ? (w['grossDateTime'] as Timestamp).toDate() : null;
    final tareDt = w['tareDateTime'] is Timestamp ? (w['tareDateTime'] as Timestamp).toDate() : null;
    String fmtDateTime(DateTime? dt) => dt != null ? DateFormat('dd/MM/yyyy HH:mm').format(dt) : '--';
    String fmtNum(dynamic v) {
      if (v == null) return '--';
      final n = v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0;
      final str = n.toString();
      if (str.length <= 3) return str;
      final lastThree = str.substring(str.length - 3);
      final rest = str.substring(0, str.length - 3);
      final formatted = rest.replaceAllMapped(RegExp(r'(\d)(?=(\d{2})+$)'), (m) => '${m[1]},');
      return '$formatted,$lastThree';
    }

    final customerName = w['customerName'] as String? ?? '';
    final snapData = _extractSnapshots(w);
    const excludeLabels = ['Operator', 'Customer'];
    int countEvidence(List<String> labels) => labels.where((l) => !excludeLabels.contains(l)).length;
    final int grossEvidence = countEvidence(snapData.grossLabels);
    final int tareEvidence = countEvidence(snapData.tareLabels);
    final int maxEvidence = grossEvidence > tareEvidence ? grossEvidence : tareEvidence;
    final bool hasCameras = maxEvidence > 0;

    final screenH = MediaQuery.of(context).size.height;
    final double dialogH = screenH * 0.96;

    return Dialog(
      alignment: Alignment.topCenter,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
      child: SizedBox(
        width: 900,
        height: dialogH,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 16, 14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
                    child: Text('#${w['rstNumber'] ?? '--'}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                    child: Text(w['vehicleNumber'] as String? ?? '--', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface, letterSpacing: 0.3)),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 140,
                    height: 28,
                    child: _buildStandaloneBarcode(w, scheme),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: w['status'] == 'completed' ? scheme.primaryContainer.withValues(alpha: 0.5) : scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      w['status'] == 'completed' ? 'Done' : 'Pending',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: w['status'] == 'completed' ? scheme.primary : scheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 22)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _standaloneWeightBlock('GROSS', w['grossWeight'], fmtDateTime(grossDt), scheme, fmtNum, false),
                        const SizedBox(width: 8),
                        _standaloneWeightBlock('TARE', w['tareWeight'], fmtDateTime(tareDt), scheme, fmtNum, false),
                        const SizedBox(width: 8),
                        _standaloneWeightBlock('NET', w['netWeight'], null, scheme, fmtNum, true),
                      ],
                    ),
                    const SizedBox(height: 10),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Customer card (non-clickable, just info)
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: customerName == '[Archived]' ? scheme.surfaceContainerHighest.withValues(alpha: 0.5) : scheme.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (customerName == '[Archived]' && (w['archivedCustomerFace'] as String?)?.isNotEmpty == true) ...[
                                        CircleAvatar(
                                          radius: 12,
                                          backgroundColor: scheme.surfaceContainerHighest,
                                          backgroundImage: MemoryImage(_tryDecodeBase64(w['archivedCustomerFace'] as String) ?? Uint8List(0)),
                                          onBackgroundImageError: (_, __) {},
                                        ),
                                        const SizedBox(width: 8),
                                      ] else ...[
                                        Icon(customerName == '[Archived]' ? Icons.person_off_rounded : Icons.person_rounded, size: 14, color: customerName == '[Archived]' ? scheme.error : scheme.onSurfaceVariant),
                                        const SizedBox(width: 8),
                                      ],
                                      Expanded(child: Text(
                                        customerName == '[Archived]' ? '[Archived Customer]' : toTitleCase(customerName),
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: customerName == '[Archived]' ? scheme.onSurfaceVariant : scheme.onSurface),
                                      )),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      if (customerName != '[Archived]' && (w['customerPhone'] as String? ?? '').isNotEmpty) ...[
                                        Icon(Icons.phone_outlined, size: 12, color: scheme.onSurfaceVariant),
                                        const SizedBox(width: 4),
                                        Text(w['customerPhone'] as String? ?? '', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                                        const SizedBox(width: 14),
                                      ],
                                      Icon(Icons.inventory_2_outlined, size: 12, color: scheme.onSurfaceVariant),
                                      const SizedBox(width: 4),
                                      Text(toTitleCase(w['material'] as String? ?? '--'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Operator card (clickable)
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _showStandaloneOperatorDialog(context, w, scheme),
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2))),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.badge_rounded, size: 14, color: scheme.onSurfaceVariant),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text(toTitleCase(w['operatorName'] as String? ?? '--'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface))),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(color: scheme.secondaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(4)),
                                            child: Text((w['operatorRole'] as String? ?? 'operator').toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSecondaryContainer, letterSpacing: 0.3)),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(Icons.computer_outlined, size: 12, color: scheme.onSurfaceVariant),
                                          const SizedBox(width: 4),
                                          Text('${w['deviceId'] ?? '--'} / ${Platform.localHostname}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                                          const Spacer(),
                                          Icon(Icons.open_in_new_rounded, size: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasCameras) ...[
                      const SizedBox(height: 10),
                      Expanded(
                        child: _StandaloneCameraGrid(snapData: snapData, hasTare: w['status'] == 'completed', scheme: scheme, grossEvidence: grossEvidence, tareEvidence: tareEvidence),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStandaloneBarcode(Map<String, dynamic> w, ColorScheme scheme) {
    final parts = <String>[];
    void add(String key, dynamic val) {
      final v = val?.toString().trim() ?? '';
      if (v.isNotEmpty && v != '--') parts.add('$key=$v');
    }
    add('rst', w['rstNumber']);
    add('vehicle', w['vehicleNumber']);
    add('customer', w['customerName']);
    add('material', w['material']);
    add('gross', w['grossWeight']);
    add('tare', w['tareWeight']);
    add('net', w['netWeight']);
    add('operator', w['operatorName']);
    final barcodeData = parts.join('|');
    if (barcodeData.isEmpty) {
      return Center(child: Text('No data', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)));
    }
    return BarcodeWidget(barcode: Barcode.pdf417(), data: barcodeData, drawText: false);
  }

  void _showStandaloneOperatorDialog(BuildContext ctx, Map<String, dynamic> w, ColorScheme scheme) {
    final db = ref.read(firestorePathsProvider);
    final operatorName = w['operatorName'] as String? ?? '';
    final operatorId = w['operatorId'] as String? ?? '';
    final operatorRole = w['operatorRole'] as String? ?? 'operator';
    final csRaw = w['cameraSnapshots'] as Map<String, dynamic>?;
    final grossMap = csRaw?['gross'] as Map<String, dynamic>?;
    final tareMap = csRaw?['tare'] as Map<String, dynamic>?;
    final operatorSnapUrl = grossMap?['operator']?.toString() ?? tareMap?['operator']?.toString();

    showDialog(
      context: ctx,
      builder: (dCtx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: SizedBox(
            width: 588,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  ),
                  child: Row(
                    children: [
                      if (operatorSnapUrl != null && operatorSnapUrl.isNotEmpty) ...[
                        CircleAvatar(radius: 22, backgroundImage: NetworkImage(operatorSnapUrl), backgroundColor: scheme.surfaceContainerHighest),
                        const SizedBox(width: 12),
                      ] else ...[
                        CircleAvatar(radius: 22, backgroundColor: scheme.secondaryContainer, child: Icon(Icons.badge_rounded, size: 22, color: scheme.secondary)),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(toTitleCase(operatorName.isEmpty ? 'Unknown' : operatorName), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                            Text(operatorRole.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant, letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                      IconButton(onPressed: () => Navigator.pop(dCtx), icon: const Icon(Icons.close, size: 20)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (operatorSnapUrl != null && operatorSnapUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AspectRatio(aspectRatio: 16 / 9, child: Image.network(operatorSnapUrl, fit: BoxFit.cover)),
                    ),
                  ),
                FutureBuilder<DocumentSnapshot>(
                  future: operatorId.isNotEmpty ? db.operators.doc(operatorId).get() : null,
                  builder: (_, snap) {
                    if (snap.connectionState != ConnectionState.done || snap.data == null || !snap.data!.exists) return const SizedBox(height: 8);
                    final op = snap.data!.data() as Map<String, dynamic>;
                    final email = op['email'] as String? ?? '';
                    final phone = op['phone'] as String? ?? '';
                    final verified = op['isVerified'] == true;
                    final loginCount = op['loginCount'] as int? ?? 0;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          children: [
                            if (email.isNotEmpty) ...[
                              Icon(Icons.email_outlined, size: 12, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(email, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                              const SizedBox(width: 14),
                            ],
                            if (phone.isNotEmpty) ...[
                              Icon(Icons.phone_outlined, size: 12, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(phone, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                            ],
                            const Spacer(),
                            if (verified) ...[
                              Icon(Icons.verified_rounded, size: 13, color: const Color(0xFF22C55E)),
                              const SizedBox(width: 4),
                              Text('Verified', style: TextStyle(fontSize: 10, color: const Color(0xFF22C55E), fontWeight: FontWeight.w600)),
                              const SizedBox(width: 12),
                            ],
                            Icon(Icons.login_rounded, size: 12, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text('$loginCount logins', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Row(
                    children: [
                      Text('Recent Activity', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                      const Spacer(),
                      Text('by this operator', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                SizedBox(
                  height: 180,
                  child: FutureBuilder<QuerySnapshot>(
                    future: db.weighments.where('operatorId', isEqualTo: operatorId).orderBy('createdAt', descending: true).limit(8).get(),
                    builder: (_, snap) {
                      if (snap.connectionState != ConnectionState.done) return const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) return Center(child: Text('No activity', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.5))));
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.15)),
                        itemBuilder: (_, i) {
                          final d = docs[i].data() as Map<String, dynamic>;
                          final ts = d['createdAt'];
                          final date = ts is Timestamp ? DateFormat('dd MMM yy HH:mm').format(ts.toDate()) : '--';
                          final status = d['status'] as String? ?? '';
                          final net = d['netWeight'];
                          final vehicle = d['vehicleNumber'] as String? ?? '';
                          final customer = d['customerName'] as String? ?? '';
                          final material = d['material'] as String? ?? '';
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Text(date, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                                const SizedBox(width: 8),
                                Text(vehicle, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                                const SizedBox(width: 8),
                                Expanded(child: Text('${toTitleCase(material)} • ${toTitleCase(customer)}', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))),
                                if (net != null) Text('$net kg', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.primary)),
                                const SizedBox(width: 8),
                                Container(width: 6, height: 6, decoration: BoxDecoration(color: status == 'completed' ? const Color(0xFF22C55E) : const Color(0xFFF59E0B), shape: BoxShape.circle)),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _standaloneWeightBlock(String label, dynamic value, String? dateTime, ColorScheme scheme, String Function(dynamic) fmtNum, bool highlight) {
    final display = value != null ? '${fmtNum(value)} kg' : '--';
    final isNegative = value is num && value < 0;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: highlight ? scheme.primaryContainer.withValues(alpha: 0.35) : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: highlight ? Border.all(color: scheme.primary.withValues(alpha: 0.3), width: 1.5) : null,
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.4)),
                const SizedBox(height: 2),
                Text(display, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isNegative ? scheme.error : highlight ? scheme.primary : scheme.onSurface)),
              ],
            ),
            if (dateTime != null) ...[
              const Spacer(),
              Text(dateTime, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

class _StandaloneCameraGrid extends StatefulWidget {
  final _SnapshotData snapData;
  final bool hasTare;
  final ColorScheme scheme;
  final int grossEvidence;
  final int tareEvidence;

  const _StandaloneCameraGrid({required this.snapData, required this.hasTare, required this.scheme, required this.grossEvidence, required this.tareEvidence});

  @override
  State<_StandaloneCameraGrid> createState() => _StandaloneCameraGridState();
}

class _StandaloneCameraGridState extends State<_StandaloneCameraGrid> {
  late String _viewMode;

  @override
  void initState() {
    super.initState();
    _viewMode = widget.snapData.grossPaths.isNotEmpty ? 'gross' : 'tare';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;
    const excludeKeys = ['Operator', 'Customer'];

    final grossTiles = <MapEntry<String, String>>[];
    for (var i = 0; i < widget.snapData.grossPaths.length; i++) {
      final label = i < widget.snapData.grossLabels.length ? widget.snapData.grossLabels[i] : 'Cam ${i + 1}';
      if (excludeKeys.contains(label)) continue;
      grossTiles.add(MapEntry(label, widget.snapData.grossPaths[i]));
    }

    final tareTiles = <MapEntry<String, String>>[];
    for (var i = 0; i < widget.snapData.tarePaths.length; i++) {
      final label = i < widget.snapData.tareLabels.length ? widget.snapData.tareLabels[i] : 'Cam ${i + 1}';
      if (excludeKeys.contains(label)) continue;
      tareTiles.add(MapEntry(label, widget.snapData.tarePaths[i]));
    }

    final activeTiles = _viewMode == 'tare' ? tareTiles : grossTiles;
    final count = activeTiles.length;
    if (count == 0) return const SizedBox.shrink();
    final int cols = count <= 1 ? 1 : 2;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.grid_view_rounded, size: 12, color: scheme.primary),
              const SizedBox(width: 8),
              Text('Visual Evidence', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface)),
              const SizedBox(width: 8),
              Text('$count cameras', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
              const Spacer(),
              if (widget.hasTare) ...[
                _toggle('GROSS', _viewMode == 'gross', () => setState(() => _viewMode = 'gross'), scheme),
                const SizedBox(width: 4),
                _toggle('TARE', _viewMode == 'tare', () => setState(() => _viewMode = 'tare'), scheme),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final availH = constraints.maxHeight;
                final availW = constraints.maxWidth;
                if (availH <= 0 || availW <= 0) return const SizedBox.shrink();
                final int gridRows = (count / cols).ceil();
                final double hGaps = 6.0 * (cols - 1);
                final double vGaps = 6.0 * (gridRows - 1);
                final double maxTileW = (availW - hGaps) / cols;
                final double maxTileH = (availH - vGaps) / gridRows;
                final double tileW = (maxTileH * 16 / 9) < maxTileW ? (maxTileH * 16 / 9) : maxTileW;
                final double tileH = tileW * 9 / 16;

                int idx = 0;
                final rowWidgets = <Widget>[];
                for (int r = 0; r < gridRows; r++) {
                  final rowChildren = <Widget>[];
                  for (int c = 0; c < cols && idx < count; c++) {
                    final tile = activeTiles[idx++];
                    rowChildren.add(SizedBox(
                      width: tileW,
                      height: tileH,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(color: scheme.surfaceContainerHighest),
                            Image.network(tile.value, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: Icon(Icons.broken_image_outlined, size: 28, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)))),
                            Positioned(
                              left: 5, top: 5,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(4)),
                                child: Text(tile.key, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ));
                  }
                  rowWidgets.add(Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [for (int i = 0; i < rowChildren.length; i++) ...[if (i > 0) const SizedBox(width: 6), rowChildren[i]]],
                  ));
                }
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [for (int i = 0; i < rowWidgets.length; i++) ...[if (i > 0) const SizedBox(height: 6), rowWidgets[i]]],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool active, VoidCallback onTap, ColorScheme scheme) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? scheme.primary : scheme.outlineVariant, width: 1.2),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: active ? scheme.onPrimary : scheme.onSurfaceVariant, letterSpacing: 0.5)),
      ),
    );
  }
}

Uint8List? _tryDecodeBase64(String data) {
  try {
    String clean = data;
    if (clean.contains(',')) clean = clean.split(',').last;
    return Uint8List.fromList(base64Decode(clean));
  } catch (_) {
    return null;
  }
}

