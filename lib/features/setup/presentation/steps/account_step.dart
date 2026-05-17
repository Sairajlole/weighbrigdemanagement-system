import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/auth_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';
import '../../application/setup_wizard_provider.dart';
import '../../application/setup_wizard_state.dart';

String _hashPassword(String password) => sha256.convert(utf8.encode(password)).toString();

// ── Country Data ────────────────────────────────────────────────────────────

class _CountryCode {
  final String name;
  final String dialCode;
  final String code;
  final int minLength;
  final int maxLength;

  const _CountryCode(this.name, this.dialCode, this.code, this.minLength, this.maxLength);
}

const _countries = [
  _CountryCode('India', '+91', 'IN', 10, 10),
  _CountryCode('United States', '+1', 'US', 10, 10),
  _CountryCode('United Kingdom', '+44', 'GB', 10, 11),
  _CountryCode('Australia', '+61', 'AU', 9, 9),
  _CountryCode('Canada', '+1', 'CA', 10, 10),
  _CountryCode('Germany', '+49', 'DE', 10, 11),
  _CountryCode('France', '+33', 'FR', 9, 9),
  _CountryCode('Japan', '+81', 'JP', 10, 11),
  _CountryCode('China', '+86', 'CN', 11, 11),
  _CountryCode('Brazil', '+55', 'BR', 10, 11),
  _CountryCode('South Africa', '+27', 'ZA', 9, 9),
  _CountryCode('UAE', '+971', 'AE', 9, 9),
  _CountryCode('Saudi Arabia', '+966', 'SA', 9, 9),
  _CountryCode('Singapore', '+65', 'SG', 8, 8),
  _CountryCode('Nepal', '+977', 'NP', 10, 10),
  _CountryCode('Bangladesh', '+880', 'BD', 10, 10),
  _CountryCode('Pakistan', '+92', 'PK', 10, 10),
  _CountryCode('Sri Lanka', '+94', 'LK', 9, 9),
  _CountryCode('Indonesia', '+62', 'ID', 10, 12),
  _CountryCode('Malaysia', '+60', 'MY', 9, 10),
];

// ── Email validation ────────────────────────────────────────────────────────

final _emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');

String? _validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) return 'Required';
  if (!_emailRegex.hasMatch(value.trim())) return 'Enter a valid email address';
  return null;
}

// ── Account Step ────────────────────────────────────────────────────────────

class AccountStep extends ConsumerWidget {
  const AccountStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wizardState = ref.watch(setupWizardProvider);
    if (wizardState.role == WizardRole.returning) {
      return const _SignInForm();
    }
    return const _SignUpForm();
  }
}

class _SignUpForm extends ConsumerStatefulWidget {
  const _SignUpForm();

  @override
  ConsumerState<_SignUpForm> createState() => _SignUpFormState();
}

class _SignUpFormState extends ConsumerState<_SignUpForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _companyCode = TextEditingController();
  final _companyName = TextEditingController();

  _CountryCode _selectedCountry = _countries[0]; // India default
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _companyCode.dispose();
    _companyName.dispose();
    super.dispose();
  }

  String get _fullPhone => '${_selectedCountry.dialCode} ${_phone.text.trim()}';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_password.text != _confirmPassword.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final wizardState = ref.read(setupWizardProvider);
      final paths = ref.read(firestorePathsProvider);
      final now = Timestamp.now();

      // Global uniqueness check across all operators (any site/company)
      final db = paths.firestore;
      final email = _email.text.trim();
      final phone = _fullPhone;

      final results = await Future.wait([
        db.collectionGroup('operators').where('email', isEqualTo: email).limit(1).get(),
        db.collectionGroup('operators').where('phone', isEqualTo: phone).limit(1).get(),
        db.collection('companies').where('email', isEqualTo: email).limit(1).get(),
      ]);

      if (results[0].docs.isNotEmpty || results[2].docs.isNotEmpty) {
        setState(() { _error = 'An account with this email already exists.'; _loading = false; });
        return;
      }
      if (results[1].docs.isNotEmpty) {
        setState(() { _error = 'An account with this phone number already exists.'; _loading = false; });
        return;
      }

      // On macOS, keychain issues prevent Firebase Auth — write directly to Firestore
      String? uid;
      if (!Platform.isMacOS) {
        final cred = await ref.read(firebaseAuthProvider).createUserWithEmailAndPassword(
          email: _email.text.trim(), password: _password.text);
        uid = cred.user!.uid;
      } else {
        uid = _email.text.trim().hashCode.toRadixString(36);
      }

      final passwordHash = Platform.isMacOS ? _hashPassword(_password.text) : null;

      if (wizardState.role == WizardRole.admin) {
        await paths.flat('companies').add({
          'name': _companyName.text.trim(), 'adminUid': uid, 'createdAt': now,
        });

        await paths.flat('operators').add({
          'uid': uid, 'name': _name.text.trim(), 'email': _email.text.trim(),
          'phone': _fullPhone, 'role': 'companyAdmin',
          'isVerified': true, 'isActive': true, 'createdAt': now,
          if (passwordHash != null) 'passwordHash': passwordHash,
        });
      } else {
        final companySnap = await paths.flat('companies')
            .where('linkageCode', isEqualTo: _companyCode.text.trim().toUpperCase()).limit(1).get();
        if (companySnap.docs.isEmpty) {
          setState(() { _error = 'Invalid company code. Contact your administrator.'; _loading = false; });
          return;
        }
        final companyDoc = companySnap.docs.first;

        await paths.flat('operators').add({
          'uid': uid, 'name': _name.text.trim(), 'email': _email.text.trim(),
          'phone': _fullPhone, 'role': 'operator',
          'companyId': companyDoc.id, 'isVerified': false, 'isActive': true, 'createdAt': now,
          if (passwordHash != null) 'passwordHash': passwordHash,
        });
      }

      await LocalCacheService.cacheCurrentUserEmail(_email.text.trim());
      setState(() => _done = true);
      ref.read(setupWizardProvider.notifier).nextStep();
    } catch (e) {
      debugPrint('AccountStep error: $e');
      if (mounted) setState(() => _error = _parseError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _parseError(String error) {
    if (error.contains('email-already-in-use')) return 'An account already exists with this email.';
    if (error.contains('weak-password')) return 'Password is too weak (min 6 characters).';
    if (error.contains('network-request-failed')) return 'Network error. Check your connection.';
    if (error.contains('permission-denied')) return 'Permission denied. Check Firestore rules.';
    return error;
  }

  @override
  Widget build(BuildContext context) {
    final wizardState = ref.watch(setupWizardProvider);
    final isAdmin = wizardState.role == WizardRole.admin;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (_done) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 48, color: scheme.primary),
            const SizedBox(height: 16),
            Text('Account created successfully', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAdmin ? 'Create Admin Account' : 'Create Operator Account',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              isAdmin
                  ? 'Set up your administrator account and company.'
                  : 'Enter your details to register as an operator.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_error!, style: TextStyle(fontSize: 13, color: scheme.error, fontWeight: FontWeight.w500))),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            if (isAdmin) ...[
              _buildField('Company Name', _companyName, 'Acme Logistics', Icons.business_rounded),
              const SizedBox(height: 16),
            ] else ...[
              _buildField('Company Code', _companyCode, 'e.g. R6E-5NC', Icons.vpn_key_outlined),
              const SizedBox(height: 16),
            ],

            Row(children: [
              Expanded(child: _buildField('Full Name', _name, 'Your name', Icons.person_outline_rounded)),
              const SizedBox(width: 16),
              Expanded(child: _buildEmailField()),
            ]),
            const SizedBox(height: 16),

            _buildPhoneField(),
            const SizedBox(height: 16),

            Row(children: [
              Expanded(child: _buildPasswordField('Password', _password, false)),
              const SizedBox(width: 16),
              Expanded(child: _buildPasswordField('Confirm Password', _confirmPassword, true)),
            ]),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Create Account'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, String hint, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 18),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Email', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        const SizedBox(height: 6),
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          validator: _validateEmail,
          decoration: const InputDecoration(
            hintText: 'you@company.com',
            prefixIcon: Icon(Icons.email_outlined, size: 18),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneField() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Phone Number', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        const SizedBox(height: 6),
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(_selectedCountry.maxLength),
          ],
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Required';
            final digits = v.replaceAll(RegExp(r'\D'), '');
            if (digits.length < _selectedCountry.minLength) {
              return 'Must be ${_selectedCountry.minLength} digits';
            }
            if (digits.length > _selectedCountry.maxLength) {
              return 'Max ${_selectedCountry.maxLength} digits';
            }
            return null;
          },
          decoration: InputDecoration(
            hintText: _selectedCountry.code == 'IN' ? '99999 00000' : 'Phone number',
            prefixIcon: _buildCountrySelector(),
            prefixIconConstraints: const BoxConstraints(minWidth: 0),
          ),
        ),
      ],
    );
  }

  Widget _buildCountrySelector() {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _showCountryPicker,
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _selectedCountry.dialCode,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: scheme.onSurfaceVariant),
            Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.only(left: 4, right: 8),
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  void _showCountryPicker() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    showDialog(
      context: context,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filtered = query.isEmpty
                ? _countries
                : _countries.where((c) =>
                    c.name.toLowerCase().contains(query.toLowerCase()) ||
                    c.dialCode.contains(query) ||
                    c.code.toLowerCase().contains(query.toLowerCase()),
                  ).toList();

            return AlertDialog(
              title: Text('Select Country', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              content: SizedBox(
                width: 340,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Search country or code...',
                        prefixIcon: Icon(Icons.search, size: 18),
                        isDense: true,
                      ),
                      onChanged: (v) => setDialogState(() => query = v),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final country = filtered[i];
                          final isSelected = country.code == _selectedCountry.code;
                          return ListTile(
                            dense: true,
                            selected: isSelected,
                            selectedTileColor: scheme.primary.withValues(alpha: 0.06),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            title: Text(country.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            trailing: Text(
                              country.dialCode,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.primary),
                            ),
                            leading: isSelected
                                ? Icon(Icons.check_circle, size: 18, color: scheme.primary)
                                : const SizedBox(width: 18),
                            onTap: () {
                              setState(() => _selectedCountry = country);
                              Navigator.of(ctx).pop();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPasswordField(String label, TextEditingController controller, bool isConfirm) {
    final scheme = Theme.of(context).colorScheme;
    final obscure = isConfirm ? _obscureConfirm : _obscurePass;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
          decoration: InputDecoration(
            hintText: '••••••••',
            prefixIcon: const Icon(Icons.lock_outline, size: 18),
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
              onPressed: () => setState(() {
                if (isConfirm) {
                  _obscureConfirm = !_obscureConfirm;
                } else {
                  _obscurePass = !_obscurePass;
                }
              }),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Sign In Form (for returning users) ─────────────────────────────────────

class _SignInForm extends ConsumerStatefulWidget {
  const _SignInForm();

  @override
  ConsumerState<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends ConsumerState<_SignInForm> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    try {
      final db = ref.read(firestorePathsProvider).firestore;
      final email = _email.text.trim();

      if (!Platform.isMacOS) {
        await ref.read(firebaseAuthProvider).signInWithEmailAndPassword(
          email: email,
          password: _password.text,
        );
      }

      // Look up user's operator record to find their company/site
      final operatorSnap = await db
          .collectionGroup('operators')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (operatorSnap.docs.isEmpty) {
        // Check if they're a company admin
        final companySnap = await db
            .collection('companies')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();

        if (companySnap.docs.isEmpty) {
          setState(() { _error = 'No account found with this email.'; _loading = false; });
          return;
        }

        // Admin — find their company's sites
        await LocalCacheService.cacheCurrentUserEmail(email);
        final companyId = companySnap.docs.first.id;
        final sitesSnap = await db.collection('companies/$companyId/sites').limit(1).get();

        if (sitesSnap.docs.isNotEmpty) {
          final siteId = sitesSnap.docs.first.id;
          final wbSnap = await db
              .collection('companies/$companyId/sites/$siteId/weighbridges')
              .limit(1)
              .get();

          if (wbSnap.docs.isNotEmpty) {
            // Fully configured — restore site context and skip to review
            await ref.read(siteContextProvider.notifier).configure(
              companyId: companyId,
              siteId: siteId,
              weighbridgeId: wbSnap.docs.first.id,
            );
            _advanceToReviewOrSite(hasFullContext: true);
            return;
          }
        }

        // Partial setup — has company but no site/weighbridge
        _advanceToReviewOrSite(hasFullContext: false);
        return;
      }

      // Found operator record — verify password on macOS
      final opDoc = operatorSnap.docs.first;
      if (Platform.isMacOS) {
        final storedHash = opDoc.data()['passwordHash'] as String?;
        if (storedHash != null && storedHash != _hashPassword(_password.text)) {
          setState(() { _error = 'Invalid email or password.'; _loading = false; });
          return;
        }
      }

      await LocalCacheService.cacheCurrentUserEmail(email);

      // Resolve their path
      final opPath = opDoc.reference.path;
      final segments = opPath.split('/');

      // Nested path: companies/{cid}/sites/{sid}/operators/{oid} (6 segments)
      // Legacy flat path: operators/{oid} (2 segments)
      if (segments.length >= 6) {
        final companyId = segments[1];
        final siteId = segments[3];

        final wbSnap = await db
            .collection('companies/$companyId/sites/$siteId/weighbridges')
            .limit(1)
            .get();

        if (wbSnap.docs.isNotEmpty) {
          await ref.read(siteContextProvider.notifier).configure(
            companyId: companyId,
            siteId: siteId,
            weighbridgeId: wbSnap.docs.first.id,
          );
          _advanceToReviewOrSite(hasFullContext: true);
        } else {
          _advanceToReviewOrSite(hasFullContext: false);
        }
      } else {
        // Legacy flat operator — check companyId field on the document
        final opData = opDoc.data();
        final companyId = opData['companyId'] as String?;
        if (companyId != null && companyId.isNotEmpty) {
          final sitesSnap = await db.collection('companies/$companyId/sites').limit(1).get();
          if (sitesSnap.docs.isNotEmpty) {
            final siteId = sitesSnap.docs.first.id;
            final wbSnap = await db
                .collection('companies/$companyId/sites/$siteId/weighbridges')
                .limit(1)
                .get();
            if (wbSnap.docs.isNotEmpty) {
              await ref.read(siteContextProvider.notifier).configure(
                companyId: companyId,
                siteId: siteId,
                weighbridgeId: wbSnap.docs.first.id,
              );
              _advanceToReviewOrSite(hasFullContext: true);
              return;
            }
          }
        }
        // No resolvable context — go to site step
        _advanceToReviewOrSite(hasFullContext: false);
      }
    } catch (e) {
      debugPrint('SignIn error: $e');
      if (mounted) setState(() => _error = _parseError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _advanceToReviewOrSite({required bool hasFullContext}) {
    if (hasFullContext) {
      if (mounted) context.go('/dashboard');
    } else {
      ref.read(setupWizardProvider.notifier).nextStep();
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sign In', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Sign in with your existing account to configure this device.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_error!, style: TextStyle(fontSize: 13, color: scheme.error, fontWeight: FontWeight.w500))),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            Text('Email', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              validator: _validateEmail,
              decoration: const InputDecoration(
                hintText: 'you@company.com',
                prefixIcon: Icon(Icons.email_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 16),

            Text('Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
            const SizedBox(height: 6),
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
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Sign In'),
              ),
            ),

            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'After sign-in, you\'ll select which site and weighbridge this device connects to.',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
