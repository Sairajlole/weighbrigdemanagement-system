import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/crypto_service.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';
import 'package:weighbridgemanagement/shared/services/platform_service.dart';

// ─── Security Settings Model ─────────────────────────────────────────────────

class SecuritySettings {
  // Operator permissions
  final bool opCanVoidWeighment;
  final bool opCanEditWeighment;
  final bool opCanManualWeight;
  final bool opCanReprint;
  final bool opCanExportData;
  final bool opCanViewReports;
  final bool opCanViewCctv;
  final bool opCanChangeSettings;
  final bool opCanManageCustomers;
  final bool opCanManageMaterials;
  final bool opCanDeleteRecords;
  final bool opCanAccessPrinting;
  final bool opCanAccessGateControl;
  final bool opCanAccessCameras;
  final bool opCanAccessWeighbridge;

  // KYC enforcement
  final bool requireKycForSensitiveOps;

  // Audit
  final bool auditEnabled;
  final bool auditLogSettingChanges;
  final bool auditLogWeighmentEdits;
  final bool auditLogReprints;
  final bool auditLogLogins;
  final bool auditLogExports;

  // Data security
  final bool autoLockEnabled;
  final int autoLockMinutes;
  final bool maskSensitiveFields;
  final bool encryptBackups;

  // Operator verification
  final bool faceVerifyOnWeighmentStart;
  final bool faceVerifyOnSessionStart;
  final bool faceVerifyOnDayStart;
  final bool shiftBasedLogin;
  final bool forcePasswordChangeFirstLogin;
  final int passwordExpiryDays;

  // Session
  final bool emergencyLockdown;
  final bool autoLogoutEnabled;
  final int autoLogoutMinutes;
  final bool restrictUsb;
  final bool blockRemoteDesktop;

  // Privacy / Archival
  final bool anonymizeVehicleOnArchive;

  // Screen protection
  final bool preventScreenshots;
  final bool dimOnInactiveWindow;
  final bool watermarkEnabled;

  // IP whitelist
  final bool ipWhitelistEnabled;
  final List<String> whitelistedIps;

  const SecuritySettings({
    this.opCanVoidWeighment = false,
    this.opCanEditWeighment = false,
    this.opCanManualWeight = false,
    this.opCanReprint = true,
    this.opCanExportData = false,
    this.opCanViewReports = true,
    this.opCanViewCctv = false,
    this.opCanChangeSettings = false,
    this.opCanManageCustomers = false,
    this.opCanManageMaterials = false,
    this.opCanDeleteRecords = false,
    this.opCanAccessPrinting = false,
    this.opCanAccessGateControl = false,
    this.opCanAccessCameras = false,
    this.opCanAccessWeighbridge = false,
    this.requireKycForSensitiveOps = false,
    this.auditEnabled = true,
    this.auditLogSettingChanges = true,
    this.auditLogWeighmentEdits = true,
    this.auditLogReprints = true,
    this.auditLogLogins = true,
    this.auditLogExports = true,
    this.autoLockEnabled = true,
    this.autoLockMinutes = 5,
    this.maskSensitiveFields = true,
    this.encryptBackups = false,
    this.faceVerifyOnWeighmentStart = false,
    this.faceVerifyOnSessionStart = false,
    this.faceVerifyOnDayStart = false,
    this.shiftBasedLogin = false,
    this.forcePasswordChangeFirstLogin = true,
    this.passwordExpiryDays = 0,
    this.emergencyLockdown = false,
    this.autoLogoutEnabled = false,
    this.autoLogoutMinutes = 30,
    this.restrictUsb = false,
    this.blockRemoteDesktop = false,
    this.anonymizeVehicleOnArchive = false,
    this.preventScreenshots = false,
    this.dimOnInactiveWindow = false,
    this.watermarkEnabled = false,
    this.ipWhitelistEnabled = false,
    this.whitelistedIps = const [],
  });

  factory SecuritySettings.fromMap(Map<String, dynamic> data) {
    return SecuritySettings(
      opCanVoidWeighment: data['opCanVoidWeighment'] as bool? ?? false,
      opCanEditWeighment: data['opCanEditWeighment'] as bool? ?? false,
      opCanManualWeight: data['opCanManualWeight'] as bool? ?? false,
      opCanReprint: data['opCanReprint'] as bool? ?? true,
      opCanExportData: data['opCanExportData'] as bool? ?? false,
      opCanViewReports: data['opCanViewReports'] as bool? ?? true,
      opCanViewCctv: data['opCanViewCctv'] as bool? ?? false,
      opCanChangeSettings: data['opCanChangeSettings'] as bool? ?? false,
      opCanManageCustomers: data['opCanManageCustomers'] as bool? ?? false,
      opCanManageMaterials: data['opCanManageMaterials'] as bool? ?? false,
      opCanDeleteRecords: data['opCanDeleteRecords'] as bool? ?? false,
      opCanAccessPrinting: data['opCanAccessPrinting'] as bool? ?? false,
      opCanAccessGateControl: data['opCanAccessGateControl'] as bool? ?? false,
      opCanAccessCameras: data['opCanAccessCameras'] as bool? ?? false,
      opCanAccessWeighbridge: data['opCanAccessWeighbridge'] as bool? ?? false,
      requireKycForSensitiveOps: data['requireKycForSensitiveOps'] as bool? ?? false,
      auditEnabled: data['auditEnabled'] as bool? ?? true,
      auditLogSettingChanges: data['auditLogSettingChanges'] as bool? ?? true,
      auditLogWeighmentEdits: data['auditLogWeighmentEdits'] as bool? ?? true,
      auditLogReprints: data['auditLogReprints'] as bool? ?? true,
      auditLogLogins: data['auditLogLogins'] as bool? ?? true,
      auditLogExports: data['auditLogExports'] as bool? ?? true,
      autoLockEnabled: data['autoLockEnabled'] as bool? ?? true,
      autoLockMinutes: data['autoLockMinutes'] as int? ?? 5,
      maskSensitiveFields: data['maskSensitiveFields'] as bool? ?? true,
      encryptBackups: data['encryptBackups'] as bool? ?? false,
      faceVerifyOnWeighmentStart: data['faceVerifyOnWeighmentStart'] as bool? ?? data['requireFaceVerification'] as bool? ?? false,
      faceVerifyOnSessionStart: data['faceVerifyOnSessionStart'] as bool? ?? false,
      faceVerifyOnDayStart: data['faceVerifyOnDayStart'] as bool? ?? false,
      shiftBasedLogin: data['shiftBasedLogin'] as bool? ?? false,
      forcePasswordChangeFirstLogin: data['forcePasswordChangeFirstLogin'] as bool? ?? true,
      passwordExpiryDays: data['passwordExpiryDays'] as int? ?? 0,
      emergencyLockdown: data['emergencyLockdown'] as bool? ?? false,
      autoLogoutEnabled: data['autoLogoutEnabled'] as bool? ?? false,
      autoLogoutMinutes: data['autoLogoutMinutes'] as int? ?? 30,
      restrictUsb: data['restrictUsb'] as bool? ?? false,
      blockRemoteDesktop: data['blockRemoteDesktop'] as bool? ?? false,
      anonymizeVehicleOnArchive: data['anonymizeVehicleOnArchive'] as bool? ?? false,
      preventScreenshots: data['preventScreenshots'] as bool? ?? false,
      dimOnInactiveWindow: data['dimOnInactiveWindow'] as bool? ?? false,
      watermarkEnabled: data['watermarkEnabled'] as bool? ?? false,
      ipWhitelistEnabled: data['ipWhitelistEnabled'] as bool? ?? false,
      whitelistedIps: (data['whitelistedIps'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

// ─── Providers ───────────────────────────────────────────────────────────────

final securitySettingsOverrideProvider = StateProvider<SecuritySettings?>((ref) => null);
final securityRefreshProvider = StateProvider<int>((ref) => 0);

final securitySettingsProvider = FutureProvider<SecuritySettings>((ref) async {
  final override = ref.watch(securitySettingsOverrideProvider);
  if (override != null) return override;
  ref.watch(securityRefreshProvider);
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const SecuritySettings();
  try {
    final snap = await paths.securitySettings.get(const GetOptions(source: Source.cache));
    if (snap.exists) return SecuritySettings.fromMap(snap.data()!);
  } catch (_) {}
  try {
    final snap = await paths.securitySettings.get();
    if (snap.exists) return SecuritySettings.fromMap(snap.data()!);
  } catch (_) {}
  return const SecuritySettings();
});

final currentUserRoleProvider = FutureProvider<String>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  final user = FirebaseAuth.instance.currentUser;
  final email = user?.email ?? await LocalCacheService.getCachedCurrentUserEmail();
  if (email == null || email.isEmpty) return Platform.isMacOS ? 'admin' : 'operator';
  if (!paths.isConfigured) return 'admin';
  try {
    final doc = await paths.operators.where('email', isEqualTo: email).limit(1).get();
    if (doc.docs.isNotEmpty) {
      final role = doc.docs.first.data()['role'] as String? ?? 'operator';
      return (role == 'companyAdmin' || role == 'admin') ? 'admin' : role;
    }
  } catch (_) {}
  return 'admin';
});

final isAdminProvider = Provider<bool>((ref) {
  final role = ref.watch(currentUserRoleProvider);
  return role.valueOrNull == 'admin';
});

// ─── KYC Status Provider ────────────────────────────────────────────────────

final currentOperatorKycProvider = FutureProvider<bool>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return true;
  if (!paths.isConfigured) return true;
  try {
    final snap = await paths.operators.where('email', isEqualTo: user.email).limit(1).get();
    if (snap.docs.isEmpty) return true; // admin (not in operators collection)
    return snap.docs.first.data()['idStatus'] == 'verified';
  } catch (_) {}
  return false;
});

// ─── Operator Active Status ─────────────────────────────────────────────────

final currentOperatorActiveProvider = FutureProvider<bool>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  final user = FirebaseAuth.instance.currentUser;
  final email = user?.email ?? await LocalCacheService.getCachedCurrentUserEmail();
  if (email == null || email.isEmpty) return true;
  if (!paths.isConfigured) return true;
  try {
    final snap = await paths.operators.where('email', isEqualTo: email).limit(1).get();
    if (snap.docs.isEmpty) return true;
    return snap.docs.first.data()['isActive'] as bool? ?? true;
  } catch (_) {}
  return true;
});

// ─── Current Operator Name ──────────────────────────────────────────────────

/// Invalidate this to force re-fetch of operator identity after a switch.
final operatorIdentityRefreshProvider = StateProvider<int>((ref) => 0);

final currentOperatorNameProvider = Provider<String>((ref) {
  ref.watch(operatorIdentityRefreshProvider);
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return '';
  return ref.watch(_operatorNameFutureProvider).valueOrNull ?? '';
});

final _operatorNameFutureProvider = FutureProvider<String>((ref) async {
  ref.watch(operatorIdentityRefreshProvider);
  final paths = ref.watch(firestorePathsProvider);
  final user = FirebaseAuth.instance.currentUser;
  final email = user?.email ?? await LocalCacheService.getCachedCurrentUserEmail();
  if (email == null || email.isEmpty) return '';
  if (!paths.isConfigured) return '';
  try {
    final snap = await paths.operators.where('email', isEqualTo: email).limit(1).get();
    if (snap.docs.isNotEmpty) {
      return snap.docs.first.data()['name'] as String? ?? '';
    }
  } catch (_) {}
  return user?.displayName ?? email;
});

final currentOperatorProfilePicProvider = FutureProvider<String>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  final user = FirebaseAuth.instance.currentUser;
  final email = user?.email ?? await LocalCacheService.getCachedCurrentUserEmail();
  if (email == null || email.isEmpty) return '';
  if (!paths.isConfigured) return '';
  try {
    final snap = await paths.operators.where('email', isEqualTo: email).limit(1).get();
    if (snap.docs.isNotEmpty) {
      return snap.docs.first.data()['profilePic'] as String? ?? '';
    }
  } catch (_) {}
  return '';
});

// ─── Per-Operator Permissions ───────────────────────────────────────────────

class OperatorPermissions {
  final bool canViewCustomers;
  final bool canViewWeighments;
  final bool canViewReports;
  final bool ownWeighmentsOnly;

  const OperatorPermissions({
    this.canViewCustomers = true,
    this.canViewWeighments = true,
    this.canViewReports = true,
    this.ownWeighmentsOnly = false,
  });

  factory OperatorPermissions.fromMap(Map<String, dynamic> data) {
    return OperatorPermissions(
      canViewCustomers: data['canViewCustomers'] as bool? ?? true,
      canViewWeighments: data['canViewWeighments'] as bool? ?? true,
      canViewReports: data['canViewReports'] as bool? ?? true,
      ownWeighmentsOnly: data['ownWeighmentsOnly'] as bool? ?? false,
    );
  }
}

final currentOperatorPermissionsProvider = FutureProvider<OperatorPermissions>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  final user = FirebaseAuth.instance.currentUser;
  final email = user?.email ?? await LocalCacheService.getCachedCurrentUserEmail();
  if (email == null || email.isEmpty) return const OperatorPermissions();
  if (!paths.isConfigured) return const OperatorPermissions();
  try {
    final snap = await paths.operators.where('email', isEqualTo: email).limit(1).get();
    if (snap.docs.isEmpty) return const OperatorPermissions();
    return OperatorPermissions.fromMap(snap.docs.first.data());
  } catch (_) {}
  return const OperatorPermissions();
});

// ─── Permission Check Service ────────────────────────────────────────────────

final permissionServiceProvider = Provider<PermissionService>((ref) {
  final settings = ref.watch(securitySettingsProvider).valueOrNull ?? const SecuritySettings();
  final isAdmin = ref.watch(isAdminProvider);
  final kycVerified = ref.watch(currentOperatorKycProvider).valueOrNull ?? true;
  final isActive = ref.watch(currentOperatorActiveProvider).valueOrNull ?? true;
  final opPerms = ref.watch(currentOperatorPermissionsProvider).valueOrNull ?? const OperatorPermissions();
  return PermissionService(settings: settings, isAdmin: isAdmin, kycVerified: kycVerified, isDeactivated: !isAdmin && !isActive, opPerms: opPerms);
});

class PermissionService {
  final SecuritySettings settings;
  final bool isAdmin;
  final bool kycVerified;
  final bool isDeactivated;
  final OperatorPermissions opPerms;

  const PermissionService({required this.settings, required this.isAdmin, required this.kycVerified, this.isDeactivated = false, this.opPerms = const OperatorPermissions()});

  bool get _kycOk => isAdmin || !settings.requireKycForSensitiveOps || kycVerified;

  // KYC-gated (sensitive operations)
  bool get canVoidWeighment => (isAdmin || settings.opCanVoidWeighment) && _kycOk;
  bool get canEditWeighment => (isAdmin || settings.opCanEditWeighment) && _kycOk;
  bool get canManualWeight => (isAdmin || settings.opCanManualWeight) && _kycOk;
  bool get canExportData => (isAdmin || settings.opCanExportData) && _kycOk;
  bool get canDeleteRecords => (isAdmin || settings.opCanDeleteRecords) && _kycOk;

  // Not KYC-gated
  bool get canReprint => isAdmin || settings.opCanReprint;
  bool get canViewReports => isAdmin || (settings.opCanViewReports && opPerms.canViewReports);
  bool get canViewCctv => isAdmin || settings.opCanViewCctv;
  bool get canAccessSettings => isAdmin || settings.opCanChangeSettings;
  bool get canManageCustomers => isAdmin || (settings.opCanManageCustomers && opPerms.canViewCustomers);
  bool get canManageMaterials => isAdmin || settings.opCanManageMaterials;
  bool get canAccessPrinting => isAdmin || settings.opCanAccessPrinting;
  bool get canAccessGateControl => isAdmin || settings.opCanAccessGateControl;
  bool get canAccessCameras => isAdmin || settings.opCanAccessCameras;
  bool get canAccessWeighbridge => isAdmin || settings.opCanAccessWeighbridge;

  // Per-operator screen visibility
  bool get canViewWeighments => isAdmin || opPerms.canViewWeighments;
  bool get ownWeighmentsOnly => !isAdmin && opPerms.ownWeighmentsOnly;

  bool get isLockdown => settings.emergencyLockdown && !isAdmin;
  bool get shouldMaskSensitive => !isAdmin && settings.maskSensitiveFields;
}

// ─── Audit Log Service ───────────────────────────────────────────────────────

final auditServiceProvider = Provider<AuditService>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  final settings = ref.watch(securitySettingsProvider).valueOrNull ?? const SecuritySettings();
  return AuditService(paths: paths, settings: settings);
});

class AuditService {
  final FirestorePaths paths;
  final SecuritySettings settings;

  const AuditService({required this.paths, required this.settings});

  Future<void> log({
    required String event,
    required String description,
    String? user,
    Map<String, dynamic>? metadata,
  }) async {
    if (!settings.auditEnabled) return;
    if (!paths.isConfigured) return;

    if (event == 'settingChange' && !settings.auditLogSettingChanges) return;
    if (event == 'weighmentEdit' && !settings.auditLogWeighmentEdits) return;
    if (event == 'reprint' && !settings.auditLogReprints) return;
    if (event == 'login' && !settings.auditLogLogins) return;
    if (event == 'export' && !settings.auditLogExports) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    final hostname = Platform.localHostname;

    try {
      await paths.auditLog.add({
        'event': event,
        'description': description,
        'user': user ?? currentUser?.email ?? 'unknown',
        'machine': hostname,
        'ip': await _getLocalIp(),
        'timestamp': FieldValue.serverTimestamp(),
        'success': true,
        ...?metadata,
      });
    } catch (_) {
      // Swallow network errors — Firestore offline persistence will queue it
    }
  }

  Future<void> logLogin({required bool success, String? email}) async {
    if (!settings.auditEnabled || !settings.auditLogLogins) return;
    if (!paths.isConfigured) return;

    final hostname = Platform.localHostname;
    try {
      await paths.auditLog.add({
        'event': 'login',
        'description': success ? 'Successful login' : 'Failed login attempt',
        'user': email ?? FirebaseAuth.instance.currentUser?.email ?? 'unknown',
        'machine': hostname,
        'ip': await _getLocalIp(),
        'timestamp': FieldValue.serverTimestamp(),
        'success': success,
      });
    } catch (_) {}
  }

  Future<String> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }
}

// ─── Screen Protection Service ───────────────────────────────────────────────

final screenProtectionProvider = Provider<ScreenProtectionService>((ref) {
  final settings = ref.watch(securitySettingsProvider).valueOrNull ?? const SecuritySettings();
  return ScreenProtectionService(settings: settings);
});

class ScreenProtectionService {
  final SecuritySettings settings;

  const ScreenProtectionService({required this.settings});

  bool get shouldPreventScreenshots => settings.preventScreenshots;
  bool get shouldDimOnInactive => settings.dimOnInactiveWindow;
  bool get shouldShowWatermark => settings.watermarkEnabled;
}

// ─── Remote Desktop Detection Service ────────────────────────────────────────

final remoteDesktopMonitorProvider = Provider<RemoteDesktopMonitor>((ref) {
  final settings = ref.watch(securitySettingsProvider).valueOrNull ?? const SecuritySettings();
  return RemoteDesktopMonitor(enabled: settings.blockRemoteDesktop);
});

class RemoteDesktopMonitor {
  final bool enabled;

  const RemoteDesktopMonitor({required this.enabled});

  static const _blockedProcesses = [
    'AnyDesk',
    'anydesk',
    'AnyDeskHelper',
    'TeamViewer',
    'TeamViewer_Service',
    'teamviewerd',
    'TeamViewerDesktop',
    'Chrome Remote Desktop',
    'remoting_host',
    'chromoting',
    'rustdesk',
    'RustDesk',
    'Splashtop',
    'SplashtopStreamer',
    'VNC',
    'screensharingd',
    'ScreensharingAgent',
    'ultraviewer',
    'UltraViewer',
  ];

  Future<bool> isRemoteDesktopRunning() async {
    if (!enabled) return false;
    final apps = await getRunningRemoteApps();
    return apps.isNotEmpty;
  }

  Future<List<String>> getRunningRemoteApps() async {
    if (!enabled) return [];
    final found = <String>{};
    try {
      if (Platform.isMacOS) {
        // Use pgrep for more reliable process detection on macOS
        for (final proc in _blockedProcesses) {
          final result = await Process.run('pgrep', ['-fi', proc]);
          if (result.exitCode == 0 && (result.stdout as String).trim().isNotEmpty) {
            found.add(proc);
          }
        }
      } else if (Platform.isWindows) {
        final result = await Process.run('tasklist', ['/FO', 'CSV', '/NH']);
        if (result.exitCode == 0) {
          final output = (result.stdout as String).toLowerCase();
          for (final proc in _blockedProcesses) {
            if (output.contains(proc.toLowerCase())) found.add(proc);
          }
        }
      } else {
        final result = await Process.run('ps', ['aux']);
        if (result.exitCode == 0) {
          final output = result.stdout as String;
          for (final proc in _blockedProcesses) {
            if (output.contains(proc)) found.add(proc);
          }
        }
      }
    } catch (_) {}
    return found.toList();
  }

  Future<void> killRemoteApps() async {
    if (!enabled) return;
    try {
      for (final proc in _blockedProcesses) {
        await PlatformService.killProcess(proc);
      }
    } catch (_) {}
  }
}

// ─── Inactivity Timer Service ────────────────────────────────────────────────

class InactivityService {
  Timer? _lockTimer;
  Timer? _logoutTimer;
  final void Function()? onLock;
  final void Function()? onLogout;
  final SecuritySettings settings;

  InactivityService({required this.settings, this.onLock, this.onLogout});

  void resetTimers() {
    _lockTimer?.cancel();
    _logoutTimer?.cancel();

    if (settings.autoLockEnabled) {
      _lockTimer = Timer(Duration(minutes: settings.autoLockMinutes), () {
        onLock?.call();
      });
    }

    if (settings.autoLogoutEnabled) {
      _logoutTimer = Timer(Duration(minutes: settings.autoLogoutMinutes), () {
        onLogout?.call();
      });
    }
  }

  void dispose() {
    _lockTimer?.cancel();
    _logoutTimer?.cancel();
  }
}

// ─── USB Monitor Service ────────────────────────────────────────────────────

final usbMonitorProvider = Provider<UsbMonitorService>((ref) {
  final settings = ref.watch(securitySettingsProvider).valueOrNull ?? const SecuritySettings();
  return UsbMonitorService(enabled: settings.restrictUsb);
});

class UsbMonitorService {
  final bool enabled;

  const UsbMonitorService({required this.enabled});

  Future<List<String>> getExternalVolumes() async {
    if (!enabled) return [];
    if (!Platform.isMacOS) return []; // diskutil is macOS-only
    try {
      final result = await Process.run('diskutil', ['list', 'external']);
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final volumes = <String>[];
        final regex = RegExp(r'/dev/(disk\d+)');
        for (final match in regex.allMatches(output)) {
          final diskId = match.group(1);
          if (diskId != null) {
            final infoResult = await Process.run('diskutil', ['info', diskId]);
            if (infoResult.exitCode == 0) {
              final info = infoResult.stdout as String;
              final mountMatch = RegExp(r'Mount Point:\s+(.+)').firstMatch(info);
              if (mountMatch != null) {
                final mountPoint = mountMatch.group(1)?.trim();
                if (mountPoint != null && mountPoint.isNotEmpty && mountPoint != '/') {
                  volumes.add(mountPoint);
                }
              }
            }
          }
        }
        return volumes;
      }
    } catch (_) {}
    return [];
  }

  Future<void> ejectAll() async {
    if (!enabled) return;
    if (!Platform.isMacOS) return; // diskutil is macOS-only
    try {
      final result = await Process.run('diskutil', ['list', 'external']);
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final regex = RegExp(r'/dev/(disk\d+)');
        for (final match in regex.allMatches(output)) {
          final diskId = match.group(1);
          if (diskId != null) {
            await Process.run('diskutil', ['eject', '/dev/$diskId']);
          }
        }
      }
    } catch (_) {}
  }

  Future<bool> hasExternalStorage() async {
    if (!enabled) return false;
    final volumes = await getExternalVolumes();
    return volumes.isNotEmpty;
  }
}

// ─── Shift Validation Service ───────────────────────────────────────────────

class ShiftValidationResult {
  final bool allowed;
  final String? message;
  const ShiftValidationResult({required this.allowed, this.message});
}

Future<ShiftValidationResult> validateShiftLogin(FirestorePaths paths, String email, SecuritySettings settings) async {
  if (!settings.shiftBasedLogin) return const ShiftValidationResult(allowed: true);

  try {
    final snap = await paths.operators.where('email', isEqualTo: email).limit(1).get();
    if (snap.docs.isEmpty) return const ShiftValidationResult(allowed: true); // admin
    final data = snap.docs.first.data();

    if (data['shiftRestricted'] != true) return const ShiftValidationResult(allowed: true);

    final shiftStart = data['shiftStart'] as String?;
    final shiftEnd = data['shiftEnd'] as String?;
    final shiftDays = (data['shiftDays'] as List<dynamic>?)?.map((e) => e.toString()).toList();

    if (shiftStart == null || shiftEnd == null || shiftDays == null || shiftDays.isEmpty) {
      return const ShiftValidationResult(allowed: true);
    }

    final now = DateTime.now();
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final today = dayNames[now.weekday - 1];

    if (!shiftDays.contains(today)) {
      return ShiftValidationResult(allowed: false, message: 'Your shift is not scheduled for $today. Shift days: ${shiftDays.join(", ")}');
    }

    final startParts = shiftStart.split(':');
    final endParts = shiftEnd.split(':');
    final startMinutes = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
    final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
    final nowMinutes = now.hour * 60 + now.minute;

    if (nowMinutes < startMinutes || nowMinutes > endMinutes) {
      return ShiftValidationResult(allowed: false, message: 'Outside your shift hours ($shiftStart – $shiftEnd). Current time: ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}');
    }
  } catch (e) {
    // Deny access on validation failure — fail closed
    return ShiftValidationResult(allowed: false, message: 'Shift validation error: $e');
  }
  return const ShiftValidationResult(allowed: true);
}

// ─── Password Expiry Check ──────────────────────────────────────────────────

class PasswordCheckResult {
  final bool mustChange;
  final String? reason;
  const PasswordCheckResult({required this.mustChange, this.reason});
}

Future<PasswordCheckResult> checkPasswordStatus(FirestorePaths paths, String email, SecuritySettings settings) async {
  try {
    final snap = await paths.operators.where('email', isEqualTo: email).limit(1).get();
    if (snap.docs.isEmpty) return const PasswordCheckResult(mustChange: false); // admin

    final data = snap.docs.first.data();

    if (data['mustChangePassword'] == true) {
      return const PasswordCheckResult(mustChange: true, reason: 'You must change your password before continuing.');
    }

    if (settings.passwordExpiryDays > 0) {
      final lastChanged = data['passwordLastChanged'];
      if (lastChanged == null) {
        return const PasswordCheckResult(mustChange: true, reason: 'Password has never been set. Please change it now.');
      }
      DateTime lastDate;
      if (lastChanged is Timestamp) {
        lastDate = lastChanged.toDate();
      } else {
        return const PasswordCheckResult(mustChange: false);
      }
      final daysSince = DateTime.now().difference(lastDate).inDays;
      if (daysSince >= settings.passwordExpiryDays) {
        return PasswordCheckResult(mustChange: true, reason: 'Your password expired $daysSince days ago (policy: every ${settings.passwordExpiryDays} days).');
      }
    }
  } catch (e) {
    // Fail closed: require change if we can't verify
    return PasswordCheckResult(mustChange: true, reason: 'Unable to verify password status: $e');
  }
  return const PasswordCheckResult(mustChange: false);
}

// ─── IP Whitelist Check ─────────────────────────────────────────────────────

Future<String?> getPublicIp() async {
  final services = [
    'https://api.ipify.org',
    'https://ifconfig.me/ip',
    'https://icanhazip.com',
  ];
  for (final url in services) {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode == 200) {
        final ip = await response.transform(utf8.decoder).join();
        final trimmed = ip.trim();
        if (trimmed.isNotEmpty && RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(trimmed)) {
          client.close();
          return trimmed;
        }
      }
      client.close();
    } catch (_) {}
  }
  return null;
}

Future<List<String>> getLocalIps() async {
  final ips = <String>[];
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final iface in interfaces) {
      // Only include real network interfaces (en0/en1 on macOS, eth/wlan on Linux)
      final name = iface.name.toLowerCase();
      if (name.startsWith('en') || name.startsWith('eth') || name.startsWith('wlan') || name.startsWith('wi')) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) ips.add(addr.address);
        }
      }
    }
    // Fallback: if filtering excluded everything, take the first non-loopback
    if (ips.isEmpty) {
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) { ips.add(addr.address); return ips; }
        }
      }
    }
  } catch (_) {}
  return ips;
}

bool ipMatchesEntry(String ip, String entry) {
  // Exact match
  if (ip == entry) return true;

  // CIDR match (e.g. 192.168.1.0/24)
  if (entry.contains('/')) {
    final parts = entry.split('/');
    if (parts.length != 2) return false;
    final prefix = parts[0];
    final bits = int.tryParse(parts[1]);
    if (bits == null || bits < 0 || bits > 32) return false;
    final ipInt = _ipToInt(ip);
    final prefixInt = _ipToInt(prefix);
    if (ipInt == null || prefixInt == null) return false;
    final mask = bits == 0 ? 0 : (~0 << (32 - bits)) & 0xFFFFFFFF;
    return (ipInt & mask) == (prefixInt & mask);
  }

  // Range match (e.g. 192.168.1.10-192.168.1.50)
  if (entry.contains('-')) {
    final parts = entry.split('-');
    if (parts.length != 2) return false;
    final startInt = _ipToInt(parts[0].trim());
    final endInt = _ipToInt(parts[1].trim());
    final ipInt = _ipToInt(ip);
    if (startInt == null || endInt == null || ipInt == null) return false;
    return ipInt >= startInt && ipInt <= endInt;
  }

  // Wildcard match (e.g. 192.168.1.*)
  if (entry.contains('*')) {
    final pattern = entry.replaceAll('.', r'\.').replaceAll('*', r'\d{1,3}');
    return RegExp('^$pattern\$').hasMatch(ip);
  }

  return false;
}

int? _ipToInt(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return null;
  int result = 0;
  for (final p in parts) {
    final octet = int.tryParse(p);
    if (octet == null || octet < 0 || octet > 255) return null;
    result = (result << 8) | octet;
  }
  return result;
}

Future<bool> isIpAllowed(SecuritySettings settings) async {
  if (!settings.ipWhitelistEnabled || settings.whitelistedIps.isEmpty) return true;
  try {
    final localIps = await getLocalIps();
    for (final ip in localIps) {
      for (final entry in settings.whitelistedIps) {
        if (ipMatchesEntry(ip, entry)) return true;
      }
    }
  } catch (_) {
    return false;
  }
  return false;
}

// ─── Local cache for offline ─────────────────────────────────────────────────

String get _localCachePath {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  final dir = Directory('$home/.weighbridge');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return '${dir.path}/security_cache.json';
}

Future<SecuritySettings> loadSecuritySettingsLocally() async {
  try {
    final file = File(_localCachePath);
    if (await file.exists()) {
      final content = await file.readAsString();
      final decrypted = CryptoService.decrypt(content);
      final data = jsonDecode(decrypted) as Map<String, dynamic>;
      return SecuritySettings.fromMap(data);
    }
  } catch (_) {}
  return const SecuritySettings();
}

Future<void> cacheSecuritySettings(Map<String, dynamic> data) async {
  try {
    final json = jsonEncode(data);
    await File(_localCachePath).writeAsString(CryptoService.encrypt(json));
  } catch (_) {}
}

