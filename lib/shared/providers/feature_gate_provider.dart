import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/license_provider.dart';

final isTrialProvider = Provider<bool>((ref) {
  final license = ref.watch(licenseProvider);
  return license.isTrial && license.isValid;
});

final maxWeighbridgesProvider = Provider<int>((ref) {
  return ref.watch(licenseProvider).maxWeighbridges;
});

final maxSitesProvider = Provider<int>((ref) {
  return ref.watch(licenseProvider).maxSites;
});

final canUseGateControlProvider = Provider<bool>((ref) {
  return ref.watch(hasFeatureProvider('gate_control'));
});

final canUseIpCamerasProvider = Provider<bool>((ref) {
  return ref.watch(hasFeatureProvider('ip_cameras'));
});

final canUseIntegrationsProvider = Provider<bool>((ref) {
  return ref.watch(hasFeatureProvider('integrations'));
});

final canUseAdvancedSecurityProvider = Provider<bool>((ref) {
  return ref.watch(hasFeatureProvider('advanced_security'));
});

final canUseMultiSiteProvider = Provider<bool>((ref) {
  return ref.watch(hasFeatureProvider('multi_site'));
});

final canUseMultiWeighbridgeProvider = Provider<bool>((ref) {
  return ref.watch(hasFeatureProvider('multi_weighbridge'));
});
