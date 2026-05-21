import 'dart:convert';

import 'package:http/http.dart' as http;

class BillingConfig {
  final bool enabled;
  final String webhookUrl;
  final String apiKey;
  final Map<String, String> headers;
  final String method;

  const BillingConfig({
    this.enabled = false,
    this.webhookUrl = '',
    this.apiKey = '',
    this.headers = const {},
    this.method = 'POST',
  });

  factory BillingConfig.fromMap(Map<String, dynamic> map) => BillingConfig(
    enabled: map['enabled'] as bool? ?? false,
    webhookUrl: map['webhookUrl'] as String? ?? '',
    apiKey: map['apiKey'] as String? ?? '',
    headers: (map['headers'] as Map?)?.cast<String, String>() ?? {},
    method: map['method'] as String? ?? 'POST',
  );

  bool get isConfigured => enabled && webhookUrl.isNotEmpty;
}

class BillingService {
  final BillingConfig config;

  BillingService(this.config);

  Future<bool> postWeighment(Map<String, dynamic> weighmentData) async {
    if (!config.isConfigured) return false;

    final payload = {
      'event': 'weighment_complete',
      'timestamp': DateTime.now().toIso8601String(),
      'data': {
        'rstNumber': weighmentData['rstNumber'],
        'vehicleNumber': weighmentData['vehicleNumber'],
        'customerName': weighmentData['customerName'],
        'customerPhone': weighmentData['customerPhone'],
        'material': weighmentData['material'],
        'grossWeight': weighmentData['grossWeight'],
        'tareWeight': weighmentData['tareWeight'],
        'netWeight': weighmentData['netWeight'],
        'direction': weighmentData['direction'],
        'operatorName': weighmentData['operatorName'],
      },
    };

    final requestHeaders = <String, String>{
      'Content-Type': 'application/json',
      ...config.headers,
    };
    if (config.apiKey.isNotEmpty) {
      requestHeaders['X-API-Key'] = config.apiKey;
    }

    try {
      final uri = Uri.parse(config.webhookUrl);
      final http.Response response;
      if (config.method == 'PUT') {
        response = await http.put(uri, headers: requestHeaders, body: jsonEncode(payload));
      } else {
        response = await http.post(uri, headers: requestHeaders, body: jsonEncode(payload));
      }
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
