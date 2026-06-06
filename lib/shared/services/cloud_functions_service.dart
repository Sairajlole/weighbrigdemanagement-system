import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CloudFunctionsService {
  static const _projectId = 'weighbridge-management';
  static const _region = 'us-central1';

  /// Calls a Firebase Cloud Function by name.
  /// On Windows, uses direct HTTP since the cloud_functions plugin
  /// doesn't support Windows desktop (no platform channel).
  /// On other platforms, uses the standard plugin.
  static Future<Map<String, dynamic>> call(
    String functionName, [
    Map<String, dynamic>? parameters,
  ]) async {
    if (!Platform.isWindows) {
      final fn = FirebaseFunctions.instance.httpsCallable(functionName);
      final result = await fn.call(parameters);
      return result.data is Map
          ? Map<String, dynamic>.from(result.data as Map)
          : {'data': result.data};
    }

    return _callViaHttp(functionName, parameters);
  }

  static Future<Map<String, dynamic>> _callViaHttp(
    String functionName,
    Map<String, dynamic>? parameters,
  ) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final url = Uri.parse(
      'https://$_region-$_projectId.cloudfunctions.net/$functionName',
    );

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'data': parameters ?? {}}),
    );

    debugPrint('[CloudFunctions] $functionName → ${response.statusCode}');

    if (response.statusCode != 200) {
      final msg = 'Cloud Function $functionName failed: ${response.statusCode}';
      debugPrint('[CloudFunctions] ERROR: $msg');
      throw CloudFunctionHttpException(response.statusCode, msg);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['result'] is Map
        ? Map<String, dynamic>.from(body['result'] as Map)
        : body;
  }
}

class CloudFunctionHttpException implements Exception {
  final int statusCode;
  final String message;
  CloudFunctionHttpException(this.statusCode, this.message);
  @override
  String toString() => 'CloudFunctionHttpException($statusCode): $message';
}
