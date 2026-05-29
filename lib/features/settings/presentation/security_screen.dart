import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/widgets/pro_feature_banner.dart';
import 'package:intl/intl.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/general_settings_provider.dart';
import 'package:weighbridgemanagement/shared/providers/mfa_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/app_error.dart';
import 'package:weighbridgemanagement/shared/widgets/app_loading.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

// ─── Local persistence ───────────────────────────────────────────────────────

String get _localSettingsPath {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  final dir = Directory('$home/.weighbridge');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return '${dir.path}/security_settings.json';
}

Future<void> _saveLocally(Map<String, dynamic> data) async {
  await File(_localSettingsPath).writeAsString(jsonEncode(data));
}

Future<Map<String, dynamic>> _loadLocally() async {
  try {
    final file = File(_localSettingsPath);
    if (await file.exists()) return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  } catch (_) {}
  return {};
}

// ─── Provider ────────────────────────────────────────────────────────────────

final _securitySettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  try {
    final doc = await db.securitySettings.get();
    if (doc.exists) {
      final data = doc.data()!;
      await _saveLocally(data);
      return data;
    }
  } catch (_) {}
  return _loadLocally();
});

// ─── Screen ──────────────────────────────────────────────────────────────────

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  bool _loaded = false;
  bool _saving = false;
  bool _dirty = false;

  String? _headerMsg;
  bool _headerMsgIsError = false;

  // ── KYC enforcement ──
  bool _requireKycForSensitiveOps = false;

  // ── Role-Based Access ──
  // Admin permissions (all true, non-editable)
  // Operator permissions (configurable)
  bool _opCanVoidWeighment = false;
  bool _opCanEditWeighment = false;
  bool _opCanManualWeight = false;
  bool _opCanReprint = true;
  bool _opCanExportData = false;
  bool _opCanViewReports = true;
  bool _opCanViewCctv = false;
  bool _opCanChangeSettings = false;
  bool _opCanManageCustomers = false;
  bool _opCanManageMaterials = false;
  bool _opCanDeleteRecords = false;
  bool _opCanAccessPrinting = false;
  bool _opCanAccessGateControl = false;
  bool _opCanAccessCameras = false;
  bool _opCanAccessWeighbridge = false;

  // ── Audit Trail ──
  bool _auditEnabled = true;
  int _auditRetentionDays = 365;
  bool _auditLogSettingChanges = true;
  bool _auditLogWeighmentEdits = true;
  bool _auditLogReprints = true;
  bool _auditLogLogins = true;
  bool _auditLogExports = true;

  // ── Data Security ──
  bool _autoLockEnabled = true;
  int _autoLockMinutes = 5;
  bool _encryptBackups = false;
  bool _maskSensitiveFields = true;

  // ── Operator Verification ──
  bool _faceVerifyOnWeighmentStart = false;
  bool _faceVerifyOnSessionStart = false;
  bool _faceVerifyOnDayStart = false;
  bool _shiftBasedLogin = false;
  bool _forcePasswordChangeFirstLogin = true;
  int _passwordExpiryDays = 0; // 0 = never

  // ── Privacy / Archival ──
  bool _anonymizeVehicleOnArchive = false;

  // ── Email Domain Restriction ──
  bool _domainRestrictionEnabled = false;
  final _domainController = TextEditingController();
  List<String> _allowedDomains = [];

  // ── Screen Protection ──
  bool _preventScreenshots = false;
  bool _dimOnInactiveWindow = false;
  bool _watermarkEnabled = false;

  // ── Session & Lockdown ──
  bool _emergencyLockdown = false;
  bool _autoLogoutEnabled = false;
  int _autoLogoutMinutes = 30;
  bool _restrictUsb = false;
  bool _blockRemoteDesktop = false;

  // ── Session Log (loaded from Firestore) ──
  List<Map<String, dynamic>> _sessionLogs = [];

  // ── IP Whitelist ──
  bool _ipWhitelistEnabled = false;
  List<String> _whitelistedIps = [];

  // ── MFA State ──
  bool _mfaLoading = true;
  List<MultiFactorInfo> _mfaFactors = [];
  TotpSecret? _totpSecret;
  bool _mfaEnrolling = false;
  String? _mfaError;
  String? _mfaSuccess;
  final _otpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMfa();
    _loadSessionLogs();
    _loadDomainRestriction();
  }

  Future<void> _loadSessionLogs() async {
    try {
      final db = ref.read(firestorePathsProvider);
      final snap = await db.auditLog
          .where('event', isEqualTo: 'login')
          .orderBy('timestamp', descending: true)
          .limit(10)
          .get();
      if (mounted) {
        setState(() {
          _sessionLogs = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _otpController.dispose();
    _domainController.dispose();
    super.dispose();
  }

  Future<void> _loadMfa() async {
    try {
      final mfa = ref.read(mfaServiceProvider);
      _mfaFactors = await mfa.getEnrolledFactors();
    } catch (_) {}
    if (mounted) setState(() => _mfaLoading = false);
  }

  Future<void> _loadDomainRestriction() async {
    try {
      final paths = ref.read(firestorePathsProvider);
      final companyDoc = await paths.firestore.doc('companies/${paths.context.companyId}').get();
      if (companyDoc.exists && mounted) {
        final data = companyDoc.data()!;
        // Support both old single-string and new array format
        final domainsRaw = data['emailDomainRestrictions'] as List<dynamic>?;
        final legacySingle = data['emailDomainRestriction'] as String?;
        setState(() {
          if (domainsRaw != null && domainsRaw.isNotEmpty) {
            _allowedDomains = domainsRaw.cast<String>();
            _domainRestrictionEnabled = true;
          } else if (legacySingle != null && legacySingle.isNotEmpty) {
            _allowedDomains = [legacySingle];
            _domainRestrictionEnabled = true;
          } else {
            _allowedDomains = [];
            _domainRestrictionEnabled = false;
          }
        });
      }
    } catch (_) {}
  }

  void _addDomain() {
    final domain = _domainController.text.trim().toLowerCase();
    if (domain.isEmpty || _allowedDomains.contains(domain)) return;
    setState(() {
      _allowedDomains.add(domain);
      _domainController.clear();
    });
    _saveDomainRestriction();
  }

  void _removeDomain(String domain) {
    setState(() => _allowedDomains.remove(domain));
    _saveDomainRestriction();
  }

  Future<void> _saveDomainRestriction() async {
    try {
      final paths = ref.read(firestorePathsProvider);
      final domains = _domainRestrictionEnabled ? _allowedDomains : <String>[];
      await paths.firestore.doc('companies/${paths.context.companyId}').set(
        {
          'emailDomainRestrictions': domains,
          'emailDomainRestriction': domains.isNotEmpty ? domains.first : null,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (mounted) _showHeaderMsg('Domain restriction updated');
    } catch (e) {
      if (mounted) _showHeaderMsg('Failed to update: $e', isError: true);
    }
  }

  void _loadData(Map<String, dynamic> data) {
    if (_loaded) return;
    _loaded = true;

    _requireKycForSensitiveOps = data['requireKycForSensitiveOps'] as bool? ?? false;
    _opCanVoidWeighment = data['opCanVoidWeighment'] as bool? ?? false;
    _opCanEditWeighment = data['opCanEditWeighment'] as bool? ?? false;
    _opCanManualWeight = data['opCanManualWeight'] as bool? ?? false;
    _opCanReprint = data['opCanReprint'] as bool? ?? true;
    _opCanExportData = data['opCanExportData'] as bool? ?? false;
    _opCanViewReports = data['opCanViewReports'] as bool? ?? true;
    _opCanViewCctv = data['opCanViewCctv'] as bool? ?? false;
    _opCanChangeSettings = data['opCanChangeSettings'] as bool? ?? false;
    _opCanManageCustomers = data['opCanManageCustomers'] as bool? ?? false;
    _opCanManageMaterials = data['opCanManageMaterials'] as bool? ?? false;
    _opCanDeleteRecords = data['opCanDeleteRecords'] as bool? ?? false;
    _opCanAccessPrinting = data['opCanAccessPrinting'] as bool? ?? false;
    _opCanAccessGateControl = data['opCanAccessGateControl'] as bool? ?? false;
    _opCanAccessCameras = data['opCanAccessCameras'] as bool? ?? false;
    _opCanAccessWeighbridge = data['opCanAccessWeighbridge'] as bool? ?? false;

    _auditEnabled = data['auditEnabled'] as bool? ?? true;
    _auditRetentionDays = data['auditRetentionDays'] as int? ?? 365;
    _auditLogSettingChanges = data['auditLogSettingChanges'] as bool? ?? true;
    _auditLogWeighmentEdits = data['auditLogWeighmentEdits'] as bool? ?? true;
    _auditLogReprints = data['auditLogReprints'] as bool? ?? true;
    _auditLogLogins = data['auditLogLogins'] as bool? ?? true;
    _auditLogExports = data['auditLogExports'] as bool? ?? true;

    _autoLockEnabled = data['autoLockEnabled'] as bool? ?? true;
    _autoLockMinutes = data['autoLockMinutes'] as int? ?? 5;
    _encryptBackups = data['encryptBackups'] as bool? ?? false;
    _maskSensitiveFields = data['maskSensitiveFields'] as bool? ?? true;

    _faceVerifyOnWeighmentStart = data['faceVerifyOnWeighmentStart'] as bool? ?? data['requireFaceVerification'] as bool? ?? false;
    _faceVerifyOnSessionStart = data['faceVerifyOnSessionStart'] as bool? ?? false;
    _faceVerifyOnDayStart = data['faceVerifyOnDayStart'] as bool? ?? false;
    _shiftBasedLogin = data['shiftBasedLogin'] as bool? ?? false;
    _forcePasswordChangeFirstLogin = data['forcePasswordChangeFirstLogin'] as bool? ?? true;
    _passwordExpiryDays = data['passwordExpiryDays'] as int? ?? 0;

    _anonymizeVehicleOnArchive = data['anonymizeVehicleOnArchive'] as bool? ?? false;

    _preventScreenshots = data['preventScreenshots'] as bool? ?? false;
    _dimOnInactiveWindow = data['dimOnInactiveWindow'] as bool? ?? false;
    _watermarkEnabled = data['watermarkEnabled'] as bool? ?? false;

    _emergencyLockdown = data['emergencyLockdown'] as bool? ?? false;
    _autoLogoutEnabled = data['autoLogoutEnabled'] as bool? ?? false;
    _autoLogoutMinutes = data['autoLogoutMinutes'] as int? ?? 30;
    _restrictUsb = data['restrictUsb'] as bool? ?? false;
    _blockRemoteDesktop = data['blockRemoteDesktop'] as bool? ?? false;

    _ipWhitelistEnabled = data['ipWhitelistEnabled'] as bool? ?? false;
    final ips = data['whitelistedIps'] as List<dynamic>?;
    if (ips != null) _whitelistedIps = ips.map((e) => e.toString()).toList();
  }

  void _markDirty() => setState(() => _dirty = true);

  void _showHeaderMsg(String msg, {bool isError = false}) {
    setState(() { _headerMsg = msg; _headerMsgIsError = isError; });
    Future.delayed(Duration(seconds: isError ? 5 : 3), () {
      if (mounted) setState(() => _headerMsg = null);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    // Auto-add current IP if enabling whitelist without including this machine
    if (_ipWhitelistEnabled) {
      final localIps = await getLocalIps();
      final currentIp = localIps.isNotEmpty ? localIps.first : null;
      if (currentIp != null) {
        bool currentIncluded = false;
        for (final entry in _whitelistedIps) {
          if (ipMatchesEntry(currentIp, entry)) { currentIncluded = true; break; }
        }
        if (!currentIncluded) {
          setState(() => _whitelistedIps.add(currentIp));
          if (mounted) _showHeaderMsg('Auto-added your IP ($currentIp) to prevent lockout');
        }
      }
    }

    final data = {
      'requireKycForSensitiveOps': _requireKycForSensitiveOps,
      'opCanVoidWeighment': _opCanVoidWeighment,
      'opCanEditWeighment': _opCanEditWeighment,
      'opCanManualWeight': _opCanManualWeight,
      'opCanReprint': _opCanReprint,
      'opCanExportData': _opCanExportData,
      'opCanViewReports': _opCanViewReports,
      'opCanViewCctv': _opCanViewCctv,
      'opCanChangeSettings': _opCanChangeSettings,
      'opCanManageCustomers': _opCanManageCustomers,
      'opCanManageMaterials': _opCanManageMaterials,
      'opCanDeleteRecords': _opCanDeleteRecords,
      'opCanAccessPrinting': _opCanAccessPrinting,
      'opCanAccessGateControl': _opCanAccessGateControl,
      'opCanAccessCameras': _opCanAccessCameras,
      'opCanAccessWeighbridge': _opCanAccessWeighbridge,
      'auditEnabled': _auditEnabled,
      'auditRetentionDays': _auditRetentionDays,
      'auditLogSettingChanges': _auditLogSettingChanges,
      'auditLogWeighmentEdits': _auditLogWeighmentEdits,
      'auditLogReprints': _auditLogReprints,
      'auditLogLogins': _auditLogLogins,
      'auditLogExports': _auditLogExports,
      'autoLockEnabled': _autoLockEnabled,
      'autoLockMinutes': _autoLockMinutes,
      'encryptBackups': _encryptBackups,
      'maskSensitiveFields': _maskSensitiveFields,
      'faceVerifyOnWeighmentStart': _faceVerifyOnWeighmentStart,
      'faceVerifyOnSessionStart': _faceVerifyOnSessionStart,
      'faceVerifyOnDayStart': _faceVerifyOnDayStart,
      'shiftBasedLogin': _shiftBasedLogin,
      'forcePasswordChangeFirstLogin': _forcePasswordChangeFirstLogin,
      'passwordExpiryDays': _passwordExpiryDays,
      'anonymizeVehicleOnArchive': _anonymizeVehicleOnArchive,
      'preventScreenshots': _preventScreenshots,
      'dimOnInactiveWindow': _dimOnInactiveWindow,
      'watermarkEnabled': _watermarkEnabled,
      'emergencyLockdown': _emergencyLockdown,
      'autoLogoutEnabled': _autoLogoutEnabled,
      'autoLogoutMinutes': _autoLogoutMinutes,
      'restrictUsb': _restrictUsb,
      'blockRemoteDesktop': _blockRemoteDesktop,
      'ipWhitelistEnabled': _ipWhitelistEnabled,
      'whitelistedIps': _whitelistedIps,
    };
    try {
      final db = ref.read(firestorePathsProvider);
      await db.securitySettings.set(data, SetOptions(merge: true));
      await _saveLocally(data);
      ref.read(auditServiceProvider).log(event: 'settingChange', description: 'Security settings updated');
      if (mounted) _showHeaderMsg('Security settings saved');
    } catch (e) {
      await _saveLocally(data);
      if (mounted) _showHeaderMsg('Save failed: $e', isError: true);
    }
    ref.read(securitySettingsOverrideProvider.notifier).state = SecuritySettings.fromMap(data);
    ref.invalidate(_securitySettingsProvider);
    if (mounted) setState(() { _saving = false; _dirty = false; });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final asyncData = ref.watch(_securitySettingsProvider);

    asyncData.whenData(_loadData);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Column(
        children: [
          // ── Header ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                      onPressed: () {
                        context.go('/settings');
                      },
                      style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
                    ),
                    SizedBox(width: AppSpacing.md),
                    Icon(Icons.shield_rounded, size: 20, color: scheme.primary),
                    SizedBox(width: 10.rs),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Security', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text('Access control and audit', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                    const Spacer(),
                    if (_dirty) ...[
                      TextButton(
                        onPressed: () { setState(() { _loaded = false; _dirty = false; }); ref.invalidate(_securitySettingsProvider); },
                        child: const Text('Cancel'),
                      ),
                      SizedBox(width: AppSpacing.sm),
                    ],
                    FilledButton.icon(
                      onPressed: _dirty && !_saving ? _save : null,
                      icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded, size: 16),
                      label: Text(_saving ? 'Saving...' : 'Save'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
                    ),
                  ],
                ),
                if (_headerMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _headerMsgIsError ? scheme.errorContainer.withValues(alpha: 0.6) : AppTheme.successColor.withValues(alpha: 0.1),
                        borderRadius: AppRadius.button,
                        border: Border.all(color: _headerMsgIsError ? scheme.error.withValues(alpha: 0.3) : AppTheme.successColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _headerMsgIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                            size: 15,
                            color: _headerMsgIsError ? scheme.error : AppTheme.successColor,
                          ),
                          SizedBox(width: AppSpacing.sm),
                          Expanded(child: Text(_headerMsg!, style: text.bodySmall?.copyWith(color: _headerMsgIsError ? scheme.error : AppTheme.successColor, fontWeight: FontWeight.w500))),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // ── Body ──
          Expanded(
            child: asyncData.when(
              loading: () => const AppLoading(),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) => SingleChildScrollView(
                padding: AppSpacing.pagePadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ProFeatureBanner(feature: 'Advanced Security'),
                    // Row 1: RBAC + Audit Trail
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildRbacSection(scheme, text)),
                          SizedBox(width: 20.rs),
                          Expanded(child: _buildAuditSection(scheme, text)),
                        ],
                      ),
                    ),
                    SizedBox(height: 20.rs),
                    // Row 2: Data Security + Operator Verification
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildDataSecuritySection(scheme, text)),
                          SizedBox(width: 20.rs),
                          Expanded(child: _buildOperatorVerificationSection(scheme, text)),
                        ],
                      ),
                    ),
                    SizedBox(height: 20.rs),
                    // Row 3: MFA + IP Whitelist
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildMfaSection(scheme, text)),
                          SizedBox(width: 20.rs),
                          Expanded(child: _buildIpWhitelistSection(scheme, text)),
                        ],
                      ),
                    ),
                    SizedBox(height: 20.rs),
                    // Row 4: Screen Protection + Emergency & Session Control
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildScreenProtectionSection(scheme, text)),
                          SizedBox(width: 20.rs),
                          Expanded(child: _buildSessionControlSection(scheme, text)),
                        ],
                      ),
                    ),
                    SizedBox(height: 20.rs),
                    // Row 5: Session Log (full width)
                    _buildSessionLogSection(scheme, text),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ROLE-BASED ACCESS CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRbacSection(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      icon: Icons.admin_panel_settings_rounded,
      title: 'Role-Based Access',
      scheme: scheme,
      text: text,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.2),
            borderRadius: AppRadius.button,
          ),
          child: Row(
            children: [
              Icon(Icons.verified_user_rounded, size: 14, color: scheme.primary),
              SizedBox(width: AppSpacing.sm),
              Text('Admin', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary)),
              const Spacer(),
              Text('Full access to all features', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.md),
        _PermissionToggle(
          label: 'Require ID verification (KYC) for sensitive operations',
          value: _requireKycForSensitiveOps,
          onChanged: (v) { setState(() => _requireKycForSensitiveOps = v); _markDirty(); },
        ),
        if (_requireKycForSensitiveOps)
          Padding(
            padding: const EdgeInsets.only(left: 42, bottom: 8),
            child: Text('Operators must have verified ID to: void, edit, manual weight, export, delete', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
          ),
        SizedBox(height: AppSpacing.md),
        Text('Operator Permissions', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
        SizedBox(height: AppSpacing.sm),
        _PermissionToggle(label: 'Void weighments', value: _opCanVoidWeighment, onChanged: (v) { setState(() => _opCanVoidWeighment = v); _markDirty(); }),
        _PermissionToggle(label: 'Edit weighments', value: _opCanEditWeighment, onChanged: (v) { setState(() => _opCanEditWeighment = v); _markDirty(); }),
        _PermissionToggle(label: 'Manual weight entry (override scale)', value: _opCanManualWeight, onChanged: (v) { setState(() => _opCanManualWeight = v); _markDirty(); }, danger: true),
        _PermissionToggle(label: 'Reprint dockets', value: _opCanReprint, onChanged: (v) { setState(() => _opCanReprint = v); _markDirty(); }),
        _PermissionToggle(label: 'Export data', value: _opCanExportData, onChanged: (v) { setState(() => _opCanExportData = v); _markDirty(); }),
        _PermissionToggle(label: 'View reports', value: _opCanViewReports, onChanged: (v) { setState(() => _opCanViewReports = v); _markDirty(); }),
        _PermissionToggle(label: 'View CCTV snapshots & recordings', value: _opCanViewCctv, onChanged: (v) { setState(() => _opCanViewCctv = v); _markDirty(); }),
        _PermissionToggle(label: 'Access settings page', value: _opCanChangeSettings, onChanged: (v) { setState(() => _opCanChangeSettings = v); _markDirty(); }),
        _PermissionToggle(label: 'Manage customers', value: _opCanManageCustomers, onChanged: (v) { setState(() => _opCanManageCustomers = v); _markDirty(); }),
        _PermissionToggle(label: 'Manage materials', value: _opCanManageMaterials, onChanged: (v) { setState(() => _opCanManageMaterials = v); _markDirty(); }),
        _PermissionToggle(label: 'Delete records', value: _opCanDeleteRecords, onChanged: (v) { setState(() => _opCanDeleteRecords = v); _markDirty(); }, danger: true),
        SizedBox(height: AppSpacing.md),
        Text('Settings Access', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
        SizedBox(height: AppSpacing.sm),
        _PermissionToggle(label: 'Printing settings', value: _opCanAccessPrinting, onChanged: (v) { setState(() => _opCanAccessPrinting = v); _markDirty(); }),
        _PermissionToggle(label: 'Gate control settings', value: _opCanAccessGateControl, onChanged: (v) { setState(() => _opCanAccessGateControl = v); _markDirty(); }),
        _PermissionToggle(label: 'Cameras & AI settings', value: _opCanAccessCameras, onChanged: (v) { setState(() => _opCanAccessCameras = v); _markDirty(); }),
        _PermissionToggle(label: 'Weighbridge settings', value: _opCanAccessWeighbridge, onChanged: (v) { setState(() => _opCanAccessWeighbridge = v); _markDirty(); }),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUDIT TRAIL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAuditSection(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      icon: Icons.history_rounded,
      title: 'Audit Trail',
      scheme: scheme,
      text: text,
      children: [
        Row(
          children: [
            SizedBox(
              height: 20, width: 36,
              child: FittedBox(child: Switch(value: _auditEnabled, onChanged: (v) { setState(() => _auditEnabled = v); _markDirty(); })),
            ),
            SizedBox(width: AppSpacing.sm),
            Text('Enable audit logging', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        if (_auditEnabled) ...[
          SizedBox(height: AppSpacing.md),
          Text('Log events:', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
          SizedBox(height: AppSpacing.sm),
          _PermissionToggle(label: 'Setting changes', value: _auditLogSettingChanges, onChanged: (v) { setState(() => _auditLogSettingChanges = v); _markDirty(); }),
          _PermissionToggle(label: 'Weighment edits/deletions', value: _auditLogWeighmentEdits, onChanged: (v) { setState(() => _auditLogWeighmentEdits = v); _markDirty(); }),
          _PermissionToggle(label: 'Docket reprints', value: _auditLogReprints, onChanged: (v) { setState(() => _auditLogReprints = v); _markDirty(); }),
          _PermissionToggle(label: 'Login/logout events', value: _auditLogLogins, onChanged: (v) { setState(() => _auditLogLogins = v); _markDirty(); }),
          _PermissionToggle(label: 'Data exports', value: _auditLogExports, onChanged: (v) { setState(() => _auditLogExports = v); _markDirty(); }),
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Text('Retention:', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: TextEditingController(text: '$_auditRetentionDays'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) { final n = int.tryParse(v); if (n != null && n > 0) { _auditRetentionDays = n; _markDirty(); } },
                  decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                  style: text.bodySmall,
                ),
              ),
              SizedBox(width: 6.rs),
              Text('days', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          SizedBox(height: 10.rs),
          Text('Audit logs are tamper-proof and cannot be edited by operators.', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DATA SECURITY
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDataSecuritySection(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      icon: Icons.lock_rounded,
      title: 'Data Security',
      scheme: scheme,
      text: text,
      children: [
        Row(
          children: [
            SizedBox(
              height: 20, width: 36,
              child: FittedBox(child: Switch(value: _autoLockEnabled, onChanged: (v) { setState(() => _autoLockEnabled = v); _markDirty(); })),
            ),
            SizedBox(width: AppSpacing.sm),
            Text('Auto-lock screen', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        if (_autoLockEnabled) ...[
          SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              SizedBox(width: 44.rs),
              Text('after', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              SizedBox(width: AppSpacing.sm),
              _ChipGroup(
                value: '${_autoLockMinutes}m',
                options: const ['2m', '5m', '10m', '15m', '30m'],
                onChanged: (v) { setState(() => _autoLockMinutes = int.parse(v.replaceAll('m', ''))); _markDirty(); },
              ),
            ],
          ),
        ],
        SizedBox(height: 14.rs),
        _PermissionToggle(label: 'Encrypt local backups', value: _encryptBackups, onChanged: (v) { setState(() => _encryptBackups = v); _markDirty(); }),
        SizedBox(height: AppSpacing.xs),
        _PermissionToggle(label: 'Mask sensitive fields for operators', value: _maskSensitiveFields, onChanged: (v) { setState(() => _maskSensitiveFields = v); _markDirty(); }),
        SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.only(left: 44),
          child: Text('Phone, PAN, Aadhaar hidden for non-admin roles', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
        ),
        SizedBox(height: 14.rs),
        _PermissionToggle(label: 'Anonymize vehicle number on archive', value: _anonymizeVehicleOnArchive, onChanged: (v) { setState(() => _anonymizeVehicleOnArchive = v); _markDirty(); }),
        Padding(
          padding: const EdgeInsets.only(left: 44),
          child: Text('When a customer is archived, also replace vehicle numbers on their weighments with [Archived]', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OPERATOR VERIFICATION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildOperatorVerificationSection(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      icon: Icons.fingerprint_rounded,
      title: 'Operator Verification',
      scheme: scheme,
      text: text,
      children: [
        _PermissionToggle(label: 'Face verify on each weighment start', value: _faceVerifyOnWeighmentStart, onChanged: (v) { setState(() => _faceVerifyOnWeighmentStart = v); _markDirty(); }),
        SizedBox(height: AppSpacing.xs),
        _PermissionToggle(label: 'Face verify on session start (once per login)', value: _faceVerifyOnSessionStart, onChanged: (v) { setState(() => _faceVerifyOnSessionStart = v); _markDirty(); }),
        SizedBox(height: AppSpacing.xs),
        _PermissionToggle(label: 'Face verify on day start (once per calendar day)', value: _faceVerifyOnDayStart, onChanged: (v) { setState(() => _faceVerifyOnDayStart = v); _markDirty(); }),
        SizedBox(height: AppSpacing.xs),
        _PermissionToggle(label: 'Shift-based login only', value: _shiftBasedLogin, onChanged: (v) { setState(() => _shiftBasedLogin = v); _markDirty(); }),
        SizedBox(height: AppSpacing.xs),
        _PermissionToggle(label: 'Force password change on first login', value: _forcePasswordChangeFirstLogin, onChanged: (v) { setState(() => _forcePasswordChangeFirstLogin = v); _markDirty(); }),
        SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Text('Password expiry:', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            SizedBox(width: AppSpacing.sm),
            _ChipGroup(
              value: _passwordExpiryDays == 0 ? 'never' : '${_passwordExpiryDays}d',
              options: const ['never', '30d', '60d', '90d'],
              onChanged: (v) { setState(() => _passwordExpiryDays = v == 'never' ? 0 : int.parse(v.replaceAll('d', ''))); _markDirty(); },
            ),
          ],
        ),
        SizedBox(height: 18.rs),
        Divider(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        SizedBox(height: 14.rs),
        Text('Email Domain Restriction', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
        SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            SizedBox(
              height: 20, width: 36,
              child: FittedBox(child: Switch(
                value: _domainRestrictionEnabled,
                onChanged: (v) {
                  setState(() => _domainRestrictionEnabled = v);
                  if (!v) {
                    _allowedDomains.clear();
                    _saveDomainRestriction();
                  }
                },
              )),
            ),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('Restrict operators to allowed email domains', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
          ],
        ),
        if (_domainRestrictionEnabled) ...[
          SizedBox(height: 10.rs),
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_allowedDomains.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _allowedDomains.map((domain) => Chip(
                      label: Text('@$domain', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                      deleteIcon: Icon(Icons.close_rounded, size: 14, color: scheme.error),
                      onDeleted: () => _removeDomain(domain),
                      backgroundColor: scheme.primaryContainer.withValues(alpha: 0.3),
                      side: BorderSide(color: scheme.primary.withValues(alpha: 0.2)),
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    )).toList(),
                  ),
                  SizedBox(height: 10.rs),
                ],
                Row(
                  children: [
                    Text('@', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary)),
                    SizedBox(width: 6.rs),
                    SizedBox(
                      width: 180,
                      child: TextField(
                        controller: _domainController,
                        decoration: InputDecoration(
                          hintText: 'company.com',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: AppRadius.button),
                        ),
                        style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                        onSubmitted: (_) => _addDomain(),
                      ),
                    ),
                    SizedBox(width: AppSpacing.sm),
                    FilledButton.icon(
                      onPressed: _addDomain,
                      icon: const Icon(Icons.add_rounded, size: 14),
                      label: const Text('Add'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), textStyle: const TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
                SizedBox(height: AppSpacing.sm),
                Text(
                  'New operators must use one of the allowed domains. Existing operators are not affected.',
                  style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MFA SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMfaSection(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      icon: Icons.security_rounded,
      title: 'Two-Factor Authentication',
      scheme: scheme,
      text: text,
      children: [
        if (_mfaLoading)
          const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)))
        else ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _mfaFactors.isNotEmpty ? const Color(0xFFE8F5E9) : scheme.surfaceContainerLow,
              borderRadius: AppRadius.button,
            ),
            child: Row(
              children: [
                Icon(
                  _mfaFactors.isNotEmpty ? Icons.verified_user_rounded : Icons.shield_outlined,
                  size: 18,
                  color: _mfaFactors.isNotEmpty ? const Color(0xFF2E7D32) : scheme.onSurfaceVariant,
                ),
                SizedBox(width: 10.rs),
                Expanded(
                  child: Text(
                    _mfaFactors.isNotEmpty ? 'MFA Enabled' : 'MFA Not Enabled',
                    style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: _mfaFactors.isNotEmpty ? const Color(0xFF2E7D32) : scheme.onSurfaceVariant),
                  ),
                ),
                if (_mfaFactors.isEmpty && _totpSecret == null)
                  OutlinedButton.icon(
                    onPressed: _mfaEnrolling ? null : _startMfaEnrollment,
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Enable'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 11)),
                  ),
              ],
            ),
          ),
          if (_mfaError != null) ...[
            SizedBox(height: AppSpacing.sm),
            Container(
              padding: EdgeInsets.all(8.rs),
              decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: AppRadius.chip),
              child: Text(_mfaError!, style: const TextStyle(fontSize: 11, color: Color(0xFFC62828))),
            ),
          ],
          if (_mfaSuccess != null) ...[
            SizedBox(height: AppSpacing.sm),
            Container(
              padding: EdgeInsets.all(8.rs),
              decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: AppRadius.chip),
              child: Text(_mfaSuccess!, style: const TextStyle(fontSize: 11, color: Color(0xFF1B5E20))),
            ),
          ],
          if (_totpSecret != null) ...[
            SizedBox(height: AppSpacing.md),
            Text('Manual key:', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
            SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: AppRadius.chip),
              child: Row(
                children: [
                  Expanded(child: SelectableText(_totpSecret!.secretKey, style: const TextStyle(fontFamily: 'Courier', fontSize: 11, fontWeight: FontWeight.w600))),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    onPressed: () { Clipboard.setData(ClipboardData(text: _totpSecret!.secretKey)); },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  ),
                ],
              ),
            ),
            SizedBox(height: 10.rs),
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 3),
                    decoration: const InputDecoration(hintText: '000000', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                  ),
                ),
                SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: _mfaEnrolling ? null : _finalizeMfaEnrollment,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), textStyle: const TextStyle(fontSize: 11)),
                  child: const Text('Verify'),
                ),
                SizedBox(width: AppSpacing.xs),
                TextButton(
                  onPressed: () => setState(() { _totpSecret = null; _mfaError = null; }),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), textStyle: const TextStyle(fontSize: 11)),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
          if (_mfaFactors.isNotEmpty) ...[
            SizedBox(height: 10.rs),
            ..._mfaFactors.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF2E7D32)),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(f.displayName ?? 'Authenticator App', style: text.bodySmall)),
                  InkWell(
                    onTap: () => _removeMfaFactor(f),
                    child: Padding(padding: EdgeInsets.all(4.rs), child: Icon(Icons.close_rounded, size: 14, color: scheme.error)),
                  ),
                ],
              ),
            )),
          ],
        ],
      ],
    );
  }

  Future<void> _startMfaEnrollment() async {
    setState(() { _mfaEnrolling = true; _mfaError = null; _mfaSuccess = null; });
    try {
      final mfa = ref.read(mfaServiceProvider);
      _totpSecret = await mfa.enrollTotp();
    } catch (e) {
      _mfaError = 'Failed to generate secret. Re-authenticate and try again.';
    }
    if (mounted) setState(() => _mfaEnrolling = false);
  }

  Future<void> _finalizeMfaEnrollment() async {
    if (_otpController.text.length != 6) {
      setState(() => _mfaError = 'Enter a valid 6-digit code.');
      return;
    }
    setState(() { _mfaEnrolling = true; _mfaError = null; });
    try {
      final mfa = ref.read(mfaServiceProvider);
      await mfa.finalizeEnrollment(_totpSecret!, _otpController.text.trim());
      _totpSecret = null;
      _otpController.clear();
      _mfaSuccess = 'MFA enrolled successfully!';
      await _loadMfa();
    } on FirebaseAuthException catch (e) {
      _mfaError = e.code == 'invalid-verification-code' ? 'Invalid code.' : 'Enrollment failed: ${e.message}';
    } catch (e) {
      _mfaError = 'Enrollment failed.';
    }
    if (mounted) setState(() => _mfaEnrolling = false);
  }

  Future<void> _removeMfaFactor(MultiFactorInfo factor) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove MFA'),
        content: const Text('Disable two-factor authentication?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error), child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final mfa = ref.read(mfaServiceProvider);
      await mfa.unenrollFactor(factor);
      _mfaSuccess = 'MFA removed.';
      await _loadMfa();
    } catch (_) {
      setState(() => _mfaError = 'Failed to remove. Re-authenticate.');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // IP WHITELIST
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildIpWhitelistSection(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      icon: Icons.lan_rounded,
      title: 'IP Whitelist',
      scheme: scheme,
      text: text,
      children: [
        Row(
          children: [
            SizedBox(
              height: 20, width: 36,
              child: FittedBox(child: Switch(value: _ipWhitelistEnabled, onChanged: (v) { setState(() => _ipWhitelistEnabled = v); _markDirty(); })),
            ),
            SizedBox(width: AppSpacing.sm),
            Text('Restrict access to allowed IPs', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        if (_ipWhitelistEnabled) ...[
          SizedBox(height: AppSpacing.md),
          FutureBuilder<Map<String, List<String>>>(
            future: _detectCurrentIps(),
            builder: (ctx, snap) {
              if (!snap.hasData) {
                return Row(children: [
                  SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: scheme.primary)),
                  SizedBox(width: AppSpacing.sm),
                  Text('Detecting IP...', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                ]);
              }
              final publicIp = snap.data!['public']?.firstOrNull;
              final localIps = snap.data!['local'] ?? [];
              return Container(
                padding: EdgeInsets.all(10.rs),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.15),
                  borderRadius: AppRadius.button,
                  border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your current IPs:', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary)),
                    SizedBox(height: AppSpacing.xs),
                    if (publicIp != null)
                      Row(children: [
                        Icon(Icons.public_rounded, size: 12, color: scheme.primary),
                        SizedBox(width: 6.rs),
                        Text('Public: ', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                        Text(publicIp, style: text.bodySmall?.copyWith(fontFamily: 'Courier', fontWeight: FontWeight.w700)),
                      ]),
                    if (localIps.isNotEmpty) ...[
                      SizedBox(height: 2.rs),
                      Row(children: [
                        Icon(Icons.wifi_rounded, size: 12, color: scheme.onSurfaceVariant),
                        SizedBox(width: 6.rs),
                        Text('Local: ', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                        Text(localIps.join(', '), style: text.bodySmall?.copyWith(fontFamily: 'Courier')),
                      ]),
                    ],
                  ],
                ),
              );
            },
          ),
          SizedBox(height: AppSpacing.md),
          ..._whitelistedIps.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(Icons.computer_rounded, size: 14, color: scheme.onSurfaceVariant),
                SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(e.value, style: text.bodySmall?.copyWith(fontFamily: 'Courier'))),
                InkWell(
                  onTap: () { setState(() => _whitelistedIps.removeAt(e.key)); _markDirty(); },
                  child: Padding(padding: EdgeInsets.all(4.rs), child: Icon(Icons.close_rounded, size: 14, color: scheme.error)),
                ),
              ],
            ),
          )),
          SizedBox(height: 6.rs),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _addIpDialog(scheme, text),
                icon: const Icon(Icons.add_rounded, size: 14),
                label: const Text('Add IP / Subnet'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 11)),
              ),
              OutlinedButton.icon(
                onPressed: _addCurrentIp,
                icon: const Icon(Icons.my_location_rounded, size: 14),
                label: const Text('Add This PC'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 11)),
              ),
              OutlinedButton.icon(
                onPressed: _addCurrentSubnet,
                icon: const Icon(Icons.hub_rounded, size: 14),
                label: const Text('Add LAN Subnet'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 11)),
              ),
            ],
          ),
          SizedBox(height: 10.rs),
          Text(
            'Supports: exact IP, CIDR (192.168.1.0/24), range (192.168.1.10-192.168.1.50), wildcard (192.168.1.*)',
            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }

  Future<Map<String, List<String>>> _detectCurrentIps() async {
    final localIps = await getLocalIps();
    final publicIp = await getPublicIp();
    return {
      'local': localIps,
      if (publicIp != null) 'public': [publicIp],
    };
  }

  Future<void> _addCurrentIp() async {
    try {
      final localIps = await getLocalIps();
      if (localIps.isEmpty) return;
      final ip = localIps.first;
      if (!_whitelistedIps.contains(ip)) {
        setState(() => _whitelistedIps.add(ip));
        _markDirty();
      }
    } catch (_) {}
  }

  Future<void> _addCurrentSubnet() async {
    try {
      final localIps = await getLocalIps();
      if (localIps.isEmpty) return;
      final ip = localIps.first;
      final parts = ip.split('.');
      if (parts.length != 4) return;
      final subnet = '${parts[0]}.${parts[1]}.${parts[2]}.0/24';
      if (!_whitelistedIps.contains(subnet)) {
        setState(() => _whitelistedIps.add(subnet));
        _markDirty();
      }
    } catch (_) {}
  }

  void _addIpDialog(ColorScheme scheme, TextTheme text) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add IP / Subnet'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(hintText: '192.168.1.0/24', isDense: true),
                autofocus: true,
              ),
              SizedBox(height: 10.rs),
              Text('Examples:', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
              SizedBox(height: AppSpacing.xs),
              Text('192.168.1.100  — single PC', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontFamily: 'Courier')),
              Text('192.168.1.0/24  — entire LAN', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontFamily: 'Courier')),
              Text('192.168.1.10-192.168.1.50  — range', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontFamily: 'Courier')),
              Text('192.168.1.*  — wildcard', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontFamily: 'Courier')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final ip = ctrl.text.trim();
            if (ip.isNotEmpty && !_whitelistedIps.contains(ip)) {
              setState(() => _whitelistedIps.add(ip));
              _markDirty();
            }
            Navigator.pop(ctx);
          }, child: const Text('Add')),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN PROTECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildScreenProtectionSection(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      icon: Icons.screenshot_monitor_rounded,
      title: 'Screen Protection',
      scheme: scheme,
      text: text,
      children: [
        if (Platform.isWindows) ...[
          _PermissionToggle(
            label: 'Prevent screenshots (blank screen on capture)',
            value: _preventScreenshots,
            onChanged: (v) { setState(() => _preventScreenshots = v); _markDirty(); },
          ),
          SizedBox(height: AppSpacing.xs),
        ],
        _PermissionToggle(
          label: 'Dim content when window is inactive',
          value: _dimOnInactiveWindow,
          onChanged: (v) { setState(() => _dimOnInactiveWindow = v); _markDirty(); },
        ),
        SizedBox(height: AppSpacing.xs),
        _PermissionToggle(
          label: 'Overlay watermark (operator name + timestamp)',
          value: _watermarkEnabled,
          onChanged: (v) { setState(() => _watermarkEnabled = v); _markDirty(); },
        ),
        SizedBox(height: AppSpacing.md),
        Container(
          padding: EdgeInsets.all(10.rs),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: AppRadius.button,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How it works:', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
              SizedBox(height: 6.rs),
              if (Platform.isWindows) ...[
                _infoRow(Icons.screenshot_rounded, 'Screenshots: Window appears black in all screen captures & recordings', text, scheme),
                SizedBox(height: AppSpacing.xs),
              ],
              _infoRow(Icons.visibility_off_rounded, 'Inactive dimming: Obscures data when app loses focus, deters shoulder-surfing', text, scheme),
              SizedBox(height: AppSpacing.xs),
              _infoRow(Icons.water_drop_rounded, 'Watermark: Visible operator identity overlay makes photos traceable', text, scheme),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.sm),
        Text('Note: No software can fully prevent external camera capture. Watermark + audit trail provides accountability.', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, TextTheme text, ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 12, color: scheme.primary),
        SizedBox(width: 6.rs),
        Expanded(child: Text(label, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.3))),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SESSION CONTROL & EMERGENCY LOCKDOWN
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSessionControlSection(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      icon: Icons.power_settings_new_rounded,
      title: 'Session & Lockdown',
      scheme: scheme,
      text: text,
      children: [
        // Emergency Lockdown
        Container(
          padding: EdgeInsets.all(12.rs),
          decoration: BoxDecoration(
            color: _emergencyLockdown ? scheme.errorContainer.withValues(alpha: 0.3) : scheme.surfaceContainerLow,
            borderRadius: AppRadius.button,
            border: _emergencyLockdown ? Border.all(color: scheme.error.withValues(alpha: 0.4)) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_emergencyLockdown ? Icons.lock_rounded : Icons.lock_open_rounded, size: 16, color: _emergencyLockdown ? scheme.error : scheme.onSurfaceVariant),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text('Emergency Lockdown', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: _emergencyLockdown ? scheme.error : scheme.onSurface))),
                  FilledButton(
                    onPressed: () => _toggleLockdown(scheme),
                    style: FilledButton.styleFrom(
                      backgroundColor: _emergencyLockdown ? scheme.error : scheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                    child: Text(_emergencyLockdown ? 'Deactivate' : 'Activate'),
                  ),
                ],
              ),
              SizedBox(height: 6.rs),
              Text(
                _emergencyLockdown
                    ? 'ACTIVE: All operator sessions locked out. Only admin can deactivate.'
                    : 'Instantly locks all operator sessions and blocks new logins.',
                style: text.labelSmall?.copyWith(color: _emergencyLockdown ? scheme.error : scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        SizedBox(height: 14.rs),
        // Auto-logout vs lock
        Text('Inactivity behavior:', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
        SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            SizedBox(
              height: 20, width: 36,
              child: FittedBox(child: Switch(value: _autoLogoutEnabled, onChanged: (v) { setState(() => _autoLogoutEnabled = v); _markDirty(); })),
            ),
            SizedBox(width: AppSpacing.sm),
            Text('Full logout on inactivity', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        if (_autoLogoutEnabled) ...[
          SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              SizedBox(width: 44.rs),
              Text('after', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              SizedBox(width: AppSpacing.sm),
              _ChipGroup(
                value: '${_autoLogoutMinutes}m',
                options: const ['15m', '30m', '60m', '120m'],
                onChanged: (v) { setState(() => _autoLogoutMinutes = int.parse(v.replaceAll('m', ''))); _markDirty(); },
              ),
            ],
          ),
        ],
        if (!_autoLogoutEnabled)
          Padding(
            padding: const EdgeInsets.only(left: 44, top: 4),
            child: Text('Screen lock (PIN to resume) is used instead', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
          ),
        SizedBox(height: 14.rs),
        // USB restriction
        _PermissionToggle(
          label: 'Restrict USB storage access',
          value: _restrictUsb,
          onChanged: (v) { setState(() => _restrictUsb = v); _markDirty(); },
        ),
        Padding(
          padding: const EdgeInsets.only(left: 44),
          child: Text('Blocks data copy to external USB drives', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
        ),
        SizedBox(height: AppSpacing.sm),
        // Remote desktop blocking
        _PermissionToggle(
          label: 'Block remote desktop software',
          value: _blockRemoteDesktop,
          onChanged: (v) { setState(() => _blockRemoteDesktop = v); _markDirty(); },
        ),
        Padding(
          padding: const EdgeInsets.only(left: 44),
          child: Text('Detects and blocks AnyDesk, TeamViewer, Chrome Remote, etc.', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
        ),
      ],
    );
  }

  void _toggleLockdown(ColorScheme scheme) {
    if (_emergencyLockdown) {
      setState(() => _emergencyLockdown = false);
      _saveLockdownImmediate(false);
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(children: [Icon(Icons.warning_rounded, color: scheme.error), SizedBox(width: AppSpacing.sm), const Text('Emergency Lockdown')]),
          content: const Text('This will immediately lock out ALL operator sessions and prevent new operator logins. Only admin accounts will retain access.\n\nAre you sure?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _emergencyLockdown = true);
                _saveLockdownImmediate(true);
              },
              style: FilledButton.styleFrom(backgroundColor: scheme.error),
              child: const Text('Activate Lockdown'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _saveLockdownImmediate(bool active) async {
    try {
      final db = ref.read(firestorePathsProvider);
      await db.securitySettings.set({'emergencyLockdown': active}, SetOptions(merge: true));
      ref.read(securitySettingsOverrideProvider.notifier).state = null;
      ref.invalidate(_securitySettingsProvider);
      if (mounted) _showHeaderMsg(active ? 'Emergency lockdown ACTIVATED' : 'Lockdown deactivated');
    } catch (e) {
      if (mounted) _showHeaderMsg('Failed to update lockdown: $e', isError: true);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SESSION LOG
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSessionLogSection(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      icon: Icons.list_alt_rounded,
      title: 'Recent Sessions',
      scheme: scheme,
      text: text,
      children: [
        if (_sessionLogs.isEmpty)
          Container(
            width: double.infinity,
            padding: AppSpacing.cardPadding,
            decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: AppRadius.button),
            child: Text('No session logs recorded yet.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
          )
        else
          Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.button,
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                // Header row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text('User', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700))),
                      Expanded(flex: 2, child: Text('Time', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700))),
                      Expanded(flex: 2, child: Text('Machine / IP', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700))),
                      Expanded(flex: 1, child: Text('Status', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700))),
                    ],
                  ),
                ),
                // Data rows
                ..._sessionLogs.asMap().entries.map((entry) {
                  final log = entry.value;
                  final isLast = entry.key == _sessionLogs.length - 1;
                  final user = log['user'] as String? ?? log['email'] as String? ?? 'Unknown';
                  final timestamp = log['timestamp'];
                  String timeStr = '';
                  if (timestamp is Timestamp) {
                    timeStr = formatTimestamp(timestamp, ref.read(timeFormatProvider), dateFormat: 'dd MMM');
                  } else if (timestamp is String) {
                    timeStr = timestamp;
                  }
                  final machine = log['machine'] as String? ?? log['ip'] as String? ?? '—';
                  final success = log['success'] as bool? ?? true;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: isLast ? null : Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.1))),
                    ),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: Text(user, style: text.bodySmall, overflow: TextOverflow.ellipsis)),
                        Expanded(flex: 2, child: Text(timeStr, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
                        Expanded(flex: 2, child: Text(machine, style: text.bodySmall?.copyWith(fontFamily: 'Courier', fontSize: 11))),
                        Expanded(flex: 1, child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: success ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(4.rs),
                          ),
                          child: Text(
                            success ? 'OK' : 'Failed',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: success ? const Color(0xFF2E7D32) : const Color(0xFFC62828)),
                            textAlign: TextAlign.center,
                          ),
                        )),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        SizedBox(height: 10.rs),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _loadSessionLogs,
              icon: const Icon(Icons.refresh_rounded, size: 14),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 11)),
            ),
            SizedBox(width: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _exportAuditLogCsv,
              icon: const Icon(Icons.download_rounded, size: 14),
              label: const Text('Export CSV'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _exportAuditLogCsv() async {
    final chosen = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose export location for audit log',
    );
    if (chosen == null || chosen.isEmpty) return;
    final exportPath = chosen.endsWith('/') ? chosen.substring(0, chosen.length - 1) : chosen;

    try {
      final db = ref.read(firestorePathsProvider);
      final snap = await db.auditLog
          .orderBy('timestamp', descending: true)
          .limit(5000)
          .get();

      final buffer = StringBuffer();
      buffer.writeln('Event,Description,User,Machine,IP,Timestamp,Success');

      for (final doc in snap.docs) {
        final d = doc.data();
        final event = _csvEscape(d['event'] as String? ?? '');
        final desc = _csvEscape(d['description'] as String? ?? '');
        final user = _csvEscape(d['user'] as String? ?? '');
        final machine = _csvEscape(d['machine'] as String? ?? '');
        final ip = _csvEscape(d['ip'] as String? ?? '');
        final ts = d['timestamp'];
        String timeStr = '';
        if (ts is Timestamp) {
          timeStr = formatTimestamp(ts, ref.read(timeFormatProvider), dateFormat: 'yyyy-MM-dd');
        }
        final success = d['success'] == true ? 'Yes' : 'No';
        buffer.writeln('$event,$desc,$user,$machine,$ip,$timeStr,$success');
      }

      final filePath = '$exportPath/audit_log_${DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now())}.csv';
      await File(filePath).writeAsString(buffer.toString());

      if (mounted) {
        AppError.success(context, 'Audit log exported: $filePath (${snap.docs.length} entries)');
      }
    } catch (e) {
      if (mounted) {
        AppError.show(context, 'Export failed: $e');
      }
    }
  }

  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// REUSABLE WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final ColorScheme scheme;
  final TextTheme text;
  final List<Widget> children;

  const _SectionCard({required this.icon, required this.title, required this.scheme, required this.text, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.dialog,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.15))),
            ),
            child: Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(7.rs)),
                  child: Icon(icon, size: 15, color: scheme.primary),
                ),
                SizedBox(width: 10.rs),
                Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2)),
              ],
            ),
          ),
          Padding(
            padding: AppSpacing.pagePadding,
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

class _PermissionToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool danger;

  const _PermissionToggle({required this.label, required this.value, required this.onChanged, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            height: 18, width: 32,
            child: FittedBox(child: Switch(value: value, onChanged: onChanged, activeTrackColor: danger ? scheme.error.withValues(alpha: 0.3) : null, activeThumbColor: danger ? scheme.error : null)),
          ),
          SizedBox(width: 10.rs),
          Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: danger ? scheme.error : scheme.onSurface))),
        ],
      ),
    );
  }
}

class _ChipGroup extends StatelessWidget {
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _ChipGroup({required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: options.map((opt) {
        final selected = opt == value;
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: GestureDetector(
            onTap: () => onChanged(opt),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? scheme.primaryContainer : Colors.transparent,
                borderRadius: AppRadius.chip,
                border: Border.all(color: selected ? scheme.primary.withValues(alpha: 0.4) : scheme.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Text(opt, style: TextStyle(fontSize: 10, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? scheme.primary : scheme.onSurfaceVariant)),
            ),
          ),
        );
      }).toList(),
    );
  }
}
