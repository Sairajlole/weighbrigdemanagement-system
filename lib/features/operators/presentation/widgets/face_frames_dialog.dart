import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/cloud_functions_service.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/app_error.dart';

/// Admin tool: review the face-verification frames for an operator and exclude
/// specific shots from the face model. Excluded frames are kept (not deleted);
/// applying re-embeds from the remaining frames on the local sidecar. Gated by
/// an OTP sent to the admin.
class FaceFramesDialog extends ConsumerStatefulWidget {
  final String operatorId;
  final String operatorEmail;
  final String operatorName;

  const FaceFramesDialog({
    super.key,
    required this.operatorId,
    required this.operatorEmail,
    required this.operatorName,
  });

  @override
  ConsumerState<FaceFramesDialog> createState() => _FaceFramesDialogState();
}

class _Frame {
  final String path;
  final Uint8List bytes;
  final double quality;
  final bool specs;
  bool excluded;
  _Frame(this.path, this.bytes, this.quality, this.specs, this.excluded);
}

class _FaceFramesDialogState extends ConsumerState<FaceFramesDialog> {
  bool _loading = true;
  String? _error;
  List<_Frame> _frames = [];
  String _enrolledAt = '';

  bool _otpSent = false;
  bool _busy = false;
  String? _otpError;
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocus = List.generate(6, (_) => FocusNode());

  static const int _minKept = 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _otpControllers) { c.dispose(); }
    for (final f in _otpFocus) { f.dispose(); }
    super.dispose();
  }

  String get _otp => _otpControllers.map((c) => c.text).join();
  int get _keptCount => _frames.where((f) => !f.excluded).length;
  bool get _dirty => _frames.any((f) => f.excluded) || _changedFromServer;
  bool _changedFromServer = false;

  Future<void> _load() async {
    try {
      final paths = ref.read(firestorePathsProvider);
      final data = await CloudFunctionsService.call('getFaceFrames', {
        'companyId': paths.context.companyId,
        'operatorId': widget.operatorId,
      });
      final raw = (data['frames'] as List?) ?? [];
      _frames = raw.map((e) {
        final m = e as Map;
        return _Frame(
          m['path'] as String,
          base64Decode(m['image'] as String),
          (m['quality'] as num?)?.toDouble() ?? 0.0,
          m['specs'] == true,
          m['excluded'] == true,
        );
      }).toList();
      _enrolledAt = data['enrolledAt'] as String? ?? '';
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Could not load face frames: $e'; });
    }
  }

  void _toggle(_Frame f) {
    setState(() {
      f.excluded = !f.excluded;
      _changedFromServer = true;
    });
  }

  Future<void> _startApply() async {
    if (_keptCount < _minKept) {
      setState(() => _otpError = 'At least $_minKept frames must remain to keep a usable face model.');
      return;
    }
    final adminEmail = FirebaseAuth.instance.currentUser?.email;
    if (adminEmail == null || adminEmail.isEmpty) {
      setState(() => _otpError = 'Admin email unavailable.');
      return;
    }
    setState(() { _busy = true; _otpError = null; });
    try {
      await CloudFunctionsService.call('sendEmailOTP', {'email': adminEmail});
      setState(() { _otpSent = true; _busy = false; });
    } catch (e) {
      setState(() { _busy = false; _otpError = 'Failed to send verification code.'; });
    }
  }

  Future<void> _confirmApply() async {
    if (_otp.length != 6) {
      setState(() => _otpError = 'Enter the 6-digit code.');
      return;
    }
    final adminEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    setState(() { _busy = true; _otpError = null; });
    try {
      // 1. Verify the admin's OTP.
      await CloudFunctionsService.call('verifyEmailOTP', {'email': adminEmail, 'otp': _otp});

      // 2. Re-embed from the KEPT frames on the local sidecar (atomic — only
      //    write the doc once the new embedding is in hand).
      final kept = _frames.where((f) => !f.excluded).toList();
      final sidecar = ref.read(sidecarClientProvider);
      final result = await sidecar.enrollFromImages(kept.map((f) => f.bytes).toList());
      if (result == null || result.embedding.isEmpty) {
        setState(() { _busy = false; _otpError = 'Could not rebuild the face model from the remaining frames.'; });
        return;
      }

      // 3. Persist: new embedding, the excluded set, updated frame count.
      final paths = ref.read(firestorePathsProvider);
      final excludedPaths = _frames.where((f) => f.excluded).map((f) => f.path).toList();
      await paths.operators.doc(widget.operatorId).update({
        'faceEmbedding': result.embedding,
        'faceModelVersion': 'arcface_glintr100',
        'excludedFrames': excludedPaths,
        'faceEnrollment.validFrameCount': result.facesUsed,
        'faceEnrollment.enrolledAt': FieldValue.serverTimestamp(),
      });
      await sidecar.syncEnrollments(operators: [{
        'operator_id': widget.operatorId,
        'email': widget.operatorEmail,
        'name': widget.operatorName,
        'embedding': result.embedding,
        'is_active': true,
      }]);

      if (mounted) {
        Navigator.pop(context, true);
        AppError.success(context, 'Face model updated — ${excludedPaths.length} frame(s) excluded.');
      }
    } on FirebaseFunctionsException catch (e) {
      setState(() { _busy = false; _otpError = e.message ?? 'Invalid code.'; });
    } catch (e) {
      setState(() { _busy = false; _otpError = 'Update failed: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1000,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Padding(
          padding: AppSpacing.pagePadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.face_retouching_natural_rounded, size: 20, color: scheme.primary),
                  SizedBox(width: 10.rs),
                  Expanded(child: Text('Face Verification Images', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                  IconButton(onPressed: _busy ? null : () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, size: 18)),
                ],
              ),
              SizedBox(height: 4.rs),
              Text('Tap a frame to exclude it from the face model. Excluded frames are kept but won\'t be used for verification.',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              SizedBox(height: AppSpacing.lg),
              Flexible(child: _buildBody(scheme, text)),
              if (!_loading && _error == null) ...[
                SizedBox(height: AppSpacing.md),
                _buildFooter(scheme, text),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme scheme, TextTheme text) {
    if (_loading) return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
    if (_error != null) return Center(child: Text(_error!, style: text.bodySmall?.copyWith(color: scheme.error)));
    if (_frames.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('No stored frames for this operator. Frames are saved from the next enrollment onward.',
              textAlign: TextAlign.center, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ),
      );
    }
    final specs = _frames.where((f) => f.specs).toList();
    final noSpecs = _frames.where((f) => !f.specs).toList()
      ..sort((a, b) => b.quality.compareTo(a.quality)); // best quality first
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_enrolledAt.isNotEmpty) ...[
            Row(children: [
              Icon(Icons.event_rounded, size: 14, color: scheme.onSurfaceVariant),
              SizedBox(width: 6.rs),
              Text('Enrolled ${_formatEnrolledAt(_enrolledAt)}',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            ]),
            SizedBox(height: AppSpacing.md),
          ],
          if (specs.isNotEmpty) ...[
            _sectionHeader('With spectacles', specs.length, scheme, text),
            SizedBox(height: 8.rs),
            _grid(specs, scheme, showQuality: false),
            SizedBox(height: AppSpacing.lg),
          ],
          if (noSpecs.isNotEmpty) ...[
            _sectionHeader(specs.isNotEmpty ? 'Without spectacles · best quality first' : 'Captured frames · best quality first', noSpecs.length, scheme, text),
            SizedBox(height: 8.rs),
            _grid(noSpecs, scheme, showQuality: true),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, int count, ColorScheme scheme, TextTheme text) {
    return Text('$title  ·  $count',
        style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant));
  }

  Widget _grid(List<_Frame> frames, ColorScheme scheme, {required bool showQuality}) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, crossAxisSpacing: 8, mainAxisSpacing: 8),
      itemCount: frames.length,
      itemBuilder: (_, i) => _frameTile(frames[i], scheme, showQuality: showQuality),
    );
  }

  Widget _frameTile(_Frame f, ColorScheme scheme, {required bool showQuality}) {
    return GestureDetector(
      onTap: _busy ? null : () => _toggle(f),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: AppRadius.button,
            child: ColorFiltered(
              colorFilter: f.excluded
                  ? const ColorFilter.matrix(<double>[0.2126,0.7152,0.0722,0,0, 0.2126,0.7152,0.0722,0,0, 0.2126,0.7152,0.0722,0,0, 0,0,0,1,0])
                  : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
              child: Image.memory(f.bytes, fit: BoxFit.cover),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.button,
              border: Border.all(color: f.excluded ? scheme.error : AppTheme.successColor.withValues(alpha: 0.6), width: 2),
            ),
          ),
          Positioned(
            top: 4, right: 4,
            child: Icon(
              f.excluded ? Icons.cancel_rounded : Icons.check_circle_rounded,
              size: 18,
              color: f.excluded ? scheme.error : AppTheme.successColor,
            ),
          ),
          if (showQuality)
            Positioned(
              bottom: 4, left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(4)),
                child: Text('${(f.quality * 100).round()}%', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }

  String _formatEnrolledAt(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  Widget _buildFooter(ColorScheme scheme, TextTheme text) {
    if (_otpSent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Enter the 6-digit code sent to your admin email to confirm.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          SizedBox(height: 10.rs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (i) => Container(
              width: 38, height: 44, margin: EdgeInsets.only(right: i < 5 ? 6 : 0),
              child: TextField(
                controller: _otpControllers[i], focusNode: _otpFocus[i], textAlign: TextAlign.center,
                keyboardType: TextInputType.number, maxLength: 1,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(counterText: '', border: OutlineInputBorder(borderRadius: AppRadius.button)),
                onChanged: (v) {
                  if (v.isNotEmpty && i < 5) _otpFocus[i + 1].requestFocus();
                  if (v.isEmpty && i > 0) _otpFocus[i - 1].requestFocus();
                  if (_otp.length == 6) _confirmApply();
                },
              ),
            )),
          ),
          if (_otpError != null) ...[
            SizedBox(height: 8.rs),
            Text(_otpError!, style: text.bodySmall?.copyWith(color: scheme.error)),
          ],
          SizedBox(height: 12.rs),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _confirmApply,
              child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Confirm & Rebuild Model'),
            ),
          ),
        ],
      );
    }

    final excluded = _frames.where((f) => f.excluded).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('$_keptCount kept · $excluded excluded', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            if (_keptCount < _minKept)
              Text('Min $_minKept required', style: text.bodySmall?.copyWith(color: scheme.error)),
          ],
        ),
        if (_otpError != null) ...[
          SizedBox(height: 6.rs),
          Text(_otpError!, style: text.bodySmall?.copyWith(color: scheme.error)),
        ],
        SizedBox(height: 10.rs),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (!_dirty || _busy || _keptCount < _minKept) ? null : _startApply,
            icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.shield_rounded, size: 16),
            label: const Text('Apply Exclusions (verify)'),
          ),
        ),
      ],
    );
  }
}
