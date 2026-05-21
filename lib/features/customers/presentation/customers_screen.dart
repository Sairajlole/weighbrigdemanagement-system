import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weighbridgemanagement/features/weighments/presentation/weighments_screen.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/utils/title_case.dart';

final _customersProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.customers.snapshots().map(
        (snap) {
          final list = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          list.sort((a, b) => (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));
          return list;
        },
      );
});

final _siteFilteredCustomersProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, siteId) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.customers.where('siteId', isEqualTo: siteId).snapshots().map(
        (snap) {
          final list = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          list.sort((a, b) => (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));
          return list;
        },
      );
});

final _crossSiteCustomersProvider = FutureProvider<bool>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return false;
  final doc = await paths.generalSettings.get();
  return doc.data()?['crossSiteCustomers'] == true;
});

final _allWeighmentsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.weighments.snapshots().map(
    (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
  );
});

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

enum _SortOption {
  nameAsc, nameDesc, addressAsc, addressDesc,
  weighmentsHigh, weighmentsLow,
  createdNewest, createdOldest,
  updatedNewest, updatedOldest,
}

enum _SelectPurpose { merge, delete }

class _TimeColumn {
  final String label;
  final DateTime start;
  final DateTime end;
  const _TimeColumn(this.label, this.start, this.end);
}

List<_TimeColumn> _buildAvailableTimeColumns() {
  final now = DateTime.now();
  final fyStartYear = now.month >= 4 ? now.year : now.year - 1;
  final columns = <_TimeColumn>[];

  // Quarters first (most recent first)
  for (int i = 0; i < 4; i++) {
    final currentQ = ((now.month - 1) ~/ 3);
    final totalQ = now.year * 4 + currentQ - i;
    final y = totalQ ~/ 4;
    final q = totalQ % 4;
    final qStart = DateTime(y, q * 3 + 1, 1);
    final qEnd = DateTime(y, q * 3 + 4, 1).subtract(const Duration(seconds: 1));
    final qLabel = 'Q${q + 1} ${y % 100}';
    columns.add(_TimeColumn(qLabel, qStart, qEnd));
  }

  // FY
  columns.add(_TimeColumn('FY ${fyStartYear % 100}-${(fyStartYear + 1) % 100}', DateTime(fyStartYear, 4, 1), DateTime(fyStartYear + 1, 3, 31, 23, 59, 59)));

  // All time
  columns.add(_TimeColumn('All Time', DateTime(2000), DateTime(2100)));

  return columns;
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  static bool _persistedGridView = false;

  final FocusNode _focusNode = FocusNode();
  final GlobalKey _sortKey = GlobalKey();
  final GlobalKey _columnsKey = GlobalKey();
  String _search = '';
  bool _gridView = _persistedGridView;
  final Set<String> _selected = {};
  bool _selectMode = false;
  _SelectPurpose _selectPurpose = _SelectPurpose.merge;
  _SortOption _sortOption = _SortOption.nameAsc;
  bool _viewAllSites = false;
  late final List<_TimeColumn> _availableTimeColumns = _buildAvailableTimeColumns();
  final Set<int> _visibleTimeColumns = {0, 4, 5};

  static const _colsPrefKey = 'customers_visible_time_cols';

  @override
  void initState() {
    super.initState();
    _loadPersistedCols();
  }

  Future<void> _loadPersistedCols() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_colsPrefKey);
    if (saved != null && saved.isNotEmpty) {
      final restored = saved.map((s) => int.tryParse(s)).whereType<int>().toSet();
      if (restored.isNotEmpty) {
        setState(() {
          _visibleTimeColumns.clear();
          _visibleTimeColumns.addAll(restored);
        });
      }
    }
  }

  void _persistCols() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setStringList(_colsPrefKey, _visibleTimeColumns.map((i) => i.toString()).toList());
    });
  }

  String _maskPhone(String? phone) {
    if (phone == null || phone.isEmpty) return '--';
    if (phone.length <= 4) return '****$phone';
    return '****${phone.substring(phone.length - 4)}';
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _selectMode = false;
      } else {
        _selected.add(id);
      }
    });
  }

  void _cancelSelection() {
    setState(() { _selected.clear(); _selectMode = false; });
  }

  Future<void> _deleteSelected(BuildContext ctx) async {
    final scheme = Theme.of(ctx).colorScheme;
    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        icon: Icon(Icons.delete_sweep_rounded, color: scheme.error, size: 28),
        title: Text('Delete $count Customer${count > 1 ? 's' : ''}?'),
        content: Text(
          'Moved to Recycle Bin. Auto-deleted after 30 days. Customers with weighments will need individual handling.',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dCtx, true),
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final db = ref.read(firestorePathsProvider);
    int deleted = 0;
    int skipped = 0;

    for (final id in _selected.toList()) {
      final doc = await db.customers.doc(id).get();
      if (!doc.exists) continue;
      final data = doc.data()!;
      final totalWeighments = data['totalWeighments'] as int? ?? 0;

      if (totalWeighments > 0) {
        skipped++;
        continue;
      }

      // Move to recycle bin
      final archiveData = Map<String, dynamic>.from(data);
      archiveData['deletedAt'] = Timestamp.now();
      archiveData['originalId'] = id;
      await db.customersDeleted.doc(id).set(archiveData);
      await db.customers.doc(id).delete();
      deleted++;
    }

    _cancelSelection();
    if (ctx.mounted) {
      final msg = skipped > 0
          ? 'Deleted $deleted customer${deleted != 1 ? 's' : ''}. Skipped $skipped with weighments (use individual delete).'
          : 'Deleted $deleted customer${deleted != 1 ? 's' : ''}.';
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: scheme.primary),
      );
    }
  }

  void _applySorting(List<Map<String, dynamic>> list) {
    switch (_sortOption) {
      case _SortOption.nameAsc:
        list.sort((a, b) => (a['name'] as String? ?? '').toLowerCase().compareTo((b['name'] as String? ?? '').toLowerCase()));
      case _SortOption.nameDesc:
        list.sort((a, b) => (b['name'] as String? ?? '').toLowerCase().compareTo((a['name'] as String? ?? '').toLowerCase()));
      case _SortOption.addressAsc:
        list.sort((a, b) => (a['address'] as String? ?? '').toLowerCase().compareTo((b['address'] as String? ?? '').toLowerCase()));
      case _SortOption.addressDesc:
        list.sort((a, b) => (b['address'] as String? ?? '').toLowerCase().compareTo((a['address'] as String? ?? '').toLowerCase()));
      case _SortOption.weighmentsHigh:
        list.sort((a, b) => (b['totalWeighments'] as int? ?? 0).compareTo(a['totalWeighments'] as int? ?? 0));
      case _SortOption.weighmentsLow:
        list.sort((a, b) => (a['totalWeighments'] as int? ?? 0).compareTo(b['totalWeighments'] as int? ?? 0));
      case _SortOption.createdNewest:
        list.sort((a, b) => _tsCompare(b['createdAt'], a['createdAt']));
      case _SortOption.createdOldest:
        list.sort((a, b) => _tsCompare(a['createdAt'], b['createdAt']));
      case _SortOption.updatedNewest:
        list.sort((a, b) => _tsCompare(b['updatedAt'], a['updatedAt']));
      case _SortOption.updatedOldest:
        list.sort((a, b) => _tsCompare(a['updatedAt'], b['updatedAt']));
    }
  }

  int _tsCompare(dynamic a, dynamic b) {
    final ta = a is Timestamp ? a.millisecondsSinceEpoch : 0;
    final tb = b is Timestamp ? b.millisecondsSinceEpoch : 0;
    return ta.compareTo(tb);
  }

  String _sortLabel(_SortOption opt) => switch (opt) {
    _SortOption.nameAsc => 'Name A→Z',
    _SortOption.nameDesc => 'Name Z→A',
    _SortOption.addressAsc => 'Address A→Z',
    _SortOption.addressDesc => 'Address Z→A',
    _SortOption.weighmentsHigh => 'Weighments ↓',
    _SortOption.weighmentsLow => 'Weighments ↑',
    _SortOption.createdNewest => 'Created (Newest)',
    _SortOption.createdOldest => 'Created (Oldest)',
    _SortOption.updatedNewest => 'Updated (Newest)',
    _SortOption.updatedOldest => 'Updated (Oldest)',
  };

  void _showSortPicker(ColorScheme scheme) {
    final renderBox = _sortKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final chipSize = renderBox.size;
    final chipOffset = renderBox.localToGlobal(Offset.zero);
    final left = chipOffset.dx;
    final top = chipOffset.dy + chipSize.height + 6;

    const pairs = [
      (_SortOption.nameAsc, _SortOption.nameDesc),
      (_SortOption.addressAsc, _SortOption.addressDesc),
      (_SortOption.weighmentsHigh, _SortOption.weighmentsLow),
      (_SortOption.createdNewest, _SortOption.createdOldest),
      (_SortOption.updatedNewest, _SortOption.updatedOldest),
    ];

    showDialog(
      context: context,
      barrierColor: Colors.black12,
      builder: (ctx) => Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: Container(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: pairs.map((pair) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _sortChip(pair.$1, scheme, ctx),
                        const SizedBox(width: 6),
                        _sortChip(pair.$2, scheme, ctx),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sortChip(_SortOption opt, ColorScheme scheme, BuildContext ctx) {
    final active = opt == _sortOption;
    return GestureDetector(
      onTap: () {
        setState(() => _sortOption = opt);
        Navigator.pop(ctx);
      },
      child: Container(
        width: 120,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? scheme.primary.withValues(alpha: 0.15) : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(6),
          border: active ? Border.all(color: scheme.primary.withValues(alpha: 0.6)) : null,
        ),
        child: Text(
          _sortLabel(opt),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: active ? scheme.primary : scheme.onSurface),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final ctx = ref.watch(siteContextProvider);
    final crossSite = ref.watch(_crossSiteCustomersProvider).valueOrNull ?? false;
    final showAll = _viewAllSites || crossSite;
    final customersAsync = showAll
        ? ref.watch(_customersProvider)
        : ref.watch(_siteFilteredCustomersProvider(ctx.siteId));
    final weighmentsAsync = ref.watch(_allWeighmentsProvider);
    final shouldMask = ref.watch(permissionServiceProvider).shouldMaskSensitive;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape && _selectMode) {
          _cancelSelection();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        children: [
          Expanded(
            child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          if (_selectMode)
            _buildSelectionHeader(scheme, text, customersAsync)
          else
            _buildNormalHeader(scheme, text, customersAsync),
          const SizedBox(height: 20),

          // Content
          Expanded(
            child: customersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (customers) {
                final filtered = _search.isEmpty
                    ? List<Map<String, dynamic>>.from(customers)
                    : customers.where((c) =>
                        (c['name'] as String? ?? '').toLowerCase().contains(_search) ||
                        (c['phone'] as String? ?? '').contains(_search) ||
                        (c['address'] as String? ?? '').toLowerCase().contains(_search)).toList();

                _applySorting(filtered);

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline, size: 48, color: scheme.outlineVariant),
                        const SizedBox(height: 8),
                        Text(
                          _search.isNotEmpty ? 'No matches for "$_search"' : 'No customers yet',
                          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _search.isNotEmpty ? 'Try a different search term' : 'Add your first customer to get started',
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  );
                }

                if (_gridView) {
                  return _buildGrid(filtered, scheme, text, shouldMask);
                } else {
                  final allWeighments = weighmentsAsync.valueOrNull ?? [];
                  return _buildTable(filtered, scheme, text, shouldMask, allWeighments);
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildBottomSummary(scheme, customersAsync, weighmentsAsync),
        ],
      ),
    ),
          ),
        ],
      ),
    );
  }


  Widget _buildBottomSummary(ColorScheme scheme, AsyncValue<List<Map<String, dynamic>>> customersAsync, AsyncValue<List<Map<String, dynamic>>> weighmentsAsync) {
    final customers = customersAsync.valueOrNull ?? [];
    final allWeighments = weighmentsAsync.valueOrNull ?? [];

    if (customers.isEmpty) return const SizedBox.shrink();

    final filtered = _search.isEmpty
        ? customers
        : customers.where((c) =>
            (c['name'] as String? ?? '').toLowerCase().contains(_search) ||
            (c['phone'] as String? ?? '').contains(_search) ||
            (c['address'] as String? ?? '').toLowerCase().contains(_search)).toList();

    final withPhone = filtered.where((c) => (c['phone'] as String? ?? '').isNotEmpty).length;
    final withAddress = filtered.where((c) => (c['address'] as String? ?? '').isNotEmpty).length;
    final archivedCount = filtered.where((c) => c['archived'] == true).length;

    // Top materials by weighment count for these customers
    final customerNames = filtered.map((c) => (c['name'] as String? ?? '').toLowerCase()).toSet();
    final materialCount = <String, int>{};
    for (final w in allWeighments) {
      final cn = (w['customerName'] as String? ?? '').toLowerCase();
      if (customerNames.contains(cn)) {
        final mat = w['material'] as String? ?? '';
        if (mat.isNotEmpty) {
          materialCount[mat] = (materialCount[mat] ?? 0) + 1;
        }
      }
    }
    final topMaterials = materialCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Text('${filtered.length} shown', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
          const SizedBox(width: 16),
          _bottomPill('With Phone', '$withPhone', scheme),
          const SizedBox(width: 8),
          _bottomPill('With Address', '$withAddress', scheme),
          const SizedBox(width: 8),
          if (archivedCount > 0) ...[
            _bottomPill('Archived', '$archivedCount', scheme),
            const SizedBox(width: 8),
          ],
          _bottomPill('Weighments', '${allWeighments.length}', scheme),
          const SizedBox(width: 16),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: topMaterials.take(6).map((e) => Padding(
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

  Widget _bottomPill(String label, String value, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '$label ', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          TextSpan(text: value, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurface)),
        ]),
      ),
    );
  }

  Widget _buildNormalHeader(ColorScheme scheme, TextTheme text, AsyncValue<List<Map<String, dynamic>>> customersAsync) {
    final allWeighments = ref.watch(_allWeighmentsProvider).valueOrNull ?? [];
    final customers = customersAsync.valueOrNull ?? [];
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final activeCount = customers.where((c) => c['archived'] != true).length;
    final newThisMonth = customers.where((c) {
      final ts = c['createdAt'];
      if (ts is! Timestamp) return false;
      return ts.toDate().isAfter(monthStart);
    }).length;

    final siteCtx = ref.watch(siteContextProvider);
    final crossSite = ref.watch(_crossSiteCustomersProvider).valueOrNull ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Customers', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            if (crossSite)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swap_horiz_rounded, size: 12, color: scheme.primary),
                    const SizedBox(width: 5),
                    Text('Cross-Site', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.primary)),
                  ],
                ),
              )
            else ...[
              Container(
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _viewAllSites = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: !_viewAllSites ? scheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.location_on_rounded, size: 12, color: !_viewAllSites ? scheme.onPrimary : scheme.onSurfaceVariant),
                            const SizedBox(width: 5),
                            FutureBuilder<String>(
                              future: ref.read(firestorePathsProvider).firestore.doc('companies/${siteCtx.companyId}/sites/${siteCtx.siteId}').get().then((d) => d.data()?['name'] as String? ?? 'This Site'),
                              builder: (_, snap) => Text(snap.data ?? 'This Site', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: !_viewAllSites ? scheme.onPrimary : scheme.onSurfaceVariant)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    GestureDetector(
                      onTap: () => setState(() => _viewAllSites = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _viewAllSites ? scheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('All Sites', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _viewAllSites ? scheme.onPrimary : scheme.onSurfaceVariant)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),

        // Row 2: Stats bar
        Row(
          children: [
            _headerStatCard('Total', '${customers.length}', Icons.people_rounded, scheme.primary, scheme),
            const SizedBox(width: 12),
            _headerStatCard('Active', '$activeCount', Icons.check_circle_rounded, Colors.green.shade700, scheme),
            const SizedBox(width: 12),
            _headerStatCard('Weighments', '${allWeighments.length}', Icons.monitor_weight_rounded, Colors.deepPurple, scheme),
            const SizedBox(width: 12),
            _headerStatCard('New This Month', '$newThisMonth', Icons.person_add_rounded, Colors.amber.shade700, scheme),
          ],
        ),
        const SizedBox(height: 16),

        // Row 3: Filter/action bar
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 200,
              height: 32,
              child: Center(
                child: TextField(
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  expands: true,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: 'Search...',
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
            GestureDetector(
              key: _sortKey,
              onTap: () => _showSortPicker(scheme),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: _sortOption != _SortOption.nameAsc ? scheme.primary.withValues(alpha: 0.1) : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(6),
                  border: _sortOption != _SortOption.nameAsc ? Border.all(color: scheme.primary.withValues(alpha: 0.4)) : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _sortOption == _SortOption.nameAsc ? 'Sort' : _sortLabel(_sortOption),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _sortOption != _SortOption.nameAsc ? scheme.primary : scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _importFromCsv(context),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Import CSV', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onPrimary)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              height: 32,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _viewToggle(Icons.grid_view_rounded, true, scheme),
                  _viewToggle(Icons.table_rows_rounded, false, scheme),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _chipButton('History', scheme.onSurfaceVariant, scheme, onTap: () => _showMergeHistory(context)),
            _chipButton('Recycle Bin', scheme.onSurfaceVariant, scheme, onTap: () => _showRecycleBin(context)),
            const SizedBox(width: 8),
            _chipButton('Merge', scheme.primary, scheme, onTap: () => setState(() { _selectMode = true; _selectPurpose = _SelectPurpose.merge; })),
            _chipButton('Delete', scheme.error, scheme, onTap: () => setState(() { _selectMode = true; _selectPurpose = _SelectPurpose.delete; })),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showAddDialog(context),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Add Customer', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onPrimary)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _headerStatCard(String label, String value, IconData icon, Color color, ColorScheme scheme) {
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

  Widget _buildSelectionHeader(ColorScheme scheme, TextTheme text, AsyncValue<List<Map<String, dynamic>>> customersAsync) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Center(child: Text('${_selected.length}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.primary))),
          ),
          const SizedBox(width: 12),
          Text('selected', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface)),
          const SizedBox(width: 12),
          Text(
            _selectPurpose == _SelectPurpose.merge ? 'Select 2 or more to merge' : 'Select customers to delete',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          if (_selectPurpose == _SelectPurpose.delete)
            TextButton(
              onPressed: _selected.isNotEmpty ? () => _deleteSelected(context) : null,
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              child: const Text('Delete Selected', style: TextStyle(fontSize: 13)),
            )
          else
            TextButton(
              onPressed: _selected.length >= 2 ? () => _mergeCustomers(context) : null,
              style: TextButton.styleFrom(foregroundColor: scheme.primary),
              child: const Text('Merge Selected', style: TextStyle(fontSize: 13)),
            ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _cancelSelection,
            style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
            child: const Text('Cancel', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _chipButton(String label, Color color, ColorScheme scheme, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _viewToggle(IconData icon, bool isGrid, ColorScheme scheme) {
    final active = _gridView == isGrid;
    return GestureDetector(
      onTap: () { setState(() => _gridView = isGrid); _persistedGridView = isGrid; },
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: active ? scheme.onPrimary : scheme.onSurfaceVariant),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GRID VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildGrid(List<Map<String, dynamic>> customers, ColorScheme scheme, TextTheme text, bool shouldMask) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        mainAxisExtent: 320,
      ),
      itemCount: customers.length,
      itemBuilder: (_, i) {
        final c = customers[i];
        final id = c['id'] as String? ?? '';
        final isSelected = _selected.contains(id);
        return GestureDetector(
          onTap: _selectMode ? () => _toggleSelect(id) : () => _showDetailDialog(context, c),
          onLongPress: () { setState(() => _selectMode = true); _toggleSelect(id); },
          child: Stack(
            children: [
              _CustomerCard(
                customer: c,
                scheme: scheme,
                text: text,
                shouldMask: shouldMask,
                maskPhone: _maskPhone,
                isSelected: isSelected,
              ),
              if (_selectMode)
                Positioned(
                  top: 8, right: 8,
                  child: Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: isSelected ? scheme.primary : scheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: isSelected ? scheme.primary : scheme.outlineVariant, width: 2),
                    ),
                    child: isSelected ? Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary) : null,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TABLE VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  int _countInPeriod(String customerName, _TimeColumn col, List<Map<String, dynamic>> weighments) {
    return weighments.where((w) {
      if ((w['customerName'] as String? ?? '') != customerName) return false;
      final ts = w['createdAt'];
      if (ts is! Timestamp) return false;
      final dt = ts.toDate();
      return !dt.isBefore(col.start) && !dt.isAfter(col.end);
    }).length;
  }

  Map<String, int> _materialBreakdownInPeriod(String customerName, _TimeColumn col, List<Map<String, dynamic>> weighments) {
    final breakdown = <String, int>{};
    for (final w in weighments) {
      if ((w['customerName'] as String? ?? '') != customerName) continue;
      final ts = w['createdAt'];
      if (ts is! Timestamp) continue;
      final dt = ts.toDate();
      if (dt.isBefore(col.start) || dt.isAfter(col.end)) continue;
      final material = w['material'] as String? ?? 'Unknown';
      breakdown[material] = (breakdown[material] ?? 0) + 1;
    }
    return breakdown;
  }

  void _showColumnPicker(BuildContext context, ColorScheme scheme) {
    final renderBox = _columnsKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final chipSize = renderBox.size;
    final chipOffset = renderBox.localToGlobal(Offset.zero);
    final right = MediaQuery.of(context).size.width - chipOffset.dx - chipSize.width;
    final top = chipOffset.dy + chipSize.height + 6;

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
                  width: 320,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Toggle time columns', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(_availableTimeColumns.length, (idx) {
                          final active = _visibleTimeColumns.contains(idx);
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                if (active) {
                                  _visibleTimeColumns.remove(idx);
                                } else {
                                  _visibleTimeColumns.add(idx);
                                }
                              });
                              _persistCols();
                              setDialogState(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: active ? scheme.primary.withValues(alpha: 0.12) : scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(6),
                                border: active ? Border.all(color: scheme.primary.withValues(alpha: 0.5)) : null,
                              ),
                              child: Text(
                                _availableTimeColumns[idx].label,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: active ? scheme.primary : scheme.onSurfaceVariant),
                              ),
                            ),
                          );
                        }),
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

  Widget _buildTable(List<Map<String, dynamic>> customers, ColorScheme scheme, TextTheme text, bool shouldMask, List<Map<String, dynamic>> allWeighments) {
    final activeCols = _visibleTimeColumns.toList()..sort();
    final timeCols = activeCols.map((i) => _availableTimeColumns[i]).toList();

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                if (_selectMode) const SizedBox(width: 40),
                SizedBox(width: 42, child: Text('#', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant))),
                Expanded(flex: 3, child: Text('Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant))),
                Expanded(flex: 2, child: Text('Phone', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant))),
                Expanded(flex: 2, child: Text('Address', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant))),
                for (final col in timeCols)
                  SizedBox(width: 90, child: Text(col.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant), textAlign: TextAlign.center)),
                SizedBox(
                  width: 32,
                  child: IconButton(
                    key: _columnsKey,
                    icon: Icon(Icons.view_column_rounded, size: 16, color: scheme.onSurfaceVariant),
                    tooltip: 'Select columns',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _showColumnPicker(context, scheme),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: customers.length,
              separatorBuilder: (_, i) => Divider(
                height: 1,
                thickness: (i + 1) % 5 == 0 ? 2 : 1,
                color: (i + 1) % 5 == 0 ? scheme.outlineVariant.withValues(alpha: 0.6) : scheme.outlineVariant.withValues(alpha: 0.2),
              ),
              itemBuilder: (_, i) {
                final c = customers[i];
                final id = c['id'] as String? ?? '';
                final name = c['name'] as String? ?? '--';
                final phone = c['phone'] as String? ?? '';
                final address = c['address'] as String? ?? '--';
                final isSelected = _selected.contains(id);

                return InkWell(
                  onTap: _selectMode ? () => _toggleSelect(id) : () => _showDetailDialog(context, c),
                  onLongPress: () { setState(() => _selectMode = true); _toggleSelect(id); },
                  hoverColor: scheme.primaryContainer.withValues(alpha: 0.1),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? scheme.primaryContainer.withValues(alpha: 0.2)
                          : (i.isEven ? scheme.surface : scheme.surfaceContainerLow.withValues(alpha: 0.5)),
                      border: Border(left: BorderSide(
                        width: 3,
                        color: isSelected ? scheme.primary : scheme.primary.withValues(alpha: i.isEven ? 0.15 : 0.35),
                      )),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        if (_selectMode)
                          SizedBox(
                            width: 40,
                            child: Checkbox(
                              value: isSelected,
                              onChanged: (_) => _toggleSelect(id),
                            ),
                          ),
                        SizedBox(width: 42, child: Text('${i + 1}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant))),
                        Expanded(flex: 3, child: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis, maxLines: 1)),
                        Expanded(
                          flex: 2,
                          child: Text(
                            shouldMask ? _maskPhone(phone) : (phone.isNotEmpty ? phone : '--'),
                            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis, maxLines: 1,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(address, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis, maxLines: 1),
                        ),
                        for (final col in timeCols)
                          SizedBox(
                            width: 90,
                            child: _buildPeriodCell(name, col, allWeighments, scheme),
                          ),
                        const SizedBox(width: 32),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodCell(String customerName, _TimeColumn col, List<Map<String, dynamic>> weighments, ColorScheme scheme) {
    final count = _countInPeriod(customerName, col, weighments);
    if (count == 0) {
      return Center(child: Text('–', style: TextStyle(fontSize: 12, color: scheme.outlineVariant)));
    }
    final breakdown = _materialBreakdownInPeriod(customerName, col, weighments);
    return Tooltip(
      message: breakdown.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(4)),
          child: Text(
            breakdown.length == 1 ? '$count (${breakdown.keys.first})' : '$count',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onPrimaryContainer),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DETAIL DIALOG (with inline edit)
  // ═══════════════════════════════════════════════════════════════════════════

  bool _detailOpen = false;

  void _showDetailDialog(BuildContext context, Map<String, dynamic> customer) {
    if (_detailOpen) return;
    _detailOpen = true;
    showDialog(
      context: context,
      builder: (ctx) => _CustomerDetailDialog(customer: customer, ref: ref),
    ).then((_) => _detailOpen = false);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADD DIALOG
  // ═══════════════════════════════════════════════════════════════════════════

  void _showAddDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _AddCustomerDialog(ref: ref),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // IMPORT FROM CSV
  // ═══════════════════════════════════════════════════════════════════════════

  void _importFromCsv(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CsvImportDialog(ref: ref),
    );
  }


  // ═══════════════════════════════════════════════════════════════════════════
  // MERGE CUSTOMERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _mergeCustomers(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final customers = ref.read(_customersProvider).valueOrNull ?? [];
    final selectedCustomers = customers.where((c) => _selected.contains(c['id'])).toList();
    if (selectedCustomers.length < 2) return;

    String? primaryId = selectedCustomers.first['id'] as String?;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final phones = selectedCustomers.map((c) => c['phone'] as String? ?? '').where((p) => p.isNotEmpty).toSet();
          final hasPhoneMismatch = phones.length > 1;

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                          child: Icon(Icons.merge_rounded, size: 18, color: scheme.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Merge Customers', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                              Text('Select the primary record to keep', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, size: 20)),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: selectedCustomers.map((c) {
                        final id = c['id'] as String;
                        final name = c['name'] as String? ?? '--';
                        final phone = c['phone'] as String? ?? '';
                        final weighments = c['totalWeighments'] as int? ?? 0;
                        final isSelected = primaryId == id;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: GestureDetector(
                            onTap: () => setSt(() => primaryId = id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? scheme.primaryContainer.withValues(alpha: 0.3) : scheme.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32, height: 32,
                                    decoration: BoxDecoration(
                                      color: isSelected ? scheme.primary : scheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: isSelected
                                          ? Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary)
                                          : Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                                        Row(
                                          children: [
                                            if (phone.isNotEmpty) ...[
                                              Text(phone, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                                              const SizedBox(width: 8),
                                            ],
                                            Text('$weighments weighments', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(4)),
                                      child: Text('PRIMARY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.primary, letterSpacing: 0.5)),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  if (hasPhoneMismatch)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: scheme.tertiaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: scheme.tertiary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 14, color: scheme.tertiary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('Different phone numbers detected. Primary\'s phone will be kept.', style: TextStyle(fontSize: 11, color: scheme.tertiary)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 13, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        const SizedBox(width: 6),
                        Expanded(child: Text('Weighments will be reassigned to primary. This action can be reverted from History.', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)))),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(foregroundColor: scheme.onSurfaceVariant, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                          child: const Text('Cancel', style: TextStyle(fontSize: 13)),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: primaryId == null ? null : () async {
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _performMerge(primaryId!, selectedCustomers);
                            _cancelSelection();
                          },
                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                          child: const Text('Merge', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _performMerge(String primaryId, List<Map<String, dynamic>> allCustomers) async {
    final db = ref.read(firestorePathsProvider);
    final primary = allCustomers.firstWhere((c) => c['id'] == primaryId);
    final others = allCustomers.where((c) => c['id'] != primaryId).toList();
    final primaryName = primary['name'] as String? ?? '';

    // Save merge record for revert capability
    final mergedCustomerSnapshots = <Map<String, dynamic>>[];
    final weighmentReassignments = <Map<String, dynamic>>[];

    String? firstFace = primary['firstFace'] as String?;
    String? lastFace = primary['lastFace'] as String?;

    for (final other in others) {
      final otherId = other['id'] as String;
      final otherName = other['name'] as String? ?? '';

      // Snapshot the merged customer data for revert
      final otherSnapshot = Map<String, dynamic>.from(other)..remove('id');
      mergedCustomerSnapshots.add({'id': otherId, ...otherSnapshot});

      if (firstFace == null || firstFace.isEmpty) {
        firstFace = other['firstFace'] as String?;
      }
      if (lastFace == null || lastFace.isEmpty) {
        lastFace = other['lastFace'] as String?;
      }

      // Reassign weighments from other customer to primary
      final weighments = await db.weighments.where('customerName', isEqualTo: otherName).get();
      if (weighments.docs.isNotEmpty) {
        for (final doc in weighments.docs) {
          weighmentReassignments.add({
            'weighmentId': doc.id,
            'originalCustomerName': otherName,
            'originalCustomerPhone': other['phone'] ?? '',
          });
        }
        final chunks = <List<QueryDocumentSnapshot>>[];
        for (var i = 0; i < weighments.docs.length; i += 450) {
          chunks.add(weighments.docs.sublist(i, i + 450 > weighments.docs.length ? weighments.docs.length : i + 450));
        }
        for (final chunk in chunks) {
          final batch = db.batch();
          for (final doc in chunk) {
            batch.update(doc.reference, {'customerName': primaryName, 'customerPhone': primary['phone'] ?? ''});
          }
          await batch.commit();
        }
      }

      // Delete the merged customer (do NOT delete face files — needed for revert)
      await db.customers.doc(otherId).delete();
    }

    // Update primary with actual weighment count, inherited faces, and merge trail
    final primarySnapshot = Map<String, dynamic>.from(primary)..remove('id');
    final mergedNames = others.map((o) => o['name'] as String? ?? '').where((n) => n.isNotEmpty).toList();
    final existingMergedFrom = (primary['mergedFrom'] as List?)?.cast<String>() ?? [];

    // Recount actual weighments for accuracy
    final actualWeighments = await db.weighments.where('customerName', isEqualTo: primaryName).get();

    final updateData = <String, dynamic>{
      'totalWeighments': actualWeighments.docs.length,
      'updatedAt': Timestamp.now(),
      'mergedFrom': [...existingMergedFrom, ...mergedNames],
    };
    if (firstFace != null && firstFace.isNotEmpty) updateData['firstFace'] = firstFace;
    if (lastFace != null && lastFace.isNotEmpty) updateData['lastFace'] = lastFace;
    await db.customers.doc(primaryId).update(updateData);

    // Save merge history record
    await db.customerMerges.add({
      'primaryId': primaryId,
      'primarySnapshot': primarySnapshot,
      'mergedCustomers': mergedCustomerSnapshots,
      'weighmentReassignments': weighmentReassignments,
      'mergedAt': Timestamp.now(),
      'reverted': false,
    });

    ref.read(auditServiceProvider).log(
      event: 'weighmentEdit',
      description: 'Merged ${others.length} customer(s) into $primaryName',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Merged ${others.length} customer(s) into $primaryName'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ));
    }
  }

  void _showMergeHistory(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _MergeHistoryDialog(ref: ref),
    );
  }

  void _showRecycleBin(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _RecycleBinDialog(ref: ref),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOMER DETAIL DIALOG (inline edit + weighment history)
// ═══════════════════════════════════════════════════════════════════════════════

class _CustomerDetailDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> customer;
  final WidgetRef ref;

  const _CustomerDetailDialog({required this.customer, required this.ref});

  @override
  ConsumerState<_CustomerDetailDialog> createState() => _CustomerDetailDialogState();
}

class _CustomerDetailDialogState extends ConsumerState<_CustomerDetailDialog> {
  bool _editing = false;
  bool _faceCaptureOpen = false;
  late TextEditingController _nameC;
  late TextEditingController _phoneC;
  late TextEditingController _addressC;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameC = TextEditingController(text: widget.customer['name']);
    _phoneC = TextEditingController(text: widget.customer['phone']);
    _addressC = TextEditingController(text: widget.customer['address'] ?? '');
  }

  @override
  void dispose() {
    _nameC.dispose();
    _phoneC.dispose();
    _addressC.dispose();
    super.dispose();
  }

  int get _weighmentCount => widget.customer['totalWeighments'] as int? ?? 0;
  bool get _hasWeighments => _weighmentCount > 0;
  bool get _canEditWithReverification => _weighmentCount == 1;

  Future<void> _saveChanges() async {
    if (_nameC.text.trim().isEmpty || _phoneC.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final db = ref.read(firestorePathsProvider);
      final oldName = widget.customer['name'] as String? ?? '';
      final oldPhone = widget.customer['phone'] as String? ?? '';
      final newName = toTitleCase(_nameC.text.trim());
      final newPhone = _phoneC.text.trim();

      // Check phone duplication
      if (newPhone != oldPhone) {
        final existing = await db.customers.where('phone', isEqualTo: newPhone).get();
        if (existing.docs.any((d) => d.id != widget.customer['id'])) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Phone $newPhone already belongs to another customer'), backgroundColor: Theme.of(context).colorScheme.error),
            );
            setState(() => _saving = false);
          }
          return;
        }
      }

      await db.customers.doc(widget.customer['id']).update({
        'name': newName,
        'phone': newPhone,
        'address': _addressC.text.trim().isEmpty ? null : toTitleCase(_addressC.text.trim()),
        'updatedAt': Timestamp.now(),
      });

      // Update weighments referencing old name/phone
      if (newName != oldName || newPhone != oldPhone) {
        final weighments = await db.weighments.where('customerName', isEqualTo: oldName).get();
        if (weighments.docs.isNotEmpty) {
          final batch = db.batch();
          for (final doc in weighments.docs) {
            final updates = <String, dynamic>{};
            if (newName != oldName) updates['customerName'] = newName;
            if (newPhone != oldPhone) updates['customerPhone'] = newPhone;
            if (updates.isNotEmpty) batch.update(doc.reference, updates);
          }
          await batch.commit();
        }
      }

      if (mounted) setState(() => _editing = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestReverification(BuildContext ctx, VoidCallback onVerified) async {
    final passC = TextEditingController();
    final scheme = Theme.of(ctx).colorScheme;
    final verified = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          Icon(Icons.verified_user_rounded, size: 20, color: scheme.tertiary),
          const SizedBox(width: 8),
          const Text('Admin Reverification'),
        ]),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This customer has 1 weighment. Editing requires operator/admin password to confirm.',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              TextField(
                controller: passC,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Admin Password',
                  prefixIcon: const Icon(Icons.lock_rounded, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (passC.text.isEmpty) return;
              try {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null && user.email != null) {
                  final cred = EmailAuthProvider.credential(email: user.email!, password: passC.text);
                  await user.reauthenticateWithCredential(cred);
                  if (dCtx.mounted) Navigator.pop(dCtx, true);
                } else {
                  if (dCtx.mounted) Navigator.pop(dCtx, true);
                }
              } catch (_) {
                if (dCtx.mounted) {
                  ScaffoldMessenger.of(dCtx).showSnackBar(
                    SnackBar(content: const Text('Invalid password'), backgroundColor: scheme.error),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: scheme.tertiary),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
    if (verified == true) onVerified();
  }

  Future<void> _deleteCustomer(BuildContext ctx) async {
    final db = ref.read(firestorePathsProvider);
    final id = widget.customer['id'] as String;
    final name = widget.customer['name'] as String? ?? '--';
    final totalWeighments = widget.customer['totalWeighments'] as int? ?? 0;
    final scheme = Theme.of(ctx).colorScheme;

    if (totalWeighments == 0) {
      // Simple delete — no weighments
      final confirmed = await showDialog<bool>(
        context: ctx,
        builder: (dCtx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.delete_outline_rounded, size: 20, color: scheme.error),
                  const SizedBox(width: 10),
                  Text('Delete Customer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                ]),
                const SizedBox(height: 12),
                Text('Delete "$name"? This customer has no weighments and will be moved to the recycle bin.', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  OutlinedButton(onPressed: () => Navigator.pop(dCtx, false), style: OutlinedButton.styleFrom(foregroundColor: scheme.onSurfaceVariant), child: const Text('Cancel', style: TextStyle(fontSize: 13))),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: () => Navigator.pop(dCtx, true), style: FilledButton.styleFrom(backgroundColor: scheme.error), child: const Text('Delete', style: TextStyle(fontSize: 13))),
                ]),
              ],
            ),
          ),
        ),
      );
      if (confirmed == true) {
        final data = Map<String, dynamic>.from(widget.customer)..remove('id');
        data['deletedAt'] = Timestamp.now();
        data['originalId'] = id;
        await db.customersDeleted.doc(id).set(data);
        await db.customers.doc(id).delete();
        ref.read(auditServiceProvider).log(event: 'weighmentEdit', description: 'Customer "$name" deleted (no weighments)');
        if (ctx.mounted) Navigator.pop(ctx);
      }
    } else {
      // Has weighments — show options: archive or transfer
      final result = await showDialog<String>(
        context: ctx,
        builder: (dCtx) => _DeleteWithWeighmentsDialog(
          customerName: name,
          weighmentCount: totalWeighments,
          customerId: id,
          ref: ref,
        ),
      );
      if (result == 'done' && ctx.mounted) Navigator.pop(ctx);
    }
  }

  void _openWeighmentDetail(BuildContext ctx, Map<String, dynamic> w) {
    showWeighmentDetailDialog(ctx, ref, w);
  }

  void _showFaceCaptureDialog(BuildContext ctx) {
    if (_faceCaptureOpen) return;
    _faceCaptureOpen = true;
    showDialog(
      context: ctx,
      builder: (_) => _FaceCaptureForCustomerDialog(
        ref: ref,
        customerId: widget.customer['id'] as String,
      ),
    ).then((_) => _faceCaptureOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = widget.customer['name'] as String? ?? '--';
    final phone = widget.customer['phone'] as String? ?? '--';
    final address = widget.customer['address'] as String? ?? '';
    final firstFace = widget.customer['firstFace'] as String?;
    final lastFace = widget.customer['lastFace'] as String?;
    final totalWeighments = widget.customer['totalWeighments'] as int? ?? 0;
    final mergedFrom = (widget.customer['mergedFrom'] as List?)?.cast<String>() ?? [];

    return Dialog(
      alignment: Alignment.topCenter,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
      child: SizedBox(
        width: 900,
        height: MediaQuery.of(context).size.height * 0.96,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: _editing ? _buildEditHeader(scheme, text) : _buildViewHeader(scheme, text, name, phone, address, firstFace, lastFace, totalWeighments, mergedFrom),
            ),
            const Divider(height: 1),
            // Weighment history
            Expanded(
              child: _WeighmentHistory(
                customerName: name,
                scheme: scheme,
                text: text,
                ref: ref,
                onViewWeighment: (w) => _openWeighmentDetail(context, w),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewHeader(ColorScheme scheme, TextTheme text, String name, String phone, String address, String? firstFace, String? lastFace, int totalWeighments, List<String> mergedFrom) {
    return Row(
      children: [
        if (firstFace != null)
          _FacePreview(facePath: firstFace, label: 'First', scheme: scheme)
        else
          Tooltip(
            message: 'Scan face',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _showFaceCaptureDialog(context),
                child: Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: scheme.primary)),
                      const SizedBox(height: 2),
                      Icon(Icons.camera_alt_rounded, size: 13, color: scheme.primary.withValues(alpha: 0.6)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(width: 10),
        if (lastFace != null) ...[
          _FacePreview(facePath: lastFace, label: 'Last', scheme: scheme),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.phone_rounded, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(phone, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                if (address.isNotEmpty) ...[
                  Text('   •   ', style: TextStyle(fontSize: 12, color: scheme.outlineVariant)),
                  Icon(Icons.location_on_rounded, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(child: Text(address, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
                ],
                if (address.isEmpty) const Spacer(),
              ]),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(6)),
                    child: Text('$totalWeighments weighments', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
                  ),
                  if (mergedFrom.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Merged from: ${mergedFrom.join(", ")}',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: scheme.tertiaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(6)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.merge_rounded, size: 11, color: scheme.tertiary),
                            const SizedBox(width: 4),
                            Text('${mergedFrom.length} merged', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.tertiary)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (_canEditWithReverification)
          TextButton(
            onPressed: () => _requestReverification(context, () => setState(() => _editing = true)),
            style: TextButton.styleFrom(foregroundColor: scheme.tertiary),
            child: const Text('Edit', style: TextStyle(fontSize: 12)),
          )
        else if (!_hasWeighments)
          TextButton(
            onPressed: () => setState(() => _editing = true),
            style: TextButton.styleFrom(foregroundColor: scheme.primary),
            child: const Text('Edit', style: TextStyle(fontSize: 12)),
          ),
        const SizedBox(width: 4),
        TextButton(
          onPressed: () => _deleteCustomer(context),
          style: TextButton.styleFrom(foregroundColor: scheme.error),
          child: const Text('Delete', style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, size: 20),
          tooltip: 'Close',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _buildEditHeader(ColorScheme scheme, TextTheme text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _nameC,
          decoration: InputDecoration(
            labelText: 'Name',
            prefixIcon: const Icon(Icons.person_rounded, size: 18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _phoneC,
                decoration: InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: const Icon(Icons.phone_rounded, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _addressC,
                decoration: InputDecoration(
                  labelText: 'Address',
                  prefixIcon: const Icon(Icons.location_on_rounded, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: () => setState(() => _editing = false), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving ? null : _saveChanges,
              child: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WEIGHMENT HISTORY
// ═══════════════════════════════════════════════════════════════════════════════

class _WeighmentHistory extends StatelessWidget {
  final String customerName;
  final ColorScheme scheme;
  final TextTheme text;
  final WidgetRef ref;
  final void Function(Map<String, dynamic> weighment)? onViewWeighment;

  const _WeighmentHistory({
    required this.customerName,
    required this.scheme,
    required this.text,
    required this.ref,
    this.onViewWeighment,
  });

  Future<List<Map<String, dynamic>>> _fetchAllWbWeighments() async {
    final db = ref.read(firestorePathsProvider);
    final ctx = db.context;
    final firestore = db.firestore;
    final all = <Map<String, dynamic>>[];
    final sitesSnap = await firestore.collection('companies/${ctx.companyId}/sites').get();
    for (final site in sitesSnap.docs) {
      final wbSnap = await firestore.collection('companies/${ctx.companyId}/sites/${site.id}/weighbridges').get();
      for (final wb in wbSnap.docs) {
        final wbName = wb.data()['name'] as String? ?? 'Unnamed WB';
        final wmSnap = await firestore
            .collection('companies/${ctx.companyId}/sites/${site.id}/weighbridges/${wb.id}/weighments')
            .where('customerName', isEqualTo: customerName)
            .orderBy('createdAt', descending: true)
            .limit(50)
            .get();
        for (final d in wmSnap.docs) {
          all.add({'id': d.id, 'weighbridgeName': wbName, ...d.data()});
        }
      }
    }
    all.sort((a, b) {
      final ta = a['createdAt'];
      final tb = b['createdAt'];
      if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
      return 0;
    });
    return all;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchAllWbWeighments(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 40, color: scheme.error.withValues(alpha: 0.5)),
                const SizedBox(height: 8),
                Text('Failed to load history', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text('${snap.error}', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)), textAlign: TextAlign.center),
              ],
            ),
          );
        }

        final docs = snap.data ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.scale_rounded, size: 40, color: scheme.outlineVariant),
                const SizedBox(height: 8),
                Text('No weighment history', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          );
        }

        // Material breakdown
        final materialCounts = <String, int>{};
        double totalNet = 0;
        for (final d in docs) {
          final m = d['material'] as String? ?? 'Unknown';
          materialCounts[m] = (materialCounts[m] ?? 0) + 1;
          final net = d['netWeight'];
          if (net is num) totalNet += net;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 4),
              child: Row(
                children: [
                  Text('Weighments (${docs.length})', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(6)),
                    child: Text('Net: ${(totalNet / 1000).toStringAsFixed(1)} t', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: totalNet < 0 ? scheme.error : scheme.onTertiaryContainer)),
                  ),
                ],
              ),
            ),
            // Material chips
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: materialCounts.entries.map((e) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Text('${e.key}: ${e.value}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                )).toList(),
              ),
            ),
            const Divider(height: 1),
            // List header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text('Date', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant))),
                  Expanded(flex: 2, child: Text('WB', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant))),
                  Expanded(flex: 3, child: Text('Vehicle', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant))),
                  Expanded(flex: 2, child: Text('Material', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant))),
                  Expanded(flex: 2, child: Text('Gross (kg)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant), textAlign: TextAlign.right)),
                  Expanded(flex: 2, child: Text('Tare (kg)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant), textAlign: TextAlign.right)),
                  Expanded(flex: 2, child: Text('Net (kg)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant), textAlign: TextAlign.right)),
                  const SizedBox(width: 32),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: docs.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.2)),
                itemBuilder: (_, i) {
                  final data = docs[i];
                  final material = data['material'] as String? ?? '--';
                  final vehicleNo = data['vehicleNumber'] as String? ?? data['vehicleNo'] as String? ?? '--';
                  final grossWeight = data['grossWeight'] as num?;
                  final tareWeight = data['tareWeight'] as num?;
                  final netWeight = data['netWeight'] as num?;
                  final createdAt = data['createdAt'] as Timestamp?;
                  final wbName = data['weighbridgeName'] as String? ?? '--';

                  final dateStr = createdAt != null
                      ? DateFormat('dd MMM yy').format(createdAt.toDate())
                      : '--';
                  final timeStr = createdAt != null
                      ? DateFormat('HH:mm').format(createdAt.toDate())
                      : '';

                  String fmtKg(num? v) => v != null ? v.toStringAsFixed(0) : '--';

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(dateStr, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                              Text(timeStr, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        Expanded(flex: 2, child: Text(wbName, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.primary), overflow: TextOverflow.ellipsis)),
                        Expanded(flex: 3, child: Text(vehicleNo, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                        Expanded(flex: 2, child: Text(material, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
                        Expanded(flex: 2, child: Text(fmtKg(grossWeight), style: TextStyle(fontSize: 11, color: grossWeight != null && grossWeight < 0 ? scheme.error : null), textAlign: TextAlign.right)),
                        Expanded(flex: 2, child: Text(fmtKg(tareWeight), style: TextStyle(fontSize: 11, color: tareWeight != null && tareWeight < 0 ? scheme.error : null), textAlign: TextAlign.right)),
                        Expanded(flex: 2, child: Text(fmtKg(netWeight), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: netWeight != null && netWeight < 0 ? scheme.error : netWeight != null ? scheme.primary : null), textAlign: TextAlign.right)),
                        SizedBox(
                          width: 32,
                          child: IconButton(
                            onPressed: onViewWeighment != null ? () => onViewWeighment!(data) : null,
                            icon: Icon(Icons.open_in_new_rounded, size: 14, color: scheme.primary.withValues(alpha: 0.6)),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            tooltip: 'View details',
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RECYCLE BIN DIALOG
// ═══════════════════════════════════════════════════════════════════════════════

class _RecycleBinDialog extends StatefulWidget {
  final WidgetRef ref;
  const _RecycleBinDialog({required this.ref});

  @override
  State<_RecycleBinDialog> createState() => _RecycleBinDialogState();
}

class _RecycleBinDialogState extends State<_RecycleBinDialog> {
  List<Map<String, dynamic>>? _deleted;
  bool _loading = true;
  final Set<String> _restoring = {};
  final Set<String> _permanentlyDeleting = {};

  @override
  void initState() {
    super.initState();
    _loadDeleted();
  }

  Future<void> _loadDeleted() async {
    try {
      final db = widget.ref.read(firestorePathsProvider);
      final snap = await db.customersDeleted.orderBy('deletedAt', descending: true).get();
      if (mounted) {
        setState(() {
          _deleted = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _deleted = []; _loading = false; });
    }
  }

  Future<void> _restore(Map<String, dynamic> item) async {
    final id = item['id'] as String;
    setState(() => _restoring.add(id));

    try {
      final db = widget.ref.read(firestorePathsProvider);
      final data = Map<String, dynamic>.from(item)
        ..remove('id')
        ..remove('deletedAt')
        ..remove('originalId')
        ..remove('archiveReason')
        ..remove('archivedWeighmentCount')
        ..remove('transferredTo')
        ..remove('transferredToName')
        ..remove('transferredWeighments')
        ..remove('transferredWeighmentIds');

      final customerName = data['name'] as String? ?? '';
      final customerPhone = data['phone'] as String? ?? '';
      final wasArchived = item['archiveReason'] == 'archived_with_weighments';
      final wasTransferred = item['transferredTo'] != null;

      // Restore customer
      await db.customers.doc(id).set(data);

      if (wasArchived && customerName.isNotEmpty) {
        // Un-anonymize weighments that were archived with this customer
        final weighments = await db.weighments.where('archivedCustomerId', isEqualTo: id).get();
        if (weighments.docs.isNotEmpty) {
          final chunks = <List<QueryDocumentSnapshot>>[];
          for (var i = 0; i < weighments.docs.length; i += 450) {
            chunks.add(weighments.docs.sublist(i, i + 450 > weighments.docs.length ? weighments.docs.length : i + 450));
          }
          for (final chunk in chunks) {
            final batch = db.batch();
            for (final doc in chunk) {
              batch.update(doc.reference, {
                'customerName': customerName,
                'customerPhone': customerPhone,
                'archivedCustomerId': FieldValue.delete(),
                'archivedCustomerFace': FieldValue.delete(),
              });
            }
            await batch.commit();
          }
          await db.customers.doc(id).update({'totalWeighments': weighments.docs.length});
        }
      } else if (wasTransferred) {
        // Transferred weighments now belong to another customer — can't reconnect
        await db.customers.doc(id).update({'totalWeighments': 0});
      } else {
        // Simple delete — recount weighments by name
        if (customerName.isNotEmpty) {
          final weighments = await db.weighments.where('customerName', isEqualTo: customerName).get();
          await db.customers.doc(id).update({'totalWeighments': weighments.docs.length});
        }
      }

      // Remove from recycle bin
      await db.customersDeleted.doc(id).delete();

      if (mounted) {
        setState(() {
          _restoring.remove(id);
          _deleted?.removeWhere((d) => d['id'] == id);
        });
        final suffix = wasTransferred ? ' (weighments remain with transfer target)' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restored "$customerName"$suffix'), backgroundColor: Theme.of(context).colorScheme.primary),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _restoring.remove(id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  Future<void> _permanentDelete(Map<String, dynamic> item) async {
    final id = item['id'] as String;
    final name = item['name'] as String? ?? '--';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Permanently Delete?'),
        content: Text('Delete "$name" permanently? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dCtx).colorScheme.error),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _permanentlyDeleting.add(id));

    final db = widget.ref.read(firestorePathsProvider);

    // Clean up face files
    for (final key in ['firstFace', 'lastFace']) {
      final path = item[key] as String?;
      if (path != null && path.startsWith('/')) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }

    await db.customersDeleted.doc(id).delete();

    if (mounted) {
      setState(() {
        _permanentlyDeleting.remove(id);
        _deleted?.removeWhere((d) => d['id'] == id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 550,
        height: 450,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(color: scheme.errorContainer.withValues(alpha: 0.3)),
              child: Row(
                children: [
                  Icon(Icons.delete_sweep_rounded, size: 22, color: scheme.error),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Recycle Bin', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text('Items are permanently deleted after 30 days', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_deleted == null || _deleted!.isEmpty)
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline_rounded, size: 40, color: scheme.outlineVariant),
                              const SizedBox(height: 8),
                              Text('Recycle bin is empty', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _deleted!.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final item = _deleted![i];
                            final id = item['id'] as String;
                            final name = item['name'] as String? ?? '--';
                            final phone = item['phone'] as String? ?? '--';
                            final deletedAt = item['deletedAt'] as Timestamp?;
                            final totalWeighments = item['totalWeighments'] as int? ?? 0;
                            final isRestoring = _restoring.contains(id);
                            final isDeleting = _permanentlyDeleting.contains(id);

                            final dateStr = deletedAt != null
                                ? '${deletedAt.toDate().day}/${deletedAt.toDate().month}/${deletedAt.toDate().year}'
                                : '--';
                            final daysLeft = deletedAt != null
                                ? 30 - DateTime.now().difference(deletedAt.toDate()).inDays
                                : null;

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36, height: 36,
                                    decoration: BoxDecoration(
                                      color: scheme.errorContainer.withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.error))),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(name, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis, maxLines: 1),
                                        Text('$phone  •  $totalWeighments weighments  •  Deleted $dateStr'
                                            '${daysLeft != null ? "  •  ${daysLeft > 0 ? "$daysLeft days left" : "Expiring soon"}" : ""}',
                                            style: TextStyle(fontSize: 10, color: daysLeft != null && daysLeft <= 7 ? scheme.error : scheme.onSurfaceVariant),
                                            overflow: TextOverflow.ellipsis, maxLines: 1),
                                      ],
                                    ),
                                  ),
                                  if (isRestoring || isDeleting)
                                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  else ...[
                                    TextButton(
                                      onPressed: () => _restore(item),
                                      style: TextButton.styleFrom(foregroundColor: scheme.primary, minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                      child: const Text('Restore', style: TextStyle(fontSize: 11)),
                                    ),
                                    const SizedBox(width: 4),
                                    TextButton(
                                      onPressed: () => _permanentDelete(item),
                                      style: TextButton.styleFrom(foregroundColor: scheme.error, minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                      child: const Text('Delete', style: TextStyle(fontSize: 11)),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MERGE HISTORY DIALOG
// ═══════════════════════════════════════════════════════════════════════════════

class _MergeHistoryDialog extends StatefulWidget {
  final WidgetRef ref;
  const _MergeHistoryDialog({required this.ref});

  @override
  State<_MergeHistoryDialog> createState() => _MergeHistoryDialogState();
}

class _MergeHistoryDialogState extends State<_MergeHistoryDialog> {
  List<Map<String, dynamic>>? _merges;
  bool _loading = true;
  final Set<String> _reverting = {};

  @override
  void initState() {
    super.initState();
    _loadMerges();
  }

  Future<void> _loadMerges() async {
    try {
      final db = widget.ref.read(firestorePathsProvider);
      final snap = await db.customerMerges.orderBy('mergedAt', descending: true).limit(30).get();
      if (mounted) {
        setState(() {
          _merges = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _merges = []; _loading = false; });
    }
  }

  Future<void> _revertMerge(Map<String, dynamic> merge) async {
    final id = merge['id'] as String;
    setState(() => _reverting.add(id));

    try {
      final db = widget.ref.read(firestorePathsProvider);
      final primaryId = merge['primaryId'] as String;
      final primarySnapshot = Map<String, dynamic>.from(merge['primarySnapshot'] as Map);
      final mergedCustomers = (merge['mergedCustomers'] as List).map((m) => Map<String, dynamic>.from(m as Map)).toList();
      final reassignments = (merge['weighmentReassignments'] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();

      // Restore merged customers
      for (final customer in mergedCustomers) {
        final custId = customer['id'] as String;
        final data = Map<String, dynamic>.from(customer)..remove('id');
        data['updatedAt'] = Timestamp.now();
        await db.customers.doc(custId).set(data);
      }

      // Revert weighment reassignments
      if (reassignments.isNotEmpty) {
        final chunks = <List<Map<String, dynamic>>>[];
        for (var i = 0; i < reassignments.length; i += 450) {
          chunks.add(reassignments.sublist(i, i + 450 > reassignments.length ? reassignments.length : i + 450));
        }
        for (final chunk in chunks) {
          final batch = db.batch();
          for (final r in chunk) {
            final wId = r['weighmentId'] as String;
            batch.update(db.weighments.doc(wId), {
              'customerName': r['originalCustomerName'],
              'customerPhone': r['originalCustomerPhone'],
            });
          }
          await batch.commit();
        }
      }

      // Restore primary customer to original state
      primarySnapshot['updatedAt'] = Timestamp.now();
      await db.customers.doc(primaryId).set(primarySnapshot);

      // Mark merge as reverted
      await db.customerMerges.doc(id).update({'reverted': true, 'revertedAt': Timestamp.now()});

      if (mounted) {
        setState(() {
          _reverting.remove(id);
          final idx = _merges?.indexWhere((m) => m['id'] == id);
          if (idx != null && idx >= 0) {
            _merges![idx]['reverted'] = true;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Merge reverted successfully'), backgroundColor: Theme.of(context).colorScheme.primary),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _reverting.remove(id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Revert failed: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 580,
        height: 480,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(color: scheme.surfaceContainerLow),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.merge_rounded, size: 18, color: scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Merge History', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text('View and revert past merges', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_merges == null || _merges!.isEmpty)
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.merge_rounded, size: 40, color: scheme.outlineVariant),
                              const SizedBox(height: 8),
                              Text('No merge history', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _merges!.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final merge = _merges![i];
                            final id = merge['id'] as String;
                            final primarySnap = merge['primarySnapshot'] as Map<String, dynamic>? ?? {};
                            final primaryName = primarySnap['name'] as String? ?? '--';
                            final mergedCustomers = (merge['mergedCustomers'] as List?) ?? [];
                            final mergedAt = merge['mergedAt'] as Timestamp?;
                            final isReverted = merge['reverted'] == true;
                            final isReverting = _reverting.contains(id);
                            final reassignCount = ((merge['weighmentReassignments'] as List?) ?? []).length;

                            final dateStr = mergedAt != null
                                ? '${mergedAt.toDate().day}/${mergedAt.toDate().month}/${mergedAt.toDate().year} ${mergedAt.toDate().hour.toString().padLeft(2, '0')}:${mergedAt.toDate().minute.toString().padLeft(2, '0')}'
                                : '--';

                            final primaryPhone = primarySnap['phone'] as String? ?? '';
                            final mergedDetails = mergedCustomers.map((c) {
                              final m = c as Map;
                              return {
                                'name': m['name'] as String? ?? '?',
                                'phone': m['phone'] as String? ?? '',
                                'weighments': m['totalWeighments'] as int? ?? 0,
                              };
                            }).toList();

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: isReverted ? scheme.surfaceContainerHighest.withValues(alpha: 0.3) : scheme.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Header: primary + date
                                  Row(
                                    children: [
                                      Icon(Icons.person_rounded, size: 14, color: scheme.primary),
                                      const SizedBox(width: 6),
                                      Text(primaryName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(3)),
                                        child: Text('PRIMARY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.primary, letterSpacing: 0.3)),
                                      ),
                                      if (primaryPhone.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Text(primaryPhone, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                                      ],
                                      const Spacer(),
                                      Text(dateStr, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Merged customers list
                                  ...mergedDetails.map((m) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        Icon(Icons.subdirectory_arrow_right_rounded, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
                                        const SizedBox(width: 6),
                                        Text(m['name'] as String, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurface)),
                                        if ((m['phone'] as String).isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Text(m['phone'] as String, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                                        ],
                                        if ((m['weighments'] as int) > 0) ...[
                                          const SizedBox(width: 6),
                                          Text('${m['weighments']} wt', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
                                        ],
                                      ],
                                    ),
                                  )),
                                  const SizedBox(height: 4),
                                  // Stats + revert
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(4)),
                                        child: Text('${mergedDetails.length} merged', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                                      ),
                                      if (reassignCount > 0) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(4)),
                                          child: Text('$reassignCount weighments moved', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                                        ),
                                      ],
                                      const Spacer(),
                                      if (isReverted)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(4)),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.undo_rounded, size: 12, color: scheme.onSurfaceVariant),
                                              const SizedBox(width: 4),
                                              Text('Reverted', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                                            ],
                                          ),
                                        )
                                      else if (isReverting)
                                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                      else
                                        TextButton(
                                          onPressed: () => _confirmRevert(merge),
                                          style: TextButton.styleFrom(
                                            foregroundColor: scheme.error,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          child: const Text('Revert', style: TextStyle(fontSize: 11)),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmRevert(Map<String, dynamic> merge) {
    final scheme = Theme.of(context).colorScheme;
    final primaryName = (merge['primarySnapshot'] as Map?)?['name'] as String? ?? '--';
    final mergedCount = ((merge['mergedCustomers'] as List?) ?? []).length;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.undo_rounded, size: 20, color: scheme.error),
                  const SizedBox(width: 10),
                  Text('Revert Merge?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'This will restore $mergedCount customer(s) that were merged into "$primaryName" and reassign their weighments back.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
                    child: const Text('Cancel', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _revertMerge(merge);
                    },
                    style: FilledButton.styleFrom(backgroundColor: scheme.error),
                    child: const Text('Revert', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DELETE CUSTOMER WITH WEIGHMENTS DIALOG
// ═══════════════════════════════════════════════════════════════════════════════

class _DeleteWithWeighmentsDialog extends StatefulWidget {
  final String customerName;
  final int weighmentCount;
  final String customerId;
  final WidgetRef ref;

  const _DeleteWithWeighmentsDialog({
    required this.customerName,
    required this.weighmentCount,
    required this.customerId,
    required this.ref,
  });

  @override
  State<_DeleteWithWeighmentsDialog> createState() => _DeleteWithWeighmentsDialogState();
}

class _DeleteWithWeighmentsDialogState extends State<_DeleteWithWeighmentsDialog> {
  String? _transferTarget;
  List<Map<String, dynamic>>? _otherCustomers;
  bool _loading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadOtherCustomers();
  }

  Future<void> _loadOtherCustomers() async {
    final db = widget.ref.read(firestorePathsProvider);
    final snap = await db.customers.get();
    if (mounted) {
      setState(() {
        _otherCustomers = snap.docs
            .where((d) => d.id != widget.customerId)
            .map((d) => {'id': d.id, ...d.data()})
            .toList()
          ..sort((a, b) => (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));
      });
    }
  }

  Future<void> _archive() async {
    setState(() => _loading = true);
    try {
      final db = widget.ref.read(firestorePathsProvider);

      // Check if vehicle number should be anonymized
      final securitySettings = widget.ref.read(securitySettingsProvider).valueOrNull;
      final anonymizeVehicle = securitySettings?.anonymizeVehicleOnArchive ?? false;

      // Get customer's face photo to preserve on weighments
      final custDoc = await db.customers.doc(widget.customerId).get();
      final custData = custDoc.exists ? custDoc.data()! : <String, dynamic>{};
      final customerFace = custData['firstFace'] as String? ?? custData['lastFace'] as String?;

      // Anonymize weighments — remove customer identity but keep weights/material
      final weighments = await db.weighments.where('customerName', isEqualTo: widget.customerName).get();
      if (weighments.docs.isNotEmpty) {
        final chunks = <List<QueryDocumentSnapshot>>[];
        for (var i = 0; i < weighments.docs.length; i += 450) {
          chunks.add(weighments.docs.sublist(i, i + 450 > weighments.docs.length ? weighments.docs.length : i + 450));
        }
        for (final chunk in chunks) {
          final batch = db.batch();
          for (final doc in chunk) {
            final updateData = <String, dynamic>{
              'customerName': '[Archived]',
              'customerPhone': '',
              'archivedCustomerId': widget.customerId,
            };
            if (anonymizeVehicle) {
              updateData['vehicleNumber'] = '[Archived]';
            }
            if (customerFace != null && customerFace.isNotEmpty) {
              updateData['archivedCustomerFace'] = customerFace;
            }
            batch.update(doc.reference, updateData);
          }
          await batch.commit();
        }
      }

      // Move customer to deleted
      final data = <String, dynamic>{};
      if (custDoc.exists) data.addAll(custData);
      data.remove('id');
      data['deletedAt'] = Timestamp.now();
      data['originalId'] = widget.customerId;
      data['archiveReason'] = 'archived_with_weighments';
      data['archivedWeighmentCount'] = weighments.docs.length;
      await db.customersDeleted.doc(widget.customerId).set(data);
      await db.customers.doc(widget.customerId).delete();

      if (mounted) {
        Navigator.pop(context, 'done');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Archived "${widget.customerName}" — ${weighments.docs.length} weighments anonymized'), backgroundColor: Theme.of(context).colorScheme.primary),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Archive failed: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  Future<void> _transfer() async {
    if (_transferTarget == null) return;
    setState(() => _loading = true);
    try {
      final db = widget.ref.read(firestorePathsProvider);

      final targetDoc = await db.customers.doc(_transferTarget!).get();
      if (!targetDoc.exists) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final targetData = targetDoc.data()!;
      final targetName = targetData['name'] as String? ?? '';
      final targetPhone = targetData['phone'] as String? ?? '';

      // Transfer all weighments
      final weighments = await db.weighments.where('customerName', isEqualTo: widget.customerName).get();
      if (weighments.docs.isNotEmpty) {
        final chunks = <List<QueryDocumentSnapshot>>[];
        for (var i = 0; i < weighments.docs.length; i += 450) {
          chunks.add(weighments.docs.sublist(i, i + 450 > weighments.docs.length ? weighments.docs.length : i + 450));
        }
        for (final chunk in chunks) {
          final batch = db.batch();
          for (final doc in chunk) {
            batch.update(doc.reference, {'customerName': targetName, 'customerPhone': targetPhone});
          }
          await batch.commit();
        }
      }

      // Update target customer weighment count
      final targetWeighments = (targetData['totalWeighments'] as int? ?? 0) + weighments.docs.length;
      await db.customers.doc(_transferTarget!).update({'totalWeighments': targetWeighments, 'updatedAt': Timestamp.now()});

      // Delete the source customer (now has 0 weighments)
      final srcData = <String, dynamic>{};
      final srcDoc = await db.customers.doc(widget.customerId).get();
      if (srcDoc.exists) srcData.addAll(srcDoc.data()!);
      srcData.remove('id');
      srcData['deletedAt'] = Timestamp.now();
      srcData['originalId'] = widget.customerId;
      srcData['transferredTo'] = _transferTarget;
      srcData['transferredToName'] = targetName;
      srcData['transferredWeighments'] = weighments.docs.length;
      srcData['transferredWeighmentIds'] = weighments.docs.map((d) => d.id).toList();
      await db.customersDeleted.doc(widget.customerId).set(srcData);
      await db.customers.doc(widget.customerId).delete();

      if (mounted) {
        Navigator.pop(context, 'done');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transferred ${weighments.docs.length} weighments to "$targetName" and deleted "${widget.customerName}"'), backgroundColor: Theme.of(context).colorScheme.primary),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transfer failed: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final filteredCustomers = _otherCustomers?.where((c) {
      if (_searchQuery.isEmpty) return true;
      final name = (c['name'] as String? ?? '').toLowerCase();
      final phone = (c['phone'] as String? ?? '').toLowerCase();
      return name.contains(_searchQuery) || phone.contains(_searchQuery);
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 500,
        height: 520,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.15),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.person_off_rounded, size: 18, color: scheme.error),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Delete "${widget.customerName}"', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                        Text('${widget.weighmentCount} weighments on this account', style: TextStyle(fontSize: 11, color: scheme.error)),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, size: 20)),
                ],
              ),
            ),
            const Divider(height: 1),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Choose how to handle the weighments:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                      const SizedBox(height: 12),
                      // Option 1: Archive
                      GestureDetector(
                        onTap: _archive,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                                child: Icon(Icons.archive_rounded, size: 16, color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Archive & Anonymize', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                                    Text('Weighments stay but customer identity is permanently hidden', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded, size: 18, color: scheme.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Option 2: Transfer
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 32, height: 32,
                                  decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
                                  child: Icon(Icons.swap_horiz_rounded, size: 16, color: scheme.primary),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Transfer & Delete', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                                      Text('Move all weighments to another customer, then delete', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 32,
                              child: TextField(
                                onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                                decoration: InputDecoration(
                                  hintText: 'Search customer to transfer to...',
                                  hintStyle: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                                  prefixIcon: Icon(Icons.search, size: 16, color: scheme.onSurfaceVariant),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: scheme.outlineVariant)),
                                  isDense: true,
                                ),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 160,
                              child: filteredCustomers == null
                                  ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                                  : filteredCustomers.isEmpty
                                      ? Center(child: Text('No customers found', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)))
                                      : ListView.separated(
                                          itemCount: filteredCustomers.length,
                                          separatorBuilder: (_, __) => const SizedBox(height: 4),
                                          itemBuilder: (_, i) {
                                            final c = filteredCustomers[i];
                                            final cId = c['id'] as String;
                                            final cName = c['name'] as String? ?? '--';
                                            final cPhone = c['phone'] as String? ?? '';
                                            final isSelected = _transferTarget == cId;
                                            return GestureDetector(
                                              onTap: () => setState(() => _transferTarget = cId),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: isSelected ? scheme.primaryContainer.withValues(alpha: 0.3) : Colors.transparent,
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: isSelected ? Border.all(color: scheme.primary.withValues(alpha: 0.4)) : null,
                                                ),
                                                child: Row(
                                                  children: [
                                                    if (isSelected)
                                                      Icon(Icons.check_circle_rounded, size: 14, color: scheme.primary)
                                                    else
                                                      Icon(Icons.radio_button_unchecked_rounded, size: 14, color: scheme.outlineVariant),
                                                    const SizedBox(width: 8),
                                                    Expanded(child: Text(cName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface))),
                                                    if (cPhone.isNotEmpty)
                                                      Text(cPhone, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                            ),
                            if (_transferTarget != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton(
                                    onPressed: _transfer,
                                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                                    child: const Text('Transfer & Delete', style: TextStyle(fontSize: 12)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FACE CAPTURE DIALOG (for existing customer without face)
// ═══════════════════════════════════════════════════════════════════════════════

class _FaceCaptureForCustomerDialog extends StatefulWidget {
  final WidgetRef ref;
  final String customerId;
  const _FaceCaptureForCustomerDialog({required this.ref, required this.customerId});

  @override
  State<_FaceCaptureForCustomerDialog> createState() => _FaceCaptureForCustomerDialogState();
}

class _FaceCaptureForCustomerDialogState extends State<_FaceCaptureForCustomerDialog> {
  Uint8List? _liveFrame;
  Uint8List? _capturedFace;
  Timer? _frameTimer;
  bool _scanning = false;
  bool _faceDetected = false;
  bool _saving = false;
  int _frameCount = 0;
  int _deviceIndex = 0;
  bool _capturing = false;
  String _status = '';
  bool _showCameraPicker = false;
  List<String> _availableCameras = [];

  String get _frameCachePath {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    final dir = Directory('$home/.weighbridge/frames');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    super.dispose();
  }

  Future<List<String>> _getSystemCameras() async {
    try {
      final result = await Process.run('system_profiler', ['SPCameraDataType', '-json']);
      if (result.exitCode == 0) {
        final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
        final cams = data['SPCameraDataType'] as List<dynamic>? ?? [];
        return cams.map((c) => (c as Map<String, dynamic>)['_name'] as String? ?? 'Unknown').toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _startScan() async {
    setState(() { _scanning = true; _status = 'Initializing camera...'; _faceDetected = false; _frameCount = 0; _showCameraPicker = false; });

    final systemCams = await _getSystemCameras();
    bool camFound = false;
    Map<String, dynamic>? allConfiguredCams;

    try {
      final db = widget.ref.read(firestorePathsProvider);
      final camDoc = await db.camerasAiSettings.get();
      if (camDoc.exists) {
        allConfiguredCams = camDoc.data()?['cameras'] as Map<String, dynamic>?;
        final customerCam = allConfiguredCams?['customer'] as Map<String, dynamic>?;
        if (customerCam != null && customerCam['enabled'] == true) {
          final source = customerCam['source'] as String? ?? 'Built-in';
          final deviceName = source == 'USB'
              ? customerCam['usbDevice'] as String? ?? ''
              : customerCam['builtInDevice'] as String? ?? '';
          if (deviceName.isNotEmpty) {
            final idx = systemCams.indexOf(deviceName);
            if (idx >= 0) { _deviceIndex = idx; camFound = true; }
          }
        }
      }
    } catch (_) {}

    if (!camFound) {
      if (!mounted) return;
      if (systemCams.isEmpty) {
        setState(() { _status = 'No cameras detected'; _scanning = false; });
        return;
      }
      if (systemCams.length == 1 && (allConfiguredCams == null || allConfiguredCams.isEmpty)) {
        _deviceIndex = 0;
      } else {
        // Build combined list: configured cameras + system cameras
        final pickerList = <String>[];
        if (allConfiguredCams != null) {
          const labels = {'front': 'Front View', 'rear': 'Rear View', 'top': 'Top View', 'side': 'Side View', 'operator': 'Operator', 'customer': 'Customer'};
          for (final entry in allConfiguredCams.entries) {
            final cam = entry.value as Map<String, dynamic>?;
            if (cam == null || cam['enabled'] != true) continue;
            final source = cam['source'] as String? ?? 'Built-in';
            final deviceName = source == 'USB' ? cam['usbDevice'] as String? ?? '' : cam['builtInDevice'] as String? ?? '';
            if (deviceName.isNotEmpty && systemCams.contains(deviceName)) {
              pickerList.add('${labels[entry.key] ?? entry.key} ($deviceName)');
            }
          }
        }
        for (final cam in systemCams) {
          if (!pickerList.any((p) => p.contains(cam))) {
            pickerList.add(cam);
          }
        }
        setState(() { _availableCameras = pickerList; _showCameraPicker = true; _scanning = false; });
        return;
      }
    }

    _beginCapture();
  }

  void _selectCameraAndScan(int index) {
    // Resolve device index from picker label
    final label = _availableCameras[index];
    // Extract device name from "Label (DeviceName)" or use as-is
    final match = RegExp(r'\((.+)\)$').firstMatch(label);
    final deviceName = match != null ? match.group(1)! : label;
    _getSystemCameras().then((systemCams) {
      final idx = systemCams.indexOf(deviceName);
      _deviceIndex = idx >= 0 ? idx : index;
      setState(() { _showCameraPicker = false; _scanning = true; _status = 'Initializing camera...'; });
      _beginCapture();
    });
  }

  void _beginCapture() {
    _captureFrame();
    _frameTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_scanning && !_capturing) _captureFrame();
    });
  }

  Future<void> _captureFrame() async {
    if (_capturing) return;
    _capturing = true;
    final framePath = '$_frameCachePath/customer_capture_live.jpg';
    try {
      final result = await Process.run('ffmpeg', [
        '-y', '-f', 'avfoundation', '-framerate', '30',
        '-i', '$_deviceIndex:none', '-frames:v', '1',
        '-update', '1', '-q:v', '3', framePath,
      ], stdoutEncoding: utf8, stderrEncoding: utf8);

      if (!mounted) return;
      final file = File(framePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty && mounted) {
          _frameCount++;
          setState(() {
            _liveFrame = bytes;
            if (_frameCount >= 3 && !_faceDetected) {
              _faceDetected = true;
              _status = 'Face detected — tap Capture';
            } else if (!_faceDetected) {
              _status = 'Detecting face...';
            }
          });
        }
      } else {
        final err = (result.stderr as String).toLowerCase();
        if (err.contains('permission') || err.contains('denied')) {
          setState(() { _status = 'Camera permission denied'; _scanning = false; });
          _frameTimer?.cancel();
        }
      }
    } catch (_) {
      if (mounted) { setState(() { _status = 'ffmpeg not found'; _scanning = false; }); _frameTimer?.cancel(); }
    } finally {
      _capturing = false;
    }
  }

  void _captureFace() {
    if (_liveFrame == null) return;
    _frameTimer?.cancel();
    setState(() { _capturedFace = _liveFrame; _scanning = false; });
  }

  void _retake() {
    setState(() { _capturedFace = null; _liveFrame = null; _faceDetected = false; _frameCount = 0; });
    _startScan();
  }

  Future<void> _saveFace() async {
    if (_capturedFace == null) return;
    setState(() => _saving = true);
    final faceBase64 = base64Encode(_capturedFace!);

    final db = widget.ref.read(firestorePathsProvider);
    await db.customers.doc(widget.customerId).update({
      'firstFace': faceBase64,
      'faceScannedAt': Timestamp.now(),
    });

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Face captured successfully'), backgroundColor: Theme.of(context).colorScheme.primary),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.3)),
              child: Row(
                children: [
                  Icon(Icons.face_rounded, size: 20, color: scheme.primary),
                  const SizedBox(width: 10),
                  Text('Capture Face', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    onPressed: () { _frameTimer?.cancel(); Navigator.pop(context); },
                    icon: const Icon(Icons.close_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // Camera feed area
            Container(
              width: double.infinity,
              height: 260,
              color: scheme.surfaceContainerLow,
              child: _buildCameraContent(scheme, text),
            ),

            // Actions
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildActions(scheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraContent(ColorScheme scheme, TextTheme text) {
    if (_showCameraPicker) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off_rounded, size: 24, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text('Customer camera not configured', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            Text('Select a camera:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.primary)),
            const SizedBox(height: 8),
            ...List.generate(_availableCameras.length, (i) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SizedBox(
                width: double.infinity,
                height: 32,
                child: OutlinedButton(
                  onPressed: () => _selectCameraAndScan(i),
                  style: OutlinedButton.styleFrom(side: BorderSide(color: scheme.primary.withValues(alpha: 0.4))),
                  child: Text(_availableCameras[i], style: TextStyle(fontSize: 11, color: scheme.primary)),
                ),
              ),
            )),
          ],
        ),
      );
    }

    if (_capturedFace != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(_capturedFace!, fit: BoxFit.cover),
          Positioned(
            bottom: 8, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                child: const Text('Preview — save or retake', style: TextStyle(fontSize: 10, color: Colors.white70)),
              ),
            ),
          ),
        ],
      );
    }

    if (_scanning && _liveFrame != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(_liveFrame!, fit: BoxFit.cover, gaplessPlayback: true),
          Positioned(
            top: 8, left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (_faceDetected ? Colors.green : Colors.orange).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_faceDetected ? Icons.face_rounded : Icons.face_retouching_off_rounded, size: 12, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(_faceDetected ? 'Detected' : 'Searching...', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          Positioned.fill(child: CustomPaint(painter: _FaceScanGuidePainter(detected: _faceDetected, scheme: Theme.of(context).colorScheme))),
        ],
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary)),
          const SizedBox(height: 10),
          Text(_status, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildActions(ColorScheme scheme) {
    if (_capturedFace != null) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _retake,
              child: const Text('Retake'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: _saving ? null : _saveFace,
              child: Text(_saving ? 'Saving...' : 'Save Face'),
            ),
          ),
        ],
      );
    }

    if (_scanning) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () { _frameTimer?.cancel(); Navigator.pop(context); },
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: _faceDetected ? _captureFace : null,
              child: const Text('Capture'),
            ),
          ),
        ],
      );
    }

    return OutlinedButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('Close'),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ADD CUSTOMER DIALOG WITH FACE SCAN
// ═══════════════════════════════════════════════════════════════════════════════

class _AddCustomerDialog extends StatefulWidget {
  final WidgetRef ref;
  const _AddCustomerDialog({required this.ref});

  @override
  State<_AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<_AddCustomerDialog> {
  final _nameC = TextEditingController();
  final _phoneC = TextEditingController();
  final _addressC = TextEditingController();

  Uint8List? _liveFrame;
  Uint8List? _capturedFace;
  Timer? _frameTimer;
  bool _scanning = false;
  bool _faceDetected = false;
  bool _saving = false;
  int _frameCount = 0;
  int _deviceIndex = 0;
  bool _capturing = false;
  String _status = '';
  bool _showCameraPicker = false;
  List<String> _availableCameras = [];

  // Site & WB selection
  String? _selectedSiteId;
  String? _selectedWbId;
  List<Map<String, dynamic>> _sites = [];
  List<Map<String, dynamic>> _wbs = [];

  String get _frameCachePath {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    final dir = Directory('$home/.weighbridge/frames');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  @override
  void initState() {
    super.initState();
    _loadSites();
  }

  Future<void> _loadSites() async {
    final db = widget.ref.read(firestorePathsProvider);
    final ctx = widget.ref.read(siteContextProvider);
    try {
      final sitesSnap = await db.firestore.collection('companies/${ctx.companyId}/sites').get();
      final sites = sitesSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      if (mounted) {
        setState(() {
          _sites = sites;
          _selectedSiteId = ctx.siteId;
        });
        _loadWbsForSite(ctx.siteId);
      }
    } catch (_) {}
  }

  Future<void> _loadWbsForSite(String siteId) async {
    final db = widget.ref.read(firestorePathsProvider);
    final ctx = widget.ref.read(siteContextProvider);
    try {
      final wbsSnap = await db.firestore.collection('companies/${ctx.companyId}/sites/$siteId/weighbridges').get();
      final wbs = wbsSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      if (mounted) {
        setState(() {
          _wbs = wbs;
          _selectedWbId = wbs.length == 1 ? wbs.first['id'] as String : (siteId == ctx.siteId ? ctx.weighbridgeId : null);
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _nameC.dispose();
    _phoneC.dispose();
    _addressC.dispose();
    super.dispose();
  }

  Future<List<String>> _getSystemCameras() async {
    try {
      final result = await Process.run('system_profiler', ['SPCameraDataType', '-json']);
      if (result.exitCode == 0) {
        final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
        final cams = data['SPCameraDataType'] as List<dynamic>? ?? [];
        return cams.map((c) => (c as Map<String, dynamic>)['_name'] as String? ?? 'Unknown').toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _startScan() async {
    if (_selectedSiteId == null) {
      setState(() { _status = 'Select a site first'; });
      return;
    }
    if (_wbs.length > 1 && _selectedWbId == null) {
      setState(() { _status = 'Select a weighbridge for camera'; });
      return;
    }

    setState(() { _scanning = true; _status = 'Initializing camera...'; _faceDetected = false; _frameCount = 0; _showCameraPicker = false; });

    final systemCams = await _getSystemCameras();
    bool customerCamFound = false;
    Map<String, dynamic>? allConfiguredCams;

    try {
      final db = widget.ref.read(firestorePathsProvider);
      final ctx = widget.ref.read(siteContextProvider);
      final wbId = _selectedWbId ?? ctx.weighbridgeId;
      final camDocRef = db.firestore.doc('companies/${ctx.companyId}/sites/$_selectedSiteId/weighbridges/$wbId/settings/camerasAi');
      final camDoc = await camDocRef.get();
      if (camDoc.exists) {
        allConfiguredCams = camDoc.data()?['cameras'] as Map<String, dynamic>?;
        final customerCam = allConfiguredCams?['customer'] as Map<String, dynamic>?;
        if (customerCam != null && customerCam['enabled'] == true) {
          final source = customerCam['source'] as String? ?? 'Built-in';
          final deviceName = source == 'USB'
              ? customerCam['usbDevice'] as String? ?? ''
              : customerCam['builtInDevice'] as String? ?? '';
          if (deviceName.isNotEmpty) {
            final idx = systemCams.indexOf(deviceName);
            if (idx >= 0) { _deviceIndex = idx; customerCamFound = true; }
          }
        }
      }
    } catch (_) {}

    if (!customerCamFound) {
      if (!mounted) return;
      if (systemCams.isEmpty) {
        setState(() { _status = 'No cameras detected'; _scanning = false; });
        return;
      }
      if (systemCams.length == 1 && (allConfiguredCams == null || allConfiguredCams.isEmpty)) {
        _deviceIndex = 0;
      } else {
        final pickerList = <String>[];
        if (allConfiguredCams != null) {
          const labels = {'front': 'Front View', 'rear': 'Rear View', 'top': 'Top View', 'side': 'Side View', 'operator': 'Operator', 'customer': 'Customer'};
          for (final entry in allConfiguredCams.entries) {
            final cam = entry.value as Map<String, dynamic>?;
            if (cam == null || cam['enabled'] != true) continue;
            final source = cam['source'] as String? ?? 'Built-in';
            final deviceName = source == 'USB' ? cam['usbDevice'] as String? ?? '' : cam['builtInDevice'] as String? ?? '';
            if (deviceName.isNotEmpty && systemCams.contains(deviceName)) {
              pickerList.add('${labels[entry.key] ?? entry.key} ($deviceName)');
            }
          }
        }
        for (final cam in systemCams) {
          if (!pickerList.any((p) => p.contains(cam))) {
            pickerList.add(cam);
          }
        }
        setState(() { _availableCameras = pickerList; _showCameraPicker = true; _scanning = false; });
        return;
      }
    }

    _beginCapture();
  }

  void _selectCameraAndScan(int index) {
    final label = _availableCameras[index];
    final match = RegExp(r'\((.+)\)$').firstMatch(label);
    final deviceName = match != null ? match.group(1)! : label;
    _getSystemCameras().then((systemCams) {
      final idx = systemCams.indexOf(deviceName);
      _deviceIndex = idx >= 0 ? idx : index;
      setState(() { _showCameraPicker = false; _scanning = true; _status = 'Initializing camera...'; });
      _beginCapture();
    });
  }

  void _beginCapture() {
    _captureFrame();
    _frameTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_scanning && !_capturing) _captureFrame();
    });
  }

  Future<void> _captureFrame() async {
    if (_capturing) return;
    _capturing = true;
    final framePath = '$_frameCachePath/customer_scan_live.jpg';

    try {
      final result = await Process.run('ffmpeg', [
        '-y', '-f', 'avfoundation', '-framerate', '30',
        '-i', '$_deviceIndex:none', '-frames:v', '1',
        '-update', '1', '-q:v', '3', framePath,
      ], stdoutEncoding: utf8, stderrEncoding: utf8);

      if (!mounted) return;
      final file = File(framePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty && mounted) {
          _frameCount++;
          setState(() {
            _liveFrame = bytes;
            if (_frameCount >= 3 && !_faceDetected) {
              _faceDetected = true;
              _status = 'Face detected — tap Capture';
            } else if (!_faceDetected) {
              _status = 'Detecting face...';
            }
          });
        }
      } else {
        final err = (result.stderr as String).toLowerCase();
        if (err.contains('permission') || err.contains('denied')) {
          setState(() { _status = 'Camera permission denied'; _scanning = false; });
          _frameTimer?.cancel();
        } else if (err.contains('no such') || err.contains('cannot open')) {
          setState(() { _status = 'Camera not available'; _scanning = false; });
          _frameTimer?.cancel();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() { _status = 'ffmpeg not found'; _scanning = false; });
        _frameTimer?.cancel();
      }
    } finally {
      _capturing = false;
    }
  }

  void _captureFace() {
    if (_liveFrame == null) return;
    _frameTimer?.cancel();
    setState(() { _capturedFace = _liveFrame; _scanning = false; });
  }

  void _retake() {
    setState(() { _capturedFace = null; _liveFrame = null; });
    _startScan();
  }

  void _removeFace() {
    setState(() { _capturedFace = null; _liveFrame = null; _faceDetected = false; _frameCount = 0; });
  }

  Future<void> _save() async {
    if (_nameC.text.trim().isEmpty || _phoneC.text.trim().isEmpty) return;
    if (_selectedSiteId == null) return;
    setState(() => _saving = true);

    final db = widget.ref.read(firestorePathsProvider);
    final phone = _phoneC.text.trim();

    // Check phone duplication
    final existing = await db.customers.where('phone', isEqualTo: phone).get();
    if (existing.docs.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Phone $phone already belongs to another customer'), backgroundColor: Theme.of(context).colorScheme.error),
        );
        setState(() => _saving = false);
      }
      return;
    }

    final now = Timestamp.now();
    final data = <String, dynamic>{
      'name': toTitleCase(_nameC.text.trim()),
      'phone': phone,
      'address': _addressC.text.trim().isEmpty ? null : toTitleCase(_addressC.text.trim()),
      'siteId': _selectedSiteId,
      'totalWeighments': 0,
      'createdAt': now,
      'updatedAt': now,
    };

    if (_capturedFace != null) {
      data['firstFace'] = base64Encode(_capturedFace!);
      data['faceScannedAt'] = now;
    }

    await db.customers.add(data);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.3)),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.person_add_rounded, size: 20, color: scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('New Customer', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text('Add a new customer to the system', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),

            // Site & WB selector
            if (_sites.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedSiteId,
                        isExpanded: true,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Site *',
                          prefixIcon: const Icon(Icons.location_on_rounded, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                        items: _sites.map((s) => DropdownMenuItem(
                          value: s['id'] as String,
                          child: Text(s['name'] as String? ?? s['id'] as String, style: const TextStyle(fontSize: 13)),
                        )).toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _selectedSiteId = v;
                            _selectedWbId = null;
                            _wbs = [];
                          });
                          _loadWbsForSite(v);
                        },
                      ),
                    ),
                    if (_wbs.length > 1) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedWbId,
                          isExpanded: true,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Camera from WB',
                            prefixIcon: const Icon(Icons.videocam_rounded, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                          items: _wbs.map((w) => DropdownMenuItem(
                            value: w['id'] as String,
                            child: Text(w['name'] as String? ?? w['id'] as String, style: const TextStyle(fontSize: 13)),
                          )).toList(),
                          onChanged: (v) => setState(() => _selectedWbId = v),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: Face scan area
                  SizedBox(
                    width: 160,
                    child: Column(
                      children: [
                        Container(
                          width: 160,
                          height: 180,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _capturedFace != null
                                  ? scheme.primary
                                  : _scanning ? scheme.tertiary.withValues(alpha: 0.6) : scheme.outlineVariant.withValues(alpha: 0.5),
                              width: _capturedFace != null || _scanning ? 2 : 1.5,
                            ),
                            color: scheme.surfaceContainerLow,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _buildFaceArea(scheme, text),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildFaceActions(scheme),
                      ],
                    ),
                  ),

                  const SizedBox(width: 20),

                  // Right: Form fields
                  Expanded(
                    child: Column(
                      children: [
                        TextField(
                          controller: _nameC,
                          autofocus: true,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Full Name *',
                            hintText: 'e.g. Rajesh Kumar',
                            prefixIcon: const Icon(Icons.person_rounded, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _phoneC,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Phone Number *',
                            hintText: 'e.g. 9876543210',
                            prefixIcon: const Icon(Icons.phone_rounded, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _addressC,
                          maxLines: 1,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Address',
                            hintText: 'Village, District, State',
                            prefixIcon: const Icon(Icons.location_on_rounded, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 13, color: scheme.outline),
                  const SizedBox(width: 6),
                  Text('* Required fields', style: TextStyle(fontSize: 10, color: scheme.outline)),
                  const Spacer(),
                  TextButton(
                    onPressed: () { _frameTimer?.cancel(); Navigator.pop(context); },
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving...' : 'Add Customer'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFaceArea(ColorScheme scheme, TextTheme text) {
    // Captured face (review)
    if (_capturedFace != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(_capturedFace!, fit: BoxFit.cover),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_rounded, size: 12, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text('Face captured', style: TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Camera picker — customer camera not configured
    if (_showCameraPicker) {
      return Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off_rounded, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(height: 6),
            Text('Customer camera\nnot configured', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant, height: 1.3)),
            const SizedBox(height: 10),
            Text('Select camera:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.primary)),
            const SizedBox(height: 6),
            ...List.generate(_availableCameras.length, (i) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SizedBox(
                width: double.infinity,
                height: 26,
                child: OutlinedButton(
                  onPressed: () => _selectCameraAndScan(i),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: Text(
                    _availableCameras[i],
                    style: TextStyle(fontSize: 10, color: scheme.primary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            )),
          ],
        ),
      );
    }

    // Live scanning feed
    if (_scanning) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (_liveFrame != null)
            Image.memory(_liveFrame!, fit: BoxFit.cover, gaplessPlayback: true)
          else
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary)),
                  const SizedBox(height: 8),
                  Text(_status, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          if (_liveFrame != null)
            Positioned(
              top: 6, left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: (_faceDetected ? Colors.green : Colors.orange).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_faceDetected ? Icons.face_rounded : Icons.face_retouching_off_rounded, size: 11, color: Colors.white),
                    const SizedBox(width: 3),
                    Text(
                      _faceDetected ? 'Detected' : 'Searching...',
                      style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          if (_liveFrame != null)
            Positioned.fill(child: CustomPaint(painter: _FaceScanGuidePainter(detected: _faceDetected, scheme: scheme))),
        ],
      );
    }

    // Empty state — prompt to scan
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.face_rounded, size: 28, color: scheme.primary.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 10),
        Text('Scan Face', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text('Optional', style: TextStyle(fontSize: 10, color: scheme.outline)),
      ],
    );
  }

  Widget _buildFaceActions(ColorScheme scheme) {
    if (_capturedFace != null) {
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 30,
              child: OutlinedButton(
                onPressed: _retake,
                style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                child: const Text('Retake', style: TextStyle(fontSize: 10)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SizedBox(
              height: 30,
              child: OutlinedButton(
                onPressed: _removeFace,
                style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: scheme.error, side: BorderSide(color: scheme.error.withValues(alpha: 0.4))),
                child: const Text('Remove', style: TextStyle(fontSize: 10)),
              ),
            ),
          ),
        ],
      );
    }

    if (_scanning) {
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 30,
              child: OutlinedButton(
                onPressed: () { _frameTimer?.cancel(); setState(() { _scanning = false; _liveFrame = null; }); },
                style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                child: const Text('Cancel', style: TextStyle(fontSize: 10)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SizedBox(
              height: 30,
              child: FilledButton(
                onPressed: _faceDetected ? _captureFace : null,
                style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                child: const Text('Capture', style: TextStyle(fontSize: 10)),
              ),
            ),
          ),
        ],
      );
    }

    if (_showCameraPicker) {
      return SizedBox(
        width: 160,
        height: 30,
        child: OutlinedButton(
          onPressed: () => setState(() => _showCameraPicker = false),
          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
          child: const Text('Cancel', style: TextStyle(fontSize: 10)),
        ),
      );
    }

    return SizedBox(
      width: 160,
      height: 32,
      child: OutlinedButton(
        onPressed: _startScan,
        style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, side: BorderSide(color: scheme.primary.withValues(alpha: 0.4))),
        child: Text('Scan Face', style: TextStyle(fontSize: 11, color: scheme.primary)),
      ),
    );
  }
}

class _FaceScanGuidePainter extends CustomPainter {
  final bool detected;
  final ColorScheme scheme;

  _FaceScanGuidePainter({required this.detected, required this.scheme});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = detected ? Colors.green : Colors.white60
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final rx = size.width * 0.32;
    final ry = size.height * 0.38;
    const corner = 18.0;

    // Top-left
    canvas.drawLine(Offset(cx - rx, cy - ry), Offset(cx - rx + corner, cy - ry), paint);
    canvas.drawLine(Offset(cx - rx, cy - ry), Offset(cx - rx, cy - ry + corner), paint);
    // Top-right
    canvas.drawLine(Offset(cx + rx, cy - ry), Offset(cx + rx - corner, cy - ry), paint);
    canvas.drawLine(Offset(cx + rx, cy - ry), Offset(cx + rx, cy - ry + corner), paint);
    // Bottom-left
    canvas.drawLine(Offset(cx - rx, cy + ry), Offset(cx - rx + corner, cy + ry), paint);
    canvas.drawLine(Offset(cx - rx, cy + ry), Offset(cx - rx, cy + ry - corner), paint);
    // Bottom-right
    canvas.drawLine(Offset(cx + rx, cy + ry), Offset(cx + rx - corner, cy + ry), paint);
    canvas.drawLine(Offset(cx + rx, cy + ry), Offset(cx + rx, cy + ry - corner), paint);
  }

  @override
  bool shouldRepaint(covariant _FaceScanGuidePainter oldDelegate) => oldDelegate.detected != detected;
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOMER CARD (Grid view)
// ═══════════════════════════════════════════════════════════════════════════════

class _CustomerCard extends StatelessWidget {
  final Map<String, dynamic> customer;
  final ColorScheme scheme;
  final TextTheme text;
  final bool shouldMask;
  final String Function(String?) maskPhone;
  final bool isSelected;

  const _CustomerCard({
    required this.customer,
    required this.scheme,
    required this.text,
    required this.shouldMask,
    required this.maskPhone,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final name = customer['name'] as String? ?? '--';
    final phone = customer['phone'] as String? ?? '';
    final address = customer['address'] as String? ?? '';
    final firstFace = customer['firstFace'] as String?;
    final lastFace = customer['lastFace'] as String?;
    final weighments = customer['totalWeighments'] as int? ?? 0;
    final mergedFrom = (customer['mergedFrom'] as List?)?.cast<String>() ?? [];

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isSelected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.3), width: isSelected ? 2 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Face photos
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  _FaceSlot(facePath: firstFace, label: 'First', name: name, scheme: scheme),
                  _FaceSlot(facePath: lastFace, label: 'Last', name: name, scheme: scheme),
                ],
              ),
            ),
          ),
          // Info
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      TextSpan(text: '  •  ', style: TextStyle(fontSize: 13, color: scheme.outlineVariant)),
                      TextSpan(text: shouldMask ? maskPhone(phone) : (phone.isNotEmpty ? phone : '--'), style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
                      if (weighments > 0) TextSpan(text: '  ×$weighments', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (mergedFrom.isNotEmpty)
                  Tooltip(
                    message: 'Merged: ${mergedFrom.join(", ")}',
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(Icons.merge_rounded, size: 14, color: scheme.tertiary),
                    ),
                  ),
                if (address.isNotEmpty)
                  Text(
                    address,
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FACE WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _FaceSlot extends StatelessWidget {
  final String? facePath;
  final String label;
  final String name;
  final ColorScheme scheme;

  const _FaceSlot({required this.facePath, required this.label, required this.name, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: SizedBox.expand(child: _buildFaceImage(facePath, name, 120, scheme)),
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}


class _FacePreview extends StatelessWidget {
  final String facePath;
  final String label;
  final ColorScheme scheme;

  const _FacePreview({required this.facePath, required this.label, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.3), width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _buildFaceFromPath(facePath),
          ),
        ),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

Widget _buildFaceImage(String? facePath, String name, double size, ColorScheme scheme) {
  if (facePath != null && facePath.isNotEmpty) {
    return _buildFaceFromPath(facePath);
  }
  return Container(
    color: scheme.primaryContainer.withValues(alpha: 0.4),
    child: Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w700, color: scheme.primary),
      ),
    ),
  );
}

Widget _buildFaceFromPath(String path) {
  if (path.startsWith('/')) {
    final file = File(path);
    return FutureBuilder<bool>(
      future: file.exists(),
      builder: (_, snap) {
        if (snap.data == true) {
          return Image.file(file, fit: BoxFit.cover);
        }
        return const Icon(Icons.broken_image_rounded, size: 16);
      },
    );
  }
  if (path.startsWith('http')) {
    return Image.network(path, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, size: 16));
  }
  // Try base64
  try {
    String clean = path;
    if (clean.contains(',')) clean = clean.split(',').last;
    final bytes = base64Decode(clean);
    if (bytes.isNotEmpty) return Image.memory(Uint8List.fromList(bytes), fit: BoxFit.cover);
  } catch (_) {}
  return const Icon(Icons.face_rounded, size: 16);
}

// ═══════════════════════════════════════════════════════════════════════════════
// CSV IMPORT DIALOG — stays open through format guide → file pick → validate → edit → import
// ═══════════════════════════════════════════════════════════════════════════════

enum _CsvStage { guide, loading, review, importing, done }

class _CsvImportDialog extends StatefulWidget {
  final WidgetRef ref;
  const _CsvImportDialog({required this.ref});

  @override
  State<_CsvImportDialog> createState() => _CsvImportDialogState();
}

class _CsvImportDialogState extends State<_CsvImportDialog> {
  _CsvStage _stage = _CsvStage.guide;
  List<Map<String, String>> _rows = [];
  List<Map<String, String>> _invalidRows = [];
  String? _error;
  int _importedCount = 0;
  int _duplicateCount = 0;

  Future<void> _pickAndParse() async {
    setState(() { _stage = _CsvStage.loading; _error = null; });

    final result = await Process.run('osascript', [
      '-e',
      'set theFile to choose file of type {"public.comma-separated-values-text", "public.text", "public.plain-text"} with prompt "Select CSV file (Name, Phone, Address columns)"',
      '-e',
      'POSIX path of theFile',
    ]);
    final path = (result.stdout as String).trim();
    if (path.isEmpty) {
      setState(() => _stage = _CsvStage.guide);
      return;
    }

    final file = File(path);
    if (!file.existsSync()) {
      setState(() { _error = 'File not found'; _stage = _CsvStage.guide; });
      return;
    }

    final ext = path.split('.').last.toLowerCase();
    if (ext != 'csv' && ext != 'txt') {
      setState(() { _error = 'Invalid file type (.$ext). Only .csv or .txt files are accepted.'; _stage = _CsvStage.guide; });
      return;
    }

    final content = file.readAsStringSync();
    final csvRows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false).convert(content);
    if (csvRows.isEmpty) {
      setState(() { _error = 'File is empty'; _stage = _CsvStage.guide; });
      return;
    }

    // Detect header
    final firstRow = csvRows.first.map((e) => e.toString().toLowerCase().trim()).toList();
    int nameCol = -1, phoneCol = -1, addressCol = -1;
    for (var i = 0; i < firstRow.length; i++) {
      final h = firstRow[i];
      if (nameCol == -1 && (h.contains('name') || h.contains('party') || h.contains('customer'))) nameCol = i;
      else if (phoneCol == -1 && (h.contains('phone') || h.contains('mobile') || h.contains('number') || h.contains('contact'))) phoneCol = i;
      else if (addressCol == -1 && (h.contains('address') || h.contains('city') || h.contains('location'))) addressCol = i;
    }

    bool hasHeader = nameCol >= 0 || phoneCol >= 0 || addressCol >= 0;
    var dataRows = hasHeader ? csvRows.sublist(1) : csvRows;
    if (!hasHeader) {
      nameCol = 0;
      phoneCol = csvRows.first.length > 1 ? 1 : -1;
      addressCol = csvRows.first.length > 2 ? 2 : -1;
    }

    if (nameCol < 0) {
      setState(() { _error = 'Could not detect a Name column'; _stage = _CsvStage.guide; });
      return;
    }

    // Parse all rows
    final valid = <Map<String, String>>[];
    final invalid = <Map<String, String>>[];
    final seenPhones = <String>{};

    for (var i = 0; i < dataRows.length; i++) {
      final row = dataRows[i];
      if (row.isEmpty || row.every((c) => c.toString().trim().isEmpty)) continue;
      final name = nameCol < row.length ? row[nameCol].toString().trim() : '';
      final phone = phoneCol >= 0 && phoneCol < row.length ? row[phoneCol].toString().trim().replaceAll(RegExp(r'[^0-9]'), '') : '';
      final address = addressCol >= 0 && addressCol < row.length ? row[addressCol].toString().trim() : '';

      final entry = {'name': name, 'phone': phone, 'address': address};

      // Validate
      final issues = <String>[];
      if (name.isEmpty) issues.add('name');
      if (phone.isEmpty) issues.add('phone');
      else if (phone.length < 10) issues.add('phone<10');
      else if (phone.length > 12) issues.add('phone>12');
      else if (seenPhones.contains(phone)) issues.add('dup');
      if (address.isEmpty) issues.add('address');

      if (issues.isEmpty) {
        seenPhones.add(phone);
        valid.add(entry);
      } else {
        entry['_issues'] = issues.join(',');
        invalid.add(entry);
      }
    }

    if (valid.isEmpty && invalid.isEmpty) {
      setState(() { _error = 'No data rows found in file'; _stage = _CsvStage.guide; });
      return;
    }

    setState(() { _rows = valid; _invalidRows = invalid; _stage = _CsvStage.review; });
  }

  void _fixRow(int index, String name, String phone, String address) {
    final cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final issues = <String>[];
    if (name.trim().isEmpty) issues.add('name');
    if (cleaned.isEmpty) issues.add('phone');
    else if (cleaned.length < 10) issues.add('phone<10');
    else if (cleaned.length > 12) issues.add('phone>12');
    if (address.trim().isEmpty) issues.add('address');

    // Check dup against valid rows
    if (issues.isEmpty && _rows.any((r) => r['phone'] == cleaned)) {
      issues.add('dup');
    }

    setState(() {
      if (issues.isEmpty) {
        _invalidRows.removeAt(index);
        _rows.add({'name': name.trim(), 'phone': cleaned, 'address': address.trim()});
      } else {
        _invalidRows[index] = {'name': name.trim(), 'phone': cleaned, 'address': address.trim(), '_issues': issues.join(',')};
      }
    });
  }

  void _removeInvalidRow(int index) {
    setState(() => _invalidRows.removeAt(index));
  }

  Future<void> _doImport() async {
    if (_rows.isEmpty) return;
    setState(() => _stage = _CsvStage.importing);

    final db = widget.ref.read(firestorePathsProvider);
    final existing = widget.ref.read(_customersProvider).valueOrNull ?? [];
    final existingPhones = existing.map((c) => c['phone'] as String? ?? '').where((p) => p.isNotEmpty).toSet();
    final siteId = widget.ref.read(siteContextProvider).siteId;
    int imported = 0;
    int duplicates = 0;

    for (var i = 0; i < _rows.length; i += 500) {
      final chunk = _rows.sublist(i, (i + 500).clamp(0, _rows.length));
      final batch = db.batch();
      for (final row in chunk) {
        final phone = row['phone'] ?? '';
        if (existingPhones.contains(phone)) { duplicates++; continue; }
        existingPhones.add(phone);
        batch.set(db.customers.doc(), {
          'name': toTitleCase(row['name']!),
          'phone': phone,
          'address': row['address'] ?? '',
          'siteId': siteId,
          'totalWeighments': 0,
          'importedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });
        imported++;
      }
      await batch.commit();
    }

    setState(() { _importedCount = imported; _duplicateCount = duplicates; _stage = _CsvStage.done; });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 580),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
              decoration: BoxDecoration(color: scheme.surfaceContainerLow),
              child: Row(
                children: [
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(9)),
                    child: Icon(Icons.upload_file_rounded, size: 17, color: scheme.tertiary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Import Customers', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text(_stageSubtitle, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 11)),
                    ],
                  )),
                  if (_stage != _CsvStage.importing)
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, size: 20)),
                ],
              ),
            ),
            const Divider(height: 1),
            // Body
            Flexible(child: _buildBody(scheme, text)),
          ],
        ),
      ),
    );
  }

  String get _stageSubtitle => switch (_stage) {
    _CsvStage.guide => 'CSV format guide',
    _CsvStage.loading => 'Reading file...',
    _CsvStage.review => '${_rows.length} valid${_invalidRows.isNotEmpty ? ' · ${_invalidRows.length} need attention' : ''}',
    _CsvStage.importing => 'Importing...',
    _CsvStage.done => 'Import complete',
  };

  Widget _buildBody(ColorScheme scheme, TextTheme text) {
    return switch (_stage) {
      _CsvStage.guide => _buildGuide(scheme, text),
      _CsvStage.loading => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
      _CsvStage.review => _buildReview(scheme, text),
      _CsvStage.importing => const Center(child: Padding(padding: EdgeInsets.all(40), child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Importing customers...')]))),
      _CsvStage.done => _buildDone(scheme, text),
    };
  }

  Widget _buildGuide(ColorScheme scheme, TextTheme text) {
    return Column(
      children: [
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: scheme.errorContainer.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8), border: Border.all(color: scheme.error.withValues(alpha: 0.3))),
                  child: Row(children: [
                    Icon(Icons.error_outline_rounded, size: 14, color: scheme.error),
                    const SizedBox(width: 8),
                    Text(_error!, style: text.bodySmall?.copyWith(color: scheme.error, fontWeight: FontWeight.w500)),
                  ]),
                ),
              ],
              Text('Required Columns (all 3 mandatory)', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _CsvFormatRow(label: 'Name', description: 'Customer/party name', example: 'Rajesh Kumar', scheme: scheme, text: text),
              _CsvFormatRow(label: 'Phone', description: 'Mobile number (10-12 digits)', example: '9876543210', scheme: scheme, text: text),
              _CsvFormatRow(label: 'Address', description: 'Village/city/area', example: 'Vatva, Ahmedabad', scheme: scheme, text: text),
              const SizedBox(height: 16),
              Text('Accepted Formats', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(8), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('With header row:', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('Name, Phone, Address\nRajesh Kumar, 9876543210, Vatva', style: text.bodySmall?.copyWith(fontFamily: 'monospace', fontSize: 11, color: scheme.onSurfaceVariant, height: 1.5)),
                    const SizedBox(height: 10),
                    Text('Without header (columns in order):', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('Rajesh Kumar, 9876543210, Vatva\nSuresh Patel, 8765432109, Naroda', style: text.bodySmall?.copyWith(fontFamily: 'monospace', fontSize: 11, color: scheme.onSurfaceVariant, height: 1.5)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  Icon(Icons.lightbulb_outline_rounded, size: 14, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Header keywords: name/party/customer, phone/mobile/contact, address/city/location. Names are auto title-cased. Non-digit characters in phone are stripped.', style: text.bodySmall?.copyWith(fontSize: 11, color: scheme.primary))),
                ]),
              ),
            ],
          ),
        )),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Row(
            children: [
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _pickAndParse,
                icon: const Icon(Icons.file_open_rounded, size: 16),
                label: Text(_error != null ? 'Try Another File' : 'Select CSV File'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReview(ColorScheme scheme, TextTheme text) {
    return Column(
      children: [
        // Valid rows table
        if (_rows.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            alignment: Alignment.centerLeft,
            child: Row(children: [
              Icon(Icons.check_circle_rounded, size: 14, color: Colors.green.shade600),
              const SizedBox(width: 6),
              Text('${_rows.length} valid row${_rows.length != 1 ? 's' : ''}', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: Colors.green.shade700)),
            ]),
          ),
          Flexible(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3))),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                Container(
                  color: scheme.surfaceContainerLow,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Row(children: [
                    SizedBox(width: 28, child: Text('#', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant))),
                    Expanded(flex: 3, child: Text('Name', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700))),
                    Expanded(flex: 2, child: Text('Phone', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700))),
                    Expanded(flex: 3, child: Text('Address', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700))),
                  ]),
                ),
                Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
                Flexible(child: ListView.separated(
                  itemCount: _rows.length.clamp(0, 100),
                  separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.12)),
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      child: Row(children: [
                        SizedBox(width: 28, child: Text('${i + 1}', style: text.bodySmall?.copyWith(fontSize: 11, color: scheme.onSurfaceVariant))),
                        Expanded(flex: 3, child: Text(toTitleCase(r['name']!), style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                        Expanded(flex: 2, child: Text(r['phone']!, style: text.bodySmall, overflow: TextOverflow.ellipsis)),
                        Expanded(flex: 3, child: Text(r['address']!, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
                      ]),
                    );
                  },
                )),
                if (_rows.length > 100) ...[
                  Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text('+ ${_rows.length - 100} more', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 11))),
                ],
              ]),
            ),
          ),
        ],
        // Invalid rows — editable
        if (_invalidRows.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            alignment: Alignment.centerLeft,
            child: Row(children: [
              Icon(Icons.edit_note_rounded, size: 16, color: scheme.error),
              const SizedBox(width: 6),
              Text('${_invalidRows.length} row${_invalidRows.length != 1 ? 's' : ''} need fixing', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.error)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _invalidRows.clear()),
                icon: Icon(Icons.delete_sweep_rounded, size: 14, color: scheme.error),
                label: Text('Remove All', style: TextStyle(fontSize: 11, color: scheme.error)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
              ),
            ]),
          ),
          Flexible(
            flex: 2,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _invalidRows.length,
              itemBuilder: (_, i) => _InvalidRowTile(
                row: _invalidRows[i],
                index: i,
                scheme: scheme,
                text: text,
                onFix: _fixRow,
                onRemove: _removeInvalidRow,
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        // Footer
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Row(children: [
            OutlinedButton.icon(
              onPressed: _pickAndParse,
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text('Re-upload'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), textStyle: const TextStyle(fontSize: 12)),
            ),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _rows.isEmpty ? null : _doImport,
              icon: const Icon(Icons.upload_rounded, size: 16),
              label: Text('Import ${_rows.length} Customer${_rows.length != 1 ? 's' : ''}'),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _buildDone(ColorScheme scheme, TextTheme text) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 48, color: Colors.green.shade600),
          const SizedBox(height: 16),
          Text('$_importedCount customer${_importedCount != 1 ? 's' : ''} imported', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (_duplicateCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('$_duplicateCount duplicate phone${_duplicateCount != 1 ? 's' : ''} skipped', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          const SizedBox(height: 24),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      ),
    );
  }
}

class _InvalidRowTile extends StatefulWidget {
  final Map<String, String> row;
  final int index;
  final ColorScheme scheme;
  final TextTheme text;
  final void Function(int index, String name, String phone, String address) onFix;
  final void Function(int index) onRemove;

  const _InvalidRowTile({required this.row, required this.index, required this.scheme, required this.text, required this.onFix, required this.onRemove});

  @override
  State<_InvalidRowTile> createState() => _InvalidRowTileState();
}

class _InvalidRowTileState extends State<_InvalidRowTile> {
  late final TextEditingController _nameC;
  late final TextEditingController _phoneC;
  late final TextEditingController _addressC;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _nameC = TextEditingController(text: widget.row['name'] ?? '');
    _phoneC = TextEditingController(text: widget.row['phone'] ?? '');
    _addressC = TextEditingController(text: widget.row['address'] ?? '');
  }

  @override
  void didUpdateWidget(_InvalidRowTile old) {
    super.didUpdateWidget(old);
    if (old.row != widget.row) {
      _nameC.text = widget.row['name'] ?? '';
      _phoneC.text = widget.row['phone'] ?? '';
      _addressC.text = widget.row['address'] ?? '';
    }
  }

  @override
  void dispose() { _nameC.dispose(); _phoneC.dispose(); _addressC.dispose(); super.dispose(); }

  String _issueLabel(String code) => switch (code) {
    'name' => 'Missing name',
    'phone' => 'Missing phone',
    'phone<10' => 'Phone too short',
    'phone>12' => 'Phone too long',
    'dup' => 'Duplicate phone',
    'address' => 'Missing address',
    _ => code,
  };

  @override
  Widget build(BuildContext context) {
    final issues = (widget.row['_issues'] ?? '').split(',');
    final scheme = widget.scheme;
    final text = widget.text;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.error.withValues(alpha: 0.25)),
        color: scheme.errorContainer.withValues(alpha: 0.06),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  widget.row['name']?.isNotEmpty == true ? widget.row['name']! : '(empty name)',
                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                )),
                const SizedBox(width: 8),
                ...issues.map((code) => Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: scheme.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(_issueLabel(code), style: TextStyle(fontSize: 9, color: scheme.error, fontWeight: FontWeight.w600)),
                )),
                IconButton(
                  onPressed: () => widget.onRemove(widget.index),
                  icon: Icon(Icons.close_rounded, size: 14, color: scheme.error),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  tooltip: 'Remove row',
                ),
              ]),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(children: [
                Expanded(child: TextField(
                  controller: _nameC,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Name',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    errorText: issues.contains('name') ? '' : null,
                    errorStyle: const TextStyle(height: 0, fontSize: 0),
                  ),
                )),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: _phoneC,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Phone',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    errorText: issues.any((c) => c.startsWith('phone') || c == 'dup') ? '' : null,
                    errorStyle: const TextStyle(height: 0, fontSize: 0),
                  ),
                )),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: _addressC,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Address',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    errorText: issues.contains('address') ? '' : null,
                    errorStyle: const TextStyle(height: 0, fontSize: 0),
                  ),
                )),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => widget.onFix(widget.index, _nameC.text, _phoneC.text, _addressC.text),
                  icon: Icon(Icons.check_circle_rounded, size: 20, color: Colors.green.shade600),
                  tooltip: 'Validate',
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

class _CsvFormatRow extends StatelessWidget {
  final String label;
  final String description;
  final String example;
  final ColorScheme scheme;
  final TextTheme text;

  const _CsvFormatRow({required this.label, required this.description, required this.example, required this.scheme, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 70,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(label, style: text.bodySmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(description, style: text.bodySmall?.copyWith(fontSize: 11, color: scheme.onSurfaceVariant))),
          Text(example, style: text.bodySmall?.copyWith(fontSize: 11, fontFamily: 'monospace', color: scheme.outline)),
        ],
      ),
    );
  }
}
