import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/camera_provider.dart';
import 'package:weighbridgemanagement/shared/providers/ai_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';

class LockScreen extends ConsumerStatefulWidget {
  final VoidCallback onUnlock;
  final void Function(String operatorId, String name)? onSwitchOperator;

  const LockScreen({super.key, required this.onUnlock, this.onSwitchOperator});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _passwordController = TextEditingController();
  final _focusNode = FocusNode();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _faceScanning = false;
  String? _faceStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your password or PIN');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Try PIN first (4-6 digits)
    if (RegExp(r'^\d{4,6}$').hasMatch(password)) {
      final pinResult = await _tryPinUnlock(password);
      if (pinResult) return;
    }

    // Try Firebase password
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No authenticated user — restart the app';
        });
        return;
      }

      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);

      if (mounted) widget.onUnlock();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.code == 'wrong-password' || e.code == 'invalid-credential'
              ? 'Incorrect password or PIN'
              : 'Authentication failed';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Authentication failed';
        });
      }
    }
  }

  Future<bool> _tryPinUnlock(String pin) async {
    try {
      final paths = ref.read(firestorePathsProvider);
      final user = FirebaseAuth.instance.currentUser;
      if (user?.email == null) return false;

      final snap = await paths.operators
          .where('email', isEqualTo: user!.email)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) return false;
      final data = snap.docs.first.data();
      final storedPin = data['pin'] as String? ?? '';

      if (storedPin == pin) {
        if (mounted) widget.onUnlock();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _startFaceScan() async {
    final opCam = await ref.read(operatorCameraConfigProvider.future);
    if (!opCam.enabled) {
      setState(() => _errorMessage = 'Operator camera not configured');
      return;
    }

    setState(() {
      _faceScanning = true;
      _faceStatus = 'Scanning...';
      _errorMessage = null;
    });

    try {
      final sidecar = ref.read(sidecarClientProvider);
      final channel = const MethodChannel('com.weighbridge/webcam');
      final frame = await channel.invokeMethod<Uint8List>('captureFrame');

      if (frame == null) {
        setState(() {
          _faceScanning = false;
          _faceStatus = null;
          _errorMessage = 'Could not capture frame';
        });
        return;
      }

      final result = await sidecar.identifyFace(frame, collection: 'operator');
      if (result != null && (result['matched'] == true || result['operator_id'] != null)) {
        if (mounted) {
          final operatorId = result['operator_id'] as String? ?? '';
          final name = result['name'] as String? ?? '';
          if (widget.onSwitchOperator != null && operatorId.isNotEmpty) {
            widget.onSwitchOperator!(operatorId, name);
          }
          widget.onUnlock();
        }
      } else {
        setState(() {
          _faceScanning = false;
          _faceStatus = null;
          _errorMessage = 'Face not recognized';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _faceScanning = false;
          _faceStatus = null;
          _errorMessage = 'Face scan failed';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;
    final opCam = ref.watch(operatorCameraConfigProvider).valueOrNull;
    final hasFaceCamera = opCam?.enabled ?? false;

    return Material(
      color: scheme.surface,
      child: Center(
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.primary.withValues(alpha: 0.8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(Icons.lock_rounded, color: scheme.onPrimary, size: 36),
              ),
              const SizedBox(height: 24),

              Text(
                'Session Locked',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: scheme.onSurface),
              ),
              const SizedBox(height: 8),

              Text(
                user?.email ?? 'Enter password or PIN to unlock',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),

              // Face scan button
              if (hasFaceCamera) ...[
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _faceScanning ? null : _startFaceScan,
                    icon: _faceScanning
                        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary))
                        : Icon(Icons.face_rounded, size: 20),
                    label: Text(_faceScanning ? (_faceStatus ?? 'Scanning...') : 'Unlock with Face'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: Divider(color: scheme.outlineVariant)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ),
                    Expanded(child: Divider(color: scheme.outlineVariant)),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // Password/PIN field
              TextField(
                controller: _passwordController,
                focusNode: _focusNode,
                obscureText: _obscurePassword,
                enabled: !_isLoading,
                onSubmitted: (_) => _unlock(),
                decoration: InputDecoration(
                  labelText: 'Password or PIN',
                  prefixIcon: Icon(Icons.lock_outline_rounded, size: 20, color: scheme.onSurfaceVariant),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  errorText: _errorMessage,
                ),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  onPressed: _isLoading ? null : _unlock,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary))
                      : const Text('Unlock', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
