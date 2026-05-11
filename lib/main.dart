import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/firebase_options.dart';
import 'package:weighbridgemanagement/core/theme/app_theme.dart';
import 'package:weighbridgemanagement/core/providers/providers.dart';
import 'package:weighbridgemanagement/authentication/login_screen.dart';
import 'package:weighbridgemanagement/authentication/signup_screen.dart';
import 'package:weighbridgemanagement/authentication/otp_verification_screen.dart';
import 'package:weighbridgemanagement/authentication/reset_password_screen.dart';
import 'package:weighbridgemanagement/authentication/admin_signup_screen.dart';
import 'package:weighbridgemanagement/authentication/linkage_request_submitted_screen.dart';
import 'package:weighbridgemanagement/dashboardpanel/dashboard_screen.dart';
import 'package:weighbridgemanagement/dashboardpanel/weighment_live_screen.dart';
import 'package:weighbridgemanagement/dashboardpanel/weighment_complete_screen.dart';
import 'package:weighbridgemanagement/dashboardpanel/gate_control_screen.dart'
    as dashboard_gate;
import 'package:weighbridgemanagement/dashboardpanel/vehicle_detection_screen.dart';
import 'package:weighbridgemanagement/dashboardpanel/manual_entry_screen.dart';
import 'package:weighbridgemanagement/dashboardpanel/driver_assist_screen.dart';
import 'package:weighbridgemanagement/dashboardpanel/material_recognition_screen.dart';
import 'package:weighbridgemanagement/dashboardpanel/customer_identification_screen.dart';
import 'package:weighbridgemanagement/settingspanel/settings_dashboard_screen.dart';
import 'package:weighbridgemanagement/settingspanel/general_settings_screen.dart';
import 'package:weighbridgemanagement/settingspanel/custom_fields_screen.dart';
import 'package:weighbridgemanagement/settingspanel/materials_screen.dart';
import 'package:weighbridgemanagement/settingspanel/gate_control_screen.dart';
import 'package:weighbridgemanagement/settingspanel/weighbridge_screen.dart';
import 'package:weighbridgemanagement/settingspanel/cameras_ai_screen.dart';
import 'package:weighbridgemanagement/settingspanel/notifications_screen.dart';
import 'package:weighbridgemanagement/settingspanel/printing_screen.dart';
import 'package:weighbridgemanagement/settingspanel/data_backup_screen.dart';
import 'package:weighbridgemanagement/settingspanel/security_screen.dart';
import 'package:weighbridgemanagement/settingspanel/integrations_screen.dart';
import 'package:weighbridgemanagement/subscriptionpanel/subscription_billing_screen.dart';
import 'package:weighbridgemanagement/auditpanel/audit_log_screen.dart';
import 'package:weighbridgemanagement/reportpanel/reports_screen.dart';
import 'package:weighbridgemanagement/reportpanel/weighment_reports_screen.dart';
import 'package:weighbridgemanagement/reportpanel/vehicle_reports_screen.dart';
import 'package:weighbridgemanagement/reportpanel/material_reports_screen.dart';
import 'package:weighbridgemanagement/reportpanel/operator_reports_screen.dart';
import 'package:weighbridgemanagement/reportpanel/comparison_reports_screen.dart';
import 'package:weighbridgemanagement/reportpanel/custom_reports_screen.dart';
import 'package:weighbridgemanagement/reportpanel/time_analysis_reports_screen.dart';
import 'package:weighbridgemanagement/reportpanel/customer_reports_screen.dart';
import 'package:weighbridgemanagement/reportpanel/financial_reports_screen.dart';
import 'package:weighbridgemanagement/operatorpanel/operator_requests_screen.dart';
import 'package:weighbridgemanagement/accountsettingpanel/account_settings_screen.dart';
import 'package:weighbridgemanagement/customerpanel/customer_database_screen.dart';
import 'package:weighbridgemanagement/customerpanel/customer_profile_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: WeighbridgeApp()));
}

class WeighbridgeApp extends ConsumerWidget {
  const WeighbridgeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return MaterialApp(
      title: "Weighbridge Manager",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      initialRoute: authState.when(
        data: (user) => user != null ? "/dashboard" : "/login",
        loading: () => "/login",
        error: (_, __) => "/login",
      ),
      routes: {
        "/login": (context) => const LoginScreen(),
        "/signup": (context) => const SignupScreen(),
        "/otp": (context) => const OtpVerificationScreen(),
        "/reset": (context) => const ResetPasswordScreen(),
        "/adminSignup": (context) => const AdminSignupScreen(),
        "/linkageSubmitted": (context) => const LinkageRequestSubmittedScreen(),
        "/dashboard": (context) => const DashboardScreen(),
        "/startWeighment": (context) => const WeighmentLiveScreen(),
        "/weighmentLive": (context) => const WeighmentLiveScreen(),
        "/weighmentComplete": (context) => const WeighmentCompleteScreen(),
        "/oldGateControl": (context) => const dashboard_gate.GateControlScreen(),
        "/vehicleDetection": (context) => const VehicleDetectionScreen(),
        "/manualEntry": (context) => const ManualEntryScreen(),
        "/driverAssist": (context) => const DriverAssistScreen(),
        "/materialRecognition": (context) => const MaterialRecognitionScreen(),
        "/customerIdentification": (context) => const CustomerIdentificationScreen(),
        "/settings": (context) => const SettingsDashboardScreen(),
        "/generalSettings": (context) => const GeneralSettingsScreen(),
        "/customFields": (context) => const CustomFieldsScreen(),
        "/materials": (context) => const MaterialsScreen(),
        "/gateControl": (context) => const GateControlScreen(),
        "/weighbridge": (context) => const WeighbridgeScreen(),
        "/camerasAi": (context) => const CamerasAiScreen(),
        "/notifications": (context) => const NotificationsScreen(),
        "/printing": (context) => const PrintingScreen(),
        "/dataBackup": (context) => const DataBackupScreen(),
        "/security": (context) => const SecurityScreen(),
        "/integrations": (context) => const IntegrationsScreen(),
        "/subscriptionBilling": (context) => const SubscriptionBillingScreen(),
        "/auditLog": (context) => const AuditLogScreen(),
        "/reports": (context) => const ReportsScreen(),
        "/weighmentReports": (context) => const WeighmentReportsScreen(),
        "/vehicleReports": (context) => const VehicleReportsScreen(),
        "/materialReports": (context) => const MaterialReportsScreen(),
        "/operatorReports": (context) => const OperatorReportsScreen(),
        "/comparisonReports": (context) => const ComparisonReportsScreen(),
        "/customReports": (context) => const CustomReportsScreen(),
        "/timeAnalysisReports": (context) => const TimeAnalysisReportsScreen(),
        "/customerReports": (context) => const CustomerReportsScreen(),
        "/financialReports": (context) => const FinancialReportsScreen(),
        "/operatorRequests": (context) => const OperatorRequestsScreen(),
        "/operators": (context) => const OperatorRequestsScreen(),
        "/accountSettings": (context) => const AccountSettingsScreen(),
        "/customers": (context) => const CustomerDatabaseScreen(),
        "/customerProfile": (context) => const CustomerProfileScreen(),
      },
    );
  }
}
