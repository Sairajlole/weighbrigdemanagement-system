import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';

enum WeighmentDirection { inbound, outbound } // Legacy — kept for Firestore backward compat

enum SessionStatus { active, awaitingSecondWeight, completed, cancelled }

class WeighmentSession {
  final String id;
  final DateTime startedAt;
  final SessionStatus status;

  // Vehicle
  final String vehicleNumber;
  final String? rfidTag;

  // Customer
  final String customerName;
  final String customerAddress;
  final String customerPhone;

  // Material
  final String material;
  final WeighmentDirection direction;

  // Weights
  final double? firstWeight;
  final DateTime? firstWeightAt;
  final double? secondWeight;
  final DateTime? secondWeightAt;
  final double? grossWeight;
  final double? tareWeight;
  final double? netWeight;
  final String firstWeighType; // 'gross' or 'tare'

  // Identifiers
  final String? rstNumber;
  final String? operatorId;
  final String? operatorName;

  // Camera evidence
  final Map<String, String> firstWeightSnapshots;
  final Map<String, String> secondWeightSnapshots;
  final Map<String, String> cameraLabels;

  // AI predictions (for training data)
  final String? anprPrediction;
  final double? anprConfidence;
  final String? plateCropB64;
  final String? materialPrediction;
  final double? materialConfidence;
  final String? driverFaceEmbedding;
  final String? customerFaceEmbedding;
  final String? customerFaceId;

  // Custom fields
  final Map<String, String> customFields;

  // Metadata
  final String? existingDocId;
  final String? deviceId;
  final DateTime? completedAt;

  const WeighmentSession({
    required this.id,
    required this.startedAt,
    this.status = SessionStatus.active,
    this.vehicleNumber = '',
    this.rfidTag,
    this.customerName = '',
    this.customerAddress = '',
    this.customerPhone = '',
    this.material = '',
    this.direction = WeighmentDirection.inbound,
    this.firstWeight,
    this.firstWeightAt,
    this.secondWeight,
    this.secondWeightAt,
    this.grossWeight,
    this.tareWeight,
    this.netWeight,
    this.firstWeighType = 'gross',
    this.rstNumber,
    this.operatorId,
    this.operatorName,
    this.firstWeightSnapshots = const {},
    this.secondWeightSnapshots = const {},
    this.cameraLabels = const {},
    this.anprPrediction,
    this.anprConfidence,
    this.plateCropB64,
    this.materialPrediction,
    this.materialConfidence,
    this.driverFaceEmbedding,
    this.customerFaceEmbedding,
    this.customerFaceId,
    this.customFields = const {},
    this.existingDocId,
    this.deviceId,
    this.completedAt,
  });

  WeighmentSession copyWith({
    String? id,
    DateTime? startedAt,
    SessionStatus? status,
    String? vehicleNumber,
    String? rfidTag,
    String? customerName,
    String? customerAddress,
    String? customerPhone,
    String? material,
    WeighmentDirection? direction,
    double? firstWeight,
    DateTime? firstWeightAt,
    double? secondWeight,
    DateTime? secondWeightAt,
    double? grossWeight,
    double? tareWeight,
    double? netWeight,
    String? firstWeighType,
    String? rstNumber,
    String? operatorId,
    String? operatorName,
    Map<String, String>? firstWeightSnapshots,
    Map<String, String>? secondWeightSnapshots,
    Map<String, String>? cameraLabels,
    String? anprPrediction,
    double? anprConfidence,
    String? plateCropB64,
    String? materialPrediction,
    double? materialConfidence,
    String? driverFaceEmbedding,
    String? customerFaceEmbedding,
    String? customerFaceId,
    Map<String, String>? customFields,
    String? existingDocId,
    String? deviceId,
    DateTime? completedAt,
  }) {
    return WeighmentSession(
      id: id ?? this.id,
      startedAt: startedAt ?? this.startedAt,
      status: status ?? this.status,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      rfidTag: rfidTag ?? this.rfidTag,
      customerName: customerName ?? this.customerName,
      customerAddress: customerAddress ?? this.customerAddress,
      customerPhone: customerPhone ?? this.customerPhone,
      material: material ?? this.material,
      direction: direction ?? this.direction,
      firstWeight: firstWeight ?? this.firstWeight,
      firstWeightAt: firstWeightAt ?? this.firstWeightAt,
      secondWeight: secondWeight ?? this.secondWeight,
      secondWeightAt: secondWeightAt ?? this.secondWeightAt,
      grossWeight: grossWeight ?? this.grossWeight,
      tareWeight: tareWeight ?? this.tareWeight,
      netWeight: netWeight ?? this.netWeight,
      firstWeighType: firstWeighType ?? this.firstWeighType,
      rstNumber: rstNumber ?? this.rstNumber,
      operatorId: operatorId ?? this.operatorId,
      operatorName: operatorName ?? this.operatorName,
      firstWeightSnapshots: firstWeightSnapshots ?? this.firstWeightSnapshots,
      secondWeightSnapshots: secondWeightSnapshots ?? this.secondWeightSnapshots,
      cameraLabels: cameraLabels ?? this.cameraLabels,
      anprPrediction: anprPrediction ?? this.anprPrediction,
      anprConfidence: anprConfidence ?? this.anprConfidence,
      plateCropB64: plateCropB64 ?? this.plateCropB64,
      materialPrediction: materialPrediction ?? this.materialPrediction,
      materialConfidence: materialConfidence ?? this.materialConfidence,
      driverFaceEmbedding: driverFaceEmbedding ?? this.driverFaceEmbedding,
      customerFaceEmbedding: customerFaceEmbedding ?? this.customerFaceEmbedding,
      customerFaceId: customerFaceId ?? this.customerFaceId,
      customFields: customFields ?? this.customFields,
      existingDocId: existingDocId ?? this.existingDocId,
      deviceId: deviceId ?? this.deviceId,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'startedAt': startedAt.toIso8601String(),
      'status': status.name,
      'vehicleNumber': vehicleNumber,
      'rfidTag': rfidTag,
      'customerName': customerName,
      'customerAddress': customerAddress,
      'customerPhone': customerPhone,
      'material': material,
      'direction': direction.name,
      'firstWeight': firstWeight,
      'firstWeightAt': firstWeightAt?.toIso8601String(),
      'secondWeight': secondWeight,
      'secondWeightAt': secondWeightAt?.toIso8601String(),
      'grossWeight': grossWeight,
      'tareWeight': tareWeight,
      'netWeight': netWeight,
      'firstWeighType': firstWeighType,
      'rstNumber': rstNumber,
      'operatorId': operatorId,
      'operatorName': operatorName,
      'firstWeightSnapshots': firstWeightSnapshots,
      'secondWeightSnapshots': secondWeightSnapshots,
      'cameraLabels': cameraLabels,
      'anprPrediction': anprPrediction,
      'anprConfidence': anprConfidence,
      'materialPrediction': materialPrediction,
      'materialConfidence': materialConfidence,
      'driverFaceEmbedding': driverFaceEmbedding,
      'customerFaceEmbedding': customerFaceEmbedding,
      'customerFaceId': customerFaceId,
      'customFields': customFields,
      'existingDocId': existingDocId,
      'deviceId': deviceId,
      'completedAt': completedAt?.toIso8601String(),
    };
  }

  factory WeighmentSession.fromMap(Map<String, dynamic> map) {
    return WeighmentSession(
      id: map['id'] as String,
      startedAt: DateTime.parse(map['startedAt'] as String),
      status: SessionStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => SessionStatus.active,
      ),
      vehicleNumber: map['vehicleNumber'] as String? ?? '',
      rfidTag: map['rfidTag'] as String?,
      customerName: map['customerName'] as String? ?? '',
      customerAddress: map['customerAddress'] as String? ?? '',
      customerPhone: map['customerPhone'] as String? ?? '',
      material: map['material'] as String? ?? '',
      direction: WeighmentDirection.values.firstWhere(
        (d) => d.name == map['direction'],
        orElse: () => WeighmentDirection.inbound,
      ),
      firstWeight: (map['firstWeight'] as num?)?.toDouble(),
      firstWeightAt: map['firstWeightAt'] != null ? DateTime.parse(map['firstWeightAt'] as String) : null,
      secondWeight: (map['secondWeight'] as num?)?.toDouble(),
      secondWeightAt: map['secondWeightAt'] != null ? DateTime.parse(map['secondWeightAt'] as String) : null,
      grossWeight: (map['grossWeight'] as num?)?.toDouble(),
      tareWeight: (map['tareWeight'] as num?)?.toDouble(),
      netWeight: (map['netWeight'] as num?)?.toDouble(),
      firstWeighType: map['firstWeighType'] as String? ?? 'gross',
      rstNumber: map['rstNumber'] as String?,
      operatorId: map['operatorId'] as String?,
      operatorName: map['operatorName'] as String?,
      firstWeightSnapshots: (map['firstWeightSnapshots'] as Map<String, dynamic>?)?.cast<String, String>() ?? {},
      secondWeightSnapshots: (map['secondWeightSnapshots'] as Map<String, dynamic>?)?.cast<String, String>() ?? {},
      cameraLabels: (map['cameraLabels'] as Map<String, dynamic>?)?.cast<String, String>() ?? {},
      anprPrediction: map['anprPrediction'] as String?,
      anprConfidence: (map['anprConfidence'] as num?)?.toDouble(),
      materialPrediction: map['materialPrediction'] as String?,
      materialConfidence: (map['materialConfidence'] as num?)?.toDouble(),
      driverFaceEmbedding: map['driverFaceEmbedding'] as String?,
      customerFaceEmbedding: map['customerFaceEmbedding'] as String?,
      customerFaceId: map['customerFaceId'] as String?,
      customFields: (map['customFields'] as Map<String, dynamic>?)?.cast<String, String>() ?? {},
      existingDocId: map['existingDocId'] as String?,
      deviceId: map['deviceId'] as String?,
      completedAt: map['completedAt'] != null ? DateTime.parse(map['completedAt'] as String) : null,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    final map = <String, dynamic>{
      'vehicleNumber': vehicleNumber,
      'customerName': customerName,
      'customerAddress': customerAddress,
      'customerPhone': customerPhone,
      'material': material,
      'direction': direction.name,
      'firstWeighType': firstWeighType,
      'status': status == SessionStatus.completed ? 'completed' : 'awaitingTare',
      'operatorId': operatorId,
      'operatorName': operatorName,
      'deviceId': deviceId,
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (grossWeight != null) {
      map['grossWeight'] = grossWeight;
    } else if (firstWeight != null && firstWeighType == 'gross') {
      map['grossWeight'] = firstWeight;
    }
    if (tareWeight != null) {
      map['tareWeight'] = tareWeight;
    } else if (firstWeight != null && firstWeighType == 'tare') {
      map['tareWeight'] = firstWeight;
    }
    if (netWeight != null) map['netWeight'] = netWeight;
    if (firstWeightAt != null) map['grossDateTime'] = Timestamp.fromDate(firstWeighType == 'gross' ? firstWeightAt! : secondWeightAt ?? firstWeightAt!);
    if (secondWeightAt != null) map['tareDateTime'] = Timestamp.fromDate(firstWeighType == 'tare' ? firstWeightAt! : secondWeightAt!);
    if (netWeight != null) map['netDateTime'] = Timestamp.fromDate(completedAt ?? DateTime.now());
    if (rstNumber != null) map['rstNumber'] = rstNumber;
    if (rfidTag != null) map['rfidTag'] = rfidTag;

    if (firstWeightSnapshots.isNotEmpty || secondWeightSnapshots.isNotEmpty) {
      map['cameraSnapshots'] = {
        if (firstWeightSnapshots.isNotEmpty) (firstWeighType == 'gross' ? 'gross' : 'tare'): firstWeightSnapshots,
        if (secondWeightSnapshots.isNotEmpty) (firstWeighType == 'gross' ? 'tare' : 'gross'): secondWeightSnapshots,
      };
    }
    if (cameraLabels.isNotEmpty) map['cameraLabels'] = cameraLabels;

    for (final entry in customFields.entries) {
      map['custom_${entry.key}'] = entry.value;
    }

    return map;
  }

  static String _sessionsDir(String? siteId, String? weighbridgeId) {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    if (siteId != null && weighbridgeId != null) {
      return '$home/.weighbridge/sessions/$siteId/$weighbridgeId';
    }
    return '$home/.weighbridge/sessions';
  }

  Future<void> persistToDisk({String? siteId, String? weighbridgeId}) async {
    final dir = Directory(_sessionsDir(siteId, weighbridgeId));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('${dir.path}/$id.json');
    await file.writeAsString(jsonEncode(toMap()));
  }

  static Future<WeighmentSession?> loadFromDisk(String sessionId, {String? siteId, String? weighbridgeId}) async {
    final file = File('${_sessionsDir(siteId, weighbridgeId)}/$sessionId.json');
    if (!file.existsSync()) return null;
    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return WeighmentSession.fromMap(data);
    } catch (_) {
      return null;
    }
  }

  static Future<WeighmentSession?> loadLatestFromDisk({String? siteId, String? weighbridgeId}) async {
    final dir = Directory(_sessionsDir(siteId, weighbridgeId));
    if (!dir.existsSync()) return null;
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
    if (files.isEmpty) return null;
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    try {
      final data = jsonDecode(await files.first.readAsString()) as Map<String, dynamic>;
      final session = WeighmentSession.fromMap(data);
      if (session.status == SessionStatus.active || session.status == SessionStatus.awaitingSecondWeight) {
        return session;
      }
    } catch (_) {}
    return null;
  }

  Future<void> deleteFromDisk({String? siteId, String? weighbridgeId}) async {
    final file = File('${_sessionsDir(siteId, weighbridgeId)}/$id.json');
    if (file.existsSync()) await file.delete();
  }
}
