import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:weighbridgemanagement/shared/providers/mfa_provider.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

/// Self-contained Two-Factor Authentication UI (enroll / disable / recovery
/// codes). Drop it into any screen. When [embedded] is true it renders only the
/// content (no card chrome) so it can sit inside another card.
class MfaSettingsCard extends ConsumerStatefulWidget {
  final bool embedded;
  /// Widgets rendered above the 2FA heading (e.g. the security card's info
  /// rows), so the enrollment QR can span the full height beside them too.
  final List<Widget> leading;
  const MfaSettingsCard({super.key, this.embedded = false, this.leading = const []});

  @override
  ConsumerState<MfaSettingsCard> createState() => _MfaSettingsCardState();
}

class _MfaSettingsCardState extends ConsumerState<MfaSettingsCard> {
  bool _loading = true;
  bool _enabled = false;
  int _backupRemaining = 0;
  String _email = '';
  MfaEnrollment? _enrollment;
  bool _busy = false;
  String? _error;
  String? _success;
  String? _pendingAction; // 'enroll' | 'disable' | 'regenerate' — shows the inline password field
  List<String>? _newBackupCodes; // freshly generated codes shown inline ("save these"), until dismissed
  final _password = TextEditingController();
  final _otp1 = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _password.dispose();
    _otp1.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _email = FirebaseAuth.instance.currentUser?.email ??
          await LocalCacheService.getCachedCurrentUserEmail() ?? '';
      if (_email.isNotEmpty) {
        final st = await ref.read(mfaServiceProvider).status(_email);
        _enabled = st.enabled;
        _backupRemaining = st.backupCodesRemaining;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // Shows the inline password field for [action] ('enroll' / 'disable' /
  // 'regenerate') instead of an overlay dialog.
  void _requestPassword(String action) {
    if (_email.isEmpty) {
      setState(() => _error = 'Could not determine your account email.');
      return;
    }
    setState(() { _pendingAction = action; _error = null; _success = null; _password.clear(); });
  }

  void _cancelPassword() {
    setState(() { _pendingAction = null; _password.clear(); _error = null; });
  }

  Future<void> _submitPassword() async {
    final password = _password.text;
    if (password.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    final action = _pendingAction;
    setState(() { _busy = true; _error = null; });
    try {
      if (action == 'enroll') {
        final enr = await ref.read(mfaServiceProvider).beginEnroll(_email, password);
        if (mounted) setState(() { _enrollment = enr; _pendingAction = null; _password.clear(); });
      } else if (action == 'disable') {
        await ref.read(mfaServiceProvider).disable(_email, password: password);
        if (mounted) {
          setState(() {
            _enabled = false;
            _enrollment = null;
            _pendingAction = null;
            _password.clear();
            _success = null;
          });
        }
      } else if (action == 'regenerate') {
        final codes = await ref.read(mfaServiceProvider).regenerateBackupCodes(_email, password);
        if (mounted) {
          setState(() {
            _backupRemaining = codes.length;
            _pendingAction = null;
            _password.clear();
            _newBackupCodes = codes.isNotEmpty ? codes : null;
            _success = codes.isNotEmpty ? null : 'New recovery codes generated.';
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Incorrect password, or the action could not be completed.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _finishEnroll() async {
    final code = _otp1.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your authenticator app.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final backupCodes = await ref.read(mfaServiceProvider).confirmEnroll(_email, code);
      if (mounted) {
        setState(() {
          _otp1.clear();
          _enrollment = null;
          _enabled = true;
          _backupRemaining = backupCodes.length;
          _newBackupCodes = backupCodes.isNotEmpty ? backupCodes : null;
          _success = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Incorrect code. Check your authenticator app and try again.');
    }
    if (mounted) setState(() => _busy = false);
  }

  void _showEnlargedQr() {
    final url = _enrollment?.otpauth;
    if (url == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 300,
                height: 300,
                child: QrImageView(data: url, version: QrVersions.auto, backgroundColor: Colors.white),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadCodes() async {
    final codes = _newBackupCodes;
    if (codes == null || codes.isEmpty) return;
    try {
      // Write straight to Downloads (no save dialog); sandbox-safe on macOS via
      // the files.downloads.read-write entitlement.
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}tulanam-2fa-recovery-codes.txt');
      final content = 'Tulanam — Two-Factor Authentication recovery codes\n'
          'Account: $_email\n\n'
          'Each code can be used once in place of your authenticator code if you lose access.\n'
          'Keep this file somewhere safe.\n\n'
          '${codes.join('\n')}\n';
      await file.writeAsString(content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn\'t save the file: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final headingRow = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.4), borderRadius: AppRadius.chip),
                child: Icon(Icons.security_rounded, size: 16, color: scheme.primary),
              ),
              SizedBox(width: AppSpacing.sm),
              Text('Two-Factor Authentication', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              if (!_loading && _pendingAction == null) ...[
                SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _enabled ? AppTheme.successColor.withValues(alpha: 0.14) : scheme.surfaceContainerHighest,
                    borderRadius: AppRadius.chip,
                  ),
                  child: Text(_enabled ? 'ON' : 'OFF',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5,
                          color: _enabled ? AppTheme.successColor : scheme.onSurfaceVariant)),
                ),
              ],
              const Spacer(),
              if (_loading)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else if (_pendingAction != null) ...[
                SizedBox(
                  width: 160,
                  height: 40,
                  child: TextField(
                    controller: _password,
                    obscureText: true,
                    autofocus: true,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Password',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submitPassword(),
                  ),
                ),
                SizedBox(width: AppSpacing.sm),
                Tooltip(
                  message: 'Continue',
                  child: SizedBox(
                    height: 34,
                    width: 34,
                    child: FilledButton(
                      onPressed: _busy ? null : _submitPassword,
                      style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
                      child: _busy
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_rounded, size: 18),
                    ),
                  ),
                ),
                SizedBox(width: AppSpacing.xs),
                Tooltip(
                  message: 'Cancel',
                  child: SizedBox(
                    height: 34,
                    width: 34,
                    child: OutlinedButton(
                      onPressed: _busy ? null : _cancelPassword,
                      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: scheme.error, side: BorderSide(color: scheme.outlineVariant), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
                      child: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ),
                ),
              ]
              else if (_enabled) ...[
                Tooltip(
                  message: '$_backupRemaining recovery codes left',
                  child: Icon(Icons.vpn_key_rounded, size: 14, color: _backupRemaining <= 2 ? scheme.error : scheme.onSurfaceVariant),
                ),
                SizedBox(width: 3.rs),
                Text('$_backupRemaining', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _backupRemaining <= 2 ? scheme.error : scheme.onSurfaceVariant)),
                TextButton(
                  onPressed: _busy ? null : () => _requestPassword('regenerate'),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap, textStyle: const TextStyle(fontSize: 11)),
                  child: const Text('Regenerate'),
                ),
                SizedBox(width: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _requestPassword('disable'),
                  icon: const Icon(Icons.lock_open_rounded, size: 14),
                  label: const Text('Disable'),
                  style: OutlinedButton.styleFrom(foregroundColor: scheme.error, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 11)),
                ),
              ]
              else if (_enrollment == null)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _requestPassword('enroll'),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Enable'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 11)),
                ),
            ],
          );
    final body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loading) ...[
            ...widget.leading,
            headingRow,
          ]
          else if (_enrollment != null)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...widget.leading,
                        headingRow,
                        SizedBox(height: AppSpacing.md),
                        Text('Scan the QR with any authenticator app, or enter the key, then verify with a code.',
                            style: text.bodySmall?.copyWith(fontSize: 11, color: scheme.onSurfaceVariant)),
                        SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            // Manual key
                            Expanded(
                              child: SizedBox(
                                height: 40,
                                child: Container(
                                  padding: const EdgeInsets.only(left: 10, right: 2),
                                  decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: AppRadius.chip),
                                  child: Row(
                                    children: [
                                      Expanded(child: Text(_enrollment!.secret, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Courier', fontSize: 11, fontWeight: FontWeight.w600))),
                                      IconButton(
                                        icon: const Icon(Icons.copy_rounded, size: 14),
                                        tooltip: 'Copy key',
                                        onPressed: () => Clipboard.setData(ClipboardData(text: _enrollment!.secret)),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: AppSpacing.sm),
                            // Code
                            Expanded(
                              child: SizedBox(
                                height: 40,
                                child: TextField(
                                  controller: _otp1,
                                  textAlignVertical: TextAlignVertical.center,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 2),
                                  decoration: const InputDecoration(
                                    hintText: 'Code',
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10),
                                    border: OutlineInputBorder(),
                                  ),
                                  onSubmitted: (_) => _finishEnroll(),
                                ),
                              ),
                            ),
                            SizedBox(width: AppSpacing.sm),
                            SizedBox(
                              height: 40,
                              child: FilledButton(
                                onPressed: _busy ? null : _finishEnroll,
                                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16), textStyle: const TextStyle(fontSize: 11)),
                                child: _busy
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('Verify'),
                              ),
                            ),
                            SizedBox(width: AppSpacing.xs),
                            SizedBox(
                              height: 40,
                              child: TextButton(
                                onPressed: () => setState(() { _enrollment = null; _error = null; _otp1.clear(); }),
                                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), textStyle: const TextStyle(fontSize: 11)),
                                child: const Text('Cancel'),
                              ),
                            ),
                          ],
                        ),
                        if (_error != null) ...[
                          SizedBox(height: AppSpacing.sm),
                          Container(
                            padding: EdgeInsets.all(8.rs),
                            decoration: BoxDecoration(color: scheme.error.withValues(alpha: 0.12), borderRadius: AppRadius.chip),
                            child: Text(_error!, style: TextStyle(fontSize: 11, color: scheme.error)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: AppSpacing.lg),
                  Tooltip(
                    message: 'Tap to enlarge',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _showEnlargedQr,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: AppRadius.button,
                            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                          ),
                          child: Center(
                            child: SizedBox(
                              width: 200,
                              height: 200,
                              child: QrImageView(data: _enrollment!.otpauth, version: QrVersions.auto, backgroundColor: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            ...widget.leading,
            headingRow,
            SizedBox(height: AppSpacing.md),
            if (_error != null) ...[
              SizedBox(height: AppSpacing.sm),
              Container(
                padding: EdgeInsets.all(8.rs),
                decoration: BoxDecoration(color: scheme.error.withValues(alpha: 0.12), borderRadius: AppRadius.chip),
                child: Text(_error!, style: TextStyle(fontSize: 11, color: scheme.error)),
              ),
            ],
            if (_success != null) ...[
              SizedBox(height: AppSpacing.sm),
              Container(
                padding: EdgeInsets.all(8.rs),
                decoration: BoxDecoration(color: AppTheme.successColor.withValues(alpha: 0.12), borderRadius: AppRadius.chip),
                child: Text(_success!, style: TextStyle(fontSize: 11, color: AppTheme.successColor)),
              ),
            ],
            if (_newBackupCodes != null) ...[
              SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12.rs),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: AppRadius.button,
                  border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.vpn_key_rounded, size: 16, color: AppTheme.successColor),
                        SizedBox(width: AppSpacing.sm),
                        Text('Save your recovery codes', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                    SizedBox(height: AppSpacing.sm),
                    Text('If you lose your authenticator, each one-time code works in place of the 6-digit code to sign in. They won\'t be shown again — store them somewhere safe.',
                        style: text.bodySmall?.copyWith(fontSize: 11, color: scheme.onSurfaceVariant)),
                    SizedBox(height: AppSpacing.sm),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: scheme.surface, borderRadius: AppRadius.chip),
                      child: Wrap(
                        spacing: 18,
                        runSpacing: 8,
                        children: _newBackupCodes!
                            .map((c) => SelectableText(c, style: const TextStyle(fontFamily: 'Courier', fontSize: 13, fontWeight: FontWeight.w600)))
                            .toList(),
                      ),
                    ),
                    SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => Clipboard.setData(ClipboardData(text: _newBackupCodes!.join('\n'))),
                          icon: const Icon(Icons.copy_rounded, size: 14),
                          label: const Text('Copy all', style: TextStyle(fontSize: 11)),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                        ),
                        SizedBox(width: AppSpacing.xs),
                        TextButton.icon(
                          onPressed: _downloadCodes,
                          icon: const Icon(Icons.download_rounded, size: 14),
                          label: const Text('Download', style: TextStyle(fontSize: 11)),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => setState(() => _newBackupCodes = null),
                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), textStyle: const TextStyle(fontSize: 11)),
                          child: const Text('I\'ve saved them'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      );

    if (widget.embedded) return body;
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.dialog,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: body,
    );
  }

}
