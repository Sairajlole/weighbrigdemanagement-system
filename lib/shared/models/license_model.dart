enum LicenseTier { free, trial, pro }

enum LicenseStatus { active, expired, revoked }

const List<String> proFeatures = [
  'multi_weighbridge',
  'ip_cameras',
  'rtsp',
  'ai_anpr',
  'ai_material',
  'ai_face',
  'gate_control',
  'integrations',
  'advanced_security',
  'multi_site',
];

class License {
  final String key;
  final LicenseTier tier;
  final LicenseStatus status;
  final String? gstin;
  final String? companyId;
  final String? deviceFingerprint;
  final DateTime? activatedAt;
  final DateTime? expiresAt;
  final DateTime? trialStartedAt;
  final DateTime? lastValidatedAt;
  final int maxWeighbridges;
  final int maxSites;
  final List<String> features;

  const License({
    required this.key,
    required this.tier,
    required this.status,
    this.gstin,
    this.companyId,
    this.deviceFingerprint,
    this.activatedAt,
    this.expiresAt,
    this.trialStartedAt,
    this.lastValidatedAt,
    this.maxWeighbridges = 1,
    this.maxSites = 1,
    this.features = const [],
  });

  static const empty = License(key: '', tier: LicenseTier.free, status: LicenseStatus.active);

  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get isValid => status == LicenseStatus.active && !isExpired;
  bool get isFree => tier == LicenseTier.free;
  bool get isPro => tier == LicenseTier.pro;
  bool get isTrial => tier == LicenseTier.trial;

  LicenseTier get effectiveTier => isValid ? tier : LicenseTier.free;
  bool get effectivelyFree => effectiveTier == LicenseTier.free;
  bool get effectivelyPro => effectiveTier == LicenseTier.pro || effectiveTier == LicenseTier.trial;

  bool hasFeature(String feature) => effectivelyPro && features.contains(feature);

  bool get canAddWeighbridge => effectiveTier != LicenseTier.free;
  bool get canAddSite => effectiveTier != LicenseTier.free;

  int get daysRemaining {
    if (expiresAt == null) return -1;
    return expiresAt!.difference(DateTime.now()).inDays;
  }

  int get daysSinceValidation {
    if (lastValidatedAt == null) return 999;
    return DateTime.now().difference(lastValidatedAt!).inDays;
  }

  bool get needsRevalidation => daysSinceValidation > 30;
  bool get isWithinOfflineGrace => daysSinceValidation <= 60;

  License copyWith({
    String? key,
    LicenseTier? tier,
    LicenseStatus? status,
    String? gstin,
    String? companyId,
    String? deviceFingerprint,
    DateTime? activatedAt,
    DateTime? expiresAt,
    DateTime? trialStartedAt,
    DateTime? lastValidatedAt,
    int? maxWeighbridges,
    int? maxSites,
    List<String>? features,
  }) {
    return License(
      key: key ?? this.key,
      tier: tier ?? this.tier,
      status: status ?? this.status,
      gstin: gstin ?? this.gstin,
      companyId: companyId ?? this.companyId,
      deviceFingerprint: deviceFingerprint ?? this.deviceFingerprint,
      activatedAt: activatedAt ?? this.activatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      trialStartedAt: trialStartedAt ?? this.trialStartedAt,
      lastValidatedAt: lastValidatedAt ?? this.lastValidatedAt,
      maxWeighbridges: maxWeighbridges ?? this.maxWeighbridges,
      maxSites: maxSites ?? this.maxSites,
      features: features ?? this.features,
    );
  }

  Map<String, dynamic> toMap() => {
    'key': key,
    'tier': tier.name,
    'status': status.name,
    'gstin': gstin,
    'companyId': companyId,
    'deviceFingerprint': deviceFingerprint,
    'activatedAt': activatedAt?.millisecondsSinceEpoch,
    'expiresAt': expiresAt?.millisecondsSinceEpoch,
    'trialStartedAt': trialStartedAt?.millisecondsSinceEpoch,
    'lastValidatedAt': lastValidatedAt?.millisecondsSinceEpoch,
    'maxWeighbridges': maxWeighbridges,
    'maxSites': maxSites,
    'features': features,
  };

  factory License.fromMap(Map<String, dynamic> map) {
    return License(
      key: map['key'] as String? ?? '',
      tier: LicenseTier.values.firstWhere(
        (t) => t.name == map['tier'],
        orElse: () => LicenseTier.free,
      ),
      status: LicenseStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => LicenseStatus.active,
      ),
      gstin: map['gstin'] as String?,
      companyId: map['companyId'] as String?,
      deviceFingerprint: map['deviceFingerprint'] as String?,
      activatedAt: _parseDateTime(map['activatedAt']),
      expiresAt: _parseDateTime(map['expiresAt']),
      trialStartedAt: _parseDateTime(map['trialStartedAt']),
      lastValidatedAt: _parseDateTime(map['lastValidatedAt']),
      maxWeighbridges: (map['maxWeighbridges'] as num?)?.toInt() ?? 1,
      maxSites: (map['maxSites'] as num?)?.toInt() ?? 1,
      features: (map['features'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is Map && value['_seconds'] != null) {
      return DateTime.fromMillisecondsSinceEpoch((value['_seconds'] as int) * 1000);
    }
    return null;
  }
}
