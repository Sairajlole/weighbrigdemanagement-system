import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// App version, precise (includes build number) and brief — e.g. `v1.0.0+42`.
/// Resolved once from the platform package metadata and cached.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  final build = info.buildNumber.isNotEmpty ? '+${info.buildNumber}' : '';
  return 'v${info.version}$build';
});
