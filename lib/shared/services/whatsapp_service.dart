import 'dart:convert';

import 'package:http/http.dart' as http;

class WhatsAppConfig {
  final bool enabled;
  final String phoneNumberId;
  final String accessToken;
  final String templateName;
  final List<String> recipientNumbers;
  final bool sendOnComplete;

  const WhatsAppConfig({
    this.enabled = false,
    this.phoneNumberId = '',
    this.accessToken = '',
    this.templateName = 'weighment_complete',
    this.recipientNumbers = const [],
    this.sendOnComplete = true,
  });

  factory WhatsAppConfig.fromMap(Map<String, dynamic> map) => WhatsAppConfig(
    enabled: map['enabled'] as bool? ?? false,
    phoneNumberId: map['phoneNumberId'] as String? ?? '',
    accessToken: map['accessToken'] as String? ?? '',
    templateName: map['templateName'] as String? ?? 'weighment_complete',
    recipientNumbers: (map['recipientNumbers'] as List?)?.cast<String>() ?? [],
    sendOnComplete: map['sendOnComplete'] as bool? ?? true,
  );

  bool get isConfigured => enabled && phoneNumberId.isNotEmpty && accessToken.isNotEmpty;
}

class WhatsAppService {
  final WhatsAppConfig config;
  static const _baseUrl = 'https://graph.facebook.com/v19.0';

  WhatsAppService(this.config);

  Future<bool> sendWeighmentNotification(Map<String, dynamic> weighmentData) async {
    if (!config.isConfigured || !config.sendOnComplete) return false;

    final vehicle = weighmentData['vehicleNumber'] ?? '';
    final net = weighmentData['netWeight']?.toString() ?? '0';
    final material = weighmentData['material'] ?? '';
    final rst = weighmentData['rstNumber'] ?? '';

    bool allSuccess = true;
    for (final recipient in config.recipientNumbers) {
      final success = await _sendTemplate(
        to: recipient,
        parameters: [vehicle, material, '${net}kg', rst],
      );
      if (!success) allSuccess = false;
    }
    return allSuccess;
  }

  Future<bool> sendCustomMessage(String to, String message) async {
    if (!config.isConfigured) return false;

    final url = '$_baseUrl/${config.phoneNumberId}/messages';
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${config.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'messaging_product': 'whatsapp',
          'to': to,
          'type': 'text',
          'text': {'body': message},
        }),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _sendTemplate({required String to, required List<String> parameters}) async {
    final url = '$_baseUrl/${config.phoneNumberId}/messages';
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${config.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'messaging_product': 'whatsapp',
          'to': to,
          'type': 'template',
          'template': {
            'name': config.templateName,
            'language': {'code': 'en'},
            'components': [
              {
                'type': 'body',
                'parameters': parameters.map((p) => {'type': 'text', 'text': p}).toList(),
              },
            ],
          },
        }),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
