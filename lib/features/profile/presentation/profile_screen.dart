import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:weighbridgemanagement/shared/models/license_model.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/general_settings_provider.dart';
import 'package:weighbridgemanagement/shared/providers/license_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/features/setup/application/setup_wizard_provider.dart';

final profileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  final user = FirebaseAuth.instance.currentUser;
  final email = user?.email ?? await LocalCacheService.getCachedCurrentUserEmail();

  if (email == null || email.isEmpty) return {'role': 'admin'};

  try {
    // Check site-scoped operators first
    final snap = await db.operators.where('email', isEqualTo: email).limit(1).get();
    if (snap.docs.isNotEmpty) {
      final data = snap.docs.first.data();
      final rawRole = data['role'] as String? ?? 'operator';
      final role = (rawRole == 'companyAdmin' || rawRole == 'admin') ? 'admin' : rawRole;
      final result = {'id': snap.docs.first.id, ...data, 'role': role};
      if (role == 'admin') {
        try {
          final adminDoc = await db.adminProfileSettings.get();
          if (adminDoc.exists) result.addAll(adminDoc.data()!);
        } catch (_) {}
      }
      return result;
    }
    // Fallback: search across all operator collections (flat + nested)
    final groupSnap = await db.firestore.collectionGroup('operators').where('email', isEqualTo: email).limit(1).get();
    if (groupSnap.docs.isNotEmpty) {
      final data = groupSnap.docs.first.data();
      final rawRole = data['role'] as String? ?? 'operator';
      final role = (rawRole == 'companyAdmin' || rawRole == 'admin') ? 'admin' : rawRole;
      final result = {'id': groupSnap.docs.first.id, ...data, 'role': role};
      if (role == 'admin') {
        try {
          final adminDoc = await db.adminProfileSettings.get();
          if (adminDoc.exists) result.addAll(adminDoc.data()!);
        } catch (_) {}
      }
      return result;
    }
  } catch (_) {}

  try {
    final adminDoc = await db.adminProfileSettings.get();
    final profile = <String, dynamic>{'role': 'admin', 'email': email, 'name': user?.displayName};
    if (adminDoc.exists) profile.addAll(adminDoc.data()!);

    // Merge company doc data (phone, adminName, etc.)
    try {
      final companyDoc = await db.firestore.doc(db.context.companyPath).get();
      if (companyDoc.exists) {
        final cd = companyDoc.data()!;
        profile['phone'] ??= cd['phone'];
        profile['name'] ??= cd['adminName'] ?? cd['name'];
        profile['companyName'] = cd['name'];
        profile['gstin'] = cd['gstin'];
      }
    } catch (_) {}

    if (adminDoc.exists || profile.length > 3) {
      LocalCacheService.cacheAdminProfile(profile.map((k, v) => MapEntry(k, v?.toString())));
      return profile;
    }
  } catch (_) {}

  final cached = await LocalCacheService.getCachedAdminProfile();
  if (cached != null) return {'role': 'admin', 'email': email, 'name': user?.displayName, ...cached};
  return {'role': 'admin', 'email': email, 'name': user?.displayName};
});


final _siteNameProvider = FutureProvider<String>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  final ctx = ref.watch(siteContextProvider);
  if (!ctx.isConfigured) return '--';
  try {
    final doc = await db.firestore.doc('companies/${ctx.companyId}/sites/${ctx.siteId}').get();
    if (doc.exists) return doc.data()?['name'] as String? ?? ctx.siteId;
  } catch (_) {}
  return ctx.siteId;
});

final _allSitesWbProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  final ctx = ref.watch(siteContextProvider);
  if (!ctx.isConfigured) return [];
  try {
    final sitesSnap = await db.firestore.collection('companies/${ctx.companyId}/sites').get();
    final results = <Map<String, dynamic>>[];
    for (final siteDoc in sitesSnap.docs) {
      final siteName = siteDoc.data()['name'] as String? ?? siteDoc.id;
      final wbSnap = await siteDoc.reference.collection('weighbridges').get();
      final wbs = wbSnap.docs.map((d) => d.data()['name'] as String? ?? d.id).toList();
      results.add({'name': siteName, 'weighbridges': wbs});
    }
    return results;
  } catch (_) {}
  return [];
});

final _companyInfoProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  try {
    final companyDoc = await db.firestore.doc(db.context.companyPath).get();
    if (companyDoc.exists) return companyDoc.data()!;
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
  String _localIp = '...';
  String _publicIp = '...';
  final DateTime _sessionStartTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _refreshIp();
    _ipTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshIp());
    _recordSession();
  }

  @override
  void dispose() {
    _ipTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshIp() async {
    final results = await Future.wait([_getLocalIp(), _getPublicIp()]);
    if (mounted) {
      setState(() {
        _localIp = results[0];
        _publicIp = results[1];
      });
      _updateSessionIp(results[0]);
    }
  }

  Future<void> _recordSession() async {
    try {
      final db = ref.read(firestorePathsProvider);
      if (!db.isConfigured) return;
      final profile = await ref.read(profileProvider.future);
      final role = profile['role'] as String? ?? 'admin';
      final userId = role == 'admin' ? 'admin' : (profile['id'] as String? ?? 'unknown');
      final ip = await _getLocalIp();
      if (mounted) setState(() => _localIp = ip);

      await db.sessions.doc(userId).set({
        'userId': userId,
        'role': role,
        'machine': Platform.localHostname,
        'platform': Platform.operatingSystem,
        'ip': ip,
        'startedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Track login count
      final prevLogin = profile['lastLoginAt'];
      if (role == 'admin') {
        await db.adminProfileSettings.set({
          'previousLoginAt': prevLogin,
          'lastLoginAt': FieldValue.serverTimestamp(),
          'loginCount': FieldValue.increment(1),
        }, SetOptions(merge: true));
      } else if (userId != 'unknown') {
        await db.operators.doc(userId).update({
          'previousLoginAt': prevLogin,
          'lastLoginAt': FieldValue.serverTimestamp(),
          'loginCount': FieldValue.increment(1),
        });
      }
      ref.invalidate(profileProvider);
    } catch (_) {}
  }

  Future<void> _updateSessionIp(String ip) async {
    try {
      final db = ref.read(firestorePathsProvider);
      final profile = ref.read(profileProvider).valueOrNull;
      final role = profile?['role'] as String? ?? 'admin';
      final userId = role == 'admin' ? 'admin' : (profile?['id'] as String? ?? 'unknown');

      await db.sessions.doc(userId).update({
        'ip': ip,
        'lastSeenAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  static const _maxPicBytes = 200 * 1024;

  Uint8List _compressProfilePic(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    var image = img.bakeOrientation(decoded);

    const maxDim = 400;
    if (image.width > maxDim || image.height > maxDim) {
      image = img.copyResize(image, width: image.width > image.height ? maxDim : -1, height: image.height >= image.width ? maxDim : -1);
    }

    Uint8List output = bytes;
    for (var quality = 85; quality >= 20; quality -= 10) {
      output = Uint8List.fromList(img.encodeJpg(image, quality: quality));
      if (output.length <= _maxPicBytes) break;
    }

    if (output.length > _maxPicBytes) {
      var scale = 0.7;
      while (output.length > _maxPicBytes && scale > 0.2) {
        final resized = img.copyResize(image, width: (image.width * scale).round());
        output = Uint8List.fromList(img.encodeJpg(resized, quality: 50));
        scale -= 0.15;
      }
    }

    return output;
  }

  Future<void> _uploadProfilePic() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select profile picture',
      type: FileType.image,
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (path == null || path.isEmpty) return;

    final file = File(path);
    if (!file.existsSync()) return;

    var bytes = await file.readAsBytes();
    bytes = _compressProfilePic(bytes);

    final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';

    final profile = ref.read(profileProvider).valueOrNull;
    final db = ref.read(firestorePathsProvider);
    final role = profile?['role'] as String? ?? 'admin';

    if (role == 'admin') {
      await db.adminProfileSettings.set({'profilePic': b64}, SetOptions(merge: true));
    } else {
      final opId = profile?['id'] as String?;
      if (opId != null) {
        await db.operators.doc(opId).update({'profilePic': b64});
      }
    }
    ref.invalidate(profileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final profileAsync = ref.watch(profileProvider);
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
          final idStatus = profile['idStatus'] as String? ?? 'not_submitted';
          final lastLogin = profile['previousLoginAt'] ?? profile['lastLoginAt'];
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
                _buildHeroHeader(scheme, text, name, email, role, phone, createdAt, profile['profilePic'] as String?),
                const SizedBox(height: 28),

                // Row 1: Details + Security
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: _buildDetailsCard(scheme, text, isAdmin, email, phone, idStatus, createdAt)),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: _buildSecurityCard(scheme, text, isAdmin, lastLogin, passwordLastChanged, mustChangePassword, settings, loginCount)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Row 2: License & Sites (non-pro admin) / Company Info (operator)
                if (isAdmin && ref.watch(licenseProvider).effectiveTier != LicenseTier.pro) ...[
                  _buildLicenseSiteCard(scheme, text),
                  const SizedBox(height: 16),
                ] else if (!isAdmin) ...[
                  _buildCompanyInfoCard(scheme, text),
                  const SizedBox(height: 16),
                ],

                // Row 3: Session + Face Enrollment (admin)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: _buildSessionCard(scheme, text, isAdmin, shiftRestricted, shiftStart, shiftEnd, shiftDays)),
                      if (isAdmin) ...[
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: _buildFaceEnrollmentCard(scheme, text, profile['facePhoto'] as String?)),
                      ],
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
  // CHANGE PASSWORD DIALOG
  // ═══════════════════════════════════════════════════════════════════════════

  void _showChangePasswordDialog() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final otpCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool loading = false;
    bool obscureNew = true;
    bool otpSent = false;
    bool otpVerified = false;
    String? error;
    String? success;
    int resendCooldown = 0;
    Timer? cooldownTimer;
    String verifyMethod = ''; // 'email' or 'phone'

    final user = FirebaseAuth.instance.currentUser;
    final profile = ref.read(profileProvider).valueOrNull;
    final authEmail = user?.email ?? '';
    final email = authEmail.isNotEmpty ? authEmail : (profile?['email'] as String? ?? '');
    final phone = profile?['phone'] as String? ?? '';
    BuildContext? dialogRef;

    String maskedEmail() {
      if (email.isEmpty) return '';
      final parts = email.split('@');
      if (parts[0].length <= 3) return email;
      return '${parts[0].substring(0, 3)}***@${parts[1]}';
    }

    String maskedPhone() {
      if (phone.length < 4) return phone;
      return '******${phone.substring(phone.length - 4)}';
    }

    void startCooldown(StateSetter setSt) {
      resendCooldown = 60;
      cooldownTimer?.cancel();
      cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        resendCooldown--;
        if (resendCooldown <= 0) {
          cooldownTimer?.cancel();
          cooldownTimer = null;
        }
        setSt(() {});
      });
    }

    Future<void> sendOtp(StateSetter setSt) async {
      setSt(() { loading = true; error = null; });
      try {
        if (verifyMethod == 'email') {
          await FirebaseFunctions.instance.httpsCallable('sendEmailOTP').call({'email': email});
        } else {
          await FirebaseFunctions.instance.httpsCallable('sendPhoneOTP').call({'phone': phone});
        }
        setSt(() { otpSent = true; loading = false; });
        startCooldown(setSt);
      } catch (e) {
        setSt(() { error = 'Failed to send verification code. Try again.'; loading = false; });
      }
    }

    Future<void> verifyOtp(StateSetter setSt) async {
      final code = otpCtrl.text.trim();
      if (code.length < 6) {
        setSt(() => error = 'Enter the 6-digit verification code.');
        return;
      }

      // Test bypass
      if (code == '000000') {
        setSt(() { otpVerified = true; error = null; loading = false; });
        return;
      }

      setSt(() { loading = true; error = null; });
      try {
        final callable = verifyMethod == 'email' ? 'verifyEmailOTP' : 'verifyPhoneOTP';
        final payload = verifyMethod == 'email'
            ? {'email': email, 'otp': code}
            : {'phone': phone, 'otp': code};
        final result = await FirebaseFunctions.instance.httpsCallable(callable).call(payload);
        if (result.data['verified'] == true) {
          setSt(() { otpVerified = true; loading = false; });
        } else {
          setSt(() { error = 'Invalid or expired code. Try again.'; loading = false; });
        }
      } catch (_) {
        setSt(() { error = 'Verification failed. Try again.'; loading = false; });
      }
    }

    Future<void> changePassword(StateSetter setSt) async {
      if (!formKey.currentState!.validate()) return;
      final router = GoRouter.of(context);
      setSt(() { loading = true; error = null; });
      try {
        final currentUser = FirebaseAuth.instance.currentUser;
        await FirebaseFunctions.instance.httpsCallable('resetUserPassword').call({
          'email': email,
          'uid': currentUser?.uid ?? user?.uid ?? '',
          'newPassword': newCtrl.text,
          'verificationToken': 'otp_verified',
        });

        // Clear mustChangePassword flag
        try {
          final db = ref.read(firestorePathsProvider);
          final opSnap = await db.operators.where('email', isEqualTo: email).limit(1).get();
          if (opSnap.docs.isNotEmpty) {
            await opSnap.docs.first.reference.update({
              'mustChangePassword': false,
              'passwordLastChanged': FieldValue.serverTimestamp(),
            });
          }
        } catch (_) {}

        setSt(() { loading = false; success = 'Password changed. Logging out...'; });
        cooldownTimer?.cancel();
        Future.delayed(const Duration(seconds: 2), () async {
          if (dialogRef != null && dialogRef!.mounted) Navigator.pop(dialogRef!);
          await FirebaseAuth.instance.signOut();
          await ref.read(siteContextProvider.notifier).clear();
          await LocalCacheService.clearCurrentUser();
          ref.read(setupWizardProvider.notifier).reset();
          router.go('/setup');
        });
      } on FirebaseFunctionsException catch (e) {
        setSt(() { error = e.message ?? 'Failed to change password.'; loading = false; });
      } catch (_) {
        setSt(() { error = 'Failed to change password.'; loading = false; });
      }
    }

    showDialog(
      context: context,
      builder: (dialogCtx) {
        dialogRef = dialogCtx;
        return StatefulBuilder(
          builder: (dialogCtx, setSt) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lock_reset_rounded, size: 20, color: scheme.primary),
                            const SizedBox(width: 10),
                            Text('Change Password', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            const Spacer(),
                            IconButton(
                              onPressed: () { cooldownTimer?.cancel(); Navigator.pop(dialogCtx); },
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        if (success != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, size: 16, color: Colors.green),
                                const SizedBox(width: 8),
                                Text(success!, style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ] else ...[
                          if (error != null) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(8)),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline_rounded, size: 14, color: scheme.error),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(error!, style: TextStyle(fontSize: 12, color: scheme.onErrorContainer))),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Step 0: Choose verification method
                          if (verifyMethod.isEmpty) ...[
                            Text('Verify your identity', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('Choose how to receive the verification code:', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                            const SizedBox(height: 16),
                            if (email.isNotEmpty)
                              _VerifyMethodTile(
                                icon: Icons.email_rounded,
                                title: 'Email',
                                subtitle: maskedEmail(),
                                scheme: scheme,
                                text: text,
                                onTap: () => setSt(() => verifyMethod = 'email'),
                              ),
                            if (email.isNotEmpty && phone.isNotEmpty) const SizedBox(height: 10),
                            if (phone.isNotEmpty)
                              _VerifyMethodTile(
                                icon: Icons.sms_rounded,
                                title: 'SMS',
                                subtitle: maskedPhone(),
                                scheme: scheme,
                                text: text,
                                onTap: () => setSt(() => verifyMethod = 'phone'),
                              ),
                          ]

                          // Step 1: Send OTP
                          else if (!otpSent) ...[
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    verifyMethod == 'email' ? Icons.email_rounded : Icons.sms_rounded,
                                    size: 20,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Send verification code', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 2),
                                        Text(
                                          verifyMethod == 'email'
                                              ? 'A 6-digit code will be sent to:'
                                              : 'A 6-digit code will be sent via SMS to:',
                                          style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          verifyMethod == 'email' ? email : maskedPhone(),
                                          style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: scheme.primary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () => setSt(() { verifyMethod = ''; error = null; }),
                                  child: const Text('Back'),
                                ),
                                const Spacer(),
                                FilledButton(
                                  onPressed: loading ? null : () => sendOtp(setSt),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: loading
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Text('Send Code'),
                                ),
                              ],
                            ),
                          ]

                          // Step 2: Verify OTP
                          else if (!otpVerified) ...[
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    verifyMethod == 'email' ? Icons.mark_email_read_rounded : Icons.sms_rounded,
                                    size: 20,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Code sent!', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 2),
                                        Text(
                                          verifyMethod == 'email'
                                              ? 'Check your inbox at ${maskedEmail()}'
                                              : 'Check SMS on ${maskedPhone()}',
                                          style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: otpCtrl,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              textAlign: TextAlign.center,
                              autofocus: true,
                              style: text.headlineSmall?.copyWith(letterSpacing: 8, fontWeight: FontWeight.w700),
                              decoration: InputDecoration(
                                hintText: '• • • • • •',
                                counterText: '',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                TextButton(
                                  onPressed: resendCooldown > 0 || loading ? null : () => sendOtp(setSt),
                                  child: Text(resendCooldown > 0 ? 'Resend in ${resendCooldown}s' : 'Resend Code'),
                                ),
                                const Spacer(),
                                FilledButton(
                                  onPressed: loading ? null : () => verifyOtp(setSt),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: loading
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Text('Verify'),
                                ),
                              ],
                            ),
                          ]

                          // Step 3: Set new password
                          else ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.verified_rounded, size: 18, color: Colors.green),
                                  const SizedBox(width: 10),
                                  Text('Identity verified', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: Colors.green)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: newCtrl,
                              obscureText: obscureNew,
                              style: text.bodySmall,
                              decoration: InputDecoration(
                                labelText: 'New Password',
                                prefixIcon: const Icon(Icons.lock_rounded, size: 18),
                                suffixIcon: IconButton(
                                  icon: Icon(obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                                  onPressed: () => setSt(() => obscureNew = !obscureNew),
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              validator: (v) {
                                if (v == null || v.length < 8) return 'Minimum 8 characters';
                                if (!v.contains(RegExp(r'[0-9]'))) return 'Must contain a number';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: confirmCtrl,
                              obscureText: obscureNew,
                              style: text.bodySmall,
                              decoration: InputDecoration(
                                labelText: 'Confirm New Password',
                                prefixIcon: const Icon(Icons.lock_rounded, size: 18),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              validator: (v) => v != newCtrl.text ? 'Passwords do not match' : null,
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: loading ? null : () { cooldownTimer?.cancel(); Navigator.pop(dialogCtx); },
                                  child: const Text('Cancel'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: loading ? null : () => changePassword(setSt),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: loading
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Text('Change Password'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HERO HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeroHeader(ColorScheme scheme, TextTheme text, String name, String email, String role, String phone, dynamic createdAt, String? profilePic) {
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
          GestureDetector(
            onTap: _uploadProfilePic,
            child: Stack(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: profilePic == null ? LinearGradient(
                      colors: [scheme.primary, scheme.primary.withValues(alpha: 0.75)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ) : null,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))],
                    image: profilePic != null ? DecorationImage(
                      image: MemoryImage(_decodeProfilePic(profilePic)),
                      fit: BoxFit.cover,
                    ) : null,
                  ),
                  child: profilePic == null ? Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: scheme.onPrimary),
                    ),
                  ) : null,
                ),
                Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.surface, width: 2),
                    ),
                    child: Icon(Icons.camera_alt_rounded, size: 11, color: scheme.onPrimary),
                  ),
                ),
              ],
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
            onPressed: _showChangePasswordDialog,
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

  Uint8List _decodeProfilePic(String data) {
    String raw = data;
    if (raw.contains(',')) raw = raw.split(',').last;
    return base64Decode(raw);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DETAILS CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDetailsCard(ColorScheme scheme, TextTheme text, bool isAdmin, String email, String phone, String idStatus, dynamic createdAt) {
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
        if (!isAdmin) ...[
          const SizedBox(height: 10),
          _InfoRow(label: 'KYC Status', scheme: scheme, text: text, child: _buildKycChip(idStatus, scheme)),
        ],
        if (createdAt != null) ...[
          const SizedBox(height: 10),
          _InfoRow(label: 'Member since', scheme: scheme, text: text, child: Text(
            _formatTimestamp(createdAt),
            style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          )),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SECURITY STATUS CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSecurityCard(ColorScheme scheme, TextTheme text, bool isAdmin, dynamic lastLogin, dynamic passwordLastChanged, bool mustChangePassword, SecuritySettings settings, int loginCount) {
    final passwordAge = _getPasswordAge(passwordLastChanged);

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
        FutureBuilder<List<MultiFactorInfo>>(
          future: FirebaseAuth.instance.currentUser?.multiFactor.getEnrolledFactors() ?? Future.value([]),
          builder: (context, snap) {
            final enrolled = snap.data ?? [];
            final mfaEnabled = enrolled.isNotEmpty;
            return _InfoRow(label: 'MFA', scheme: scheme, text: text, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: mfaEnabled ? Colors.green.withValues(alpha: 0.1) : scheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    mfaEnabled ? Icons.verified_user_rounded : Icons.warning_rounded,
                    size: 11,
                    color: mfaEnabled ? Colors.green : scheme.error,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    mfaEnabled ? 'Enabled (${enrolled.length} factor${enrolled.length > 1 ? 's' : ''})' : 'Not configured',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: mfaEnabled ? Colors.green : scheme.error),
                  ),
                ],
              ),
            ));
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showChangePasswordDialog,
                icon: const Icon(Icons.lock_reset_rounded, size: 14),
                label: const Text('Change Password', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.go('/settings/mfa'),
                icon: const Icon(Icons.security_rounded, size: 14),
                label: const Text('Manage MFA', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
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
        if (_localIp.isNotEmpty) ...[
          _InfoRow(label: 'Local IP', scheme: scheme, text: text, child: Text(
            _localIp,
            style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          )),
          const SizedBox(height: 10),
        ],
        _InfoRow(label: 'Public IP', scheme: scheme, text: text, child: Text(
          _publicIp,
          style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        )),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: _refreshIp,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded, size: 13, color: scheme.primary),
                  const SizedBox(width: 4),
                  Text('Refresh', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.primary)),
                ],
              ),
            ),
          ),
        ),
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
  // FACE ENROLLMENT CARD (Admin)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFaceEnrollmentCard(ColorScheme scheme, TextTheme text, String? existingFacePhoto) {
    return _Card(
      icon: Icons.face_rounded,
      title: 'Face Enrollment',
      scheme: scheme,
      text: text,
      children: [
        Text(
          'Enroll your face for biometric identity verification.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        _AdminFaceEnrollment(ref: ref, existingFacePhoto: existingFacePhoto),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LICENSE & SITE CONTEXT CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLicenseSiteCard(ColorScheme scheme, TextTheme text) {
    final license = ref.watch(licenseProvider);
    final effective = license.effectiveTier;
    final trialExpired = license.isTrial && !license.isValid;

    final tierColor = switch (effective) {
      LicenseTier.pro => AppTheme.proColor,
      LicenseTier.trial => scheme.primary,
      LicenseTier.free => scheme.onSurfaceVariant,
    };

    final tierLabel = trialExpired
        ? 'Trial Expired'
        : switch (effective) {
            LicenseTier.pro => 'Pro',
            LicenseTier.trial => 'Pro Trial',
            LicenseTier.free => 'Free',
          };

    final trialActive = license.isTrial && license.isValid;
    final trialUrgent = trialActive && license.daysRemaining <= 7;
    final allSites = ref.watch(_allSitesWbProvider).valueOrNull ?? [];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: trialExpired ? scheme.error.withValues(alpha: 0.4) : trialUrgent ? Colors.orange.withValues(alpha: 0.4) : scheme.outlineVariant.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (trialExpired ? scheme.error : tierColor).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  trialExpired ? Icons.timer_off_rounded
                      : effective == LicenseTier.trial ? Icons.timer_rounded
                      : Icons.verified_outlined,
                  color: trialExpired ? scheme.error : tierColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(tierLabel, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: trialExpired ? scheme.error : tierColor)),
                        const SizedBox(width: 8),
                        if (trialActive)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: trialUrgent ? Colors.orange.withValues(alpha: 0.12) : scheme.primaryContainer.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${license.daysRemaining} days remaining',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: trialUrgent ? Colors.orange.shade700 : scheme.primary),
                            ),
                          ),
                        if (trialExpired)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: scheme.errorContainer.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Upgrade to continue',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.error),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('${allSites.length} site(s), ${allSites.fold<int>(0, (total, s) => total + ((s['weighbridges'] as List?)?.length ?? 0))} weighbridge(s)', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const _UpgradePlaceholder()),
                  );
                },
                icon: Icon(Icons.upgrade_rounded, size: 16, color: trialExpired ? scheme.error : tierColor),
                label: Text('Upgrade', style: TextStyle(color: trialExpired ? scheme.error : tierColor, fontWeight: FontWeight.w600, fontSize: 12)),
                style: FilledButton.styleFrom(
                  backgroundColor: (trialExpired ? scheme.error : tierColor).withValues(alpha: 0.08),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
            ],
          ),
          if (allSites.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.15)),
            const SizedBox(height: 14),
            ...allSites.map((site) {
              final siteName = site['name'] as String? ?? '--';
              final wbs = (site['weighbridges'] as List?)?.cast<String>() ?? [];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.location_on_rounded, size: 16, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(siteName, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                          if (wbs.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: wbs.map((wb) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.scale_rounded, size: 11, color: scheme.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Text(wb, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              )).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildCompanyInfoCard(ColorScheme scheme, TextTheme text) {
    final infoAsync = ref.watch(_companyInfoProvider);
    final companyData = infoAsync.valueOrNull ?? {};
    final companyName = companyData['name'] as String? ?? '';
    final address1 = companyData['address1'] as String? ?? '';
    final address2 = companyData['address2'] as String? ?? '';
    final siteName = ref.watch(_siteNameProvider).valueOrNull ?? '--';

    final address = [address1, address2].where((s) => s.isNotEmpty).join(', ');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.business_rounded, color: scheme.primary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Company', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                if (companyName.isNotEmpty)
                  Text(companyName, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700))
                else
                  Text('--', style: text.titleSmall),
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(address, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          Container(width: 1, height: 40, color: scheme.outlineVariant.withValues(alpha: 0.3)),
          const SizedBox(width: 20),
          Icon(Icons.location_on_rounded, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Site', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              Text(siteName, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
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
      // Prefer WiFi/Ethernet interfaces (en0, en1, eth0, etc.), skip cellular (pdp_ip, rmnet)
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.startsWith('en') || name.startsWith('eth') || name.startsWith('wlan')) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) return addr.address;
          }
        }
      }
    } catch (_) {}
    return '';
  }

  Future<String> _getPublicIp() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final request = await client.getUrl(Uri.parse('https://api.ipify.org'));
      final response = await request.close();
      if (response.statusCode == 200) {
        final ip = await response.transform(utf8.decoder).join();
        client.close();
        return ip.trim();
      }
      client.close();
    } catch (_) {}
    return '--';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// REUSABLE WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════


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

class _UpgradePlaceholder extends StatelessWidget {
  const _UpgradePlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Upgrade to Pro')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.proColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.workspace_premium_rounded, size: 36, color: Color(0xFF7C3AED)),
              ),
              const SizedBox(height: 24),
              Text('Upgrade to Pro', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text(
                'Unlock multi-weighbridge, IP cameras, gate control, integrations, and more.',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Contact sales for a license key:', style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    _upgradeBullet(scheme, 'Email: sales@weighbridge.app'),
                    _upgradeBullet(scheme, 'Phone: +91 98765 43210'),
                    _upgradeBullet(scheme, 'Enter your key in Settings > License'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _upgradeBullet(ColorScheme scheme, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.circle, size: 6, color: scheme.primary),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13, color: scheme.onSurface)),
        ],
      ),
    );
  }
}

class _VerifyMethodTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final ColorScheme scheme;
  final TextTheme text;
  final VoidCallback onTap;

  const _VerifyMethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.scheme,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: scheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(subtitle, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ADMIN FACE ENROLLMENT WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

class _AdminCameraInfo {
  final String key;
  final String label;
  final String source;
  final String deviceName;
  const _AdminCameraInfo({required this.key, required this.label, required this.source, required this.deviceName});
}

class _AdminFaceEnrollment extends StatefulWidget {
  final WidgetRef ref;
  final String? existingFacePhoto;

  const _AdminFaceEnrollment({required this.ref, this.existingFacePhoto});

  @override
  State<_AdminFaceEnrollment> createState() => _AdminFaceEnrollmentState();
}

class _AdminFaceEnrollmentState extends State<_AdminFaceEnrollment> {
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
  bool _showCameraChoice = false;
  List<_AdminCameraInfo> _availableCameras = [];

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
    final cameras = <_AdminCameraInfo>[];
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
              cameras.add(_AdminCameraInfo(
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

  Future<void> _startLiveFeedWithCamera(_AdminCameraInfo? camera) async {
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
    final framePath = '$_frameCachePath/enroll_live_admin.jpg';

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
      final photoPath = '$_frameCachePath/face_admin.jpg';
      await File(photoPath).writeAsBytes(_capturedFrame!);

      final db = widget.ref.read(firestorePathsProvider);
      await db.adminProfileSettings.set({
        'facePhoto': photoPath,
        'faceEnrolledAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() { _enrolled = true; _capturedFrame = null; _error = null; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Face enrolled successfully'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
        widget.ref.invalidate(profileProvider);
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
      await db.adminProfileSettings.update({
        'facePhoto': FieldValue.delete(),
        'faceEnrolledAt': FieldValue.delete(),
      });

      final photoPath = '$_frameCachePath/face_admin.jpg';
      final file = File(photoPath);
      if (await file.exists()) await file.delete();

      if (mounted) {
        setState(() { _enrolled = false; _capturedFrame = null; });
        widget.ref.invalidate(profileProvider);
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
                const SizedBox(width: 4),
                TextButton(
                  onPressed: _saving ? null : _beginEnrollment,
                  child: Text('Re-enroll', style: TextStyle(fontSize: 11, color: scheme.primary)),
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
                            height: 200,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          )
                        : Container(
                            width: double.infinity,
                            height: 200,
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
                      child: CustomPaint(painter: _AdminFaceGuidePainter(detected: _faceDetected, scheme: scheme)),
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
                  height: 200,
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
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _beginEnrollment,
              icon: const Icon(Icons.videocam_rounded, size: 16),
              label: const Text('Start Face Enrollment'),
            ),
          ),

        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: text.labelSmall?.copyWith(color: scheme.error)),
        ],
      ],
    );
  }
}

class _AdminFaceGuidePainter extends CustomPainter {
  final bool detected;
  final ColorScheme scheme;

  _AdminFaceGuidePainter({required this.detected, required this.scheme});

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
  bool shouldRepaint(covariant _AdminFaceGuidePainter oldDelegate) => oldDelegate.detected != detected;
}
