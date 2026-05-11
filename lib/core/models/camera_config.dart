import 'package:weighbridgemanagement/core/enums/weighment_enums.dart';

class CameraConfig {
  final String id;
  final String name;
  final CameraPurpose purpose;
  final CameraSourceType sourceType;
  final String streamUrl;
  final bool enabled;
  final bool showOnWeighmentScreen;
  final int gridOrder;

  CameraConfig({
    required this.id,
    required this.name,
    required this.purpose,
    required this.sourceType,
    required this.streamUrl,
    this.enabled = true,
    this.showOnWeighmentScreen = true,
    this.gridOrder = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'purpose': purpose.name,
        'sourceType': sourceType.name,
        'streamUrl': streamUrl,
        'enabled': enabled,
        'showOnWeighmentScreen': showOnWeighmentScreen,
        'gridOrder': gridOrder,
      };

  factory CameraConfig.fromMap(Map<String, dynamic> map) => CameraConfig(
        id: map['id'] ?? '',
        name: map['name'] ?? '',
        purpose: CameraPurpose.values.byName(map['purpose'] ?? 'platformTopView'),
        sourceType: CameraSourceType.values.byName(map['sourceType'] ?? 'rtsp'),
        streamUrl: map['streamUrl'] ?? '',
        enabled: map['enabled'] ?? true,
        showOnWeighmentScreen: map['showOnWeighmentScreen'] ?? true,
        gridOrder: map['gridOrder'] ?? 0,
      );
}

enum CameraSourceType { rtsp, http, usb }
