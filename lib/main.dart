import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/authentication/admin_signup_screen.dart';
import 'package:weighbridgemanagement/authentication/linkage_request_submitted_screen.dart';
import 'package:weighbridgemanagement/authentication/login_screen.dart';
import 'package:weighbridgemanagement/authentication/otp_verification_screen.dart';
import 'package:weighbridgemanagement/authentication/reset_password_screen.dart';
import 'package:weighbridgemanagement/authentication/signup_screen.dart';
import 'package:weighbridgemanagement/dashboardpanel/dashboard_screen.dart';
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


void main() {
  runApp(const WeighbridgeApp());
}

class WeighbridgeApp extends StatelessWidget {
  const WeighbridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Weighbridge Manager",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: "Arial",
      ),
      initialRoute: "/login",
      routes: {
        "/login": (context) =>  LoginScreen(),
        "/signup": (context) =>  SignupScreen(),
        "/otp": (context) =>  OtpVerificationScreen(),
        "/reset": (context) => ResetPasswordScreen(),
        "/adminSignup": (context) => AdminSignupScreen(),
        "/linkageSubmitted": (context) => LinkageRequestSubmittedScreen(),
        "/dashboard": (context) =>  DashboardScreen(),
        "/settings": (context) => SettingsDashboardScreen(),
        "/generalSettings": (context) => GeneralSettingsScreen(),
        "/customFields": (context) => CustomFieldsScreen(),
        "/materials": (context) => MaterialsScreen(),
        "/gateControl": (context) => GateControlScreen(),
        "/weighbridge": (context) => WeighbridgeScreen(),
        "/camerasAi": (context) => CamerasAiScreen(),
        "/notifications": (context) => NotificationsScreen(),
        "/printing": (context) => PrintingScreen(),
        "/dataBackup": (context) => DataBackupScreen(),
        "/security": (context) => SecurityScreen(),
        "/integrations": (context) => IntegrationsScreen(),
        "/subscriptionBilling": (context) => SubscriptionBillingScreen(),
        "/auditLog": (context) => AuditLogScreen(),
        "/reports": (context) => ReportsScreen(),
        "/weighmentReports": (context) => WeighmentReportsScreen(),
        "/vehicleReports": (context) => VehicleReportsScreen(),
        "/materialReports": (context) => MaterialReportsScreen(),
        "/operatorReports": (context) => OperatorReportsScreen(),
        "/comparisonReports": (context) => ComparisonReportsScreen(),
        "/customReports": (context) => CustomReportsScreen(),
        "/timeAnalysisReports": (context) => TimeAnalysisReportsScreen(),
        "/customerReports": (context) => CustomerReportsScreen(),
        "/financialReports": (context) => FinancialReportsScreen(),
        "/operatorRequests": (context) => OperatorRequestsScreen(),
        "/operators": (context) => OperatorRequestsScreen(),
      },
    );
  }
}
