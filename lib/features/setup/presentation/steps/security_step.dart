import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/license_provider.dart';
import '../../application/setup_wizard_provider.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/app_loading.dart';
import 'package:weighbridgemanagement/shared/widgets/mfa_settings_card.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

class SecurityStep extends ConsumerStatefulWidget {
  const SecurityStep({super.key});

  @override
  ConsumerState<SecurityStep> createState() => _SecurityStepState();
}

class _SecurityStepState extends ConsumerState<SecurityStep> {
  bool _loaded = false;

  // Auto-lock
  bool _autoLock = true;
  int _autoLockMinutes = 5;

  // Operator permissions
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

  // KYC
  bool _requireKycForSensitiveOps = false;

  // Face verification
  bool _faceVerifyOnWeighmentStart = false;
  bool _faceVerifyOnSessionStart = false;
  bool _faceVerifyOnDayStart = false;

  // Audit (always on, not configurable)

  // Data security
  bool _maskSensitiveFields = true;

  // Operator verification
  bool _shiftBasedLogin = false;
  bool _forcePasswordChangeFirstLogin = false;
  int _passwordExpiryDays = 0;

  bool _userModified = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(stepSaveCallbackProvider.notifier).state = _save;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _markModified() {
    if (!_userModified) {
      _userModified = true;
      ref.read(stepHasDataProvider.notifier).state = true;
    }
  }

  Future<void> _loadData() async {
    final paths = ref.read(firestorePathsProvider);
    if (!paths.isConfigured) {
      setState(() => _loaded = true);
      return;
    }

    try {
      final snap = await paths.securitySettings.get();
      final data = snap.data() ?? {};
      if (mounted) {
        setState(() {
          _autoLock = data['autoLockEnabled'] as bool? ?? data['autoLock'] as bool? ?? true;
          _autoLockMinutes = data['autoLockMinutes'] as int? ?? 5;
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
          _requireKycForSensitiveOps = data['requireKycForSensitiveOps'] as bool? ?? false;
          _faceVerifyOnWeighmentStart = data['faceVerifyOnWeighmentStart'] as bool? ?? false;
          _faceVerifyOnSessionStart = data['faceVerifyOnSessionStart'] as bool? ?? false;
          _faceVerifyOnDayStart = data['faceVerifyOnDayStart'] as bool? ?? false;
          _maskSensitiveFields = data['maskSensitiveFields'] as bool? ?? true;
          _shiftBasedLogin = data['shiftBasedLogin'] as bool? ?? false;
          _forcePasswordChangeFirstLogin = data['forcePasswordChangeFirstLogin'] as bool? ?? true;
          _passwordExpiryDays = data['passwordExpiryDays'] as int? ?? 0;
          _loaded = true;
        });
        if (snap.exists && data.isNotEmpty) {
          ref.read(stepHasDataProvider.notifier).state = true;
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<bool> _save() async {
    try {
      final paths = ref.read(firestorePathsProvider);
      await paths.securitySettings.set({
        'autoLockEnabled': _autoLock,
        'autoLockMinutes': _autoLockMinutes,
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
        'requireKycForSensitiveOps': _requireKycForSensitiveOps,
        'faceVerifyOnWeighmentStart': _faceVerifyOnWeighmentStart,
        'faceVerifyOnSessionStart': _faceVerifyOnSessionStart,
        'faceVerifyOnDayStart': _faceVerifyOnDayStart,
        'auditEnabled': true,
        'encryptBackups': true,
        'maskSensitiveFields': _maskSensitiveFields,
        'shiftBasedLogin': _shiftBasedLogin,
        'forcePasswordChangeFirstLogin': _forcePasswordChangeFirstLogin,
        'passwordExpiryDays': _passwordExpiryDays,
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), behavior: SnackBarBehavior.floating),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isFree = ref.watch(isFreeProvider);

    if (!_loaded) return const AppLoading();

    return SingleChildScrollView(
      padding: EdgeInsets.all(40.rs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Security', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: AppSpacing.sm),
          Text(
            'Set up access control, operator verification, and data protection policies.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          SizedBox(height: AppSpacing.xxl),

          // Operator Permissions — two columns
          _buildCard(scheme, children: [
            _buildSectionHeader('Operator Permissions', Icons.admin_panel_settings_rounded, scheme, text),
            SizedBox(height: AppSpacing.xs),
            Text('What operators are allowed to do', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            SizedBox(height: 14.rs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Weighment Operations', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
                      SizedBox(height: AppSpacing.sm),
                      _buildPermissionRow(Icons.block_rounded, 'Void weighments', _opCanVoidWeighment, (v) { setState(() => _opCanVoidWeighment = v); _markModified(); }, scheme, isDangerous: true),
                      _buildPermissionRow(Icons.edit_rounded, 'Edit weighment records', _opCanEditWeighment, (v) { setState(() => _opCanEditWeighment = v); _markModified(); }, scheme, isDangerous: true),
                      _buildPermissionRow(Icons.keyboard_rounded, 'Manual weight entry (override scale)', _opCanManualWeight, (v) { setState(() => _opCanManualWeight = v); _markModified(); }, scheme, isDangerous: true),
                      _buildPermissionRow(Icons.delete_forever_rounded, 'Delete weighment records', _opCanDeleteRecords, (v) { setState(() => _opCanDeleteRecords = v); _markModified(); }, scheme, isDangerous: true),
                      SizedBox(height: AppSpacing.lg),
                      Text('Data & Reports', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
                      SizedBox(height: AppSpacing.sm),
                      _buildPermissionRow(Icons.bar_chart_rounded, 'View reports & analytics', _opCanViewReports, (v) { setState(() => _opCanViewReports = v); _markModified(); }, scheme),
                      _buildPermissionRow(Icons.download_rounded, 'Export data (CSV, PDF)', _opCanExportData, (v) { setState(() => _opCanExportData = v); _markModified(); }, scheme),
                      _buildPermissionRow(Icons.print_rounded, 'Reprint dockets', _opCanReprint, (v) { setState(() => _opCanReprint = v); _markModified(); }, scheme),
                      _buildPermissionRow(Icons.videocam_rounded, 'View CCTV snapshots & recordings', _opCanViewCctv, (v) { setState(() => _opCanViewCctv = v); _markModified(); }, scheme),
                    ],
                  ),
                ),
                SizedBox(width: 20.rs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Master Data Management', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
                      SizedBox(height: AppSpacing.sm),
                      _buildPermissionRow(Icons.people_rounded, 'Manage customers / parties', _opCanManageCustomers, (v) { setState(() => _opCanManageCustomers = v); _markModified(); }, scheme),
                      _buildPermissionRow(Icons.inventory_2_rounded, 'Manage materials / products', _opCanManageMaterials, (v) { setState(() => _opCanManageMaterials = v); _markModified(); }, scheme),
                      SizedBox(height: AppSpacing.lg),
                      Text('Settings Access', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
                      SizedBox(height: 2.rs),
                      Text('Which settings screens the operator can access', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                      SizedBox(height: AppSpacing.sm),
                      _buildPermissionRow(Icons.settings_rounded, 'General & appearance', _opCanChangeSettings, (v) { setState(() => _opCanChangeSettings = v); _markModified(); }, scheme),
                      _buildPermissionRow(Icons.scale_rounded, 'Weighbridge / scale', _opCanAccessWeighbridge, (v) { setState(() => _opCanAccessWeighbridge = v); _markModified(); }, scheme),
                      _buildPermissionRow(Icons.garage_rounded, 'Gate control & traffic signals', _opCanAccessGateControl, (v) { setState(() => _opCanAccessGateControl = v); _markModified(); }, scheme),
                      _buildPermissionRow(Icons.camera_alt_rounded, 'Cameras & AI', _opCanAccessCameras, (v) { setState(() => _opCanAccessCameras = v); _markModified(); }, scheme),
                      _buildPermissionRow(Icons.print_outlined, 'Printing & docket layout', _opCanAccessPrinting, (v) { setState(() => _opCanAccessPrinting = v); _markModified(); }, scheme),
                    ],
                  ),
                ),
              ],
            ),
          ]),

          SizedBox(height: AppSpacing.lg),

          // Operator Verification — full width below
          _buildCard(scheme, children: [
            _buildSectionHeader('Operator Verification', Icons.verified_user_rounded, scheme, text),
            SizedBox(height: AppSpacing.xs),
            Text('Identity checks and login policies', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFaceOption(
                        Icons.scale_rounded, 'Face verify: each weighment',
                        'Before every gross/tare capture',
                        _faceVerifyOnWeighmentStart,
                        (v) { setState(() => _faceVerifyOnWeighmentStart = v); _markModified(); },
                        scheme,
                      ),
                      SizedBox(height: AppSpacing.sm),
                      _buildFaceOption(
                        Icons.login_rounded, 'Face verify: session start',
                        'Once per login session',
                        _faceVerifyOnSessionStart,
                        (v) { setState(() => _faceVerifyOnSessionStart = v); _markModified(); },
                        scheme,
                      ),
                      SizedBox(height: AppSpacing.sm),
                      _buildFaceOption(
                        Icons.today_rounded, 'Face verify: day start',
                        'Once per calendar day',
                        _faceVerifyOnDayStart,
                        (v) { setState(() => _faceVerifyOnDayStart = v); _markModified(); },
                        scheme,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 20.rs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFaceOption(
                        Icons.schedule_rounded, 'Shift-based login',
                        'Restrict login to assigned shift hours',
                        _shiftBasedLogin,
                        (v) { setState(() => _shiftBasedLogin = v); _markModified(); },
                        scheme,
                      ),
                      SizedBox(height: AppSpacing.sm),
                      _buildFaceOption(
                        Icons.password_rounded, 'Force password change',
                        'On first login for new operators',
                        _forcePasswordChangeFirstLogin,
                        (v) { setState(() => _forcePasswordChangeFirstLogin = v); _markModified(); },
                        scheme,
                      ),
                      SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Container(
                            width: 26, height: 26,
                            decoration: BoxDecoration(
                              color: _passwordExpiryDays > 0 ? scheme.primaryContainer.withValues(alpha: 0.4) : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              borderRadius: AppRadius.chip,
                            ),
                            child: Icon(Icons.autorenew_rounded, size: 13, color: _passwordExpiryDays > 0 ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.4)),
                          ),
                          SizedBox(width: 10.rs),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Password expiry', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurface)),
                                Text(_passwordExpiryDays == 0 ? 'Never expires' : 'Every $_passwordExpiryDays days', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 6.rs),
                      Padding(
                        padding: const EdgeInsets.only(left: 36),
                        child: Wrap(
                          spacing: 6,
                          children: [0, 30, 60, 90].map((d) => _buildSelectChip(
                            d == 0 ? 'Never' : '${d}d', _passwordExpiryDays == d,
                            () { setState(() => _passwordExpiryDays = d); _markModified(); }, scheme,
                          )).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ]),

          SizedBox(height: AppSpacing.xl),

          if (isFree)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer.withValues(alpha: 0.15),
                borderRadius: AppRadius.button,
                border: Border.all(color: scheme.tertiary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.workspace_premium_rounded, size: 14, color: scheme.tertiary),
                  SizedBox(width: 10.rs),
                  Expanded(
                    child: Text(
                      'MFA, IP whitelisting, screen protection, and session lockdown require Pro.',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            _buildSectionHeader('Two-Factor Authentication (2FA)', Icons.shield_rounded, scheme, text),
            SizedBox(height: AppSpacing.sm),
            const MfaSettingsCard(embedded: true),
            SizedBox(height: AppSpacing.md),
            Text(
              'IP whitelisting, domain restrictions, screen protection, USB restrictions, and remote desktop blocking are available in Settings.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCard(ColorScheme scheme, {required List<Widget> children}) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.4),
        borderRadius: AppRadius.card,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, ColorScheme scheme, TextTheme text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        SizedBox(width: AppSpacing.sm),
        Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildSelectChip(String label, bool selected, VoidCallback onTap, ColorScheme scheme) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          borderRadius: AppRadius.chip,
          border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? scheme.surface : scheme.onSurfaceVariant)),
      ),
    );
  }

  Widget _buildPermissionRow(IconData icon, String label, bool value, ValueChanged<bool> onChanged, ColorScheme scheme, {bool isDangerous = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: value
                  ? (isDangerous ? scheme.errorContainer.withValues(alpha: 0.3) : scheme.primaryContainer.withValues(alpha: 0.3))
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: AppRadius.chip,
            ),
            child: Icon(icon, size: 13, color: value ? (isDangerous ? scheme.error : scheme.primary) : scheme.onSurfaceVariant.withValues(alpha: 0.4)),
          ),
          SizedBox(width: 10.rs),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurface),
            ),
          ),
          if (isDangerous && value)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(Icons.warning_amber_rounded, size: 13, color: scheme.error.withValues(alpha: 0.7)),
            ),
          SizedBox(
            height: 24,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: isDangerous ? scheme.error : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaceOption(IconData icon, String label, String subtitle, bool value, ValueChanged<bool> onChanged, ColorScheme scheme) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: value ? scheme.primaryContainer.withValues(alpha: 0.4) : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: AppRadius.chip,
          ),
          child: Icon(icon, size: 13, color: value ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.4)),
        ),
        SizedBox(width: 10.rs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurface)),
              Text(subtitle, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        SizedBox(height: 28, child: Switch(value: value, onChanged: onChanged)),
      ],
    );
  }
}
