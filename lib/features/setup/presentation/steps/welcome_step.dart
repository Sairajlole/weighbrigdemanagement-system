import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/appearance_provider.dart';
import 'package:weighbridgemanagement/shared/providers/auth_provider.dart';
import 'package:weighbridgemanagement/shared/providers/connectivity_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/routing/app_router.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';
import '../../application/setup_wizard_provider.dart';
import '../../application/setup_wizard_state.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

String _hashPassword(String password) => sha256.convert(utf8.encode(password)).toString();

Future<void> _ensureFirebaseAuthAccount(String email, String password) async {
  try {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'ensureFirebaseAuth',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 8)),
    );
    await callable.call({'email': email, 'password': password}).timeout(const Duration(seconds: 8));
    await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
    debugPrint('[Login] Firebase Auth sign-in succeeded after ensure');
  } catch (e) {
    debugPrint('[Login] ensureFirebaseAuth skipped: $e');
  }
}

final _emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');

class WelcomeStep extends ConsumerStatefulWidget {
  final bool initialSignIn;
  const WelcomeStep({super.key, this.initialSignIn = false});

  @override
  ConsumerState<WelcomeStep> createState() => _WelcomeStepState();
}

enum _WelcomeView { roles, signIn, resumeSignIn }

class _WelcomeStepState extends ConsumerState<WelcomeStep> {
  late _WelcomeView _view = widget.initialSignIn ? _WelcomeView.signIn : _WelcomeView.roles;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(setupWizardProvider);

    // Auto-show resume sign-in when redirected from Company Info step
    final showResume = ref.watch(wizardShowResumeSignInProvider);
    if (showResume && _view != _WelcomeView.resumeSignIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(wizardShowResumeSignInProvider.notifier).state = false;
          setState(() => _view = _WelcomeView.resumeSignIn);
        }
      });
    }

    // Auto-show sign-in when redirected from account step
    final prefillEmail = ref.watch(wizardPrefillEmailProvider);
    if (prefillEmail != null && prefillEmail.isNotEmpty && _view == _WelcomeView.roles) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _view = _WelcomeView.signIn);
      });
    }
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // Themed background
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        scheme.surface,
                        scheme.primary.withValues(alpha: 0.05),
                        scheme.surface,
                      ]
                    : [
                        scheme.primary.withValues(alpha: 0.03),
                        scheme.surface,
                        scheme.primaryContainer.withValues(alpha: 0.1),
                      ],
              ),
            ),
          ),
        ),
        // Decorative circles
        Positioned(
          top: -60,
          right: -40,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: isDark ? 0.04 : 0.06),
            ),
          ),
        ),
        Positioned(
          bottom: -80,
          left: -60,
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.tertiary.withValues(alpha: isDark ? 0.03 : 0.05),
            ),
          ),
        ),
        // Content
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: switch (_view) {
                _WelcomeView.signIn => _SignInContent(
                    key: const ValueKey('signin'),
                    onBack: () => setState(() => _view = _WelcomeView.roles),
                  ),
                _WelcomeView.resumeSignIn => _ResumeSignInContent(
                    key: const ValueKey('resume'),
                    onBack: () => setState(() => _view = _WelcomeView.roles),
                  ),
                _WelcomeView.roles => _RoleSelectionContent(
                    key: const ValueKey('roles'),
                    state: state,
                    onSignIn: () => setState(() => _view = _WelcomeView.signIn),
                    onResumeSignIn: () => setState(() => _view = _WelcomeView.resumeSignIn),
                  ),
              },
            ),
          ),
        ),
        // Connectivity indicator (top-left)
        const Positioned(
          top: 16,
          left: 16,
          child: _ConnectivityPing(),
        ),
        // Appearance controls (top-right, device-local)
        const Positioned(
          top: 16,
          right: 16,
          child: _AppearanceControls(),
        ),
      ],
    );
  }
}

// ── Role Selection (main welcome view) ─────────────────────────────────────

class _RoleSelectionContent extends ConsumerWidget {
  final SetupWizardState state;
  final VoidCallback onSignIn;
  final VoidCallback onResumeSignIn;

  const _RoleSelectionContent({super.key, required this.state, required this.onSignIn, required this.onResumeSignIn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20.rs),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
          ),
          child: Icon(Icons.scale_rounded, size: 36, color: scheme.primary),
        ),
        SizedBox(height: AppSpacing.xl),
        Text(
          'Weighbridge Management',
          style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        SizedBox(height: AppSpacing.sm),
        Text(
          'Smart weighing, simplified operations',
          style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        SizedBox(height: 48.rs),

        // Role cards
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Row(
            children: [
              Expanded(
                child: _RoleCard(
                  icon: Icons.person_add_rounded,
                  title: 'Sign Up',
                  subtitle: 'Create a new account as admin or operator',
                  isSelected: state.role == WizardRole.admin || state.role == WizardRole.operator,
                  onTap: () => ref.read(setupWizardProvider.notifier).setRole(WizardRole.admin),
                  scheme: scheme,
                ),
              ),
              SizedBox(width: 20.rs),
              Expanded(
                child: _RoleCard(
                  icon: Icons.login_rounded,
                  title: 'Sign In',
                  subtitle: 'Already have an account? Configure this device',
                  isSelected: state.role == WizardRole.returning,
                  onTap: () {
                    ref.read(setupWizardProvider.notifier).setRole(WizardRole.returning);
                    onSignIn();
                  },
                  scheme: scheme,
                ),
              ),
            ],
          ),
        ),

        // Sub-role selector (shown when Sign Up selected)
        if (state.role == WizardRole.admin || state.role == WizardRole.operator) ...[
          SizedBox(height: AppSpacing.xl),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Container(
              padding: AppSpacing.cardPadding,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(14.rs),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('I am a...', style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                  SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: _SubRoleChip(
                          icon: Icons.shield_rounded,
                          label: 'Company Admin',
                          description: 'Set up a new company',
                          isSelected: state.role == WizardRole.admin,
                          onTap: () => ref.read(setupWizardProvider.notifier).setRole(WizardRole.admin),
                          scheme: scheme,
                        ),
                      ),
                      SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _SubRoleChip(
                          icon: Icons.badge_rounded,
                          label: 'Operator',
                          description: 'Join with company code',
                          isSelected: state.role == WizardRole.operator,
                          onTap: () => ref.read(setupWizardProvider.notifier).setRole(WizardRole.operator),
                          scheme: scheme,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],

        SizedBox(height: AppSpacing.xxl),

        // Get Started button (only for Sign Up)
        if (state.role == WizardRole.admin || state.role == WizardRole.operator)
          FilledButton.icon(
            onPressed: () {
              final progress = ref.read(wizardProgressProvider);
              // Resume only for admin who actually got past account creation (step > 3)
              // and hasn't completed setup yet
              if (state.role == WizardRole.admin && !progress.setupComplete && progress.currentStepIndex > 3 && progress.role == 'admin') {
                onResumeSignIn();
                return;
              }
              // Fresh start — clear stale context so it's reconfigured in the site step
              ref.read(siteContextProvider.notifier).clear();
              ref.read(wizardProgressProvider.notifier).clear();
              ref.read(setupWizardProvider.notifier).nextStep();
            },
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Get Started'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),

        SizedBox(height: AppSpacing.xl),

        // Info banner
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10.rs),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: scheme.primary),
                SizedBox(width: 10.rs),
                Expanded(
                  child: Text(
                    switch (state.role) {
                      WizardRole.admin => 'You\'ll verify your company via GSTIN, create your account, and configure your weighbridge system.',
                      WizardRole.operator => 'You\'ll need a company code from your admin to join. Then set up this device for operation.',
                      WizardRole.returning => 'Sign in with your existing credentials and select which site and weighbridge this device connects to.',
                      WizardRole.undecided => 'Choose Sign Up or Sign In to get started.',
                    },
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Resume Setup Sign In ──────────────────────────────────────────────────

class _ResumeSignInContent extends ConsumerStatefulWidget {
  final VoidCallback onBack;

  const _ResumeSignInContent({super.key, required this.onBack});

  @override
  ConsumerState<_ResumeSignInContent> createState() => _ResumeSignInContentState();
}

class _ResumeSignInContentState extends ConsumerState<_ResumeSignInContent> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  // Company details from Firestore
  String? _companyName;
  String? _gstin;
  String? _address;
  String? _entityType;
  bool _loadingDetails = true;

  @override
  void initState() {
    super.initState();
    _loadCompanyDetails();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadCompanyDetails() async {
    try {
      final db = ref.read(firestoreProvider);

      final companiesSnap = await db.collection('companies')
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();

      for (final doc in companiesSnap.docs) {
        final data = doc.data();
        final gstin = data['gstin'] as String? ?? '';
        if (gstin.isNotEmpty) {
          setState(() {
            _companyName = data['name'] as String? ?? '';
            _gstin = gstin;
            _address = data['address1'] as String? ?? '';
            _entityType = data['entityType'] as String? ?? '';
            _loadingDetails = false;
          });

          // Pre-fill email if company has one
          final email = data['email'] as String?;
          if (email != null && email.isNotEmpty) {
            _email.text = email;
          }
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingDetails = false);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _loading = true; _error = null; });

    try {
      final db = ref.read(firestoreProvider);
      final email = _email.text.trim();

      bool firebaseAuthOk = false;
      try {
        await ref.read(firebaseAuthProvider).signInWithEmailAndPassword(
          email: email, password: _password.text);
        firebaseAuthOk = true;
      } catch (_) {}

      // Find operator by email
      final operatorSnap = await db
          .collectionGroup('operators')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      String? companyId;

      if (operatorSnap.docs.isEmpty) {
        // Try company email
        final companySnap = await db.collection('companies')
            .where('email', isEqualTo: email).limit(1).get();
        if (companySnap.docs.isEmpty) {
          setState(() { _error = 'No account found with this email.'; _loading = false; });
          return;
        }
        // Company admin: verify password via hash
        if (!firebaseAuthOk) {
          final companyData = companySnap.docs.first.data();
          final storedHash = companyData['passwordHash'] as String?;
          if (storedHash != null && storedHash != _hashPassword(_password.text)) {
            setState(() { _error = 'Invalid email or password.'; _loading = false; });
            return;
          }
          // Migrate: store hash for accounts that don't have one yet
          if (storedHash == null) {
            companySnap.docs.first.reference.update({'passwordHash': _hashPassword(_password.text)});
          }
        }
        companyId = companySnap.docs.first.id;
      } else {
        // Verify password via Firebase Auth or hash fallback
        if (!firebaseAuthOk) {
          final storedHash = operatorSnap.docs.first.data()['passwordHash'] as String?;
          if (storedHash != null && storedHash != _hashPassword(_password.text)) {
            setState(() { _error = 'Invalid email or password.'; _loading = false; });
            return;
          }
          // Migrate: store hash for accounts that don't have one yet
          if (storedHash == null) {
            operatorSnap.docs.first.reference.update({'passwordHash': _hashPassword(_password.text)});
          }
        }
        companyId = operatorSnap.docs.first.data()['companyId'] as String? ?? '';
      }

      if (companyId.isEmpty) {
        setState(() { _error = 'No company linked to this account.'; _loading = false; });
        return;
      }

      if (!firebaseAuthOk) await _ensureFirebaseAuthAccount(email, _password.text);
      await LocalCacheService.cacheCurrentUserEmail(email);

      // Configure site context if a site+weighbridge exists (so Firestore paths work)
      final sitesSnap = await db.collection('companies/$companyId/sites').get();
      for (final site in sitesSnap.docs) {
        final wbSnap = await db
            .collection('companies/$companyId/sites/${site.id}/weighbridges')
            .limit(1).get();
        if (wbSnap.docs.isNotEmpty) {
          await ref.read(siteContextProvider.notifier).configure(
            companyId: companyId,
            siteId: site.id,
            weighbridgeId: wbSnap.docs.first.id,
          );
          break;
        }
      }

      // Resume wizard from saved progress — never go to dashboard from here
      // minStep = 4 (site) so we never land back on account/company screens
      ref.read(wizardCompanyIdProvider.notifier).state = companyId;
      final siteStepIndex = wizardSteps.indexWhere((s) => s.id == WizardStepId.site);
      final resumed = ref.read(setupWizardProvider.notifier).resumeFromProgress(minStep: siteStepIndex);
      if (!resumed) {
        ref.read(setupWizardProvider.notifier).setRole(WizardRole.admin);
        ref.read(setupWizardProvider.notifier).resumeFromProgress(minStep: siteStepIndex);
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _error = 'Sign in failed. Check your credentials.'; _loading = false; });
    }
  }

  void _resetAndStartFresh() {
    ref.read(setupWizardProvider.notifier).reset();
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final progress = ref.watch(wizardProgressProvider);
    final stepName = progress.currentStepIndex < wizardSteps.length
        ? wizardSteps[progress.currentStepIndex].title
        : 'Unknown';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: scheme.tertiary.withValues(alpha: 0.1),
            borderRadius: AppRadius.dialog,
            border: Border.all(color: scheme.tertiary.withValues(alpha: 0.2)),
          ),
          child: Icon(Icons.restore_rounded, size: 28, color: scheme.tertiary),
        ),
        SizedBox(height: 20.rs),
        Text(
          'Resume Setup',
          style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        SizedBox(height: AppSpacing.sm),
        Text(
          'Sign in to continue where you left off',
          style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        SizedBox(height: 28.rs),

        // Info bar — explains what happened
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            padding: EdgeInsets.all(14.rs),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer.withValues(alpha: 0.15),
              borderRadius: AppRadius.card,
              border: Border.all(color: scheme.tertiary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: scheme.tertiary),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'You have an incomplete setup (paused at "$stepName" step). Verify your credentials to resume.',
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 20.rs),

        // Company/GSTIN details card
        if (!_loadingDetails && _gstin != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              padding: AppSpacing.cardPadding,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14.rs),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(10.rs),
                        ),
                        child: Icon(Icons.business_rounded, size: 18, color: scheme.primary),
                      ),
                      SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _companyName ?? '',
                              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _entityType ?? '',
                              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: AppSpacing.md),
                  Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.2)),
                  SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      _DetailChip(icon: Icons.assignment_ind_rounded, label: 'GSTIN: $_gstin', scheme: scheme),
                    ],
                  ),
                  if (_address != null && _address!.isNotEmpty) ...[
                    SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 13, color: scheme.onSurfaceVariant),
                        SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(_address!, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

        if (_loadingDetails)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          ),

        SizedBox(height: AppSpacing.xl),

        // Sign-in form
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            padding: AppSpacing.pagePadding,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(18.rs),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 6)),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null) ...[
                    Container(
                      padding: EdgeInsets.all(12.rs),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10.rs),
                        border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 16, color: scheme.error),
                          SizedBox(width: AppSpacing.sm),
                          Expanded(child: Text(_error!, style: TextStyle(fontSize: 12, color: scheme.error, fontWeight: FontWeight.w500))),
                        ],
                      ),
                    ),
                    SizedBox(height: AppSpacing.lg),
                  ],

                  Text('Email', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                  SizedBox(height: 6.rs),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (!_emailRegex.hasMatch(v.trim())) return 'Enter a valid email';
                      return null;
                    },
                    decoration: const InputDecoration(
                      hintText: 'you@company.com',
                      prefixIcon: Icon(Icons.email_outlined, size: 18),
                    ),
                  ),
                  SizedBox(height: AppSpacing.lg),

                  Text('Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                  SizedBox(height: 6.rs),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
                    decoration: InputDecoration(
                      hintText: '••••••••',
                      prefixIcon: const Icon(Icons.lock_outline, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  SizedBox(height: AppSpacing.xl),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _submit,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      child: _loading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Verify & Resume'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        SizedBox(height: 20.rs),

        // Options row
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Back'),
              ),
              TextButton.icon(
                onPressed: _resetAndStartFresh,
                icon: Icon(Icons.restart_alt_rounded, size: 16, color: scheme.error),
                label: Text('Start Fresh', style: TextStyle(color: scheme.error)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme scheme;

  const _DetailChip({required this.icon, required this.label, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: AppRadius.chip,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: scheme.primary),
          SizedBox(width: AppSpacing.xs),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.primary)),
        ],
      ),
    );
  }
}

// ── Inline Sign In Form (same themed page) ─────────────────────────────────

class _SignInContent extends ConsumerStatefulWidget {
  final VoidCallback onBack;

  const _SignInContent({super.key, required this.onBack});

  @override
  ConsumerState<_SignInContent> createState() => _SignInContentState();
}

class _SignInContentState extends ConsumerState<_SignInContent> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  // Force password change state
  bool _forcePasswordChange = false;
  final _newPassword = TextEditingController();
  final _confirmNewPassword = TextEditingController();
  bool _obscureNew = true;
  String? _changeError;
  String? _changeSuccess;

  @override
  void initState() {
    super.initState();
    final prefill = ref.read(wizardPrefillEmailProvider);
    if (prefill != null && prefill.isNotEmpty) {
      _email.text = prefill;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(wizardPrefillEmailProvider.notifier).state = null;
      });
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _newPassword.dispose();
    _confirmNewPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _loading = true; _error = null; });

    try {
      final db = ref.read(firestoreProvider);
      final email = _email.text.trim();
      debugPrint('[Login] Starting for $email');

      bool firebaseAuthOk = false;
      try {
        await ref.read(firebaseAuthProvider).signInWithEmailAndPassword(
          email: email,
          password: _password.text,
        );
        firebaseAuthOk = true;
        debugPrint('[Login] Firebase auth OK');
      } catch (e) {
        debugPrint('[Login] Firebase auth failed: $e');
      }
      if (!mounted) { debugPrint('[Login] Not mounted after auth'); return; }

      debugPrint('[Login] Querying operators...');
      final operatorSnap = await db
          .collectionGroup('operators')
          .where('email', isEqualTo: email)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 8), onTimeout: () {
            debugPrint('[Login] Operator query timed out');
            throw TimeoutException('Query timed out');
          });
      debugPrint('[Login] Got ${operatorSnap.docs.length} operator docs');

      if (operatorSnap.docs.isEmpty) {
        debugPrint('[Login] No operator, checking companies...');
        final companySnap = await db
            .collection('companies')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        debugPrint('[Login] Got ${companySnap.docs.length} company docs');

        if (companySnap.docs.isEmpty) {
          setState(() { _error = 'No account found with this email.'; _loading = false; });
          return;
        }

        // Company admin: verify password via Firebase Auth or hash fallback
        if (!firebaseAuthOk) {
          final companyData = companySnap.docs.first.data();
          final storedHash = companyData['passwordHash'] as String?;
          debugPrint('[Login] storedHash=${storedHash != null ? "exists" : "null"}, firebaseAuthOk=$firebaseAuthOk');
          if (storedHash != null && storedHash != _hashPassword(_password.text)) {
            debugPrint('[Login] Hash mismatch — wrong password');
            setState(() { _error = 'Invalid email or password.'; _loading = false; });
            return;
          }
          if (storedHash == null) {
            debugPrint('[Login] No hash stored, saving one');
            companySnap.docs.first.reference.update({'passwordHash': _hashPassword(_password.text)});
          }
        }

        debugPrint('[Login] Password OK, ensuring Firebase Auth account...');
        await _ensureFirebaseAuthAccount(email, _password.text);
        await LocalCacheService.cacheCurrentUserEmail(email);
        final companyId = companySnap.docs.first.id;

        final sitesSnap = await db.collection('companies/$companyId/sites').get();
        debugPrint('[Login] Sites: ${sitesSnap.docs.length}');

        final companyDoc = await db.doc('companies/$companyId').get();
        final firstLoginDone = companyDoc.data()?['firstLoginComplete'] == true;
        debugPrint('[Login] firstLoginDone=$firstLoginDone');

        for (final site in sitesSnap.docs) {
          final wbSnap = await db
              .collection('companies/$companyId/sites/${site.id}/weighbridges')
              .limit(1)
              .get();
          debugPrint('[Login] Site ${site.id}: ${wbSnap.docs.length} weighbridges');
          if (wbSnap.docs.isNotEmpty) {
            await ref.read(siteContextProvider.notifier).configure(
              companyId: companyId,
              siteId: site.id,
              weighbridgeId: wbSnap.docs.first.id,
            );
            debugPrint('[Login] Site configured. firstLoginDone=$firstLoginDone');
            if (!firstLoginDone) {
              if (!mounted) return;
              debugPrint('[Login] Going to wizard (first login not done)');
              ref.read(sessionLoggedInProvider.notifier).state = true;
              ref.read(wizardCompanyIdProvider.notifier).state = companyId;
              final siteStepIndex = wizardSteps.indexWhere((s) => s.id == WizardStepId.site);
              final resumed = ref.read(setupWizardProvider.notifier).resumeFromProgress(minStep: siteStepIndex);
              if (!resumed) {
                ref.read(setupWizardProvider.notifier).setRole(WizardRole.admin);
                ref.read(setupWizardProvider.notifier).resumeFromProgress(minStep: siteStepIndex);
              }
              return;
            }
            debugPrint('[Login] Marking wizard complete, going to dashboard...');
            await ref.read(wizardProgressProvider.notifier).markComplete();
            ref.read(sessionLoggedInProvider.notifier).state = true;
            final allowed = await _runPostLoginChecks(ref, email);
            debugPrint('[Login] postLoginChecks allowed=$allowed');
            if (!allowed) return;
            if (mounted) context.go('/dashboard');
            return;
          }
        }

        // No site with weighbridge — go to site setup
        ref.read(wizardCompanyIdProvider.notifier).state = companyId;
        ref.read(setupWizardProvider.notifier).setRole(WizardRole.returning);
        ref.read(setupWizardProvider.notifier).nextStep();
        return;
      }

      // Found operator record — verify password
      debugPrint('[Login] Found operator, verifying password...');
      final opDoc = operatorSnap.docs.first;
      if (!firebaseAuthOk) {
        final storedHash = opDoc.data()['passwordHash'] as String?;
        debugPrint('[Login] Op storedHash=${storedHash != null ? "exists" : "null"}');
        if (storedHash != null && storedHash != _hashPassword(_password.text)) {
          debugPrint('[Login] Op hash mismatch');
          setState(() { _error = 'Invalid email or password.'; _loading = false; });
          return;
        }
        if (storedHash == null) {
          opDoc.reference.update({'passwordHash': _hashPassword(_password.text)});
        }
      }
      debugPrint('[Login] Op password OK');

      final opData = opDoc.data();

      // Status-based access control
      final isDeleted = opData['isDeleted'] == true;
      final isArchived = opData['isArchived'] == true;

      if (isDeleted) {
        setState(() { _error = 'Invalid email or password.'; _loading = false; });
        return;
      }

      if (isArchived) {
        setState(() { _error = 'Your account has been archived. Contact your administrator to restore access.'; _loading = false; });
        return;
      }

      final isVerified = opData['isVerified'] as bool? ?? false;
      final isActive = opData['isActive'] as bool? ?? false;
      debugPrint('[Login] Op isVerified=$isVerified isActive=$isActive isDeleted=$isDeleted isArchived=$isArchived');
      if (!isVerified || !isActive) {
        debugPrint('[Login] Op not verified/active — blocking');
        setState(() { _error = 'Your account is pending approval. Please wait for your administrator to accept your request.'; _loading = false; });
        return;
      }

      if (!firebaseAuthOk) await _ensureFirebaseAuthAccount(email, _password.text);
      await LocalCacheService.cacheCurrentUserEmail(email);
      ref.read(sessionLoggedInProvider.notifier).state = true;

      final opRole = opData['role'] as String? ?? '';
      final isOperatorRole = opRole == 'operator';

      // Resolve company ID from path or doc data
      final opPath = opDoc.reference.path;
      final segments = opPath.split('/');
      String? companyId;
      String? siteIdFromPath;

      // Path: companies/{companyId}/sites/{siteId}/operators/{opId} → 6 segments
      // Path: companies/{companyId}/operators/{opId} → 4 segments
      // Path: operators/{opId} → 2 segments (top-level, use doc data)
      if (segments.length >= 6 && segments[0] == 'companies') {
        companyId = segments[1];
        siteIdFromPath = segments[3];
      } else if (segments.length >= 4 && segments[0] == 'companies') {
        companyId = segments[1];
      }
      companyId ??= opData['companyId'] as String?;

      if (companyId == null || companyId.isEmpty) {
        setState(() { _error = 'No company linked to this account.'; _loading = false; });
        return;
      }

      final opCompanyDoc = await db.doc('companies/$companyId').get();
      final opFirstLoginDone = opCompanyDoc.data()?['firstLoginComplete'] == true;

      // Try site from path first
      if (siteIdFromPath != null) {
        final wbSnap = await db
            .collection('companies/$companyId/sites/$siteIdFromPath/weighbridges')
            .limit(1).get();
        if (wbSnap.docs.isNotEmpty) {
          await ref.read(siteContextProvider.notifier).configure(
            companyId: companyId,
            siteId: siteIdFromPath,
            weighbridgeId: wbSnap.docs.first.id,
          );
          if (!opFirstLoginDone) {
            if (!mounted) return;
            ref.read(wizardCompanyIdProvider.notifier).state = companyId;
            final siteStepIndex = wizardSteps.indexWhere((s) => s.id == WizardStepId.site);
            final resumed = ref.read(setupWizardProvider.notifier).resumeFromProgress(minStep: siteStepIndex);
            if (!resumed) {
              ref.read(setupWizardProvider.notifier).setRole(WizardRole.admin);
              ref.read(setupWizardProvider.notifier).resumeFromProgress(minStep: siteStepIndex);
            }
            return;
          }
          await ref.read(wizardProgressProvider.notifier).markComplete();
          final allowed = await _runPostLoginChecks(ref, email);
          if (!allowed) return;
          if (mounted) context.go('/dashboard');
          return;
        }
      }

      // Auto-resolve site: find first site with a weighbridge
      final sitesSnap = await db.collection('companies/$companyId/sites').get();
      for (final site in sitesSnap.docs) {
        final wbSnap = await db
            .collection('companies/$companyId/sites/${site.id}/weighbridges')
            .limit(1).get();
        if (wbSnap.docs.isNotEmpty) {
          await ref.read(siteContextProvider.notifier).configure(
            companyId: companyId,
            siteId: site.id,
            weighbridgeId: wbSnap.docs.first.id,
          );
          if (!opFirstLoginDone) {
            if (!mounted) return;
            ref.read(wizardCompanyIdProvider.notifier).state = companyId;
            final siteStepIndex = wizardSteps.indexWhere((s) => s.id == WizardStepId.site);
            final resumed = ref.read(setupWizardProvider.notifier).resumeFromProgress(minStep: siteStepIndex);
            if (!resumed) {
              ref.read(setupWizardProvider.notifier).setRole(WizardRole.admin);
              ref.read(setupWizardProvider.notifier).resumeFromProgress(minStep: siteStepIndex);
            }
            return;
          }
          await ref.read(wizardProgressProvider.notifier).markComplete();
          final allowed = await _runPostLoginChecks(ref, email);
          if (!allowed) return;
          if (mounted) context.go('/dashboard');
          return;
        }
      }

      // No site with weighbridge found
      if (isOperatorRole) {
        setState(() { _error = 'No site assigned yet. Contact your admin.'; _loading = false; });
      } else {
        // Admin with no site/weighbridge — send to site setup
        ref.read(wizardCompanyIdProvider.notifier).state = companyId;
        ref.read(setupWizardProvider.notifier).setRole(WizardRole.returning);
        ref.read(setupWizardProvider.notifier).nextStep();
      }
    } catch (e) {
      debugPrint('SignIn error: $e');
      // Log failed login attempt
      _logLoginAttempt(ref, _email.text.trim(), false);
      if (mounted) setState(() => _error = _parseError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _runPostLoginChecks(WidgetRef ref, String email) async {
    final paths = ref.read(firestorePathsProvider);
    if (!paths.isConfigured) return true;

    final settings = ref.read(securitySettingsProvider).valueOrNull ?? const SecuritySettings();

    // IP whitelist check
    final ipAllowed = await isIpAllowed(settings);
    if (!ipAllowed) {
      _logLoginAttempt(ref, email, false);
      if (mounted) setState(() => _error = 'Access denied: your IP address is not whitelisted.');
      return false;
    }

    // Shift-based login check
    final shiftResult = await validateShiftLogin(paths, email, settings);
    if (!shiftResult.allowed) {
      _logLoginAttempt(ref, email, false);
      if (mounted) setState(() => _error = shiftResult.message ?? 'Login not allowed outside your shift.');
      return false;
    }

    // Password change check
    final passwordResult = await checkPasswordStatus(paths, email, settings);
    if (passwordResult.mustChange && mounted) {
      _logLoginAttempt(ref, email, true);
      setState(() { _error = null; _loading = false; _forcePasswordChange = true; });
      return false;
    }

    // Log successful login
    _logLoginAttempt(ref, email, true);
    return true;
  }

  void _logLoginAttempt(WidgetRef ref, String email, bool success) {
    try {
      final paths = ref.read(firestorePathsProvider);
      if (!paths.isConfigured) return;
      final settings = ref.read(securitySettingsProvider).valueOrNull ?? const SecuritySettings();
      AuditService(paths: paths, settings: settings).logLogin(success: success, email: email);
    } catch (_) {}
  }

  Widget _buildSignInForm(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null) ...[
          Container(
            padding: EdgeInsets.all(12.rs),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10.rs),
              border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: scheme.error),
                SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(_error!, style: TextStyle(fontSize: 12, color: scheme.error, fontWeight: FontWeight.w500))),
              ],
            ),
          ),
          SizedBox(height: 20.rs),
        ],

        Text('Email', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        SizedBox(height: 6.rs),
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Required';
            if (!_emailRegex.hasMatch(v.trim())) return 'Enter a valid email';
            return null;
          },
          decoration: const InputDecoration(
            hintText: 'you@company.com',
            prefixIcon: Icon(Icons.email_outlined, size: 18),
          ),
        ),
        SizedBox(height: AppSpacing.lg),

        Text('Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        SizedBox(height: 6.rs),
        TextFormField(
          controller: _password,
          obscureText: _obscure,
          validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
          decoration: InputDecoration(
            hintText: '••••••••',
            prefixIcon: const Icon(Icons.lock_outline, size: 18),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        SizedBox(height: AppSpacing.md),

        Align(
          alignment: Alignment.centerRight,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => context.go('/forgot-password'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  borderRadius: AppRadius.button,
                  border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
                ),
                child: Text('Forgot Password?',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.primary)),
              ),
            ),
          ),
        ),
        SizedBox(height: 20.rs),

        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _loading ? null : _submit,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            child: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Sign In'),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordChangeForm(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.lock_reset_rounded, size: 20, color: scheme.primary),
            SizedBox(width: AppSpacing.sm),
            Text('Change Password', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        SizedBox(height: AppSpacing.sm),
        Text(
          'Your administrator requires you to set a new password before continuing.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        SizedBox(height: 20.rs),

        if (_changeSuccess != null) ...[
          Container(
            padding: EdgeInsets.all(12.rs),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10.rs),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 16, color: Colors.green),
                SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(_changeSuccess!, style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        ] else ...[
          if (_changeError != null) ...[
            Container(
              padding: EdgeInsets.all(12.rs),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10.rs),
                border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: scheme.error),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(_changeError!, style: TextStyle(fontSize: 12, color: scheme.error, fontWeight: FontWeight.w500))),
                ],
              ),
            ),
            SizedBox(height: AppSpacing.lg),
          ],

          Text('New Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
          SizedBox(height: 6.rs),
          TextFormField(
            controller: _newPassword,
            obscureText: _obscureNew,
            validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
            decoration: InputDecoration(
              hintText: '••••••••',
              prefixIcon: const Icon(Icons.lock_outline, size: 18),
              suffixIcon: IconButton(
                icon: Icon(_obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
            ),
          ),
          SizedBox(height: 14.rs),

          Text('Confirm New Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
          SizedBox(height: 6.rs),
          TextFormField(
            controller: _confirmNewPassword,
            obscureText: _obscureNew,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (v != _newPassword.text) return 'Passwords do not match';
              return null;
            },
            decoration: const InputDecoration(
              hintText: '••••••••',
              prefixIcon: Icon(Icons.lock_outline, size: 18),
            ),
          ),
          SizedBox(height: 20.rs),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _loading ? null : _submitNewPassword,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              child: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Set New Password'),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _submitNewPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _changeError = null; });
    try {
      final email = _email.text.trim();
      final db = ref.read(firestoreProvider);
      final opSnap = await db.collectionGroup('operators')
          .where('email', isEqualTo: email).limit(1).get();
      if (opSnap.docs.isNotEmpty) {
        final updateData = <String, dynamic>{
          'mustChangePassword': false,
          'passwordLastChanged': FieldValue.serverTimestamp(),
        };
        updateData['passwordHash'] = _hashPassword(_newPassword.text);
        await opSnap.docs.first.reference.update(updateData);
      }
      setState(() {
        _loading = false;
        _changeSuccess = 'Password changed. Please sign in with your new password.';
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _forcePasswordChange = false;
            _changeSuccess = null;
            _password.clear();
            _newPassword.clear();
            _confirmNewPassword.clear();
          });
        }
      });
    } catch (e) {
      setState(() { _changeError = 'Failed to update password. Try again.'; _loading = false; });
    }
  }

  String _parseError(String error) {
    if (error.contains('user-not-found')) return 'No account found with this email.';
    if (error.contains('wrong-password') || error.contains('invalid-credential')) return 'Invalid email or password.';
    if (error.contains('too-many-requests')) return 'Too many attempts. Try again later.';
    if (error.contains('network-request-failed')) return 'Network error. Check your connection.';
    return error;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.1),
            borderRadius: AppRadius.dialog,
            border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
          ),
          child: Icon(Icons.scale_rounded, size: 28, color: scheme.primary),
        ),
        SizedBox(height: 20.rs),
        Text(
          'Welcome Back',
          style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        SizedBox(height: AppSpacing.sm),
        Text(
          'Sign in to configure this device',
          style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        SizedBox(height: 40.rs),

        // Sign-in card
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: EdgeInsets.all(32.rs),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(20.rs),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 8)),
              ],
            ),
            child: Form(
              key: _formKey,
              child: _forcePasswordChange
                  ? _buildPasswordChangeForm(scheme, text)
                  : _buildSignInForm(scheme, text),
            ),
          ),
        ),

        SizedBox(height: AppSpacing.xl),

        // Back link
        TextButton.icon(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded, size: 16),
          label: const Text('Back to options'),
        ),
      ],
    );
  }
}

// ── Shared Widgets ─────────────────────────────────────────────────────────

class _RoleCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme scheme;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    required this.scheme,
  });

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: AppSpacing.pagePadding,
          decoration: BoxDecoration(
            color: widget.isSelected
                ? scheme.primary.withValues(alpha: 0.08)
                : _hovered
                    ? scheme.surfaceContainerHighest.withValues(alpha: 0.6)
                    : scheme.surface,
            borderRadius: AppRadius.dialog,
            border: Border.all(
              color: widget.isSelected
                  ? scheme.primary.withValues(alpha: 0.5)
                  : _hovered
                      ? scheme.outlineVariant
                      : scheme.outlineVariant.withValues(alpha: 0.3),
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: widget.isSelected
                ? [BoxShadow(color: scheme.primary.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))]
                : _hovered
                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]
                    : null,
          ),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? scheme.primary.withValues(alpha: 0.12)
                      : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14.rs),
                ),
                child: Icon(widget.icon, size: 24, color: widget.isSelected ? scheme.primary : scheme.onSurfaceVariant),
              ),
              SizedBox(height: AppSpacing.lg),
              Text(
                widget.title,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: scheme.onSurface),
              ),
              SizedBox(height: 6.rs),
              Text(
                widget.subtitle,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.4),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 14.rs),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isSelected ? scheme.primary : Colors.transparent,
                  border: Border.all(
                    color: widget.isSelected ? scheme.primary : scheme.outlineVariant,
                    width: 2,
                  ),
                ),
                child: widget.isSelected
                    ? Icon(Icons.check, size: 14, color: scheme.onPrimary)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubRoleChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme scheme;

  const _SubRoleChip({
    required this.icon,
    required this.label,
    required this.description,
    required this.isSelected,
    required this.onTap,
    required this.scheme,
  });

  @override
  State<_SubRoleChip> createState() => _SubRoleChipState();
}

class _SubRoleChipState extends State<_SubRoleChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? scheme.primary.withValues(alpha: 0.08)
                : _hovered
                    ? scheme.surfaceContainerHigh.withValues(alpha: 0.5)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10.rs),
            border: Border.all(
              color: widget.isSelected
                  ? scheme.primary.withValues(alpha: 0.4)
                  : _hovered
                      ? scheme.outlineVariant.withValues(alpha: 0.5)
                      : scheme.outlineVariant.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 20,
                color: widget.isSelected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: widget.isSelected ? scheme.primary : scheme.onSurface,
                      ),
                    ),
                    Text(
                      widget.description,
                      style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (widget.isSelected)
                Icon(Icons.check_circle_rounded, size: 18, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Appearance Controls (top-right, device-local) ─────────────────────────

const _accentColors = <Color>[
  Color(0xFF059669), // Emerald
  Color(0xFF2563EB), // Blue
  Color(0xFF7C3AED), // Violet
  Color(0xFFDC2626), // Red
  Color(0xFFEA580C), // Orange
  Color(0xFFCA8A04), // Amber
  Color(0xFF0891B2), // Cyan
  Color(0xFF4F46E5), // Indigo
  Color(0xFFDB2777), // Pink
  Color(0xFF16A34A), // Green
  Color(0xFF475569), // Slate
  Color(0xFF1E293B), // Dark
];

class _AppearanceControls extends ConsumerWidget {
  const _AppearanceControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appearanceProvider);
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Theme toggle
        _ThemeToggleButton(
          themeMode: settings.themeMode,
          scheme: scheme,
          onChanged: (mode) => ref.read(appearanceProvider.notifier).setThemeMode(mode),
        ),
        SizedBox(width: AppSpacing.sm),
        // Accent color picker
        _AccentColorButton(
          currentColor: settings.accentColor,
          scheme: scheme,
          onChanged: (color) => ref.read(appearanceProvider.notifier).setAccentColor(color),
        ),
      ],
    );
  }
}

class _ConnectivityPing extends ConsumerWidget {
  const _ConnectivityPing();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityProvider);
    final isOnline = connectivity.valueOrNull ?? false;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PingDot(isOnline: isOnline),
          SizedBox(width: 6.rs),
          Text(
            isOnline ? 'Online' : 'Offline',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isOnline ? const Color(0xFF16A34A) : scheme.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _PingDot extends StatefulWidget {
  final bool isOnline;
  const _PingDot({required this.isOnline});

  @override
  State<_PingDot> createState() => _PingDotState();
}

class _PingDotState extends State<_PingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isOnline ? const Color(0xFF16A34A) : Theme.of(context).colorScheme.error;
    return SizedBox(
      width: 12,
      height: 12,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.isOnline)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final value = _controller.value;
                return Opacity(
                  opacity: (1.0 - value).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 1.0 + value * 1.5,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: color, width: 1.5),
                      ),
                    ),
                  ),
                );
              },
            ),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeToggleButton extends StatelessWidget {
  final ThemeMode themeMode;
  final ColorScheme scheme;
  final ValueChanged<ThemeMode> onChanged;

  const _ThemeToggleButton({required this.themeMode, required this.scheme, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.8),
        borderRadius: AppRadius.button,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildChip(Icons.light_mode_rounded, ThemeMode.light),
          _buildChip(Icons.dark_mode_rounded, ThemeMode.dark),
          _buildChip(Icons.brightness_auto_rounded, ThemeMode.system),
        ],
      ),
    );
  }

  Widget _buildChip(IconData icon, ThemeMode mode) {
    final selected = themeMode == mode;
    return GestureDetector(
      onTap: () => onChanged(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.all(6.rs),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: AppRadius.chip,
        ),
        child: Icon(icon, size: 16, color: selected ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.6)),
      ),
    );
  }
}

class _AccentColorButton extends StatefulWidget {
  final Color currentColor;
  final ColorScheme scheme;
  final ValueChanged<Color> onChanged;

  const _AccentColorButton({required this.currentColor, required this.scheme, required this.onChanged});

  @override
  State<_AccentColorButton> createState() => _AccentColorButtonState();
}

class _AccentColorButtonState extends State<_AccentColorButton> {
  final _overlayController = OverlayPortalController();
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (_) => _buildOverlay(),
        child: GestureDetector(
          onTap: () => _overlayController.toggle(),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: widget.currentColor,
              shape: BoxShape.circle,
              border: Border.all(color: widget.scheme.outlineVariant.withValues(alpha: 0.4), width: 2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => _overlayController.hide(),
      child: Stack(
        children: [
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 8),
            child: GestureDetector(
              onTap: () {},
              child: Container(
                padding: EdgeInsets.all(12.rs),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: AppRadius.card,
                  border: Border.all(color: widget.scheme.outlineVariant.withValues(alpha: 0.3)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _accentColors.map((color) {
                    final selected = widget.currentColor.toARGB32() == color.toARGB32();
                    return GestureDetector(
                      onTap: () {
                        widget.onChanged(color);
                        _overlayController.hide();
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? widget.scheme.onSurface : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: selected ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
