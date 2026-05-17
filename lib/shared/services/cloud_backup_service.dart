import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:weighbridgemanagement/shared/services/crypto_service.dart';

enum BackupStatus { idle, running, success, failed }

class BackupResult {
  final bool success;
  final String message;
  final int? filesUploaded;
  final int? bytesTransferred;
  final DateTime timestamp;

  BackupResult({required this.success, required this.message, this.filesUploaded, this.bytesTransferred})
      : timestamp = DateTime.now();
}

class GDriveConfig {
  final bool enabled;
  final String clientId;
  final String folder;
  final String frequency;

  const GDriveConfig({
    this.enabled = false,
    this.clientId = '',
    this.folder = 'WeighbridgeBackups',
    this.frequency = 'daily',
  });

  factory GDriveConfig.fromMap(Map<String, dynamic> data) {
    return GDriveConfig(
      enabled: data['enabled'] as bool? ?? false,
      clientId: data['clientId'] as String? ?? '',
      folder: data['folder'] as String? ?? 'WeighbridgeBackups',
      frequency: data['frequency'] as String? ?? 'daily',
    );
  }

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'clientId': clientId,
    'folder': folder,
    'frequency': frequency,
  };
}

class S3Config {
  final bool enabled;
  final String bucket;
  final String region;
  final String accessKey;
  final String secretKey;
  final String prefix;
  final String frequency;

  const S3Config({
    this.enabled = false,
    this.bucket = '',
    this.region = 'ap-south-1',
    this.accessKey = '',
    this.secretKey = '',
    this.prefix = 'weighbridge/',
    this.frequency = 'daily',
  });

  factory S3Config.fromMap(Map<String, dynamic> data) {
    return S3Config(
      enabled: data['enabled'] as bool? ?? false,
      bucket: data['bucket'] as String? ?? '',
      region: data['region'] as String? ?? 'ap-south-1',
      accessKey: CryptoService.decrypt(data['accessKey'] as String? ?? ''),
      secretKey: CryptoService.decrypt(data['secretKey'] as String? ?? ''),
      prefix: data['prefix'] as String? ?? 'weighbridge/',
      frequency: data['frequency'] as String? ?? 'daily',
    );
  }

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'bucket': bucket,
    'region': region,
    'accessKey': CryptoService.encrypt(accessKey),
    'secretKey': CryptoService.encrypt(secretKey),
    'prefix': prefix,
    'frequency': frequency,
  };
}

class CloudBackupService {
  GDriveConfig _gdriveConfig;
  S3Config _s3Config;
  final FirebaseFirestore _db;

  final _statusController = StreamController<BackupStatus>.broadcast();
  final _logController = StreamController<BackupResult>.broadcast();
  BackupStatus _status = BackupStatus.idle;
  Timer? _scheduleTimer;
  DateTime? _lastBackupTime;

  CloudBackupService(this._gdriveConfig, this._s3Config, this._db) {
    _scheduleNextBackup();
  }

  Stream<BackupStatus> get statusStream => _statusController.stream;
  Stream<BackupResult> get logStream => _logController.stream;
  BackupStatus get status => _status;
  DateTime? get lastBackupTime => _lastBackupTime;

  void updateConfig(GDriveConfig gdrive, S3Config s3) {
    _gdriveConfig = gdrive;
    _s3Config = s3;
    _scheduleTimer?.cancel();
    _scheduleNextBackup();
  }

  Future<BackupResult> runBackupNow() async {
    _setStatus(BackupStatus.running);

    try {
      final exportData = await _exportFirestoreData();
      final exportJson = jsonEncode(exportData);
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final filename = 'weighbridge_backup_$timestamp.json';

      final results = <BackupResult>[];

      if (_s3Config.enabled) {
        results.add(await _uploadToS3(filename, exportJson));
      }

      if (_gdriveConfig.enabled) {
        results.add(await _uploadToGDrive(filename, exportJson));
      }

      if (results.isEmpty) {
        final result = BackupResult(success: false, message: 'No backup destination enabled');
        _logController.add(result);
        _setStatus(BackupStatus.failed);
        return result;
      }

      final allSuccess = results.every((r) => r.success);
      _lastBackupTime = DateTime.now();

      await _db.collection('settings').doc('integrations').set({
        'cloud': {'lastBackup': FieldValue.serverTimestamp()},
      }, SetOptions(merge: true));

      final result = BackupResult(
        success: allSuccess,
        message: allSuccess ? 'Backup completed' : 'Partial backup: ${results.where((r) => !r.success).map((r) => r.message).join(', ')}',
        filesUploaded: results.where((r) => r.success).length,
        bytesTransferred: exportJson.length,
      );
      _logController.add(result);
      _setStatus(allSuccess ? BackupStatus.success : BackupStatus.failed);
      return result;
    } catch (e) {
      final result = BackupResult(success: false, message: 'Backup failed: $e');
      _logController.add(result);
      _setStatus(BackupStatus.failed);
      return result;
    }
  }

  Future<bool> testS3Connection() async {
    if (!_s3Config.enabled || _s3Config.bucket.isEmpty) return false;

    try {
      final now = DateTime.now().toUtc();
      final dateStamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final host = '${_s3Config.bucket}.s3.${_s3Config.region}.amazonaws.com';

      final headers = _signS3Request('HEAD', '/${_s3Config.prefix}', host, dateStamp, now);

      final client = HttpClient();
      final request = await client.headUrl(Uri.parse('https://$host/${_s3Config.prefix}'));
      headers.forEach((k, v) => request.headers.set(k, v));

      final response = await request.close();
      client.close();

      return response.statusCode == 200 || response.statusCode == 404 || response.statusCode == 403;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _exportFirestoreData() async {
    final export = <String, dynamic>{};

    final collections = ['weighments', 'customers', 'operators', 'settings', 'materials'];
    for (final col in collections) {
      final snap = await _db.collection(col).get();
      export[col] = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    }

    export['exportedAt'] = DateTime.now().toIso8601String();
    export['version'] = 1;
    return export;
  }

  Future<BackupResult> _uploadToS3(String filename, String content) async {
    try {
      final now = DateTime.now().toUtc();
      final dateStamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final host = '${_s3Config.bucket}.s3.${_s3Config.region}.amazonaws.com';
      final path = '/${_s3Config.prefix}$filename';

      final headers = _signS3Request('PUT', path, host, dateStamp, now, body: content);

      final client = HttpClient();
      final request = await client.putUrl(Uri.parse('https://$host$path'));
      headers.forEach((k, v) => request.headers.set(k, v));
      request.headers.set('content-type', 'application/json');
      request.write(content);

      final response = await request.close();
      client.close();

      if (response.statusCode == 200) {
        return BackupResult(success: true, message: 'S3 upload OK', bytesTransferred: content.length);
      }
      return BackupResult(success: false, message: 'S3 HTTP ${response.statusCode}');
    } catch (e) {
      return BackupResult(success: false, message: 'S3 error: $e');
    }
  }

  Future<BackupResult> _uploadToGDrive(String filename, String content) async {
    if (_gdriveConfig.clientId.isEmpty) {
      return BackupResult(success: false, message: 'GDrive: no client ID configured');
    }

    try {
      final tokenDoc = await _db.collection('settings').doc('integrations').get();
      final gdriveToken = tokenDoc.data()?['gdrive']?['accessToken'] as String?;
      final refreshToken = tokenDoc.data()?['gdrive']?['refreshToken'] as String?;

      if (gdriveToken == null || gdriveToken.isEmpty) {
        // Fall back to local staging if no OAuth token available
        final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
        final backupDir = Directory('$home/.weighbridge/backups/gdrive');
        if (!backupDir.existsSync()) backupDir.createSync(recursive: true);
        final file = File('${backupDir.path}/$filename');
        await file.writeAsString(content);
        return BackupResult(success: false, message: 'GDrive: no access token — staged locally. Please authorize via Settings > Integrations.');
      }

      var accessToken = CryptoService.decrypt(gdriveToken);

      // Try upload
      var response = await _gdriveUpload(accessToken, filename, content);

      // Token expired — try refresh
      if (response.statusCode == 401 && refreshToken != null && refreshToken.isNotEmpty) {
        final newToken = await _refreshGDriveToken(CryptoService.decrypt(refreshToken));
        if (newToken != null) {
          accessToken = newToken;
          await _db.collection('settings').doc('integrations').set({
            'gdrive': {'accessToken': CryptoService.encrypt(newToken)},
          }, SetOptions(merge: true));
          response = await _gdriveUpload(accessToken, filename, content);
        }
      }

      if (response.statusCode == 200) {
        return BackupResult(success: true, message: 'GDrive: uploaded', filesUploaded: 1, bytesTransferred: content.length);
      }
      final respBody = await response.transform(utf8.decoder).join();
      final truncated = respBody.length > 100 ? respBody.substring(0, 100) : respBody;
      return BackupResult(success: false, message: 'GDrive HTTP ${response.statusCode}: $truncated');
    } catch (e) {
      return BackupResult(success: false, message: 'GDrive error: $e');
    }
  }

  Future<HttpClientResponse> _gdriveUpload(String accessToken, String filename, String content) async {
    final metadata = jsonEncode({'name': filename, 'parents': [_gdriveConfig.folder]});
    final boundary = '===weighbridge_boundary===';
    final body = '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadata\r\n--$boundary\r\nContent-Type: application/json\r\n\r\n$content\r\n--$boundary--';

    final client = HttpClient();
    final request = await client.postUrl(Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart'));
    request.headers.set('Authorization', 'Bearer $accessToken');
    request.headers.set('Content-Type', 'multipart/related; boundary=$boundary');
    request.write(body);
    final response = await request.close();
    client.close();
    return response;
  }

  Future<String?> _refreshGDriveToken(String refreshToken) async {
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('https://oauth2.googleapis.com/token'));
      request.headers.set('Content-Type', 'application/x-www-form-urlencoded');
      request.write('client_id=${_gdriveConfig.clientId}&refresh_token=$refreshToken&grant_type=refresh_token');
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        return data['access_token'] as String?;
      }
      client.close();
    } catch (_) {}
    return null;
  }

  Map<String, String> _signS3Request(String method, String path, String host, String dateStamp, DateTime now, {String? body}) {
    final amzDate = '${dateStamp}T${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}Z';
    final contentHash = sha256.convert(utf8.encode(body ?? '')).toString();

    final canonicalRequest = '$method\n$path\n\nhost:$host\nx-amz-content-sha256:$contentHash\nx-amz-date:$amzDate\n\nhost;x-amz-content-sha256;x-amz-date\n$contentHash';
    final scope = '$dateStamp/${_s3Config.region}/s3/aws4_request';
    final stringToSign = 'AWS4-HMAC-SHA256\n$amzDate\n$scope\n${sha256.convert(utf8.encode(canonicalRequest))}';

    final signingKey = _deriveSigningKey(dateStamp);
    final signature = Hmac(sha256, signingKey).convert(utf8.encode(stringToSign)).toString();

    return {
      'host': host,
      'x-amz-date': amzDate,
      'x-amz-content-sha256': contentHash,
      'authorization': 'AWS4-HMAC-SHA256 Credential=${_s3Config.accessKey}/$scope, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=$signature',
    };
  }

  List<int> _deriveSigningKey(String dateStamp) {
    final kDate = Hmac(sha256, utf8.encode('AWS4${_s3Config.secretKey}')).convert(utf8.encode(dateStamp)).bytes;
    final kRegion = Hmac(sha256, kDate).convert(utf8.encode(_s3Config.region)).bytes;
    final kService = Hmac(sha256, kRegion).convert(utf8.encode('s3')).bytes;
    return Hmac(sha256, kService).convert(utf8.encode('aws4_request')).bytes;
  }

  void _scheduleNextBackup() {
    if (!_gdriveConfig.enabled && !_s3Config.enabled) return;

    final frequency = _s3Config.enabled ? _s3Config.frequency : _gdriveConfig.frequency;
    final duration = switch (frequency) {
      'hourly' => const Duration(hours: 1),
      'daily' => const Duration(hours: 24),
      'weekly' => const Duration(days: 7),
      _ => const Duration(hours: 24),
    };

    _scheduleTimer = Timer(duration, () {
      runBackupNow();
      _scheduleNextBackup();
    });
  }

  void _setStatus(BackupStatus s) {
    _status = s;
    _statusController.add(s);
  }

  void dispose() {
    _scheduleTimer?.cancel();
    _statusController.close();
    _logController.close();
  }
}
