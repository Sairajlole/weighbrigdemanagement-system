import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/models/license_model.dart';
import 'package:weighbridgemanagement/shared/providers/license_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/providers/version_provider.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

class LicenseScreen extends ConsumerStatefulWidget {
  const LicenseScreen({super.key});

  @override
  ConsumerState<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends ConsumerState<LicenseScreen> {
  final _keyCtrl = TextEditingController();
  bool _activating = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _activateKey() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Please enter a license key');
      return;
    }

    setState(() { _activating = true; _error = null; _success = null; });

    final notifier = ref.read(licenseProvider.notifier);
    final ctx = ref.read(siteContextProvider);
    final success = await notifier.activate(
      licenseKey: key,
      gstin: '',
      companyId: ctx.companyId,
    );

    if (mounted) {
      setState(() {
        _activating = false;
        if (success) {
          _success = 'License activated successfully!';
          _keyCtrl.clear();
        } else {
          _error = 'Invalid or already-used license key';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final license = ref.watch(licenseProvider);
    final versionAsync = ref.watch(versionProvider);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => context.go('/settings'),
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs))),
                ),
                SizedBox(width: 12.rs),
                Icon(Icons.workspace_premium_rounded, size: 22, color: scheme.primary),
                SizedBox(width: 10.rs),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('License & Updates', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Manage subscription, activate keys, and check for updates', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(28.rs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusHero(license, scheme, text),
                  SizedBox(height: 24.rs),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: Column(
                        children: [
                          if (license.effectiveTier != LicenseTier.pro) ...[
                            _buildActivateCard(scheme, text),
                            SizedBox(height: 20.rs),
                          ],
                          _buildPlanCards(license, scheme, text),
                          SizedBox(height: 20.rs),
                          _buildFeatureBreakdown(license, scheme, text),
                        ],
                      )),
                      SizedBox(width: 20.rs),
                      Expanded(flex: 2, child: Column(
                        children: [
                          _buildLicenseDetails(license, scheme, text),
                          SizedBox(height: 20.rs),
                          _buildUsageLimits(license, scheme, text),
                          SizedBox(height: 20.rs),
                          versionAsync.when(
                            data: (info) => _buildVersionCard(info, scheme, text),
                            loading: () => const SizedBox.shrink(),
                            error: (_, __) => const SizedBox.shrink(),
                          ),
                        ],
                      )),
                    ],
                  ),
                  SizedBox(height: 40.rs),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusHero(License license, ColorScheme scheme, TextTheme text) {
    final effective = license.effectiveTier;
    final trialActive = license.isTrial && license.isValid;
    final trialExpired = license.isTrial && !license.isValid;

    final tierColor = switch (effective) {
      LicenseTier.pro => AppTheme.proColor,
      LicenseTier.trial => scheme.primary,
      LicenseTier.free => scheme.onSurfaceVariant,
    };

    final tierLabel = trialExpired
        ? 'Trial Expired'
        : switch (effective) {
            LicenseTier.pro => 'Pro License',
            LicenseTier.trial => 'Pro Trial',
            LicenseTier.free => 'Free Plan',
          };

    final subtitle = trialExpired
        ? 'Your trial has ended. Upgrade to Pro to restore full access.'
        : switch (effective) {
            LicenseTier.pro => 'All features unlocked. No limits on weighbridges or sites.',
            LicenseTier.trial => 'Full access to all Pro features for the trial period.',
            LicenseTier.free => 'Basic weighment features with 1 weighbridge and 1 site.',
          };

    return Container(
      padding: EdgeInsets.all(24.rs),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            (trialExpired ? scheme.error : tierColor).withValues(alpha: 0.08),
            (trialExpired ? scheme.error : tierColor).withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16.rs),
        border: Border.all(color: (trialExpired ? scheme.error : tierColor).withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: (trialExpired ? scheme.error : tierColor).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16.rs),
            ),
            child: Icon(
              trialExpired ? Icons.timer_off_rounded
                  : effective == LicenseTier.pro ? Icons.workspace_premium_rounded
                  : effective == LicenseTier.trial ? Icons.timer_rounded
                  : Icons.shield_outlined,
              color: trialExpired ? scheme.error : tierColor,
              size: 28,
            ),
          ),
          SizedBox(width: 20.rs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(tierLabel, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: trialExpired ? scheme.error : tierColor)),
                    SizedBox(width: 12.rs),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: license.isValid
                            ? Colors.green.withValues(alpha: 0.1)
                            : scheme.errorContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(6.rs),
                      ),
                      child: Text(
                        license.isValid ? 'Active' : 'Expired',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: license.isValid ? Colors.green : scheme.error),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4.rs),
                Text(subtitle, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (trialActive) ...[
            SizedBox(width: 16.rs),
            _buildTrialProgress(license, scheme, text),
          ],
        ],
      ),
    );
  }

  Widget _buildTrialProgress(License license, ColorScheme scheme, TextTheme text) {
    final daysRemaining = license.daysRemaining;
    final progress = daysRemaining > 0 ? (30 - daysRemaining) / 30.0 : 1.0;
    final urgent = daysRemaining <= 7;

    return Container(
      width: 100,
      padding: EdgeInsets.all(12.rs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12.rs),
        border: Border.all(color: urgent ? Colors.orange.withValues(alpha: 0.3) : scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text('$daysRemaining', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: urgent ? Colors.orange.shade700 : scheme.primary)),
          Text('days left', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          SizedBox(height: 8.rs),
          ClipRRect(
            borderRadius: BorderRadius.circular(4.rs),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: scheme.surfaceContainerHigh,
              color: urgent ? Colors.orange : scheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivateCard(ColorScheme scheme, TextTheme text) {
    return Container(
      padding: EdgeInsets.all(22.rs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.proColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8.rs),
                ),
                child: const Icon(Icons.vpn_key_rounded, size: 16, color: AppTheme.proColor),
              ),
              SizedBox(width: 12.rs),
              Text('Activate Pro License', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          SizedBox(height: 6.rs),
          Text('Enter a license key to unlock all Pro features permanently.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          SizedBox(height: 16.rs),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keyCtrl,
                  decoration: InputDecoration(
                    hintText: 'XXXX-XXXX-XXXX-XXXX',
                    prefixIcon: const Icon(Icons.key_rounded, size: 18),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.rs)),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 1),
                  onSubmitted: (_) => _activateKey(),
                ),
              ),
              SizedBox(width: 12.rs),
              FilledButton.icon(
                onPressed: _activating ? null : _activateKey,
                icon: _activating
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_rounded, size: 16),
                label: const Text('Activate'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  backgroundColor: AppTheme.proColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.rs)),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            SizedBox(height: 10.rs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: scheme.errorContainer.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(6.rs)),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, size: 14, color: scheme.error),
                  SizedBox(width: 6.rs),
                  Expanded(child: Text(_error!, style: TextStyle(fontSize: 11, color: scheme.error))),
                ],
              ),
            ),
          ],
          if (_success != null) ...[
            SizedBox(height: 10.rs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6.rs)),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, size: 14, color: Colors.green),
                  SizedBox(width: 6.rs),
                  Expanded(child: Text(_success!, style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600))),
                ],
              ),
            ),
          ],
          SizedBox(height: 14.rs),
          Container(
            padding: EdgeInsets.all(12.rs),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8.rs),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                SizedBox(width: 8.rs),
                Expanded(
                  child: Text(
                    'License keys are priced per weighbridge. Contact sales@weighbridge.app for a key.',
                    style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCards(License license, ColorScheme scheme, TextTheme text) {
    final effective = license.effectiveTier;

    return Container(
      padding: EdgeInsets.all(22.rs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8.rs),
                ),
                child: Icon(Icons.compare_arrows_rounded, size: 16, color: scheme.primary),
              ),
              SizedBox(width: 12.rs),
              Text('Plan Comparison', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (effective == LicenseTier.pro ? AppTheme.proColor : effective == LicenseTier.trial ? scheme.primary : scheme.onSurfaceVariant).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4.rs),
                ),
                child: Text(
                  'Current: ${effective == LicenseTier.pro ? 'Pro' : effective == LicenseTier.trial ? 'Trial' : 'Free'}',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: effective == LicenseTier.pro ? AppTheme.proColor : effective == LicenseTier.trial ? scheme.primary : scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          SizedBox(height: 20.rs),

          // Two plan cards side by side
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _PlanCard(
                  title: 'Free',
                  price: 'Always free',
                  icon: Icons.shield_outlined,
                  isActive: effective == LicenseTier.free,
                  color: scheme.onSurfaceVariant,
                  limits: const ['1 weighbridge', '1 site', 'No expiry'],
                  features: const [
                    'Basic weighments & customers',
                    'Manual weight capture',
                    'Simple docket printing',
                    'USB camera verification',
                    'Dashboard & basic reports',
                    'Scale connection',
                  ],
                  scheme: scheme,
                  text: text,
                )),
                SizedBox(width: 14.rs),
                Expanded(child: _PlanCard(
                  title: 'Pro',
                  price: 'Per weighbridge/year',
                  icon: Icons.workspace_premium_rounded,
                  badge: 'Full Power',
                  isActive: effective == LicenseTier.pro || effective == LicenseTier.trial,
                  color: AppTheme.proColor,
                  limits: const ['Unlimited WBs', 'Unlimited sites', '1-year license'],
                  features: const [
                    'Everything in Free, plus:',
                    'Multiple weighbridges & sites',
                    'IP cameras & RTSP streams',
                    'AI: ANPR, face, material detection',
                    'Gate control & RFID automation',
                    'Tally ERP integration',
                    'Advanced security (MFA, IP lock)',
                    'PDF417 barcodes & advanced printing',
                    'Cross-site reporting & exports',
                    'Priority support & updates',
                  ],
                  scheme: scheme,
                  text: text,
                )),
              ],
            ),
          ),

          // Trial fallback info (if on trial)
          if (license.isTrial && license.isValid) ...[
            SizedBox(height: 16.rs),
            Container(
              padding: EdgeInsets.all(14.rs),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10.rs),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: scheme.primary),
                  SizedBox(width: 10.rs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'After your trial ends',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface),
                        ),
                        SizedBox(height: 4.rs),
                        Text(
                          'Your account will move to the Free plan. All data is preserved — Pro features are locked until you upgrade. You can upgrade anytime with a license key.',
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFeatureBreakdown(License license, ColorScheme scheme, TextTheme text) {
    final effective = license.effectiveTier;
    final isPro = effective == LicenseTier.pro || effective == LicenseTier.trial;

    return Container(
      padding: EdgeInsets.all(22.rs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8.rs),
                ),
                child: Icon(Icons.featured_play_list_rounded, size: 16, color: scheme.primary),
              ),
              SizedBox(width: 12.rs),
              Text('Feature Details', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          SizedBox(height: 20.rs),

          // Feature groups
          _FeatureGroupWidget(
            icon: Icons.scale_rounded,
            title: 'Weighing & Capture',
            items: [
              _FeatureItem('Unlimited weighments', true, true),
              _FeatureItem('Manual weight capture', true, true),
              _FeatureItem('Auto capture (scale-triggered)', false, true),
              _FeatureItem('Tare weight management', true, true),
              _FeatureItem('Custom fields per weighment', false, true),
            ],
            isPro: isPro,
            scheme: scheme,
            text: text,
          ),
          SizedBox(height: 16.rs),
          _FeatureGroupWidget(
            icon: Icons.videocam_rounded,
            title: 'Cameras & AI',
            items: [
              _FeatureItem('USB camera verification', true, true),
              _FeatureItem('IP cameras & RTSP streams', false, true),
              _FeatureItem('ANPR (license plate reading)', false, true),
              _FeatureItem('Face verification', false, true),
              _FeatureItem('Material detection (YOLO AI)', false, true),
            ],
            isPro: isPro,
            scheme: scheme,
            text: text,
          ),
          SizedBox(height: 16.rs),
          _FeatureGroupWidget(
            icon: Icons.door_sliding_rounded,
            title: 'Automation & Hardware',
            items: [
              _FeatureItem('Scale connection (RS232/TCP)', true, true),
              _FeatureItem('Gate control (boom barriers)', false, true),
              _FeatureItem('RFID support', false, true),
              _FeatureItem('Traffic lights', false, true),
            ],
            isPro: isPro,
            scheme: scheme,
            text: text,
          ),
          SizedBox(height: 16.rs),
          _FeatureGroupWidget(
            icon: Icons.print_rounded,
            title: 'Printing & Output',
            items: [
              _FeatureItem('Simple docket printing', true, true),
              _FeatureItem('Custom slip templates', false, true),
              _FeatureItem('PDF417 barcodes', false, true),
              _FeatureItem('Direct thermal printing', false, true),
              _FeatureItem('Multi-size paper support', false, true),
            ],
            isPro: isPro,
            scheme: scheme,
            text: text,
          ),
          SizedBox(height: 16.rs),
          _FeatureGroupWidget(
            icon: Icons.bar_chart_rounded,
            title: 'Reports & Data',
            items: [
              _FeatureItem('Dashboard', true, true),
              _FeatureItem('Basic reports', true, true),
              _FeatureItem('Advanced analytics & exports', false, true),
              _FeatureItem('Cross-site reporting', false, true),
              _FeatureItem('Data backup & restore', false, true),
            ],
            isPro: isPro,
            scheme: scheme,
            text: text,
          ),
          SizedBox(height: 16.rs),
          _FeatureGroupWidget(
            icon: Icons.security_rounded,
            title: 'Security & Integrations',
            items: [
              _FeatureItem('Basic operator accounts', true, true),
              _FeatureItem('Role-based permissions', false, true),
              _FeatureItem('MFA & IP restrictions', false, true),
              _FeatureItem('Audit trail', false, true),
              _FeatureItem('Tally ERP sync', false, true),
            ],
            isPro: isPro,
            scheme: scheme,
            text: text,
          ),
        ],
      ),
    );
  }

  Widget _buildLicenseDetails(License license, ColorScheme scheme, TextTheme text) {
    return Container(
      padding: EdgeInsets.all(20.rs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(7.rs),
                ),
                child: Icon(Icons.info_outline_rounded, size: 14, color: scheme.primary),
              ),
              SizedBox(width: 10.rs),
              Text('License Details', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          SizedBox(height: 16.rs),
          _detailRow('Key', license.key.isNotEmpty ? '${license.key.substring(0, license.key.length > 10 ? 10 : license.key.length)}...' : 'None', scheme, text),
          SizedBox(height: 10.rs),
          _detailRow('Tier', switch (license.tier) {
            LicenseTier.pro => 'Pro',
            LicenseTier.trial => 'Pro Trial (30 days)',
            LicenseTier.free => 'Free',
          }, scheme, text),
          SizedBox(height: 10.rs),
          _detailRow('Status', license.isValid ? 'Active' : 'Expired', scheme, text),
          SizedBox(height: 10.rs),
          _detailRow('GSTIN', license.gstin ?? '--', scheme, text),
          if (license.activatedAt != null) ...[
            SizedBox(height: 10.rs),
            _detailRow('Activated', _formatDate(license.activatedAt!), scheme, text),
          ],
          if (license.expiresAt != null) ...[
            SizedBox(height: 10.rs),
            _detailRow('Expires', _formatDate(license.expiresAt!), scheme, text),
          ],
          if (license.lastValidatedAt != null) ...[
            SizedBox(height: 10.rs),
            _detailRow('Last validated', _formatDate(license.lastValidatedAt!), scheme, text),
          ],
          SizedBox(height: 14.rs),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await ref.read(licenseProvider.notifier).validate();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: const Text('License validated'), backgroundColor: scheme.primary),
                  );
                }
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Validate Now'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (license.needsRevalidation) ...[
            SizedBox(height: 10.rs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6.rs),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange.shade700),
                  SizedBox(width: 6.rs),
                  Expanded(child: Text(
                    'Last validated ${license.daysSinceValidation} days ago. Validate to confirm license status.',
                    style: TextStyle(fontSize: 10, color: Colors.orange.shade700),
                  )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUsageLimits(License license, ColorScheme scheme, TextTheme text) {
    final wbLabel = license.effectivelyFree ? '1' : (license.maxWeighbridges == -1 ? 'Unlimited' : '${license.maxWeighbridges}');
    final siteLabel = license.effectivelyFree ? '1' : (license.maxSites == -1 ? 'Unlimited' : '${license.maxSites}');

    return Container(
      padding: EdgeInsets.all(20.rs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(7.rs),
                ),
                child: Icon(Icons.tune_rounded, size: 14, color: scheme.primary),
              ),
              SizedBox(width: 10.rs),
              Text('Usage & Limits', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          SizedBox(height: 16.rs),
          _LimitRow(icon: Icons.scale_rounded, label: 'Weighbridges', value: wbLabel, scheme: scheme, text: text),
          SizedBox(height: 10.rs),
          _LimitRow(icon: Icons.location_on_rounded, label: 'Sites', value: siteLabel, scheme: scheme, text: text),
          SizedBox(height: 10.rs),
          _LimitRow(icon: Icons.receipt_long_rounded, label: 'Weighments', value: 'Unlimited', scheme: scheme, text: text),
          SizedBox(height: 10.rs),
          _LimitRow(icon: Icons.people_rounded, label: 'Operators', value: 'Unlimited', scheme: scheme, text: text),
          SizedBox(height: 10.rs),
          _LimitRow(icon: Icons.person_rounded, label: 'Customers', value: 'Unlimited', scheme: scheme, text: text),
          if (license.effectivelyFree) ...[
            SizedBox(height: 14.rs),
            Container(
              padding: EdgeInsets.all(10.rs),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8.rs),
              ),
              child: Row(
                children: [
                  Icon(Icons.trending_up_rounded, size: 14, color: scheme.primary),
                  SizedBox(width: 8.rs),
                  Expanded(
                    child: Text(
                      'Upgrade to Pro for unlimited weighbridges and multi-site support.',
                      style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, ColorScheme scheme, TextTheme text) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(label, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
        Expanded(child: Text(value, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildVersionCard(VersionInfo info, ColorScheme scheme, TextTheme text) {
    final statusColor = switch (info.status) {
      VersionStatus.upToDate => Colors.green,
      VersionStatus.updateAvailable => Colors.orange,
      VersionStatus.updateRequired => scheme.error,
      VersionStatus.unknown => scheme.onSurfaceVariant,
    };

    final statusIcon = switch (info.status) {
      VersionStatus.upToDate => Icons.check_circle_rounded,
      VersionStatus.updateAvailable => Icons.arrow_circle_up_rounded,
      VersionStatus.updateRequired => Icons.error_rounded,
      VersionStatus.unknown => Icons.help_outline_rounded,
    };

    final statusLabel = switch (info.status) {
      VersionStatus.upToDate => 'Up to date',
      VersionStatus.updateAvailable => 'Update available',
      VersionStatus.updateRequired => 'Update required',
      VersionStatus.unknown => 'Unable to check',
    };

    return Container(
      padding: EdgeInsets.all(20.rs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14.rs),
        border: Border.all(color: info.status == VersionStatus.updateRequired
            ? scheme.error.withValues(alpha: 0.3)
            : scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(7.rs),
                ),
                child: Icon(Icons.system_update_rounded, size: 14, color: statusColor),
              ),
              SizedBox(width: 10.rs),
              Text('App Version', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          SizedBox(height: 14.rs),
          Row(
            children: [
              Icon(statusIcon, size: 18, color: statusColor),
              SizedBox(width: 8.rs),
              Text(statusLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor)),
            ],
          ),
          SizedBox(height: 10.rs),
          _detailRow('Current', 'v${info.currentVersion}', scheme, text),
          if (info.latestVersion != null && info.status != VersionStatus.upToDate) ...[
            SizedBox(height: 8.rs),
            _detailRow('Latest', 'v${info.latestVersion}', scheme, text),
          ],
          if (info.releaseNotes != null && info.releaseNotes!.isNotEmpty) ...[
            SizedBox(height: 10.rs),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(10.rs),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(6.rs),
              ),
              child: Text(
                info.releaseNotes!,
                style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (info.status == VersionStatus.updateAvailable || info.status == VersionStatus.updateRequired) ...[
            SizedBox(height: 12.rs),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Download Update'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
                  backgroundColor: statusColor,
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

// ─── Plan Card ──────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final String title;
  final String price;
  final IconData icon;
  final String? badge;
  final bool isActive;
  final Color color;
  final List<String> limits;
  final List<String> features;
  final ColorScheme scheme;
  final TextTheme text;

  const _PlanCard({
    required this.title,
    required this.price,
    required this.icon,
    this.badge,
    required this.isActive,
    required this.color,
    required this.limits,
    required this.features,
    required this.scheme,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(18.rs),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.04) : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14.rs),
        border: Border.all(
          color: isActive ? color.withValues(alpha: 0.4) : scheme.outlineVariant.withValues(alpha: 0.3),
          width: isActive ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8.rs),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              SizedBox(width: 10.rs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: color)),
                        if (badge != null) ...[
                          SizedBox(width: 6.rs),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8.rs)),
                            child: Text(badge!, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        ],
                        if (isActive) ...[
                          SizedBox(width: 6.rs),
                          Icon(Icons.check_circle_rounded, size: 14, color: color),
                        ],
                      ],
                    ),
                    Text(price, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12.rs),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: limits.map((l) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(5.rs),
              ),
              child: Text(l, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
            )).toList(),
          ),
          SizedBox(height: 14.rs),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(
                    f.startsWith('Everything') ? Icons.all_inclusive_rounded : Icons.check_rounded,
                    size: 12,
                    color: color.withValues(alpha: 0.7),
                  ),
                ),
                SizedBox(width: 8.rs),
                Expanded(child: Text(f, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, height: 1.3))),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

// ─── Feature Group Widget ───────────────────────────────────────────────────

class _FeatureItem {
  final String label;
  final bool inFree;
  final bool inPro;

  _FeatureItem(this.label, this.inFree, this.inPro);
}

class _FeatureGroupWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<_FeatureItem> items;
  final bool isPro;
  final ColorScheme scheme;
  final TextTheme text;

  const _FeatureGroupWidget({
    required this.icon,
    required this.title,
    required this.items,
    required this.isPro,
    required this.scheme,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14.rs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: scheme.primary),
              SizedBox(width: 8.rs),
              Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface)),
            ],
          ),
          SizedBox(height: 10.rs),
          // Header row
          Row(
            children: [
              const Expanded(flex: 5, child: SizedBox.shrink()),
              SizedBox(width: 50, child: Center(child: Text('Free', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)))),
              SizedBox(width: 50, child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: AppTheme.proColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(3.rs)),
                  child: const Text('Pro', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppTheme.proColor)),
                ),
              )),
            ],
          ),
          SizedBox(height: 6.rs),
          ...items.map((item) {
            final isLocked = !item.inFree && !isPro;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      item.label,
                      style: TextStyle(fontSize: 11, color: isLocked ? scheme.onSurfaceVariant.withValues(alpha: 0.6) : scheme.onSurface),
                    ),
                  ),
                  SizedBox(
                    width: 50,
                    child: Center(child: Icon(
                      item.inFree ? Icons.check_circle_rounded : Icons.remove_rounded,
                      size: 14,
                      color: item.inFree ? Colors.green.withValues(alpha: 0.7) : scheme.outlineVariant,
                    )),
                  ),
                  SizedBox(
                    width: 50,
                    child: Center(child: Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: isPro ? AppTheme.proColor : Colors.green.withValues(alpha: 0.7),
                    )),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Limit Row ──────────────────────────────────────────────────────────────

class _LimitRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme scheme;
  final TextTheme text;

  const _LimitRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.scheme,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        SizedBox(width: 8.rs),
        Expanded(child: Text(label, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(5.rs),
          ),
          child: Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurface)),
        ),
      ],
    );
  }
}
