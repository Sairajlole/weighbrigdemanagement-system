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
import 'package:weighbridgemanagement/shared/routing/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // On macOS, attempt sign-in (keychain issues may prevent this)
  if (Platform.isMacOS && FirebaseAuth.instance.currentUser == null) {
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (_) {
      // Keychain not accessible — app works with open rules in dev
    }
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
          child: child!,
        );
      },
    );
  }
}
