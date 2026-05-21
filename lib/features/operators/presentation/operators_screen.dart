import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';
import 'package:weighbridgemanagement/shared/providers/general_settings_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/utils/title_case.dart';


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
        width: 130,
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
    final operatorsAsync = _viewAllSites
        ? ref.watch(_allOperatorsProvider)
        : ref.watch(_operatorsProvider);

    return Column(
      children: [
        Expanded(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildNormalHeader(scheme, text, operatorsAsync),
            const SizedBox(height: 16),
            _buildTabBar(scheme, text, operatorsAsync),
            const SizedBox(height: 16),
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

                  final pending = filtered.where((o) => o['isVerified'] == false && (o['uid'] as String? ?? '').isEmpty).toList();
                  final verified = filtered.where((o) => o['isVerified'] != false || (o['uid'] as String? ?? '').isNotEmpty).toList();

                  if (_tabIndex == 1) {
                    return _buildRequestsTab(pending, scheme, text);
                  }

                  if (verified.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people_outline, size: 48, color: scheme.outlineVariant),
                          const SizedBox(height: 8),
                          Text(
                            _search.isNotEmpty ? 'No matches for "$_search"' : 'No operators yet',
                            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 4),
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
            const SizedBox(height: 12),
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
    final active = operators.where((o) => o['isActive'] == true && (o['isVerified'] != false || (o['uid'] as String? ?? '').isNotEmpty)).length;
    final pending = operators.where((o) => o['isVerified'] == false && (o['uid'] as String? ?? '').isEmpty).length;
    final shiftRestricted = operators.where((o) => o['shiftRestricted'] == true).length;
    final siteCtx = ref.watch(siteContextProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Operators', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 16),
            _buildJoinCodeChip(scheme),
            const Spacer(),
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
                            future: (siteCtx.companyId.isNotEmpty && siteCtx.siteId.isNotEmpty)
                                ? ref.read(firestorePathsProvider).firestore.doc('companies/${siteCtx.companyId}/sites/${siteCtx.siteId}').get().then((d) => d.data()?['name'] as String? ?? 'This Site')
                                : Future.value('This Site'),
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
        ),
        const SizedBox(height: 20),

        Row(
          children: [
            _headerStatCard('Total', '$total', Icons.people_rounded, scheme.primary, scheme),
            const SizedBox(width: 12),
            _headerStatCard('Active', '$active', Icons.check_circle_rounded, Colors.green.shade700, scheme),
            const SizedBox(width: 12),
            _headerStatCard('Pending', '$pending', Icons.pending_actions_rounded, Colors.amber.shade700, scheme),
            const SizedBox(width: 12),
            _headerStatCard('Shift Restricted', '$shiftRestricted', Icons.schedule_rounded, Colors.deepPurple, scheme),
          ],
        ),
        const SizedBox(height: 16),

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
            GestureDetector(
              onTap: () => _showAddOperatorDialog(context),
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
                    Icon(Icons.add_rounded, size: 14, color: scheme.onPrimary),
                    const SizedBox(width: 4),
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('System code copied'), duration: Duration(seconds: 2)),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.vpn_key_rounded, size: 12, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(code, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.primary, letterSpacing: 1)),
                  const SizedBox(width: 6),
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
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: scheme.primary)),
                const SizedBox(width: 6),
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
              borderRadius: BorderRadius.circular(6),
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
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: BorderSide(color: scheme.outlineVariant)),
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
                const SizedBox(width: 6),
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
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_rounded, size: 12, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text('System Code', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                    const SizedBox(width: 4),
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
    final pendingCount = all.where((o) => o['isVerified'] == false && (o['uid'] as String? ?? '').isEmpty && o['isArchived'] != true).length;
    final archivedCount = all.where((o) => o['isArchived'] == true).length;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
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
          borderRadius: BorderRadius.circular(6),
          boxShadow: selected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 3, offset: const Offset(0, 1))] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? scheme.onSurface : scheme.onSurfaceVariant)),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
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
    if (pending.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 48, color: scheme.outlineVariant),
            const SizedBox(height: 8),
            Text('No pending requests', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('All operator registrations have been processed', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: pending.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final op = pending[i];
        final createdAt = op['createdAt'];
        final invitedAt = op['invitedAt'];
        final isInvited = invitedAt != null;
        final timeStr = (isInvited ? invitedAt : createdAt) is Timestamp
            ? _formatTimestamp((isInvited ? invitedAt : createdAt) as Timestamp, ref.read(timeFormatProvider))
            : 'Unknown';

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isInvited ? scheme.primary.withValues(alpha: 0.3) : Colors.amber.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: isInvited ? scheme.primaryContainer.withValues(alpha: 0.3) : Colors.amber.withValues(alpha: 0.12),
                child: Icon(
                  isInvited ? Icons.send_rounded : Icons.person_outline_rounded,
                  size: 16,
                  color: isInvited ? scheme.primary : Colors.amber.shade700,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(op['name'] ?? 'Unknown', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isInvited ? scheme.primary.withValues(alpha: 0.08) : Colors.amber.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isInvited ? 'Invited' : 'Self-registered',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: isInvited ? scheme.primary : Colors.amber.shade700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(op['email'] ?? '', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          isInvited ? Icons.hourglass_bottom_rounded : Icons.access_time_rounded,
                          size: 11,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isInvited ? 'Awaiting login confirmation · Invited $timeStr' : 'Requested $timeStr',
                          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (!isInvited)
                GestureDetector(
                  onTap: () => ref.read(firestorePathsProvider).operators.doc(op['id']).update({'isVerified': true, 'isActive': true}),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded, size: 14, color: Colors.green.shade700),
                        const SizedBox(width: 4),
                        Text('Approve', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green.shade700)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => ref.read(firestorePathsProvider).operators.doc(op['id']).update({
                  'isArchived': true,
                  'isActive': false,
                  'isVerified': false,
                  'permissionsRevoked': true,
                  'archivedAt': FieldValue.serverTimestamp(),
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close_rounded, size: 14, color: scheme.error),
                      const SizedBox(width: 4),
                      Text('Reject', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.error)),
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

  Future<void> _deleteArchivedOperator(String id, String name) async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
    await ref.read(firestorePathsProvider).operators.doc(id).delete();
  }

  Widget _buildArchivedTab(List<Map<String, dynamic>> archived, ColorScheme scheme, TextTheme text) {
    if (archived.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.archive_outlined, size: 48, color: scheme.outlineVariant),
            const SizedBox(height: 8),
            Text('No archived operators', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('Archived operators will appear here', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: archived.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final op = archived[i];
        final archivedAt = op['archivedAt'];
        final timeStr = archivedAt is Timestamp
            ? _formatTimestamp(archivedAt, ref.read(timeFormatProvider))
            : 'Unknown';

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
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
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(op['name'] ?? 'Unknown', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(op['email'] ?? '', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.archive_outlined, size: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        const SizedBox(width: 4),
                        Text('Archived $timeStr', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
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
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.unarchive_outlined, size: 14, color: scheme.primary),
                      const SizedBox(width: 4),
                      Text('Restore', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.primary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _deleteArchivedOperator(op['id'] as String, op['name'] as String? ?? 'Unknown'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 14, color: scheme.error),
                      const SizedBox(width: 4),
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
  // TABLE VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTableContent(List<Map<String, dynamic>> operators, ColorScheme scheme, TextTheme text) {
    if (operators.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                SizedBox(width: 30, child: Text('#', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant))),
                const Expanded(flex: 3, child: Text('Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                const Expanded(flex: 3, child: Text('Email', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                const SizedBox(width: 90, child: Text('Phone', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                const Expanded(flex: 2, child: Text('Shift', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                const SizedBox(width: 90, child: Text('ID Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                const SizedBox(width: 150, child: Text('Last Active', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                const SizedBox(width: 60, child: Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                const Expanded(flex: 2, child: Center(child: Text('Actions', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: operators.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                thickness: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.2),
              ),
              itemBuilder: (_, i) {
                final op = operators[i];
                final isActive = op['isActive'] == true;
                final idStatus = op['idStatus'] as String? ?? 'not_submitted';
                final phone = op['phone'] as String? ?? '';

                return InkWell(
                  onTap: () => _showEditOperatorDialog(context, op),
                  hoverColor: scheme.primaryContainer.withValues(alpha: 0.1),
                  child: Container(
                    decoration: BoxDecoration(
                      color: i.isEven ? scheme.surface : scheme.surfaceContainerLow.withValues(alpha: 0.5),
                      border: Border(left: BorderSide(
                        width: 3,
                        color: isActive ? scheme.primary.withValues(alpha: i.isEven ? 0.15 : 0.35) : scheme.error.withValues(alpha: 0.3),
                      )),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(width: 30, child: Text('${i + 1}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant))),
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              _operatorAvatar(op, scheme, 14),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(op['name'] ?? '--', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis, maxLines: 1),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(op['email'] ?? '--', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis, maxLines: 1),
                        ),
                        SizedBox(
                          width: 90,
                          child: Text(phone.isNotEmpty ? phone : '--', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis, maxLines: 1),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(_formatShift(op), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis, maxLines: 1),
                        ),
                        SizedBox(width: 90, child: Align(alignment: Alignment.centerLeft, child: _buildIdStatusChip(idStatus, scheme))),
                        SizedBox(
                          width: 150,
                          child: Text(
                            _formatTimestamp(op['lastLoginAt'], ref.read(timeFormatProvider)),
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: isActive ? Colors.green.withValues(alpha: 0.1) : scheme.errorContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isActive ? 'Active' : 'Inactive',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isActive ? Colors.green.shade700 : scheme.onErrorContainer),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _actionChip(icon: Icons.edit_outlined, label: 'Edit', color: scheme.primary, onTap: () => _showEditOperatorDialog(context, op)),
                              const SizedBox(width: 4),
                              _actionChip(
                                icon: isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                                label: isActive ? 'Deactivate' : 'Activate',
                                color: isActive ? scheme.error : Colors.green.shade700,
                                onTap: () => ref.read(firestorePathsProvider).operators.doc(op['id']).update({'isActive': !isActive}),
                              ),
                              const SizedBox(width: 4),
                              _actionChip(icon: Icons.archive_outlined, label: 'Archive', color: scheme.error, onTap: () => _confirmArchive(context, op)),
                            ],
                          ),
                        ),
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

  // ═══════════════════════════════════════════════════════════════════════════
  // GRID VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildGridContent(List<Map<String, dynamic>> operators, ColorScheme scheme, TextTheme text) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        childAspectRatio: 1.3,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: operators.length,
      itemBuilder: (_, i) => _buildOperatorCard(operators[i], scheme, text),
    );
  }

  Widget _buildOperatorCard(Map<String, dynamic> op, ColorScheme scheme, TextTheme text) {
    final isActive = op['isActive'] == true;

    return GestureDetector(
      onTap: () => _showEditOperatorDialog(context, op),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _operatorAvatar(op, scheme, 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(op['name'] ?? '--', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                      Text(op['email'] ?? '--', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: isActive ? Colors.green : scheme.error,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const Spacer(),
            if ((op['phone'] as String? ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.phone_rounded, size: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        op['phone'] as String,
                        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _formatShift(op),
                    style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.access_time_rounded, size: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                const SizedBox(width: 4),
                Text(
                  _formatTimestamp(op['lastLoginAt'], ref.read(timeFormatProvider)),
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
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

    final active = filtered.where((o) => o['isActive'] == true && (o['isVerified'] != false || (o['uid'] as String? ?? '').isNotEmpty)).length;
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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Text('${filtered.length} shown', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
          if (filtered.length != operators.length) ...[
            Text(' / ${operators.length} total', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
          ],
          const SizedBox(width: 16),
          _bottomPill('Active', '$active', Colors.green.shade700, scheme),
          const SizedBox(width: 6),
          _bottomPill('Inactive', '$inactive', scheme.error, scheme),
          const SizedBox(width: 6),
          _bottomPill('Recent 7d', '$recentlyActive', scheme.primary, scheme),
          const SizedBox(width: 6),
          _bottomPill('Face', '$withFace', scheme.tertiary, scheme),
          const SizedBox(width: 6),
          _bottomPill('KYC', '$kycVerified', Colors.teal, scheme),
          const SizedBox(width: 6),
          _bottomPill('Shift Locked', '$shiftRestricted', Colors.deepPurple, scheme),
          const Spacer(),
          _bottomPill('All Sites', '$allSites', scheme.onSurfaceVariant, scheme),
          const SizedBox(width: 6),
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
        borderRadius: BorderRadius.circular(4),
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

  Widget _actionChip({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
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
        borderRadius: BorderRadius.circular(4),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: active ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 6),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add operator: $e')),
        );
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 440,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_add_rounded, size: 20, color: scheme.primary),
                    const SizedBox(width: 10),
                    Text('Add Operator', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 13, color: scheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Operator will need to log in and confirm to activate their account.',
                          style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('Name', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
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
                const SizedBox(height: 16),
                Text('Email', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
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
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.block_rounded, size: 13, color: scheme.error),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '"@${_domainWarning!}" is not in the allowed domains list.',
                                style: TextStyle(fontSize: 11, color: scheme.error, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
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
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_rounded, size: 12, color: scheme.primary),
                                    const SizedBox(width: 4),
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
                const SizedBox(height: 16),
                Text('Phone', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
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
                const SizedBox(height: 16),
                Text('Site Access', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _scopeChip('all', 'All Sites', Icons.public_rounded, scheme),
                    const SizedBox(width: 8),
                    _scopeChip('specific', 'Specific Sites', Icons.location_on_rounded, scheme),
                  ],
                ),
                if (_siteScope == 'specific' && _allSites.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
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
                                borderRadius: BorderRadius.circular(6),
                                border: selected ? Border.all(color: scheme.primary.withValues(alpha: 0.3)) : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                    size: 16,
                                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
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
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving || _domainWarning != null ? null : _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  late bool _mustChangePassword;

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

    _mustChangePassword = op['mustChangePassword'] == true;

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
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: active ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 6),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${field == 'email' ? 'Email' : 'Phone'} updated successfully.')),
        );
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
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _currentEmail.isNotEmpty ? _currentEmail : '--',
                  style: text.bodySmall?.copyWith(color: scheme.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 36,
              child: OutlinedButton(
                onPressed: () => _startChangeField('email'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Change'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _fieldLabel('Phone', text),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _currentPhone.isNotEmpty ? _currentPhone : '--',
                  style: text.bodySmall?.copyWith(color: scheme.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 36,
              child: OutlinedButton(
                onPressed: () => _startChangeField('phone'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            const SizedBox(width: 6),
            Text('Change Operator $fieldLabel', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary)),
            const Spacer(),
            GestureDetector(
              onTap: _cancelChange,
              child: Icon(Icons.close_rounded, size: 16, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (!_otpSent) ...[
          Text(
            'New $fieldLabel',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurface),
          ),
          const SizedBox(height: 6),
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
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'A verification code will be sent to your admin email ($adminEmail) for confirmation.',
                    style: TextStyle(fontSize: 10, color: scheme.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _otpVerifying ? null : _sendAdminOTP,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
          const SizedBox(height: 10),
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _otpVerifying ? null : _verifyAndApplyChange,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _otpVerifying
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Verify & Update'),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _otpVerifying ? null : _sendAdminOTP,
              child: Text('Resend Code', style: TextStyle(fontSize: 11, color: scheme.primary)),
            ),
          ),
        ],

        if (_changeError != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 13, color: scheme.error),
                const SizedBox(width: 6),
                Expanded(child: Text(_changeError!, style: TextStyle(fontSize: 11, color: scheme.error))),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildKycSection(ColorScheme scheme, TextTheme text, Map<String, dynamic> op) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Success message
        if (_kycSuccessMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 15, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(child: Text(_kycSuccessMessage!, style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
          const SizedBox(height: 12),
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
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded, size: 15, color: Colors.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(type, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: Colors.green.shade700)),
                        Text(number, style: text.bodySmall?.copyWith(color: scheme.onSurface, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
        ],

        if (_verifiedIds.isEmpty && !_showAddId)
          Text('No IDs verified yet.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),

        // Add new ID section
        if (_showAddId) ...[
          // Document type dropdown
          _fieldLabel('Document Type', text),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _idDocumentType,
            items: _documentTypes
                .where((e) => !_verifiedIds.any((id) => id['type'] == e))
                .map((e) => DropdownMenuItem(value: e, child: Text(e, style: text.bodySmall))).toList(),
            onChanged: (v) { if (v != null) setState(() => _idDocumentType = v); },
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: scheme.outlineVariant)),
            ),
            style: text.bodySmall,
            icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),

          // Document number (read-only, extracted from scan)
          if (_idDocNumberCtrl.text.isNotEmpty) ...[
            _fieldLabel('Extracted Number', text),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Text(_idDocNumberCtrl.text, style: text.bodySmall),
            ),
            const SizedBox(height: 12),
          ],

          // Upload hint + button
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(_idUploadHint(), style: TextStyle(fontSize: 10, color: scheme.primary))),
              ],
            ),
          ),
          const SizedBox(height: 10),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('Select multiple files for front + back. Accepts PDF, JPG, PNG.', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 10)),

          // Scan error
          if (_kycError != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 14, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_kycError!, style: TextStyle(fontSize: 11, color: scheme.error))),
                ],
              ),
            ),
          ],

          // Name match result
          if (_kycNameMatch != null && _kycExtractedName != null) ...[
            const SizedBox(height: 12),
            if (_kycNameMatch == 'exact')
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 15, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Name matches: $_kycExtractedName', style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600))),
                  ],
                ),
              ),

            if (_kycNameMatch == 'close') ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_rounded, size: 14, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Name on ID: "$_kycExtractedName"', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade700))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _wasAlreadyVerified
                          ? 'Slightly different from operator name "${op['name']}". Name cannot be changed after first verification.'
                          : 'Slightly different from operator name "${op['name']}". Update name to match ID?',
                      style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (!_wasAlreadyVerified) ...[
                          Expanded(
                            child: FilledButton(
                              onPressed: () => _applyKycVerification(_kycExtractedName),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                              ),
                              child: const Text('Update Name & Verify'),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: _wasAlreadyVerified
                              ? FilledButton(
                                  onPressed: () => _applyKycVerification(null),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                                  ),
                                  child: const Text('Verify'),
                                )
                              : OutlinedButton(
                                  onPressed: () => _applyKycVerification(null),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.error_rounded, size: 14, color: scheme.error),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Name mismatch', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.error))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('ID says: "$_kycExtractedName"', style: TextStyle(fontSize: 11, color: scheme.onSurface)),
                    Text('Operator: "${op['name']}"', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (!_wasAlreadyVerified) ...[
                          Expanded(
                            child: FilledButton(
                              onPressed: () => _applyKycVerification(_kycExtractedName),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                                backgroundColor: Colors.orange,
                              ),
                              child: const Text('Use ID Name & Verify'),
                            ),
                          ),
                          const SizedBox(width: 8),
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
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
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
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_rounded, size: 14, color: Colors.amber.shade700),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_kycDuplicateWarning!, style: TextStyle(fontSize: 10, color: Colors.amber.shade900))),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => setState(() { _showAddId = false; _kycError = null; _kycNameMatch = null; _idDocNumberCtrl.clear(); }),
              child: Text('Cancel', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ),
          ),
        ],

        // Add ID button (hide if all types already verified)
        if (!_showAddId && _documentTypes.any((e) => !_verifiedIds.any((id) => id['type'] == e))) ...[
          const SizedBox(height: 12),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ],
    );
  }


  Future<void> _saveField(Map<String, dynamic> fields) async {
    try {
      final db = widget.ref.read(firestorePathsProvider);
      await db.operators.doc(widget.operator['id']).update(fields);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
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
      setState(() => _kycError = e.message ?? 'Scan failed.');
    } catch (e) {
      setState(() => _kycError = 'Failed to scan document.');
    } finally {
      if (mounted) setState(() => _kycScanning = false);
    }
  }

  Future<void> _applyKycVerification(String? newName) async {
    final db = widget.ref.read(firestorePathsProvider);
    final adminEmail = await _getAdminEmail() ?? 'admin';
    final docNumber = _idDocNumberCtrl.text.trim();

    // Add to verified IDs list
    final newIdEntry = <String, dynamic>{
      'type': _idDocumentType,
      'number': docNumber,
      'verifiedBy': adminEmail,
      'verifiedAt': DateTime.now().toIso8601String(),
      if (_kycExtractedAddress != null) 'address': _kycExtractedAddress,
    };
    _verifiedIds.add(newIdEntry);

    final updateData = <String, dynamic>{
      'idStatus': 'verified',
      'idVerifiedAt': FieldValue.serverTimestamp(),
      'idVerifiedBy': adminEmail,
      'idDocumentType': _idDocumentType,
      'idDocumentNumber': docNumber,
      'verifiedIds': _verifiedIds,
    };
    if (newName != null && newName.isNotEmpty) {
      updateData['name'] = newName;
    }
    if (_kycExtractedAddress != null && _kycExtractedAddress!.isNotEmpty) {
      updateData['address'] = _kycExtractedAddress;
    }
    await db.operators.doc(widget.operator['id']).update(updateData);
    setState(() {
      _idStatus = 'verified';
      _kycNameMatch = null;
      _kycExtractedName = null;
      _kycExtractedAddress = null;
      _showAddId = false;
      _idDocNumberCtrl.clear();
      _kycSuccessMessage = newName != null ? 'ID verified, name updated to "$newName".' : 'ID verified successfully.';
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 32),
      child: SizedBox(
        width: 920,
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
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(op['name'] ?? '', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isActive ? Colors.green.withValues(alpha: 0.1) : scheme.errorContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(width: 6, height: 6, decoration: BoxDecoration(color: isActive ? Colors.green : scheme.error, shape: BoxShape.circle)),
                                  const SizedBox(width: 6),
                                  Text(isActive ? 'Active' : 'Inactive', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isActive ? Colors.green.shade700 : scheme.error)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(op['role'] ?? 'operator', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant)),
                            ),
                            if (op['shiftRestricted'] == true) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.schedule_rounded, size: 11, color: Colors.deepPurple.shade400),
                                    const SizedBox(width: 4),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left column
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
                          if ((op['address'] as String? ?? '').isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _sectionCard(
                              title: 'Address',
                              icon: Icons.location_on_rounded,
                              scheme: scheme,
                              text: text,
                              child: Text(op['address'] as String, style: text.bodySmall?.copyWith(color: scheme.onSurface)),
                            ),
                          ],
                          const SizedBox(height: 16),
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
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(child: _timePickerTile('Start', _shiftStart, () => _pickTime(isStart: true), scheme, text)),
                                      const SizedBox(width: 14),
                                      Expanded(child: _timePickerTile('End', _shiftEnd, () => _pickTime(isStart: false), scheme, text)),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
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
                                            borderRadius: BorderRadius.circular(6),
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
                          const SizedBox(height: 16),
                          _sectionCard(
                            title: 'ID Verification (KYC)',
                            icon: Icons.verified_user_rounded,
                            scheme: scheme,
                            text: text,
                            child: _buildKycSection(scheme, text, op),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 28),

                    // Right column
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
                                const SizedBox(height: 12),
                                _metaRow(Icons.key_rounded, 'Password changed', _formatTimestamp(op['passwordLastChanged'], widget.ref.read(timeFormatProvider)), scheme, text),
                                const SizedBox(height: 6),
                                _metaRow(Icons.login_rounded, 'First login', (op['loginCount'] != null && (op['loginCount'] as int) > 0) ? 'Completed' : 'Not yet', scheme, text),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
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
                          const SizedBox(height: 16),
                          _sectionCard(
                            title: 'Activity',
                            icon: Icons.insights_rounded,
                            scheme: scheme,
                            text: text,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _metaRow(Icons.access_time_rounded, 'Last login', _formatTimestamp(op['lastLoginAt'], widget.ref.read(timeFormatProvider)), scheme, text),
                                const SizedBox(height: 6),
                                _metaRow(Icons.numbers_rounded, 'Total logins', '${op['loginCount'] ?? 0}', scheme, text),
                                const SizedBox(height: 6),
                                _metaRow(Icons.calendar_today_rounded, 'Created', _formatTimestamp(op['createdAt'], widget.ref.read(timeFormatProvider)), scheme, text),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
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
                                    const SizedBox(width: 8),
                                    _editScopeChip('specific', 'Specific Sites', Icons.location_on_rounded, scheme),
                                  ],
                                ),
                                if (_siteScope == 'specific' && _allSites.isNotEmpty) ...[
                                  const SizedBox(height: 10),
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
                                                  const SizedBox(width: 8),
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
                          const SizedBox(height: 16),
                          _sectionCard(
                            title: 'Face Enrollment',
                            icon: Icons.face_rounded,
                            scheme: scheme,
                            text: text,
                            child: _FaceEnrollmentWidget(
                              ref: widget.ref,
                              operatorId: widget.operator['id'] as String,
                              existingFacePhoto: widget.operator['facePhoto'] as String?,
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        insetPadding: const EdgeInsets.all(40),
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
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(file, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(8),
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
                  padding: const EdgeInsets.all(6),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 14),
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
        const SizedBox(width: 8),
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
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
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

class _IdentityCamera {
  final String key;
  final String label;
  final String source;
  final String deviceName;
  const _IdentityCamera({required this.key, required this.label, required this.source, required this.deviceName});
}

class _FaceEnrollmentWidget extends StatefulWidget {
  final WidgetRef ref;
  final String operatorId;
  final String? existingFacePhoto;

  const _FaceEnrollmentWidget({
    required this.ref,
    required this.operatorId,
    this.existingFacePhoto,
  });

  @override
  State<_FaceEnrollmentWidget> createState() => _FaceEnrollmentWidgetState();
}

class _FaceEnrollmentWidgetState extends State<_FaceEnrollmentWidget> {
  Uint8List? _capturedFrame;
  Uint8List? _liveFrame;
  Timer? _frameTimer;
  bool _capturing = false;
  bool _enrolled = false;
  bool _liveMode = false;
  bool _faceDetected = false;
  bool _saving = false;
  String? _error;
  String _status = '';
  int _deviceIndex = 0;
  int _frameCount = 0;

  // Camera selection
  bool _showCameraChoice = false;
  List<_IdentityCamera> _availableCameras = [];

  String get _frameCachePath {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    final dir = Directory('$home/.weighbridge/frames');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  @override
  void initState() {
    super.initState();
    _enrolled = widget.existingFacePhoto != null && widget.existingFacePhoto!.isNotEmpty;
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAvailableCameras() async {
    final cameras = <_IdentityCamera>[];
    try {
      final db = widget.ref.read(firestorePathsProvider);
      final camDoc = await db.camerasAiSettings.get();
      if (camDoc.exists) {
        final camsMap = camDoc.data()?['cameras'] as Map<String, dynamic>?;
        for (final key in ['operator', 'customer']) {
          final cam = camsMap?[key] as Map<String, dynamic>?;
          if (cam != null && cam['enabled'] == true) {
            final source = cam['source'] as String? ?? 'Built-in';
            final deviceName = source == 'USB'
                ? cam['usbDevice'] as String? ?? ''
                : cam['builtInDevice'] as String? ?? '';
            if (deviceName.isNotEmpty) {
              cameras.add(_IdentityCamera(
                key: key,
                label: key == 'operator' ? 'Operator Camera' : 'Customer Camera',
                source: source,
                deviceName: deviceName,
              ));
            }
          }
        }
      }
    } catch (_) {}
    _availableCameras = cameras;
  }

  Future<void> _beginEnrollment() async {
    await _loadAvailableCameras();
    if (_availableCameras.length > 1) {
      setState(() => _showCameraChoice = true);
    } else {
      _startLiveFeedWithCamera(_availableCameras.isNotEmpty ? _availableCameras.first : null);
    }
  }

  Future<void> _startLiveFeedWithCamera(_IdentityCamera? camera) async {
    setState(() { _liveMode = true; _showCameraChoice = false; _status = 'Initializing camera...'; _error = null; });

    if (camera != null) {
      try {
        final result = await Process.run('system_profiler', ['SPCameraDataType', '-json']);
        if (result.exitCode == 0) {
          final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
          final cams = data['SPCameraDataType'] as List<dynamic>? ?? [];
          final names = cams.map((c) => (c as Map<String, dynamic>)['_name'] as String? ?? '').toList();
          final idx = names.indexOf(camera.deviceName);
          if (idx >= 0) _deviceIndex = idx;
        }
      } catch (_) {}
    }

    _frameCount = 0;
    _faceDetected = false;
    _captureLocalFrame();
    _frameTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_liveMode && !_capturing) _captureLocalFrame();
    });
  }

  Future<void> _captureLocalFrame() async {
    if (_capturing) return;
    _capturing = true;
    final framePath = '$_frameCachePath/enroll_live_${widget.operatorId}.jpg';

    try {
      final result = await Process.run('ffmpeg', [
        '-y',
        '-f', 'avfoundation',
        '-framerate', '30',
        '-i', '$_deviceIndex:none',
        '-frames:v', '1',
        '-update', '1',
        '-q:v', '3',
        framePath,
      ], stdoutEncoding: utf8, stderrEncoding: utf8);

      if (!mounted) return;
      final file = File(framePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty && mounted) {
          _frameCount++;
          setState(() {
            _liveFrame = bytes;
            _error = null;
            if (_frameCount >= 3 && !_faceDetected) {
              _faceDetected = true;
              _status = 'Face detected — ready to capture';
            } else if (!_faceDetected) {
              _status = 'Detecting face...';
            }
          });
        }
      } else {
        final err = (result.stderr as String).toLowerCase();
        if (err.contains('permission') || err.contains('denied')) {
          setState(() { _error = 'Camera permission denied'; _liveMode = false; });
          _frameTimer?.cancel();
        } else if (err.contains('no such') || err.contains('cannot open')) {
          setState(() { _error = 'Camera not available'; _liveMode = false; });
          _frameTimer?.cancel();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() { _error = 'ffmpeg not found. Install via: brew install ffmpeg'; _liveMode = false; });
        _frameTimer?.cancel();
      }
    } finally {
      _capturing = false;
    }
  }

  void _captureForEnrollment() {
    if (_liveFrame == null) return;
    _frameTimer?.cancel();
    setState(() {
      _capturedFrame = _liveFrame;
      _liveMode = false;
    });
  }

  void _cancelLiveFeed() {
    _frameTimer?.cancel();
    setState(() { _liveMode = false; _liveFrame = null; _faceDetected = false; _frameCount = 0; });
  }

  Future<void> _enrollFace() async {
    if (_capturedFrame == null) return;
    setState(() => _saving = true);

    try {
      final photoPath = '$_frameCachePath/face_${widget.operatorId}.jpg';
      await File(photoPath).writeAsBytes(_capturedFrame!);

      final db = widget.ref.read(firestorePathsProvider);
      await db.operators.doc(widget.operatorId).update({
        'facePhoto': photoPath,
        'faceEnrolledAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() { _enrolled = true; _capturedFrame = null; _error = null; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Face enrolled successfully'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeFace() async {
    setState(() => _saving = true);
    try {
      final db = widget.ref.read(firestorePathsProvider);
      await db.operators.doc(widget.operatorId).update({
        'facePhoto': FieldValue.delete(),
        'faceEnrolledAt': FieldValue.delete(),
      });

      final photoPath = '$_frameCachePath/face_${widget.operatorId}.jpg';
      final file = File(photoPath);
      if (await file.exists()) await file.delete();

      if (mounted) {
        setState(() { _enrolled = false; _capturedFrame = null; });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to remove: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_enrolled && !_liveMode && _capturedFrame == null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Face enrolled', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.primary)),
                const Spacer(),
                TextButton(
                  onPressed: _saving ? null : _removeFace,
                  child: Text('Remove', style: TextStyle(fontSize: 11, color: scheme.error)),
                ),
              ],
            ),
          ),

        if (_liveMode)
          Column(
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _liveFrame != null
                        ? Image.memory(
                            _liveFrame!,
                            width: double.infinity,
                            height: 180,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          )
                        : Container(
                            width: double.infinity,
                            height: 180,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary)),
                                  const SizedBox(height: 8),
                                  Text(_status, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (_faceDetected ? Colors.green : Colors.orange).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _faceDetected ? Icons.face_rounded : Icons.face_retouching_off_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _faceDetected ? 'Face Detected' : 'Searching...',
                            style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_liveFrame != null)
                    Positioned.fill(
                      child: CustomPaint(painter: _FaceGuidePainter(detected: _faceDetected, scheme: scheme)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(_status, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cancelLiveFeed,
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _faceDetected ? _captureForEnrollment : null,
                      icon: const Icon(Icons.camera_rounded, size: 16),
                      label: const Text('Capture'),
                    ),
                  ),
                ],
              ),
            ],
          ),

        if (_capturedFrame != null && !_liveMode)
          Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  _capturedFrame!,
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _beginEnrollment,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Retake'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _enrollFace,
                      icon: _saving
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_rounded, size: 16),
                      label: Text(_saving ? 'Saving...' : 'Enroll'),
                    ),
                  ),
                ],
              ),
            ],
          ),

        if (_showCameraChoice && !_liveMode)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Select Camera', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ..._availableCameras.map((cam) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _startLiveFeedWithCamera(cam),
                    icon: Icon(cam.key == 'operator' ? Icons.face_rounded : Icons.person_search_rounded, size: 16),
                    label: Text('${cam.label} (${cam.source})', style: const TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              )),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _showCameraChoice = false),
                  child: Text('Cancel', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                ),
              ),
            ],
          ),

        if (!_enrolled && !_liveMode && _capturedFrame == null && !_showCameraChoice)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Capture a face photo for quick switch via face scan.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _beginEnrollment,
                  icon: const Icon(Icons.videocam_rounded, size: 16),
                  label: const Text('Start Face Enrollment'),
                ),
              ),
            ],
          ),

        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: text.labelSmall?.copyWith(color: scheme.error)),
        ],
      ],
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
