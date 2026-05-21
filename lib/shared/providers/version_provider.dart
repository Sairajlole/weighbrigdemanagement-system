import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';

enum VersionStatus { upToDate, updateAvailable, updateRequired, unknown }

class VersionInfo {
  final VersionStatus status;
  final String currentVersion;
  final String? latestVersion;
  final String? minimumVersion;
  final String? updateUrl;
  final String? releaseNotes;

  const VersionInfo({
    this.status = VersionStatus.unknown,
    this.currentVersion = '',
    this.latestVersion,
    this.minimumVersion,
    this.updateUrl,
    this.releaseNotes,
  });
}

final versionProvider = FutureProvider<VersionInfo>((ref) async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    final current = packageInfo.version;

    final db = ref.read(firestoreProvider);
    final doc = await db.doc('global/app_version').get();

    if (!doc.exists) {
      return VersionInfo(status: VersionStatus.upToDate, currentVersion: current);
    }

    final data = doc.data()!;
    final latest = data['latestVersion'] as String? ?? current;
    final minimum = data['minimumVersion'] as String?;
    final updateUrl = data['updateUrl'] as String?;
    final releaseNotes = data['releaseNotes'] as String?;

    final status = _compareVersions(current, latest, minimum);

    return VersionInfo(
      status: status,
      currentVersion: current,
      latestVersion: latest,
      minimumVersion: minimum,
      updateUrl: updateUrl,
      releaseNotes: releaseNotes,
    );
  } catch (_) {
    return const VersionInfo(status: VersionStatus.unknown, currentVersion: '0.0.0');
  }
});

VersionStatus _compareVersions(String current, String latest, String? minimum) {
  if (minimum != null && _versionToInt(current) < _versionToInt(minimum)) {
    return VersionStatus.updateRequired;
  }
  if (_versionToInt(current) < _versionToInt(latest)) {
    return VersionStatus.updateAvailable;
  }
  return VersionStatus.upToDate;
}

int _versionToInt(String version) {
  final parts = version.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  while (parts.length < 3) {
    parts.add(0);
  }
  return parts[0] * 10000 + parts[1] * 100 + parts[2];
}
