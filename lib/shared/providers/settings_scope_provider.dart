import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';

typedef ScopeNames = ({String weighbridge, String site, String company});

/// Lets a settings feature (printing, materials, custom fields) be stored at one
/// of three scopes — this weighbridge, this site, or company-wide — chosen by
/// the admin. The choice itself is stored company-wide (in
/// `companies/{c}/settings/settingsScope`) so every PC agrees on it.
///
/// Reuses [CollectionScope] from the path provider.

extension SettingsScopeLabels on CollectionScope {
  String get label => switch (this) {
        CollectionScope.weighbridge => 'This Weighbridge',
        CollectionScope.site => 'This Site',
        CollectionScope.company => 'Company-wide',
      };

  String get shortLabel => switch (this) {
        CollectionScope.weighbridge => 'Weighbridge',
        CollectionScope.site => 'Site',
        CollectionScope.company => 'Company',
      };
}

CollectionScope parseScope(Object? value, {CollectionScope fallback = CollectionScope.weighbridge}) {
  return switch (value) {
    'site' => CollectionScope.site,
    'company' => CollectionScope.company,
    'weighbridge' => CollectionScope.weighbridge,
    _ => fallback,
  };
}

/// The actual names of the current weighbridge / site / company, so the scope
/// control can read e.g. "WB-1 / HQ / Yash Cotex" instead of generic labels.
final scopeNamesProvider = FutureProvider<ScopeNames>((ref) async {
  final paths = ref.watch(firestorePathsProvider);
  final ctx = ref.watch(siteContextProvider);
  const fallback = (weighbridge: 'This Weighbridge', site: 'This Site', company: 'Company-wide');
  if (!paths.isConfigured) return fallback;
  final db = paths.firestore;
  String nameOf(DocumentSnapshot<Map<String, dynamic>> d, String fb) =>
      (d.data()?['name'] as String?)?.trim().isNotEmpty == true ? (d.data()!['name'] as String).trim() : fb;
  try {
    final company = await db.doc('companies/${ctx.companyId}').get();
    final site = await db.doc('companies/${ctx.companyId}/sites/${ctx.siteId}').get();
    final wb = await db.doc('companies/${ctx.companyId}/sites/${ctx.siteId}/weighbridges/${ctx.weighbridgeId}').get();
    return (
      weighbridge: nameOf(wb, fallback.weighbridge),
      site: nameOf(site, fallback.site),
      company: nameOf(company, fallback.company),
    );
  } catch (_) {
    return fallback;
  }
});

/// The actual name for [scope] from a resolved [names] record.
String scopeName(ScopeNames names, CollectionScope scope) => switch (scope) {
      CollectionScope.weighbridge => names.weighbridge,
      CollectionScope.site => names.site,
      CollectionScope.company => names.company,
    };

/// Resolves the settings document for [feature] at the given [scope].
DocumentReference<Map<String, dynamic>> scopedSettingDoc(
  FirestorePaths paths,
  String feature,
  CollectionScope scope,
) {
  return switch (scope) {
    CollectionScope.weighbridge => paths.weighbridgeSetting(feature),
    CollectionScope.site => paths.siteSetting(feature),
    CollectionScope.company => paths.companySetting(feature),
  };
}

/// Streams the chosen scope for [feature]. [fallback] is the scope where the
/// data lives today, so behaviour is unchanged until the admin picks otherwise.
final settingsScopeProvider = StreamProvider.family<CollectionScope, ({String feature, CollectionScope fallback})>((ref, arg) {
  final paths = ref.watch(firestorePathsProvider);
  if (!paths.isConfigured) {
    return Stream<CollectionScope>.value(arg.fallback);
  }
  return paths.companySetting('settingsScope').snapshots().map(
        (doc) => parseScope(doc.data()?[arg.feature], fallback: arg.fallback),
      );
});

