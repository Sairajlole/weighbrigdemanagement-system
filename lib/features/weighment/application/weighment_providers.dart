import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';

// ─── ANPR Detection Overlay ─────────────────────────────────────────────────

class AnprOverlay {
  final String cameraKey;
  final List<double> bbox;
  final String plateText;
  final double confidence;
  final String plateType;
  final bool srApplied;
  final String plateCropB64;
  final String plateBgColor;

  const AnprOverlay({
    required this.cameraKey,
    required this.bbox,
    required this.plateText,
    required this.confidence,
    this.plateType = 'unknown',
    this.srApplied = false,
    this.plateCropB64 = '',
    this.plateBgColor = '#FFFFFF',
  });

  bool get hasDetection => plateText.isNotEmpty && confidence > 0.3;
  bool get hasLiveBbox => bbox.length == 4 && (bbox[2] - bbox[0]) > 0.02 && (bbox[3] - bbox[1]) > 0.01;
  bool get hasCrop => plateCropB64.isNotEmpty;
}

final anprDetectionOverlayProvider = StateProvider<Map<String, AnprOverlay>>((ref) => {});
final anprScanningProvider = StateProvider<bool>((ref) => false);
final anprRescanTriggerProvider = StateProvider<int>((ref) => 0);

// ─── Panel Collapse State ─────────────────────────────────────────────────────

final pendingPanelCollapsedProvider = StateProvider<bool>((ref) => false);
final camerasPanelCollapsedProvider = StateProvider<bool>((ref) => false);

// ─── Customer Face Auto-Detect ────────────────────────────────────────────────

class CustomerFaceCandidate {
  final String customerId;
  final String name;
  final String phone;
  final double confidence;

  const CustomerFaceCandidate({
    required this.customerId,
    required this.name,
    required this.phone,
    required this.confidence,
  });
}

class CustomerFaceState {
  final bool detected;
  final bool isKnown;
  final bool isAmbiguous;
  final String? customerId;
  final String? name;
  final String? phone;
  final String? email;
  final String? address;
  final double confidence;
  final List<double>? embedding;
  final String? faceCropB64;
  final List<CustomerFaceCandidate> candidates;
  final bool scanning;
  final bool enabled;

  const CustomerFaceState({
    this.detected = false,
    this.isKnown = false,
    this.isAmbiguous = false,
    this.customerId,
    this.name,
    this.phone,
    this.email,
    this.address,
    this.confidence = 0,
    this.embedding,
    this.faceCropB64,
    this.candidates = const [],
    this.scanning = false,
    this.enabled = true,
  });

  CustomerFaceState copyWith({
    bool? detected,
    bool? isKnown,
    bool? isAmbiguous,
    String? customerId,
    String? name,
    String? phone,
    String? email,
    String? address,
    double? confidence,
    List<double>? embedding,
    String? faceCropB64,
    List<CustomerFaceCandidate>? candidates,
    bool? scanning,
    bool? enabled,
  }) => CustomerFaceState(
    detected: detected ?? this.detected,
    isKnown: isKnown ?? this.isKnown,
    isAmbiguous: isAmbiguous ?? this.isAmbiguous,
    customerId: customerId ?? this.customerId,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    address: address ?? this.address,
    confidence: confidence ?? this.confidence,
    embedding: embedding ?? this.embedding,
    faceCropB64: faceCropB64 ?? this.faceCropB64,
    candidates: candidates ?? this.candidates,
    scanning: scanning ?? this.scanning,
    enabled: enabled ?? this.enabled,
  );

  static const empty = CustomerFaceState();

  CustomerFaceState cleared() => const CustomerFaceState(enabled: true);
}

final customerFaceProvider = StateProvider<CustomerFaceState>((ref) => CustomerFaceState.empty);

class CustomerCameraFeed {
  final int? textureId;
  final int width;
  final int height;
  final String? ipCameraKey;

  const CustomerCameraFeed({this.textureId, this.width = 960, this.height = 540, this.ipCameraKey});
  static const empty = CustomerCameraFeed();
  bool get active => textureId != null || ipCameraKey != null;
  bool get isIpCamera => ipCameraKey != null;
}

final customerCameraFeedProvider = StateProvider<CustomerCameraFeed>((ref) => CustomerCameraFeed.empty);

final pendingWeighmentsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.weighments
      .where('status', isEqualTo: 'awaitingTare')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

final allWeighmentsForPrintProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.weighments
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots()
      .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

final customerNamesProvider = StreamProvider<List<String>>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.customers.orderBy('name').snapshots().map(
    (snap) => snap.docs
        .map((d) => d.data()['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList(),
  );
});

final customerDetailProvider = FutureProvider.family<Map<String, dynamic>?, String>((ref, name) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return null;
  final snap = await paths.customers.where('name', isEqualTo: name).limit(1).get();
  if (snap.docs.isEmpty) return null;
  return snap.docs.first.data();
});

final materialsListProvider = StreamProvider<List<String>>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.materials.orderBy('name').snapshots().map(
    (snap) => snap.docs
        .map((d) => d.data()['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList(),
  );
});

final materialAllowOtherProvider = FutureProvider<bool>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return true;
  try {
    final doc = await paths.materialsSettings.get();
    if (!doc.exists) return true;
    return doc.data()?['allowOther'] as bool? ?? true;
  } catch (_) {
    return true;
  }
});

final materialDirectionMapProvider = StreamProvider<Map<String, String>>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const Stream.empty();
  return paths.materials.snapshots().map((snap) {
    final map = <String, String>{};
    for (final doc in snap.docs) {
      final name = doc.data()['name'] as String? ?? '';
      final dir = doc.data()['defaultDirection'] as String?;
      if (name.isNotEmpty && dir != null && dir.isNotEmpty) {
        map[name] = dir;
      }
    }
    return map;
  });
});

final customFieldsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return [];
  final doc = await paths.customFieldsSettings.get();
  if (!doc.exists) return [];
  final fields = doc.data()?['fields'] as List<dynamic>?;
  if (fields == null) return [];
  return fields.cast<Map<String, dynamic>>().where((f) => f['enabled'] == true).toList();
});

final nextRstProvider = FutureProvider<String>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return '0001';
  final counterRef = paths.firestore.doc(
    'companies/${paths.context.companyId}/sites/${paths.context.siteId}/weighbridges/${paths.context.weighbridgeId}/counters/weighments',
  );
  final result = await paths.firestore.runTransaction<int>((tx) async {
    final doc = await tx.get(counterRef);
    final current = doc.exists ? (doc.data()?['lastRst'] as int? ?? 0) : 0;
    final next = current + 1;
    tx.set(counterRef, {'lastRst': next}, SetOptions(merge: true));
    return next;
  });
  return result.toString();
});

// ─── Weighment Mode Config (per weighbridge) ────────────────────────────────

enum WeighmentEntryMode { singleEntry, multiEntry }

class WeighmentModeConfig {
  final WeighmentEntryMode entryMode;
  final bool allowCrossWeighbridge;
  final double minWeightDiff;
  final bool lockFieldsOnSecondWeigh;

  const WeighmentModeConfig({
    this.entryMode = WeighmentEntryMode.multiEntry,
    this.allowCrossWeighbridge = false,
    this.minWeightDiff = 0,
    this.lockFieldsOnSecondWeigh = true,
  });

  factory WeighmentModeConfig.fromMap(Map<String, dynamic> data) {
    return WeighmentModeConfig(
      entryMode: data['entryMode'] == 'singleEntry'
          ? WeighmentEntryMode.singleEntry
          : WeighmentEntryMode.multiEntry,
      allowCrossWeighbridge: data['allowCrossWeighbridge'] as bool? ?? false,
      minWeightDiff: (data['minWeightDiff'] as num?)?.toDouble() ?? 0,
      lockFieldsOnSecondWeigh: data['lockFieldsOnSecondWeigh'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'entryMode': entryMode == WeighmentEntryMode.singleEntry ? 'singleEntry' : 'multiEntry',
    'allowCrossWeighbridge': allowCrossWeighbridge,
    'minWeightDiff': minWeightDiff,
    'lockFieldsOnSecondWeigh': lockFieldsOnSecondWeigh,
  };
}

final weighmentModeConfigProvider = FutureProvider<WeighmentModeConfig>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) return const WeighmentModeConfig();
  try {
    final doc = await paths.weighbridgeSetting('weighmentMode').get();
    if (doc.exists && doc.data() != null) {
      return WeighmentModeConfig.fromMap(doc.data()!);
    }
  } catch (_) {}
  return const WeighmentModeConfig();
});

// Form font scale: compact (0.6) or regular (0.85)
final formScaleProvider = StateProvider<double>((ref) => 0.85);
