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
import 'package:weighbridgemanagement/features/weighments/presentation/weighments_screen.dart';
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
import 'package:weighbridgemanagement/shared/providers/site_context_provider.dart';
import 'package:weighbridgemanagement/shared/widgets/lockdown_screen.dart';
import 'package:weighbridgemanagement/features/setup/presentation/setup_wizard_screen.dart';

CustomTransitionPage<void> _noTransitionPage(Widget child, GoRouterState state) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (_, __, ___, child) => child,
  );
}

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

      // Site context gate
      final siteCtx = ref.read(siteContextProvider);
      final isSetupRoute = state.matchedLocation == '/setup';
      if (!siteCtx.isConfigured && !isSetupRoute) {
        final authRoutes = ['/login', '/signup', '/forgot-password', '/linkage-pending'];
        if (!authRoutes.contains(state.matchedLocation)) return '/setup';
      }
      if (siteCtx.isConfigured && isSetupRoute) return '/dashboard';

      if (skipAuth) return null;

      final authState = ref.read(authStateProvider);
      final isLoggedIn = authState.valueOrNull != null;
      final authRoutes = ['/login', '/signup', '/forgot-password', '/linkage-pending'];
      final isAuthRoute = authRoutes.contains(state.matchedLocation);

      if (!isLoggedIn && !isAuthRoute && !isSetupRoute) return '/login';
      if (isLoggedIn && isAuthRoute && state.matchedLocation != '/linkage-pending') return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/login', pageBuilder: (_, state) => _noTransitionPage(const LoginScreen(), state)),
      GoRoute(path: '/signup', pageBuilder: (_, state) => _noTransitionPage(const SignupScreen(), state)),
      GoRoute(path: '/forgot-password', pageBuilder: (_, state) => _noTransitionPage(const ForgotPasswordScreen(), state)),
      GoRoute(path: '/linkage-pending', pageBuilder: (_, state) => _noTransitionPage(const LinkagePendingScreen(), state)),
      GoRoute(path: '/lockdown', pageBuilder: (_, state) => _noTransitionPage(const LockdownScreen(), state)),
      GoRoute(path: '/setup', pageBuilder: (_, state) => _noTransitionPage(const SetupWizardScreen(), state)),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', pageBuilder: (_, state) => _noTransitionPage(const DashboardScreen(), state)),
          GoRoute(path: '/weighment', pageBuilder: (_, state) => _noTransitionPage(const WeighmentScreen(), state)),
          GoRoute(path: '/weighments', pageBuilder: (_, state) => _noTransitionPage(const WeighmentsScreen(), state)),
          GoRoute(path: '/customers', pageBuilder: (_, state) => _noTransitionPage(const CustomersScreen(), state)),
          GoRoute(path: '/operators', pageBuilder: (_, state) => _noTransitionPage(const OperatorsScreen(), state)),
          GoRoute(path: '/reports', pageBuilder: (_, state) => _noTransitionPage(const ReportsScreen(), state)),
          GoRoute(path: '/profile', pageBuilder: (_, state) => _noTransitionPage(const ProfileScreen(), state)),
          GoRoute(path: '/settings', pageBuilder: (_, state) => _noTransitionPage(const SettingsScreen(), state),
            routes: [
              GoRoute(path: 'general', pageBuilder: (_, state) => _noTransitionPage(const GeneralSettingsScreen(), state)),
              GoRoute(path: 'custom-fields', pageBuilder: (_, state) => _noTransitionPage(const CustomFieldsScreen(), state)),
              GoRoute(path: 'materials', pageBuilder: (_, state) => _noTransitionPage(const MaterialsScreen(), state)),
              GoRoute(path: 'gate-control', pageBuilder: (_, state) => _noTransitionPage(const GateControlScreen(), state)),
              GoRoute(path: 'weighbridge', pageBuilder: (_, state) => _noTransitionPage(const ScaleSettingsScreen(), state)),
              GoRoute(path: 'cameras', pageBuilder: (_, state) => _noTransitionPage(const CamerasAiScreen(), state)),
              GoRoute(path: 'notifications', pageBuilder: (_, state) => _noTransitionPage(const NotificationsScreen(), state)),
              GoRoute(path: 'printing', pageBuilder: (_, state) => _noTransitionPage(const PrintingScreen(), state)),
              GoRoute(path: 'backup', pageBuilder: (_, state) => _noTransitionPage(const DataBackupScreen(), state)),
              GoRoute(path: 'mfa', pageBuilder: (_, state) => _noTransitionPage(const SecurityScreen(), state)),
              GoRoute(path: 'integrations', pageBuilder: (_, state) => _noTransitionPage(const IntegrationsScreen(), state)),
              GoRoute(path: 'appearance', pageBuilder: (_, state) => _noTransitionPage(const AppearanceScreen(), state)),
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
