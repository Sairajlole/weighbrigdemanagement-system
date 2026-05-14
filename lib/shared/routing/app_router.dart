import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/app/app_shell.dart';
import 'package:weighbridgemanagement/features/auth/presentation/login_screen.dart';
import 'package:weighbridgemanagement/features/auth/presentation/signup_screen.dart';
import 'package:weighbridgemanagement/features/auth/presentation/forgot_password_screen.dart';
import 'package:weighbridgemanagement/features/auth/presentation/linkage_pending_screen.dart';
import 'package:weighbridgemanagement/features/dashboard/presentation/dashboard_screen.dart';
import 'package:weighbridgemanagement/features/weighment/presentation/weighment_screen.dart';
import 'package:weighbridgemanagement/features/customers/presentation/customers_screen.dart';
import 'package:weighbridgemanagement/features/operators/presentation/operators_screen.dart';
import 'package:weighbridgemanagement/features/profile/presentation/profile_screen.dart';
import 'package:weighbridgemanagement/features/reports/presentation/reports_screen.dart';
import 'package:weighbridgemanagement/features/settings/presentation/settings_screen.dart';
import 'package:weighbridgemanagement/features/settings/presentation/general_settings_screen.dart';
import 'package:weighbridgemanagement/features/settings/presentation/custom_fields_screen.dart';
import 'package:weighbridgemanagement/features/settings/presentation/materials_screen.dart';
import 'package:weighbridgemanagement/features/settings/presentation/gate_control_screen.dart';
import 'package:weighbridgemanagement/features/settings/presentation/scale_settings_screen.dart';
import 'package:weighbridgemanagement/features/settings/presentation/cameras_ai_screen.dart';
import 'package:weighbridgemanagement/features/settings/presentation/notifications_screen.dart';
import 'package:weighbridgemanagement/features/settings/presentation/printing_screen.dart';
import 'package:weighbridgemanagement/features/settings/presentation/data_backup_screen.dart';
import 'package:weighbridgemanagement/features/settings/presentation/security_screen.dart';
import 'package:weighbridgemanagement/features/settings/presentation/integrations_screen.dart';
import 'package:weighbridgemanagement/features/settings/presentation/appearance_screen.dart';
import 'package:weighbridgemanagement/shared/providers/auth_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart' show permissionServiceProvider;
import 'package:weighbridgemanagement/shared/widgets/lockdown_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final bool skipAuth = Platform.isMacOS;

  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final perms = ref.read(permissionServiceProvider);
      if (perms.isLockdown && state.matchedLocation != '/lockdown') {
        return '/lockdown';
      }
      if (!perms.isLockdown && state.matchedLocation == '/lockdown') {
        return '/dashboard';
      }

      if (skipAuth) return null;

      final authState = ref.read(authStateProvider);
      final isLoggedIn = authState.valueOrNull != null;
      final authRoutes = ['/login', '/signup', '/forgot-password', '/linkage-pending'];
      final isAuthRoute = authRoutes.contains(state.matchedLocation);

      if (!isLoggedIn && !isAuthRoute) return '/login';
      if (isLoggedIn && isAuthRoute && state.matchedLocation != '/linkage-pending') return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: '/linkage-pending', builder: (_, __) => const LinkagePendingScreen()),
      GoRoute(path: '/lockdown', builder: (_, __) => const LockdownScreen()),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/weighment', builder: (_, __) => const WeighmentScreen()),
          GoRoute(path: '/customers', builder: (_, __) => const CustomersScreen()),
          GoRoute(path: '/operators', builder: (_, __) => const OperatorsScreen()),
          GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen(),
            routes: [
              GoRoute(path: 'general', builder: (_, __) => const GeneralSettingsScreen()),
              GoRoute(path: 'custom-fields', builder: (_, __) => const CustomFieldsScreen()),
              GoRoute(path: 'materials', builder: (_, __) => const MaterialsScreen()),
              GoRoute(path: 'gate-control', builder: (_, __) => const GateControlScreen()),
              GoRoute(path: 'weighbridge', builder: (_, __) => const ScaleSettingsScreen()),
              GoRoute(path: 'cameras', builder: (_, __) => const CamerasAiScreen()),
              GoRoute(path: 'notifications', builder: (_, __) => const NotificationsScreen()),
              GoRoute(path: 'printing', builder: (_, __) => const PrintingScreen()),
              GoRoute(path: 'backup', builder: (_, __) => const DataBackupScreen()),
              GoRoute(path: 'mfa', builder: (_, __) => const SecurityScreen()),
              GoRoute(path: 'integrations', builder: (_, __) => const IntegrationsScreen()),
              GoRoute(path: 'appearance', builder: (_, __) => const AppearanceScreen()),
            ],
          ),
        ],
      ),
    ],
  );

  if (!skipAuth) {
    ref.listen(authStateProvider, (_, __) {
      router.refresh();
    });
  }

  return router;
});
