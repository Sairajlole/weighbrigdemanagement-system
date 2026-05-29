import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:weighbridgemanagement/firebase_options.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/providers/appearance_provider.dart';
import 'package:weighbridgemanagement/shared/providers/version_provider.dart';
import 'package:weighbridgemanagement/shared/routing/app_router.dart';
import 'package:weighbridgemanagement/shared/services/local_cache_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Disable keychain persistence — we sign out on every cold start anyway,
  // and this avoids keychain-error on macOS without a valid provisioning profile.
  // For production distribution (signed with Apple Developer ID), remove this
  // and use proper keychain-access-groups in entitlements instead.
  try {
    await FirebaseAuth.instance.setPersistence(Persistence.NONE);
  } catch (_) {}

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 100 * 1024 * 1024,
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

  await windowManager.waitUntilReadyToShow(null, () async {
    await windowManager.show();
    await windowManager.maximize();
    await windowManager.focus();
  });

  await Future.delayed(const Duration(milliseconds: 500));
  final size = await windowManager.getSize();
  await windowManager.setMinimumSize(size);
  await windowManager.setMaximumSize(size);

  runApp(const ProviderScope(child: WeighbridgeApp()));
}

class WeighbridgeApp extends ConsumerWidget {
  const WeighbridgeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final appearance = ref.watch(appearanceProvider);

    final theme = switch (appearance.themeMode) {
      ThemeMode.dark => AppTheme.darkFrom(seed: appearance.accentColor),
      ThemeMode.light => AppTheme.lightFrom(seed: appearance.accentColor),
      ThemeMode.system => AppTheme.lightFrom(seed: appearance.accentColor),
    };

    return MaterialApp.router(
      title: 'Weighbridge',
      debugShowCheckedModeBanner: false,
      theme: theme,
      themeAnimationDuration: Duration.zero,
      locale: Locale(appearance.locale),
      routerConfig: router,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(appearance.fontScale),
          ),
          child: _VersionGate(child: child!),
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
