import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CloudFunctionsService {
  static const _projectId = 'tulanam';
  static const _region = 'asia-south1';

  /// Server-issued session token (set after loginUser, cleared on logout).
  /// Attached to every callable so secured functions can authorize the caller.
  static String? sessionToken;

  static bool get _useHttp => Platform.isWindows || Platform.isLinux;

  /// Calls a Firebase Cloud Function by name.
  /// On Windows/Linux, uses direct HTTP since the cloud_functions plugin
  /// has no platform channel for those platforms.
  /// On iOS/macOS/Android, uses the standard plugin.
  static Future<Map<String, dynamic>> call(
    String functionName, [
    Map<String, dynamic>? parameters,
  ]) async {
    // Attach the session token so secured callables can authorize the caller.
    // Unsecured callables simply ignore the extra field.
    final params = (sessionToken != null && sessionToken!.isNotEmpty)
        ? {...?parameters, 'sessionToken': sessionToken}
        : parameters;
    if (!_useHttp) {
      final fn = FirebaseFunctions.instanceFor(region: _region).httpsCallable(functionName);
      final result = await fn.call(params);
      return result.data is Map
          ? Map<String, dynamic>.from(result.data as Map)
          : {'data': result.data};
    }

    return _callViaHttp(functionName, params);
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
