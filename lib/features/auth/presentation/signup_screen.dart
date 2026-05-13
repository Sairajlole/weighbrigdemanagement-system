import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/features/auth/presentation/animated_background.dart';
import 'package:weighbridgemanagement/shared/providers/auth_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';

enum _AccountType { operator, admin }

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  _AccountType _accountType = _AccountType.operator;

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _companyCode = TextEditingController();
  final _companyName = TextEditingController();

  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _agreedToTerms = false;
  bool _loading = false;
  String? _error;

  late AnimationController _cardController;

  @override
  void initState() {
    super.initState();
    _cardController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
  }

  @override
  void dispose() {
    _cardController.dispose();
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _companyCode.dispose();
    _companyName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedToTerms) {
      setState(() => _error = 'Please agree to the Terms of Service.');
      return;
    }
    if (_password.text != _confirmPassword.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final db = ref.read(firestoreProvider);

      if (_accountType == _AccountType.admin) {
        final cred = await ref.read(firebaseAuthProvider).createUserWithEmailAndPassword(
          email: _email.text.trim(), password: _password.text);
        final uid = cred.user!.uid;
        final now = Timestamp.now();

        final companyRef = await db.collection('companies').add({
          'name': _companyName.text.trim(), 'adminUid': uid, 'createdAt': now,
        });

        await db.collection('operators').add({
          'uid': uid, 'name': _name.text.trim(), 'email': _email.text.trim(),
          'phone': _phone.text.trim(), 'role': 'companyAdmin',
          'companyId': companyRef.id, 'isVerified': true, 'isActive': true, 'createdAt': now,
        });
      } else {
        final companySnap = await db.collection('companies')
            .where('linkageCode', isEqualTo: _companyCode.text.trim().toUpperCase()).limit(1).get();
        if (companySnap.docs.isEmpty) {
          setState(() { _error = 'Invalid company code. Contact your administrator.'; _loading = false; });
          return;
        }
        final companyDoc = companySnap.docs.first;

        final cred = await ref.read(firebaseAuthProvider).createUserWithEmailAndPassword(
          email: _email.text.trim(), password: _password.text);
        final uid = cred.user!.uid;
        final now = Timestamp.now();

        await db.collection('operators').add({
          'uid': uid, 'name': _name.text.trim(), 'email': _email.text.trim(),
          'phone': _phone.text.trim(), 'role': 'operator',
          'companyId': companyDoc.id, 'isVerified': false, 'isActive': true, 'createdAt': now,
        });

        if (mounted) { context.go('/linkage-pending'); return; }
      }
    } catch (e) {
      if (mounted) setState(() => _error = _parseError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _parseError(String error) {
    if (error.contains('email-already-in-use')) return 'An account already exists with this email.';
    if (error.contains('weak-password')) return 'Password is too weak.';
    if (error.contains('network-request-failed')) return 'Network error. Check your connection.';
    return 'Registration failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedAuthBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AnimatedBuilder(
              animation: _cardController,
              builder: (context, child) {
                final t = CurvedAnimation(parent: _cardController, curve: Curves.easeOutBack).value;
                return Opacity(
                  opacity: CurvedAnimation(parent: _cardController, curve: const Interval(0.0, 0.6)).value,
                  child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
                );
              },
              child: _buildCard(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      width: 540,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Colors.white.withValues(alpha: 0.88),
        boxShadow: [
          BoxShadow(color: const Color(0xFF1B5E20).withValues(alpha: 0.08), blurRadius: 40, offset: const Offset(0, 16)),
          BoxShadow(color: Colors.white.withValues(alpha: 0.8), blurRadius: 1, spreadRadius: 1),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 36),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF43A047), Color(0xFF2E7D32)]),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 16),
                      ),
                      const SizedBox(width: 10),
                      const Text('Weighbridge Manager',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Tabs
                _GlassyTabs(activeIndex: 1, onChanged: (i) { if (i == 0) context.go('/login'); }),
                const SizedBox(height: 28),

                // Title
                Text(
                  _accountType == _AccountType.admin ? 'Create Company Account' : 'Create Operator Account',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A), letterSpacing: -0.5),
                ),
                const SizedBox(height: 4),
                Text(
                  _accountType == _AccountType.admin
                      ? 'Manage your weighbridge operations efficiently.'
                      : 'Enter your details to register as a weighbridge operator.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 24),

                // Account type selector
                Row(
                  children: [
                    Expanded(child: _AccountCard(
                      label: 'Operator', subtitle: 'Standard access', icon: Icons.badge_outlined,
                      isSelected: _accountType == _AccountType.operator,
                      onTap: () => setState(() => _accountType = _AccountType.operator),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _AccountCard(
                      label: 'Admin', subtitle: 'Full access', icon: Icons.shield_outlined,
                      isSelected: _accountType == _AccountType.admin,
                      onTap: () => setState(() => _accountType = _AccountType.admin),
                    )),
                  ],
                ),
                const SizedBox(height: 24),

                if (_error != null) ...[
                  _ErrorBanner(message: _error!),
                  const SizedBox(height: 16),
                ],

                // Form fields with animation
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _accountType == _AccountType.operator
                      ? _operatorForm()
                      : _adminForm(),
                ),
                const SizedBox(height: 22),

                // Terms
                GestureDetector(
                  onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 18, height: 18,
                        decoration: BoxDecoration(
                          color: _agreedToTerms ? const Color(0xFF2E7D32) : Colors.transparent,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: _agreedToTerms ? const Color(0xFF2E7D32) : Colors.grey.shade400, width: 1.5),
                        ),
                        child: _agreedToTerms ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            children: [
                              const TextSpan(text: 'I agree to the '),
                              TextSpan(text: 'Terms of Service', style: TextStyle(color: const Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                              const TextSpan(text: ' and '),
                              TextSpan(text: 'Privacy Policy', style: TextStyle(color: const Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),

                _GradientButton(label: 'Create Account', loading: _loading, onTap: _submit, icon: Icons.arrow_forward),
                const SizedBox(height: 18),

                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Already have an account? ', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                      GestureDetector(
                        onTap: () => context.go('/login'),
                        child: const Text('Log in',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32))),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _operatorForm() {
    return Column(
      key: const ValueKey('operator'),
      children: [
        Row(children: [
          Expanded(child: _field('Full Name', _name, 'John Doe', Icons.person_outline)),
          const SizedBox(width: 14),
          Expanded(child: _field('Email', _email, 'john@example.com', Icons.email_outlined, type: TextInputType.emailAddress)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _field('Phone', _phone, '+91 99999 00000', Icons.phone_outlined, type: TextInputType.phone)),
          const SizedBox(width: 14),
          Expanded(child: _field('Company Code', _companyCode, 'CMP-XXXX', Icons.business_outlined)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _passwordField('Password', _password, false)),
          const SizedBox(width: 14),
          Expanded(child: _passwordField('Confirm', _confirmPassword, true)),
        ]),
      ],
    );
  }

  Widget _adminForm() {
    return Column(
      key: const ValueKey('admin'),
      children: [
        _field('Company Name', _companyName, 'Acme Logistics', Icons.business),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _field('Full Name', _name, 'Your name', Icons.person_outline)),
          const SizedBox(width: 14),
          Expanded(child: _field('Email', _email, 'admin@company.com', Icons.email_outlined, type: TextInputType.emailAddress)),
        ]),
        const SizedBox(height: 14),
        _field('Phone', _phone, '+91 99999 00000', Icons.phone_outlined, type: TextInputType.phone),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _passwordField('Password', _password, false)),
          const SizedBox(width: 14),
          Expanded(child: _passwordField('Confirm', _confirmPassword, true)),
        ]),
      ],
    );
  }

  Widget _field(String label, TextEditingController c, String hint, IconData icon, {TextInputType type = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF444444))),
        const SizedBox(height: 6),
        TextFormField(
          controller: c, keyboardType: type,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Required';
            if (type == TextInputType.emailAddress && !v.contains('@')) return 'Invalid';
            return null;
          },
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            prefixIcon: Icon(icon, size: 18, color: Colors.grey.shade400),
            filled: true, fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF43A047), width: 2)),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE53935))),
          ),
        ),
      ],
    );
  }

  Widget _passwordField(String label, TextEditingController c, bool isConfirm) {
    final obscure = isConfirm ? _obscureConfirm : _obscurePass;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF444444))),
        const SizedBox(height: 6),
        TextFormField(
          controller: c, obscureText: obscure,
          validator: (v) => (v == null || v.length < 6) ? 'Min 6 chars' : null,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: '••••••••',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon: Icon(Icons.lock_outline, size: 18, color: Colors.grey.shade400),
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: Colors.grey.shade500),
              onPressed: () => setState(() {
                if (isConfirm) {
                  _obscureConfirm = !_obscureConfirm;
                } else {
                  _obscurePass = !_obscurePass;
                }
              }),
            ),
            filled: true, fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF43A047), width: 2)),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE53935))),
          ),
        ),
      ],
    );
  }
}

// === Account Card ===
class _AccountCard extends StatefulWidget {
  final String label, subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _AccountCard({required this.label, required this.subtitle, required this.icon, required this.isSelected, required this.onTap});

  @override
  State<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<_AccountCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.isSelected ? const Color(0xFFF1F8E9) : (_hovered ? Colors.grey.shade50 : Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.isSelected ? const Color(0xFF43A047) : (_hovered ? Colors.grey.shade400 : Colors.grey.shade200),
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: widget.isSelected ? [
              BoxShadow(color: const Color(0xFF43A047).withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2)),
            ] : null,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 20, height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isSelected ? const Color(0xFF43A047) : Colors.transparent,
                  border: Border.all(color: widget.isSelected ? const Color(0xFF43A047) : Colors.grey.shade400, width: 2),
                ),
                child: widget.isSelected ? const Center(child: Icon(Icons.circle, size: 8, color: Colors.white)) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: widget.isSelected ? const Color(0xFF1B5E20) : Colors.grey.shade700)),
                    Text(widget.subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Icon(widget.icon, size: 20, color: widget.isSelected ? const Color(0xFF43A047) : Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

// === Shared Components ===
class _GlassyTabs extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onChanged;
  const _GlassyTabs({required this.activeIndex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44, padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [_tab('Log In', 0), _tab('Sign Up', 1)]),
    );
  }

  Widget _tab(String label, int index) {
    final isActive = activeIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isActive ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))] : null,
          ),
          child: Center(child: Text(label,
            style: TextStyle(fontSize: 14, fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              color: isActive ? const Color(0xFF1A1A1A) : Colors.grey.shade500))),
        ),
      ),
    );
  }
}

class _GradientButton extends StatefulWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;
  final IconData? icon;
  const _GradientButton({required this.label, required this.loading, required this.onTap, this.icon});

  @override
  State<_GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<_GradientButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (!widget.loading) widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 50,
        transform: Matrix4.diagonal3Values(_pressed ? 0.97 : 1.0, _pressed ? 0.97 : 1.0, 1.0),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF43A047), Color(0xFF2E7D32)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: const Color(0xFF2E7D32).withValues(alpha: _pressed ? 0.2 : 0.35), blurRadius: _pressed ? 8 : 16, offset: Offset(0, _pressed ? 2 : 6))],
        ),
        child: Center(
          child: widget.loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(widget.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                  if (widget.icon != null) ...[const SizedBox(width: 8), Icon(widget.icon, size: 18, color: Colors.white)],
                ]),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEF9A9A).withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFE53935)),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: const TextStyle(fontSize: 13, color: Color(0xFFC62828), fontWeight: FontWeight.w500))),
      ]),
    );
  }
}

