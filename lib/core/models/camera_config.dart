import 'package:cloud_firestore/cloud_firestore.dart';
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

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'purpose': purpose.name,
        'sourceType': sourceType.name,
        'streamUrl': streamUrl,
        'enabled': enabled,
        'showOnWeighmentScreen': showOnWeighmentScreen,
        'gridOrder': gridOrder,
      };

  factory CameraConfig.fromFirestore(DocumentSnapshot doc) {
    final map = doc.data() as Map<String, dynamic>;
    return CameraConfig(
      id: doc.id,
      name: map['name'] ?? '',
      purpose: CameraPurpose.values.byName(map['purpose'] ?? 'platformTopView'),
      sourceType: CameraSourceType.values.byName(map['sourceType'] ?? 'rtsp'),
      streamUrl: map['streamUrl'] ?? '',
      enabled: map['enabled'] ?? true,
      showOnWeighmentScreen: map['showOnWeighmentScreen'] ?? true,
      gridOrder: map['gridOrder'] ?? 0,
    );
  }

  CameraConfig copyWith({
    String? name,
    CameraPurpose? purpose,
    CameraSourceType? sourceType,
    String? streamUrl,
    bool? enabled,
    bool? showOnWeighmentScreen,
    int? gridOrder,
  }) =>
      CameraConfig(
        id: id,
        name: name ?? this.name,
        purpose: purpose ?? this.purpose,
        sourceType: sourceType ?? this.sourceType,
        streamUrl: streamUrl ?? this.streamUrl,
        enabled: enabled ?? this.enabled,
        showOnWeighmentScreen: showOnWeighmentScreen ?? this.showOnWeighmentScreen,
        gridOrder: gridOrder ?? this.gridOrder,
      );

  static List<CameraConfig> defaults() => [
        CameraConfig(id: '', name: 'Front Gate', purpose: CameraPurpose.vehicleNumberPlate, sourceType: CameraSourceType.rtsp, streamUrl: '', gridOrder: 0),
        CameraConfig(id: '', name: 'Platform Top', purpose: CameraPurpose.platformTopView, sourceType: CameraSourceType.rtsp, streamUrl: '', gridOrder: 1),
        CameraConfig(id: '', name: 'Left Side', purpose: CameraPurpose.platformLeftView, sourceType: CameraSourceType.rtsp, streamUrl: '', gridOrder: 2),
        CameraConfig(id: '', name: 'Right Side', purpose: CameraPurpose.platformRightView, sourceType: CameraSourceType.rtsp, streamUrl: '', gridOrder: 3),
      ];
}

enum CameraSourceType { rtsp, http, usb }
