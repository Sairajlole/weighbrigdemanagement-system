import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:weighbridgemanagement/core/enums/weighment_enums.dart';

class Weighment {
  final String id;
  final String sessionId;
  final String rstNumber;
  final String deviceId;
  final String weighbridgeId;

  // Vehicle
  final String vehicleNumber;
  final String? rfidTag;

  // Customer
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String? customerAddress;

  // Material
  final String material;
  final MaterialDetectionResult? materialDetectionResult;
  final double? materialConfidence;

  // Weights
  final double? grossWeight;
  final double? tareWeight;
  final double? netWeight;
  final DateTime? grossDateTime;
  final DateTime? tareDateTime;

  // Operator
  final String operatorId;
  final String operatorName;
  final UserRole operatorRole;

  // Security
  final String? ipAddress;

  // Camera snapshots paths
  final Map<String, dynamic>? cameraSnapshots;

  // Status
  final WeighmentStatus status;
  final WeighmentStep currentStep;

  // Timestamps
  final DateTime createdAt;
  final DateTime updatedAt;

  // PDF
  final String? pdfPath;
  final String? pdfDrivePath;

  Weighment({
    required this.id,
    required this.sessionId,
    required this.rstNumber,
    required this.deviceId,
    required this.weighbridgeId,
    required this.vehicleNumber,
    this.rfidTag,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    this.customerAddress,
    required this.material,
    this.materialDetectionResult,
    this.materialConfidence,
    this.grossWeight,
    this.tareWeight,
    this.netWeight,
    this.grossDateTime,
    this.tareDateTime,
    required this.operatorId,
    required this.operatorName,
    required this.operatorRole,
    this.ipAddress,
    this.cameraSnapshots,
    required this.status,
    required this.currentStep,
    required this.createdAt,
    required this.updatedAt,
    this.pdfPath,
    this.pdfDrivePath,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'sessionId': sessionId,
      'rstNumber': rstNumber,
      'deviceId': deviceId,
      'weighbridgeId': weighbridgeId,
      'vehicleNumber': vehicleNumber,
      'rfidTag': rfidTag,
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerAddress': customerAddress,
      'material': material,
      'materialDetectionResult': materialDetectionResult?.name,
      'materialConfidence': materialConfidence,
      'grossWeight': grossWeight,
      'tareWeight': tareWeight,
      'netWeight': netWeight,
      'grossDateTime': grossDateTime != null ? Timestamp.fromDate(grossDateTime!) : null,
      'tareDateTime': tareDateTime != null ? Timestamp.fromDate(tareDateTime!) : null,
      'operatorId': operatorId,
      'operatorName': operatorName,
      'operatorRole': operatorRole.name,
      'ipAddress': ipAddress,
      'cameraSnapshots': cameraSnapshots,
      'status': status.name,
      'currentStep': currentStep.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'pdfPath': pdfPath,
      'pdfDrivePath': pdfDrivePath,
    };
  }

  factory Weighment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Weighment(
      id: doc.id,
      sessionId: data['sessionId'] ?? '',
      rstNumber: data['rstNumber'] ?? '',
      deviceId: data['deviceId'] ?? '',
      weighbridgeId: data['weighbridgeId'] ?? '',
      vehicleNumber: data['vehicleNumber'] ?? '',
      rfidTag: data['rfidTag'],
      customerId: data['customerId'] ?? '',
      customerName: data['customerName'] ?? '',
      customerPhone: data['customerPhone'] ?? '',
      customerAddress: data['customerAddress'],
      material: data['material'] ?? '',
      materialDetectionResult: data['materialDetectionResult'] != null
          ? MaterialDetectionResult.values.byName(data['materialDetectionResult'])
          : null,
      materialConfidence: (data['materialConfidence'] as num?)?.toDouble(),
      grossWeight: (data['grossWeight'] as num?)?.toDouble(),
      tareWeight: (data['tareWeight'] as num?)?.toDouble(),
      netWeight: (data['netWeight'] as num?)?.toDouble(),
      grossDateTime: (data['grossDateTime'] as Timestamp?)?.toDate(),
      tareDateTime: (data['tareDateTime'] as Timestamp?)?.toDate(),
      operatorId: data['operatorId'] ?? '',
      operatorName: data['operatorName'] ?? '',
      operatorRole: UserRole.values.byName(data['operatorRole'] ?? 'operator'),
      ipAddress: data['ipAddress'],
      cameraSnapshots: data['cameraSnapshots'] as Map<String, dynamic>?,
      status: WeighmentStatus.values.byName(data['status'] ?? 'pending'),
      currentStep: WeighmentStep.values.byName(data['currentStep'] ?? 'retryQueue'),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      pdfPath: data['pdfPath'],
      pdfDrivePath: data['pdfDrivePath'],
    );
  }

  Weighment copyWith({
    String? sessionId,
    String? rstNumber,
    String? vehicleNumber,
    String? rfidTag,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    String? material,
    MaterialDetectionResult? materialDetectionResult,
    double? materialConfidence,
    double? grossWeight,
    double? tareWeight,
    double? netWeight,
    DateTime? grossDateTime,
    DateTime? tareDateTime,
    String? operatorId,
    String? operatorName,
    UserRole? operatorRole,
    String? ipAddress,
    Map<String, dynamic>? cameraSnapshots,
    WeighmentStatus? status,
    WeighmentStep? currentStep,
    DateTime? updatedAt,
    String? pdfPath,
    String? pdfDrivePath,
  }) {
    return Weighment(
      id: id,
      sessionId: sessionId ?? this.sessionId,
      rstNumber: rstNumber ?? this.rstNumber,
      deviceId: deviceId,
      weighbridgeId: weighbridgeId,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      rfidTag: rfidTag ?? this.rfidTag,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerAddress: customerAddress ?? this.customerAddress,
      material: material ?? this.material,
      materialDetectionResult: materialDetectionResult ?? this.materialDetectionResult,
      materialConfidence: materialConfidence ?? this.materialConfidence,
      grossWeight: grossWeight ?? this.grossWeight,
      tareWeight: tareWeight ?? this.tareWeight,
      netWeight: netWeight ?? this.netWeight,
      grossDateTime: grossDateTime ?? this.grossDateTime,
      tareDateTime: tareDateTime ?? this.tareDateTime,
      operatorId: operatorId ?? this.operatorId,
      operatorName: operatorName ?? this.operatorName,
      operatorRole: operatorRole ?? this.operatorRole,
      ipAddress: ipAddress ?? this.ipAddress,
      cameraSnapshots: cameraSnapshots ?? this.cameraSnapshots,
      status: status ?? this.status,
      currentStep: currentStep ?? this.currentStep,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pdfPath: pdfPath ?? this.pdfPath,
      pdfDrivePath: pdfDrivePath ?? this.pdfDrivePath,
    );
  }
}
