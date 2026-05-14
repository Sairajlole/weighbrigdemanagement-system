import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';

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
  final bool shiftBasedLogin;
  final bool forcePasswordChangeFirstLogin;
  final int passwordExpiryDays;

  // Session
  final bool emergencyLockdown;
  final bool autoLogoutEnabled;
  final int autoLogoutMinutes;
  final bool restrictUsb;
  final bool blockRemoteDesktop;

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
    this.shiftBasedLogin = false,
    this.forcePasswordChangeFirstLogin = true,
    this.passwordExpiryDays = 0,
    this.emergencyLockdown = false,
    this.autoLogoutEnabled = false,
    this.autoLogoutMinutes = 30,
    this.restrictUsb = false,
    this.blockRemoteDesktop = false,
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
      shiftBasedLogin: data['shiftBasedLogin'] as bool? ?? false,
      forcePasswordChangeFirstLogin: data['forcePasswordChangeFirstLogin'] as bool? ?? true,
      passwordExpiryDays: data['passwordExpiryDays'] as int? ?? 0,
      emergencyLockdown: data['emergencyLockdown'] as bool? ?? false,
      autoLogoutEnabled: data['autoLogoutEnabled'] as bool? ?? false,
      autoLogoutMinutes: data['autoLogoutMinutes'] as int? ?? 30,
      restrictUsb: data['restrictUsb'] as bool? ?? false,
      blockRemoteDesktop: data['blockRemoteDesktop'] as bool? ?? false,
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

final securitySettingsProvider = StreamProvider<SecuritySettings>((ref) {
  final override = ref.watch(securitySettingsOverrideProvider);
  if (override != null) {
    return Stream.value(override);
  }
  final db = ref.watch(firestoreProvider);
  return db.collection('settings').doc('security').snapshots().map((snap) {
    if (snap.exists) return SecuritySettings.fromMap(snap.data()!);
    return const SecuritySettings();
  });
});

final currentUserRoleProvider = FutureProvider<String>((ref) async {
  final db = ref.watch(firestoreProvider);
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Platform.isMacOS ? 'admin' : 'operator';
  try {
    final doc = await db.collection('operators').where('email', isEqualTo: user.email).limit(1).get();
    if (doc.docs.isNotEmpty) {
      return doc.docs.first.data()['role'] as String? ?? 'operator';
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
  final db = ref.watch(firestoreProvider);
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return true;
  try {
    final snap = await db.collection('operators').where('email', isEqualTo: user.email).limit(1).get();
    if (snap.docs.isEmpty) return true; // admin (not in operators collection)
    return snap.docs.first.data()['idStatus'] == 'verified';
  } catch (_) {}
  return false;
});

// ─── Permission Check Service ────────────────────────────────────────────────

final permissionServiceProvider = Provider<PermissionService>((ref) {
  final settings = ref.watch(securitySettingsProvider).valueOrNull ?? const SecuritySettings();
  final isAdmin = ref.watch(isAdminProvider);
  final kycVerified = ref.watch(currentOperatorKycProvider).valueOrNull ?? true;
  return PermissionService(settings: settings, isAdmin: isAdmin, kycVerified: kycVerified);
});

class PermissionService {
  final SecuritySettings settings;
  final bool isAdmin;
  final bool kycVerified;

  const PermissionService({required this.settings, required this.isAdmin, required this.kycVerified});

  bool get _kycOk => isAdmin || !settings.requireKycForSensitiveOps || kycVerified;

  // KYC-gated (sensitive operations)
  bool get canVoidWeighment => (isAdmin || settings.opCanVoidWeighment) && _kycOk;
  bool get canEditWeighment => (isAdmin || settings.opCanEditWeighment) && _kycOk;
  bool get canManualWeight => (isAdmin || settings.opCanManualWeight) && _kycOk;
  bool get canExportData => (isAdmin || settings.opCanExportData) && _kycOk;
  bool get canDeleteRecords => (isAdmin || settings.opCanDeleteRecords) && _kycOk;

  // Not KYC-gated
  bool get canReprint => isAdmin || settings.opCanReprint;
  bool get canViewReports => isAdmin || settings.opCanViewReports;
  bool get canViewCctv => isAdmin || settings.opCanViewCctv;
  bool get canAccessSettings => isAdmin || settings.opCanChangeSettings;
  bool get canManageCustomers => isAdmin || settings.opCanManageCustomers;
  bool get canManageMaterials => isAdmin || settings.opCanManageMaterials;

  bool get isLockdown => settings.emergencyLockdown && !isAdmin;
  bool get shouldMaskSensitive => !isAdmin && settings.maskSensitiveFields;
}

// ─── Audit Log Service ───────────────────────────────────────────────────────

final auditServiceProvider = Provider<AuditService>((ref) {
  final db = ref.watch(firestoreProvider);
  final settings = ref.watch(securitySettingsProvider).valueOrNull ?? const SecuritySettings();
  return AuditService(db: db, settings: settings);
});

class AuditService {
  final FirebaseFirestore db;
  final SecuritySettings settings;

  const AuditService({required this.db, required this.settings});

  Future<void> log({
    required String event,
    required String description,
    String? user,
    Map<String, dynamic>? metadata,
  }) async {
    if (!settings.auditEnabled) return;

    if (event == 'settingChange' && !settings.auditLogSettingChanges) return;
    if (event == 'weighmentEdit' && !settings.auditLogWeighmentEdits) return;
    if (event == 'reprint' && !settings.auditLogReprints) return;
    if (event == 'login' && !settings.auditLogLogins) return;
    if (event == 'export' && !settings.auditLogExports) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    final hostname = Platform.localHostname;

    await db.collection('auditLog').add({
      'event': event,
      'description': description,
      'user': user ?? currentUser?.email ?? 'unknown',
      'machine': hostname,
      'ip': await _getLocalIp(),
      'timestamp': FieldValue.serverTimestamp(),
      'success': true,
      ...?metadata,
    });
  }

  Future<void> logLogin({required bool success, String? email}) async {
    if (!settings.auditEnabled || !settings.auditLogLogins) return;

    final hostname = Platform.localHostname;
    await db.collection('auditLog').add({
      'event': 'login',
      'description': success ? 'Successful login' : 'Failed login attempt',
      'user': email ?? FirebaseAuth.instance.currentUser?.email ?? 'unknown',
      'machine': hostname,
      'ip': await _getLocalIp(),
      'timestamp': FieldValue.serverTimestamp(),
      'success': success,
    });
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
    'TeamViewer',
    'teamviewerd',
    'Chrome Remote Desktop',
    'remoting_host',
    'rustdesk',
    'RustDesk',
    'Splashtop',
    'SplashtopStreamer',
    'VNC',
    'screensharingd',
  ];

  Future<bool> isRemoteDesktopRunning() async {
    if (!enabled) return false;
    try {
      final result = await Process.run('ps', ['aux']);
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        for (final proc in _blockedProcesses) {
          if (output.contains(proc)) return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<List<String>> getRunningRemoteApps() async {
    if (!enabled) return [];
    final found = <String>[];
    try {
      final result = await Process.run('ps', ['aux']);
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        for (final proc in _blockedProcesses) {
          if (output.contains(proc)) found.add(proc);
        }
      }
    } catch (_) {}
    return found;
  }

  Future<void> killRemoteApps() async {
    if (!enabled) return;
    for (final proc in _blockedProcesses) {
      try {
        await Process.run('pkill', ['-f', proc]);
      } catch (_) {}
    }
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

Future<ShiftValidationResult> validateShiftLogin(FirebaseFirestore db, String email, SecuritySettings settings) async {
  if (!settings.shiftBasedLogin) return const ShiftValidationResult(allowed: true);

  try {
    final snap = await db.collection('operators').where('email', isEqualTo: email).limit(1).get();
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
  } catch (_) {}
  return const ShiftValidationResult(allowed: true);
}

// ─── Password Expiry Check ──────────────────────────────────────────────────

class PasswordCheckResult {
  final bool mustChange;
  final String? reason;
  const PasswordCheckResult({required this.mustChange, this.reason});
}

Future<PasswordCheckResult> checkPasswordStatus(FirebaseFirestore db, String email, SecuritySettings settings) async {
  try {
    final snap = await db.collection('operators').where('email', isEqualTo: email).limit(1).get();
    if (snap.docs.isEmpty) return const PasswordCheckResult(mustChange: false); // admin

    final data = snap.docs.first.data();

    if (settings.forcePasswordChangeFirstLogin && data['mustChangePassword'] == true) {
      return const PasswordCheckResult(mustChange: true, reason: 'You must change your password on first login.');
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
  } catch (_) {}
  return const PasswordCheckResult(mustChange: false);
}

// ─── IP Whitelist Check ─────────────────────────────────────────────────────

Future<bool> isIpAllowed(SecuritySettings settings) async {
  if (!settings.ipWhitelistEnabled || settings.whitelistedIps.isEmpty) return true;
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback && settings.whitelistedIps.contains(addr.address)) {
          return true;
        }
      }
    }
  } catch (_) {
    return true;
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
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return SecuritySettings.fromMap(data);
    }
  } catch (_) {}
  return const SecuritySettings();
}

Future<void> cacheSecuritySettings(Map<String, dynamic> data) async {
  try {
    await File(_localCachePath).writeAsString(jsonEncode(data));
  } catch (_) {}
}

