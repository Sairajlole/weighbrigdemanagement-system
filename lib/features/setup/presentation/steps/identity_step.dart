import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import '../../application/setup_wizard_provider.dart';

class IdentityStep extends ConsumerStatefulWidget {
  const IdentityStep({super.key});

  @override
  ConsumerState<IdentityStep> createState() => _IdentityStepState();
}

class _IdentityStepState extends ConsumerState<IdentityStep> {
  static const _documentTypes = ['Aadhaar', 'PAN', 'Driving License', 'Passport'];

  String _selectedDocType = 'Aadhaar';
  bool _scanning = false;
  String? _error;
  String? _extractedName;
  String? _extractedNumber;
  bool _idVerified = false;

  // Face enrollment
  bool _faceEnrolled = false;
  bool _capturingFace = false;
  String? _faceError;
  String? _faceImageUri;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(stepSaveCallbackProvider.notifier).state = _save;
      ref.read(stepHasDataProvider.notifier).state = false;
    });
  }

  void _updateHasData() {
    ref.read(stepHasDataProvider.notifier).state = _idVerified && _faceEnrolled;
  }

  Future<bool> _save() async {
    if (!_idVerified || !_faceEnrolled) return false;
    return true;
  }

  String get _uploadHint => switch (_selectedDocType) {
    'Aadhaar' => 'Upload both sides (front + back) of your Aadhaar card.',
    'PAN' => 'Upload full PAN card (front side with photo and number).',
    'Driving License' => 'Upload both sides (front + back) of Driving License.',
    'Passport' => 'Upload passport pages showing photo and details.',
    _ => 'Upload all relevant pages/sides of the document.',
  };

  Future<void> _uploadAndScanId() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() { _scanning = true; _error = null; });

    try {
      final images = <String>[];
      for (final f in result.files) {
        if (f.bytes != null && f.bytes!.isNotEmpty) {
          images.add(base64Encode(f.bytes!));
        } else if (f.path != null && f.path!.isNotEmpty) {
          try {
            final file = File(f.path!);
            if (await file.exists()) {
              final fileBytes = await file.readAsBytes();
              if (fileBytes.isNotEmpty) images.add(base64Encode(fileBytes));
            }
          } catch (_) {}
        }
      }
      if (images.isEmpty) {
        setState(() { _scanning = false; _error = 'Could not read the selected file(s). Try a PDF instead.'; });
        return;
      }

      final paths = ref.read(firestorePathsProvider);
      final companyId = ref.read(wizardCompanyIdProvider) ?? paths.context.companyId;

      // Get operator name from invited data or Firestore
      String operatorName = '';
      final invitedOp = ref.read(wizardInvitedOperatorProvider);
      if (invitedOp != null) {
        operatorName = invitedOp['name'] as String? ?? '';
      }
      if (operatorName.isEmpty) {
        final email = await LocalCacheService.getCachedCurrentUserEmail();
        if (email != null && email.isNotEmpty) {
          final db = paths.firestore;
          final opSnap = await db.collection('operators')
              .where('email', isEqualTo: email).limit(1).get();
          if (opSnap.docs.isNotEmpty) {
            operatorName = opSnap.docs.first.data()['name'] as String? ?? '';
          }
        }
      }

      final response = await FirebaseFunctions.instance
          .httpsCallable('verifyOperatorId', options: HttpsCallableOptions(timeout: const Duration(seconds: 90)))
          .call({
        'images': images,
        'documentType': _selectedDocType,
        'operatorName': operatorName,
        'companyId': companyId,
      });

      final data = response.data as Map<String, dynamic>;

      if (data['valid'] != true) {
        setState(() { _scanning = false; _error = data['message'] as String? ?? 'Verification failed.'; });
        return;
      }

      setState(() {
        _scanning = false;
        _extractedName = data['extractedName'] as String?;
        _extractedNumber = data['extractedDocNumber'] as String?;
        _idVerified = true;
        _error = null;
      });
      _updateHasData();
    } on FirebaseFunctionsException catch (e) {
      setState(() { _scanning = false; _error = e.message ?? 'Scan failed.'; });
    } catch (e) {
      setState(() { _scanning = false; _error = 'Failed to scan document.'; });
    }
  }

  Future<void> _captureFacePhoto() async {
    setState(() { _capturingFace = true; _faceError = null; });

    try {
      final result = await Process.run('osascript', [
        '-e',
        'set theFile to choose file of type {"public.jpeg", "public.png"} with prompt "Select a clear selfie photo (JPEG or PNG)"',
        '-e',
        'POSIX path of theFile',
      ]);
      final path = (result.stdout as String).trim();
      if (path.isEmpty) {
        if (mounted) setState(() => _capturingFace = false);
        return;
      }

      final file = File(path);
      if (!file.existsSync()) {
        if (mounted) setState(() { _capturingFace = false; _faceError = 'File not found.'; });
        return;
      }

      final bytes = file.readAsBytesSync();
      if (bytes.length > 2 * 1024 * 1024) {
        if (mounted) setState(() { _capturingFace = false; _faceError = 'Photo too large (max 2 MB).'; });
        return;
      }

      final ext = path.split('.').last.toLowerCase();
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      final dataUri = 'data:$mime;base64,${base64Encode(bytes)}';

      setState(() {
        _faceImageUri = dataUri;
        _faceEnrolled = true;
        _capturingFace = false;
        _faceError = null;
      });
      _updateHasData();
    } catch (e) {
      if (mounted) setState(() { _capturingFace = false; _faceError = 'Failed to capture photo.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                ),
                child: Icon(Icons.fingerprint_rounded, size: 28, color: scheme.primary),
              ),
              const SizedBox(height: 20),
              Text('Identity Verification', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'Upload a government ID and a selfie to verify your identity.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // ID Document Section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _idVerified
                      ? AppTheme.successColor.withValues(alpha: 0.4)
                      : scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _idVerified ? Icons.check_circle_rounded : Icons.badge_rounded,
                          size: 20,
                          color: _idVerified ? AppTheme.successColor : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Government ID',
                            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (_idVerified)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.successColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('Verified', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.successColor)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Any one: Aadhaar, PAN, Driving License, or Passport',
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                    ),

                    if (!_idVerified) ...[
                      const SizedBox(height: 16),
                      // Document type selector
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _documentTypes.map((type) {
                          final selected = _selectedDocType == type;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedDocType = type),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: selected ? scheme.primary.withValues(alpha: 0.1) : scheme.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4),
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _iconForDocType(type),
                                    size: 14,
                                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    type,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                                      color: selected ? scheme.primary : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),

                      // Upload hint
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 13, color: scheme.primary),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_uploadHint, style: TextStyle(fontSize: 10, color: scheme.primary))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Upload button
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: _scanning ? null : _uploadAndScanId,
                          icon: _scanning
                              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary))
                              : const Icon(Icons.upload_file_rounded, size: 18),
                          label: Text(_scanning ? 'Scanning...' : 'Upload & Verify', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: Text(
                          'Select multiple files for front + back. Accepts PDF, JPG, PNG.',
                          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        ),
                      ),
                    ],

                    // Verified result
                    if (_idVerified) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.successColor.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.check_circle_rounded, size: 14, color: AppTheme.successColor),
                                const SizedBox(width: 8),
                                Text(_selectedDocType, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.successColor)),
                              ],
                            ),
                            if (_extractedNumber != null && _extractedNumber!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text('Number: $_extractedNumber', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontFamily: 'Courier')),
                            ],
                            if (_extractedName != null && _extractedName!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text('Name: $_extractedName', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                            ],
                          ],
                        ),
                      ),
                    ],

                    // Error
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 14, color: scheme.error),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!, style: TextStyle(fontSize: 11, color: scheme.error))),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Face Enrollment Section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _faceEnrolled
                      ? AppTheme.successColor.withValues(alpha: 0.4)
                      : scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _faceEnrolled ? Icons.check_circle_rounded : Icons.face_rounded,
                          size: 20,
                          color: _faceEnrolled ? AppTheme.successColor : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Face Enrollment',
                            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (_faceEnrolled)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.successColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('Enrolled', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.successColor)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'A clear photo of your face for attendance and security.',
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                    ),

                    if (!_faceEnrolled) ...[
                      const SizedBox(height: 16),
                      // Face capture area
                      GestureDetector(
                        onTap: _capturingFace ? null : _captureFacePhoto,
                        child: Container(
                          width: double.infinity,
                          height: 140,
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4), style: BorderStyle.solid),
                          ),
                          child: _capturingFace
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary)),
                                      const SizedBox(height: 10),
                                      Text('Processing...', style: TextStyle(fontSize: 12, color: scheme.primary)),
                                    ],
                                  ),
                                )
                              : Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: scheme.primary.withValues(alpha: 0.08),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(Icons.camera_alt_rounded, size: 24, color: scheme.primary),
                                      ),
                                      const SizedBox(height: 10),
                                      Text('Tap to upload selfie', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.primary)),
                                      const SizedBox(height: 4),
                                      Text('Clear, front-facing, good lighting', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                    ],

                    // Enrolled result
                    if (_faceEnrolled && _faceImageUri != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.4), width: 2),
                              image: DecorationImage(
                                image: MemoryImage(base64Decode(_faceImageUri!.split(',').last)),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.check_circle_rounded, size: 14, color: AppTheme.successColor),
                                    const SizedBox(width: 6),
                                    Text('Face enrolled', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.successColor)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: () => setState(() { _faceEnrolled = false; _faceImageUri = null; _updateHasData(); }),
                                  child: Text('Retake photo', style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w500)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Face error
                    if (_faceError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 14, color: scheme.error),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_faceError!, style: TextStyle(fontSize: 11, color: scheme.error))),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForDocType(String type) => switch (type) {
    'Aadhaar' => Icons.credit_card_rounded,
    'PAN' => Icons.badge_rounded,
    'Driving License' => Icons.directions_car_rounded,
    'Passport' => Icons.flight_rounded,
    _ => Icons.description_rounded,
  };
}
