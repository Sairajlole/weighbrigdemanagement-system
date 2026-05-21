import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';

/// Scoping: where each collection lives in the hierarchy.
enum CollectionScope {
  weighbridge, // companies/{c}/sites/{s}/weighbridges/{w}/...
  site, // companies/{c}/sites/{s}/...
  company, // companies/{c}/...
}

class FirestorePaths {
  final FirebaseFirestore _db;
  final SiteContext _ctx;

  FirestorePaths(this._db, this._ctx);

  FirebaseFirestore get firestore => _db;
  bool get isConfigured => _ctx.isConfigured;
  SiteContext get context => _ctx;

  WriteBatch batch() => _db.batch();

  // ─── Path builders ─────────────────────────────────────────────

  String get _companyPrefix => 'companies/${_ctx.companyId}';
  String get _sitePrefix => '$_companyPrefix/sites/${_ctx.siteId}';
  String get _weighbridgePrefix =>
      '$_sitePrefix/weighbridges/${_ctx.weighbridgeId}';

  // ─── Per-weighbridge collections ──────────────────────────────

  CollectionReference<Map<String, dynamic>> get weighments =>
      _db.collection('$_weighbridgePrefix/weighments');

  CollectionReference<Map<String, dynamic>> get queues =>
      _db.collection('$_weighbridgePrefix/queues');

  CollectionReference<Map<String, dynamic>> get counters =>
      _db.collection('$_weighbridgePrefix/counters');

  CollectionReference<Map<String, dynamic>> get gateEvents =>
      _db.collection('$_weighbridgePrefix/gateEvents');

  CollectionReference<Map<String, dynamic>> get gateCommands =>
      _db.collection('$_weighbridgePrefix/gateCommands');

  CollectionReference<Map<String, dynamic>> get cameras =>
      _db.collection('$_weighbridgePrefix/cameras');

  DocumentReference<Map<String, dynamic>> weighbridgeSetting(String id) =>
      _db.doc('$_weighbridgePrefix/settings/$id');

  // ─── Per-site collections ─────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get operators =>
      _db.collection('$_companyPrefix/operators');

  DocumentReference<Map<String, dynamic>> siteSetting(String id) =>
      _db.doc('$_sitePrefix/settings/$id');

  DocumentReference<Map<String, dynamic>> companySetting(String id) =>
      _db.doc('$_companyPrefix/settings/$id');

  // ─── Company-wide collections ─────────────────────────────────

  CollectionReference<Map<String, dynamic>> get customers =>
      _db.collection('$_companyPrefix/customers');

  CollectionReference<Map<String, dynamic>> get customersDeleted =>
      _db.collection('$_companyPrefix/customers_deleted');

  CollectionReference<Map<String, dynamic>> get customerMerges =>
      _db.collection('$_companyPrefix/customer_merges');

  CollectionReference<Map<String, dynamic>> get materials =>
      _db.collection('$_weighbridgePrefix/materials');

  CollectionReference<Map<String, dynamic>> get vehicles =>
      _db.collection('$_companyPrefix/vehicles');

  CollectionReference<Map<String, dynamic>> get auditLog =>
      _db.collection('$_companyPrefix/auditLog');

  CollectionReference<Map<String, dynamic>> get notifications =>
      _db.collection('$_companyPrefix/notifications');

  CollectionReference<Map<String, dynamic>> get trainingData =>
      _db.collection('$_companyPrefix/training_data');

  // ─── Settings helpers ─────────────────────────────────────────

  /// Weighbridge-scoped settings: scale, camerasAi, gateControl
  DocumentReference<Map<String, dynamic>> get scaleSettings =>
      weighbridgeSetting('scale');

  DocumentReference<Map<String, dynamic>> get camerasAiSettings =>
      weighbridgeSetting('camerasAi');

  DocumentReference<Map<String, dynamic>> get gateControlSettings =>
      weighbridgeSetting('gateControl');

  DocumentReference<Map<String, dynamic>> get printingSettings =>
      weighbridgeSetting('printing');

  /// Company-scoped settings (shared across all PCs/sites)
  DocumentReference<Map<String, dynamic>> get securitySettings =>
      companySetting('security');

  DocumentReference<Map<String, dynamic>> get integrationsSettings =>
      companySetting('integrations');

  DocumentReference<Map<String, dynamic>> get generalSettings =>
      companySetting('general');

  DocumentReference<Map<String, dynamic>> get generalDocsSettings =>
      companySetting('general_docs');

  DocumentReference<Map<String, dynamic>> get dataBackupSettings =>
      companySetting('dataBackup');

  DocumentReference<Map<String, dynamic>> get customFieldsSettings =>
      companySetting('customFields');

  DocumentReference<Map<String, dynamic>> get adminProfileSettings =>
      companySetting('adminProfile');

  /// Site-scoped settings (per physical location)
  DocumentReference<Map<String, dynamic>> get notificationsSettings =>
      siteSetting('notifications');

  DocumentReference<Map<String, dynamic>> get appearanceSettings =>
      siteSetting('appearance');

  /// Weighbridge-scoped settings (per individual scale/PC)
  DocumentReference<Map<String, dynamic>> get materialsSettings =>
      weighbridgeSetting('materials');

  /// Site settings collection (for iterating all settings docs)
  CollectionReference<Map<String, dynamic>> get siteSettings =>
      _db.collection('$_sitePrefix/settings');

  /// Weighbridge settings collection
  CollectionReference<Map<String, dynamic>> get weighbridgeSettings =>
      _db.collection('$_weighbridgePrefix/settings');

  // ─── Print log (per weighbridge) ─────────────────────────────

  CollectionReference<Map<String, dynamic>> get printLog =>
      _db.collection('$_weighbridgePrefix/print_log');

  // ─── Sessions (per site) ──────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get sessions =>
      _db.collection('$_sitePrefix/sessions');

  // ─── Legacy flat fallback (for migration period) ──────────────

  /// Resolve a collection by name (for dynamic iteration in backup/restore).
  CollectionReference<Map<String, dynamic>>? collectionByName(String name) {
    return switch (name) {
      'customers' => customers,
      'materials' => materials,
      'vehicles' => vehicles,
      'operators' => operators,
      'weighments' => weighments,
      'auditLog' => auditLog,
      'notifications' => notifications,
      'customers_deleted' => customersDeleted,
      'customer_merges' => customerMerges,
      'queues' => queues,
      'counters' => counters,
      'cameras' => cameras,
      'gateEvents' => gateEvents,
      'gateCommands' => gateCommands,
      _ => null,
    };
  }

  /// Returns the flat (non-hierarchical) collection for backward compat.
  /// Use only during migration transition.
  CollectionReference<Map<String, dynamic>> flat(String name) =>
      _db.collection(name);
}

final firestorePathsProvider = Provider<FirestorePaths>((ref) {
  final db = ref.watch(firestoreProvider);
  final ctx = ref.watch(siteContextProvider);
  return FirestorePaths(db, ctx);
});
