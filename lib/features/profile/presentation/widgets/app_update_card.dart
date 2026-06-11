import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/version_provider.dart';
import 'package:weighbridgemanagement/shared/services/platform_service.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

enum _Dl { idle, downloading, done, error }

/// Profile card that checks for an app update and, when one is available,
/// downloads the installer in-app (with progress) and hands it to the OS to run.
class AppUpdateCard extends ConsumerStatefulWidget {
  const AppUpdateCard({super.key});

  @override
  ConsumerState<AppUpdateCard> createState() => _AppUpdateCardState();
}

class _AppUpdateCardState extends ConsumerState<AppUpdateCard> {
  _Dl _state = _Dl.idle;
  double _progress = 0;
  String? _error;
  String? _downloadedPath;

  Future<void> _download(String url) async {
    setState(() { _state = _Dl.downloading; _progress = 0; _error = null; });
    final client = http.Client();
    try {
      final resp = await client.send(http.Request('GET', Uri.parse(url)));
      if (resp.statusCode != 200) {
        throw 'Server returned ${resp.statusCode}';
      }
      final total = resp.contentLength ?? 0;
      var fileName = Uri.parse(url).pathSegments.isNotEmpty ? Uri.parse(url).pathSegments.last : 'update';
      if (fileName.isEmpty) fileName = 'update';
      final dir = (await getDownloadsDirectory()) ?? (await getTemporaryDirectory());
      final file = File('${dir.path}/$fileName');
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && mounted) setState(() => _progress = received / total);
      }
      await sink.close();
      _downloadedPath = file.path;
      if (mounted) setState(() => _state = _Dl.done);
    } catch (e) {
      if (mounted) setState(() { _state = _Dl.error; _error = 'Download failed: $e'; });
    } finally {
      client.close();
    }
  }

  Future<void> _openInstaller() async {
    if (_downloadedPath == null) return;
    try {
      await PlatformService.openFile(_downloadedPath!);
    } catch (e) {
      if (mounted) setState(() { _state = _Dl.error; _error = 'Could not open the installer: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final async = ref.watch(versionProvider);
    final info = async.valueOrNull;
    final checking = async.isLoading;

    final hasUpdate = info != null &&
        (info.status == VersionStatus.updateAvailable || info.status == VersionStatus.updateRequired);
    final accent = info?.status == VersionStatus.updateRequired
        ? scheme.error
        : (hasUpdate ? Colors.orange : AppTheme.successColor);

    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: AppRadius.card,
        border: Border.all(color: hasUpdate ? accent.withValues(alpha: 0.3) : scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.system_update_rounded, size: 18, color: accent),
              SizedBox(width: AppSpacing.sm),
              Text('App Update', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (checking)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              else
                _statusChip(info?.status ?? VersionStatus.unknown, accent),
            ],
          ),
          SizedBox(height: AppSpacing.md),

          // Current / latest version line.
          _kv('Installed', info?.currentVersion.isNotEmpty == true ? 'v${info!.currentVersion}' : '—', scheme, text),
          if (hasUpdate && (info.latestVersion ?? '').isNotEmpty) ...[
            SizedBox(height: 6.rs),
            _kv('Latest', 'v${info.latestVersion}', scheme, text),
          ],

          // Release notes for an available update.
          if (hasUpdate && (info.releaseNotes ?? '').isNotEmpty) ...[
            SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(10.rs),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.4), borderRadius: AppRadius.button),
              child: Text(info.releaseNotes!, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4)),
            ),
          ],

          SizedBox(height: AppSpacing.lg),
          ..._buildAction(info, hasUpdate, accent, scheme, text),
        ],
      ),
    );
  }

  List<Widget> _buildAction(VersionInfo? info, bool hasUpdate, Color accent, ColorScheme scheme, TextTheme text) {
    switch (_state) {
      case _Dl.downloading:
        return [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: _progress > 0 ? _progress : null, minHeight: 8, backgroundColor: scheme.surfaceContainerHighest),
          ),
          SizedBox(height: AppSpacing.sm),
          Text('Downloading… ${(_progress * 100).toStringAsFixed(0)}%', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ];
      case _Dl.done:
        return [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.successColor),
              SizedBox(width: AppSpacing.sm),
              Expanded(child: Text('Downloaded. Open the installer and follow the prompts to finish updating.',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4))),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openInstaller,
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Open Installer'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
            ),
          ),
        ];
      case _Dl.error:
        return [
          Text(_error ?? 'Update failed', style: text.bodySmall?.copyWith(color: scheme.error), maxLines: 3, overflow: TextOverflow.ellipsis),
          SizedBox(height: AppSpacing.sm),
          if (hasUpdate && (info?.updateUrl ?? '').isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: () => _download(info!.updateUrl!), child: const Text('Retry Download')),
            ),
        ];
      case _Dl.idle:
        if (hasUpdate) {
          final canDownload = (info?.updateUrl ?? '').isNotEmpty;
          return [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canDownload ? () => _download(info!.updateUrl!) : null,
                icon: const Icon(Icons.download_rounded, size: 16),
                label: Text(canDownload ? 'Download & Install' : 'Update unavailable'),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                ),
              ),
            ),
          ];
        }
        // Up to date / unknown.
        return [
          Row(
            children: [
              Icon(
                info?.status == VersionStatus.unknown ? Icons.help_outline_rounded : Icons.check_circle_rounded,
                size: 16,
                color: info?.status == VersionStatus.unknown ? scheme.onSurfaceVariant : AppTheme.successColor,
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  info?.status == VersionStatus.unknown
                      ? "Couldn't check for updates. Check your connection and reopen this screen."
                      : "You're on the latest version.",
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              if (info?.status == VersionStatus.unknown)
                TextButton(onPressed: () => ref.invalidate(versionProvider), child: const Text('Retry')),
            ],
          ),
        ];
    }
  }

  Widget _statusChip(VersionStatus status, Color accent) {
    final label = switch (status) {
      VersionStatus.upToDate => 'Up to date',
      VersionStatus.updateAvailable => 'Update available',
      VersionStatus.updateRequired => 'Update required',
      VersionStatus.unknown => 'Unknown',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: AppRadius.chip),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: accent)),
    );
  }

  Widget _kv(String k, String v, ColorScheme scheme, TextTheme text) {
    return Row(
      children: [
        Text('$k  ', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        Text(v, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
