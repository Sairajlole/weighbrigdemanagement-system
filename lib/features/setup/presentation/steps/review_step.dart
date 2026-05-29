import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/models/license_model.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import 'package:weighbridgemanagement/shared/providers/license_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';
import 'package:weighbridgemanagement/shared/services/platform_service.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import '../../application/setup_wizard_provider.dart';
import '../../application/setup_wizard_state.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

class ReviewStep extends ConsumerStatefulWidget {
  const ReviewStep({super.key});

  @override
  ConsumerState<ReviewStep> createState() => _ReviewStepState();
}

class _ReviewStepState extends ConsumerState<ReviewStep> with TickerProviderStateMixin {
  String _siteName = '';
  String _wbName = '';
  String _companyName = '';
  String _companyGstin = '';
  bool _loaded = false;
  bool _completing = false;
  bool _completed = false;

  // Operator-specific state
  bool _operatorSuccess = false;
  bool _pendingApproval = false;
  bool _checkingApproval = false;
  String? _approvalError;
  String? _rejectedReason;

  late final AnimationController _checkController;
  late final AnimationController _confettiController;
  late final Animation<double> _checkScale;
  late final Animation<double> _checkOpacity;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _confettiController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

    _checkScale = CurvedAnimation(parent: _checkController, curve: Curves.elasticOut);
    _checkOpacity = CurvedAnimation(parent: _checkController, curve: const Interval(0, 0.5, curve: Curves.easeIn));

    _loadNames();
  }

  @override
  void dispose() {
    _checkController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _loadNames() async {
    final siteCtx = ref.read(siteContextProvider);
    final companyId = siteCtx.companyId.isNotEmpty
        ? siteCtx.companyId
        : ref.read(wizardCompanyIdProvider) ?? '';
    final db = ref.read(firestoreProvider);

    // Load company info
    if (companyId.isNotEmpty) {
      try {
        final compSnap = await db.doc('companies/$companyId').get();
        final compData = compSnap.data();
        if (mounted && compData != null) {
          _companyName = compData['name'] as String? ?? '';
          _companyGstin = compData['gstin'] as String? ?? '';
        }
      } catch (_) {}
    }

    if (!siteCtx.isConfigured) {
      setState(() => _loaded = true);
      return;
    }
    try {
      final siteFuture = db.doc(siteCtx.sitePath).get();
      final wbFuture = db.doc(siteCtx.weighbridgePath).get();
      final results = await Future.wait([siteFuture, wbFuture]);
      final siteData = results[0].data();
      final wbData = results[1].data();
      if (mounted) {
        setState(() {
          _siteName = siteData?['name'] as String? ?? siteCtx.siteId;
          _wbName = wbData?['name'] as String? ?? siteCtx.weighbridgeId;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _completeSetup() async {
    setState(() => _completing = true);

    ref.read(wizardProgressProvider.notifier).markComplete();

    // Mark first login complete on the company doc
    final siteCtx = ref.read(siteContextProvider);
    final companyId = siteCtx.companyId.isNotEmpty
        ? siteCtx.companyId
        : ref.read(wizardCompanyIdProvider) ?? '';
    if (companyId.isNotEmpty) {
      final db = ref.read(firestoreProvider);
      await db.doc('companies/$companyId').set({'firstLoginComplete': true}, SetOptions(merge: true));
    }

    await Future.delayed(const Duration(milliseconds: 300));
    setState(() => _completed = true);

    _checkController.forward();
    _confettiController.forward();
    _playSuccessSound();

    await Future.delayed(const Duration(milliseconds: 2200));
    if (mounted) context.go('/dashboard');
  }

  void _playSuccessSound() {
    PlatformService.playSound(SoundType.complete);
  }

  Future<void> _checkApprovalStatus() async {
    final docPath = ref.read(wizardOperatorDocPathProvider);
    if (docPath == null) return;
    setState(() { _checkingApproval = true; _approvalError = null; });

    try {
      final db = ref.read(firestorePathsProvider).firestore;
      final snap = await db.doc(docPath).get();
      final data = snap.data();
      if (data == null) {
        // Doc deleted — check if rejected
        final email = ref.read(wizardOperatorFormDataProvider)?['email'] as String? ?? '';
        final companyId = ref.read(wizardCompanyIdProvider) ?? ref.read(siteContextProvider).companyId;
        if (email.isNotEmpty && companyId.isNotEmpty) {
          final rejSnap = await db.collection('companies/$companyId/rejections')
              .where('email', isEqualTo: email).limit(1).get();
          if (rejSnap.docs.isNotEmpty) {
            final reason = rejSnap.docs.first.data()['reason'] as String? ?? '';
            setState(() {
              _checkingApproval = false;
              _rejectedReason = reason;
              _approvalError = 'Your registration was rejected.${reason.isNotEmpty ? '\nReason: $reason' : ''}\n\nYou can re-register with updated information.';
            });
            return;
          }
        }
        setState(() { _checkingApproval = false; _approvalError = 'Account not found.'; });
        return;
      }
      final isActive = data['isActive'] == true;
      final isVerified = data['isVerified'] == true;
      if (isActive && isVerified) {
        _completeOperatorSetup();
      } else {
        setState(() { _checkingApproval = false; _approvalError = 'Still awaiting approval...'; });
      }
    } catch (e) {
      setState(() { _checkingApproval = false; _approvalError = 'Could not check status. Try again.'; });
    }
  }

  void _completeOperatorSetup() {
    setState(() => _operatorSuccess = true);
    _checkController.forward();
    _confettiController.forward();
    _playSuccessSound();
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      _navigateOperatorToDashboard();
    });
  }

  Future<void> _navigateOperatorToDashboard() async {
    final companyId = ref.read(wizardCompanyIdProvider) ?? '';
    try {
      final db = ref.read(firestorePathsProvider).firestore;
      final sitesSnap = await db.collection('companies/$companyId/sites').limit(1).get();
      if (sitesSnap.docs.isNotEmpty) {
        final siteId = sitesSnap.docs.first.id;
        final wbSnap = await db.collection('companies/$companyId/sites/$siteId/weighbridges').limit(1).get();
        if (wbSnap.docs.isNotEmpty) {
          await ref.read(siteContextProvider.notifier).configure(
            companyId: companyId,
            siteId: siteId,
            weighbridgeId: wbSnap.docs.first.id,
          );
        }
      }
    } catch (_) {}
    if (mounted) context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final wizardState = ref.watch(setupWizardProvider);

    if (_completed || _operatorSuccess) return _buildCompletionView(scheme, text);

    // Operator flow
    if (wizardState.role == WizardRole.operator) {
      if (_pendingApproval) return _buildPendingApprovalView(scheme, text);
      return _buildOperatorReviewView(scheme, text);
    }

    final license = ref.watch(licenseProvider);
    final tierLabel = switch (license.tier) {
      LicenseTier.pro => 'Pro',
      LicenseTier.trial => 'Pro Trial (30 days)',
      LicenseTier.free => 'Free',
    };
    final tierColor = switch (license.tier) {
      LicenseTier.pro => AppTheme.proColor,
      LicenseTier.trial => scheme.primary,
      LicenseTier.free => scheme.onSurfaceVariant,
    };

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(48.rs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20.rs),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
              ),
              child: Icon(Icons.rocket_launch_rounded, size: 32, color: scheme.primary),
            ),
            SizedBox(height: 24.rs),
            Text('Ready to Launch', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            SizedBox(height: 8.rs),
            Text(
              'Your weighbridge system is configured and ready to go.',
              style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            SizedBox(height: 40.rs),

            // Plan & Site card
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                padding: EdgeInsets.all(20.rs),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16.rs),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    // Plan row
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: tierColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10.rs),
                          ),
                          child: Icon(Icons.workspace_premium_rounded, size: 20, color: tierColor),
                        ),
                        SizedBox(width: 14.rs),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Plan', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                              Text(tierLabel, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tierColor)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.2)),
                    ),
                    // Site row
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10.rs),
                          ),
                          child: Icon(Icons.location_on_rounded, size: 20, color: scheme.primary),
                        ),
                        SizedBox(width: 14.rs),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Site', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                              Text(
                                _loaded ? (_siteName.isNotEmpty ? _siteName : '--') : '...',
                                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 14.rs),
                    // Weighbridge row
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: scheme.tertiary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10.rs),
                          ),
                          child: Icon(Icons.scale_rounded, size: 20, color: scheme.tertiary),
                        ),
                        SizedBox(width: 14.rs),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Weighbridge', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                              Text(
                                _loaded ? (_wbName.isNotEmpty ? _wbName : '--') : '...',
                                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 32.rs),

            // Info text
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                'All settings can be modified later from the Settings menu.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),

            SizedBox(height: 32.rs),

            // Complete button
            FilledButton.icon(
              onPressed: _completing ? null : _completeSetup,
              icon: _completing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded, size: 20),
              label: Text(_completing ? 'Launching...' : 'Complete Setup'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletionView(ColorScheme scheme, TextTheme text) {
    return Stack(
      children: [
        // Confetti
        AnimatedBuilder(
          animation: _confettiController,
          builder: (context, _) => CustomPaint(
            size: MediaQuery.of(context).size,
            painter: _ConfettiPainter(progress: _confettiController.value, scheme: scheme),
          ),
        ),
        // Centered success
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _checkScale,
                child: FadeTransition(
                  opacity: _checkOpacity,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary,
                      boxShadow: [
                        BoxShadow(color: scheme.primary.withValues(alpha: 0.3), blurRadius: 24, spreadRadius: 4),
                      ],
                    ),
                    child: Icon(Icons.check_rounded, size: 48, color: scheme.onPrimary),
                  ),
                ),
              ),
              SizedBox(height: 24.rs),
              FadeTransition(
                opacity: _checkOpacity,
                child: Text(
                  'Setup Complete!',
                  style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
                ),
              ),
              SizedBox(height: 8.rs),
              FadeTransition(
                opacity: _checkOpacity,
                child: Text(
                  'Taking you to the dashboard...',
                  style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOperatorReviewView(ColorScheme scheme, TextTheme text) {
    final isInvited = ref.read(wizardOperatorInvitedProvider);
    final formData = ref.read(wizardOperatorFormDataProvider);
    final faceEnrolled = ref.read(wizardFaceEnrolledProvider);
    final docType = ref.read(wizardSubmittedDocTypeProvider);

    final operatorName = formData?['name'] as String? ?? '';
    final operatorEmail = formData?['email'] as String? ?? '';
    final operatorPhone = formData?['phone'] as String? ?? '';
    final operatorAddress = formData?['address'] as String? ?? '';
    final operatorAddress2 = formData?['address2'] as String? ?? '';
    final idDocNumber = formData?['idDocNumber'] as String? ?? '';


    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(48.rs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20.rs),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
              ),
              child: Icon(
                isInvited ? Icons.how_to_reg_rounded : Icons.send_rounded,
                size: 32,
                color: scheme.primary,
              ),
            ),
            SizedBox(height: 24.rs),
            Text(
              isInvited ? 'Ready to Go' : 'Review & Submit',
              style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
            ),
            SizedBox(height: 8.rs),
            Text(
              isInvited
                  ? 'Your account is set up and ready to use.'
                  : 'Review your details and submit your registration for approval.',
              style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 32.rs),

            // Company info card
            if (_companyName.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  padding: EdgeInsets.all(20.rs),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16.rs),
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.business_rounded, size: 18, color: scheme.tertiary),
                          SizedBox(width: 8.rs),
                          Text('Company', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.tertiary)),
                        ],
                      ),
                      SizedBox(height: 16.rs),
                      _infoRow(scheme, Icons.domain_rounded, 'Name', _companyName),
                      if (_companyGstin.isNotEmpty) ...[
                        SizedBox(height: 12.rs),
                        _infoRow(scheme, Icons.receipt_long_rounded, 'GSTIN', _companyGstin),
                      ],
                    ],
                  ),
                ),
              ),

            // Operator info card
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: EdgeInsets.all(20.rs),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16.rs),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person_rounded, size: 18, color: scheme.primary),
                        SizedBox(width: 8.rs),
                        Text('Your Details', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.primary)),
                      ],
                    ),
                    SizedBox(height: 16.rs),
                    _infoRow(scheme, Icons.badge_rounded, 'Name', operatorName),
                    SizedBox(height: 12.rs),
                    _infoRow(scheme, Icons.email_rounded, 'Email', operatorEmail),
                    SizedBox(height: 12.rs),
                    _infoRow(scheme, Icons.phone_rounded, 'Phone', operatorPhone),
                    if (operatorAddress.isNotEmpty) ...[
                      SizedBox(height: 12.rs),
                      _infoRow(scheme, Icons.location_on_rounded, 'Address',
                        operatorAddress2.isNotEmpty ? '$operatorAddress, $operatorAddress2' : operatorAddress),
                    ],
                    if (idDocNumber.isNotEmpty) ...[
                      SizedBox(height: 12.rs),
                      _infoRow(scheme, Icons.credit_card_rounded, docType ?? 'ID', idDocNumber),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(height: 16.rs),

            // Status card
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: EdgeInsets.all(20.rs),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16.rs),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    _statusRow(
                      scheme,
                      Icons.verified_user_rounded,
                      'ID Verification',
                      docType != null ? 'Verified ($docType)' : 'Completed',
                      AppTheme.successColor,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.2)),
                    ),
                    _statusRow(
                      scheme,
                      Icons.face_rounded,
                      'Face Enrollment',
                      faceEnrolled ? 'Enrolled' : 'Skipped',
                      faceEnrolled ? AppTheme.successColor : scheme.onSurfaceVariant,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.2)),
                    ),
                    _statusRow(
                      scheme,
                      Icons.mark_email_read_rounded,
                      'Email & Phone',
                      'Verified',
                      AppTheme.successColor,
                    ),
                  ],
                ),
              ),
            ),

            if (!isInvited) ...[
              SizedBox(height: 16.rs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  padding: EdgeInsets.all(14.rs),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12.rs),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: Colors.orange.shade700),
                      SizedBox(width: 12.rs),
                      Expanded(
                        child: Text(
                          'After submitting, your administrator will review and approve your registration. You can check your approval status anytime.',
                          style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            SizedBox(height: 32.rs),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _completing ? null : () => ref.read(setupWizardProvider.notifier).previousStep(),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Back'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                ),
                SizedBox(width: 16.rs),
                FilledButton.icon(
                  onPressed: _completing ? null : _completeOperator,
                  icon: _completing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Icon(isInvited ? Icons.check_rounded : Icons.send_rounded, size: 20),
                  label: Text(
                    _completing
                        ? 'Submitting...'
                        : (isInvited ? 'Complete Setup' : 'Submit Request'),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(ColorScheme scheme, IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
        SizedBox(width: 10.rs),
        SizedBox(
          width: 72,
          child: Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
        ),
        SizedBox(width: 8.rs),
        Expanded(
          child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        ),
      ],
    );
  }

  Widget _statusRow(ColorScheme scheme, IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8.rs),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        SizedBox(width: 12.rs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
              Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
        Icon(
          color == AppTheme.successColor ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
          size: 16,
          color: color,
        ),
      ],
    );
  }

  Future<void> _completeOperator() async {
    setState(() => _completing = true);
    final isInvited = ref.read(wizardOperatorInvitedProvider);

    if (isInvited) {
      await Future.delayed(const Duration(milliseconds: 400));
      _completeOperatorSetup();
    } else {
      // Now actually create the operator doc in Firestore
      try {
        final formData = ref.read(wizardOperatorFormDataProvider);
        if (formData == null) {
          setState(() { _completing = false; });
          return;
        }

        final db = ref.read(firestoreProvider);
        final companyId = ref.read(wizardCompanyIdProvider) ?? ref.read(siteContextProvider).companyId;
        if (companyId.isEmpty) {
          setState(() { _completing = false; });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Company not resolved. Please go back and verify your company code.')),
            );
          }
          return;
        }
        final now = Timestamp.now();
        final data = Map<String, dynamic>.from(formData);
        data['createdAt'] = now;
        data.removeWhere((k, v) => v == null);

        // Store ID doc images as Firestore Blobs (raw bytes, not base64)
        final idDocImagesB64 = data.remove('idDocImages') as List<String>?;
        if (idDocImagesB64 != null && idDocImagesB64.isNotEmpty) {
          data['idDocImages'] = idDocImagesB64.map((b64) => Blob(base64Decode(b64))).toList();
          data['hasIdDoc'] = true;
        }

        final newDoc = await db.collection('companies/$companyId/operators').add(data);

        final email = data['email'] as String? ?? '';
        await LocalCacheService.cacheCurrentUserEmail(email);
        ref.read(wizardOperatorDocPathProvider.notifier).state = newDoc.path;

        // Enroll face if frames were captured
        final faceFrames = ref.read(wizardFaceFramesProvider);
        if (faceFrames != null && faceFrames.isNotEmpty && companyId.isNotEmpty) {
          try {
            await FirebaseFunctions.instance
                .httpsCallable('enrollOperatorFace', options: HttpsCallableOptions(timeout: const Duration(seconds: 120)))
                .call({'images': faceFrames, 'companyId': companyId, 'operatorEmail': email});
          } catch (e) {
            debugPrint('[ReviewStep] Face enrollment failed (non-blocking): $e');
          }

          // Generate sidecar embedding for local face identification
          try {
            final sidecar = ref.read(sidecarClientProvider);
            if (await sidecar.isAvailable()) {
              final frameBytes = faceFrames.map((f) => Uint8List.fromList(base64Decode(f))).toList();
              final result = await sidecar.enrollFromImages(frameBytes);
              if (result != null && result.embedding.isNotEmpty) {
                await db.doc(newDoc.path).update({
                  'faceEmbedding': result.embedding,
                  'faceModelVersion': 'arcface_glintr100',
                });
                await sidecar.syncEnrollments(operators: [{
                  'operator_id': newDoc.id,
                  'email': email,
                  'name': data['name'] as String? ?? '',
                  'embedding': result.embedding,
                  'is_active': true,
                }]);
                debugPrint('[ReviewStep] Sidecar embedding generated and cached');
              }
            }
          } catch (e) {
            debugPrint('[ReviewStep] Sidecar embedding generation failed (non-blocking): $e');
          }
        }

        // Play success animation then go to pending
        setState(() => _completed = true);
        _checkController.forward();
        _confettiController.forward();
        _playSuccessSound();

        await Future.delayed(const Duration(milliseconds: 2200));
        if (mounted) {
          ref.read(wizardFullscreenModeProvider.notifier).state = true;
          setState(() { _completed = false; _completing = false; _pendingApproval = true; });
        }
      } catch (e) {
        setState(() { _completing = false; });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to submit: $e')),
          );
        }
      }
    }
  }

  Widget _buildPendingApprovalView(ColorScheme scheme, TextTheme text) {
    final formData = ref.read(wizardOperatorFormDataProvider);
    final faceEnrolled = ref.read(wizardFaceEnrolledProvider);
    final docType = ref.read(wizardSubmittedDocTypeProvider) ?? formData?['idDocType'] as String?;
    final operatorName = formData?['name'] as String? ?? '';
    final operatorEmail = formData?['email'] as String? ?? '';
    final operatorPhone = formData?['phone'] as String? ?? '';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              SizedBox(height: 24.rs),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.tertiaryContainer.withValues(alpha: 0.3),
                  border: Border.all(color: scheme.tertiary.withValues(alpha: 0.2), width: 2),
                ),
                child: Icon(Icons.hourglass_top_rounded, size: 40, color: scheme.tertiary),
              ),
              SizedBox(height: 24.rs),
              Text('Awaiting Admin Approval', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              SizedBox(height: 10.rs),
              Text(
                'Your registration has been submitted successfully. An administrator will review and approve your request.',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 28.rs),

              // Summary card
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(20.rs),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16.rs),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person_rounded, size: 16, color: scheme.primary),
                        SizedBox(width: 8.rs),
                        Text('Registration Summary', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.primary)),
                      ],
                    ),
                    SizedBox(height: 16.rs),
                    if (operatorName.isNotEmpty) ...[
                      _infoRow(scheme, Icons.badge_rounded, 'Name', operatorName),
                      SizedBox(height: 10.rs),
                    ],
                    _infoRow(scheme, Icons.email_rounded, 'Email', operatorEmail),
                    SizedBox(height: 10.rs),
                    if (operatorPhone.isNotEmpty) ...[
                      _infoRow(scheme, Icons.phone_rounded, 'Phone', operatorPhone),
                      SizedBox(height: 10.rs),
                    ],
                    if (_companyName.isNotEmpty)
                      _infoRow(scheme, Icons.business_rounded, 'Company', _companyName),
                  ],
                ),
              ),
              SizedBox(height: 12.rs),

              // Verification status
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16.rs),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16.rs),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    _statusRow(scheme, Icons.verified_user_rounded, 'ID Verification', docType != null ? 'Verified' : 'Skipped',
                        docType != null ? AppTheme.successColor : scheme.onSurfaceVariant),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.2))),
                    _statusRow(scheme, Icons.face_rounded, 'Face Enrollment', faceEnrolled ? 'Enrolled' : 'Skipped',
                        faceEnrolled ? AppTheme.successColor : scheme.onSurfaceVariant),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.2))),
                    _statusRow(scheme, Icons.send_rounded, 'Request Status', 'Pending',
                        scheme.tertiary),
                  ],
                ),
              ),
              SizedBox(height: 24.rs),

              if (_approvalError != null) ...[
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12.rs),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _rejectedReason != null
                        ? scheme.errorContainer.withValues(alpha: 0.2)
                        : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10.rs),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _rejectedReason != null ? Icons.cancel_rounded : Icons.info_outline_rounded,
                        size: 16,
                        color: _rejectedReason != null ? scheme.error : scheme.onSurfaceVariant,
                      ),
                      SizedBox(width: 10.rs),
                      Expanded(
                        child: Text(
                          _approvalError!,
                          style: TextStyle(fontSize: 13, color: _rejectedReason != null ? scheme.error : scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_rejectedReason != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      ref.read(wizardFullscreenModeProvider.notifier).state = false;
                      ref.read(wizardPrefillEmailProvider.notifier).state = null;
                      ref.read(wizardShowResumeSignInProvider.notifier).state = false;
                      ref.read(wizardOperatorInvitedProvider.notifier).state = false;
                      ref.read(wizardOperatorDocPathProvider.notifier).state = null;
                      ref.read(wizardOperatorFormDataProvider.notifier).state = null;
                      ref.read(wizardFaceFramesProvider.notifier).state = null;
                      ref.read(wizardFaceEnrolledProvider.notifier).state = false;
                      ref.read(wizardIdDocImagesProvider.notifier).state = null;
                      ref.read(wizardIdFacePhotoProvider.notifier).state = null;
                      ref.read(setupWizardProvider.notifier).reset();
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Re-register'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _checkingApproval ? null : _checkApprovalStatus,
                    icon: _checkingApproval
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(_checkingApproval ? 'Checking...' : 'Check Approval Status'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
              SizedBox(height: 12.rs),
              TextButton.icon(
                onPressed: () {
                  ref.read(wizardFullscreenModeProvider.notifier).state = false;
                  ref.read(wizardPrefillEmailProvider.notifier).state = null;
                  ref.read(wizardShowResumeSignInProvider.notifier).state = false;
                  ref.read(wizardOperatorInvitedProvider.notifier).state = false;
                  ref.read(wizardOperatorDocPathProvider.notifier).state = null;
                  ref.read(setupWizardProvider.notifier).goToWelcome();
                },
                icon: Icon(Icons.logout_rounded, size: 14, color: scheme.onSurfaceVariant),
                label: Text('Exit', style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final double progress;
  final ColorScheme scheme;
  static final _random = Random(42);
  static final _particles = List.generate(60, (_) => _ConfettiParticle.random(_random));

  _ConfettiPainter({required this.progress, required this.scheme});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0) return;
    final colors = [
      scheme.primary,
      scheme.tertiary,
      scheme.error,
      const Color(0xFFEA580C),
      const Color(0xFFCA8A04),
      const Color(0xFF16A34A),
    ];

    for (final p in _particles) {
      final t = progress;
      final x = size.width * p.startX + p.dx * t * size.width * 0.5;
      final y = -20 + (size.height + 40) * t * p.speed + p.dy * sin(t * pi * 3) * 30;
      final opacity = (1.0 - t).clamp(0.0, 1.0);
      final paint = Paint()..color = colors[p.colorIndex % colors.length].withValues(alpha: opacity * 0.8);
      final rotation = t * p.rotationSpeed * pi * 4;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      if (p.isRect) {
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6), paint);
      } else {
        canvas.drawCircle(Offset.zero, p.size * 0.4, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

class _ConfettiParticle {
  final double startX;
  final double dx;
  final double dy;
  final double speed;
  final double size;
  final double rotationSpeed;
  final int colorIndex;
  final bool isRect;

  const _ConfettiParticle({
    required this.startX,
    required this.dx,
    required this.dy,
    required this.speed,
    required this.size,
    required this.rotationSpeed,
    required this.colorIndex,
    required this.isRect,
  });

  factory _ConfettiParticle.random(Random r) => _ConfettiParticle(
    startX: r.nextDouble(),
    dx: r.nextDouble() * 2 - 1,
    dy: r.nextDouble() * 2 - 1,
    speed: 0.5 + r.nextDouble() * 0.5,
    size: 4 + r.nextDouble() * 6,
    rotationSpeed: 0.5 + r.nextDouble(),
    colorIndex: r.nextInt(6),
    isRect: r.nextBool(),
  );
}
