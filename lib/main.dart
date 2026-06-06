import 'dart:io';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:weighbridgemanagement/shared/widgets/window_title_bar.dart';
import 'package:weighbridgemanagement/firebase_options.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/providers/appearance_provider.dart';
import 'package:weighbridgemanagement/shared/providers/version_provider.dart';
import 'package:weighbridgemanagement/shared/routing/app_router.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    MediaKit.ensureInitialized();
  } catch (_) {}
  await windowManager.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Disable keychain persistence — we sign out on every cold start anyway,
  // and this avoids keychain-error on macOS without a valid provisioning profile.
  // For production distribution (signed with Apple Developer ID), remove this
  // and use proper keychain-access-groups in entitlements instead.
  try {
    await FirebaseAuth.instance.setPersistence(Persistence.NONE);
  } catch (_) {}

  FirebaseFirestore.instance.settings = Settings(
    // Disable persistence on Windows — the cloud_firestore C++ plugin sends
    // persistence-layer responses on non-platform threads, crashing the app.
    persistenceEnabled: !Platform.isWindows,
    cacheSizeBytes: Platform.isWindows ? null : 100 * 1024 * 1024,
  );

  // Sign out on every cold start — user must sign in fresh
  await LocalCacheService.clearCurrentUser();
  try {
    if (FirebaseAuth.instance.currentUser != null && !FirebaseAuth.instance.currentUser!.isAnonymous) {
      await FirebaseAuth.instance.signOut();
    }
  } catch (_) {}

  // Anonymous sign-in so Firestore queries work during the login flow
  if (FirebaseAuth.instance.currentUser == null) {
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (_) {}
  }

  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1280, 800),
      center: true,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'Tulanam',
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  await windowManager.setMinimumSize(const Size(1024, 600));

  runApp(const ProviderScope(child: WeighbridgeApp()));
}

class WeighbridgeApp extends ConsumerStatefulWidget {
  const WeighbridgeApp({super.key});

  @override
  ConsumerState<WeighbridgeApp> createState() => _WeighbridgeAppState();
}

class _WeighbridgeAppState extends ConsumerState<WeighbridgeApp> {
  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final appearance = ref.watch(appearanceProvider);

    final theme = switch (appearance.themeMode) {
      ThemeMode.dark => AppTheme.darkFrom(seed: AppTheme.defaultAccent),
      ThemeMode.light => AppTheme.lightFrom(seed: AppTheme.defaultAccent),
      ThemeMode.system => AppTheme.lightFrom(seed: AppTheme.defaultAccent),
    };

    return MaterialApp.router(
      title: 'Tulanam',
      debugShowCheckedModeBanner: false,
      theme: theme,
      themeAnimationDuration: Duration.zero,
      locale: Locale(appearance.locale),
      scrollBehavior: const _AppScrollBehavior(),
      routerConfig: router,
      builder: (context, child) {
        Responsive.init(context);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(appearance.fontScale),
          ),
          child: Column(
            children: [
              const WindowTitleBar(),
              Expanded(child: _VersionGate(child: child!)),
            ],
          ),
        );
      },
    );
  }
}

class _VersionGate extends ConsumerStatefulWidget {
  final Widget child;
  const _VersionGate({required this.child});

  @override
  ConsumerState<_VersionGate> createState() => _VersionGateState();
}

class _VersionGateState extends ConsumerState<_VersionGate> {
  bool _dialogShown = false;

  @override
  Widget build(BuildContext context) {
    final versionAsync = ref.watch(versionProvider);

    versionAsync.whenData((info) {
      if (info.status == VersionStatus.updateRequired && !_dialogShown) {
        _dialogShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Update Required'),
              content: Text(
                'A critical update (v${info.latestVersion}) is required to continue using this application.\n\n'
                '${info.releaseNotes ?? "Please update to the latest version."}',
              ),
              actions: [
                FilledButton(
                  onPressed: () => exit(0),
                  child: const Text('Close App'),
                ),
              ],
            ),
          );
        });
      }
    });

    return widget.child;
  }
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    if (details.controller == null) return child;
    return _HoverScrollButtons(
      controller: details.controller!,
      axis: details.direction,
      child: child,
    );
  }
}

class _HoverScrollButtons extends StatefulWidget {
  final ScrollController controller;
  final AxisDirection axis;
  final Widget child;

  const _HoverScrollButtons({
    required this.controller,
    required this.axis,
    required this.child,
  });

  @override
  State<_HoverScrollButtons> createState() => _HoverScrollButtonsState();
}

class _HoverScrollButtonsState extends State<_HoverScrollButtons> {
  final _showStart = ValueNotifier(false);
  final _showEnd = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateVisibility);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateVisibility());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateVisibility);
    _showStart.dispose();
    _showEnd.dispose();
    super.dispose();
  }

  void _updateVisibility() {
    if (!widget.controller.hasClients) return;
    final pos = widget.controller.position;
    _showStart.value = pos.pixels > pos.minScrollExtent + 10;
    _showEnd.value = pos.pixels < pos.maxScrollExtent - 10;
  }

  void _scrollBy(double delta) {
    if (!widget.controller.hasClients) return;
    final pos = widget.controller.position;
    widget.controller.animateTo(
      (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  bool get _isVertical => widget.axis == AxisDirection.down || widget.axis == AxisDirection.up;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        widget.child,
        ValueListenableBuilder<bool>(
          valueListenable: _showStart,
          builder: (_, show, __) => show
              ? Positioned(
                  top: _isVertical ? 12 : 0,
                  left: _isVertical ? 0 : 12,
                  right: _isVertical ? 0 : null,
                  bottom: _isVertical ? null : 0,
                  child: Center(
                    child: _ScrollButton(
                      icon: _isVertical ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_left_rounded,
                      onTap: () => _scrollBy(_isVertical ? -200 : -200),
                      scheme: scheme,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _showEnd,
          builder: (_, show, __) => show
              ? Positioned(
                  bottom: _isVertical ? 12 : 0,
                  left: _isVertical ? 0 : null,
                  right: _isVertical ? 0 : 12,
                  top: _isVertical ? null : 0,
                  child: Center(
                    child: _ScrollButton(
                      icon: _isVertical ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                      onTap: () => _scrollBy(_isVertical ? 200 : 200),
                      scheme: scheme,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _ScrollButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme scheme;

  const _ScrollButton({required this.icon, required this.onTap, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.95),
          shape: BoxShape.circle,
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
