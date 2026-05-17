import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/general_settings_provider.dart';

// ─── Local persistence ───────────────────────────────────────────────────────

String get _localSettingsPath {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  final dir = Directory('$home/.weighbridge');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return '${dir.path}/data_backup_settings.json';
}

Future<void> _saveLocally(Map<String, dynamic> data) async {
  final file = File(_localSettingsPath);
  await file.writeAsString(jsonEncode(data));
}

Future<Map<String, dynamic>> _loadLocally() async {
  try {
    final file = File(_localSettingsPath);
    if (await file.exists()) return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  } catch (_) {}
  return {};
}

// ─── JSON Serialization Helper ───────────────────────────────────────────────

Object? _toJsonSafe(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate().toIso8601String();
  if (value is DateTime) return value.toIso8601String();
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), _toJsonSafe(v)));
  if (value is List) return value.map(_toJsonSafe).toList();
  return value;
}

String _encodeJson(dynamic data) {
  return const JsonEncoder.withIndent('  ').convert(_toJsonSafe(data));
}

// ─── Provider ────────────────────────────────────────────────────────────────

final _dataBackupProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  try {
    final doc = await db.dataBackupSettings.get();
    if (doc.exists) {
      final data = doc.data()!;
      await _saveLocally(data);
      return data;
    }
  } catch (_) {}
  return _loadLocally();
});

// ─── Screen ──────────────────────────────────────────────────────────────────

class DataBackupScreen extends ConsumerStatefulWidget {
  const DataBackupScreen({super.key});

  @override
  ConsumerState<DataBackupScreen> createState() => _DataBackupScreenState();
}

class _DataBackupScreenState extends ConsumerState<DataBackupScreen> {
  bool _loaded = false;
  bool _saving = false;
  bool _dirty = false;

  String? _headerMsg;
  bool _headerMsgIsError = false;

  // ── Backup Schedule ──
  String _backupSchedule = 'daily'; // off, daily, weekly, monthly
  String _backupTime = '02:00';

  // ── Backup Location ──
  late String _basePath;
  String get _defaultBasePath {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    return '$home/WeighbridgeData';
  }

  // ── What to backup ──
  bool _backupWeighments = true;
  bool _backupSettings = true;
  bool _backupMasterData = true;
  bool _backupCctv = false;
  bool _backupOperators = true;

  // ── CCTV Storage ──
  String _cctvPath = '';
  int _cctvRetentionDays = 30;
  int _cctvMaxStorageGb = 50;
  String _cctvQuality = 'compressed'; // full, compressed
  String _cctvNamingFormat = '{camera}_{vehicle}_{timestamp}';

  // ── Data Retention ──
  int _archiveAfterMonths = 12;
  bool _autoPurgeArchived = false;
  int _purgeAfterMonths = 36;

  // ── Cloud Sync ──
  bool _offlineMode = false;
  String _lastSyncTime = '';
  int _pendingChanges = 0;

  // ── Folder structure preview ──
  String get _folderPreview => '''$_basePath/
├── Backups/
│   ├── ${DateFormat('yyyy-MM-dd').format(DateTime.now())}_$_backupSchedule/
│   └── ...
├── CCTV/
│   ├── ${DateFormat('yyyy/MM/dd').format(DateTime.now())}/
│   │   └── $_cctvNamingFormat
│   └── retention: ${_cctvRetentionDays}d
├── Exports/
│   └── weighments_${DateFormat('MMMyyy').format(DateTime.now()).toLowerCase()}.csv
└── Logs/
    └── app_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.log''';

  @override
  void initState() {
    super.initState();
    _basePath = _defaultBasePath;
    _cctvPath = '$_basePath/CCTV';
  }

  void _loadData(Map<String, dynamic> data) {
    if (_loaded) return;
    _loaded = true;

    _backupSchedule = data['backupSchedule'] as String? ?? 'daily';
    _backupTime = data['backupTime'] as String? ?? '02:00';
    _basePath = data['basePath'] as String? ?? _defaultBasePath;
    _backupWeighments = data['backupWeighments'] as bool? ?? true;
    _backupSettings = data['backupSettings'] as bool? ?? true;
    _backupMasterData = data['backupMasterData'] as bool? ?? true;
    _backupCctv = data['backupCctv'] as bool? ?? false;
    _backupOperators = data['backupOperators'] as bool? ?? true;
    _cctvPath = data['cctvPath'] as String? ?? '$_basePath/CCTV';
    _cctvRetentionDays = data['cctvRetentionDays'] as int? ?? 30;
    _cctvMaxStorageGb = data['cctvMaxStorageGb'] as int? ?? 50;
    _cctvQuality = data['cctvQuality'] as String? ?? 'compressed';
    _cctvNamingFormat = data['cctvNamingFormat'] as String? ?? '{camera}_{vehicle}_{timestamp}';
    _archiveAfterMonths = data['archiveAfterMonths'] as int? ?? 12;
    _autoPurgeArchived = data['autoPurgeArchived'] as bool? ?? false;
    _purgeAfterMonths = data['purgeAfterMonths'] as int? ?? 36;
    _offlineMode = data['offlineMode'] as bool? ?? false;
    _lastSyncTime = data['lastSyncTime'] as String? ?? '';
    _pendingChanges = data['pendingChanges'] as int? ?? 0;
  }

  void _markDirty() => setState(() => _dirty = true);

  void _showHeaderMsg(String msg, {bool isError = false}) {
    setState(() { _headerMsg = msg; _headerMsgIsError = isError; });
    Future.delayed(Duration(seconds: isError ? 5 : 3), () {
      if (mounted) setState(() => _headerMsg = null);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final data = {
      'backupSchedule': _backupSchedule,
      'backupTime': _backupTime,
      'basePath': _basePath,
      'backupWeighments': _backupWeighments,
      'backupSettings': _backupSettings,
      'backupMasterData': _backupMasterData,
      'backupCctv': _backupCctv,
      'backupOperators': _backupOperators,
      'cctvPath': _cctvPath,
      'cctvRetentionDays': _cctvRetentionDays,
      'cctvMaxStorageGb': _cctvMaxStorageGb,
      'cctvQuality': _cctvQuality,
      'cctvNamingFormat': _cctvNamingFormat,
      'archiveAfterMonths': _archiveAfterMonths,
      'autoPurgeArchived': _autoPurgeArchived,
      'purgeAfterMonths': _purgeAfterMonths,
      'offlineMode': _offlineMode,
      'lastSyncTime': _lastSyncTime,
      'pendingChanges': _pendingChanges,
    };
    try {
      final db = ref.read(firestorePathsProvider);
      await db.dataBackupSettings.set(data, SetOptions(merge: true));
      await _saveLocally(data);
      if (mounted) _showHeaderMsg('Backup settings saved');
    } catch (_) {
      await _saveLocally(data);
      if (mounted) _showHeaderMsg('Saved locally (offline)', isError: true);
    }
    ref.invalidate(_dataBackupProvider);
    if (mounted) setState(() { _saving = false; _dirty = false; });
  }

  Future<void> _backupNow() async {
    final dir = Directory('$_basePath/Backups/${DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now())}');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final manifest = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'includes': {
        'weighments': _backupWeighments,
        'settings': _backupSettings,
        'masterData': _backupMasterData,
        'cctv': _backupCctv,
        'operators': _backupOperators,
      },
    };

    final db = ref.read(firestorePathsProvider);

    if (_backupSettings) {
      try {
        final settingsSnap = await db.siteSettings.get();
        final settings = <String, dynamic>{};
        for (final doc in settingsSnap.docs) {
          settings[doc.id] = doc.data();
        }
        await File('${dir.path}/settings.json').writeAsString(_encodeJson(settings));
      } catch (_) {}
    }

    if (_backupMasterData) {
      for (final col in ['customers', 'materials', 'vehicles']) {
        try {
          final snap = await db.collectionByName(col)!.get();
          final items = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          await File('${dir.path}/$col.json').writeAsString(_encodeJson(items));
        } catch (_) {}
      }
    }

    if (_backupOperators) {
      try {
        final snap = await db.operators.get();
        final items = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        await File('${dir.path}/operators.json').writeAsString(_encodeJson(items));
      } catch (_) {}
    }

    if (_backupWeighments) {
      try {
        final snap = await db.weighments.orderBy('timestamp', descending: true).limit(10000).get();
        final items = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        await File('${dir.path}/weighments.json').writeAsString(_encodeJson(items));
      } catch (_) {}
    }

    await File('${dir.path}/manifest.json').writeAsString(_encodeJson(manifest));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Backup saved to ${dir.path}'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ));
    }
  }

  Future<String?> _askEncryptionPassword({required bool isExport}) async {
    final ctrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final scheme = Theme.of(context).colorScheme;
    String? error;

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Row(children: [
            Icon(Icons.lock_rounded, size: 20, color: scheme.primary),
            const SizedBox(width: 8),
            Text(isExport ? 'Encrypt Backup' : 'Decrypt Backup'),
          ]),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isExport ? 'Choose a password to encrypt the backup file.' : 'Enter the password used during export.', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password', isDense: true),
                ),
                if (isExport) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Confirm Password', isDense: true),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(fontSize: 11, color: scheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () {
              if (ctrl.text.length < 8) {
                setSt(() => error = 'Password must be at least 8 characters.');
                return;
              }
              if (isExport && ctrl.text != confirmCtrl.text) {
                setSt(() => error = 'Passwords do not match.');
                return;
              }
              Navigator.pop(ctx, ctrl.text);
            }, child: Text(isExport ? 'Encrypt & Export' : 'Decrypt')),
          ],
        ),
      ),
    );
  }

  Future<bool> _isEncryptionEnabled() async {
    try {
      final db = ref.read(firestorePathsProvider);
      final secSnap = await db.securitySettings.get();
      return secSnap.data()?['encryptBackups'] as bool? ?? false;
    } catch (_) {}
    return false;
  }

  Future<void> _exportSettings() async {
    final result = await Process.run('osascript', [
      '-e', 'POSIX path of (choose folder with prompt "Choose export location")',
    ]);
    if (result.exitCode != 0) return;
    final chosen = (result.stdout as String).trim();
    if (chosen.isEmpty) return;
    final exportPath = chosen.endsWith('/') ? chosen.substring(0, chosen.length - 1) : chosen;

    final dir = Directory(exportPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final encrypt = await _isEncryptionEnabled();
    String? password;
    if (encrypt) {
      password = await _askEncryptionPassword(isExport: true);
      if (password == null) return;
    }

    final db = ref.read(firestorePathsProvider);
    try {
      final snap = await db.siteSettings.get();
      final settings = <String, dynamic>{};
      for (final doc in snap.docs) {
        settings[doc.id] = doc.data();
      }
      final jsonStr = _encodeJson(settings);

      if (encrypt && password != null) {
        final encPath = '${dir.path}/system_settings_${DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now())}.enc';
        final tmpFile = File('${dir.path}/.tmp_export.json');
        await tmpFile.writeAsString(jsonStr);
        final encResult = await Process.run('openssl', [
          'enc', '-aes-256-cbc', '-pbkdf2', '-pass', 'pass:$password', '-in', tmpFile.path, '-out', encPath,
        ]);
        if (tmpFile.existsSync()) await tmpFile.delete();
        if (encResult.exitCode != 0 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Encryption failed: ${encResult.stderr}'), backgroundColor: Theme.of(context).colorScheme.error));
          return;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Encrypted settings exported to $encPath'), backgroundColor: Theme.of(context).colorScheme.primary));
        }
      } else {
        final path = '${dir.path}/system_settings_${DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now())}.json';
        await File(path).writeAsString(jsonStr);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Settings exported to $path'), backgroundColor: Theme.of(context).colorScheme.primary));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e'), backgroundColor: Theme.of(context).colorScheme.error));
      }
    }
  }

  Future<void> _importSettings() async {
    final result = await Process.run('osascript', [
      '-e', 'POSIX path of (choose file of type {"json", "enc"} with prompt "Select settings file (.json or .enc)")',
    ]);
    if (result.exitCode != 0) return;
    final path = (result.stdout as String).trim();
    if (path.isEmpty) return;

    try {
      String content;
      if (path.endsWith('.enc')) {
        final password = await _askEncryptionPassword(isExport: false);
        if (password == null) return;
        final decResult = await Process.run('openssl', [
          'enc', '-aes-256-cbc', '-pbkdf2', '-d', '-pass', 'pass:$password', '-in', path,
        ]);
        if (decResult.exitCode != 0) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Decryption failed — wrong password or corrupted file.'), backgroundColor: Theme.of(context).colorScheme.error));
          }
          return;
        }
        content = decResult.stdout as String;
      } else {
        content = await File(path).readAsString();
      }
      final settings = jsonDecode(content) as Map<String, dynamic>;
      final db = ref.read(firestorePathsProvider);
      for (final entry in settings.entries) {
        await db.siteSetting(entry.key).set(entry.value as Map<String, dynamic>);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Settings imported successfully. Restart to apply.'), backgroundColor: Theme.of(context).colorScheme.primary));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e'), backgroundColor: Theme.of(context).colorScheme.error));
      }
    }
  }

  Future<void> _forceSync() async {
    setState(() => _pendingChanges = 0);
    final now = DateTime.now();
    setState(() => _lastSyncTime = '${DateFormat('yyyy-MM-dd').format(now)} ${getTimeFormatter(ref.read(timeFormatProvider)).format(now)}');
    _markDirty();
    await _save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Sync complete'), backgroundColor: Theme.of(context).colorScheme.primary));
    }
  }

  Future<void> _pickFolder(String current, void Function(String) onPicked) async {
    final result = await Process.run('osascript', [
      '-e', 'POSIX path of (choose folder with prompt "Select folder")',
    ]);
    if (result.exitCode == 0) {
      final path = (result.stdout as String).trim();
      if (path.isNotEmpty) {
        setState(() => onPicked(path.endsWith('/') ? path.substring(0, path.length - 1) : path));
        _markDirty();
      }
    }
  }

  void _ensureFolderStructure() {
    final dirs = [
      '$_basePath/Backups',
      '$_basePath/CCTV',
      '$_basePath/Exports',
      '$_basePath/Logs',
    ];
    for (final d in dirs) {
      final dir = Directory(d);
      if (!dir.existsSync()) dir.createSync(recursive: true);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Folder structure created'), backgroundColor: Theme.of(context).colorScheme.primary));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final asyncData = ref.watch(_dataBackupProvider);

    asyncData.whenData(_loadData);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Column(
        children: [
          // ── Header ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                      onPressed: () => context.go('/settings'),
                      style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.backup_rounded, size: 20, color: scheme.primary),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Data & Backup', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text('Backups and data retention', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                    const Spacer(),
                    if (_dirty) ...[
                      TextButton(
                        onPressed: () { setState(() { _loaded = false; _dirty = false; }); ref.invalidate(_dataBackupProvider); },
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    FilledButton.icon(
                      onPressed: _dirty && !_saving ? _save : null,
                      icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded, size: 16),
                      label: Text(_saving ? 'Saving...' : 'Save'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    ),
                  ],
                ),
                if (_headerMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _headerMsgIsError ? scheme.errorContainer.withValues(alpha: 0.6) : AppTheme.successColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _headerMsgIsError ? scheme.error.withValues(alpha: 0.3) : AppTheme.successColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _headerMsgIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                            size: 15,
                            color: _headerMsgIsError ? scheme.error : AppTheme.successColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_headerMsg!, style: text.bodySmall?.copyWith(color: _headerMsgIsError ? scheme.error : AppTheme.successColor, fontWeight: FontWeight.w500))),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // ── Body ──
          Expanded(
            child: asyncData.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) => SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ═══ Row 1: Backup + CCTV Storage ═══
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildBackupSection(scheme, text)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildCctvStorageSection(scheme, text)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // ═══ Row 2: Folder Structure + Data Retention ═══
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildFolderStructureSection(scheme, text)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildDataRetentionSection(scheme, text)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // ═══ Row 3: Cloud Sync + System Settings ═══
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildCloudSyncSection(scheme, text)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildSystemSettingsSection(scheme, text)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BACKUP SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBackupSection(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      icon: Icons.cloud_upload_rounded,
      title: 'Backup',
      scheme: scheme,
      text: text,
      children: [
        _buildRow('Schedule', scheme, text, child: _ChipGroup(
          value: _backupSchedule,
          options: const ['off', 'daily', 'weekly', 'monthly'],
          onChanged: (v) { setState(() => _backupSchedule = v); _markDirty(); },
        )),
        if (_backupSchedule != 'off') ...[
          const SizedBox(height: 10),
          _buildRow('Time', scheme, text, child: GestureDetector(
            onTap: () async {
              final parts = _backupTime.split(':');
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
              );
              if (picked != null) {
                setState(() => _backupTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
                _markDirty();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: scheme.outlineVariant)),
              child: Text(_backupTime, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
          )),
        ],
        const SizedBox(height: 10),
        _buildRow('Location', scheme, text, child: Expanded(
          child: GestureDetector(
            onTap: () => _pickFolder(_basePath, (v) => _basePath = v),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: scheme.surfaceContainerLow),
              child: Text(_basePath, style: text.bodySmall, overflow: TextOverflow.ellipsis),
            ),
          ),
        )),
        const SizedBox(height: 14),
        Text('Include in backup:', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _ToggleChip(label: 'Weighments', value: _backupWeighments, onChanged: (v) { setState(() => _backupWeighments = v); _markDirty(); }),
            _ToggleChip(label: 'Settings', value: _backupSettings, onChanged: (v) { setState(() => _backupSettings = v); _markDirty(); }),
            _ToggleChip(label: 'Master Data', value: _backupMasterData, onChanged: (v) { setState(() => _backupMasterData = v); _markDirty(); }),
            _ToggleChip(label: 'CCTV', value: _backupCctv, onChanged: (v) { setState(() => _backupCctv = v); _markDirty(); }),
            _ToggleChip(label: 'Operators', value: _backupOperators, onChanged: (v) { setState(() => _backupOperators = v); _markDirty(); }),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _backupNow,
              icon: const Icon(Icons.backup_rounded, size: 14),
              label: const Text('Backup Now'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), textStyle: const TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CCTV STORAGE SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCctvStorageSection(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      icon: Icons.videocam_rounded,
      title: 'CCTV Storage',
      scheme: scheme,
      text: text,
      children: [
        _buildRow('Storage Path', scheme, text, child: Expanded(
          child: GestureDetector(
            onTap: () => _pickFolder(_cctvPath, (v) => _cctvPath = v),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: scheme.surfaceContainerLow),
              child: Text(_cctvPath, style: text.bodySmall, overflow: TextOverflow.ellipsis),
            ),
          ),
        )),
        const SizedBox(height: 10),
        _buildRow('Retention', scheme, text, child: _ChipGroup(
          value: '${_cctvRetentionDays}d',
          options: const ['7d', '30d', '60d', '90d'],
          onChanged: (v) { setState(() => _cctvRetentionDays = int.parse(v.replaceAll('d', ''))); _markDirty(); },
        )),
        const SizedBox(height: 10),
        _buildRow('Max Storage', scheme, text, child: Row(
          children: [
            SizedBox(
              width: 60,
              child: TextField(
                controller: TextEditingController(text: '$_cctvMaxStorageGb'),
                keyboardType: TextInputType.number,
                onChanged: (v) { final n = int.tryParse(v); if (n != null && n > 0) { _cctvMaxStorageGb = n; _markDirty(); } },
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                style: text.bodySmall,
              ),
            ),
            const SizedBox(width: 6),
            Text('GB', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        )),
        const SizedBox(height: 10),
        _buildRow('Quality', scheme, text, child: _ChipGroup(
          value: _cctvQuality,
          options: const ['full', 'compressed'],
          onChanged: (v) { setState(() => _cctvQuality = v); _markDirty(); },
        )),
        const SizedBox(height: 10),
        _buildRow('File Naming', scheme, text, child: Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: scheme.surfaceContainerLow),
            child: Text(_cctvNamingFormat, style: text.bodySmall?.copyWith(fontFamily: 'Courier', fontSize: 11)),
          ),
        )),
        const SizedBox(height: 6),
        Text('Auto-purges oldest files when max storage exceeded', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FOLDER STRUCTURE SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFolderStructureSection(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      icon: Icons.folder_rounded,
      title: 'Folder Structure',
      scheme: scheme,
      text: text,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _folderPreview,
            style: const TextStyle(fontFamily: 'Courier', fontSize: 10.5, height: 1.5, color: Color(0xFFCDD6F4)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _ensureFolderStructure,
              icon: const Icon(Icons.create_new_folder_rounded, size: 14),
              label: const Text('Create Folders'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), textStyle: const TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DATA RETENTION SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDataRetentionSection(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      icon: Icons.auto_delete_rounded,
      title: 'Data Retention',
      scheme: scheme,
      text: text,
      children: [
        _buildRow('Archive after', scheme, text, child: Row(
          children: [
            SizedBox(
              width: 50,
              child: TextField(
                controller: TextEditingController(text: '$_archiveAfterMonths'),
                keyboardType: TextInputType.number,
                onChanged: (v) { final n = int.tryParse(v); if (n != null && n > 0) { _archiveAfterMonths = n; _markDirty(); } },
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                style: text.bodySmall,
              ),
            ),
            const SizedBox(width: 6),
            Text('months', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        )),
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(
              height: 20,
              width: 36,
              child: FittedBox(
                child: Switch(value: _autoPurgeArchived, onChanged: (v) { setState(() => _autoPurgeArchived = v); _markDirty(); }),
              ),
            ),
            const SizedBox(width: 8),
            Text('Auto-purge archived records', style: text.bodySmall),
          ],
        ),
        if (_autoPurgeArchived) ...[
          const SizedBox(height: 10),
          _buildRow('Purge after', scheme, text, child: Row(
            children: [
              SizedBox(
                width: 50,
                child: TextField(
                  controller: TextEditingController(text: '$_purgeAfterMonths'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) { final n = int.tryParse(v); if (n != null && n > 0) { _purgeAfterMonths = n; _markDirty(); } },
                  decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                  style: text.bodySmall,
                ),
              ),
              const SizedBox(width: 6),
              Text('months', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          )),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Export Data'),
                    content: const Text('Export all weighment records as CSV?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                      FilledButton(onPressed: () { Navigator.pop(ctx); _exportWeighments(); }, child: const Text('Export')),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.download_rounded, size: 14),
              label: const Text('Export CSV'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), textStyle: const TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _exportWeighments() async {
    final dir = Directory('$_basePath/Exports');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final db = ref.read(firestorePathsProvider);
    try {
      final snap = await db.weighments.orderBy('timestamp', descending: true).limit(50000).get();
      if (snap.docs.isEmpty) return;
      final buf = StringBuffer();
      final keys = snap.docs.first.data().keys.toList();
      buf.writeln(keys.join(','));
      for (final doc in snap.docs) {
        final d = doc.data();
        buf.writeln(keys.map((k) => '"${(d[k] ?? '').toString().replaceAll('"', '""')}"').join(','));
      }
      final path = '${dir.path}/weighments_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv';
      await File(path).writeAsString(buf.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported to $path'), backgroundColor: Theme.of(context).colorScheme.primary));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e'), backgroundColor: Theme.of(context).colorScheme.error));
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLOUD SYNC SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCloudSyncSection(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      icon: Icons.cloud_sync_rounded,
      title: 'Cloud Sync',
      scheme: scheme,
      text: text,
      children: [
        _buildRow('Last Sync', scheme, text, child: Text(
          _lastSyncTime.isEmpty ? 'Never' : _lastSyncTime,
          style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: _lastSyncTime.isEmpty ? scheme.error : scheme.onSurface),
        )),
        const SizedBox(height: 10),
        _buildRow('Pending', scheme, text, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _pendingChanges > 0 ? scheme.errorContainer : scheme.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$_pendingChanges changes', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: _pendingChanges > 0 ? scheme.onErrorContainer : scheme.primary)),
        )),
        const SizedBox(height: 10),
        _buildRow('Conflict', scheme, text, child: Text('Ask before overwriting', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(
              height: 20,
              width: 36,
              child: FittedBox(
                child: Switch(value: _offlineMode, onChanged: (v) { setState(() => _offlineMode = v); _markDirty(); }),
              ),
            ),
            const SizedBox(width: 8),
            Text('Offline Mode', style: text.bodySmall),
            const SizedBox(width: 6),
            Text('(queue writes when no internet)', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _forceSync,
          icon: const Icon(Icons.sync_rounded, size: 14),
          label: const Text('Force Sync'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), textStyle: const TextStyle(fontSize: 11)),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SYSTEM SETTINGS SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSystemSettingsSection(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      icon: Icons.settings_backup_restore_rounded,
      title: 'System Settings',
      scheme: scheme,
      text: text,
      children: [
        Text('Export or import all system configuration as a single JSON file. Use for cloning to new machines or disaster recovery.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _exportSettings,
              icon: const Icon(Icons.upload_rounded, size: 14),
              label: const Text('Export Settings'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), textStyle: const TextStyle(fontSize: 11)),
            ),
            OutlinedButton.icon(
              onPressed: _importSettings,
              icon: const Icon(Icons.download_rounded, size: 14),
              label: const Text('Import Settings'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), textStyle: const TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Row(children: [Icon(Icons.warning_rounded, color: scheme.error), const SizedBox(width: 8), const Text('Reset All Settings')]),
                content: const Text('This will reset ALL system settings to factory defaults. This action cannot be undone.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final db = ref.read(firestorePathsProvider);
                      final snap = await db.siteSettings.get();
                      for (final doc in snap.docs) {
                        await doc.reference.delete();
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('All settings reset. Restart the app.'), backgroundColor: scheme.error));
                      }
                    },
                    style: FilledButton.styleFrom(backgroundColor: scheme.error),
                    child: const Text('Reset Everything'),
                  ),
                ],
              ),
            );
          },
          icon: Icon(Icons.restart_alt_rounded, size: 14, color: scheme.error),
          label: Text('Factory Reset', style: TextStyle(color: scheme.error)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            textStyle: const TextStyle(fontSize: 11),
            side: BorderSide(color: scheme.error.withValues(alpha: 0.4)),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRow(String label, ColorScheme scheme, TextTheme text, {Widget? child}) {
    return Row(
      children: [
        SizedBox(width: 100, child: Text(label, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
        if (child != null) child,
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// REUSABLE WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final ColorScheme scheme;
  final TextTheme text;
  final List<Widget> children;

  const _SectionCard({required this.icon, required this.title, required this.scheme, required this.text, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.15))),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(icon, size: 15, color: scheme.primary),
                ),
                const SizedBox(width: 10),
                Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipGroup extends StatelessWidget {
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _ChipGroup({required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: options.map((opt) {
        final selected = opt == value;
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: GestureDetector(
            onTap: () => onChanged(opt),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? scheme.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: selected ? scheme.primary.withValues(alpha: 0.4) : scheme.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Text(opt, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? scheme.primary : scheme.onSurfaceVariant)),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleChip({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: value ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: value ? scheme.primary.withValues(alpha: 0.4) : scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(value ? Icons.check_circle_rounded : Icons.circle_outlined, size: 12, color: value ? scheme.primary : scheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: value ? FontWeight.w700 : FontWeight.w500, color: value ? scheme.primary : scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
