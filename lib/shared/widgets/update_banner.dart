import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:weighbridgemanagement/features/weighment/application/weighment_state_machine.dart';
import 'package:weighbridgemanagement/shared/providers/update_provider.dart';
import 'package:weighbridgemanagement/shared/providers/version_provider.dart';
import 'package:weighbridgemanagement/shared/services/app_updater.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

/// Claude-style update UI: an optional update shows a dismissible banner at the
/// bottom; a *required* update is a full-screen blocking overlay (it replaces
/// the old "Close App" dialog). Both download a verified package and offer
/// "Update & Restart".
class UpdateBanner extends ConsumerStatefulWidget {
  const UpdateBanner({super.key});

  @override
  ConsumerState<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<UpdateBanner> {
  bool _autoApplied = false;
  String? _downloadKickedFor; // latestVersion we've already started downloading

  @override
  Widget build(BuildContext context) {
    ref.watch(updatePollerProvider); // keep the periodic re-check alive
    final info = ref.watch(versionProvider).valueOrNull;
    if (info == null) return const SizedBox.shrink();

    final required = info.status == VersionStatus.updateRequired;
    final optional = info.status == VersionStatus.updateAvailable;
    if (!required && !optional) return const SizedBox.shrink();

    if (optional && ref.watch(dismissedUpdateVersionProvider) == info.latestVersion) {
      return const SizedBox.shrink();
    }

    final updater = ref.watch(appUpdaterProvider);
    // Auto-restart once the update is staged AND there's no live weighing cycle.
    // Watching the machine here means we re-check the moment a cycle finishes.
    final canRestart = ref.watch(weighmentMachineProvider).isIdle;
    // The banner is mounted above the app's Navigator (so it can cover the
    // sidebar), which means no Overlay ancestor — give it its own so its Material
    // widgets (tooltips etc.) work.
    return Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (overlayContext) => ValueListenableBuilder<UpdateState>(
            valueListenable: updater,
            builder: (_, st, __) {
              // Auto-download the moment an update is detected — on startup, the
              // 6-hour periodic re-check, or a manual check — with no confirmation.
              if (info.canAutoUpdate && st.phase == UpdatePhase.idle && _downloadKickedFor != info.latestVersion) {
                _downloadKickedFor = info.latestVersion;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && updater.value.phase == UpdatePhase.idle) updater.downloadAndStage(info);
                });
              }
              if (st.phase != UpdatePhase.ready) _autoApplied = false;
              // Only auto-restart when the real in-place apply is enabled — with
              // it off, apply() just opens the installer, which we don't want to
              // trigger unprompted. The manual "Update & Restart" still works.
              if (st.phase == UpdatePhase.ready && canRestart && AppUpdater.applyEnabled && !_autoApplied) {
                _autoApplied = true; // apply once; re-armed if a new update stages
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) updater.apply();
                });
              }
              // Optional updates are handled SILENTLY (no bottom banner) — they
              // download + auto-restart-when-idle in the background above, and the
              // status is surfaced inline on the Profile page. Only a *required*
              // update shows UI: a full-screen, non-dismissible block.
              if (!required) return const SizedBox.shrink();
              final card = _contentCard(overlayContext, ref, info, updater, st, required);
              return Container(
                color: Colors.black.withValues(alpha: 0.55),
                alignment: Alignment.center,
                child: card,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _contentCard(BuildContext context, WidgetRef ref, VersionInfo info, AppUpdater updater, UpdateState st, bool required) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final accent = required ? scheme.error : scheme.primary;

    return Material(
      elevation: 10,
      borderRadius: AppRadius.card,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: AppRadius.card,
          border: Border.all(color: accent.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.system_update_rounded, size: 22, color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(required ? 'Update required' : 'Update available',
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text('Version ${info.latestVersion ?? ''}',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  if (required && (info.releaseNotes ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(info.releaseNotes!, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.3), maxLines: 4, overflow: TextOverflow.ellipsis),
                  ],
                  if (st.phase == UpdatePhase.downloading || st.phase == UpdatePhase.verifying) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: st.phase == UpdatePhase.verifying ? null : (st.progress > 0 ? st.progress : null),
                        minHeight: 6,
                        backgroundColor: scheme.surfaceContainerLow,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      st.phase == UpdatePhase.verifying ? 'Verifying…' : 'Downloading… ${(st.progress * 100).toStringAsFixed(0)}%',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 11),
                    ),
                  ],
                  if (st.phase == UpdatePhase.error && st.error != null) ...[
                    const SizedBox(height: 4),
                    Text(st.error!, style: text.bodySmall?.copyWith(color: scheme.error, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            ..._actions(context, ref, info, updater, st, accent, required),
            if (!required && st.phase == UpdatePhase.idle)
              IconButton(
                tooltip: 'Dismiss',
                onPressed: () => ref.read(dismissedUpdateVersionProvider.notifier).state = info.latestVersion,
                icon: Icon(Icons.close_rounded, size: 18, color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context, WidgetRef ref, VersionInfo info, AppUpdater updater, UpdateState st, Color accent, bool required) {
    Widget btn(String label, VoidCallback? onTap, {bool filled = true}) => filled
        ? FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(backgroundColor: accent, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
            child: Text(label),
          )
        : TextButton(onPressed: onTap, child: Text(label));

    switch (st.phase) {
      case UpdatePhase.downloading:
      case UpdatePhase.verifying:
      case UpdatePhase.applying:
        return [btn('Working…', null)];
      case UpdatePhase.ready:
        return [btn('Update & Restart', updater.apply)];
      case UpdatePhase.error:
        return [
          if (info.canAutoUpdate) btn('Retry', () => updater.downloadAndStage(info)),
          // A forced update with no other path: let the user quit to install.
          if (required) btn('Quit', () => exit(0), filled: false),
        ];
      case UpdatePhase.idle:
        final url = info.downloadUrl ?? info.updateUrl;
        return [
          if (info.canAutoUpdate)
            btn('Update', () => updater.downloadAndStage(info))
          else if ((url ?? '').isNotEmpty)
            btn('Download', () => launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication)),
          if (required) btn('Quit', () => exit(0), filled: false),
        ];
    }
  }
}
