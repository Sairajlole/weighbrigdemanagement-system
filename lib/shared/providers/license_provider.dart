import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/models/license_model.dart';
import 'package:weighbridgemanagement/shared/providers/connectivity_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/services/device_fingerprint_service.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';

class LicenseNotifier extends StateNotifier<License> {
  final Ref _ref;

  LicenseNotifier(this._ref) : super(License.empty) {
    _init();
  }

  Future<void> _init() async {
    // Load from cache first
    final cached = await LocalCacheService.getCachedLicense();
    if (cached != null) {
      var license = License.fromMap(cached);
      if (license.tier == LicenseTier.trial &&
          license.status == LicenseStatus.active &&
          license.isExpired) {
        license = license.copyWith(status: LicenseStatus.expired);
        await LocalCacheService.cacheLicense(license.toMap());
      }
      state = license;
    }

    // If no cached license or it's empty, load from Firestore
    if (state.key.isEmpty) {
      try {
        final ctx = _ref.read(siteContextProvider);
        if (ctx.isConfigured) {
          await loadFromFirestore(ctx.companyId);
        }
      } catch (_) {}
    }

    // Try online validation if needed
    _checkAndValidate();
  }

  Future<void> _checkAndValidate() async {
    if (!state.needsRevalidation) return;

    final isOnline = _ref.read(connectivityProvider).valueOrNull ?? false;
    if (!isOnline) return;

    await validate();
  }

  Future<void> validate() async {
    if (state.key.isEmpty) return;

    try {
      final fingerprint = await DeviceFingerprintService.getFingerprint();
      final ctx = _ref.read(siteContextProvider);

      final result = await FirebaseFunctions.instance
          .httpsCallable('validateLicense')
          .call({
        'licenseKey': state.key,
        'companyId': ctx.companyId,
        'deviceFingerprint': fingerprint,
      });

      final data = result.data as Map<String, dynamic>;
      if (data['valid'] == true) {
        state = state.copyWith(
          status: LicenseStatus.active,
          tier: LicenseTier.values.firstWhere(
            (t) => t.name == data['tier'],
            orElse: () => LicenseTier.free,
          ),
          features: (data['features'] as List<dynamic>?)?.cast<String>(),
          maxWeighbridges: (data['maxWeighbridges'] as num?)?.toInt(),
          maxSites: (data['maxSites'] as num?)?.toInt(),
          lastValidatedAt: DateTime.now(),
          expiresAt: data['expiresAt'] != null
              ? DateTime.fromMillisecondsSinceEpoch(data['expiresAt'] as int)
              : null,
        );
      } else {
        state = state.copyWith(status: LicenseStatus.expired);
      }

      await LocalCacheService.cacheLicense(state.toMap());
    } catch (e) {
      debugPrint('License validation failed: $e');
    }
  }

  Future<bool> activate({
    required String licenseKey,
    required String gstin,
    required String companyId,
  }) async {
    try {
      final fingerprint = await DeviceFingerprintService.getFingerprint();

      final result = await FirebaseFunctions.instance
          .httpsCallable('activateLicense')
          .call({
        'licenseKey': licenseKey,
        'gstin': gstin,
        'companyId': companyId,
        'deviceFingerprint': fingerprint,
      });

      final data = result.data as Map<String, dynamic>;
      if (data['success'] == true) {
        state = License(
          key: licenseKey,
          tier: LicenseTier.values.firstWhere(
            (t) => t.name == data['tier'],
            orElse: () => LicenseTier.free,
          ),
          status: LicenseStatus.active,
          gstin: gstin,
          companyId: companyId,
          deviceFingerprint: fingerprint,
          activatedAt: DateTime.now(),
          expiresAt: data['expiresAt'] != null
              ? DateTime.fromMillisecondsSinceEpoch(data['expiresAt'] as int)
              : null,
          lastValidatedAt: DateTime.now(),
          maxWeighbridges: (data['maxWeighbridges'] as num?)?.toInt() ?? 1,
          maxSites: (data['maxSites'] as num?)?.toInt() ?? 1,
          features: (data['features'] as List<dynamic>?)?.cast<String>() ?? [],
        );
        await LocalCacheService.cacheLicense(state.toMap());
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('License activation failed: $e');
      return false;
    }
  }

  Future<bool> activateFree({required String gstin, required String companyId}) async {
    try {
      final fingerprint = await DeviceFingerprintService.getFingerprint();
      final db = _ref.read(firestoreProvider);

      // Register in GSTIN registry
      final normalizedGstin = gstin.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
      final registryRef = db.doc('gstin_registry/$normalizedGstin');
      final existing = await registryRef.get();

      if (existing.exists && existing.data()?['companyId'] != companyId) {
        return false; // GSTIN already registered to another company
      }

      await registryRef.set({
        'companyId': companyId,
        'deviceFingerprint': fingerprint,
        'hadTrial': false,
        'registeredAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Write license to company doc
      await db.doc('companies/$companyId').set({
        'license': {
          'currentLicenseKey': 'FREE_$normalizedGstin',
          'tier': 'free',
          'status': 'active',
          'features': <String>[],
          'maxWeighbridges': 1,
          'maxSites': 1,
          'lastValidatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      state = License(
        key: 'FREE_$normalizedGstin',
        tier: LicenseTier.free,
        status: LicenseStatus.active,
        gstin: gstin,
        companyId: companyId,
        deviceFingerprint: fingerprint,
        activatedAt: DateTime.now(),
        lastValidatedAt: DateTime.now(),
        maxWeighbridges: 1,
        maxSites: 1,
        features: [],
      );

      await LocalCacheService.cacheLicense(state.toMap());
      return true;
    } catch (e) {
      debugPrint('Free license activation failed: $e');
      return false;
    }
  }

  Future<bool> activateTrial({required String gstin, required String companyId}) async {
    try {
      final fingerprint = await DeviceFingerprintService.getFingerprint();
      final db = _ref.read(firestoreProvider);

      // Check if GSTIN already had a trial
      final normalizedGstin = gstin.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
      final registryRef = db.doc('gstin_registry/$normalizedGstin');
      final existing = await registryRef.get();

      if (existing.exists && existing.data()?['hadTrial'] == true) {
        final existingCompany = existing.data()?['companyId'] as String?;

        if (existingCompany != null && existingCompany != companyId) {
          // Check if the old company still exists — if deleted/recreated, allow
          final oldCompanyDoc = await db.doc('companies/$existingCompany').get();
          if (oldCompanyDoc.exists) {
            return false; // GSTIN genuinely registered to another active company
          }
          // Old company gone — update registry to point to current company and fall through to fresh trial
          await registryRef.update({'companyId': companyId, 'deviceFingerprint': fingerprint});
        } else {
          // Same company re-activating
          final companyDoc = await db.doc('companies/$companyId').get();
          final licData = companyDoc.data()?['license'] as Map<String, dynamic>?;
          if (licData != null) {
            final expiresTs = licData['expiresAt'] as Timestamp?;
            if (expiresTs != null && expiresTs.toDate().isBefore(DateTime.now())) {
              // Trial expired — downgrade to free so user can still complete setup
              await activateFree(gstin: gstin, companyId: companyId);
              return true;
            }
            // Trial still active — reload existing license state
            await loadFromFirestore(companyId);
            return true;
          }
          // Company exists but no license data yet — fall through to fresh trial activation
        }
      }

      final expiresAt = DateTime.now().add(const Duration(days: 30));

      await registryRef.set({
        'companyId': companyId,
        'deviceFingerprint': fingerprint,
        'hadTrial': true,
        'registeredAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await db.doc('companies/$companyId').set({
        'license': {
          'currentLicenseKey': 'TRIAL_$normalizedGstin',
          'tier': 'trial',
          'status': 'active',
          'features': proFeatures,
          'maxWeighbridges': 2,
          'maxSites': 1,
          'expiresAt': Timestamp.fromDate(expiresAt),
          'trialStartedAt': FieldValue.serverTimestamp(),
          'lastValidatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      state = License(
        key: 'TRIAL_$normalizedGstin',
        tier: LicenseTier.trial,
        status: LicenseStatus.active,
        gstin: gstin,
        companyId: companyId,
        deviceFingerprint: fingerprint,
        activatedAt: DateTime.now(),
        expiresAt: expiresAt,
        trialStartedAt: DateTime.now(),
        lastValidatedAt: DateTime.now(),
        maxWeighbridges: 2,
        maxSites: 1,
        features: proFeatures,
      );

      await LocalCacheService.cacheLicense(state.toMap());
      return true;
    } catch (e) {
      debugPrint('Trial activation failed: $e');
      return false;
    }
  }

  Future<void> loadFromFirestore(String companyId) async {
    try {
      final db = _ref.read(firestoreProvider);
      final doc = await db.doc('companies/$companyId').get();
      final companyData = doc.data();
      final licenseData = companyData?['license'] as Map<String, dynamic>?;
      if (licenseData == null) return;

      final gstin = companyData?['gstin'] as String? ?? licenseData['gstin'] as String?;

      state = License(
        key: licenseData['currentLicenseKey'] as String? ?? '',
        tier: LicenseTier.values.firstWhere(
          (t) => t.name == licenseData['tier'],
          orElse: () => LicenseTier.free,
        ),
        status: LicenseStatus.values.firstWhere(
          (s) => s.name == (licenseData['status'] as String? ?? 'active'),
          orElse: () => LicenseStatus.active,
        ),
        gstin: gstin,
        companyId: companyId,
        expiresAt: licenseData['expiresAt'] != null
            ? (licenseData['expiresAt'] as Timestamp).toDate()
            : null,
        trialStartedAt: licenseData['trialStartedAt'] != null
            ? (licenseData['trialStartedAt'] as Timestamp).toDate()
            : null,
        lastValidatedAt: licenseData['lastValidatedAt'] != null
            ? (licenseData['lastValidatedAt'] as Timestamp).toDate()
            : null,
        maxWeighbridges: (licenseData['maxWeighbridges'] as num?)?.toInt() ?? 1,
        maxSites: (licenseData['maxSites'] as num?)?.toInt() ?? 1,
        features: (licenseData['features'] as List<dynamic>?)?.cast<String>() ?? [],
      );

      await LocalCacheService.cacheLicense(state.toMap());
    } catch (e) {
      debugPrint('License load from Firestore failed: $e');
    }
  }

  void clear() {
    state = License.empty;
    LocalCacheService.clearLicense();
  }
}

final licenseProvider = StateNotifierProvider<LicenseNotifier, License>((ref) {
  return LicenseNotifier(ref);
});

// Convenience providers — use effectiveTier so expired trials degrade to free
final isFreeProvider = Provider<bool>((ref) => ref.watch(licenseProvider).effectivelyFree);
final isProProvider = Provider<bool>((ref) => ref.watch(licenseProvider).effectivelyPro);
final hasFeatureProvider = Provider.family<bool, String>((ref, feature) {
  return ref.watch(licenseProvider).hasFeature(feature);
});
final licenseTierProvider = Provider<LicenseTier>((ref) => ref.watch(licenseProvider).effectiveTier);

final canAddWeighbridgeProvider = Provider.family<bool, int>((ref, currentCount) {
  final license = ref.watch(licenseProvider);
  if (license.effectivelyFree) return currentCount < 1;
  if (license.maxWeighbridges == -1) return true;
  return currentCount < license.maxWeighbridges;
});

final canAddSiteProvider = Provider.family<bool, int>((ref, currentCount) {
  final license = ref.watch(licenseProvider);
  if (license.effectivelyFree) return currentCount < 1;
  if (license.maxSites == -1) return true;
  return currentCount < license.maxSites;
});
