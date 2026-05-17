import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/features/setup/application/setup_wizard_provider.dart';
import 'package:intl/intl.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/general_settings_provider.dart';
import 'package:weighbridgemanagement/shared/providers/mfa_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';

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
  bool _requireFaceVerification = false;
  bool _shiftBasedLogin = false;
  bool _forcePasswordChangeFirstLogin = true;
  int _passwordExpiryDays = 0; // 0 = never

  // ── Privacy / Archival ──
  bool _anonymizeVehicleOnArchive = false;

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
    super.dispose();
  }

  Future<void> _loadMfa() async {
    try {
      final mfa = ref.read(mfaServiceProvider);
      _mfaFactors = await mfa.getEnrolledFactors();
    } catch (_) {}
    if (mounted) setState(() => _mfaLoading = false);
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

    _requireFaceVerification = data['requireFaceVerification'] as bool? ?? false;
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
      'requireFaceVerification': _requireFaceVerification,
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
                        if (ref.read(wizardModeProvider)) {
                          ref.read(setupWizardProvider.notifier).previousStep();
                        } else {
                          context.go('/settings');
                        }
                      },
                      style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.shield_rounded, size: 20, color: scheme.primary),
                    const SizedBox(width: 10),
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
                      const SizedBox(width: 8),
                    ],
                    FilledButton.icon(
                      onPressed: _dirty && !_saving ? _save : null,
                      icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded, size: 16),
                      label: Text(_saving ? 'Saving...' : 'Save'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
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
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _headerMsgIsError ? scheme.error.withValues(alpha: 0.3) : AppTheme.successColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _headerMsgIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                            size: 15,
                            color: _headerMsgIsError ? scheme.error : AppTheme.successColor,
                          ),
                          const SizedBox(width: 8),
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
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) => SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: RBAC + Audit Trail
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildRbacSection(scheme, text)),
                          const SizedBox(width: 20),
                          Expanded(child: _buildAuditSection(scheme, text)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Row 2: Data Security + Operator Verification
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildDataSecuritySection(scheme, text)),
                          const SizedBox(width: 20),
                          Expanded(child: _buildOperatorVerificationSection(scheme, text)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Row 3: MFA + IP Whitelist
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildMfaSection(scheme, text)),
                          const SizedBox(width: 20),
                          Expanded(child: _buildIpWhitelistSection(scheme, text)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Row 4: Screen Protection + Emergency & Session Control
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildScreenProtectionSection(scheme, text)),
                          const SizedBox(width: 20),
                          Expanded(child: _buildSessionControlSection(scheme, text)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
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
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.verified_user_rounded, size: 14, color: scheme.primary),
              const SizedBox(width: 8),
              Text('Admin', style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary)),
              const Spacer(),
              Text('Full access to all features', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 12),
        Text('Operator Permissions', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 8),
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
            const SizedBox(width: 8),
            Text('Enable audit logging', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        if (_auditEnabled) ...[
          const SizedBox(height: 12),
          Text('Log events:', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          _PermissionToggle(label: 'Setting changes', value: _auditLogSettingChanges, onChanged: (v) { setState(() => _auditLogSettingChanges = v); _markDirty(); }),
          _PermissionToggle(label: 'Weighment edits/deletions', value: _auditLogWeighmentEdits, onChanged: (v) { setState(() => _auditLogWeighmentEdits = v); _markDirty(); }),
          _PermissionToggle(label: 'Docket reprints', value: _auditLogReprints, onChanged: (v) { setState(() => _auditLogReprints = v); _markDirty(); }),
          _PermissionToggle(label: 'Login/logout events', value: _auditLogLogins, onChanged: (v) { setState(() => _auditLogLogins = v); _markDirty(); }),
          _PermissionToggle(label: 'Data exports', value: _auditLogExports, onChanged: (v) { setState(() => _auditLogExports = v); _markDirty(); }),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Retention:', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(width: 8),
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
              const SizedBox(width: 6),
              Text('days', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
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
            const SizedBox(width: 8),
            Text('Auto-lock screen', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        if (_autoLockEnabled) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 44),
              Text('after', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(width: 8),
              _ChipGroup(
                value: '${_autoLockMinutes}m',
                options: const ['2m', '5m', '10m', '15m', '30m'],
                onChanged: (v) { setState(() => _autoLockMinutes = int.parse(v.replaceAll('m', ''))); _markDirty(); },
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        _PermissionToggle(label: 'Encrypt local backups', value: _encryptBackups, onChanged: (v) { setState(() => _encryptBackups = v); _markDirty(); }),
        const SizedBox(height: 4),
        _PermissionToggle(label: 'Mask sensitive fields for operators', value: _maskSensitiveFields, onChanged: (v) { setState(() => _maskSensitiveFields = v); _markDirty(); }),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 44),
          child: Text('Phone, PAN, Aadhaar hidden for non-admin roles', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
        ),
        const SizedBox(height: 14),
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
        _PermissionToggle(label: 'Require face verification before weighment', value: _requireFaceVerification, onChanged: (v) { setState(() => _requireFaceVerification = v); _markDirty(); }),
        const SizedBox(height: 4),
        _PermissionToggle(label: 'Shift-based login only', value: _shiftBasedLogin, onChanged: (v) { setState(() => _shiftBasedLogin = v); _markDirty(); }),
        const SizedBox(height: 4),
        _PermissionToggle(label: 'Force password change on first login', value: _forcePasswordChangeFirstLogin, onChanged: (v) { setState(() => _forcePasswordChangeFirstLogin = v); _markDirty(); }),
        const SizedBox(height: 12),
        Row(
          children: [
            Text('Password expiry:', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(width: 8),
            _ChipGroup(
              value: _passwordExpiryDays == 0 ? 'never' : '${_passwordExpiryDays}d',
              options: const ['never', '30d', '60d', '90d'],
              onChanged: (v) { setState(() => _passwordExpiryDays = v == 'never' ? 0 : int.parse(v.replaceAll('d', ''))); _markDirty(); },
            ),
          ],
        ),
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
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  _mfaFactors.isNotEmpty ? Icons.verified_user_rounded : Icons.shield_outlined,
                  size: 18,
                  color: _mfaFactors.isNotEmpty ? const Color(0xFF2E7D32) : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
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
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(6)),
              child: Text(_mfaError!, style: const TextStyle(fontSize: 11, color: Color(0xFFC62828))),
            ),
          ],
          if (_mfaSuccess != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(6)),
              child: Text(_mfaSuccess!, style: const TextStyle(fontSize: 11, color: Color(0xFF1B5E20))),
            ),
          ],
          if (_totpSecret != null) ...[
            const SizedBox(height: 12),
            Text('Manual key:', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(6)),
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
            const SizedBox(height: 10),
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
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _mfaEnrolling ? null : _finalizeMfaEnrollment,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), textStyle: const TextStyle(fontSize: 11)),
                  child: const Text('Verify'),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => setState(() { _totpSecret = null; _mfaError = null; }),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), textStyle: const TextStyle(fontSize: 11)),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
          if (_mfaFactors.isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._mfaFactors.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(f.displayName ?? 'Authenticator App', style: text.bodySmall)),
                  InkWell(
                    onTap: () => _removeMfaFactor(f),
                    child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 14, color: scheme.error)),
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
            const SizedBox(width: 8),
            Text('Restrict access to allowed IPs', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        if (_ipWhitelistEnabled) ...[
          const SizedBox(height: 12),
          ..._whitelistedIps.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(Icons.computer_rounded, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text(e.value, style: text.bodySmall?.copyWith(fontFamily: 'Courier'))),
                InkWell(
                  onTap: () { setState(() => _whitelistedIps.removeAt(e.key)); _markDirty(); },
                  child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 14, color: scheme.error)),
                ),
              ],
            ),
          )),
          const SizedBox(height: 6),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _addIpDialog(scheme, text),
                icon: const Icon(Icons.add_rounded, size: 14),
                label: const Text('Add IP'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _addCurrentIp,
                icon: const Icon(Icons.my_location_rounded, size: 14),
                label: const Text('Add Current IP'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _addCurrentIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      final ips = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) ips.add(addr.address);
        }
      }
      if (ips.isEmpty) return;
      final ip = ips.first;
      if (!_whitelistedIps.contains(ip)) {
        setState(() => _whitelistedIps.add(ip));
        _markDirty();
      }
    } catch (_) {}
  }

  void _addIpDialog(ColorScheme scheme, TextTheme text) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add IP Address'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '192.168.1.100', isDense: true),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final ip = ctrl.text.trim();
            if (ip.isNotEmpty) {
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
        _PermissionToggle(
          label: 'Prevent screenshots (blank screen on capture)',
          value: _preventScreenshots,
          onChanged: (v) { setState(() => _preventScreenshots = v); _markDirty(); },
        ),
        const SizedBox(height: 4),
        _PermissionToggle(
          label: 'Dim content when window is inactive',
          value: _dimOnInactiveWindow,
          onChanged: (v) { setState(() => _dimOnInactiveWindow = v); _markDirty(); },
        ),
        const SizedBox(height: 4),
        _PermissionToggle(
          label: 'Overlay watermark (operator name + timestamp)',
          value: _watermarkEnabled,
          onChanged: (v) { setState(() => _watermarkEnabled = v); _markDirty(); },
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How it works:', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              _infoRow(Icons.screenshot_rounded, 'Screenshots: Window content blanks during system screenshot capture', text, scheme),
              const SizedBox(height: 4),
              _infoRow(Icons.visibility_off_rounded, 'Inactive dimming: Obscures data when app loses focus, deters shoulder-surfing', text, scheme),
              const SizedBox(height: 4),
              _infoRow(Icons.water_drop_rounded, 'Watermark: Visible operator identity overlay makes photos traceable', text, scheme),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('Note: No software can fully prevent external camera capture. Watermark + audit trail provides accountability.', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, TextTheme text, ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 12, color: scheme.primary),
        const SizedBox(width: 6),
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
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _emergencyLockdown ? scheme.errorContainer.withValues(alpha: 0.3) : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: _emergencyLockdown ? Border.all(color: scheme.error.withValues(alpha: 0.4)) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_emergencyLockdown ? Icons.lock_rounded : Icons.lock_open_rounded, size: 16, color: _emergencyLockdown ? scheme.error : scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
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
              const SizedBox(height: 6),
              Text(
                _emergencyLockdown
                    ? 'ACTIVE: All operator sessions locked out. Only admin can deactivate.'
                    : 'Instantly locks all operator sessions and blocks new logins.',
                style: text.labelSmall?.copyWith(color: _emergencyLockdown ? scheme.error : scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Auto-logout vs lock
        Text('Inactivity behavior:', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              height: 20, width: 36,
              child: FittedBox(child: Switch(value: _autoLogoutEnabled, onChanged: (v) { setState(() => _autoLogoutEnabled = v); _markDirty(); })),
            ),
            const SizedBox(width: 8),
            Text('Full logout on inactivity', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        if (_autoLogoutEnabled) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 44),
              Text('after', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(width: 8),
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
        const SizedBox(height: 14),
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
        const SizedBox(height: 8),
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
      _markDirty();
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(children: [Icon(Icons.warning_rounded, color: scheme.error), const SizedBox(width: 8), const Text('Emergency Lockdown')]),
          content: const Text('This will immediately lock out ALL operator sessions and prevent new operator logins. Only admin accounts will retain access.\n\nAre you sure?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _emergencyLockdown = true);
                _markDirty();
              },
              style: FilledButton.styleFrom(backgroundColor: scheme.error),
              child: const Text('Activate Lockdown'),
            ),
          ],
        ),
      );
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
            child: Text('No session logs recorded yet.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
          )
        else
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
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
                            borderRadius: BorderRadius.circular(4),
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
        const SizedBox(height: 10),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _loadSessionLogs,
              icon: const Icon(Icons.refresh_rounded, size: 14),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 11)),
            ),
            const SizedBox(width: 8),
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
    final result = await Process.run('osascript', [
      '-e', 'POSIX path of (choose folder with prompt "Choose export location for audit log")',
    ]);
    if (result.exitCode != 0) return;
    final chosen = (result.stdout as String).trim();
    if (chosen.isEmpty) return;
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Audit log exported: $filePath (${snap.docs.length} entries)'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
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
        borderRadius: BorderRadius.circular(16),
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
                  decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(7)),
                  child: Icon(icon, size: 15, color: scheme.primary),
                ),
                const SizedBox(width: 10),
                Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
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
          const SizedBox(width: 10),
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
                borderRadius: BorderRadius.circular(6),
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
