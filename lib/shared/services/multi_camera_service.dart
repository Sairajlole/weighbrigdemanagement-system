import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class CameraDevice {
  final String deviceId;
  final String name;
  final String manufacturer;

  const CameraDevice({
    required this.deviceId,
    required this.name,
    required this.manufacturer,
  });
}

class CameraFeed {
  final String sessionId;
  final int textureId;
  final int width;
  final int height;
  final String deviceId;
  final String deviceName;

  const CameraFeed({
    required this.sessionId,
    required this.textureId,
    required this.width,
    required this.height,
    required this.deviceId,
    required this.deviceName,
  });
}

class MultiCameraService {
  static const _channel = MethodChannel('multi_camera');

  static Future<List<CameraDevice>> listDevices() async {
    final result = await _channel.invokeListMethod<Map>('listDevices');
    if (result == null) return [];
    return result.map((m) => CameraDevice(
      deviceId: m['deviceId'] as String? ?? '',
      name: m['name'] as String? ?? '',
      manufacturer: m['manufacturer'] as String? ?? '',
    )).toList();
  }

  static Future<CameraFeed?> start({
    required String sessionId,
    String? deviceId,
    int width = 960,
    int height = 540,
  }) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('start', {
        'sessionId': sessionId,
        'deviceId': deviceId,
        'width': width,
        'height': height,
      });
      if (result == null) return null;
      return CameraFeed(
        sessionId: result['sessionId'] as String,
        textureId: result['textureId'] as int,
        width: result['width'] as int,
        height: result['height'] as int,
        deviceId: result['deviceId'] as String,
        deviceName: result['deviceName'] as String,
      );
    } catch (e) {
      debugPrint('[MultiCamera] start error: $e');
      return null;
    }
  }

  static Future<void> stop(String sessionId) async {
    try {
      await _channel.invokeMethod('stop', {'sessionId': sessionId});
    } catch (_) {}
  }

  static Future<void> stopAll() async {
    try {
      await _channel.invokeMethod('stopAll');
    } catch (_) {}
  }

  static Future<Uint8List?> takePicture(String sessionId) async {
    try {
      final result = await _channel.invokeMethod<Uint8List>('takePicture', {
        'sessionId': sessionId,
      });
      return result;
    } catch (e) {
      debugPrint('[MultiCamera] takePicture error: $e');
      return null;
    }
  }
}
