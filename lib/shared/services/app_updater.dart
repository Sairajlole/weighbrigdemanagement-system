import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/version_provider.dart';
import 'package:weighbridgemanagement/shared/services/platform_service.dart';

enum UpdatePhase { idle, downloading, verifying, ready, applying, error }

@immutable
class UpdateState {
  final UpdatePhase phase;
  final double progress; // 0..1 during download
  final String? version;
  final String? error;
  final String? stagedPath; // verified package on disk, ready to apply
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.progress = 0,
    this.version,
    this.error,
    this.stagedPath,
  });

  UpdateState copyWith({UpdatePhase? phase, double? progress, String? version, String? error, String? stagedPath}) =>
      UpdateState(
        phase: phase ?? this.phase,
        progress: progress ?? this.progress,
        version: version ?? this.version,
        error: error,
        stagedPath: stagedPath ?? this.stagedPath,
      );
}

/// Downloads an update package with its **own** HTTP client (so the file carries
/// no Windows Mark-of-the-Web → no SmartScreen on relaunch), verifies it against
/// the feed's SHA-256, then applies it via a detached helper that swaps the
/// install and relaunches.
class AppUpdater extends ValueNotifier<UpdateState> {
  AppUpdater() : super(const UpdateState());

  /// The swap-and-relaunch path can BRICK the install if wrong, and it can't be
  /// tested in CI — verify on real macOS (notarized) and Windows (per-user
  /// install) machines first. Until then `apply()` just reveals the verified
  /// package. Flip to true once verified per-OS.
  static const bool applyEnabled = true;

  /// Download [info]'s package and verify its SHA-256. On success → phase ready.
  Future<void> downloadAndStage(VersionInfo info) async {
    if (!info.canAutoUpdate) {
      value = value.copyWith(phase: UpdatePhase.error, error: 'No verifiable package for this platform.');
      return;
    }
    value = UpdateState(phase: UpdatePhase.downloading, version: info.latestVersion, progress: 0);
    final client = http.Client();
    try {
      final resp = await client.send(http.Request('GET', Uri.parse(info.downloadUrl!)));
      if (resp.statusCode != 200) throw 'Server returned ${resp.statusCode}';
      final total = info.downloadSize ?? resp.contentLength ?? 0;

      final base = await getApplicationSupportDirectory();
      final stageDir = Directory('${base.path}/updates');
      if (stageDir.existsSync()) {
        try { stageDir.deleteSync(recursive: true); } catch (_) {}
      }
      stageDir.createSync(recursive: true);

      final segs = Uri.parse(info.downloadUrl!).pathSegments;
      final fileName = segs.isNotEmpty && segs.last.isNotEmpty ? segs.last : 'update.zip';
      final file = File('${stageDir.path}/$fileName');
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) value = value.copyWith(progress: received / total);
      }
      await sink.close();

      value = value.copyWith(phase: UpdatePhase.verifying);
      final digest = await _sha256OfFile(file);
      if (digest.toLowerCase() != info.sha256!.toLowerCase()) {
        try { file.deleteSync(); } catch (_) {}
        throw 'Integrity check failed — the download may be corrupt or tampered.';
      }
      value = value.copyWith(phase: UpdatePhase.ready, stagedPath: file.path);
    } catch (e) {
      value = value.copyWith(phase: UpdatePhase.error, error: '$e');
    } finally {
      client.close();
    }
  }

  Future<String> _sha256OfFile(File f) async {
    Digest? out;
    final outSink = ChunkedConversionSink<Digest>.withCallback((d) => out = d.first);
    final input = sha256.startChunkedConversion(outSink);
    await for (final chunk in f.openRead()) {
      input.add(chunk);
    }
    input.close();
    return out.toString();
  }

  /// Apply the staged, verified package. Until [applyEnabled] is true (verified
  /// on real devices) this just reveals the package so the user installs it.
  Future<void> apply() async {
    final path = value.stagedPath;
    if (value.phase != UpdatePhase.ready || path == null) return;
    if (!applyEnabled) {
      try { await PlatformService.openFile(path); } catch (_) {}
      return;
    }
    value = value.copyWith(phase: UpdatePhase.applying);
    try {
      if (Platform.isWindows) {
        await _applyWindows(path);
      } else if (Platform.isMacOS) {
        await _applyMacOS(path);
      } else {
        await PlatformService.openFile(path);
        return;
      }
      // The helper relaunches us; quit so it can swap files.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      exit(0);
    } catch (e) {
      value = value.copyWith(phase: UpdatePhase.error, error: 'Update failed: $e');
    }
  }

  // ── Platform apply (UNVERIFIED — gated by applyEnabled; test before enabling) ──

  // macOS: package is a zip of `<App>.app`. The new .app MUST be Developer-ID
  // signed + notarized or Gatekeeper blocks the relaunch. A detached helper
  // waits for this process (pid) to exit, replaces the running .app, relaunches.
  Future<void> _applyMacOS(String zipPath) async {
    final exe = Platform.resolvedExecutable;
    final appPath = '${exe.split('.app/').first}.app';
    final ts = DateTime.now().microsecondsSinceEpoch;
    final tmp = '${Directory.systemTemp.path}/tulanam_update_$ts';
    final script = '''#!/bin/bash
set -e
while kill -0 $pid 2>/dev/null; do sleep 0.3; done
rm -rf "$tmp" && mkdir -p "$tmp"
/usr/bin/ditto -x -k "$zipPath" "$tmp"
NEWAPP="\$(find "$tmp" -maxdepth 1 -name '*.app' | head -1)"
[ -n "\$NEWAPP" ] || exit 1
rm -rf "$appPath"
/usr/bin/ditto "\$NEWAPP" "$appPath"
rm -rf "$tmp"
open "$appPath"
''';
    final sh = File('$tmp.sh')..writeAsStringSync(script);
    await Process.run('chmod', ['+x', sh.path]);
    await Process.start('/bin/bash', [sh.path], mode: ProcessStartMode.detached);
  }

  // Windows (no signing): per-user install. Package is a zip of the new build. A
  // detached PowerShell helper waits for this process (pid) to exit, extracts
  // over the install dir, and relaunches. No MOTW (we downloaded it), no UAC
  // (per-user location).
  Future<void> _applyWindows(String zipPath) async {
    final exe = Platform.resolvedExecutable;
    final installDir = File(exe).parent.path;
    final ps = '''
\$p = $pid
while (Get-Process -Id \$p -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 300 }
Expand-Archive -LiteralPath "$zipPath" -DestinationPath "$installDir" -Force
Start-Process -FilePath "$exe"
''';
    final ts = DateTime.now().microsecondsSinceEpoch;
    final file = File('${Directory.systemTemp.path}/tulanam_update_$ts.ps1')..writeAsStringSync(ps);
    await Process.start(
      'powershell',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', file.path],
      mode: ProcessStartMode.detached,
    );
  }
}
