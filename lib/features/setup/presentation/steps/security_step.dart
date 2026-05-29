import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/license_provider.dart';
import '../../application/setup_wizard_provider.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/app_loading.dart';

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

  // Face verification
  bool _faceVerifyOnWeighmentStart = false;
  bool _faceVerifyOnSessionStart = false;
  bool _faceVerifyOnDayStart = false;

  // Audit
  bool _auditEnabled = true;

  // Data
  bool _encryptBackups = true;

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
    try {
    } catch (_) {}
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
          _autoLock = data['autoLock'] as bool? ?? true;
          _autoLockMinutes = data['autoLockMinutes'] as int? ?? 5;
          _opCanVoidWeighment = data['opCanVoidWeighment'] as bool? ?? false;
          _opCanEditWeighment = data['opCanEditWeighment'] as bool? ?? false;
          _opCanManualWeight = data['opCanManualWeight'] as bool? ?? false;
          _opCanReprint = data['opCanReprint'] as bool? ?? true;
          _opCanExportData = data['opCanExportData'] as bool? ?? false;
          _opCanViewReports = data['opCanViewReports'] as bool? ?? true;
          _faceVerifyOnWeighmentStart = data['faceVerifyOnWeighmentStart'] as bool? ?? false;
          _faceVerifyOnSessionStart = data['faceVerifyOnSessionStart'] as bool? ?? false;
          _faceVerifyOnDayStart = data['faceVerifyOnDayStart'] as bool? ?? false;
          _auditEnabled = data['auditEnabled'] as bool? ?? true;
          _encryptBackups = data['encryptBackups'] as bool? ?? true;
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
        'autoLock': _autoLock,
        'autoLockMinutes': _autoLockMinutes,
        'opCanVoidWeighment': _opCanVoidWeighment,
        'opCanEditWeighment': _opCanEditWeighment,
        'opCanManualWeight': _opCanManualWeight,
        'opCanReprint': _opCanReprint,
        'opCanExportData': _opCanExportData,
        'opCanViewReports': _opCanViewReports,
        'faceVerifyOnWeighmentStart': _faceVerifyOnWeighmentStart,
        'faceVerifyOnSessionStart': _faceVerifyOnSessionStart,
        'faceVerifyOnDayStart': _faceVerifyOnDayStart,
        'auditEnabled': _auditEnabled,
        'encryptBackups': _encryptBackups,
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
          SizedBox(height: 8.rs),
          Text(
            'Set up access control and data protection policies.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          SizedBox(height: 32.rs),

          // Two-column layout
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Lock + Audit + Encryption
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCard(scheme, children: [
                      _buildSectionHeader('Screen Lock', Icons.lock_clock_rounded, scheme, text),
                      SizedBox(height: 12.rs),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Auto-lock after inactivity', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
                          ),
                          SizedBox(height: 28, child: Switch(value: _autoLock, onChanged: (v) { setState(() => _autoLock = v); _markModified(); })),
                        ],
                      ),
                      if (_autoLock) ...[
                        SizedBox(height: 8.rs),
                        Wrap(
                          spacing: 6,
                          children: [2, 5, 10, 30].map((m) => _buildSelectChip(
                            '${m}m', _autoLockMinutes == m,
                            () { setState(() => _autoLockMinutes = m); _markModified(); }, scheme,
                          )).toList(),
                        ),
                      ],
                    ]),
                    SizedBox(height: 16.rs),
                    _buildCard(scheme, children: [
                      _buildSectionHeader('Face Verification', Icons.face_rounded, scheme, text),
                      SizedBox(height: 4.rs),
                      Text('When to require camera face match', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                      SizedBox(height: 12.rs),
                      _buildFaceOption(
                        Icons.scale_rounded, 'Each weighment',
                        'Before every gross/tare capture',
                        _faceVerifyOnWeighmentStart,
                        (v) { setState(() => _faceVerifyOnWeighmentStart = v); _markModified(); },
                        scheme,
                      ),
                      SizedBox(height: 8.rs),
                      _buildFaceOption(
                        Icons.login_rounded, 'Session start',
                        'Once per login session',
                        _faceVerifyOnSessionStart,
                        (v) { setState(() => _faceVerifyOnSessionStart = v); _markModified(); },
                        scheme,
                      ),
                      SizedBox(height: 8.rs),
                      _buildFaceOption(
                        Icons.today_rounded, 'Day start',
                        'Once per calendar day',
                        _faceVerifyOnDayStart,
                        (v) { setState(() => _faceVerifyOnDayStart = v); _markModified(); },
                        scheme,
                      ),
                    ]),
                    SizedBox(height: 16.rs),
                    _buildCard(scheme, children: [
                      _buildSectionHeader('Audit Trail', Icons.history_rounded, scheme, text),
                      SizedBox(height: 12.rs),
                      Row(
                        children: [
                          Icon(
                            _auditEnabled ? Icons.check_circle_rounded : Icons.circle_outlined,
                            size: 16,
                            color: _auditEnabled ? scheme.primary : scheme.onSurfaceVariant,
                          ),
                          SizedBox(width: 8.rs),
                          Expanded(
                            child: Text('Log all changes, logins, and exports', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
                          ),
                          SizedBox(height: 28, child: Switch(value: _auditEnabled, onChanged: (v) { setState(() => _auditEnabled = v); _markModified(); })),
                        ],
                      ),
                    ]),
                    SizedBox(height: 16.rs),
                    _buildCard(scheme, children: [
                      _buildSectionHeader('Backup Encryption', Icons.enhanced_encryption_rounded, scheme, text),
                      SizedBox(height: 12.rs),
                      Row(
                        children: [
                          Icon(
                            _encryptBackups ? Icons.lock_rounded : Icons.lock_open_rounded,
                            size: 16,
                            color: _encryptBackups ? scheme.primary : scheme.onSurfaceVariant,
                          ),
                          SizedBox(width: 8.rs),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Encrypt exported data', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
                                Text('AES-256 encryption', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          SizedBox(height: 28, child: Switch(value: _encryptBackups, onChanged: (v) { setState(() => _encryptBackups = v); _markModified(); })),
                        ],
                      ),
                    ]),
                  ],
                ),
              ),
              SizedBox(width: 20.rs),
              // Right: Operator Permissions
              Expanded(
                child: _buildCard(scheme, children: [
                  _buildSectionHeader('Operator Permissions', Icons.admin_panel_settings_rounded, scheme, text),
                  SizedBox(height: 4.rs),
                  Text('What operators are allowed to do', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                  SizedBox(height: 14.rs),
                  _buildPermissionRow(Icons.block_rounded, 'Void weighments', _opCanVoidWeighment, (v) { setState(() => _opCanVoidWeighment = v); _markModified(); }, scheme, isDangerous: true),
                  _buildPermissionRow(Icons.edit_rounded, 'Edit weighments', _opCanEditWeighment, (v) { setState(() => _opCanEditWeighment = v); _markModified(); }, scheme, isDangerous: true),
                  _buildPermissionRow(Icons.keyboard_rounded, 'Manual weight entry', _opCanManualWeight, (v) { setState(() => _opCanManualWeight = v); _markModified(); }, scheme, isDangerous: true),
                  _buildPermissionRow(Icons.print_rounded, 'Reprint dockets', _opCanReprint, (v) { setState(() => _opCanReprint = v); _markModified(); }, scheme),
                  _buildPermissionRow(Icons.download_rounded, 'Export data', _opCanExportData, (v) { setState(() => _opCanExportData = v); _markModified(); }, scheme),
                  _buildPermissionRow(Icons.bar_chart_rounded, 'View reports', _opCanViewReports, (v) { setState(() => _opCanViewReports = v); _markModified(); }, scheme),
                ]),
              ),
            ],
          ),

          SizedBox(height: 24.rs),

          if (isFree)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8.rs),
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
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8.rs),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, size: 14, color: scheme.onSurfaceVariant),
                  SizedBox(width: 10.rs),
                  Expanded(
                    child: Text(
                      'MFA enrollment, IP whitelisting, shift login, domain restrictions, and screen protection are available in Settings.',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCard(ColorScheme scheme, {required List<Widget> children}) {
    return Container(
      padding: EdgeInsets.all(16.rs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12.rs),
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
        SizedBox(width: 8.rs),
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
          borderRadius: BorderRadius.circular(6.rs),
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
              borderRadius: BorderRadius.circular(6.rs),
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
            borderRadius: BorderRadius.circular(6.rs),
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
