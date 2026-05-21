import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class SheetsConfig {
  final bool enabled;
  final String spreadsheetId;
  final String sheetName;
  final String credentialsPath;
  final List<String> columnOrder;

  const SheetsConfig({
    this.enabled = false,
    this.spreadsheetId = '',
    this.sheetName = 'Weighments',
    this.credentialsPath = '',
    this.columnOrder = const [
      'rstNumber', 'vehicleNumber', 'customerName', 'material',
      'grossWeight', 'tareWeight', 'netWeight', 'direction',
      'grossDateTime', 'tareDateTime', 'operatorName',
    ],
  });

  factory SheetsConfig.fromMap(Map<String, dynamic> map) => SheetsConfig(
    enabled: map['enabled'] as bool? ?? false,
    spreadsheetId: map['spreadsheetId'] as String? ?? '',
    sheetName: map['sheetName'] as String? ?? 'Weighments',
    credentialsPath: map['credentialsPath'] as String? ?? '',
    columnOrder: (map['columnOrder'] as List?)?.cast<String>() ?? const [
      'rstNumber', 'vehicleNumber', 'customerName', 'material',
      'grossWeight', 'tareWeight', 'netWeight', 'direction',
      'grossDateTime', 'tareDateTime', 'operatorName',
    ],
  );

  bool get isConfigured => enabled && spreadsheetId.isNotEmpty;
}

class GoogleSheetsService {
  final SheetsConfig config;
  String? _accessToken;
  DateTime? _tokenExpiry;

  GoogleSheetsService(this.config);

  Future<bool> appendRow(Map<String, dynamic> weighmentData) async {
    if (!config.isConfigured) return false;

    final token = await _getAccessToken();
    if (token == null) return false;

    final values = config.columnOrder.map((col) {
      final val = weighmentData[col];
      if (val == null) return '';
      if (val is DateTime) return val.toIso8601String();
      return val.toString();
    }).toList();

    final url = 'https://sheets.googleapis.com/v4/spreadsheets/${config.spreadsheetId}/values/${config.sheetName}!A:Z:append?valueInputOption=USER_ENTERED';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'values': [values],
        }),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _getAccessToken() async {
    if (_accessToken != null && _tokenExpiry != null && DateTime.now().isBefore(_tokenExpiry!)) {
      return _accessToken;
    }

    try {
      final credFile = File(config.credentialsPath);
      if (!await credFile.exists()) return null;

      final creds = jsonDecode(await credFile.readAsString()) as Map<String, dynamic>;
      final clientEmail = creds['client_email'] as String?;
      final privateKey = creds['private_key'] as String?;
      if (clientEmail == null || privateKey == null) return null;

      // Use gcloud CLI token as bridge until googleapis_auth is added
      final result = await Process.run('gcloud', ['auth', 'print-access-token']);
      if (result.exitCode == 0) {
        _accessToken = (result.stdout as String).trim();
        _tokenExpiry = DateTime.now().add(const Duration(minutes: 55));
        return _accessToken;
      }
    } catch (_) {}
    return null;
  }
}
