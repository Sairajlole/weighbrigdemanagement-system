import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfx/pdfx.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';
import 'package:weighbridgemanagement/shared/providers/general_settings_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/utils/title_case.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/app_error.dart';


final _operatorsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  final siteId = paths.context.siteId;
  return paths.operators.snapshots().map(
        (snap) => snap.docs
            .map((d) => {'id': d.id, ...d.data()})
            .where((op) {
              final scope = op['siteScope'] as String? ?? 'all';
              if (scope == 'all') return true;
              final allowed = op['allowedSites'] as List<dynamic>? ?? [];
              return allowed.contains(siteId);
            })
            .toList(),
      );
});

final _allOperatorsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.operators.snapshots().map(
        (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
      );
});

final _rejectionsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.rejections.orderBy('rejectedAt', descending: true).snapshots().map(
        (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
      );
});

enum _SortOption {
  nameAsc, nameDesc,
  shiftRestricted, shiftUnrestricted,
  lastActiveNewest, lastActiveOldest,
  statusActive, statusInactive,
  createdNewest, createdOldest,
}

class OperatorsScreen extends ConsumerStatefulWidget {
  const OperatorsScreen({super.key});

  @override
  ConsumerState<OperatorsScreen> createState() => _OperatorsScreenState();
}

class _OperatorsScreenState extends ConsumerState<OperatorsScreen> with WidgetsBindingObserver {
  static bool _persistedGridView = false;

  final GlobalKey _sortKey = GlobalKey();
  String _search = '';
  bool _gridView = _persistedGridView;
  _SortOption _sortOption = _SortOption.nameAsc;
  int _tabIndex = 0; // 0 = All Operators, 1 = Requests
  bool _viewAllSites = false;

  // System code OTP reveal: 'locked' → 'sending' → 'otp' → 'revealed'
  String _codeStep = 'locked';
  String? _codeOtpError;
  final _codeOtpControllers = List.generate(6, (_) => TextEditingController());
  final _codeOtpFocusNodes = List.generate(6, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in _codeOtpControllers) { c.dispose(); }
    for (final f in _codeOtpFocusNodes) { f.dispose(); }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _codeStep == 'revealed') {
      setState(() => _codeStep = 'locked');
    }
  }

  void _applySorting(List<Map<String, dynamic>> list) {
    switch (_sortOption) {
      case _SortOption.nameAsc:
        list.sort((a, b) => (a['name'] as String? ?? '').toLowerCase().compareTo((b['name'] as String? ?? '').toLowerCase()));
      case _SortOption.nameDesc:
        list.sort((a, b) => (b['name'] as String? ?? '').toLowerCase().compareTo((a['name'] as String? ?? '').toLowerCase()));
      case _SortOption.shiftRestricted:
        list.sort((a, b) => (b['shiftRestricted'] == true ? 1 : 0).compareTo(a['shiftRestricted'] == true ? 1 : 0));
      case _SortOption.shiftUnrestricted:
        list.sort((a, b) => (a['shiftRestricted'] == true ? 1 : 0).compareTo(b['shiftRestricted'] == true ? 1 : 0));
      case _SortOption.lastActiveNewest:
        list.sort((a, b) => _tsCompare(b['lastLoginAt'], a['lastLoginAt']));
      case _SortOption.lastActiveOldest:
        list.sort((a, b) => _tsCompare(a['lastLoginAt'], b['lastLoginAt']));
      case _SortOption.statusActive:
        list.sort((a, b) => (b['isActive'] == true ? 1 : 0).compareTo(a['isActive'] == true ? 1 : 0));
      case _SortOption.statusInactive:
        list.sort((a, b) => (a['isActive'] == true ? 1 : 0).compareTo(b['isActive'] == true ? 1 : 0));
      case _SortOption.createdNewest:
        list.sort((a, b) => _tsCompare(b['createdAt'], a['createdAt']));
      case _SortOption.createdOldest:
        list.sort((a, b) => _tsCompare(a['createdAt'], b['createdAt']));
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
    _SortOption.shiftRestricted => 'Shift (Restricted)',
    _SortOption.shiftUnrestricted => 'Shift (Unrestricted)',
    _SortOption.lastActiveNewest => 'Last Active ↓',
    _SortOption.lastActiveOldest => 'Last Active ↑',
    _SortOption.statusActive => 'Active First',
    _SortOption.statusInactive => 'Inactive First',
    _SortOption.createdNewest => 'Created (Newest)',
    _SortOption.createdOldest => 'Created (Oldest)',
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
      (_SortOption.shiftRestricted, _SortOption.shiftUnrestricted),
      (_SortOption.lastActiveNewest, _SortOption.lastActiveOldest),
      (_SortOption.statusActive, _SortOption.statusInactive),
      (_SortOption.createdNewest, _SortOption.createdOldest),
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
              borderRadius: BorderRadius.circular(12.rs),
              clipBehavior: Clip.antiAlias,
              child: Container(
                padding: EdgeInsets.all(10.rs),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: pairs.map((pair) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _sortChip(pair.$1, scheme, ctx),
                        SizedBox(width: 6.rs),
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
        width: 130,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? scheme.primary.withValues(alpha: 0.15) : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(6.rs),
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
    final operatorsAsync = _viewAllSites
        ? ref.watch(_allOperatorsProvider)
        : ref.watch(_operatorsProvider);

    return Column(
      children: [
        Expanded(
          child: Padding(
        padding: EdgeInsets.all(24.rs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildNormalHeader(scheme, text, operatorsAsync),
            SizedBox(height: 16.rs),
            _buildTabBar(scheme, text, operatorsAsync),
            SizedBox(height: 16.rs),
            Expanded(
              child: operatorsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (operators) {
                  // Separate archived
                  final archived = operators.where((o) => o['isArchived'] == true).toList();

                  if (_tabIndex == 2) {
                    return _buildArchivedTab(archived, scheme, text);
                  }

                  // Exclude archived, deduplicate by email
                  final seen = <String>{};
                  final unique = <Map<String, dynamic>>[];
                  for (final o in operators) {
                    if (o['isArchived'] == true) continue;
                    final email = (o['email'] as String? ?? '').toLowerCase();
                    if (email.isEmpty || seen.add(email)) unique.add(o);
                  }

                  final filtered = _search.isEmpty
                      ? List<Map<String, dynamic>>.from(unique)
                      : unique.where((o) =>
                          (o['name'] as String? ?? '').toLowerCase().contains(_search) ||
                          (o['email'] as String? ?? '').toLowerCase().contains(_search) ||
                          (o['phone'] as String? ?? '').contains(_search)).toList();

                  _applySorting(filtered);

                  final pending = filtered.where((o) => o['isVerified'] == false).toList();
                  final verified = filtered.where((o) => o['isVerified'] != false).toList();

                  if (_tabIndex == 1) {
                    return _buildRequestsTab(pending, scheme, text);
                  }

                  if (verified.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people_outline, size: 48, color: scheme.outlineVariant),
                          SizedBox(height: 8.rs),
                          Text(
                            _search.isNotEmpty ? 'No matches for "$_search"' : 'No operators yet',
                            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          SizedBox(height: 4.rs),
                          Text(
                            _search.isNotEmpty ? 'Try a different search term' : 'Add your first operator to get started',
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                          ),
                        ],
                      ),
                    );
                  }

                  if (_gridView) {
                    return _buildGridContent(verified, scheme, text);
                  } else {
                    return _buildTableContent(verified, scheme, text);
                  }
                },
              ),
            ),
            SizedBox(height: 12.rs),
            _buildBottomSummary(scheme, operatorsAsync),
          ],
        ),
          ),
        ),
      ],
    );
  }


  Widget _buildNormalHeader(ColorScheme scheme, TextTheme text, AsyncValue<List<Map<String, dynamic>>> operatorsAsync) {
    final operators = operatorsAsync.valueOrNull ?? [];
    final total = operators.length;
    final active = operators.where((o) => o['isVerified'] != false && o['isActive'] == true).length;
    final pending = operators.where((o) => o['isVerified'] == false).length;
    final shiftRestricted = operators.where((o) => o['shiftRestricted'] == true).length;
    final siteCtx = ref.watch(siteContextProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Operators', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            SizedBox(width: 16.rs),
            _buildJoinCodeChip(scheme),
            const Spacer(),
            Container(
              height: 34,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8.rs),
              ),
              padding: EdgeInsets.all(3.rs),
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
                        borderRadius: BorderRadius.circular(6.rs),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_on_rounded, size: 12, color: !_viewAllSites ? scheme.onPrimary : scheme.onSurfaceVariant),
                          SizedBox(width: 5.rs),
                          FutureBuilder<String>(
                            future: (siteCtx.companyId.isNotEmpty && siteCtx.siteId.isNotEmpty)
                                ? ref.read(firestorePathsProvider).firestore.doc('companies/${siteCtx.companyId}/sites/${siteCtx.siteId}').get().then((d) => d.data()?['name'] as String? ?? 'This Site')
                                : Future.value('This Site'),
                            builder: (_, snap) => Text(snap.data ?? 'This Site', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: !_viewAllSites ? scheme.onPrimary : scheme.onSurfaceVariant)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 2.rs),
                  GestureDetector(
                    onTap: () => setState(() => _viewAllSites = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _viewAllSites ? scheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(6.rs),
                      ),
                      child: Text('All Sites', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _viewAllSites ? scheme.onPrimary : scheme.onSurfaceVariant)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 20.rs),

        Row(
          children: [
            _headerStatCard('Total', '$total', Icons.people_rounded, scheme.primary, scheme),
            SizedBox(width: 12.rs),
            _headerStatCard('Active', '$active', Icons.check_circle_rounded, Colors.green.shade700, scheme),
            SizedBox(width: 12.rs),
            _headerStatCard('Pending', '$pending', Icons.pending_actions_rounded, Colors.amber.shade700, scheme),
            SizedBox(width: 12.rs),
            _headerStatCard('Shift Restricted', '$shiftRestricted', Icons.schedule_rounded, Colors.deepPurple, scheme),
          ],
        ),
        SizedBox(height: 16.rs),

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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.rs), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6.rs), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6.rs), borderSide: BorderSide(color: scheme.primary, width: 1.5)),
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
                  borderRadius: BorderRadius.circular(6.rs),
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
            Container(
              height: 32,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(6.rs),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _viewToggle(Icons.grid_view_rounded, true, scheme),
                  _viewToggle(Icons.table_rows_rounded, false, scheme),
                ],
              ),
            ),
            SizedBox(width: 8.rs),
            GestureDetector(
              onTap: () => _showAddOperatorDialog(context),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(6.rs),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 14, color: scheme.onPrimary),
                    SizedBox(width: 4.rs),
                    Text('Add Operator', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onPrimary)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildJoinCodeChip(ColorScheme scheme) {
    final siteCtx = ref.watch(siteContextProvider);
    if (siteCtx.companyId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<DocumentSnapshot>(
      future: ref.read(firestorePathsProvider).generalSettings.get(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final code = data?['systemCode'] as String?;
        if (code == null || code.isEmpty) return const SizedBox.shrink();

        // Revealed state
        if (_codeStep == 'revealed') {
          return GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: code));
              AppError.success(context, 'System code copied');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6.rs),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.vpn_key_rounded, size: 12, color: scheme.primary),
                  SizedBox(width: 6.rs),
                  Text(code, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.primary, letterSpacing: 1)),
                  SizedBox(width: 6.rs),
                  Icon(Icons.copy_rounded, size: 11, color: scheme.primary.withValues(alpha: 0.6)),
                ],
              ),
            ),
          );
        }

        // Sending state
        if (_codeStep == 'sending') {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6.rs),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: scheme.primary)),
                SizedBox(width: 6.rs),
                Text('Sending OTP...', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          );
        }

        // OTP input state
        if (_codeStep == 'otp') {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6.rs),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...List.generate(6, (i) {
                  return Container(
                    width: 28,
                    height: 32,
                    margin: EdgeInsets.only(right: i < 5 ? 3 : 0),
                    child: TextField(
                      controller: _codeOtpControllers[i],
                      focusNode: _codeOtpFocusNodes[i],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        counterText: '',
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(5.rs), borderSide: BorderSide(color: scheme.outlineVariant)),
                      ),
                      onChanged: (val) {
                        if (val.isNotEmpty && i < 5) {
                          _codeOtpFocusNodes[i + 1].requestFocus();
                        } else if (val.isEmpty && i > 0) {
                          _codeOtpFocusNodes[i - 1].requestFocus();
                        }
                        final otp = _codeOtpControllers.map((c) => c.text).join();
                        if (otp.length == 6) _verifyCodeOtp(otp);
                      },
                    ),
                  );
                }),
                SizedBox(width: 6.rs),
                GestureDetector(
                  onTap: () => setState(() { _codeStep = 'locked'; _codeOtpError = null; }),
                  child: Icon(Icons.close_rounded, size: 14, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        }

        // Locked state (default)
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _sendCodeOtp,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(6.rs),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_rounded, size: 12, color: scheme.onSurfaceVariant),
                    SizedBox(width: 6.rs),
                    Text('System Code', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                    SizedBox(width: 4.rs),
                    Icon(Icons.visibility_outlined, size: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                  ],
                ),
              ),
            ),
            if (_codeOtpError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_codeOtpError!, style: TextStyle(fontSize: 9, color: scheme.error)),
              ),
          ],
        );
      },
    );
  }

  Future<void> _sendCodeOtp() async {
    setState(() { _codeStep = 'sending'; _codeOtpError = null; });
    for (final c in _codeOtpControllers) { c.clear(); }

    try {
      final email = await _getAdminEmailForCode();
      if (email == null || email.isEmpty) {
        setState(() { _codeStep = 'locked'; _codeOtpError = 'Admin email not available.'; });
        return;
      }
      await FirebaseFunctions.instance.httpsCallable('sendEmailOTP').call({'email': email});
      if (mounted) {
        setState(() => _codeStep = 'otp');
        Future.delayed(Duration.zero, () { _codeOtpFocusNodes[0].requestFocus(); });
      }
    } catch (e) {
      if (mounted) setState(() { _codeStep = 'locked'; _codeOtpError = 'Failed to send OTP.'; });
    }
  }

  Future<String?> _getAdminEmailForCode() async {
    final paths = ref.read(firestorePathsProvider);
    try {
      final companyDoc = await paths.firestore.collection('companies').doc(paths.context.companyId).get();
      return companyDoc.data()?['email'] as String?;
    } catch (_) {
      return LocalCacheService.getCachedCurrentUserEmail();
    }
  }

  Future<void> _verifyCodeOtp(String otp) async {
    try {
      final email = await _getAdminEmailForCode();
      await FirebaseFunctions.instance.httpsCallable('verifyEmailOTP').call({'email': email, 'otp': otp});
      if (mounted) {
        setState(() => _codeStep = 'revealed');
        Future.delayed(const Duration(minutes: 1), () {
          if (mounted) setState(() => _codeStep = 'locked');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _codeOtpError = 'Invalid OTP.');
        for (final c in _codeOtpControllers) { c.clear(); }
        _codeOtpFocusNodes[0].requestFocus();
      }
    }
  }

  Widget _buildTabBar(ColorScheme scheme, TextTheme text, AsyncValue<List<Map<String, dynamic>>> operatorsAsync) {
    final all = operatorsAsync.valueOrNull ?? [];
    final pendingCount = all.where((o) => o['isVerified'] == false && o['isArchived'] != true).length;
    final archivedCount = all.where((o) => o['isArchived'] == true).length;

    return Container(
      padding: EdgeInsets.all(3.rs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8.rs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tabItem(0, 'All Operators', null, scheme),
          _tabItem(1, 'Requests', pendingCount > 0 ? pendingCount : null, scheme),
          _tabItem(2, 'Archived', archivedCount > 0 ? archivedCount : null, scheme),
        ],
      ),
    );
  }

  Widget _tabItem(int index, String label, int? badge, ColorScheme scheme) {
    final selected = _tabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _tabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? scheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6.rs),
          boxShadow: selected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 3, offset: const Offset(0, 1))] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? scheme.onSurface : scheme.onSurfaceVariant)),
            if (badge != null) ...[
              SizedBox(width: 6.rs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8.rs),
                ),
                child: Text('$badge', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.amber.shade700)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRequestsTab(List<Map<String, dynamic>> pending, ColorScheme scheme, TextTheme text) {
    final rejections = ref.watch(_rejectionsProvider).valueOrNull ?? [];

    if (pending.isEmpty && rejections.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 48, color: scheme.outlineVariant),
            SizedBox(height: 8.rs),
            Text('No pending requests', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            SizedBox(height: 4.rs),
            Text('All operator registrations have been processed', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.all(16.rs),
      itemCount: pending.length + (rejections.isNotEmpty ? 1 : 0),
      separatorBuilder: (_, __) => SizedBox(height: 12.rs),
      itemBuilder: (_, i) {
        // Rejected subsection at the end
        if (i >= pending.length) {
          return _buildRejectedSection(rejections, scheme, text);
        }
        final op = pending[i];
        final createdAt = op['createdAt'];
        final invitedAt = op['invitedAt'];
        final isInvited = invitedAt != null;
        final timeStr = (isInvited ? invitedAt : createdAt) is Timestamp
            ? _formatTimestamp((isInvited ? invitedAt : createdAt) as Timestamp, ref.read(timeFormatProvider))
            : 'Unknown';
        final phone = op['phone'] as String? ?? '';
        final address = op['address'] as String? ?? '';
        final address2 = op['address2'] as String? ?? '';
        final fullAddress = [address, address2].where((s) => s.isNotEmpty).join(', ');
        final idDocType = op['idDocType'] as String? ?? '';
        final idDocNumber = op['idDocNumber'] as String? ?? '';
        final faceEnrollment = op['faceEnrollment'] as Map<String, dynamic>?;
        final faceEnrolled = faceEnrollment?['enrolled'] == true;
        final faceCount = faceEnrollment?['validFrameCount'] as int? ?? faceEnrollment?['faceCount'] as int? ?? 0;
        final emailVerified = op['emailVerified'] == true;
        final phoneVerified = op['phoneVerified'] == true;
        final opEmail = (op['email'] as String? ?? '').toLowerCase();
        final priorRejections = rejections.where((r) => (r['email'] as String? ?? '').toLowerCase() == opEmail).toList();

        return Container(
          padding: EdgeInsets.all(18.rs),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(14.rs),
            border: Border.all(color: isInvited ? scheme.primary.withValues(alpha: 0.3) : Colors.amber.withValues(alpha: 0.3)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: avatar, name, badge, actions
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: isInvited ? scheme.primaryContainer.withValues(alpha: 0.3) : Colors.amber.withValues(alpha: 0.12),
                    child: Icon(
                      isInvited ? Icons.send_rounded : Icons.person_outline_rounded,
                      size: 18,
                      color: isInvited ? scheme.primary : Colors.amber.shade700,
                    ),
                  ),
                  SizedBox(width: 14.rs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(op['name'] ?? 'Unknown', style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700))),
                            SizedBox(width: 8.rs),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: isInvited ? scheme.primary.withValues(alpha: 0.08) : Colors.amber.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(5.rs),
                              ),
                              child: Text(
                                isInvited ? 'Invited' : 'Self-registered',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: isInvited ? scheme.primary : Colors.amber.shade700),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 2.rs),
                        Row(
                          children: [
                            Icon(Icons.access_time_rounded, size: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                            SizedBox(width: 4.rs),
                            Text(
                              isInvited ? 'Invited $timeStr' : 'Requested $timeStr',
                              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 12.rs),
                  if (!isInvited)
                    GestureDetector(
                      onTap: () => _approveOperator(op),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8.rs),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_rounded, size: 14, color: Colors.green.shade700),
                            SizedBox(width: 4.rs),
                            Text('Approve', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green.shade700)),
                          ],
                        ),
                      ),
                    ),
                  SizedBox(width: 8.rs),
                  GestureDetector(
                    onTap: () => _showRejectDialog(op),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: scheme.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8.rs),
                        border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close_rounded, size: 14, color: scheme.error),
                          SizedBox(width: 4.rs),
                          Text('Reject', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.error)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14.rs),
              Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.2)),
              SizedBox(height: 14.rs),
              // Details grid
              Wrap(
                spacing: 24,
                runSpacing: 10,
                children: [
                  _requestInfoChip(Icons.email_rounded, op['email'] ?? '--', scheme, verified: emailVerified),
                  if (phone.isNotEmpty) _requestInfoChip(Icons.phone_rounded, phone, scheme, verified: phoneVerified),
                  if (idDocType.isNotEmpty) _requestInfoChip(Icons.badge_rounded, '$idDocType${idDocNumber.isNotEmpty ? ' · ${idDocNumber.length > 8 ? '${idDocNumber.substring(0, 4)}••••${idDocNumber.substring(idDocNumber.length - 4)}' : idDocNumber}' : ''}', scheme),
                  if (fullAddress.isNotEmpty) _requestInfoChip(Icons.location_on_rounded, fullAddress, scheme, maxWidth: 600),
                ],
              ),
              SizedBox(height: 10.rs),
              // Verification status chips
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _verificationBadge(Icons.face_rounded, faceEnrolled ? 'Face enrolled ($faceCount valid)' : 'No face enrolled', faceEnrolled, scheme),
                  _verificationBadge(Icons.email_rounded, emailVerified ? 'Email verified' : 'Email unverified', emailVerified, scheme),
                  _verificationBadge(Icons.phone_rounded, phoneVerified ? 'Phone verified' : 'Phone unverified', phoneVerified, scheme),
                  if (idDocType.isNotEmpty || idDocNumber.isNotEmpty)
                    GestureDetector(
                      onTap: () => _showViewIdDialog(op),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6.rs),
                          border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.badge_rounded, size: 12, color: scheme.primary),
                            SizedBox(width: 5.rs),
                            Text('View ID', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.primary)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              // Rejection history
              if (priorRejections.isNotEmpty) ...[
                SizedBox(height: 12.rs),
                Container(
                  padding: EdgeInsets.all(10.rs),
                  decoration: BoxDecoration(
                    color: scheme.error.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8.rs),
                    border: Border.all(color: scheme.error.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.history_rounded, size: 14, color: scheme.error),
                          SizedBox(width: 6.rs),
                          Text('Previously rejected (${priorRejections.length}×)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.error)),
                        ],
                      ),
                      SizedBox(height: 6.rs),
                      ...priorRejections.map((r) {
                        final rejAt = r['rejectedAt'];
                        final rejTime = rejAt is Timestamp ? _formatTimestamp(rejAt, ref.read(timeFormatProvider)) : '';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('• ', style: TextStyle(fontSize: 11, color: scheme.error.withValues(alpha: 0.6))),
                              Expanded(
                                child: Text(
                                  '${r['reason'] ?? 'No reason'}${rejTime.isNotEmpty ? ' ($rejTime)' : ''}',
                                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _requestInfoChip(IconData icon, String label, ColorScheme scheme, {bool verified = false, double? maxWidth}) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth ?? 220),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
          SizedBox(width: 6.rs),
          Flexible(child: Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
          if (verified) ...[
            SizedBox(width: 4.rs),
            Icon(Icons.verified_rounded, size: 12, color: Colors.green.shade600),
          ],
        ],
      ),
    );
  }

  Widget _verificationBadge(IconData icon, String label, bool verified, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: verified ? Colors.green.withValues(alpha: 0.08) : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6.rs),
        border: Border.all(color: verified ? Colors.green.withValues(alpha: 0.2) : scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: verified ? Colors.green.shade600 : scheme.onSurfaceVariant.withValues(alpha: 0.5)),
          SizedBox(width: 5.rs),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: verified ? Colors.green.shade700 : scheme.onSurfaceVariant.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  Future<void> _approveOperator(Map<String, dynamic> op) async {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final paths = ref.read(firestorePathsProvider);
    final companyId = paths.context.companyId;

    // Fetch sites
    List<Map<String, String>> allSites = [];
    try {
      final snap = await paths.firestore.collection('companies/$companyId/sites').get();
      allSites = snap.docs.map((d) => {'id': d.id, 'name': d.data()['name'] as String? ?? 'Unnamed Site'}).toList();
    } catch (_) {}

    if (!mounted) return;

    final Set<String> selectedSites = {paths.context.siteId};
    bool selectAll = allSites.length <= 1;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.rs)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: EdgeInsets.all(24.rs),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle_rounded, size: 20, color: Colors.green.shade700),
                      SizedBox(width: 10.rs),
                      Text('Approve Operator', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, size: 18)),
                    ],
                  ),
                  SizedBox(height: 6.rs),
                  Text('Approving "${op['name'] ?? 'Unknown'}"', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  SizedBox(height: 18.rs),
                  Text('Assign to sites:', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                  SizedBox(height: 10.rs),
                  // Select All toggle
                  InkWell(
                    onTap: () => setSt(() {
                      selectAll = !selectAll;
                      if (selectAll) {
                        selectedSites.clear();
                        for (final s in allSites) {
                          selectedSites.add(s['id']!);
                        }
                      }
                    }),
                    borderRadius: BorderRadius.circular(8.rs),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8.rs),
                        color: selectAll ? scheme.primary.withValues(alpha: 0.08) : null,
                        border: Border.all(color: selectAll ? scheme.primary.withValues(alpha: 0.4) : scheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selectAll ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                            size: 18,
                            color: selectAll ? scheme.primary : scheme.onSurfaceVariant,
                          ),
                          SizedBox(width: 10.rs),
                          Text('All Sites', style: TextStyle(fontSize: 12, fontWeight: selectAll ? FontWeight.w700 : FontWeight.w500, color: selectAll ? scheme.primary : scheme.onSurface)),
                          const Spacer(),
                          Icon(Icons.public_rounded, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        ],
                      ),
                    ),
                  ),
                  if (!selectAll && allSites.isNotEmpty) ...[
                    SizedBox(height: 10.rs),
                    Container(
                      padding: EdgeInsets.all(10.rs),
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8.rs),
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: allSites.map((site) {
                            final selected = selectedSites.contains(site['id']);
                            return GestureDetector(
                              onTap: () => setSt(() {
                                if (selected) {
                                  selectedSites.remove(site['id']);
                                } else {
                                  selectedSites.add(site['id']!);
                                }
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                margin: const EdgeInsets.only(bottom: 4),
                                decoration: BoxDecoration(
                                  color: selected ? scheme.primary.withValues(alpha: 0.08) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6.rs),
                                  border: selected ? Border.all(color: scheme.primary.withValues(alpha: 0.3)) : null,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                      size: 16,
                                      color: selected ? scheme.primary : scheme.onSurfaceVariant,
                                    ),
                                    SizedBox(width: 8.rs),
                                    Expanded(
                                      child: Text(
                                        site['name']!,
                                        style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: scheme.onSurface),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                  if (!selectAll && selectedSites.isEmpty) ...[
                    SizedBox(height: 8.rs),
                    Text('Select at least one site', style: TextStyle(fontSize: 11, color: scheme.error)),
                  ],
                  SizedBox(height: 20.rs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                      SizedBox(width: 8.rs),
                      FilledButton(
                        onPressed: (!selectAll && selectedSites.isEmpty) || saving
                            ? null
                            : () async {
                                setSt(() => saving = true);
                                final siteScope = selectAll ? 'all' : 'specific';
                                final sites = selectAll ? <String>[] : selectedSites.toList();
                                final email = op['email'] as String? ?? '';

                                await paths.operators.doc(op['id']).update({
                                  'isVerified': true,
                                  'isActive': true,
                                  'siteScope': siteScope,
                                  'allowedSites': sites,
                                });

                                // Clear rejection history if any
                                if (email.isNotEmpty) {
                                  final rejSnap = await paths.rejections.where('email', isEqualTo: email).get();
                                  for (final doc in rejSnap.docs) {
                                    await doc.reference.delete();
                                  }
                                }

                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                        style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                        child: saving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Approve'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showViewIdDialog(Map<String, dynamic> op) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final idDocType = op['idDocType'] as String? ?? '';
    final idDocNumber = op['idDocNumber'] as String? ?? '';
    var idDocImages = op['idDocImages'] as List<dynamic>? ?? [];
    // Fallback: old field written by cloud function before idDocImages was added
    if (idDocImages.isEmpty) {
      final legacy = op['idImageBase64'] as String?;
      if (legacy != null && legacy.isNotEmpty) idDocImages = [legacy];
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.rs)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 750),
          child: Padding(
            padding: EdgeInsets.all(24.rs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.badge_rounded, size: 20, color: scheme.primary),
                    SizedBox(width: 10.rs),
                    Text('Submitted ID Document', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, size: 18)),
                  ],
                ),
                SizedBox(height: 6.rs),
                Text('ID details for "${op['name'] ?? 'Unknown'}"', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                SizedBox(height: 18.rs),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16.rs),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10.rs),
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.article_rounded, size: 16, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                          SizedBox(width: 8.rs),
                          Text('Document Type', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
                        ],
                      ),
                      SizedBox(height: 4.rs),
                      Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: Text(
                          idDocType.isNotEmpty ? idDocType : 'Not provided',
                          style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      SizedBox(height: 14.rs),
                      Row(
                        children: [
                          Icon(Icons.numbers_rounded, size: 16, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                          SizedBox(width: 8.rs),
                          Text('Document Number', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
                        ],
                      ),
                      SizedBox(height: 4.rs),
                      Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: Text(
                          idDocNumber.isNotEmpty ? idDocNumber : 'Not provided',
                          style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                if (idDocImages.isNotEmpty) ...[
                  SizedBox(height: 16.rs),
                  Text('Document Image${idDocImages.length > 1 ? 's (${idDocImages.length})' : ''}', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                  SizedBox(height: 8.rs),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: idDocImages.length,
                      separatorBuilder: (_, __) => SizedBox(height: 8.rs),
                      itemBuilder: (_, i) {
                        final raw = idDocImages[i] as String;
                        return _IdDocImageView(base64Data: raw, scheme: scheme);
                      },
                    ),
                  ),
                ] else ...[
                  SizedBox(height: 16.rs),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16.rs),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10.rs),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.image_not_supported_rounded, size: 16, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        SizedBox(width: 8.rs),
                        Text('No document image submitted', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
                      ],
                    ),
                  ),
                ],
                SizedBox(height: 20.rs),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRejectDialog(Map<String, dynamic> op) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    String? selectedReason;
    final customCtrl = TextEditingController();

    final faceEnrollment = op['faceEnrollment'] as Map<String, dynamic>?;
    final faceEnrolled = faceEnrollment?['enrolled'] == true;

    final reasons = [
      if (!faceEnrolled) 'Face enrollment is required',
      'Invalid ID document',
      'Duplicate registration',
      'Not authorized to operate at this company',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.rs)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: EdgeInsets.all(24.rs),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.block_rounded, size: 20, color: scheme.error),
                      SizedBox(width: 10.rs),
                      Text('Reject Operator', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, size: 18)),
                    ],
                  ),
                  SizedBox(height: 6.rs),
                  Text('Rejecting "${op['name'] ?? 'Unknown'}"', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  SizedBox(height: 18.rs),
                  Text('Select reason:', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                  SizedBox(height: 10.rs),
                  ...reasons.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      onTap: () => setSt(() { selectedReason = r; }),
                      borderRadius: BorderRadius.circular(8.rs),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8.rs),
                          border: Border.all(color: selectedReason == r ? scheme.error.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3)),
                          color: selectedReason == r ? scheme.error.withValues(alpha: 0.06) : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selectedReason == r ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                              size: 16,
                              color: selectedReason == r ? scheme.error : scheme.onSurfaceVariant,
                            ),
                            SizedBox(width: 10.rs),
                            Expanded(child: Text(r, style: text.bodySmall?.copyWith(fontWeight: selectedReason == r ? FontWeight.w600 : FontWeight.w400))),
                          ],
                        ),
                      ),
                    ),
                  )),
                  // Custom reason option
                  InkWell(
                    onTap: () => setSt(() { selectedReason = '__custom__'; }),
                    borderRadius: BorderRadius.circular(8.rs),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8.rs),
                        border: Border.all(color: selectedReason == '__custom__' ? scheme.error.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3)),
                        color: selectedReason == '__custom__' ? scheme.error.withValues(alpha: 0.06) : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selectedReason == '__custom__' ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                            size: 16,
                            color: selectedReason == '__custom__' ? scheme.error : scheme.onSurfaceVariant,
                          ),
                          SizedBox(width: 10.rs),
                          Expanded(child: Text('Other (custom reason)', style: text.bodySmall?.copyWith(fontWeight: selectedReason == '__custom__' ? FontWeight.w600 : FontWeight.w400))),
                        ],
                      ),
                    ),
                  ),
                  if (selectedReason == '__custom__') ...[
                    SizedBox(height: 10.rs),
                    TextField(
                      controller: customCtrl,
                      maxLines: 2,
                      style: text.bodySmall,
                      decoration: InputDecoration(
                        hintText: 'Enter rejection reason...',
                        isDense: true,
                        contentPadding: EdgeInsets.all(12.rs),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.rs)),
                      ),
                    ),
                  ],
                  SizedBox(height: 20.rs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                      SizedBox(width: 8.rs),
                      FilledButton(
                        onPressed: selectedReason == null || (selectedReason == '__custom__' && customCtrl.text.trim().isEmpty)
                            ? null
                            : () {
                                final reason = selectedReason == '__custom__' ? customCtrl.text.trim() : selectedReason!;
                                Navigator.pop(ctx);
                                _rejectOperator(op, reason);
                              },
                        style: FilledButton.styleFrom(backgroundColor: scheme.error),
                        child: const Text('Reject'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _rejectOperator(Map<String, dynamic> op, String reason) async {
    final paths = ref.read(firestorePathsProvider);
    final email = op['email'] as String? ?? '';

    // Add to rejections collection
    await paths.rejections.add({
      'operatorId': op['id'],
      'name': op['name'] ?? '',
      'email': email,
      'phone': op['phone'] ?? '',
      'address': op['address'] ?? '',
      'address2': op['address2'] ?? '',
      'idDocType': op['idDocType'] ?? '',
      'idDocNumber': op['idDocNumber'] ?? '',
      'faceEnrolled': (op['faceEnrollment'] is Map) && (op['faceEnrollment'] as Map)['enrolled'] == true,
      'reason': reason,
      'rejectedAt': FieldValue.serverTimestamp(),
    });

    // Remove the operator doc
    await paths.operators.doc(op['id']).delete();
  }

  Widget _buildRejectedSection(List<Map<String, dynamic>> rejections, ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 8.rs),
        Divider(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        SizedBox(height: 12.rs),
        Row(
          children: [
            Icon(Icons.person_off_rounded, size: 16, color: scheme.error.withValues(alpha: 0.7)),
            SizedBox(width: 8.rs),
            Text('Previously Rejected', style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.error.withValues(alpha: 0.8))),
            SizedBox(width: 8.rs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: scheme.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4.rs)),
              child: Text('${rejections.length}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.error)),
            ),
          ],
        ),
        SizedBox(height: 12.rs),
        ...rejections.map((rej) {
          final rejectedAt = rej['rejectedAt'];
          final timeStr = rejectedAt is Timestamp ? _formatTimestamp(rejectedAt, ref.read(timeFormatProvider)) : 'Unknown';

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: EdgeInsets.all(14.rs),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(10.rs),
                border: Border.all(color: scheme.error.withValues(alpha: 0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: scheme.error.withValues(alpha: 0.08),
                        child: Icon(Icons.person_off_rounded, size: 14, color: scheme.error),
                      ),
                      SizedBox(width: 10.rs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(rej['name'] ?? 'Unknown', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                            Text(rej['email'] ?? '', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Text(timeStr, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
                      SizedBox(width: 8.rs),
                      IconButton(
                        onPressed: () => ref.read(firestorePathsProvider).rejections.doc(rej['id']).delete(),
                        icon: Icon(Icons.close_rounded, size: 16, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        tooltip: 'Remove',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  SizedBox(height: 8.rs),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(8.rs),
                    decoration: BoxDecoration(
                      color: scheme.error.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(6.rs),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.format_quote_rounded, size: 12, color: scheme.error.withValues(alpha: 0.5)),
                        SizedBox(width: 6.rs),
                        Expanded(child: Text(rej['reason'] ?? '--', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic))),
                      ],
                    ),
                  ),
                  SizedBox(height: 8.rs),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      if ((rej['phone'] as String? ?? '').isNotEmpty)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.phone_rounded, size: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                          SizedBox(width: 4.rs),
                          Text(rej['phone'], style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.8))),
                        ]),
                      if ((rej['idDocType'] as String? ?? '').isNotEmpty)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.badge_rounded, size: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                          SizedBox(width: 4.rs),
                          Text(
                            '${rej['idDocType']}${(rej['idDocNumber'] as String? ?? '').isNotEmpty ? ' • ${rej['idDocNumber']}' : ''}',
                            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.8)),
                          ),
                        ]),
                      if (rej['faceEnrolled'] == true)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.face_rounded, size: 11, color: Colors.green.withValues(alpha: 0.7)),
                          SizedBox(width: 4.rs),
                          Text('Face enrolled', style: TextStyle(fontSize: 10, color: Colors.green.withValues(alpha: 0.8))),
                        ])
                      else
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.face_rounded, size: 11, color: scheme.error.withValues(alpha: 0.5)),
                          SizedBox(width: 4.rs),
                          Text('No face', style: TextStyle(fontSize: 10, color: scheme.error.withValues(alpha: 0.7))),
                        ]),
                    ],
                  ),
                  if ((rej['address'] as String? ?? '').isNotEmpty) ...[
                    SizedBox(height: 6.rs),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.location_on_rounded, size: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
                        SizedBox(width: 4.rs),
                        Expanded(
                          child: Text(
                            '${rej['address']}${(rej['address2'] as String? ?? '').isNotEmpty ? ', ${rej['address2']}' : ''}',
                            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _deleteArchivedOperator(String id, String name) async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.rs)),
        icon: Icon(Icons.delete_forever_rounded, color: scheme.error, size: 28),
        title: Text('Delete "$name"?', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Text(
          'This will permanently delete this operator. This action cannot be undone.',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final paths = ref.read(firestorePathsProvider);
    final doc = await paths.operators.doc(id).get();
    final email = doc.data()?['email'] as String? ?? '';

    // Delete from company subcollection
    await paths.operators.doc(id).delete();

    // Delete from global operators collection
    if (email.isNotEmpty) {
      final globalSnap = await paths.flat('operators')
          .where('email', isEqualTo: email)
          .limit(1).get();
      for (final d in globalSnap.docs) {
        await d.reference.delete();
      }
    }
  }

  Widget _buildArchivedTab(List<Map<String, dynamic>> archived, ColorScheme scheme, TextTheme text) {
    if (archived.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.archive_outlined, size: 48, color: scheme.outlineVariant),
            SizedBox(height: 8.rs),
            Text('No archived operators', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            SizedBox(height: 4.rs),
            Text('Archived operators will appear here', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: archived.length,
      separatorBuilder: (_, __) => SizedBox(height: 10.rs),
      itemBuilder: (_, i) {
        final op = archived[i];
        final archivedAt = op['archivedAt'];
        final timeStr = archivedAt is Timestamp
            ? _formatTimestamp(archivedAt, ref.read(timeFormatProvider))
            : 'Unknown';

        return Container(
          padding: EdgeInsets.all(16.rs),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12.rs),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: scheme.surfaceContainerHigh,
                child: Text(
                  (op['name'] as String? ?? 'U').substring(0, 1).toUpperCase(),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                ),
              ),
              SizedBox(width: 14.rs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(op['name'] ?? 'Unknown', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(height: 2.rs),
                    Text(op['email'] ?? '', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    SizedBox(height: 4.rs),
                    Row(
                      children: [
                        Icon(Icons.archive_outlined, size: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        SizedBox(width: 4.rs),
                        Text('Archived $timeStr', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12.rs),
              GestureDetector(
                onTap: () => ref.read(firestorePathsProvider).operators.doc(op['id']).update({
                  'isArchived': FieldValue.delete(),
                  'isActive': true,
                  'archivedAt': FieldValue.delete(),
                  'permissionsRevoked': FieldValue.delete(),
                  'idStatus': 'not_submitted',
                  'idDocumentNumber': '',
                  'idDocumentType': '',
                  'idVerifiedAt': FieldValue.delete(),
                  'idVerifiedBy': FieldValue.delete(),
                  'verifiedIds': [],
                  'mustChangePassword': true,
                  'restoredAt': FieldValue.serverTimestamp(),
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8.rs),
                    border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.unarchive_outlined, size: 14, color: scheme.primary),
                      SizedBox(width: 4.rs),
                      Text('Restore', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.primary)),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 8.rs),
              GestureDetector(
                onTap: () => _deleteArchivedOperator(op['id'] as String, op['name'] as String? ?? 'Unknown'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8.rs),
                    border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 14, color: scheme.error),
                      SizedBox(width: 4.rs),
                      Text('Delete', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.error)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _headerStatCard(String label, String value, IconData icon, Color color, ColorScheme scheme) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10.rs),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            SizedBox(width: 10.rs),
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
          borderRadius: BorderRadius.circular(6.rs),
        ),
        child: Icon(icon, size: 16, color: active ? scheme.onPrimary : scheme.onSurfaceVariant),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TABLE VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTableContent(List<Map<String, dynamic>> operators, ColorScheme scheme, TextTheme text) {
    if (operators.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(color: scheme.shadow.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.rs),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow.withValues(alpha: 0.7),
                border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 28, child: Text('#', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3))),
                  const Expanded(flex: 3, child: Text('Operator', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3))),
                  const Expanded(flex: 3, child: Text('Contact', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3))),
                  const Expanded(flex: 2, child: Text('Shift', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3))),
                  const Expanded(flex: 2, child: Text('ID Status', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3))),
                  const Expanded(flex: 2, child: Text('Last Active', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3))),
                  const SizedBox(width: 64, child: Text('Status', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3))),
                  SizedBox(width: 100.rs),
                ],
              ),
            ),
            // Body
            Expanded(
              child: Scrollbar(
                child: ListView.builder(
                  itemCount: operators.length,
                  itemBuilder: (_, i) {
                  final op = operators[i];
                  final isActive = op['isActive'] == true;
                  final idStatus = op['idStatus'] as String? ?? 'not_submitted';
                  final phone = op['phone'] as String? ?? '';
                  final email = op['email'] as String? ?? '';

                  return Material(
                    color: i.isEven ? Colors.transparent : scheme.surfaceContainerLow.withValues(alpha: 0.4),
                    child: InkWell(
                      onTap: () => _showEditOperatorDialog(context, op),
                      hoverColor: scheme.primary.withValues(alpha: 0.04),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        child: Row(
                      children: [
                        SizedBox(width: 28, child: Text('${i + 1}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)))),
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              _operatorAvatar(op, scheme, 15),
                              SizedBox(width: 10.rs),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(op['name'] ?? '--', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis, maxLines: 1),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(email.isNotEmpty ? email : '--', style: TextStyle(fontSize: 11, color: scheme.onSurface), overflow: TextOverflow.ellipsis, maxLines: 1),
                              if (phone.isNotEmpty)
                                Text(phone, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)), overflow: TextOverflow.ellipsis, maxLines: 1),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(_formatShift(op), style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis, maxLines: 1),
                        ),
                        Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: _buildIdStatusChip(idStatus, scheme))),
                        Expanded(
                          flex: 2,
                          child: Text(
                            _formatTimestamp(op['lastLoginAt'], ref.read(timeFormatProvider)),
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                          ),
                        ),
                        SizedBox(
                          width: 64,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isActive ? Colors.green.withValues(alpha: 0.08) : scheme.error.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12.rs),
                            ),
                            child: Text(
                              isActive ? 'Active' : 'Inactive',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isActive ? Colors.green.shade700 : scheme.error),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 100,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _iconAction(Icons.edit_outlined, 'Edit', scheme.primary, () => _showEditOperatorDialog(context, op)),
                              _iconAction(
                                isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                                isActive ? 'Deactivate' : 'Activate',
                                isActive ? scheme.error : Colors.green.shade700,
                                () => ref.read(firestorePathsProvider).operators.doc(op['id']).update({'isActive': !isActive}),
                              ),
                              _iconAction(Icons.archive_outlined, 'Archive', scheme.error, () => _confirmArchive(context, op)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                  );
                },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconAction(IconData icon, String tooltip, Color color, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6.rs),
        child: Padding(
          padding: EdgeInsets.all(6.rs),
          child: Icon(icon, size: 15, color: color.withValues(alpha: 0.7)),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GRID VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildGridContent(List<Map<String, dynamic>> operators, ColorScheme scheme, TextTheme text) {
    return Scrollbar(
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 320,
          childAspectRatio: 0.92,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: operators.length,
        itemBuilder: (_, i) => _buildOperatorCard(operators[i], scheme, text),
      ),
    );
  }

  Widget _buildOperatorCard(Map<String, dynamic> op, ColorScheme scheme, TextTheme text) {
    final isActive = op['isActive'] == true;
    final idStatus = op['idStatus'] as String? ?? 'not_submitted';
    final phone = op['phone'] as String? ?? '';
    final email = op['email'] as String? ?? '';

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(12.rs),
      child: InkWell(
        onTap: () => _showEditOperatorDialog(context, op),
        borderRadius: BorderRadius.circular(12.rs),
        hoverColor: scheme.primary.withValues(alpha: 0.03),
        child: Container(
          padding: EdgeInsets.all(14.rs),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12.rs),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(color: scheme.shadow.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: avatar + name + status dot
              Row(
                children: [
                  _operatorAvatar(op, scheme, 22),
                  SizedBox(width: 10.rs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(op['name'] ?? '--', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis, maxLines: 1),
                        const SizedBox(height: 1),
                        Text(
                          isActive ? 'Active' : 'Inactive',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: isActive ? Colors.green.shade700 : scheme.error),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 9, height: 9,
                    decoration: BoxDecoration(
                      color: isActive ? Colors.green : scheme.error,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: (isActive ? Colors.green : scheme.error).withValues(alpha: 0.3), blurRadius: 4)],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.rs),
              // Contact info
              _cardDetailRow(Icons.email_outlined, email.isNotEmpty ? email : '--', scheme),
              if (phone.isNotEmpty) ...[
                SizedBox(height: 5.rs),
                _cardDetailRow(Icons.phone_outlined, phone, scheme),
              ],
              SizedBox(height: 5.rs),
              _cardDetailRow(Icons.schedule_outlined, _formatShift(op), scheme),
              const Spacer(),
              // Bottom row: ID status + last active
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8.rs),
                ),
                child: Row(
                  children: [
                    _buildIdStatusChip(idStatus, scheme),
                    const Spacer(),
                    Icon(Icons.access_time_rounded, size: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                    SizedBox(width: 4.rs),
                    Text(
                      _formatTimestamp(op['lastLoginAt'], ref.read(timeFormatProvider)),
                      style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 10.rs),
              // Actions
              Row(
                children: [
                  Expanded(
                    child: _cardAction(
                      Icons.edit_outlined,
                      'Edit',
                      scheme.primary,
                      () => _showEditOperatorDialog(context, op),
                    ),
                  ),
                  SizedBox(width: 6.rs),
                  Expanded(
                    child: _cardAction(
                      isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                      isActive ? 'Deactivate' : 'Activate',
                      isActive ? scheme.error : Colors.green.shade700,
                      () => ref.read(firestorePathsProvider).operators.doc(op['id']).update({'isActive': !isActive}),
                    ),
                  ),
                  SizedBox(width: 6.rs),
                  Expanded(
                    child: _cardAction(
                      Icons.archive_outlined,
                      'Archive',
                      scheme.error,
                      () => _confirmArchive(context, op),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardDetailRow(IconData icon, String value, ColorScheme scheme) {
    return Row(
      children: [
        Icon(icon, size: 13, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
        SizedBox(width: 7.rs),
        Expanded(
          child: Text(value, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis, maxLines: 1),
        ),
      ],
    );
  }

  Widget _cardAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6.rs),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6.rs),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color.withValues(alpha: 0.8)),
            SizedBox(width: 3.rs),
            Flexible(child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.8)), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOTTOM SUMMARY
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBottomSummary(ColorScheme scheme, AsyncValue<List<Map<String, dynamic>>> operatorsAsync) {
    final operators = operatorsAsync.valueOrNull ?? [];
    if (operators.isEmpty) return const SizedBox.shrink();

    final filtered = _search.isEmpty
        ? operators
        : operators.where((o) =>
            (o['name'] as String? ?? '').toLowerCase().contains(_search) ||
            (o['email'] as String? ?? '').toLowerCase().contains(_search)).toList();

    final active = filtered.where((o) => o['isActive'] == true).length;
    final inactive = filtered.where((o) => o['isActive'] != true).length;
    final withFace = filtered.where((o) => (o['facePhoto'] as String? ?? '').isNotEmpty).length;
    final kycVerified = filtered.where((o) => o['idStatus'] == 'verified').length;
    final shiftRestricted = filtered.where((o) => o['shiftRestricted'] == true).length;
    final allSites = filtered.where((o) => (o['siteScope'] as String? ?? 'all') == 'all').length;
    final siteSpecific = filtered.length - allSites;

    // Recently active (logged in within 7 days)
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final recentlyActive = filtered.where((o) {
      final ts = o['lastLoginAt'];
      if (ts is! Timestamp) return false;
      return ts.toDate().isAfter(weekAgo);
    }).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Text('${filtered.length} shown', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
          if (filtered.length != operators.length) ...[
            Text(' / ${operators.length} total', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
          ],
          SizedBox(width: 16.rs),
          _bottomPill('Active', '$active', Colors.green.shade700, scheme),
          SizedBox(width: 6.rs),
          _bottomPill('Inactive', '$inactive', scheme.error, scheme),
          SizedBox(width: 6.rs),
          _bottomPill('Recent 7d', '$recentlyActive', scheme.primary, scheme),
          SizedBox(width: 6.rs),
          _bottomPill('Face', '$withFace', scheme.tertiary, scheme),
          SizedBox(width: 6.rs),
          _bottomPill('KYC', '$kycVerified', Colors.teal, scheme),
          SizedBox(width: 6.rs),
          _bottomPill('Shift Locked', '$shiftRestricted', Colors.deepPurple, scheme),
          const Spacer(),
          _bottomPill('All Sites', '$allSites', scheme.onSurfaceVariant, scheme),
          SizedBox(width: 6.rs),
          _bottomPill('Site-Specific', '$siteSpecific', scheme.onSurfaceVariant, scheme),
        ],
      ),
    );
  }

  Widget _bottomPill(String label, String value, Color accent, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4.rs),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '$label ', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          TextSpan(text: value, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: accent)),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _operatorAvatar(Map<String, dynamic> op, ColorScheme scheme, double radius) {
    final profilePic = op['profilePic'] as String? ?? '';
    if (profilePic.isNotEmpty) {
      try {
        final bytes = base64Decode(profilePic);
        return CircleAvatar(radius: radius, backgroundImage: MemoryImage(bytes));
      } catch (_) {}
    }
    final facePhoto = op['facePhoto'] as String? ?? '';
    if (facePhoto.isNotEmpty) {
      final file = File(facePhoto);
      if (file.existsSync()) {
        return CircleAvatar(radius: radius, backgroundImage: FileImage(file));
      }
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.secondaryContainer,
      child: Text(
        (op['name'] as String? ?? 'U').substring(0, 1).toUpperCase(),
        style: TextStyle(fontSize: radius * 0.75, fontWeight: FontWeight.w600, color: scheme.onSecondaryContainer),
      ),
    );
  }


  Widget _buildIdStatusChip(String status, ColorScheme scheme) {
    Color bgColor;
    Color fgColor;
    String label;

    switch (status) {
      case 'verified':
        bgColor = Colors.green.withValues(alpha: 0.12);
        fgColor = Colors.green;
        label = 'Verified';
        break;
      case 'pending':
        bgColor = Colors.amber.withValues(alpha: 0.12);
        fgColor = Colors.amber.shade800;
        label = 'Pending';
        break;
      case 'rejected':
        bgColor = scheme.errorContainer;
        fgColor = scheme.onErrorContainer;
        label = 'Rejected';
        break;
      default:
        bgColor = scheme.surfaceContainerHigh;
        fgColor = scheme.onSurfaceVariant;
        label = 'Not Submitted';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4.rs),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fgColor)),
    );
  }

  String _formatShift(Map<String, dynamic> op) {
    final restricted = op['shiftRestricted'] == true;
    if (!restricted) return 'No restriction';

    final start = op['shiftStart'] as String? ?? '';
    final end = op['shiftEnd'] as String? ?? '';
    final days = (op['shiftDays'] as List<dynamic>?)?.cast<String>() ?? [];

    if (start.isEmpty && end.isEmpty) return 'No restriction';

    String dayRange = '';
    if (days.isNotEmpty) {
      if (days.length == 7) {
        dayRange = 'All days';
      } else {
        dayRange = '(${days.first}-${days.last})';
      }
    }

    return '$start–$end $dayRange'.trim();
  }

  String _formatTimestamp(dynamic timestamp, String timeFormat) {
    if (timestamp == null) return 'Never';
    if (timestamp is Timestamp) {
      return formatTimestamp(timestamp, timeFormat);
    }
    return 'Never';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void _confirmArchive(BuildContext context, Map<String, dynamic> op) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.rs)),
        icon: Icon(Icons.archive_outlined, color: scheme.error, size: 28),
        title: const Text('Archive Operator'),
        content: Text('Are you sure you want to archive "${op['name']}"? They will no longer appear in the active list.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              ref.read(firestorePathsProvider).operators.doc(op['id']).update({
                'isArchived': true,
                'isActive': false,
                'permissionsRevoked': true,
                'archivedAt': FieldValue.serverTimestamp(),
              });
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }


  void _showAddOperatorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _AddOperatorDialog(ref: ref),
    );
  }

  void _showEditOperatorDialog(BuildContext context, Map<String, dynamic> op) {
    showDialog(
      context: context,
      builder: (ctx) => _EditOperatorDialog(ref: ref, operator: op),
    );
  }
}

// ─── Add Operator Dialog ──────────────────────────────────────────────────────

class _AddOperatorDialog extends StatefulWidget {
  final WidgetRef ref;

  const _AddOperatorDialog({required this.ref});

  @override
  State<_AddOperatorDialog> createState() => _AddOperatorDialogState();
}

class _AddOperatorDialogState extends State<_AddOperatorDialog> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  List<String> _allowedDomains = [];
  bool _domainRestrictionEnabled = false;
  String? _domainWarning;

  // Site scope
  String _siteScope = 'all';
  List<Map<String, String>> _allSites = [];
  Set<String> _selectedSites = {};

  @override
  void initState() {
    super.initState();
    _loadDomainRestrictions();
    _loadSites();
    _emailCtrl.addListener(_checkDomain);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDomainRestrictions() async {
    try {
      final paths = widget.ref.read(firestorePathsProvider);
      final doc = await paths.firestore.doc('companies/${paths.context.companyId}').get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        final domainsRaw = data['emailDomainRestrictions'] as List<dynamic>?;
        final legacySingle = data['emailDomainRestriction'] as String?;
        setState(() {
          if (domainsRaw != null && domainsRaw.isNotEmpty) {
            _allowedDomains = domainsRaw.cast<String>();
            _domainRestrictionEnabled = true;
          } else if (legacySingle != null && legacySingle.isNotEmpty) {
            _allowedDomains = [legacySingle];
            _domainRestrictionEnabled = true;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _loadSites() async {
    try {
      final paths = widget.ref.read(firestorePathsProvider);
      final snap = await paths.firestore.collection('companies/${paths.context.companyId}/sites').get();
      if (mounted) {
        setState(() {
          _allSites = snap.docs.map((d) => {'id': d.id, 'name': d.data()['name'] as String? ?? 'Unnamed Site'}).toList();
          _selectedSites = {paths.context.siteId};
        });
      }
    } catch (_) {}
  }

  void _checkDomain() {
    if (!_domainRestrictionEnabled || _allowedDomains.isEmpty) {
      if (_domainWarning != null) setState(() => _domainWarning = null);
      return;
    }
    final email = _emailCtrl.text.trim().toLowerCase();
    if (!email.contains('@')) {
      if (_domainWarning != null) setState(() => _domainWarning = null);
      return;
    }
    final domain = email.split('@').last;
    if (domain.isEmpty) return;
    if (_allowedDomains.contains(domain)) {
      if (_domainWarning != null) setState(() => _domainWarning = null);
    } else {
      setState(() => _domainWarning = domain);
    }
  }

  Widget _scopeChip(String value, String label, IconData icon, ColorScheme scheme) {
    final active = _siteScope == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _siteScope = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: active ? scheme.primary.withValues(alpha: 0.1) : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8.rs),
            border: Border.all(color: active ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: active ? scheme.primary : scheme.onSurfaceVariant),
              SizedBox(width: 6.rs),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? scheme.primary : scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _allowDomain(String domain) async {
    setState(() {
      _allowedDomains.add(domain);
      _domainWarning = null;
    });
    try {
      final paths = widget.ref.read(firestorePathsProvider);
      await paths.firestore.doc('companies/${paths.context.companyId}').update({
        'emailDomainRestrictions': _allowedDomains,
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_domainWarning != null) return;
    setState(() => _saving = true);

    try {
      final db = widget.ref.read(firestorePathsProvider);
      await db.operators.add({
        'name': toTitleCase(_nameCtrl.text.trim()),
        'email': _emailCtrl.text.trim().toLowerCase(),
        'phone': _phoneCtrl.text.trim(),
        'isVerified': false,
        'isActive': false,
        'mustChangePassword': false,
        'createdAt': FieldValue.serverTimestamp(),
        'invitedAt': FieldValue.serverTimestamp(),
        'role': 'operator',
        'idStatus': 'not_submitted',
        'shiftRestricted': false,
        'siteScope': _siteScope,
        'allowedSites': _siteScope == 'specific' ? _selectedSites.toList() : [],
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        AppError.show(context, 'Failed to add operator: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.rs)),
      child: SizedBox(
        width: 440,
        child: Padding(
          padding: EdgeInsets.all(24.rs),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_add_rounded, size: 20, color: scheme.primary),
                    SizedBox(width: 10.rs),
                    Text('Add Operator', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
                SizedBox(height: 8.rs),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6.rs),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 13, color: scheme.primary),
                      SizedBox(width: 6.rs),
                      Expanded(
                        child: Text(
                          'Operator will need to log in and confirm to activate their account.',
                          style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20.rs),
                Text('Name', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                SizedBox(height: 6.rs),
                TextFormField(
                  controller: _nameCtrl,
                  style: text.bodySmall,
                  decoration: const InputDecoration(
                    hintText: 'Enter full name',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                SizedBox(height: 16.rs),
                Text('Email', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                SizedBox(height: 6.rs),
                TextFormField(
                  controller: _emailCtrl,
                  style: text.bodySmall,
                  decoration: const InputDecoration(
                    hintText: 'Enter email address',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email is required';
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                if (_domainWarning != null) ...[
                  SizedBox(height: 8.rs),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8.rs),
                      border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.block_rounded, size: 13, color: scheme.error),
                            SizedBox(width: 6.rs),
                            Expanded(
                              child: Text(
                                '"@${_domainWarning!}" is not in the allowed domains list.',
                                style: TextStyle(fontSize: 11, color: scheme.error, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 6.rs),
                        Row(
                          children: [
                            Text(
                              'Allowed: ${_allowedDomains.map((d) => '@$d').join(', ')}',
                              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () => _allowDomain(_domainWarning!),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6.rs),
                                  border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_rounded, size: 12, color: scheme.primary),
                                    SizedBox(width: 4.rs),
                                    Text('Allow @${_domainWarning!}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.primary)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                SizedBox(height: 16.rs),
                Text('Phone', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                SizedBox(height: 6.rs),
                TextFormField(
                  controller: _phoneCtrl,
                  style: text.bodySmall,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: 'Enter phone number',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                SizedBox(height: 16.rs),
                Text('Site Access', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                SizedBox(height: 8.rs),
                Row(
                  children: [
                    _scopeChip('all', 'All Sites', Icons.public_rounded, scheme),
                    SizedBox(width: 8.rs),
                    _scopeChip('specific', 'Specific Sites', Icons.location_on_rounded, scheme),
                  ],
                ),
                if (_siteScope == 'specific' && _allSites.isNotEmpty) ...[
                  SizedBox(height: 10.rs),
                  Container(
                    padding: EdgeInsets.all(10.rs),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8.rs),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _allSites.map((site) {
                          final selected = _selectedSites.contains(site['id']);
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                if (selected) {
                                  if (_selectedSites.length <= 1) return;
                                  _selectedSites.remove(site['id']);
                                } else {
                                  _selectedSites.add(site['id']!);
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: selected ? scheme.primary.withValues(alpha: 0.08) : Colors.transparent,
                                borderRadius: BorderRadius.circular(6.rs),
                                border: selected ? Border.all(color: scheme.primary.withValues(alpha: 0.3)) : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                    size: 16,
                                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                                  ),
                                  SizedBox(width: 8.rs),
                                  Text(
                                    site['name']!,
                                    style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: scheme.onSurface),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
                SizedBox(height: 24.rs),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving || _domainWarning != null ? null : _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
                    ),
                    child: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Invite Operator'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Edit Operator Dialog ─────────────────────────────────────────────────────

class _EditOperatorDialog extends StatefulWidget {
  final WidgetRef ref;
  final Map<String, dynamic> operator;

  const _EditOperatorDialog({required this.ref, required this.operator});

  @override
  State<_EditOperatorDialog> createState() => _EditOperatorDialogState();
}

class _EditOperatorDialogState extends State<_EditOperatorDialog> {
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _idDocNumberCtrl;

  late bool _shiftRestricted;
  late TimeOfDay _shiftStart;
  late TimeOfDay _shiftEnd;
  late List<String> _shiftDays;

  late String _idStatus;
  late String _idDocumentType;

  Map<String, dynamic>? _faceEnrollment;

  late bool _mustChangePassword;
  bool _hasPinSet = false;
  final bool _settingPin = false;
  String? _pinError;

  // Screen visibility permissions
  late bool _canViewCustomers;
  late bool _canViewWeighments;
  late bool _canViewReports;
  late bool _ownWeighmentsOnly;

  // Site scope
  late String _siteScope;
  List<Map<String, String>> _allSites = [];
  late Set<String> _selectedSites;

  // KYC upload & verification (multiple IDs)
  List<Map<String, dynamic>> _verifiedIds = [];
  bool _kycScanning = false;
  String? _kycError;
  String? _kycExtractedName;
  String? _kycExtractedAddress;
  String? _kycNameMatch; // 'exact', 'close', 'mismatch'
  String? _kycDuplicateWarning;
  late bool _wasAlreadyVerified;
  bool _showAddId = false;
  String? _kycSuccessMessage;
  List<String> _kycScannedImages = [];

  // Email/phone change via OTP
  late String _currentEmail;
  late String _currentPhone;
  String? _pendingChangeField; // 'email' or 'phone'
  String _newValueForChange = '';
  bool _otpSent = false;
  bool _otpVerifying = false;
  String? _changeError;
  String _adminEmailDisplay = '';
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(6, (_) => FocusNode());

  static const _allDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _documentTypes = ['Aadhaar', 'PAN', 'Driving License', 'Passport'];

  @override
  void initState() {
    super.initState();
    final op = widget.operator;

    _phoneCtrl = TextEditingController(text: op['phone'] as String? ?? '');
    _idDocNumberCtrl = TextEditingController(text: op['idDocumentNumber'] as String? ?? '');
    _currentEmail = op['email'] as String? ?? '';
    _currentPhone = op['phone'] as String? ?? '';

    _shiftRestricted = op['shiftRestricted'] == true;
    _shiftStart = _parseTime(op['shiftStart'] as String?) ?? const TimeOfDay(hour: 6, minute: 0);
    _shiftEnd = _parseTime(op['shiftEnd'] as String?) ?? const TimeOfDay(hour: 14, minute: 0);
    _shiftDays = (op['shiftDays'] as List<dynamic>?)?.cast<String>() ?? List.from(_allDays.sublist(0, 5));

    _faceEnrollment = op['faceEnrollment'] is Map
        ? Map<String, dynamic>.from(op['faceEnrollment'] as Map)
        : null;

    _idStatus = op['idStatus'] as String? ?? 'not_submitted';
    _idDocumentType = op['idDocumentType'] as String? ?? 'Aadhaar';
    if (!_documentTypes.contains(_idDocumentType)) {
      _idDocumentType = 'Aadhaar';
    }

    // Load existing verified IDs
    final rawIds = op['verifiedIds'] as List<dynamic>? ?? [];
    _verifiedIds = rawIds.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    // Migrate legacy single-ID to list if needed
    if (_verifiedIds.isEmpty && _idStatus == 'verified') {
      final legacyType = op['idDocumentType'] as String? ?? '';
      final legacyNumber = op['idDocumentNumber'] as String? ?? '';
      if (legacyType.isNotEmpty && legacyNumber.isNotEmpty) {
        _verifiedIds.add({'type': legacyType, 'number': legacyNumber, 'verifiedAt': op['idVerifiedAt']});
      }
    }

    // Correct status: if there are verified IDs, status must be 'verified'
    if (_verifiedIds.isNotEmpty && _idStatus != 'verified') {
      _idStatus = 'verified';
      final db = widget.ref.read(firestorePathsProvider);
      db.operators.doc(widget.operator['id']).update({'idStatus': 'verified'});
    }
    _wasAlreadyVerified = _idStatus == 'verified';

    _mustChangePassword = false;
    _hasPinSet = (op['pinHash'] as String?)?.isNotEmpty == true;

    _canViewCustomers = op['canViewCustomers'] as bool? ?? true;
    _canViewWeighments = op['canViewWeighments'] as bool? ?? true;
    _canViewReports = op['canViewReports'] as bool? ?? true;
    _ownWeighmentsOnly = op['ownWeighmentsOnly'] as bool? ?? false;

    _siteScope = op['siteScope'] as String? ?? 'all';
    final rawSites = op['allowedSites'] as List<dynamic>? ?? [];
    _selectedSites = rawSites.cast<String>().toSet();
    _loadSites();
  }

  Future<void> _loadSites() async {
    try {
      final paths = widget.ref.read(firestorePathsProvider);
      final snap = await paths.firestore.collection('companies/${paths.context.companyId}/sites').get();
      if (mounted) {
        setState(() {
          _allSites = snap.docs.map((d) => {'id': d.id, 'name': d.data()['name'] as String? ?? 'Unnamed Site'}).toList();
        });
      }
    } catch (_) {}
  }

  Widget _editScopeChip(String value, String label, IconData icon, ColorScheme scheme) {
    final active = _siteScope == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _siteScope = value);
          _saveField({'siteScope': value, 'allowedSites': value == 'specific' ? _selectedSites.toList() : []});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: active ? scheme.primary.withValues(alpha: 0.1) : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8.rs),
            border: Border.all(color: active ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: active ? scheme.primary : scheme.onSurfaceVariant),
              SizedBox(width: 6.rs),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? scheme.primary : scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _idDocNumberCtrl.dispose();
    for (final c in _otpControllers) { c.dispose(); }
    for (final f in _otpFocusNodes) { f.dispose(); }
    super.dispose();
  }

  String get _otpValue => _otpControllers.map((c) => c.text).join();

  Future<void> _refreshFaceEnrollment() async {
    try {
      final paths = widget.ref.read(firestorePathsProvider);
      final doc = await paths.operators.doc(widget.operator['id']).get();
      final data = doc.data();
      if (data != null && mounted) {
        setState(() {
          _faceEnrollment = data['faceEnrollment'] is Map
              ? Map<String, dynamic>.from(data['faceEnrollment'] as Map)
              : null;
        });
      }
    } catch (_) {}
  }

  Future<void> _startChangeField(String field) async {
    final email = await _getAdminEmail();
    setState(() {
      _pendingChangeField = field;
      _otpSent = false;
      _changeError = null;
      _newValueForChange = '';
      _adminEmailDisplay = email ?? '';
      for (final c in _otpControllers) { c.clear(); }
    });
  }

  Future<String?> _getAdminEmail() async {
    final authEmail = FirebaseAuth.instance.currentUser?.email;
    if (authEmail != null && authEmail.isNotEmpty) return authEmail;
    return await LocalCacheService.getCachedCurrentUserEmail();
  }

  Future<void> _sendAdminOTP() async {
    final adminEmail = await _getAdminEmail();
    if (adminEmail == null || adminEmail.isEmpty) {
      setState(() => _changeError = 'Admin email not available.');
      return;
    }
    setState(() { _changeError = null; _otpVerifying = true; });
    try {
      await FirebaseFunctions.instance
          .httpsCallable('sendEmailOTP')
          .call({'email': adminEmail});
      setState(() => _otpSent = true);
    } catch (e) {
      setState(() => _changeError = 'Failed to send OTP to admin.');
    } finally {
      setState(() => _otpVerifying = false);
    }
  }

  Future<void> _verifyAndApplyChange() async {
    final otp = _otpValue;
    if (otp.length != 6) {
      setState(() => _changeError = 'Enter all 6 digits.');
      return;
    }
    final adminEmail = await _getAdminEmail();
    if (adminEmail == null || adminEmail.isEmpty) return;

    setState(() { _otpVerifying = true; _changeError = null; });
    try {
      await FirebaseFunctions.instance
          .httpsCallable('verifyEmailOTP')
          .call({'email': adminEmail, 'otp': otp});

      // OTP verified — apply the change
      final db = widget.ref.read(firestorePathsProvider);
      final field = _pendingChangeField!;
      final newVal = _newValueForChange.trim();

      if (newVal.isEmpty) {
        setState(() => _changeError = 'New value cannot be empty.');
        return;
      }

      final updateData = <String, dynamic>{field: field == 'email' ? newVal.toLowerCase() : newVal};

      // If changing email, also update Firebase Auth email
      if (field == 'email') {
        final opUid = widget.operator['uid'] as String? ?? '';
        if (opUid.isNotEmpty) {
          try {
            await FirebaseFunctions.instance
                .httpsCallable('updateOperatorEmail')
                .call({'uid': opUid, 'newEmail': newVal.toLowerCase()});
          } catch (_) {}
        }
      }

      await db.operators.doc(widget.operator['id']).update(updateData);

      setState(() {
        if (field == 'email') {
          _currentEmail = newVal.toLowerCase();
        } else {
          _currentPhone = newVal;
          _phoneCtrl.text = newVal;
        }
        _pendingChangeField = null;
        _otpSent = false;
      });

      if (mounted) {
        AppError.success(context, '${field == 'email' ? 'Email' : 'Phone'} updated successfully.');
      }
    } on FirebaseFunctionsException catch (e) {
      setState(() => _changeError = e.message ?? 'Invalid OTP.');
    } catch (e) {
      setState(() => _changeError = 'Verification failed.');
    } finally {
      setState(() => _otpVerifying = false);
    }
  }

  void _cancelChange() {
    setState(() {
      _pendingChangeField = null;
      _otpSent = false;
      _changeError = null;
      for (final c in _otpControllers) { c.clear(); }
    });
  }

  TimeOfDay? _parseTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return null;
    final parts = timeStr.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _formatTimeOfDay(TimeOfDay t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  String _formatTimestamp(dynamic timestamp, String timeFormat) {
    if (timestamp == null) return 'Never';
    if (timestamp is Timestamp) {
      return formatTimestamp(timestamp, timeFormat);
    }
    return 'Never';
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart ? _shiftStart : _shiftEnd;
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        if (isStart) {
          _shiftStart = picked;
        } else {
          _shiftEnd = picked;
        }
      });
      _saveField({
        if (isStart) 'shiftStart': _formatTimeOfDay(picked) else 'shiftEnd': _formatTimeOfDay(picked),
      });
    }
  }

  Widget _buildContactSection(ColorScheme scheme, TextTheme text) {
    if (_pendingChangeField != null) {
      return _buildOtpChangeFlow(scheme, text);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Email', text),
        SizedBox(height: 6.rs),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8.rs),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _currentEmail.isNotEmpty ? _currentEmail : '--',
                  style: text.bodySmall?.copyWith(color: scheme.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SizedBox(width: 8.rs),
            SizedBox(
              height: 36,
              child: OutlinedButton(
                onPressed: () => _startChangeField('email'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
                ),
                child: const Text('Change'),
              ),
            ),
          ],
        ),
        SizedBox(height: 14.rs),
        _fieldLabel('Phone', text),
        SizedBox(height: 6.rs),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8.rs),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _currentPhone.isNotEmpty ? _currentPhone : '--',
                  style: text.bodySmall?.copyWith(color: scheme.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SizedBox(width: 8.rs),
            SizedBox(
              height: 36,
              child: OutlinedButton(
                onPressed: () => _startChangeField('phone'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
                ),
                child: const Text('Change'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOtpChangeFlow(ColorScheme scheme, TextTheme text) {
    final fieldLabel = _pendingChangeField == 'email' ? 'Email' : 'Phone';
    final adminEmail = _adminEmailDisplay;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.edit_rounded, size: 14, color: scheme.primary),
            SizedBox(width: 6.rs),
            Text('Change Operator $fieldLabel', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary)),
            const Spacer(),
            GestureDetector(
              onTap: _cancelChange,
              child: Icon(Icons.close_rounded, size: 16, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        SizedBox(height: 12.rs),

        if (!_otpSent) ...[
          Text(
            'New $fieldLabel',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurface),
          ),
          SizedBox(height: 6.rs),
          TextField(
            onChanged: (v) => _newValueForChange = v,
            style: text.bodySmall,
            keyboardType: _pendingChangeField == 'email'
                ? TextInputType.emailAddress
                : TextInputType.phone,
            decoration: InputDecoration(
              hintText: _pendingChangeField == 'email' ? 'new@email.com' : 'New phone number',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: Icon(
                  _pendingChangeField == 'email' ? Icons.email_outlined : Icons.phone_outlined,
                  size: 16, color: scheme.onSurfaceVariant,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            ),
          ),
          SizedBox(height: 12.rs),
          Container(
            padding: EdgeInsets.all(10.rs),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8.rs),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: scheme.primary),
                SizedBox(width: 8.rs),
                Expanded(
                  child: Text(
                    'A verification code will be sent to your admin email ($adminEmail) for confirmation.',
                    style: TextStyle(fontSize: 10, color: scheme.primary),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 14.rs),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _otpVerifying ? null : _sendAdminOTP,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
              ),
              child: _otpVerifying
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Send Verification Code'),
            ),
          ),
        ],

        if (_otpSent) ...[
          Text(
            'Enter code sent to $adminEmail',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          SizedBox(height: 10.rs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (i) {
              return Container(
                width: 38,
                height: 44,
                margin: EdgeInsets.only(right: i < 5 ? 6 : 0),
                child: TextField(
                  controller: _otpControllers[i],
                  focusNode: _otpFocusNodes[i],
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 1,
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.rs)),
                  ),
                  onChanged: (val) {
                    if (val.isNotEmpty && i < 5) {
                      _otpFocusNodes[i + 1].requestFocus();
                    } else if (val.isEmpty && i > 0) {
                      _otpFocusNodes[i - 1].requestFocus();
                    }
                    if (_otpValue.length == 6) {
                      _verifyAndApplyChange();
                    }
                  },
                ),
              );
            }),
          ),
          SizedBox(height: 14.rs),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _otpVerifying ? null : _verifyAndApplyChange,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
              ),
              child: _otpVerifying
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Verify & Update'),
            ),
          ),
          SizedBox(height: 8.rs),
          Center(
            child: TextButton(
              onPressed: _otpVerifying ? null : _sendAdminOTP,
              child: Text('Resend Code', style: TextStyle(fontSize: 11, color: scheme.primary)),
            ),
          ),
        ],

        if (_changeError != null) ...[
          SizedBox(height: 10.rs),
          Container(
            padding: EdgeInsets.all(8.rs),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8.rs),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 13, color: scheme.error),
                SizedBox(width: 6.rs),
                Expanded(child: Text(_changeError!, style: TextStyle(fontSize: 11, color: scheme.error))),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAddressSection(ColorScheme scheme, TextTheme text, Map<String, dynamic> op) {
    final currentAddress = [
      op['address'] as String? ?? '',
      if ((op['address2'] as String? ?? '').isNotEmpty) op['address2'] as String,
    ].where((s) => s.isNotEmpty).join(', ');
    final regAddress = op['registrationAddress'] as String? ?? '';

    // Collect all distinct addresses from verified IDs
    final idAddresses = <String, String>{};
    for (final id in _verifiedIds) {
      final addr = id['address'] as String? ?? '';
      if (addr.isNotEmpty && addr != currentAddress) {
        idAddresses[id['type'] as String? ?? ''] = addr;
      }
    }
    // Also if registrationAddress exists and differs
    if (regAddress.isNotEmpty && regAddress != currentAddress) {
      idAddresses['Registration'] = regAddress;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(currentAddress.isNotEmpty ? currentAddress : 'No address', style: text.bodySmall?.copyWith(color: scheme.onSurface)),
        if (idAddresses.isNotEmpty) ...[
          SizedBox(height: 10.rs),
          Text('Other addresses on file:', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
          SizedBox(height: 6.rs),
          ...idAddresses.entries.map((entry) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.key, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
                      Text(entry.value, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                SizedBox(width: 8.rs),
                GestureDetector(
                  onTap: () {
                    final oldAddress = currentAddress;
                    _saveField({'address': entry.value, 'address2': '', 'registrationAddress': oldAddress.isNotEmpty ? oldAddress : regAddress});
                    setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6.rs),
                    ),
                    child: Text('Use this', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.primary)),
                  ),
                ),
              ],
            ),
          )),
        ],
      ],
    );
  }

  Widget _buildKycSection(ColorScheme scheme, TextTheme text, Map<String, dynamic> op) {
    final fe = _faceEnrollment;
    final faceEnrolled = fe?['enrolled'] == true;
    final faceValidCount = fe?['validFrameCount'] as int? ?? fe?['faceCount'] as int? ?? 0;
    final faceConfidence = fe?['averageConfidence'] as double? ?? 0.0;
    final faceEnrolledAt = fe?['enrolledAt'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Face enrollment status
        Row(
          children: [
            Icon(Icons.face_rounded, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
            SizedBox(width: 8.rs),
            Text('Face Enrollment', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
          ],
        ),
        SizedBox(height: 8.rs),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(10.rs),
          decoration: BoxDecoration(
            color: faceEnrolled ? Colors.green.withValues(alpha: 0.05) : scheme.errorContainer.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8.rs),
            border: Border.all(color: faceEnrolled ? Colors.green.withValues(alpha: 0.2) : scheme.error.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(faceEnrolled ? Icons.check_circle_rounded : Icons.cancel_rounded, size: 13, color: faceEnrolled ? Colors.green : scheme.error),
                  SizedBox(width: 6.rs),
                  Text(faceEnrolled ? 'Enrolled' : 'Not enrolled', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: faceEnrolled ? Colors.green.shade700 : scheme.error)),
                  if (faceEnrolled) ...[
                    SizedBox(width: 12.rs),
                    Text('$faceValidCount valid · ${(faceConfidence * 100).toStringAsFixed(0)}% conf', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                  ],
                ],
              ),
              if (faceEnrolled && faceEnrolledAt != null) ...[
                SizedBox(height: 6.rs),
                Row(
                  children: [
                    Icon(Icons.event_rounded, size: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                    SizedBox(width: 4.rs),
                    Text('First: ${_formatTimestamp(faceEnrolledAt, widget.ref.read(timeFormatProvider))}', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
                  ],
                ),
                if (fe?['lastTrainedAt'] != null) ...[
                  SizedBox(height: 3.rs),
                  Row(
                    children: [
                      Icon(Icons.update_rounded, size: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                      SizedBox(width: 4.rs),
                      Text('Last: ${_formatTimestamp(fe!['lastTrainedAt'], widget.ref.read(timeFormatProvider))}', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
                      if (fe['trainingSessions'] != null) ...[
                        SizedBox(width: 8.rs),
                        Text('(${fe['trainingSessions']} training sessions)', style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
                      ],
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
        SizedBox(height: 8.rs),
        _FaceEnrollmentWidget(
          ref: widget.ref,
          operatorId: widget.operator['id'] as String,
          existingFacePhoto: widget.operator['facePhoto'] as String?,
          existingFaceEnrollment: _faceEnrollment,
          onEnrollmentComplete: _refreshFaceEnrollment,
        ),

        // Operator's submitted ID (from registration)
        if ((op['idDocType'] as String? ?? '').isNotEmpty || (op['idDocNumber'] as String? ?? '').isNotEmpty) ...[
          SizedBox(height: 14.rs),
          Row(
            children: [
              Icon(Icons.badge_rounded, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
              SizedBox(width: 8.rs),
              Text('Submitted at Registration', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
            ],
          ),
          SizedBox(height: 8.rs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8.rs),
              border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified_rounded, size: 15, color: Colors.green),
                    SizedBox(width: 10.rs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((op['idDocType'] as String? ?? '').isNotEmpty)
                            Text(op['idDocType'] as String, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: Colors.green.shade700)),
                          if ((op['idDocNumber'] as String? ?? '').isNotEmpty)
                            Text(op['idDocNumber'] as String, style: text.bodySmall?.copyWith(color: scheme.onSurface, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (_hasIdDocImages(op))
                      GestureDetector(
                        onTap: () => _showViewIdFromEdit(op, scheme),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6.rs),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.visibility_rounded, size: 12, color: scheme.primary),
                              SizedBox(width: 4.rs),
                              Text('View', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.primary)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                if (!_verifiedIds.any((id) => id['type'] == (op['idDocType'] as String? ?? '') && id['number'] == (op['idDocNumber'] as String? ?? ''))) ...[
                  SizedBox(height: 8.rs),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _mergeRegistrationId(op),
                      icon: const Icon(Icons.merge_rounded, size: 14),
                      label: const Text('Merge to Verified IDs', style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green.shade700,
                        side: BorderSide(color: Colors.green.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7.rs)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],

        SizedBox(height: 14.rs),
        Row(
          children: [
            Icon(Icons.verified_user_rounded, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
            SizedBox(width: 8.rs),
            Text('Admin-Verified IDs', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
          ],
        ),
        SizedBox(height: 8.rs),

        // Success message
        if (_kycSuccessMessage != null) ...[
          Container(
            padding: EdgeInsets.all(10.rs),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8.rs),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 15, color: Colors.green),
                SizedBox(width: 8.rs),
                Expanded(child: Text(_kycSuccessMessage!, style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
          SizedBox(height: 12.rs),
        ],

        // Verified IDs list
        if (_verifiedIds.isNotEmpty) ...[
          ..._verifiedIds.asMap().entries.map((entry) {
            final idx = entry.key;
            final id = entry.value;
            final type = id['type'] as String? ?? '';
            final number = id['number'] as String? ?? '';
            return Container(
              margin: EdgeInsets.only(bottom: idx < _verifiedIds.length - 1 ? 8 : 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8.rs),
                border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded, size: 15, color: Colors.green),
                  SizedBox(width: 10.rs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(type, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: Colors.green.shade700)),
                        Text(number, style: text.bodySmall?.copyWith(color: scheme.onSurface, fontSize: 12)),
                      ],
                    ),
                  ),
                  if ((id['localImageDir'] as String? ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => _showVerifiedIdImages(id, scheme),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6.rs),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.visibility_rounded, size: 12, color: scheme.primary),
                              SizedBox(width: 4.rs),
                              Text('View', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.primary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_verifiedIds.length > 1)
                    GestureDetector(
                      onTap: () => _removeVerifiedId(idx),
                      child: Container(
                        padding: EdgeInsets.all(4.rs),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(6.rs),
                        ),
                        child: Icon(Icons.close_rounded, size: 12, color: scheme.error),
                      ),
                    ),
                ],
              ),
            );
          }),
          SizedBox(height: 12.rs),
        ],

        if (_verifiedIds.isEmpty && !_showAddId)
          Text('No IDs verified yet.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),

        // Add new ID section
        if (_showAddId) ...[
          // Document type dropdown
          _fieldLabel('Document Type', text),
          SizedBox(height: 6.rs),
          Builder(builder: (_) {
            final available = _documentTypes.where((e) => !_verifiedIds.any((id) => id['type'] == e)).toList();
            if (available.isEmpty) return const SizedBox.shrink();
            final selected = available.contains(_idDocumentType) ? _idDocumentType : available.first;
            if (selected != _idDocumentType) {
              _idDocumentType = selected;
            }
            return DropdownButtonFormField<String>(
              initialValue: selected,
              items: available.map((e) => DropdownMenuItem(value: e, child: Text(e, style: text.bodySmall))).toList(),
              onChanged: (v) { if (v != null) setState(() => _idDocumentType = v); },
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.rs), borderSide: BorderSide(color: scheme.outlineVariant)),
              ),
              style: text.bodySmall,
              icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: scheme.onSurfaceVariant),
            );
          }),
          SizedBox(height: 12.rs),

          // Document number (read-only, extracted from scan)
          if (_idDocNumberCtrl.text.isNotEmpty) ...[
            _fieldLabel('Extracted Number', text),
            SizedBox(height: 6.rs),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8.rs),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Text(_idDocNumberCtrl.text, style: text.bodySmall),
            ),
            SizedBox(height: 12.rs),
          ],

          // Upload hint + button
          Container(
            padding: EdgeInsets.all(10.rs),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8.rs),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: scheme.primary),
                SizedBox(width: 8.rs),
                Expanded(child: Text(_idUploadHint(), style: TextStyle(fontSize: 10, color: scheme.primary))),
              ],
            ),
          ),
          SizedBox(height: 10.rs),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _kycScanning ? null : _uploadAndScanId,
              icon: _kycScanning
                  ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary))
                  : const Icon(Icons.upload_file_rounded, size: 16),
              label: Text(_kycScanning ? 'Scanning...' : 'Upload & Scan ID', style: const TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
              ),
            ),
          ),
          SizedBox(height: 4.rs),
          Text('Select multiple files for front + back. Accepts PDF, JPG, PNG.', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 10)),

          // Scan error
          if (_kycError != null) ...[
            SizedBox(height: 10.rs),
            Container(
              padding: EdgeInsets.all(10.rs),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8.rs),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 14, color: scheme.error),
                  SizedBox(width: 8.rs),
                  Expanded(child: Text(_kycError!, style: TextStyle(fontSize: 11, color: scheme.error))),
                ],
              ),
            ),
          ],

          // Name match result
          if (_kycNameMatch != null && _kycExtractedName != null) ...[
            SizedBox(height: 12.rs),
            if (_kycNameMatch == 'exact')
              Container(
                padding: EdgeInsets.all(10.rs),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8.rs),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 15, color: Colors.green),
                    SizedBox(width: 8.rs),
                    Expanded(child: Text('Name matches: $_kycExtractedName', style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600))),
                  ],
                ),
              ),

            if (_kycNameMatch == 'close') ...[
              Container(
                padding: EdgeInsets.all(10.rs),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8.rs),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_rounded, size: 14, color: Colors.orange.shade700),
                        SizedBox(width: 8.rs),
                        Expanded(child: Text('Name on ID: "$_kycExtractedName"', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade700))),
                      ],
                    ),
                    SizedBox(height: 8.rs),
                    Text(
                      _wasAlreadyVerified
                          ? 'Slightly different from operator name "${op['name']}". Name cannot be changed after first verification.'
                          : 'Slightly different from operator name "${op['name']}". Update name to match ID?',
                      style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                    ),
                    SizedBox(height: 10.rs),
                    Row(
                      children: [
                        if (!_wasAlreadyVerified) ...[
                          Expanded(
                            child: FilledButton(
                              onPressed: () => _applyKycVerification(_kycExtractedName),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7.rs)),
                              ),
                              child: const Text('Update Name & Verify'),
                            ),
                          ),
                          SizedBox(width: 8.rs),
                        ],
                        Expanded(
                          child: _wasAlreadyVerified
                              ? FilledButton(
                                  onPressed: () => _applyKycVerification(null),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7.rs)),
                                  ),
                                  child: const Text('Verify'),
                                )
                              : OutlinedButton(
                                  onPressed: () => _applyKycVerification(null),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7.rs)),
                                  ),
                                  child: const Text('Keep & Verify'),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            if (_kycNameMatch == 'mismatch') ...[
              Container(
                padding: EdgeInsets.all(10.rs),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8.rs),
                  border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.error_rounded, size: 14, color: scheme.error),
                        SizedBox(width: 8.rs),
                        Expanded(child: Text('Name mismatch', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.error))),
                      ],
                    ),
                    SizedBox(height: 6.rs),
                    Text('ID says: "$_kycExtractedName"', style: TextStyle(fontSize: 11, color: scheme.onSurface)),
                    Text('Operator: "${op['name']}"', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                    SizedBox(height: 10.rs),
                    Row(
                      children: [
                        if (!_wasAlreadyVerified) ...[
                          Expanded(
                            child: FilledButton(
                              onPressed: () => _applyKycVerification(_kycExtractedName),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7.rs)),
                                backgroundColor: Colors.orange,
                              ),
                              child: const Text('Use ID Name & Verify'),
                            ),
                          ),
                          SizedBox(width: 8.rs),
                        ],
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              _rejectId();
                              setState(() => _showAddId = false);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: scheme.error,
                              side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7.rs)),
                            ),
                            child: const Text('Reject'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],

          // Duplicate name warning
          if (_kycDuplicateWarning != null) ...[
            SizedBox(height: 10.rs),
            Container(
              padding: EdgeInsets.all(10.rs),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.rs),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_rounded, size: 14, color: Colors.amber.shade700),
                  SizedBox(width: 8.rs),
                  Expanded(child: Text(_kycDuplicateWarning!, style: TextStyle(fontSize: 10, color: Colors.amber.shade900))),
                ],
              ),
            ),
          ],

          SizedBox(height: 10.rs),
          Center(
            child: TextButton(
              onPressed: () => setState(() { _showAddId = false; _kycError = null; _kycNameMatch = null; _idDocNumberCtrl.clear(); }),
              child: Text('Cancel', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ),
          ),
        ],

        // Add ID button (hide if all types already verified)
        if (!_showAddId && _documentTypes.any((e) => !_verifiedIds.any((id) => id['type'] == e))) ...[
          SizedBox(height: 12.rs),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                final available = _documentTypes.where((e) => !_verifiedIds.any((id) => id['type'] == e)).toList();
                if (available.isEmpty) return;
                setState(() { _showAddId = true; _kycError = null; _kycNameMatch = null; _idDocNumberCtrl.clear(); _idDocumentType = available.first; });
              },
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(_verifiedIds.isEmpty ? 'Add ID Document' : 'Add Another ID', style: const TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
              ),
            ),
          ),
        ],

      ],
    );
  }

  bool _hasIdDocImages(Map<String, dynamic> op) {
    final images = op['idDocImages'] as List<dynamic>? ?? [];
    if (images.isNotEmpty) return true;
    final legacy = op['idImageBase64'] as String?;
    return legacy != null && legacy.isNotEmpty;
  }

  void _showVerifiedIdImages(Map<String, dynamic> id, ColorScheme scheme) {
    final text = Theme.of(context).textTheme;
    final type = id['type'] as String? ?? '';
    final number = id['number'] as String? ?? '';
    final localDir = id['localImageDir'] as String? ?? '';

    List<File> imageFiles = [];
    if (localDir.isNotEmpty) {
      final dir = Directory(localDir);
      if (dir.existsSync()) {
        imageFiles = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.png') || f.path.endsWith('.jpg')).toList()
          ..sort((a, b) => a.path.compareTo(b.path));
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.rs)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 750),
          child: Padding(
            padding: EdgeInsets.all(24.rs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.verified_user_rounded, size: 20, color: scheme.primary),
                    SizedBox(width: 10.rs),
                    Expanded(child: Text('$type — $number', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh),
                    ),
                  ],
                ),
                if (id['verifiedBy'] != null) ...[
                  SizedBox(height: 8.rs),
                  Text('Verified by ${id['verifiedBy']}', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 11)),
                ],
                SizedBox(height: 16.rs),
                if (imageFiles.isNotEmpty) ...[
                  Text('Document Image${imageFiles.length > 1 ? 's (${imageFiles.length})' : ''}', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                  SizedBox(height: 10.rs),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: imageFiles.length,
                      separatorBuilder: (_, __) => SizedBox(height: 10.rs),
                      itemBuilder: (_, i) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8.rs),
                          child: Image.file(imageFiles[i], fit: BoxFit.contain),
                        );
                      },
                    ),
                  ),
                ] else
                  Text('No document images available.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showViewIdFromEdit(Map<String, dynamic> op, ColorScheme scheme) {
    final text = Theme.of(context).textTheme;
    final idDocType = op['idDocType'] as String? ?? op['idDocumentType'] as String? ?? '';
    final idDocNumber = op['idDocNumber'] as String? ?? op['idDocumentNumber'] as String? ?? '';
    var idDocImages = op['idDocImages'] as List<dynamic>? ?? [];
    if (idDocImages.isEmpty) {
      final legacy = op['idImageBase64'] as String?;
      if (legacy != null && legacy.isNotEmpty) idDocImages = [legacy];
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.rs)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 750),
          child: Padding(
            padding: EdgeInsets.all(24.rs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.badge_rounded, size: 20, color: scheme.primary),
                    SizedBox(width: 10.rs),
                    Text('Submitted ID Document', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, size: 18)),
                  ],
                ),
                if (idDocType.isNotEmpty || idDocNumber.isNotEmpty) ...[
                  SizedBox(height: 12.rs),
                  Row(
                    children: [
                      if (idDocType.isNotEmpty) ...[
                        Icon(Icons.article_rounded, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        SizedBox(width: 6.rs),
                        Text(idDocType, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                      if (idDocNumber.isNotEmpty) ...[
                        SizedBox(width: 16.rs),
                        Icon(Icons.numbers_rounded, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        SizedBox(width: 6.rs),
                        Text(idDocNumber, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                      ],
                    ],
                  ),
                ],
                SizedBox(height: 16.rs),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: idDocImages.length,
                    separatorBuilder: (_, __) => SizedBox(height: 8.rs),
                    itemBuilder: (_, i) {
                      final raw = idDocImages[i] as String;
                      return _IdDocImageView(base64Data: raw, scheme: scheme);
                    },
                  ),
                ),
                SizedBox(height: 16.rs),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Future<void> _saveField(Map<String, dynamic> fields) async {
    try {
      final db = widget.ref.read(firestorePathsProvider);
      await db.operators.doc(widget.operator['id']).update(fields);
    } catch (e) {
      if (mounted) {
        AppError.show(context, 'Failed to save: $e');
      }
    }
  }


  Future<void> _showSetPinDialog(BuildContext ctx, Map<String, dynamic> op, ColorScheme scheme) async {
    final pinCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? dlgError;

    final result = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.rs)),
          title: Row(
            children: [
              Icon(Icons.pin_rounded, color: scheme.primary, size: 20),
              SizedBox(width: 10.rs),
              Text(_hasPinSet ? 'Reset PIN' : 'Set Verification PIN', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Enter a 4-6 digit PIN for identity verification fallback.', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                SizedBox(height: 20.rs),
                TextField(
                  controller: pinCtrl,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: 'New PIN',
                    counterText: '',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.rs)),
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                  ),
                ),
                SizedBox(height: 12.rs),
                TextField(
                  controller: confirmCtrl,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: 'Confirm PIN',
                    counterText: '',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.rs)),
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                  ),
                ),
                if (dlgError != null) ...[
                  SizedBox(height: 10.rs),
                  Text(dlgError!, style: TextStyle(fontSize: 11, color: scheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final pin = pinCtrl.text.trim();
                final confirm = confirmCtrl.text.trim();
                if (pin.length < 4) {
                  setDlgState(() => dlgError = 'PIN must be at least 4 digits.');
                  return;
                }
                if (pin != confirm) {
                  setDlgState(() => dlgError = 'PINs do not match.');
                  return;
                }
                if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
                  setDlgState(() => dlgError = 'PIN must be 4-6 digits only.');
                  return;
                }
                setDlgState(() => dlgError = null);

                try {
                  final paths = widget.ref.read(firestorePathsProvider);
                  final companyId = paths.context.companyId;
                  final email = op['email'] as String? ?? '';

                  await FirebaseFunctions.instance
                      .httpsCallable('setOperatorPin')
                      .call({'pin': pin, 'companyId': companyId, 'operatorEmail': email});

                  if (dialogCtx.mounted) Navigator.of(dialogCtx).pop(true);
                } catch (e) {
                  setDlgState(() => dlgError = 'Failed to set PIN: $e');
                }
              },
              child: const Text('Save PIN'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() { _hasPinSet = true; _pinError = null; });
    }
  }

  Future<void> _rejectId() async {
    final db = widget.ref.read(firestorePathsProvider);
    final status = _verifiedIds.isNotEmpty ? 'verified' : 'rejected';
    await db.operators.doc(widget.operator['id']).update({
      'idStatus': status,
    });
    setState(() => _idStatus = status);
  }

  String _idUploadHint() => switch (_idDocumentType) {
    'Aadhaar' => 'Upload both sides (front + back) of your Aadhaar card.',
    'PAN' => 'Upload full PAN card (front side with photo and number).',
    'Driving License' => 'Upload both sides (front + back) of Driving License.',
    'Passport' => 'Upload passport pages showing photo and details.',
    _ => 'Upload all relevant pages/sides of the document.',
  };

  Future<void> _uploadAndScanId() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() { _kycScanning = true; _kycError = null; _kycExtractedName = null; _kycNameMatch = null; _kycDuplicateWarning = null; });

    try {
      // Read file bytes — withData may not work on desktop, fall back to path
      final images = <String>[];
      for (final f in result.files) {
        if (f.bytes != null && f.bytes!.isNotEmpty) {
          images.add(base64Encode(f.bytes!));
        } else if (f.path != null && f.path!.isNotEmpty) {
          try {
            final file = File(f.path!);
            if (await file.exists()) {
              final fileBytes = await file.readAsBytes();
              if (fileBytes.isNotEmpty) images.add(base64Encode(fileBytes));
            }
          } catch (_) {}
        }
      }
      if (images.isEmpty) {
        setState(() { _kycScanning = false; _kycError = 'Could not read the selected file(s). Try a PDF instead.'; });
        return;
      }
      // Convert PDFs to PNG for viewable storage
      final viewableImages = <String>[];
      for (final img in images) {
        final bytes = base64Decode(img);
        if (bytes.length > 4 && String.fromCharCodes(bytes.sublist(0, 4)) == '%PDF') {
          try {
            final doc = await PdfDocument.openData(bytes);
            for (int p = 1; p <= doc.pagesCount && p <= 4; p++) {
              final page = await doc.getPage(p);
              final pageImage = await page.render(width: page.width * 2, height: page.height * 2, format: PdfPageImageFormat.png);
              if (pageImage != null) viewableImages.add(base64Encode(pageImage.bytes));
              await page.close();
            }
            await doc.close();
          } catch (_) {
            viewableImages.add(img);
          }
        } else {
          viewableImages.add(img);
        }
      }
      _kycScannedImages = viewableImages;
      final operatorName = widget.operator['name'] as String? ?? '';

      final paths = widget.ref.read(firestorePathsProvider);
      final response = await FirebaseFunctions.instance
          .httpsCallable('verifyOperatorId', options: HttpsCallableOptions(timeout: const Duration(seconds: 90)))
          .call({
        'images': images,
        'documentType': _idDocumentType,
        'operatorName': operatorName,
        'operatorId': widget.operator['id'] as String? ?? '',
        'companyId': paths.context.companyId,
      });

      final data = response.data as Map<String, dynamic>;

      if (data['valid'] != true) {
        setState(() => _kycError = data['message'] as String? ?? 'Verification failed.');
        return;
      }

      final extractedName = data['extractedName'] as String?;
      final extractedDocNumber = data['extractedDocNumber'] as String?;
      final extractedAddress = data['extractedAddress'] as String?;
      final nameMatch = data['nameMatch'] as String?;
      final duplicateWarning = data['duplicateWarning'] as String?;

      setState(() {
        _kycExtractedName = extractedName;
        _kycExtractedAddress = extractedAddress;
        _kycNameMatch = nameMatch;
        _kycDuplicateWarning = duplicateWarning;
        if (extractedDocNumber != null && extractedDocNumber.isNotEmpty) {
          _idDocNumberCtrl.text = extractedDocNumber;
        }
      });

      // Auto-verify if exact match (with brief delay to show success state)
      if (nameMatch == 'exact') {
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) await _applyKycVerification(null);
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _kycError = e.message ?? 'Scan failed.');
    } catch (e) {
      if (mounted) setState(() => _kycError = 'Failed to scan document.');
    } finally {
      if (mounted) setState(() => _kycScanning = false);
    }
  }

  Future<void> _applyKycVerification(String? newName) async {
    final db = widget.ref.read(firestorePathsProvider);
    final adminEmail = await _getAdminEmail() ?? 'admin';
    final docNumber = _idDocNumberCtrl.text.trim();

    final newIdEntry = <String, dynamic>{
      'type': _idDocumentType,
      'number': docNumber,
      'verifiedBy': adminEmail,
      'verifiedAt': DateTime.now().toIso8601String(),
      if (_kycExtractedAddress != null) 'address': _kycExtractedAddress,
    };

    // Save ID images to local disk (too large for Firestore)
    if (_kycScannedImages.isNotEmpty) {
      try {
        final operatorId = widget.operator['id'] as String;
        final dir = Directory('${Directory.systemTemp.path}/weigh_id_docs/$operatorId');
        if (!dir.existsSync()) dir.createSync(recursive: true);
        for (int i = 0; i < _kycScannedImages.length; i++) {
          final file = File('${dir.path}/${_idDocumentType.toLowerCase()}_$i.png');
          await file.writeAsBytes(base64Decode(_kycScannedImages[i]));
        }
        newIdEntry['localImageDir'] = dir.path;
      } catch (_) {}
    }

    final updatedIds = [..._verifiedIds, newIdEntry];
    final updateData = <String, dynamic>{
      'idStatus': 'verified',
      'idVerifiedAt': FieldValue.serverTimestamp(),
      'idVerifiedBy': adminEmail,
      'idDocumentType': _idDocumentType,
      'idDocumentNumber': docNumber,
      'verifiedIds': updatedIds,
    };
    if (newName != null && newName.isNotEmpty) {
      updateData['name'] = newName;
    }
    if (_kycExtractedAddress != null && _kycExtractedAddress!.isNotEmpty) {
      final currentAddress = widget.operator['address'] as String? ?? '';
      if (currentAddress.isNotEmpty && widget.operator['registrationAddress'] == null) {
        updateData['registrationAddress'] = currentAddress;
      }
      updateData['address'] = _kycExtractedAddress;
    }

    try {
      await db.operators.doc(widget.operator['id']).update(updateData);
      _verifiedIds = updatedIds;
      if (mounted) {
        setState(() {
          _idStatus = 'verified';
          _kycNameMatch = null;
          _kycExtractedName = null;
          _kycExtractedAddress = null;
          _kycDuplicateWarning = null;
          _kycError = null;
          _showAddId = false;
          _idDocNumberCtrl.clear();
          _kycScannedImages = [];
          _kycSuccessMessage = newName != null ? 'ID verified, name updated to "$newName".' : 'ID verified successfully.';
        });
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _kycSuccessMessage = null);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _kycError = 'Failed to save verification: $e';
        });
      }
    }
  }

  Future<void> _removeVerifiedId(int idx) async {
    if (_verifiedIds.length <= 1) return;
    final removed = _verifiedIds.removeAt(idx);
    final db = widget.ref.read(firestorePathsProvider);
    await db.operators.doc(widget.operator['id']).update({
      'verifiedIds': _verifiedIds,
    });
    setState(() {
      _kycSuccessMessage = '${removed['type'] ?? 'ID'} removed.';
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _kycSuccessMessage = null);
    });
  }

  Future<void> _mergeRegistrationId(Map<String, dynamic> op) async {
    final docType = op['idDocType'] as String? ?? '';
    final docNumber = op['idDocNumber'] as String? ?? '';
    if (docType.isEmpty && docNumber.isEmpty) return;

    final db = widget.ref.read(firestorePathsProvider);
    final adminEmail = await _getAdminEmail() ?? 'admin';

    final newIdEntry = <String, dynamic>{
      'type': docType,
      'number': docNumber,
      'verifiedBy': adminEmail,
      'verifiedAt': DateTime.now().toIso8601String(),
      'source': 'registration',
    };
    _verifiedIds.add(newIdEntry);

    await db.operators.doc(widget.operator['id']).update({
      'idStatus': 'verified',
      'idVerifiedAt': FieldValue.serverTimestamp(),
      'idVerifiedBy': adminEmail,
      'verifiedIds': _verifiedIds,
    });

    setState(() {
      _idStatus = 'verified';
      _kycSuccessMessage = 'Registration ID merged to verified list.';
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _kycSuccessMessage = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final op = widget.operator;
    final facePhoto = op['facePhoto'] as String? ?? '';
    final isActive = op['isActive'] == true;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.rs)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 32),
      child: SizedBox(
        width: 1000,
        height: MediaQuery.of(context).size.height * 0.88,
        child: Column(
          children: [
            // Profile header
            Container(
              padding: const EdgeInsets.fromLTRB(28, 24, 20, 20),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  _buildProfileAvatar(facePhoto, op['name'] as String? ?? '', scheme),
                  SizedBox(width: 20.rs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(op['name'] ?? '', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        SizedBox(height: 8.rs),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isActive ? Colors.green.withValues(alpha: 0.1) : scheme.errorContainer,
                                borderRadius: BorderRadius.circular(12.rs),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(width: 6, height: 6, decoration: BoxDecoration(color: isActive ? Colors.green : scheme.error, shape: BoxShape.circle)),
                                  SizedBox(width: 6.rs),
                                  Text(isActive ? 'Active' : 'Inactive', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isActive ? Colors.green.shade700 : scheme.error)),
                                ],
                              ),
                            ),
                            SizedBox(width: 8.rs),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(12.rs),
                              ),
                              child: Text(op['role'] ?? 'operator', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant)),
                            ),
                            if (op['shiftRestricted'] == true) ...[
                              SizedBox(width: 8.rs),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12.rs),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.schedule_rounded, size: 11, color: Colors.deepPurple.shade400),
                                    SizedBox(width: 4.rs),
                                    Text('Shift Restricted', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.deepPurple.shade400)),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, size: 20, color: scheme.onSurfaceVariant),
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.surfaceContainerHigh,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(28.rs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left column — profile info & identity
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionCard(
                            title: 'Contact',
                            icon: Icons.phone_rounded,
                            scheme: scheme,
                            text: text,
                            child: _buildContactSection(scheme, text),
                          ),
                          if ((op['address'] as String? ?? '').isNotEmpty || (op['registrationAddress'] as String? ?? '').isNotEmpty || _verifiedIds.any((id) => (id['address'] as String? ?? '').isNotEmpty)) ...[
                            SizedBox(height: 14.rs),
                            _sectionCard(
                              title: 'Address',
                              icon: Icons.location_on_rounded,
                              scheme: scheme,
                              text: text,
                              child: _buildAddressSection(scheme, text, op),
                            ),
                          ],
                          SizedBox(height: 14.rs),
                          _sectionCard(
                            title: 'Identity & Verification',
                            icon: Icons.verified_user_rounded,
                            scheme: scheme,
                            text: text,
                            child: _buildKycSection(scheme, text, op),
                          ),
                          SizedBox(height: 14.rs),
                          _sectionCard(
                            title: 'Activity',
                            icon: Icons.insights_rounded,
                            scheme: scheme,
                            text: text,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _metaRow(Icons.access_time_rounded, 'Last login', _formatTimestamp(op['lastLoginAt'], widget.ref.read(timeFormatProvider)), scheme, text),
                                SizedBox(height: 6.rs),
                                _metaRow(Icons.numbers_rounded, 'Total logins', '${op['loginCount'] ?? 0}', scheme, text),
                                SizedBox(height: 6.rs),
                                _metaRow(Icons.calendar_today_rounded, 'Created', _formatTimestamp(op['createdAt'], widget.ref.read(timeFormatProvider)), scheme, text),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(width: 24.rs),

                    // Right column — access, security & scheduling
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionCard(
                            title: 'Security',
                            icon: Icons.lock_rounded,
                            scheme: scheme,
                            text: text,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(child: Text('Force password change on next login', style: text.bodySmall)),
                                    Switch(value: _mustChangePassword, onChanged: (v) { setState(() => _mustChangePassword = v); _saveField({'mustChangePassword': v}); }),
                                  ],
                                ),
                                SizedBox(height: 12.rs),
                                _metaRow(Icons.key_rounded, 'Password changed', _formatTimestamp(op['passwordLastChanged'], widget.ref.read(timeFormatProvider)), scheme, text),
                                SizedBox(height: 6.rs),
                                _metaRow(Icons.login_rounded, 'First login', (op['loginCount'] != null && (op['loginCount'] as int) > 0) ? 'Completed' : 'Not yet', scheme, text),
                                SizedBox(height: 14.rs),
                                Divider(color: scheme.outlineVariant.withValues(alpha: 0.2)),
                                SizedBox(height: 10.rs),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Icon(Icons.pin_rounded, size: 14, color: scheme.onSurfaceVariant),
                                          SizedBox(width: 8.rs),
                                          Text('Verification PIN', style: text.bodySmall),
                                        ],
                                      ),
                                    ),
                                    if (_hasPinSet)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(4.rs),
                                        ),
                                        child: Text('Set', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.green.shade700)),
                                      )
                                    else
                                      Text('Not set', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
                                  ],
                                ),
                                SizedBox(height: 8.rs),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _settingPin ? null : () => _showSetPinDialog(context, op, scheme),
                                    icon: Icon(_hasPinSet ? Icons.refresh_rounded : Icons.add_rounded, size: 14),
                                    label: Text(_hasPinSet ? 'Reset PIN' : 'Set PIN', style: const TextStyle(fontSize: 11)),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
                                    ),
                                  ),
                                ),
                                if (_pinError != null) ...[
                                  SizedBox(height: 6.rs),
                                  Text(_pinError!, style: TextStyle(fontSize: 10, color: scheme.error)),
                                ],
                              ],
                            ),
                          ),
                          SizedBox(height: 14.rs),
                          _sectionCard(
                            title: 'Screen Access',
                            icon: Icons.visibility_rounded,
                            scheme: scheme,
                            text: text,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(child: Text('Customers', style: text.bodySmall)),
                                    Switch(value: _canViewCustomers, onChanged: (v) { setState(() => _canViewCustomers = v); _saveField({'canViewCustomers': v}); }),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(child: Text('Weighments', style: text.bodySmall)),
                                    Switch(value: _canViewWeighments, onChanged: (v) { setState(() => _canViewWeighments = v); _saveField({'canViewWeighments': v}); }),
                                  ],
                                ),
                                if (_canViewWeighments) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(left: 16),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(child: Text('Only own weighments', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
                                        Switch(value: _ownWeighmentsOnly, onChanged: (v) { setState(() => _ownWeighmentsOnly = v); _saveField({'ownWeighmentsOnly': v}); }),
                                      ],
                                    ),
                                  ),
                                ],
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(child: Text('Reports', style: text.bodySmall)),
                                    Switch(value: _canViewReports, onChanged: (v) { setState(() => _canViewReports = v); _saveField({'canViewReports': v}); }),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 14.rs),
                          _sectionCard(
                            title: 'Site Access',
                            icon: Icons.location_on_rounded,
                            scheme: scheme,
                            text: text,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _editScopeChip('all', 'All Sites', Icons.public_rounded, scheme),
                                    SizedBox(width: 8.rs),
                                    _editScopeChip('specific', 'Specific Sites', Icons.location_on_rounded, scheme),
                                  ],
                                ),
                                if (_siteScope == 'specific' && _allSites.isNotEmpty) ...[
                                  SizedBox(height: 10.rs),
                                  Container(
                                    constraints: const BoxConstraints(maxHeight: 100),
                                    child: SingleChildScrollView(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: _allSites.map((site) {
                                          final selected = _selectedSites.contains(site['id']);
                                          return GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                if (selected) {
                                                  if (_selectedSites.length <= 1) return;
                                                  _selectedSites.remove(site['id']);
                                                } else {
                                                  _selectedSites.add(site['id']!);
                                                }
                                              });
                                              _saveField({'allowedSites': _selectedSites.toList()});
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 4),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                                    size: 16,
                                                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                                                  ),
                                                  SizedBox(width: 8.rs),
                                                  Text(site['name']!, style: TextStyle(fontSize: 12, color: scheme.onSurface)),
                                                ],
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          SizedBox(height: 14.rs),
                          _sectionCard(
                            title: 'Shift Schedule',
                            icon: Icons.schedule_rounded,
                            scheme: scheme,
                            text: text,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_shiftRestricted ? 'Restricted to schedule' : 'No restriction (any time)', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                                    Switch(
                                      value: _shiftRestricted,
                                      onChanged: (v) {
                                        setState(() => _shiftRestricted = v);
                                        final data = <String, dynamic>{'shiftRestricted': v};
                                        if (v) {
                                          data['shiftStart'] = _formatTimeOfDay(_shiftStart);
                                          data['shiftEnd'] = _formatTimeOfDay(_shiftEnd);
                                          data['shiftDays'] = _shiftDays;
                                        }
                                        _saveField(data);
                                      },
                                    ),
                                  ],
                                ),
                                if (_shiftRestricted) ...[
                                  SizedBox(height: 12.rs),
                                  Row(
                                    children: [
                                      Expanded(child: _timePickerTile('Start', _shiftStart, () => _pickTime(isStart: true), scheme, text)),
                                      SizedBox(width: 14.rs),
                                      Expanded(child: _timePickerTile('End', _shiftEnd, () => _pickTime(isStart: false), scheme, text)),
                                    ],
                                  ),
                                  SizedBox(height: 14.rs),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: _allDays.map((day) {
                                      final selected = _shiftDays.contains(day);
                                      return GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            if (selected) { _shiftDays.remove(day); } else { _shiftDays.add(day); }
                                          });
                                          _saveField({'shiftDays': _shiftDays});
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: selected ? scheme.primary : Colors.transparent,
                                            borderRadius: BorderRadius.circular(6.rs),
                                            border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant),
                                          ),
                                          child: Text(day, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? scheme.onPrimary : scheme.onSurfaceVariant)),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
              ),
              child: Row(
                children: [
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
                    ),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileAvatar(String facePhoto, String name, ColorScheme scheme) {
    final file = facePhoto.isNotEmpty ? File(facePhoto) : null;
    final hasPhoto = file != null && file.existsSync();

    return GestureDetector(
      onTap: hasPhoto ? () => _showEnlargedPhoto(file, name) : null,
      child: MouseRegion(
        cursor: hasPhoto ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: scheme.primary.withValues(alpha: 0.2), width: 2),
          ),
          child: ClipOval(
            child: hasPhoto
                ? Image.file(file, fit: BoxFit.cover, width: 64, height: 64)
                : Container(
                    color: scheme.secondaryContainer,
                    alignment: Alignment.center,
                    child: Text(
                      name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'U',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: scheme.onSecondaryContainer),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  void _showEnlargedPhoto(File file, String name) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.all(40.rs),
        child: Stack(
          alignment: Alignment.center,
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(color: Colors.transparent, width: double.infinity, height: double.infinity),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 480, maxHeight: 480),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16.rs),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16.rs),
                    child: Image.file(file, fit: BoxFit.contain),
                  ),
                ),
                SizedBox(height: 16.rs),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(8.rs),
                  ),
                  child: Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                ),
              ],
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: Container(
                  padding: EdgeInsets.all(6.rs),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close_rounded, size: 18, color: scheme.onSurface),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required IconData icon, required ColorScheme scheme, required TextTheme text, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18.rs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: scheme.primary),
              SizedBox(width: 8.rs),
              Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
          SizedBox(height: 14.rs),
          child,
        ],
      ),
    );
  }

  Widget _fieldLabel(String label, TextTheme text) {
    return Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600));
  }

  Widget _metaRow(IconData icon, String label, String value, ColorScheme scheme, TextTheme text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
        SizedBox(width: 8.rs),
        Text('$label: ', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        Expanded(child: Text(value, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
      ],
    );
  }


  Widget _timePickerTile(String label, TimeOfDay time, VoidCallback onTap, ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: 6.rs),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8.rs),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8.rs),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                Expanded(child: Text(_formatTimeOfDay(time), style: text.bodySmall)),
                Icon(Icons.access_time_rounded, size: 16, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ],
    );
  }

}

// ─── Face Enrollment Widget ─────────────────────────────────────────────────

class _FaceEnrollmentWidget extends StatefulWidget {
  final WidgetRef ref;
  final String operatorId;
  final String? existingFacePhoto;
  final Map<String, dynamic>? existingFaceEnrollment;
  final VoidCallback? onEnrollmentComplete;

  const _FaceEnrollmentWidget({
    required this.ref,
    required this.operatorId,
    this.existingFacePhoto,
    this.existingFaceEnrollment,
    this.onEnrollmentComplete,
  });

  @override
  State<_FaceEnrollmentWidget> createState() => _FaceEnrollmentWidgetState();
}

enum _ReEnrollMode { none, training, fullReset }
enum _OtpStage { notStarted, operatorSent, adminSent, adminVerified }

class _FaceEnrollmentWidgetState extends State<_FaceEnrollmentWidget> {
  static const _channel = MethodChannel('com.weighbridge/webcam');
  static const _requiredFrames = 5;

  bool _cameraReady = false;
  bool _cameraError = false;
  String? _errorMessage;
  Uint8List? _currentFrame;
  Timer? _frameTimer;

  // Pre-capture question
  bool? _wearsSpecs;
  bool _started = false;

  // Enrollment state
  final List<Uint8List> _capturedFrames = [];
  bool _capturing = false;
  bool _autoCapturing = false;
  Timer? _autoCaptureTimer;
  int _autoCountdown = 3;
  bool _enrolling = false;
  bool _enrolled = false;
  String? _enrollError;
  bool _saving = false;

  // Dual-phase capture
  bool _specsPhase = true;
  bool _specsPhaseComplete = false;
  bool _transitionAcknowledged = false;
  final List<Uint8List> _specsFrames = [];
  final List<Uint8List> _noSpecsFrames = [];

  // Camera selection
  List<Map<String, String>> _cameras = [];
  String? _selectedCameraId;

  // Re-enrollment flow
  _ReEnrollMode _reEnrollMode = _ReEnrollMode.none;
  _OtpStage _otpStage = _OtpStage.notStarted;
  bool _otpSending = false;
  bool _otpVerifying = false;
  String? _otpError;
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(6, (_) => FocusNode());
  bool _warningAccepted = false;

  bool get _hasExistingEnrollment =>
      widget.existingFaceEnrollment != null &&
      widget.existingFaceEnrollment!['enrolled'] == true;

  String get _otpValue => _otpControllers.map((c) => c.text).join();

  @override
  void initState() {
    super.initState();
    _enrolled = _hasExistingEnrollment ||
        (widget.existingFacePhoto != null && widget.existingFacePhoto!.isNotEmpty);
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _autoCaptureTimer?.cancel();
    for (final c in _otpControllers) { c.dispose(); }
    for (final f in _otpFocusNodes) { f.dispose(); }
    _stopCamera();
    super.dispose();
  }

  Future<void> _loadCameras() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('listCameras');
      if (result != null && result.isNotEmpty) {
        final list = result.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return {'id': m['id'] as String, 'name': m['name'] as String};
        }).toList();
        setState(() {
          _cameras = list;
          _selectedCameraId ??= list.first['id'];
        });
      }
    } catch (_) {}
  }

  Future<void> _initCamera() async {
    try {
      final args = _selectedCameraId != null ? {'deviceId': _selectedCameraId} : null;
      final result = await _channel.invokeMethod<bool>('startCamera', args);
      if (result == true) {
        setState(() => _cameraReady = true);
        _startFrameCapture();
      } else {
        setState(() { _cameraError = true; _errorMessage = 'Could not start camera.'; });
      }
    } on PlatformException catch (e) {
      setState(() { _cameraError = true; _errorMessage = e.message ?? 'Camera not available.'; });
    }
  }

  void _startFrameCapture() {
    _frameTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      if (!_cameraReady || !mounted) return;
      try {
        final frame = await _channel.invokeMethod<Uint8List>('captureFrame');
        if (frame != null && mounted) {
          setState(() => _currentFrame = frame);
        }
      } catch (_) {}
    });
  }

  Future<void> _stopCamera() async {
    try {
      await _channel.invokeMethod('stopCamera');
    } catch (_) {}
  }

  void _answerSpecs(bool wears) async {
    setState(() { _wearsSpecs = wears; _started = true; });
    await _loadCameras();
    _initCamera();
  }

  void _startAutoCapture() {
    if (_autoCapturing) return;
    setState(() { _autoCapturing = true; _autoCountdown = 3; });

    _autoCaptureTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_autoCountdown > 1) {
        setState(() => _autoCountdown--);
      } else {
        timer.cancel();
        _beginSequentialCapture();
      }
    });
  }

  void _beginSequentialCapture() {
    setState(() => _autoCountdown = 0);
    int captured = 0;

    _autoCaptureTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_currentFrame == null) return;

      setState(() {
        _capturing = true;
        _capturedFrames.add(_currentFrame!);
        captured++;
      });

      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _capturing = false);
      });

      if (captured >= _requiredFrames) {
        timer.cancel();
        setState(() => _autoCapturing = false);
        _onPhaseComplete();
      }
    });
  }

  void _onPhaseComplete() {
    if (_wearsSpecs == true && _specsPhase && !_specsPhaseComplete) {
      _specsFrames.addAll(_capturedFrames);
      _validatePhase(_specsFrames, onSuccess: () {
        setState(() {
          _specsPhaseComplete = true;
          _capturedFrames.clear();
          _specsPhase = false;
        });
      });
    } else if (_wearsSpecs == true && !_specsPhase) {
      _noSpecsFrames.addAll(_capturedFrames);
      _validatePhase(_noSpecsFrames, referenceFrames: _specsFrames, onSuccess: () {
        _enrollFace();
      });
    } else {
      _validatePhase(_capturedFrames, onSuccess: () {
        _enrollFace();
      });
    }
  }

  Future<void> _validatePhase(List<Uint8List> frames, {List<Uint8List>? referenceFrames, required VoidCallback onSuccess}) async {
    setState(() { _enrolling = true; _enrollError = null; });
    try {
      final images = frames.map((f) => base64Encode(f)).toList();
      final payload = <String, dynamic>{'images': images};
      if (referenceFrames != null && referenceFrames.isNotEmpty) {
        payload['referenceImages'] = referenceFrames.map((f) => base64Encode(f)).toList();
      }
      final response = await FirebaseFunctions.instance
          .httpsCallable('validateFaceConsistency', options: HttpsCallableOptions(timeout: const Duration(seconds: 120)))
          .call(payload);

      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['success'] == true) {
        setState(() => _enrolling = false);
        onSuccess();
      } else {
        setState(() {
          _enrolling = false;
          _enrollError = data['message'] as String? ?? 'Consistency check failed. Please retake.';
          _capturedFrames.clear();
          if (_wearsSpecs == true && !_specsPhase) {
            _noSpecsFrames.clear();
          } else if (_wearsSpecs == true && _specsPhase) {
            _specsFrames.clear();
          }
        });
      }
    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _enrolling = false;
        _enrollError = e.message?.isNotEmpty == true ? e.message! : 'Validation failed (${e.code}). Please try again.';
        _capturedFrames.clear();
        if (_wearsSpecs == true && !_specsPhase) {
          _noSpecsFrames.clear();
        }
      });
    } catch (e) {
      setState(() {
        _enrolling = false;
        _enrollError = 'Failed to validate faces. Try again.';
        _capturedFrames.clear();
        if (_wearsSpecs == true && !_specsPhase) {
          _noSpecsFrames.clear();
        }
      });
    }
  }

  void _resetCapture({bool fullReset = true}) {
    _autoCaptureTimer?.cancel();
    setState(() {
      _enrollError = null;
      _capturedFrames.clear();
      _autoCapturing = false;
      _autoCountdown = 3;
      if (fullReset) {
        _specsFrames.clear();
        _noSpecsFrames.clear();
        _specsPhaseComplete = false;
        _transitionAcknowledged = false;
        _specsPhase = true;
      } else {
        _noSpecsFrames.clear();
      }
    });
  }

  Future<String?> _getAdminEmail() async {
    final authEmail = FirebaseAuth.instance.currentUser?.email;
    if (authEmail != null && authEmail.isNotEmpty) return authEmail;
    return await LocalCacheService.getCachedCurrentUserEmail();
  }

  Future<String?> _getOperatorEmail() async {
    final paths = widget.ref.read(firestorePathsProvider);
    final opDoc = await paths.operators.doc(widget.operatorId).get();
    return opDoc.data()?['email'] as String?;
  }

  Future<void> _sendOtp(String email) async {
    setState(() { _otpSending = true; _otpError = null; });
    try {
      await FirebaseFunctions.instance.httpsCallable('sendEmailOTP').call({'email': email});
      setState(() => _otpSending = false);
    } catch (e) {
      setState(() { _otpSending = false; _otpError = 'Failed to send OTP.'; });
    }
  }

  Future<bool> _verifyOtp(String email) async {
    final otp = _otpValue;
    if (otp.length != 6) {
      setState(() => _otpError = 'Enter all 6 digits.');
      return false;
    }
    setState(() { _otpVerifying = true; _otpError = null; });
    try {
      await FirebaseFunctions.instance.httpsCallable('verifyEmailOTP').call({'email': email, 'otp': otp});
      setState(() => _otpVerifying = false);
      return true;
    } on FirebaseFunctionsException catch (e) {
      setState(() { _otpVerifying = false; _otpError = e.message ?? 'Invalid OTP.'; });
      return false;
    } catch (e) {
      setState(() { _otpVerifying = false; _otpError = 'Verification failed.'; });
      return false;
    }
  }

  void _clearOtpFields() {
    for (final c in _otpControllers) { c.clear(); }
  }

  Future<void> _startTrainingOtp() async {
    final adminEmail = await _getAdminEmail();
    if (adminEmail == null || adminEmail.isEmpty) {
      setState(() => _otpError = 'Admin email not available.');
      return;
    }
    await _sendOtp(adminEmail);
    if (_otpError == null) {
      setState(() => _otpStage = _OtpStage.adminSent);
    }
  }

  Future<void> _verifyTrainingAdminOtp() async {
    final adminEmail = await _getAdminEmail();
    if (adminEmail == null) return;
    final verified = await _verifyOtp(adminEmail);
    if (verified) {
      _clearOtpFields();
      setState(() { _otpStage = _OtpStage.adminVerified; _started = true; });
    }
  }

  Future<void> _startFullResetOtp() async {
    final opEmail = await _getOperatorEmail();
    if (opEmail == null || opEmail.isEmpty) {
      setState(() => _otpError = 'Operator email not available.');
      return;
    }
    await _sendOtp(opEmail);
    if (_otpError == null) {
      setState(() => _otpStage = _OtpStage.operatorSent);
    }
  }

  Future<void> _verifyOperatorOtp() async {
    final opEmail = await _getOperatorEmail();
    if (opEmail == null) return;
    final verified = await _verifyOtp(opEmail);
    if (verified) {
      _clearOtpFields();
      final adminEmail = await _getAdminEmail();
      if (adminEmail == null || adminEmail.isEmpty) {
        setState(() => _otpError = 'Admin email not available.');
        return;
      }
      await _sendOtp(adminEmail);
      if (_otpError == null) {
        setState(() => _otpStage = _OtpStage.adminSent);
      }
    }
  }

  Future<void> _verifyFullResetAdminOtp() async {
    final adminEmail = await _getAdminEmail();
    if (adminEmail == null) return;
    final verified = await _verifyOtp(adminEmail);
    if (verified) {
      _clearOtpFields();
      setState(() => _otpStage = _OtpStage.adminVerified);
    }
  }

  Future<void> _enrollFace() async {
    final List<Uint8List> allFrames;
    if (_wearsSpecs == true) {
      allFrames = [..._specsFrames, ..._noSpecsFrames];
    } else {
      allFrames = List.from(_capturedFrames);
    }
    final images = allFrames.map((f) => base64Encode(f)).toList();

    setState(() => _saving = true);
    try {
      final paths = widget.ref.read(firestorePathsProvider);
      final companyId = paths.context.companyId;
      final opDoc = await paths.operators.doc(widget.operatorId).get();
      final operatorEmail = opDoc.data()?['email'] as String? ?? '';

      final String functionName = _reEnrollMode == _ReEnrollMode.training
          ? 'trainOperatorFace'
          : 'enrollOperatorFace';

      final response = await FirebaseFunctions.instance
          .httpsCallable(functionName, options: HttpsCallableOptions(timeout: const Duration(seconds: 120)))
          .call({'images': images, 'companyId': companyId, 'operatorEmail': operatorEmail});

      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['success'] == true) {
        // Generate local AdaFace embedding via sidecar, then refresh parent UI
        _generateSidecarEmbedding(allFrames, widget.operatorId, operatorEmail, opDoc.data()?['name'] as String? ?? '').then((_) {
          widget.onEnrollmentComplete?.call();
        });

        _frameTimer?.cancel();
        _autoCaptureTimer?.cancel();
        await _stopCamera();
        if (mounted) {
          final wasTraining = _reEnrollMode == _ReEnrollMode.training;
          setState(() {
            _enrolled = true;
            _saving = false;
            _started = false;
            _wearsSpecs = null;
            _cameraReady = false;
            _currentFrame = null;
            _capturedFrames.clear();
            _specsFrames.clear();
            _noSpecsFrames.clear();
            _specsPhaseComplete = false;
            _transitionAcknowledged = false;
            _specsPhase = true;
            _autoCapturing = false;
            _enrolling = false;
            _enrollError = null;
            _reEnrollMode = _ReEnrollMode.none;
            _otpStage = _OtpStage.notStarted;
            _warningAccepted = false;
          });
          AppError.success(context, wasTraining
              ? 'Training data added successfully'
              : 'Face enrolled successfully');
          widget.onEnrollmentComplete?.call();
        }
      } else {
        setState(() {
          _saving = false;
          _enrollError = data['message'] as String? ?? 'Enrollment failed. Please retry.';
          _capturedFrames.clear();
        });
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() { _saving = false; _enrollError = e.message ?? 'Enrollment failed.'; });
    } catch (e) {
      if (mounted) setState(() { _saving = false; _enrollError = 'Enrollment failed: $e'; });
    }
  }

  /// Generate embedding via local sidecar and store in Firestore for fast local identification.
  Future<void> _generateSidecarEmbedding(List<Uint8List> frames, String operatorId, String email, String name) async {
    try {
      final sidecar = widget.ref.read(sidecarClientProvider);
      final result = await sidecar.enrollFromImages(frames);
      if (result != null && result.embedding.isNotEmpty) {
        final paths = widget.ref.read(firestorePathsProvider);
        await paths.operators.doc(operatorId).update({
          'faceEmbedding': result.embedding,
          'faceModelVersion': 'arcface_glintr100',
          'faceEnrollment': {
            'enrolled': true,
            'validFrameCount': result.facesUsed,
            'totalFrames': result.totalImages,
            'averageConfidence': result.avgQuality,
            'enrolledAt': FieldValue.serverTimestamp(),
            'model': 'arcface_glintr100',
          },
        });
        await sidecar.syncEnrollments(operators: [{
          'operator_id': operatorId,
          'email': email,
          'name': name,
          'embedding': result.embedding,
          'is_active': true,
        }]);
      }
    } catch (e) {
      debugPrint('[SidecarEnroll] Failed: $e');
    }
  }

  void _cancelFlow() {
    _frameTimer?.cancel();
    _autoCaptureTimer?.cancel();
    _stopCamera();
    setState(() {
      _started = false;
      _wearsSpecs = null;
      _cameraReady = false;
      _cameraError = false;
      _currentFrame = null;
      _capturedFrames.clear();
      _specsFrames.clear();
      _noSpecsFrames.clear();
      _specsPhaseComplete = false;
      _transitionAcknowledged = false;
      _specsPhase = true;
      _autoCapturing = false;
      _enrolling = false;
      _enrollError = null;
      _reEnrollMode = _ReEnrollMode.none;
      _otpStage = _OtpStage.notStarted;
      _otpError = null;
      _warningAccepted = false;
    });
    _clearOtpFields();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // Idle state
    if (!_started && _reEnrollMode == _ReEnrollMode.none) {
      if (_enrolled && _hasExistingEnrollment) {
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _started = true),
            icon: const Icon(Icons.refresh_rounded, size: 14),
            label: const Text('Re-enroll Face', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
            ),
          ),
        );
      }
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => setState(() => _started = true),
          icon: const Icon(Icons.videocam_rounded, size: 14),
          label: const Text('Start Face Enrollment', style: TextStyle(fontSize: 11)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
          ),
        ),
      );
    }

    // Re-enrollment mode selection (only when existing data)
    if (_started && _hasExistingEnrollment && _reEnrollMode == _ReEnrollMode.none) {
      return _buildModeChoice(scheme, text);
    }

    // OTP verification flow for training
    if (_reEnrollMode == _ReEnrollMode.training && _otpStage != _OtpStage.adminVerified) {
      return _buildTrainingOtp(scheme, text);
    }

    // OTP verification flow for full reset
    if (_reEnrollMode == _ReEnrollMode.fullReset && _otpStage != _OtpStage.adminVerified) {
      return _buildFullResetOtp(scheme, text);
    }

    // Warning for full reset
    if (_reEnrollMode == _ReEnrollMode.fullReset && !_warningAccepted) {
      return _buildResetWarning(scheme, text);
    }

    // Specs question
    if (_wearsSpecs == null) {
      return _buildSpecsQuestion(scheme, text);
    }

    // Camera error
    if (_cameraError) {
      return _buildErrorView(scheme, text);
    }

    // Camera view with auto-capture
    return _buildCameraView(scheme, text);
  }

  Widget _buildModeChoice(ColorScheme scheme, TextTheme text) {
    return Container(
      padding: EdgeInsets.all(14.rs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.face_retouching_natural_rounded, size: 24, color: scheme.primary),
          SizedBox(height: 8.rs),
          Text('Face data already exists', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: 4.rs),
          Text(
            'Choose how to update face enrollment:',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 14.rs),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _reEnrollMode = _ReEnrollMode.training),
              icon: Icon(Icons.model_training_rounded, size: 14, color: scheme.primary),
              label: const Text('Add Training Data', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 3, bottom: 10),
            child: Text(
              'Adds more face samples to improve recognition. Requires admin verification.',
              style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _reEnrollMode = _ReEnrollMode.fullReset),
              icon: Icon(Icons.restart_alt_rounded, size: 14, color: scheme.error),
              label: Text('Complete Re-enrollment', style: TextStyle(fontSize: 11, color: scheme.error)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                side: BorderSide(color: scheme.error.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 3, bottom: 6),
            child: Text(
              'Replaces all existing data. Requires operator + admin verification.',
              style: TextStyle(fontSize: 9, color: scheme.error.withValues(alpha: 0.7)),
            ),
          ),
          TextButton(
            onPressed: _cancelFlow,
            child: Text('Cancel', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _buildTrainingOtp(ColorScheme scheme, TextTheme text) {
    return Container(
      padding: EdgeInsets.all(14.rs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.admin_panel_settings_rounded, size: 22, color: scheme.primary),
          SizedBox(height: 8.rs),
          Text('Admin Verification', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: 4.rs),
          Text(
            'An OTP will be sent to admin email to authorize adding training data.',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 12.rs),
          if (_otpStage == _OtpStage.notStarted) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _otpSending ? null : _startTrainingOtp,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs))),
                child: _otpSending
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Send OTP to Admin', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
          if (_otpStage == _OtpStage.adminSent) ...[
            _buildOtpInput(scheme),
            SizedBox(height: 10.rs),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _otpVerifying ? null : _verifyTrainingAdminOtp,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs))),
                child: _otpVerifying
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Verify', style: TextStyle(fontSize: 11)),
              ),
            ),
            SizedBox(height: 4.rs),
            TextButton(
              onPressed: _otpSending ? null : _startTrainingOtp,
              child: Text('Resend Code', style: TextStyle(fontSize: 10, color: scheme.primary)),
            ),
          ],
          if (_otpError != null) ...[
            SizedBox(height: 6.rs),
            Text(_otpError!, style: TextStyle(fontSize: 10, color: scheme.error)),
          ],
          SizedBox(height: 6.rs),
          TextButton(
            onPressed: _cancelFlow,
            child: Text('Cancel', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _buildFullResetOtp(ColorScheme scheme, TextTheme text) {
    final isOperatorStage = _otpStage == _OtpStage.notStarted || _otpStage == _OtpStage.operatorSent;
    final stageLabel = isOperatorStage ? 'Step 1: Operator Verification' : 'Step 2: Admin Verification';
    final stageDesc = isOperatorStage
        ? 'OTP will be sent to operator\'s email to confirm identity.'
        : 'OTP will be sent to admin email to authorize re-enrollment.';

    return Container(
      padding: EdgeInsets.all(14.rs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10.rs),
        border: Border.all(color: scheme.error.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 20, height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (!isOperatorStage ? AppTheme.successColor : scheme.primary).withValues(alpha: 0.15),
                ),
                child: Center(child: Text('1', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: !isOperatorStage ? AppTheme.successColor : scheme.primary))),
              ),
              Container(width: 24, height: 2, color: scheme.outlineVariant.withValues(alpha: 0.4)),
              Container(
                width: 20, height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (!isOperatorStage ? scheme.primary : scheme.surfaceContainerHigh).withValues(alpha: isOperatorStage ? 1 : 0.15),
                ),
                child: Center(child: Text('2', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: !isOperatorStage ? scheme.primary : scheme.onSurfaceVariant))),
              ),
            ],
          ),
          SizedBox(height: 10.rs),
          Text(stageLabel, style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: 4.rs),
          Text(stageDesc, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
          SizedBox(height: 12.rs),
          if (_otpStage == _OtpStage.notStarted) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _otpSending ? null : _startFullResetOtp,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs))),
                child: _otpSending
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Send OTP to Operator', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
          if (_otpStage == _OtpStage.operatorSent) ...[
            _buildOtpInput(scheme),
            SizedBox(height: 10.rs),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _otpVerifying ? null : _verifyOperatorOtp,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs))),
                child: _otpVerifying
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Verify Operator', style: TextStyle(fontSize: 11)),
              ),
            ),
            SizedBox(height: 4.rs),
            TextButton(
              onPressed: _otpSending ? null : _startFullResetOtp,
              child: Text('Resend Code', style: TextStyle(fontSize: 10, color: scheme.primary)),
            ),
          ],
          if (_otpStage == _OtpStage.adminSent) ...[
            _buildOtpInput(scheme),
            SizedBox(height: 10.rs),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _otpVerifying ? null : _verifyFullResetAdminOtp,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs))),
                child: _otpVerifying
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Verify Admin', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
          if (_otpError != null) ...[
            SizedBox(height: 6.rs),
            Text(_otpError!, style: TextStyle(fontSize: 10, color: scheme.error)),
          ],
          SizedBox(height: 6.rs),
          TextButton(
            onPressed: _cancelFlow,
            child: Text('Cancel', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _buildResetWarning(ColorScheme scheme, TextTheme text) {
    return Container(
      padding: EdgeInsets.all(14.rs),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10.rs),
        border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.warning_amber_rounded, size: 28, color: scheme.error),
          SizedBox(height: 8.rs),
          Text('Complete Re-enrollment', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: scheme.error)),
          SizedBox(height: 8.rs),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(10.rs),
            decoration: BoxDecoration(
              color: scheme.error.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8.rs),
              border: Border.all(color: scheme.error.withValues(alpha: 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _warningRow(Icons.delete_forever_rounded, 'All existing face data will be permanently deleted', scheme),
                SizedBox(height: 4.rs),
                _warningRow(Icons.history_rounded, 'Previous training sessions will be lost', scheme),
                SizedBox(height: 4.rs),
                _warningRow(Icons.face_retouching_off_rounded, 'Face login will fail until new enrollment completes', scheme),
              ],
            ),
          ),
          SizedBox(height: 14.rs),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => setState(() => _warningAccepted = true),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
              ),
              child: const Text('I understand, proceed', style: TextStyle(fontSize: 11)),
            ),
          ),
          SizedBox(height: 6.rs),
          TextButton(
            onPressed: _cancelFlow,
            child: Text('Cancel', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _warningRow(IconData icon, String msg, ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 12, color: scheme.error.withValues(alpha: 0.8)),
        SizedBox(width: 6.rs),
        Expanded(child: Text(msg, style: TextStyle(fontSize: 10, color: scheme.onSurface.withValues(alpha: 0.8)))),
      ],
    );
  }

  Widget _buildOtpInput(ColorScheme scheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) => Container(
        width: 32, height: 38,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        child: TextField(
          controller: _otpControllers[i],
          focusNode: _otpFocusNodes[i],
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 1,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.rs)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6.rs),
              borderSide: BorderSide(color: scheme.primary, width: 2),
            ),
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (val) {
            if (val.isNotEmpty && i < 5) {
              _otpFocusNodes[i + 1].requestFocus();
            } else if (val.isEmpty && i > 0) {
              _otpFocusNodes[i - 1].requestFocus();
            }
          },
        ),
      )),
    );
  }

  Widget _buildSpecsQuestion(ColorScheme scheme, TextTheme text) {
    return Container(
      padding: EdgeInsets.all(14.rs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.visibility_rounded, size: 24, color: scheme.primary),
          SizedBox(height: 8.rs),
          Text('Do you wear spectacles?', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: 4.rs),
          Text(
            'If yes, face will be captured both with and without glasses.',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 14.rs),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _answerSpecs(false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
                  ),
                  child: const Text('No', style: TextStyle(fontSize: 11)),
                ),
              ),
              SizedBox(width: 10.rs),
              Expanded(
                child: FilledButton(
                  onPressed: () => _answerSpecs(true),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
                  ),
                  child: const Text('Yes', style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
          SizedBox(height: 6.rs),
          TextButton(
            onPressed: _cancelFlow,
            child: Text('Cancel', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(ColorScheme scheme, TextTheme text) {
    return Container(
      padding: EdgeInsets.all(14.rs),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10.rs),
        border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.videocam_off_rounded, size: 24, color: scheme.error),
          SizedBox(height: 8.rs),
          Text(_errorMessage ?? 'Camera not available', style: TextStyle(fontSize: 11, color: scheme.error)),
          SizedBox(height: 10.rs),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancelFlow,
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs))),
                  child: const Text('Cancel', style: TextStyle(fontSize: 11)),
                ),
              ),
              SizedBox(width: 8.rs),
              Expanded(
                child: FilledButton(
                  onPressed: () { setState(() { _cameraError = false; _errorMessage = null; }); _initCamera(); },
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs))),
                  child: const Text('Retry', style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCameraView(ColorScheme scheme, TextTheme text) {
    final isDualPhase = _wearsSpecs == true;

    // Transition screen between phases
    if (isDualPhase && _specsPhaseComplete && !_transitionAcknowledged && _capturedFrames.isEmpty && !_enrolling) {
      return _buildPhaseTransition(scheme, text);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Phase label for dual-phase
        if (isDualPhase)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: (_specsPhase ? scheme.primaryContainer : scheme.tertiaryContainer).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8.rs),
              border: Border.all(color: (_specsPhase ? scheme.primary : scheme.tertiary).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  _specsPhase ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  size: 14,
                  color: _specsPhase ? scheme.primary : scheme.tertiary,
                ),
                SizedBox(width: 8.rs),
                Expanded(
                  child: Text(
                    _specsPhase ? 'Phase 1/2 — WITH glasses' : 'Phase 2/2 — WITHOUT glasses',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _specsPhase ? scheme.primary : scheme.tertiary),
                  ),
                ),
                if (_specsPhaseComplete)
                  Icon(Icons.check_circle_rounded, size: 13, color: AppTheme.successColor),
              ],
            ),
          ),

        // Camera selector
        if (_cameras.length > 1 && !_autoCapturing)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DropdownButtonFormField<String>(
              initialValue: _selectedCameraId,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.rs)),
                prefixIcon: const Icon(Icons.videocam_rounded, size: 14),
              ),
              items: _cameras.map((cam) => DropdownMenuItem(
                value: cam['id'],
                child: Text(cam['name']!, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
              )).toList(),
              onChanged: (id) {
                if (id == null || id == _selectedCameraId) return;
                setState(() { _selectedCameraId = id; _cameraReady = false; _currentFrame = null; });
                _frameTimer?.cancel();
                _stopCamera().then((_) => _initCamera());
              },
            ),
          ),

        // Camera preview
        Container(
          width: double.infinity,
          height: 200,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(10.rs),
            border: Border.all(
              color: _capturing ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.3),
              width: _capturing ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9.rs),
            child: _currentFrame != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(_currentFrame!, fit: BoxFit.cover, gaplessPlayback: true),
                      CustomPaint(painter: _FaceGuidePainter(detected: _cameraReady, scheme: scheme)),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary)),
                        SizedBox(height: 6.rs),
                        Text('Initializing camera...', style: TextStyle(color: Colors.white54, fontSize: 10)),
                      ],
                    ),
                  ),
          ),
        ),
        SizedBox(height: 10.rs),

        // Progress indicators (thumbnail slots)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_requiredFrames, (i) {
            final captured = i < _capturedFrames.length;
            return Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6.rs),
                border: Border.all(
                  color: captured ? AppTheme.successColor : scheme.outlineVariant.withValues(alpha: 0.4),
                  width: captured ? 2 : 1,
                ),
              ),
              child: captured
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(5.rs),
                      child: Image.memory(_capturedFrames[i], fit: BoxFit.cover),
                    )
                  : Center(child: Text('${i + 1}', style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)))),
            );
          }),
        ),
        SizedBox(height: 4.rs),
        Center(
          child: Text(
            '${_capturedFrames.length} of $_requiredFrames captured',
            style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ),
        ),
        SizedBox(height: 10.rs),

        // Action area
        if (_enrolling || _saving) ...[
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8.rs),
                Text(_saving ? 'Enrolling face...' : 'Validating...', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ] else if (_enrollError != null) ...[
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(8.rs),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8.rs),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 13, color: scheme.error),
                SizedBox(width: 6.rs),
                Expanded(child: Text(_enrollError!, style: TextStyle(fontSize: 10, color: scheme.error))),
              ],
            ),
          ),
          SizedBox(height: 8.rs),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _resetCapture(fullReset: !(_wearsSpecs == true && _specsPhaseComplete)),
              icon: const Icon(Icons.refresh_rounded, size: 13),
              label: const Text('Try Again', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 7), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs))),
            ),
          ),
        ] else if (_autoCapturing && _autoCountdown > 0) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8.rs),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
            ),
            child: Center(
              child: Text(
                'Starting in $_autoCountdown...',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.primary),
              ),
            ),
          ),
        ] else if (_autoCapturing) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.successColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8.rs),
              border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3)),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fiber_manual_record_rounded, size: 10, color: AppTheme.successColor),
                  SizedBox(width: 6.rs),
                  Text('Capturing... look at camera', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.successColor)),
                ],
              ),
            ),
          ),
        ] else ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: !_cameraReady ? null : _startAutoCapture,
              icon: const Icon(Icons.play_arrow_rounded, size: 16),
              label: Text(
                isDualPhase
                    ? (_specsPhase ? 'Capture with glasses' : 'Capture without glasses')
                    : 'Start capture',
                style: const TextStyle(fontSize: 11),
              ),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs))),
            ),
          ),
          SizedBox(height: 4.rs),
          Center(child: Text('5 photos auto-captured (1/sec)', style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)))),
        ],

        SizedBox(height: 8.rs),
        if (!_autoCapturing && !_enrolling && !_saving)
          Center(
            child: TextButton(
              onPressed: _cancelFlow,
              child: Text('Cancel', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            ),
          ),
      ],
    );
  }

  Widget _buildPhaseTransition(ColorScheme scheme, TextTheme text) {
    return Container(
      padding: EdgeInsets.all(16.rs),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10.rs),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(Icons.visibility_off_rounded, size: 28, color: scheme.tertiary),
          SizedBox(height: 10.rs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.successColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12.rs),
            ),
            child: Text('Phase 1 complete', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppTheme.successColor)),
          ),
          SizedBox(height: 10.rs),
          Text('Remove spectacles', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: 4.rs),
          Text(
            'Take off glasses before continuing.',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 14.rs),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => setState(() => _transitionAcknowledged = true),
              icon: const Icon(Icons.arrow_forward_rounded, size: 14),
              label: const Text('Glasses removed — Continue', style: TextStyle(fontSize: 11)),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs))),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaceGuidePainter extends CustomPainter {
  final bool detected;
  final ColorScheme scheme;

  _FaceGuidePainter({required this.detected, required this.scheme});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (detected ? Colors.green : Colors.white).withValues(alpha: 0.7)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final rx = size.width * 0.28;
    final ry = size.height * 0.38;
    final cornerLen = 20.0;

    canvas.drawLine(Offset(cx - rx, cy - ry), Offset(cx - rx + cornerLen, cy - ry), paint);
    canvas.drawLine(Offset(cx - rx, cy - ry), Offset(cx - rx, cy - ry + cornerLen), paint);
    canvas.drawLine(Offset(cx + rx, cy - ry), Offset(cx + rx - cornerLen, cy - ry), paint);
    canvas.drawLine(Offset(cx + rx, cy - ry), Offset(cx + rx, cy - ry + cornerLen), paint);
    canvas.drawLine(Offset(cx - rx, cy + ry), Offset(cx - rx + cornerLen, cy + ry), paint);
    canvas.drawLine(Offset(cx - rx, cy + ry), Offset(cx - rx, cy + ry - cornerLen), paint);
    canvas.drawLine(Offset(cx + rx, cy + ry), Offset(cx + rx - cornerLen, cy + ry), paint);
    canvas.drawLine(Offset(cx + rx, cy + ry), Offset(cx + rx, cy + ry - cornerLen), paint);
  }

  @override
  bool shouldRepaint(covariant _FaceGuidePainter oldDelegate) => oldDelegate.detected != detected;
}

class _IdDocImageView extends StatefulWidget {
  final String base64Data;
  final ColorScheme scheme;

  const _IdDocImageView({required this.base64Data, required this.scheme});

  @override
  State<_IdDocImageView> createState() => _IdDocImageViewState();
}

class _IdDocImageViewState extends State<_IdDocImageView> {
  List<Uint8List> _pages = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _processData();
  }

  Future<void> _processData() async {
    try {
      final bytes = base64Decode(widget.base64Data);

      if (_isPdf(bytes)) {
        await _convertPdfToImages(bytes);
      } else {
        setState(() {
          _pages = [bytes];
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load document image';
        _loading = false;
      });
    }
  }

  bool _isPdf(Uint8List bytes) {
    if (bytes.length < 5) return false;
    return bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46 &&
        bytes[4] == 0x2D;
  }

  Future<void> _convertPdfToImages(Uint8List pdfBytes) async {
    try {
      final doc = await PdfDocument.openData(pdfBytes);
      final pages = <Uint8List>[];
      for (int p = 1; p <= doc.pagesCount && p <= 4; p++) {
        final page = await doc.getPage(p);
        final pageImage = await page.render(width: page.width * 2, height: page.height * 2, format: PdfPageImageFormat.png);
        if (pageImage != null) pages.add(pageImage.bytes);
        await page.close();
      }
      await doc.close();
      if (pages.isNotEmpty) {
        setState(() { _pages = pages; _loading = false; });
      } else {
        setState(() { _error = 'Could not render PDF pages'; _loading = false; });
      }
    } catch (e) {
      debugPrint('PDF rendering error: $e');
      setState(() { _error = 'PDF rendering failed: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: widget.scheme.surfaceContainerHigh.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10.rs),
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_error != null) {
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: widget.scheme.errorContainer.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10.rs),
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded, size: 16, color: widget.scheme.error),
              SizedBox(width: 8.rs),
              Text(_error!, style: TextStyle(fontSize: 12, color: widget.scheme.error)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: _pages.asMap().entries.map((entry) {
        return Padding(
          padding: EdgeInsets.only(bottom: entry.key < _pages.length - 1 ? 8 : 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10.rs),
            child: Image.memory(
              entry.value,
              fit: BoxFit.contain,
              width: double.infinity,
              errorBuilder: (_, __, ___) => Container(
                height: 100,
                color: widget.scheme.surfaceContainerHigh.withValues(alpha: 0.3),
                child: Center(
                  child: Text('Unable to display page ${entry.key + 1}', style: TextStyle(fontSize: 12, color: widget.scheme.onSurfaceVariant)),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
