import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:weighbridgemanagement/features/auth/presentation/change_password_screen.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/general_settings_provider.dart';
import 'package:weighbridgemanagement/shared/providers/offline_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';

// ─── Active user provider (supports switching) ──────────────────────────────

final activeUserProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

final _profileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final override = ref.watch(activeUserProvider);
  if (override != null) return override;

  final db = ref.watch(firestorePathsProvider);
  final user = FirebaseAuth.instance.currentUser;
  final email = user?.email ?? await LocalCacheService.getCachedCurrentUserEmail();

  if (email == null || email.isEmpty) return {'role': 'admin'};

  try {
    final snap = await db.operators.where('email', isEqualTo: email).limit(1).get();
    if (snap.docs.isNotEmpty) {
      return {'role': snap.docs.first.data()['role'] ?? 'operator', 'id': snap.docs.first.id, ...snap.docs.first.data()};
    }
  } catch (_) {}

  try {
    final adminDoc = await db.adminProfileSettings.get();
    if (adminDoc.exists) {
      final profile = {'role': 'admin', 'email': email, 'name': user?.displayName, ...adminDoc.data()!};
      LocalCacheService.cacheAdminProfile(profile.map((k, v) => MapEntry(k, v?.toString())));
      return profile;
    }
  } catch (_) {}

  final cached = await LocalCacheService.getCachedAdminProfile();
  if (cached != null) return {'role': 'admin', 'email': email, 'name': user?.displayName, ...cached};
  return {'role': 'admin', 'email': email, 'name': user?.displayName};
});

final _allOperatorsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  try {
    final snap = await db.operators.where('isActive', isEqualTo: true).get();
    final operators = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    LocalCacheService.cacheOperators(operators);
    return operators;
  } catch (_) {}
  final cached = await LocalCacheService.getCachedOperators();
  if (cached.isNotEmpty) return cached;
  return [];
});

final _cameraSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  try {
    final doc = await db.camerasAiSettings.get();
    if (doc.exists) return doc.data()!;
  } catch (_) {}
  return {};
});

// ─── Screen ─────────────────────────────────────────────────────────────────

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Timer? _ipTimer;
  String _currentIp = '...';
  final DateTime _sessionStartTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _refreshIp();
    // Scan IP every 30 seconds (standard for network session monitoring)
    _ipTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshIp());
    _recordSession();
  }

  @override
  void dispose() {
    _ipTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshIp() async {
    final ip = await _getLocalIp();
    if (mounted && ip != _currentIp) {
      setState(() => _currentIp = ip);
      _updateSessionIp(ip);
    }
  }

  Future<void> _recordSession() async {
    try {
      final db = ref.read(firestorePathsProvider);
      final profile = ref.read(_profileProvider).valueOrNull;
      final role = profile?['role'] as String? ?? 'admin';
      final userId = role == 'admin' ? 'admin' : (profile?['id'] as String? ?? 'unknown');
      final ip = await _getLocalIp();
      if (mounted) setState(() => _currentIp = ip);

      await db.sessions.doc(userId).set({
        'userId': userId,
        'role': role,
        'machine': Platform.localHostname,
        'platform': Platform.operatingSystem,
        'ip': ip,
        'startedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _updateSessionIp(String ip) async {
    try {
      final db = ref.read(firestorePathsProvider);
      final profile = ref.read(_profileProvider).valueOrNull;
      final role = profile?['role'] as String? ?? 'admin';
      final userId = role == 'admin' ? 'admin' : (profile?['id'] as String? ?? 'unknown');

      await db.sessions.doc(userId).update({
        'ip': ip,
        'lastSeenAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final profileAsync = ref.watch(_profileProvider);
    final settings = ref.watch(securitySettingsProvider).valueOrNull ?? const SecuritySettings();
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (profile) {
          final role = profile['role'] as String? ?? 'admin';
          final isAdmin = role == 'admin';
          final name = profile['name'] as String? ?? user?.displayName ?? 'Admin';
          final email = profile['email'] as String? ?? user?.email ?? '--';
          final phone = profile['phone'] as String? ?? '';
          final employeeId = profile['employeeId'] as String? ?? '';
          final idStatus = profile['idStatus'] as String? ?? 'not_submitted';
          final lastLogin = profile['lastLoginAt'];
          final loginCount = profile['loginCount'] as int? ?? 0;
          final passwordLastChanged = profile['passwordLastChanged'];
          final shiftRestricted = profile['shiftRestricted'] == true;
          final shiftStart = profile['shiftStart'] as String?;
          final shiftEnd = profile['shiftEnd'] as String?;
          final shiftDays = (profile['shiftDays'] as List<dynamic>?)?.map((e) => e.toString()).toList();
          final mustChangePassword = profile['mustChangePassword'] == true;
          final createdAt = profile['createdAt'];

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero header
                _buildHeroHeader(scheme, text, name, email, role, phone, createdAt),
                const SizedBox(height: 28),

                // Row 1: Details + Security
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: _buildDetailsCard(scheme, text, isAdmin, email, phone, employeeId, idStatus, createdAt)),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: _buildSecurityCard(scheme, text, isAdmin, lastLogin, passwordLastChanged, mustChangePassword, settings, loginCount)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Row 2: Session + Switch User
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: _buildSessionCard(scheme, text, isAdmin, shiftRestricted, shiftStart, shiftEnd, shiftDays)),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: _buildSwitchUserCard(scheme, text, isAdmin)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HERO HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeroHeader(ColorScheme scheme, TextTheme text, String name, String email, String role, String phone, dynamic createdAt) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary.withValues(alpha: 0.08), scheme.primaryContainer.withValues(alpha: 0.12)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.primary.withValues(alpha: 0.75)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: scheme.onPrimary),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: role == 'admin' ? scheme.primary : scheme.tertiary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        role == 'admin' ? 'Admin' : 'Operator',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: role == 'admin' ? scheme.onPrimary : scheme.onTertiary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(email, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(phone, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
                ],
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChangePasswordScreen(reason: 'Change your password')),
              );
            },
            icon: const Icon(Icons.lock_reset_rounded, size: 16),
            label: const Text('Change Password'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DETAILS CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDetailsCard(ColorScheme scheme, TextTheme text, bool isAdmin, String email, String phone, String employeeId, String idStatus, dynamic createdAt) {
    return _Card(
      icon: Icons.person_rounded,
      title: 'Details',
      scheme: scheme,
      text: text,
      children: [
        _InfoRow(label: 'Email', scheme: scheme, text: text, child: Text(
          email,
          style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        )),
        const SizedBox(height: 10),
        _InfoRow(label: 'Phone', scheme: scheme, text: text, child: Text(
          phone.isNotEmpty ? phone : '--',
          style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: phone.isNotEmpty ? null : scheme.onSurfaceVariant),
        )),
        const SizedBox(height: 10),
        if (!isAdmin) ...[
          _InfoRow(label: 'Employee ID', scheme: scheme, text: text, child: Text(
            employeeId.isNotEmpty ? employeeId : '--',
            style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: employeeId.isNotEmpty ? null : scheme.onSurfaceVariant),
          )),
          const SizedBox(height: 10),
          _InfoRow(label: 'KYC Status', scheme: scheme, text: text, child: _buildKycChip(idStatus, scheme)),
          const SizedBox(height: 10),
        ],
        if (createdAt != null)
          _InfoRow(label: 'Member since', scheme: scheme, text: text, child: Text(
            _formatTimestamp(createdAt),
            style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          )),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SECURITY STATUS CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSecurityCard(ColorScheme scheme, TextTheme text, bool isAdmin, dynamic lastLogin, dynamic passwordLastChanged, bool mustChangePassword, SecuritySettings settings, int loginCount) {
    final passwordAge = _getPasswordAge(passwordLastChanged);
    final mfaEnabled = FirebaseAuth.instance.currentUser?.multiFactor != null;

    return _Card(
      icon: Icons.shield_rounded,
      title: 'Security',
      scheme: scheme,
      text: text,
      children: [
        _InfoRow(label: 'Last Login', scheme: scheme, text: text, child: Text(
          lastLogin != null ? _formatTimestamp(lastLogin) : 'Current session',
          style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        )),
        const SizedBox(height: 10),
        _InfoRow(label: 'Logins', scheme: scheme, text: text, child: Text(
          '$loginCount',
          style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        )),
        const SizedBox(height: 10),
        _InfoRow(label: 'Password', scheme: scheme, text: text, child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(passwordAge, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            if (mustChangePassword) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(4)),
                child: Text('Change required', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: scheme.error)),
              ),
            ],
          ],
        )),
        if (settings.passwordExpiryDays > 0) ...[
          const SizedBox(height: 10),
          _InfoRow(label: 'Expiry', scheme: scheme, text: text, child: Text(
            'Every ${settings.passwordExpiryDays} days',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          )),
        ],
        const SizedBox(height: 10),
        _InfoRow(label: 'MFA', scheme: scheme, text: text, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: mfaEnabled ? scheme.primaryContainer.withValues(alpha: 0.5) : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            mfaEnabled ? 'Enabled' : 'Not configured',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: mfaEnabled ? scheme.primary : scheme.onSurfaceVariant),
          ),
        )),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SESSION INFO CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSessionCard(ColorScheme scheme, TextTheme text, bool isAdmin, bool shiftRestricted, String? shiftStart, String? shiftEnd, List<String>? shiftDays) {
    final hostname = Platform.localHostname;
    final sessionStart = '${DateFormat('dd MMM yyyy').format(_sessionStartTime)}, ${getTimeFormatter(ref.read(timeFormatProvider)).format(_sessionStartTime)}';
    final uptime = DateTime.now().difference(_sessionStartTime);
    final uptimeStr = uptime.inHours > 0
        ? '${uptime.inHours}h ${uptime.inMinutes.remainder(60)}m'
        : '${uptime.inMinutes}m';

    return _Card(
      icon: Icons.computer_rounded,
      title: 'Session',
      scheme: scheme,
      text: text,
      children: [
        _InfoRow(label: 'Machine', scheme: scheme, text: text, child: Text(
          hostname,
          style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        )),
        const SizedBox(height: 10),
        _InfoRow(label: 'Started', scheme: scheme, text: text, child: Text(
          sessionStart,
          style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        )),
        const SizedBox(height: 10),
        _InfoRow(label: 'Uptime', scheme: scheme, text: text, child: Text(
          uptimeStr,
          style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        )),
        const SizedBox(height: 10),
        _InfoRow(label: 'Platform', scheme: scheme, text: text, child: Text(
          '${Platform.operatingSystem[0].toUpperCase()}${Platform.operatingSystem.substring(1)}',
          style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        )),
        const SizedBox(height: 10),
        _InfoRow(label: 'IP Address', scheme: scheme, text: text, child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_currentIp, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _refreshIp,
              child: Icon(Icons.refresh_rounded, size: 14, color: scheme.primary),
            ),
          ],
        )),
        if (!isAdmin && shiftRestricted) ...[
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text('Shift Schedule', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _InfoRow(label: 'Hours', scheme: scheme, text: text, child: Text(
            '${shiftStart ?? '--'} – ${shiftEnd ?? '--'}',
            style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          )),
          const SizedBox(height: 10),
          _InfoRow(label: 'Days', scheme: scheme, text: text, child: Text(
            shiftDays?.join(', ') ?? '--',
            style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          )),
          const SizedBox(height: 10),
          _InfoRow(label: 'Status', scheme: scheme, text: text, child: _buildShiftStatus(scheme, shiftStart, shiftEnd, shiftDays)),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SWITCH USER CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSwitchUserCard(ColorScheme scheme, TextTheme text, bool isAdmin) {
    return _Card(
      icon: Icons.swap_horiz_rounded,
      title: 'Switch User',
      scheme: scheme,
      text: text,
      children: [
        Text(
          'Switch to another operator account on this machine.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),

        OutlinedButton.icon(
          onPressed: _showFaceScanDialog,
          icon: const Icon(Icons.face_rounded, size: 18),
          label: const Text('Scan Face'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 42),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 10),

        FilledButton.icon(
          onPressed: _showManualSwitchDialog,
          icon: const Icon(Icons.people_rounded, size: 18),
          label: const Text('Select Operator'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 42),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),

        // Only show "Switch to Admin" when NOT already admin
        if (!isAdmin) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _showAdminSwitchDialog,
            icon: Icon(Icons.admin_panel_settings_rounded, size: 18, color: scheme.primary),
            label: Text('Switch to Admin', style: TextStyle(color: scheme.primary)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 42),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
            ),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SWITCH USER DIALOGS
  // ═══════════════════════════════════════════════════════════════════════════

  void _showFaceScanDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _FaceScanDialog(
        ref: ref,
        onMatched: (operator) {
          Navigator.pop(ctx);
          ref.read(activeUserProvider.notifier).state = {...operator, 'role': 'operator'};
          ref.invalidate(_profileProvider);

          final opId = operator['id'] as String?;
          final online = ref.read(isOnlineProvider);

          if (opId != null) {
            if (online) {
              final db = ref.read(firestorePathsProvider);
              db.operators.doc(opId).update({
                'lastLoginAt': FieldValue.serverTimestamp(),
                'loginCount': FieldValue.increment(1),
              });
            } else {
              ref.read(offlineQueueProvider).enqueueOperatorUpdate(opId, {
                'lastLoginAt': DateTime.now().toIso8601String(),
                'loginCount': 1,
              });
            }
          }

          if (online) {
            ref.read(auditServiceProvider).log(
              event: 'userSwitch',
              description: 'Face scan switch to: ${operator['name']}',
              user: operator['email'] as String? ?? 'unknown',
            );
          } else {
            ref.read(offlineQueueProvider).enqueueAuditLog({
              'event': 'userSwitch',
              'description': 'Face scan switch to: ${operator['name']}',
              'user': operator['email'] as String? ?? 'unknown',
              'machine': Platform.localHostname,
              'timestamp': DateTime.now().toIso8601String(),
              'success': true,
            });
          }

          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Switched to ${operator['name']}'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ));
        },
      ),
    );
  }

  void _showManualSwitchDialog() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final operatorsAsync = ref.read(_allOperatorsProvider);
    final operators = operatorsAsync.valueOrNull ?? [];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.people_rounded, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          const Text('Switch to Operator'),
        ]),
        content: SizedBox(
          width: 400,
          height: 360,
          child: operators.isEmpty
              ? Center(child: Text('No active operators found', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)))
              : ListView.separated(
                  itemCount: operators.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final op = operators[i];
                    final opName = op['name'] as String? ?? '--';
                    final opEmail = op['email'] as String? ?? '--';

                    return ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      tileColor: scheme.surfaceContainerLow,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: scheme.primaryContainer,
                        child: Text(opName.isNotEmpty ? opName[0].toUpperCase() : '?', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary, fontSize: 13)),
                      ),
                      title: Text(opName, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                      subtitle: Text(opEmail, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                      trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: scheme.onSurfaceVariant),
                      onTap: () {
                        Navigator.pop(ctx);
                        _verifyAndSwitch(op);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
  }

  void _showAdminSwitchDialog() {
    _verifyAdminAndSwitch();
  }

  void _verifyAndSwitch(Map<String, dynamic> operator) {
    final scheme = Theme.of(context).colorScheme;
    final pinCtrl = TextEditingController();
    final opName = operator['name'] as String? ?? 'Operator';
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(Icons.lock_rounded, size: 20, color: scheme.primary),
            const SizedBox(width: 8),
            Text('Verify $opName'),
          ]),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Enter PIN or password to switch user', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'PIN / Password',
                    prefixIcon: const Icon(Icons.password_rounded, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    errorText: error,
                  ),
                  onSubmitted: (_) => _doSwitch(ctx, setSt, pinCtrl, operator, (e) => error = e),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => _doSwitch(ctx, setSt, pinCtrl, operator, (e) => error = e),
              child: const Text('Switch'),
            ),
          ],
        ),
      ),
    );
  }

  void _doSwitch(BuildContext ctx, StateSetter setSt, TextEditingController pinCtrl, Map<String, dynamic> operator, void Function(String?) setError) {
    final pin = pinCtrl.text.trim();
    if (pin.isEmpty) {
      setSt(() => setError('Enter PIN or password'));
      return;
    }

    final storedPin = operator['pin'] as String? ?? operator['password'] as String?;
    if (storedPin != null && pin != storedPin) {
      setSt(() => setError('Incorrect PIN / password'));
      return;
    }

    // Switch user
    ref.read(activeUserProvider.notifier).state = {...operator, 'role': 'operator'};
    ref.invalidate(_profileProvider);
    Navigator.pop(ctx);

    final opId = operator['id'] as String?;
    final online = ref.read(isOnlineProvider);

    if (opId != null) {
      if (online) {
        final db = ref.read(firestorePathsProvider);
        db.operators.doc(opId).update({
          'lastLoginAt': FieldValue.serverTimestamp(),
          'loginCount': FieldValue.increment(1),
        });
        db.sessions.doc(opId).set({
          'userId': opId,
          'role': 'operator',
          'machine': Platform.localHostname,
          'platform': Platform.operatingSystem,
          'ip': _currentIp,
          'startedAt': FieldValue.serverTimestamp(),
          'lastSeenAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        final queue = ref.read(offlineQueueProvider);
        queue.enqueueOperatorUpdate(opId, {
          'lastLoginAt': DateTime.now().toIso8601String(),
          'loginCount': 1,
        });
        queue.enqueueSessionUpdate(opId, {
          'userId': opId,
          'role': 'operator',
          'machine': Platform.localHostname,
          'platform': Platform.operatingSystem,
          'ip': _currentIp,
          'startedAt': DateTime.now().toIso8601String(),
          'lastSeenAt': DateTime.now().toIso8601String(),
        });
      }
    }

    if (online) {
      ref.read(auditServiceProvider).log(
        event: 'userSwitch',
        description: 'Switched to operator: ${operator['name']}',
        user: operator['email'] as String? ?? 'unknown',
      );
    } else {
      ref.read(offlineQueueProvider).enqueueAuditLog({
        'event': 'userSwitch',
        'description': 'Switched to operator: ${operator['name']}',
        'user': operator['email'] as String? ?? 'unknown',
        'machine': Platform.localHostname,
        'timestamp': DateTime.now().toIso8601String(),
        'success': true,
      });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Switched to ${operator['name']}'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ));
    }
  }

  void _verifyAdminAndSwitch() {
    final scheme = Theme.of(context).colorScheme;
    final passCtrl = TextEditingController();
    String? error;

    Future<void> doAdminSwitch(BuildContext ctx, StateSetter setSt) async {
      final pass = passCtrl.text.trim();
      if (pass.isEmpty) {
        setSt(() => error = 'Enter password');
        return;
      }
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && user.email != null) {
          final cred = EmailAuthProvider.credential(email: user.email!, password: pass);
          await user.reauthenticateWithCredential(cred);
        }
        if (ctx.mounted) _completeAdminSwitch(ctx);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'network-request-failed') {
          // Offline — allow switch (admin already authenticated in this session)
          if (ctx.mounted) _completeAdminSwitch(ctx);
        } else {
          setSt(() => error = 'Incorrect password');
        }
      } catch (_) {
        if (ctx.mounted) _completeAdminSwitch(ctx);
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(Icons.admin_panel_settings_rounded, size: 20, color: scheme.primary),
            const SizedBox(width: 8),
            const Text('Switch to Admin'),
          ]),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Enter admin password to switch back', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Admin Password',
                    prefixIcon: const Icon(Icons.lock_rounded, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    errorText: error,
                  ),
                  onSubmitted: (_) => doAdminSwitch(ctx, setSt),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => doAdminSwitch(ctx, setSt),
              child: const Text('Switch'),
            ),
          ],
        ),
      ),
    );
  }

  void _completeAdminSwitch(BuildContext ctx) {
    ref.read(activeUserProvider.notifier).state = null;
    ref.invalidate(_profileProvider);

    final online = ref.read(isOnlineProvider);

    if (online) {
      final db = ref.read(firestorePathsProvider);
      db.adminProfileSettings.set({
        'lastLoginAt': FieldValue.serverTimestamp(),
        'loginCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
      db.sessions.doc('admin').set({
        'userId': 'admin',
        'role': 'admin',
        'machine': Platform.localHostname,
        'platform': Platform.operatingSystem,
        'ip': _currentIp,
        'startedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      ref.read(auditServiceProvider).log(
        event: 'userSwitch',
        description: 'Switched back to admin',
      );
    } else {
      final queue = ref.read(offlineQueueProvider);
      queue.enqueueSessionUpdate('admin', {
        'userId': 'admin',
        'role': 'admin',
        'machine': Platform.localHostname,
        'platform': Platform.operatingSystem,
        'ip': _currentIp,
        'startedAt': DateTime.now().toIso8601String(),
        'lastSeenAt': DateTime.now().toIso8601String(),
      });
      queue.enqueueAuditLog({
        'event': 'userSwitch',
        'description': 'Switched back to admin',
        'machine': Platform.localHostname,
        'timestamp': DateTime.now().toIso8601String(),
        'success': true,
      });
    }

    if (ctx.mounted) Navigator.pop(ctx);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Switched to Admin'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildKycChip(String status, ColorScheme scheme) {
    final (Color bg, Color fg, String label) = switch (status) {
      'verified' => (scheme.primaryContainer, scheme.primary, 'Verified'),
      'pending' => (Colors.amber.withValues(alpha: 0.15), Colors.amber.shade700, 'Pending'),
      'rejected' => (scheme.errorContainer, scheme.error, 'Rejected'),
      _ => (scheme.surfaceContainerHigh, scheme.onSurfaceVariant, 'Not Submitted'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  Widget _buildShiftStatus(ColorScheme scheme, String? shiftStart, String? shiftEnd, List<String>? shiftDays) {
    if (shiftStart == null || shiftEnd == null || shiftDays == null) {
      return Text('--', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant));
    }

    final now = DateTime.now();
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final today = dayNames[now.weekday - 1];
    final isWorkday = shiftDays.contains(today);

    if (!isWorkday) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(4)),
        child: Text('Off duty', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
      );
    }

    final startParts = shiftStart.split(':');
    final endParts = shiftEnd.split(':');
    final startMin = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
    final endMin = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
    final nowMin = now.hour * 60 + now.minute;
    final onShift = nowMin >= startMin && nowMin <= endMin;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: onShift ? scheme.primaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        onShift ? 'On shift' : 'Off hours',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: onShift ? scheme.primary : scheme.error),
      ),
    );
  }

  String _formatTimestamp(dynamic ts) {
    if (ts is Timestamp) return formatTimestamp(ts, ref.read(timeFormatProvider));
    if (ts is String) return ts;
    return '--';
  }

  String _getPasswordAge(dynamic lastChanged) {
    if (lastChanged == null) return 'Never changed';
    DateTime date;
    if (lastChanged is Timestamp) {
      date = lastChanged.toDate();
    } else {
      return 'Unknown';
    }
    final days = DateTime.now().difference(date).inDays;
    if (days == 0) return 'Changed today';
    if (days == 1) return '1 day ago';
    return '$days days ago';
  }

  Future<String> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// REUSABLE WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
// FACE SCAN DIALOG (live video feed + matching)
// ═══════════════════════════════════════════════════════════════════════════════

class _FaceScanDialog extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final void Function(Map<String, dynamic> operator) onMatched;

  const _FaceScanDialog({required this.ref, required this.onMatched});

  @override
  ConsumerState<_FaceScanDialog> createState() => _FaceScanDialogState();
}

class _FaceScanDialogState extends ConsumerState<_FaceScanDialog> {
  Player? _player;
  VideoController? _videoController;
  Timer? _scanTimer;
  Timer? _frameTimer;
  Uint8List? _localFrame;
  bool _isLocalCamera = false;
  bool _capturing = false;
  String _status = 'Initializing camera...';
  bool _cameraReady = false;
  bool _scanning = false;
  bool _matched = false;
  String? _error;
  int _deviceIndex = 0;
  String _matchedName = '';

  String get _frameCachePath {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    final dir = Directory('$home/.weighbridge/frames');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _frameTimer?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    final camSettings = ref.read(_cameraSettingsProvider).valueOrNull ?? {};
    final cameras = camSettings['cameras'] as Map<String, dynamic>?;
    final operatorCam = cameras?['operator'] as Map<String, dynamic>?;

    if (operatorCam != null && operatorCam['enabled'] == true) {
      final source = operatorCam['source'] as String? ?? 'Built-in';
      if (source == 'IP Camera') {
        // IP camera: use RTSP stream via media_kit
        final address = operatorCam['address'] as String? ?? '';
        final port = operatorCam['port'] ?? 554;
        final username = operatorCam['username'] as String? ?? '';
        final password = operatorCam['password'] as String? ?? '';
        if (address.isNotEmpty) {
          final auth = username.isNotEmpty ? '$username:$password@' : '';
          final rtspUrl = 'rtsp://$auth$address:$port/stream';
          _startLiveStream(rtspUrl);
          return;
        }
      }
      // Local camera: determine device index
      final deviceName = source == 'USB'
          ? operatorCam['usbDevice'] as String? ?? ''
          : operatorCam['builtInDevice'] as String? ?? '';
      if (deviceName.isNotEmpty) {
        try {
          final result = await Process.run('system_profiler', ['SPCameraDataType', '-json']);
          if (result.exitCode == 0) {
            final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
            final cams = data['SPCameraDataType'] as List<dynamic>? ?? [];
            final names = cams.map((c) => (c as Map<String, dynamic>)['_name'] as String? ?? '').toList();
            final idx = names.indexOf(deviceName);
            if (idx >= 0) _deviceIndex = idx;
          }
        } catch (_) {}
      }
    }

    // Local camera via avfoundation through media_kit
    _startLocalStream();
  }

  void _startLiveStream(String url) {
    _player = Player();
    _videoController = VideoController(_player!);

    _player!.stream.playing.listen((playing) {
      if (mounted && playing && !_cameraReady) {
        setState(() {
          _cameraReady = true;
          _status = 'Camera active — position your face';
          _error = null;
        });
        _beginAutoScan();
      }
    });

    _player!.stream.error.listen((error) {
      if (mounted && !_cameraReady) {
        setState(() => _error = 'Stream error: check camera connection');
      }
    });

    _player!.open(Media(url), play: true);
    _player!.setVolume(0);
    setState(() {});
  }

  void _startLocalStream() {
    _isLocalCamera = true;
    _captureLocalFrame();
    _frameTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!_matched) _captureLocalFrame();
    });
  }

  Future<void> _captureLocalFrame() async {
    if (_capturing) return;
    _capturing = true;
    final framePath = '$_frameCachePath/face_live.jpg';
    try {
      final result = await Process.run('ffmpeg', [
        '-y',
        '-f', 'avfoundation',
        '-framerate', '30',
        '-i', '$_deviceIndex:none',
        '-frames:v', '1',
        '-update', '1',
        '-q:v', '4',
        framePath,
      ], stdoutEncoding: utf8, stderrEncoding: utf8);

      if (!mounted) return;
      final file = File(framePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty && mounted) {
          setState(() {
            _localFrame = bytes;
            _error = null;
          });
          if (!_cameraReady) {
            setState(() {
              _cameraReady = true;
              _status = 'Camera active — position your face';
            });
            _beginAutoScan();
          }
        }
      } else {
        final err = (result.stderr as String).toLowerCase();
        if (err.contains('permission') || err.contains('denied')) {
          setState(() => _error = 'Camera permission denied. Grant in System Settings > Privacy.');
          _frameTimer?.cancel();
        } else if (err.contains('no such') || err.contains('cannot open')) {
          setState(() => _error = 'Camera not available. Check Settings > Cameras & AI.');
          _frameTimer?.cancel();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'ffmpeg not installed. Install via: brew install ffmpeg');
        _frameTimer?.cancel();
      }
    } finally {
      _capturing = false;
    }
  }

  void _beginAutoScan() {
    // Auto-trigger scan after 2 seconds of live feed
    _scanTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_matched && !_scanning) {
        _performScan();
      }
    });
  }

  void _retryScan() {
    setState(() {
      _scanning = false;
      _status = 'Camera active — position your face';
      _error = null;
    });
    // Re-trigger scan after a brief moment
    _scanTimer?.cancel();
    _scanTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && !_matched) _performScan();
    });
  }

  Future<void> _performScan() async {
    if (_scanning || _matched) return;
    setState(() {
      _scanning = true;
      _status = 'Scanning...';
    });

    // Get all operators with face photos
    final operators = ref.read(_allOperatorsProvider).valueOrNull ?? [];
    final opsWithFaces = operators.where((op) {
      final facePhoto = op['facePhoto'] as String?;
      return facePhoto != null && facePhoto.isNotEmpty;
    }).toList();

    if (opsWithFaces.isEmpty) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _status = 'No operators have face data enrolled';
          _error = 'Enroll operator faces in Operators screen first.';
        });
      }
      return;
    }

    // Capture a frame from the live feed using ffmpeg
    final scanPath = '$_frameCachePath/face_match.jpg';
    try {
      await Process.run('ffmpeg', [
        '-y', '-f', 'avfoundation', '-framerate', '30',
        '-i', '$_deviceIndex:none',
        '-frames:v', '1', '-update', '1', '-q:v', '2',
        scanPath,
      ], stdoutEncoding: utf8, stderrEncoding: utf8);
    } catch (_) {}

    if (!mounted) return;

    final scanFile = File(scanPath);
    if (!await scanFile.exists()) {
      setState(() {
        _scanning = false;
        _status = 'Capture failed — retry scan';
      });
      return;
    }

    final scanBytes = await scanFile.readAsBytes();
    if (scanBytes.isEmpty) {
      setState(() {
        _scanning = false;
        _status = 'Empty capture — retry scan';
      });
      return;
    }

    // Attempt server-side matching if configured
    final camSettings = ref.read(_cameraSettingsProvider).valueOrNull ?? {};
    final aiEndpoint = camSettings['aiEndpoint'] as String? ?? '';

    if (aiEndpoint.isNotEmpty) {
      final matched = await _matchViaServer(aiEndpoint, base64Encode(scanBytes), opsWithFaces);
      if (matched != null && matched.isNotEmpty) {
        _onFaceMatched(matched);
        return;
      }
    }

    // Local matching fallback
    final matched = await _matchLocal(scanBytes, opsWithFaces);
    if (matched != null) {
      _onFaceMatched(matched);
    } else {
      if (mounted) {
        setState(() {
          _scanning = false;
          _status = 'No match found — position face and retry';
        });
      }
    }
  }

  Future<Map<String, dynamic>?> _matchViaServer(String endpoint, String frameBase64, List<Map<String, dynamic>> operators) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final uri = Uri.parse('$endpoint/face/match');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;

      final operatorFaces = operators.map((op) => {
        'id': op['id'],
        'name': op['name'],
        'facePhoto': op['facePhoto'],
      }).toList();

      request.write(jsonEncode({
        'frame': frameBase64,
        'operators': operatorFaces,
      }));

      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final result = jsonDecode(body) as Map<String, dynamic>;
        if (result['matched'] == true) {
          final matchedId = result['operatorId'] as String?;
          if (matchedId != null) {
            return operators.firstWhere((op) => op['id'] == matchedId, orElse: () => <String, dynamic>{});
          }
        }
      }
      client.close();
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _matchLocal(Uint8List scanBytes, List<Map<String, dynamic>> operators) async {
    for (final op in operators) {
      final facePhoto = op['facePhoto'] as String? ?? '';
      if (facePhoto.isEmpty) continue;

      Uint8List? refBytes;
      if (facePhoto.startsWith('/')) {
        final refFile = File(facePhoto);
        if (await refFile.exists()) {
          refBytes = await refFile.readAsBytes();
        }
      } else {
        try {
          refBytes = base64Decode(facePhoto);
        } catch (_) {}
      }

      if (refBytes == null || refBytes.isEmpty) continue;

      final similarity = _computeSimilarity(scanBytes, refBytes);
      if (similarity > 0.85) return op;
    }
    return null;
  }

  double _computeSimilarity(Uint8List a, Uint8List b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final minLen = a.length < b.length ? a.length : b.length;
    final sampleSize = minLen < 1000 ? minLen : 1000;
    int matches = 0;
    for (int i = 0; i < sampleSize; i++) {
      if ((a[i] - b[i]).abs() < 30) matches++;
    }
    return matches / sampleSize;
  }

  void _onFaceMatched(Map<String, dynamic> operator) {
    if (!mounted || _matched) return;
    _scanTimer?.cancel();
    setState(() {
      _matched = true;
      _matchedName = operator['name'] as String? ?? 'Operator';
      _status = 'Match found!';
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) widget.onMatched(operator);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Icon(Icons.face_rounded, size: 20, color: _matched ? Colors.green : scheme.primary),
        const SizedBox(width: 8),
        Text(_matched ? 'Match Found!' : 'Face Recognition'),
      ]),
      content: SizedBox(
        width: 420,
        height: 360,
        child: Column(
          children: [
            // Live camera feed
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: _matched
                        ? Border.all(color: Colors.green, width: 3)
                        : _scanning
                            ? Border.all(color: scheme.primary.withValues(alpha: 0.6), width: 2)
                            : null,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Live video feed (IP camera via media_kit, or local via fast frame capture)
                      if (_videoController != null && !_isLocalCamera)
                        Video(
                          controller: _videoController!,
                          fill: Colors.black,
                          controls: NoVideoControls,
                        )
                      else if (_isLocalCamera && _localFrame != null)
                        Image.memory(
                          _localFrame!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      else
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.camera_alt_rounded, size: 48, color: Colors.white.withValues(alpha: 0.4)),
                              const SizedBox(height: 12),
                              Text(
                                _error ?? 'Connecting to camera...',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),

                      // Face oval overlay
                      if (_cameraReady && !_matched)
                        Center(
                          child: Container(
                            width: 180,
                            height: 220,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _scanning ? scheme.primary : Colors.white.withValues(alpha: 0.5),
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(90),
                            ),
                          ),
                        ),

                      // Scanning indicator
                      if (_scanning && !_matched)
                        Positioned(
                          bottom: 12,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 14, height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('Analyzing...', style: TextStyle(color: Colors.white, fontSize: 11)),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // Match success overlay
                      if (_matched)
                        Container(
                          color: Colors.green.withValues(alpha: 0.2),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_rounded, size: 56, color: Colors.green),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _matchedName,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Status
            Text(
              _status,
              style: text.bodySmall?.copyWith(
                color: _matched ? Colors.green : _error != null ? scheme.error : scheme.onSurfaceVariant,
                fontWeight: _matched ? FontWeight.w700 : FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            if (_error != null && !_cameraReady) ...[
              const SizedBox(height: 8),
              Text(
                'Configure the operator camera in Settings > Cameras & AI',
                style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_matched) ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (_cameraReady && !_scanning)
            FilledButton.icon(
              onPressed: _retryScan,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry Scan'),
            ),
        ],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final IconData icon;
  final String title;
  final ColorScheme scheme;
  final TextTheme text;
  final List<Widget> children;

  const _Card({required this.icon, required this.title, required this.scheme, required this.text, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.15))),
            ),
            child: Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(icon, size: 15, color: scheme.primary),
                ),
                const SizedBox(width: 10),
                Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final ColorScheme scheme;
  final TextTheme text;
  final Widget child;

  const _InfoRow({required this.label, required this.scheme, required this.text, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
        child,
      ],
    );
  }
}
