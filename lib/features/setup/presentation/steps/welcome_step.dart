import 'dart:async';
import 'dart:io';

import 'package:weighbridgemanagement/shared/theme/app_theme.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:weighbridgemanagement/shared/services/cloud_functions_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

Future<void> _ensureFirebaseAuthAccount(String email, String password) async {
  try {
    await CloudFunctionsService.call('ensureFirebaseAuth', {'email': email, 'password': password});
    await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
  } catch (e) {
  }
}

final _emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');


/// Calls `loginUser`; if the account has TOTP 2FA the server replies with
/// `{mfaRequired: true}` instead of a session — this prompts for the 6-digit
/// code and re-submits until it succeeds. Returns the final loginUser result,
/// or null if the user cancels the 2FA prompt.
Future<Map<String, dynamic>?> loginUserWithMfa(BuildContext context, String email, String password,
    {Future<String?> Function({String? error})? getCode}) async {
  final first = await CloudFunctionsService.call('loginUser', {'email': email, 'password': password});
  if (first['mfaRequired'] != true) return first;
  // Inline code entry when [getCode] is supplied; otherwise fall back to the dialog.
  final prompt = getCode ?? (({String? error}) => _promptTotpCode(context, error: error));
  String? error;
  while (true) {
    if (!context.mounted) return null;
    final code = await prompt(error: error);
    if (code == null || code.isEmpty) return null; // cancelled
    try {
      final r = await CloudFunctionsService.call(
          'loginUser', {'email': email, 'password': password, 'totpCode': code});
      if (r['mfaRequired'] == true) {
        error = 'Invalid code. Try again.';
        continue;
      }
      return r;
    } catch (_) {
      error = 'Invalid code. Try again.';
    }
  }
}

Future<String?> _promptTotpCode(BuildContext context, {String? error}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Two-factor authentication'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Enter the 6-digit code from your authenticator app, or one of your recovery codes.'),
          const SizedBox(height: 14),
          TextField(
            controller: ctrl,
            autofocus: true,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
              LengthLimitingTextInputFormatter(11),
            ],
            decoration: InputDecoration(hintText: '6-digit or recovery code', errorText: error, counterText: ''),
            style: const TextStyle(fontSize: 18, letterSpacing: 2, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Verify')),
      ],
    ),
  );
  // Controller intentionally not disposed — disposing on dialog close races the
  // exit animation rebuilding the TextField; it's a lightweight, short-lived
  // notifier collected with the closure.
}

class WelcomeStep extends ConsumerStatefulWidget {
  final bool initialSignIn;
  const WelcomeStep({super.key, this.initialSignIn = false});

  @override
  ConsumerState<WelcomeStep> createState() => _WelcomeStepState();
}

enum _WelcomeView { roles, signIn, resumeSignIn, forgotPassword }

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
    final contentScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // Brand name fixed, content scrollable below
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Spacer(flex: _view == _WelcomeView.resumeSignIn || _view == _WelcomeView.forgotPassword ? 1 : 3),
            // Brand name
            Text(
              'tulanam',
              style: TextStyle(
                fontSize: 80,
                fontWeight: FontWeight.w800,
                color: contentScheme.onSurface,
                letterSpacing: 2,
                height: 1,
              ),
            ),
            const SizedBox(height: 36),
            Flexible(
              flex: 7,
              child: SingleChildScrollView(
                primary: true,
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 540),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: child,
                        ),
                      ),
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      ),
                      child: switch (_view) {
                        _WelcomeView.signIn => _SignInContent(
                            key: const ValueKey('signin'),
                            onBack: () => setState(() => _view = _WelcomeView.roles),
                            onForgotPassword: () => setState(() => _view = _WelcomeView.forgotPassword),
                          ),
                        _WelcomeView.resumeSignIn => _ResumeSignInContent(
                            key: const ValueKey('resume'),
                            onBack: () => setState(() => _view = _WelcomeView.roles),
                          ),
                        _WelcomeView.forgotPassword => _ForgotPasswordContent(
                            key: const ValueKey('forgot'),
                            onBack: () => setState(() => _view = _WelcomeView.signIn),
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
              ),
            ),
          ],
        ),
        // Footer — ping left, website right
        const Positioned(
          bottom: 16,
          left: 20,
          child: _ConnectivityPing(),
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
        // Role cards
        Row(
          children: [
            Expanded(
              child: _RoleCard(
                icon: Icons.rocket_launch_rounded,
                title: 'New here',
                subtitle: 'Set up your weighbridge for the first time',
                isSelected: state.role == WizardRole.admin || state.role == WizardRole.operator,
                onTap: () => ref.read(setupWizardProvider.notifier).setRole(WizardRole.admin),
                scheme: scheme,
              ),
            ),
            SizedBox(width: 16.rs),
            Expanded(
              child: _RoleCard(
                icon: Icons.arrow_forward_rounded,
                title: 'Returning',
                subtitle: 'Already registered? Connect this device',
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
          constraints: const BoxConstraints(maxWidth: 640),
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
  String? _pan;
  String? _state;
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
            _pan = data['pan'] as String? ?? '';
            _state = data['state'] as String? ?? '';
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

      // Server-side password verification + single-session registration.
      // loginUser stamps a new activeSessionId on the user doc (newest login
      // wins). Failure is fatal only when real Firebase Auth didn't verify.
      try {
        final r = await loginUserWithMfa(context, email, _password.text);
        if (r == null) { setState(() => _loading = false); return; } // 2FA cancelled
        final sid = r['activeSessionId'] as String?;
        if (sid != null) await LocalCacheService.cacheSessionId(sid);
      } catch (e) {
        if (!firebaseAuthOk) {
          setState(() { _error = 'Invalid email or password.'; _loading = false; });
          return;
        }
      }

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
        companyId = companySnap.docs.first.id;
      } else {
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
        Text(
          'Resume Setup',
          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
        ),
        SizedBox(height: AppSpacing.xs),
        Text(
          'Sign in to continue where you left off',
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        SizedBox(height: 16.rs),

        // Info bar — explains what happened
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
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
        SizedBox(height: 14.rs),

        // Company/GSTIN details card
        if (!_loadingDetails && _gstin != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
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
                          ],
                        ),
                      ),
                      SizedBox(width: AppSpacing.sm),
                      _DetailChip(icon: Icons.assignment_ind_rounded, label: 'GSTIN: $_gstin', scheme: scheme),
                    ],
                  ),
                  SizedBox(height: AppSpacing.md),
                  Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.2)),
                  SizedBox(height: AppSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_pan != null && _pan!.isNotEmpty)
                        Flexible(child: _DetailChip(icon: Icons.badge_outlined, label: 'PAN: $_pan', scheme: scheme)),
                      if (_entityType != null && _entityType!.isNotEmpty)
                        Flexible(child: _DetailChip(icon: Icons.category_outlined, label: _entityType!, scheme: scheme)),
                      if (_state != null && _state!.isNotEmpty)
                        Flexible(child: _DetailChip(icon: Icons.location_on_outlined, label: _state!, scheme: scheme)),
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

        SizedBox(height: AppSpacing.md),

        // Sign-in form
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Container(
            padding: AppSpacing.cardPadding,
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

        SizedBox(height: 14.rs),

        // Options row
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
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
  final VoidCallback onForgotPassword;

  const _SignInContent({super.key, required this.onBack, required this.onForgotPassword});

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

  // Inline 2FA (TOTP) — shown in-card instead of a dialog when MFA is required.
  final _totp = TextEditingController();
  bool _mfaPending = false;
  String? _totpError;
  Completer<String?>? _totpCompleter;

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
    _totp.dispose();
    _newPassword.dispose();
    _confirmNewPassword.dispose();
    super.dispose();
  }

  /// Surfaces the inline TOTP field and waits for the user to submit/cancel it.
  Future<String?> _inlineGetCode({String? error}) {
    _totpCompleter = Completer<String?>();
    setState(() { _mfaPending = true; _totpError = error; _loading = false; });
    return _totpCompleter!.future;
  }

  void _verifyTotp() {
    if (_totp.text.trim().isEmpty) {
      setState(() => _totpError = 'Enter your code.');
      return;
    }
    setState(() { _loading = true; _totpError = null; });
    _totpCompleter?.complete(_totp.text.trim());
  }

  void _cancelTotp() {
    _totpCompleter?.complete(null);
    setState(() { _mfaPending = false; _loading = false; _totpError = null; _totp.clear(); });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    try {
      final db = ref.read(firestoreProvider);
      final email = _email.text.trim();
      if (Platform.isWindows) {
        await _submitWindows(db, email);
      } else {
        await _submitDefault(db, email);
      }
    } catch (e) {
      if (!mounted) return;
      _logLoginAttempt(ref, _email.text.trim(), false);
      setState(() => _error = _parseError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Windows login: Firebase Auth first, then resolve company/operator via
  /// simple collection queries (no collectionGroup — avoids native threading issues).
  Future<void> _submitWindows(FirebaseFirestore db, String email) async {
    // Step 1: Authenticate with Firebase Auth — this validates credentials
    // and establishes the gRPC channel before any Firestore queries.
    try {
      await ref.read(firebaseAuthProvider).signInWithEmailAndPassword(
        email: email,
        password: _password.text,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        setState(() { _error = 'Invalid email or password.'; _loading = false; });
        return;
      }
      rethrow;
    }
    if (!mounted) return;

    await LocalCacheService.cacheCurrentUserEmail(email);

    // Step 2: Find the company — check if this user is a company admin first.
    final companySnap = await db
        .collection('companies')
        .where('email', isEqualTo: email)
        .limit(1)
        .get()
        .timeout(const Duration(seconds: 30), onTimeout: () {
          throw TimeoutException('Companies query timed out');
        });
    if (!mounted) return;

    String? companyId;
    bool isCompanyAdmin = false;

    if (companySnap.docs.isNotEmpty) {
      companyId = companySnap.docs.first.id;
      isCompanyAdmin = true;
    } else {
      // Not a company admin — find via collectionGroup with generous timeout.
      final operatorSnap = await db
          .collectionGroup('operators')
          .where('email', isEqualTo: email)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 60), onTimeout: () {
            throw TimeoutException('Could not reach server. Check your internet connection.');
          });

      if (operatorSnap.docs.isEmpty) {
        setState(() { _error = 'No account found with this email.'; _loading = false; });
        return;
      }

      final opDoc = operatorSnap.docs.first;
      final opData = opDoc.data();

      if (opData['isDeleted'] == true) {
        setState(() { _error = 'Invalid email or password.'; _loading = false; });
        return;
      }
      if (opData['isArchived'] == true) {
        setState(() { _error = 'Your account has been archived. Contact your administrator to restore access.'; _loading = false; });
        return;
      }
      final isVerified = opData['isVerified'] as bool? ?? false;
      final isActive = opData['isActive'] as bool? ?? false;
      if (!isVerified || !isActive) {
        setState(() { _error = 'Your account is pending approval. Please wait for your administrator to accept your request.'; _loading = false; });
        return;
      }

      // Resolve companyId from doc path
      final segments = opDoc.reference.path.split('/');
      if (segments.length >= 6 && segments[0] == 'companies') {
        companyId = segments[1];
      } else if (segments.length >= 4 && segments[0] == 'companies') {
        companyId = segments[1];
      }
      companyId ??= opData['companyId'] as String?;
    }

    if (companyId == null || companyId.isEmpty) {
      setState(() { _error = 'No company linked to this account.'; _loading = false; });
      return;
    }
    if (!mounted) return;

    // Step 3: Configure site context
    await _configureSiteAndNavigate(db, companyId, email, isCompanyAdmin);
  }

  /// Default (mobile/macOS) login — original flow with collectionGroup.
  Future<void> _submitDefault(FirebaseFirestore db, String email) async {
    bool firebaseAuthOk = false;
    try {
      await ref.read(firebaseAuthProvider).signInWithEmailAndPassword(
        email: email,
        password: _password.text,
      );
      firebaseAuthOk = true;
    } catch (e) {
    }
    if (!mounted) return;

    // Server-side password verification + single-session registration.
    try {
      final r = await loginUserWithMfa(context, email, _password.text, getCode: _inlineGetCode);
      if (r == null) { setState(() { _loading = false; _mfaPending = false; }); return; } // 2FA cancelled
      if (_mfaPending) setState(() { _mfaPending = false; _totp.clear(); });
      final sid = r['activeSessionId'] as String?;
      if (sid != null) await LocalCacheService.cacheSessionId(sid);
    } catch (e) {
      if (!firebaseAuthOk) {
        setState(() { _error = 'Invalid email or password.'; _loading = false; });
        return;
      }
    }

    final operatorSnap = await db
        .collectionGroup('operators')
        .where('email', isEqualTo: email)
        .limit(1)
        .get()
        .timeout(const Duration(seconds: 8), onTimeout: () {
          throw TimeoutException('Query timed out');
        });

    if (operatorSnap.docs.isEmpty) {
      final companySnap = await db
          .collection('companies')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (companySnap.docs.isEmpty) {
        setState(() { _error = 'No account found with this email.'; _loading = false; });
        return;
      }

      await _ensureFirebaseAuthAccount(email, _password.text);
      if (!mounted) return;
      await LocalCacheService.cacheCurrentUserEmail(email);
      final companyId = companySnap.docs.first.id;

      await _configureSiteAndNavigate(db, companyId, email, true);
      return;
    }

    // Found operator record (password already verified server-side above).
    final opDoc = operatorSnap.docs.first;
    final opData = opDoc.data();

    if (opData['isDeleted'] == true) {
      setState(() { _error = 'Invalid email or password.'; _loading = false; });
      return;
    }
    if (opData['isArchived'] == true) {
      setState(() { _error = 'Your account has been archived. Contact your administrator to restore access.'; _loading = false; });
      return;
    }
    final isVerified = opData['isVerified'] as bool? ?? false;
    final isActive = opData['isActive'] as bool? ?? false;
    if (!isVerified || !isActive) {
      setState(() { _error = 'Your account is pending approval. Please wait for your administrator to accept your request.'; _loading = false; });
      return;
    }

    if (!firebaseAuthOk) await _ensureFirebaseAuthAccount(email, _password.text);
    if (!mounted) return;
    await LocalCacheService.cacheCurrentUserEmail(email);
    ref.read(sessionLoggedInProvider.notifier).state = true;

    final opRole = opData['role'] as String? ?? '';
    final isOperatorRole = opRole == 'operator';

    final opPath = opDoc.reference.path;
    final segments = opPath.split('/');
    String? companyId;
    String? siteIdFromPath;

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
    if (!mounted) return;
    final opFirstLoginDone = opCompanyDoc.data()?['firstLoginComplete'] == true;

    if (siteIdFromPath != null) {
      final wbSnap = await db
          .collection('companies/$companyId/sites/$siteIdFromPath/weighbridges')
          .limit(1).get();
      if (!mounted) return;
      if (wbSnap.docs.isNotEmpty) {
        await ref.read(siteContextProvider.notifier).configure(
          companyId: companyId,
          siteId: siteIdFromPath,
          weighbridgeId: wbSnap.docs.first.id,
        );
        if (!mounted) return;
        if (!opFirstLoginDone) {
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
        if (!mounted) return;
        final allowed = await _runPostLoginChecks(ref, email);
        if (!allowed || !mounted) return;
        context.go('/dashboard');
        return;
      }
    }

    await _configureSiteAndNavigate(db, companyId, email, !isOperatorRole);
  }

  /// Shared: find first site with a weighbridge, configure context, navigate.
  Future<void> _configureSiteAndNavigate(
    FirebaseFirestore db, String companyId, String email, bool isAdmin,
  ) async {
    final companyDoc = await db.doc('companies/$companyId').get();
    if (!mounted) return;
    final firstLoginDone = companyDoc.data()?['firstLoginComplete'] == true;

    final sitesSnap = await db.collection('companies/$companyId/sites').get();
    if (!mounted) return;

    for (final site in sitesSnap.docs) {
      final wbSnap = await db
          .collection('companies/$companyId/sites/${site.id}/weighbridges')
          .limit(1)
          .get();
      if (!mounted) return;
      if (wbSnap.docs.isNotEmpty) {
        await ref.read(siteContextProvider.notifier).configure(
          companyId: companyId,
          siteId: site.id,
          weighbridgeId: wbSnap.docs.first.id,
        );
        if (!mounted) return;
        if (!firstLoginDone) {
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
        await ref.read(wizardProgressProvider.notifier).markComplete();
        ref.read(sessionLoggedInProvider.notifier).state = true;
        if (!mounted) return;
        final allowed = await _runPostLoginChecks(ref, email);
        if (!allowed || !mounted) return;
        context.go('/dashboard');
        return;
      }
    }

    if (!mounted) return;
    if (!isAdmin) {
      setState(() { _error = 'No site assigned yet. Contact your admin.'; _loading = false; });
    } else {
      ref.read(wizardCompanyIdProvider.notifier).state = companyId;
      ref.read(setupWizardProvider.notifier).setRole(WizardRole.returning);
      ref.read(setupWizardProvider.notifier).nextStep();
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
          enabled: !_mfaPending,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
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
          enabled: !_mfaPending,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _loading ? null : _submit(),
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

        if (_mfaPending) ...[
          Text('Two-factor code', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
          SizedBox(height: 6.rs),
          TextFormField(
            controller: _totp,
            autofocus: true,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
              LengthLimitingTextInputFormatter(11),
            ],
            onFieldSubmitted: (_) => _loading ? null : _verifyTotp(),
            style: const TextStyle(fontSize: 18, letterSpacing: 2, fontWeight: FontWeight.w600),
            textAlign: TextAlign.start,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.verified_user_outlined, size: 18),
              errorText: _totpError,
              counterText: '',
            ),
          ),
          SizedBox(height: 20.rs),
        ] else ...[
          Align(
            alignment: Alignment.centerRight,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.onForgotPassword,
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
        ],

        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _loading ? null : (_mfaPending ? _verifyTotp : _submit),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            child: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_mfaPending ? 'Verify' : 'Sign In'),
          ),
        ),
        if (_mfaPending) ...[
          SizedBox(height: 8.rs),
          Center(
            child: TextButton(
              onPressed: _loading ? null : _cancelTotp,
              child: const Text('Use a different account'),
            ),
          ),
        ],
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
        await opSnap.docs.first.reference.update(updateData);
      }
      // Store the new password as a salted server-side credential.
      await CloudFunctionsService.call('registerCredential', {'email': email, 'password': _newPassword.text});
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
        // Sign-in card
        Container(
          padding: EdgeInsets.all(36.rs),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20.rs),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.15)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8)),
            ],
          ),
          child: Form(
            key: _formKey,
            child: _forcePasswordChange
                ? _buildPasswordChangeForm(scheme, text)
                : _buildSignInForm(scheme, text),
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

// ── Forgot Password (inline, same page) ──────────────────────────────────

enum _ResetStep { email, otp, newPassword, success }

class _ForgotPasswordContent extends ConsumerStatefulWidget {
  final VoidCallback onBack;

  const _ForgotPasswordContent({super.key, required this.onBack});

  @override
  ConsumerState<_ForgotPasswordContent> createState() => _ForgotPasswordContentState();
}

class _ForgotPasswordContentState extends ConsumerState<_ForgotPasswordContent> {
  final _email = TextEditingController();
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(6, (_) => FocusNode());
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  _ResetStep _step = _ResetStep.email;
  bool _loading = false;
  bool _mfaMode = false; // verify via authenticator instead of email/SMS reset code
  String? _error;
  String? _maskedPhone;
  bool _phoneSent = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String _verificationToken = '';

  @override
  void dispose() {
    _email.dispose();
    for (final c in _otpControllers) { c.dispose(); }
    for (final f in _otpFocusNodes) { f.dispose(); }
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  String get _otpValue => _otpControllers.map((c) => c.text).join();

  Future<void> _sendOTP() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      // Prefer the account's authenticator (2FA) over an emailed reset code.
      try {
        final mfa = await CloudFunctionsService.call('mfaStatus', {'email': email});
        if (mfa['enabled'] == true) {
          if (mounted) setState(() { _mfaMode = true; _loading = false; _step = _ResetStep.otp; });
          return;
        }
      } catch (_) {/* fall through to email */}
      _mfaMode = false;
      final data = await CloudFunctionsService.call('sendPasswordResetOTP', {'email': email});
      if (mounted) {
        setState(() {
          _phoneSent = data['phoneSent'] == true;
          _maskedPhone = data['maskedPhone'] as String?;
          _step = _ResetStep.otp;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to send OTP. Check the email address.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Fallback to an emailed reset code when MFA was preferred.
  Future<void> _useEmailReset() async {
    setState(() { _mfaMode = false; _loading = true; _error = null; });
    try {
      final data = await CloudFunctionsService.call('sendPasswordResetOTP', {'email': _email.text.trim()});
      if (mounted) setState(() { _phoneSent = data['phoneSent'] == true; _maskedPhone = data['maskedPhone'] as String?; });
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to send code.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyOTP() async {
    final otp = _otpValue;
    if (otp.length != 6) {
      setState(() => _error = 'Please enter all 6 digits.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final data = _mfaMode
          ? await CloudFunctionsService.call('verifyMfaCode', {'email': _email.text.trim(), 'code': otp, 'mintResetToken': true})
          : await CloudFunctionsService.call('verifyPasswordResetOTP', {'email': _email.text.trim(), 'otp': otp});
      if (mounted) {
        _verificationToken = data['verificationToken'] as String? ?? 'otp_verified';
        setState(() => _step = _ResetStep.newPassword);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Verification failed. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final pw = _newPassword.text;
    final confirm = _confirmPassword.text;
    if (pw.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (pw != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      await CloudFunctionsService.call('resetUserPassword', {
        'email': _email.text.trim(),
        'newPassword': pw,
        'verificationToken': _verificationToken,
      });
      if (mounted) setState(() => _step = _ResetStep.success);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendOTP() async {
    for (final c in _otpControllers) { c.clear(); }
    setState(() => _error = null);
    await _sendOTP();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(32.rs),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20.rs),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.15)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 40.rs,
                    height: 40.rs,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: AppRadius.button,
                    ),
                    child: Icon(Icons.lock_reset_rounded, size: AppSizes.iconMd, color: scheme.primary),
                  ),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Reset Password', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        SizedBox(height: 2.rs),
                        Text(_stepSubtitle, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24.rs),
              Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
              SizedBox(height: 24.rs),
              _buildStepContent(scheme, text),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.xl),
        TextButton.icon(
          onPressed: _step == _ResetStep.success ? widget.onBack : widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded, size: 16),
          label: const Text('Back to Sign In'),
        ),
      ],
    );
  }

  String get _stepSubtitle {
    switch (_step) {
      case _ResetStep.email:
        return 'Enter your email to receive a verification code.';
      case _ResetStep.otp:
        return _mfaMode
            ? 'Enter the code from your authenticator app.'
            : (_phoneSent && _maskedPhone != null
                ? 'Code sent to email and phone ($_maskedPhone).'
                : 'Code sent to your email address.');
      case _ResetStep.newPassword:
        return 'Set your new password.';
      case _ResetStep.success:
        return 'Done! Your password has been reset.';
    }
  }

  Widget _buildStepContent(ColorScheme scheme, TextTheme text) {
    switch (_step) {
      case _ResetStep.email:
        return _buildEmailStep(scheme, text);
      case _ResetStep.otp:
        return _buildOtpStep(scheme, text);
      case _ResetStep.newPassword:
        return _buildNewPasswordStep(scheme, text);
      case _ResetStep.success:
        return _buildSuccessStep(scheme, text);
    }
  }

  Widget _buildError(ColorScheme scheme) {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.lg),
      child: Container(
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
    );
  }

  Widget _buildEmailStep(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildError(scheme),
        Text('Email', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        SizedBox(height: 6.rs),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          style: text.bodyMedium,
          onSubmitted: (_) => _sendOTP(),
          decoration: const InputDecoration(
            hintText: 'you@company.com',
            prefixIcon: Icon(Icons.email_outlined, size: 18),
          ),
        ),
        SizedBox(height: 20.rs),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _loading ? null : _sendOTP,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            child: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Send Verification Code'),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpStep(ColorScheme scheme, TextTheme text) {
    return Column(
      children: [
        _buildError(scheme),
        if (_phoneSent && _maskedPhone != null)
          Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.lg),
            child: Container(
              padding: EdgeInsets.all(12.rs),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10.rs),
              ),
              child: Row(
                children: [
                  Icon(Icons.phone_android_rounded, size: 16, color: scheme.primary),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Also sent via SMS to $_maskedPhone',
                      style: TextStyle(fontSize: 12, color: scheme.primary, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            return Container(
              width: 44.rs,
              height: 52.rs,
              margin: EdgeInsets.only(right: i < 5 ? 8.rs : 0),
              child: TextField(
                controller: _otpControllers[i],
                focusNode: _otpFocusNodes[i],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 1,
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: '',
                  contentPadding: EdgeInsets.symmetric(vertical: 12.rs),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.rs)),
                ),
                onChanged: (val) {
                  if (val.isNotEmpty && i < 5) {
                    _otpFocusNodes[i + 1].requestFocus();
                  } else if (val.isEmpty && i > 0) {
                    _otpFocusNodes[i - 1].requestFocus();
                  }
                  if (_otpValue.length == 6) {
                    _verifyOTP();
                  }
                },
              ),
            );
          }),
        ),
        SizedBox(height: 20.rs),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _loading ? null : _verifyOTP,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            child: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Verify Code'),
          ),
        ),
        SizedBox(height: AppSpacing.md),
        TextButton(
          onPressed: _loading ? null : (_mfaMode ? _useEmailReset : _resendOTP),
          child: Text(_mfaMode ? 'Send a code to my email instead' : 'Resend Code'),
        ),
      ],
    );
  }

  Widget _buildNewPasswordStep(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildError(scheme),
        Text('New Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        SizedBox(height: 6.rs),
        TextField(
          controller: _newPassword,
          obscureText: _obscureNew,
          style: text.bodyMedium,
          decoration: InputDecoration(
            hintText: 'Minimum 8 characters',
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
            suffixIcon: IconButton(
              icon: Icon(_obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
          ),
        ),
        SizedBox(height: AppSpacing.lg),
        Text('Confirm Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        SizedBox(height: 6.rs),
        TextField(
          controller: _confirmPassword,
          obscureText: _obscureConfirm,
          style: text.bodyMedium,
          onSubmitted: (_) => _resetPassword(),
          decoration: InputDecoration(
            hintText: 'Re-enter your password',
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
        ),
        SizedBox(height: 20.rs),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _loading ? null : _resetPassword,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            child: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Reset Password'),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessStep(ColorScheme scheme, TextTheme text) {
    return Column(
      children: [
        Container(
          width: 48.rs,
          height: 48.rs,
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF2E7D32), size: 24),
        ),
        SizedBox(height: AppSpacing.lg),
        Text('Password Reset!', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF2E7D32))),
        SizedBox(height: AppSpacing.sm),
        Text(
          'You can now sign in with your new password.',
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        SizedBox(height: 20.rs),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: widget.onBack,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            child: const Text('Go to Sign In'),
          ),
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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? scheme.surface
                : _hovered
                    ? scheme.surface.withValues(alpha: 0.8)
                    : scheme.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16.rs),
            border: Border.all(
              color: widget.isSelected
                  ? AppTheme.brandTeal
                  : _hovered
                      ? scheme.outlineVariant.withValues(alpha: 0.5)
                      : scheme.outlineVariant.withValues(alpha: 0.2),
              width: widget.isSelected ? 1.5 : 1,
            ),
            boxShadow: widget.isSelected
                ? [BoxShadow(color: AppTheme.brandTeal.withValues(alpha: 0.1), blurRadius: 16, offset: const Offset(0, 4))]
                : _hovered
                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))]
                    : null,
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 22,
                color: widget.isSelected ? AppTheme.brandTeal : scheme.onSurfaceVariant,
              ),
              SizedBox(width: 16.rs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: widget.isSelected ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                    SizedBox(height: 3.rs),
                    Text(
                      widget.subtitle,
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.3),
                    ),
                  ],
                ),
              ),
              if (widget.isSelected)
                Icon(Icons.check_circle_rounded, size: 20, color: AppTheme.brandTeal),
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





class _ConnectivityPing extends ConsumerWidget {
  const _ConnectivityPing();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityProvider);
    final isOnline = connectivity.valueOrNull ?? false;

    return Tooltip(
      message: isOnline ? 'Online' : 'Offline',
      child: _PingDot(isOnline: isOnline),
    );
  }
}

class _PingDot extends StatelessWidget {
  final bool isOnline;
  const _PingDot({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? AppTheme.successColor : Theme.of(context).colorScheme.error;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}


