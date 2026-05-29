import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/models/license_model.dart';
import 'package:weighbridgemanagement/shared/providers/connectivity_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import 'package:weighbridgemanagement/shared/providers/license_provider.dart';
import '../../application/setup_wizard_provider.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/app_loading.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

class LicenseStep extends ConsumerStatefulWidget {
  const LicenseStep({super.key});

  @override
  ConsumerState<LicenseStep> createState() => _LicenseStepState();
}

class _LicenseStepState extends ConsumerState<LicenseStep> {
  LicenseTier _selectedTier = LicenseTier.trial;
  final _keyController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(stepSaveCallbackProvider.notifier).state = _save;
    });
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<bool> _save() async {
    setState(() { _loading = true; _error = null; });

    final isOnline = ref.read(connectivityProvider).valueOrNull ?? false;
    if (!isOnline) {
      setState(() { _loading = false; _error = 'Internet connection required for license activation. Please check your connection and try again.'; });
      return false;
    }

    final companyId = ref.read(wizardCompanyIdProvider) ?? '';
    if (companyId.isEmpty) {
      setState(() { _loading = false; _error = 'Company not found. Go back and complete Company Info step.'; });
      return false;
    }

    final licenseNotifier = ref.read(licenseProvider.notifier);
    final db = ref.read(firestoreProvider);
    final companySnap = await db.doc('companies/$companyId').get();
    final gstin = companySnap.data()?['gstin'] as String? ?? '';

    if (gstin.isEmpty) {
      setState(() { _loading = false; _error = 'GSTIN is required for license activation'; });
      return false;
    }

    // If license already active for this tier+company (resuming setup), skip activation
    final currentLicense = ref.read(licenseProvider);
    if (currentLicense.companyId == companyId &&
        currentLicense.status == LicenseStatus.active &&
        !currentLicense.isExpired) {
      if ((_selectedTier == LicenseTier.trial && currentLicense.tier == LicenseTier.trial) ||
          (_selectedTier == LicenseTier.free && currentLicense.tier == LicenseTier.free) ||
          (_selectedTier == LicenseTier.pro && currentLicense.tier == LicenseTier.pro)) {
        ref.read(setupWizardProvider.notifier).setLicenseTier(_selectedTier);
        setState(() => _loading = false);
        return true;
      }
    }

    bool success;
    switch (_selectedTier) {
      case LicenseTier.free:
        success = await licenseNotifier.activateFree(
          gstin: gstin,
          companyId: companyId,
        );
      case LicenseTier.trial:
        success = await licenseNotifier.activateTrial(
          gstin: gstin,
          companyId: companyId,
        );
        if (!success) {
          setState(() { _loading = false; _error = 'Trial already used for this GSTIN. Enter a Pro license key instead.'; });
          return false;
        }
      case LicenseTier.pro:
        final key = _keyController.text.trim();
        if (key.isEmpty) {
          setState(() { _loading = false; _error = 'Please enter your license key'; });
          return false;
        }
        success = await licenseNotifier.activate(
          licenseKey: key,
          gstin: gstin,
          companyId: companyId,
        );
        if (!success) {
          setState(() { _loading = false; _error = 'Invalid or already-used license key'; });
          return false;
        }
    }

    if (success) {
      ref.read(setupWizardProvider.notifier).setLicenseTier(_selectedTier);
    }

    setState(() => _loading = false);
    return success;
  }

  Widget _buildFreeItem(IconData icon, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          SizedBox(width: 6.rs),
          Expanded(child: Text(label, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.85)))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('Your Plan', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              SizedBox(height: AppSpacing.sm),
              Text(
                'Start with a 30-day Pro trial — all features unlocked. Or enter a license key.',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 36.rs),

              // Plan cards — Pro first (recommended)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _TierCard(
                      title: 'Pro',
                      price: 'Priced per weighbridge',
                      badge: 'Recommended',
                      limits: const ['Unlimited WBs', 'Unlimited sites', '1-year license'],
                      featureGroups: const [
                        _FeatureGroup(Icons.all_inclusive_rounded, 'Everything in Trial', ['All features included']),
                        _FeatureGroup(Icons.language_rounded, 'Multi-site', ['Multiple locations', 'Cross-site reporting']),
                        _FeatureGroup(Icons.support_agent_rounded, 'Support', ['Priority support', 'Software updates']),
                      ],
                      isSelected: _selectedTier == LicenseTier.pro,
                      onSelect: () => setState(() => _selectedTier = LicenseTier.pro),
                      scheme: scheme,
                      text: text,
                    )),
                    SizedBox(width: AppSpacing.lg),
                    Expanded(child: _TierCard(
                      title: 'Pro Trial',
                      price: 'Free for 30 days',
                      limits: const ['2 weighbridges', '1 site', '30-day access'],
                      featureGroups: const [
                        _FeatureGroup(Icons.scale_rounded, 'Weighing', ['Unlimited weighments', 'Auto & manual capture']),
                        _FeatureGroup(Icons.videocam_rounded, 'Cameras & AI', ['ANPR plate reading', 'Face verification']),
                        _FeatureGroup(Icons.door_sliding_rounded, 'Automation', ['Gate control', 'RFID support']),
                        _FeatureGroup(Icons.print_rounded, 'Printing', ['All printer types', 'PDF417 barcodes']),
                        _FeatureGroup(Icons.bar_chart_rounded, 'Reports & Security', ['Dashboard & exports', 'Audit trail & permissions']),
                        _FeatureGroup(Icons.sync_alt_rounded, 'Integrations', ['Tally ERP sync']),
                      ],
                      isSelected: _selectedTier == LicenseTier.trial,
                      onSelect: () => setState(() => _selectedTier = LicenseTier.trial),
                      scheme: scheme,
                      text: text,
                    )),
                  ],
                ),
              ),

              SizedBox(height: AppSpacing.xl),

              // Animated content below cards
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 250),
                sizeCurve: Curves.easeInOut,
                crossFadeState: _selectedTier == LicenseTier.pro
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: Container(
                  padding: AppSpacing.cardPadding,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow.withValues(alpha: 0.6),
                    borderRadius: AppRadius.card,
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.vpn_key_rounded, size: 16, color: scheme.primary),
                          SizedBox(width: AppSpacing.sm),
                          Text('License Key', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      SizedBox(height: AppSpacing.xs),
                      Text(
                        'Cost is based on the number of weighbridges you operate.',
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                      SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _keyController,
                        decoration: InputDecoration(
                          hintText: 'XXXX-XXXX-XXXX-XXXX',
                          prefixIcon: const Icon(Icons.vpn_key_rounded, size: 18),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.rs)),
                        ),
                        textCapitalization: TextCapitalization.characters,
                      ),
                    ],
                  ),
                ),
                secondChild: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.all(14.rs),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10.rs),
                        border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 16, color: scheme.primary),
                          SizedBox(width: 10.rs),
                          Expanded(
                            child: Text(
                              'Your 30-day trial activates after completing the setup wizard. No credit card required.',
                              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: AppSpacing.lg),
                    Container(
                      padding: AppSpacing.cardPadding,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow.withValues(alpha: 0.6),
                        borderRadius: AppRadius.card,
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.timelapse_rounded, size: 16, color: scheme.onSurfaceVariant),
                              SizedBox(width: AppSpacing.sm),
                              Text('After 30 days — Free plan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                            ],
                          ),
                          SizedBox(height: 10.rs),
                          Text(
                            'If you don\'t upgrade to Pro, your account moves to the Free plan:',
                            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                          ),
                          SizedBox(height: AppSpacing.md),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('KEPT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: const Color(0xFF16A34A), letterSpacing: 0.5)),
                                    SizedBox(height: 6.rs),
                                    _buildFreeItem(Icons.check_rounded, 'Basic weighments', const Color(0xFF16A34A)),
                                    _buildFreeItem(Icons.check_rounded, '1 weighbridge', const Color(0xFF16A34A)),
                                    _buildFreeItem(Icons.check_rounded, 'Manual capture only', const Color(0xFF16A34A)),
                                    _buildFreeItem(Icons.check_rounded, 'Simple docket printing', const Color(0xFF16A34A)),
                                    _buildFreeItem(Icons.check_rounded, 'All your existing data', const Color(0xFF16A34A)),
                                  ],
                                ),
                              ),
                              SizedBox(width: AppSpacing.lg),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('LOCKED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: scheme.error, letterSpacing: 0.5)),
                                    SizedBox(height: 6.rs),
                                    _buildFreeItem(Icons.lock_rounded, 'ANPR & cameras', scheme.error),
                                    _buildFreeItem(Icons.lock_rounded, 'Gate automation', scheme.error),
                                    _buildFreeItem(Icons.lock_rounded, 'Face verification', scheme.error),
                                    _buildFreeItem(Icons.lock_rounded, 'Integrations (Tally)', scheme.error),
                                    _buildFreeItem(Icons.lock_rounded, 'Advanced reports', scheme.error),
                                    _buildFreeItem(Icons.lock_rounded, 'Multi-site & 2nd WB', scheme.error),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 10.rs),
                          Text(
                            'Upgrade to Pro anytime from Settings.',
                            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

          if (_error != null) ...[
            SizedBox(height: AppSpacing.lg),
            Container(
              padding: EdgeInsets.all(12.rs),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: AppRadius.button,
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, size: 16, color: scheme.error),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(_error!, style: text.bodySmall?.copyWith(color: scheme.error))),
                ],
              ),
            ),
          ],

          if (_loading) ...[
            SizedBox(height: AppSpacing.xl),
            const AppLoading(),
          ],
        ],
          ),
        ),
      ),
    );
  }
}

class _FeatureGroup {
  final IconData icon;
  final String title;
  final List<String> items;

  const _FeatureGroup(this.icon, this.title, this.items);
}

class _TierCard extends StatelessWidget {
  final String title;
  final String price;
  final String? badge;
  final List<String> limits;
  final List<_FeatureGroup> featureGroups;
  final bool isSelected;
  final VoidCallback onSelect;
  final ColorScheme scheme;
  final TextTheme text;

  const _TierCard({
    required this.title,
    required this.price,
    this.badge,
    required this.limits,
    required this.featureGroups,
    required this.isSelected,
    required this.onSelect,
    required this.scheme,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.all(22.rs),
        decoration: BoxDecoration(
          color: isSelected ? scheme.primary.withValues(alpha: 0.04) : scheme.surface,
          borderRadius: AppRadius.dialog,
          border: Border.all(
            color: isSelected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(color: scheme.primary.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4)),
          ] : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isSelected ? scheme.primary.withValues(alpha: 0.12) : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10.rs),
                  ),
                  child: Icon(
                    badge != null ? Icons.workspace_premium_rounded : Icons.rocket_launch_rounded,
                    size: 18,
                    color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          if (badge != null) ...[
                            SizedBox(width: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(10.rs),
                              ),
                              child: Text(badge!, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: scheme.onPrimary)),
                            ),
                          ],
                        ],
                      ),
                      Text(price, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary,
                    ),
                    child: Icon(Icons.check_rounded, size: 14, color: scheme.onPrimary),
                  )
                else
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.outlineVariant, width: 2),
                    ),
                  ),
              ],
            ),
            SizedBox(height: AppSpacing.lg),

            // Limits chips
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: limits.map((l) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected ? scheme.primaryContainer.withValues(alpha: 0.3) : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: AppRadius.chip,
                ),
                child: Text(l, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: isSelected ? scheme.primary : scheme.onSurfaceVariant)),
              )).toList(),
            ),
            SizedBox(height: 18.rs),

            // Feature groups
            ...featureGroups.map((group) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(group.icon, size: 14, color: isSelected ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                      SizedBox(width: 6.rs),
                      Text(group.title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                    ],
                  ),
                  SizedBox(height: 6.rs),
                  ...group.items.map((item) => Padding(
                    padding: const EdgeInsets.only(left: 20, bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected ? scheme.primary.withValues(alpha: 0.6) : scheme.onSurfaceVariant.withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(item, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, height: 1.3)),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}
