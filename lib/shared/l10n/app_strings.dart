import 'package:flutter_riverpod/flutter_riverpod.dart';

final stringsProvider = Provider<AppStrings>((ref) {
  return const EnStrings();
});

abstract class AppStrings {
  const AppStrings();

  // Navigation
  String get dashboard;
  String get weighment;
  String get weighments;
  String get customers;
  String get operators;
  String get reports;
  String get settings;
  String get profile;

  // Weighment
  String get grossWeight;
  String get tareWeight;
  String get netWeight;
  String get vehicleNumber;
  String get material;
  String get supplier;
  String get firstWeighment;
  String get secondWeighment;
  String get captureWeight;
  String get printDocket;
  String get stable;
  String get unstable;

  // Customers
  String get addCustomer;
  String get customerName;
  String get phone;
  String get address;
  String get search;

  // Operators
  String get addOperator;
  String get operatorName;
  String get role;
  String get active;
  String get inactive;

  // Reports
  String get dailyReport;
  String get monthlyReport;
  String get exportReport;
  String get dateRange;
  String get totalWeighments;
  String get totalWeight;

  // Settings
  String get general;
  String get customFields;
  String get materials;
  String get gateControl;
  String get weighbridge;
  String get cameras;
  String get notifications;
  String get printing;
  String get backup;
  String get security;
  String get integrations;
  String get appearance;
  String get dataBackup;

  // Common
  String get save;
  String get cancel;
  String get delete;
  String get edit;
  String get add;
  String get confirm;
  String get loading;
  String get error;
  String get success;
  String get noData;
  String get refresh;
}

class EnStrings extends AppStrings {
  const EnStrings();

  @override String get dashboard => 'Dashboard';
  @override String get weighment => 'Weigh';
  @override String get weighments => 'Weighments';
  @override String get customers => 'Customers';
  @override String get operators => 'Operators';
  @override String get reports => 'Reports';
  @override String get settings => 'Settings';
  @override String get profile => 'Profile';

  @override String get grossWeight => 'Gross Weight';
  @override String get tareWeight => 'Tare Weight';
  @override String get netWeight => 'Net Weight';
  @override String get vehicleNumber => 'Vehicle Number';
  @override String get material => 'Material';
  @override String get supplier => 'Supplier';
  @override String get firstWeighment => 'First Weighment';
  @override String get secondWeighment => 'Second Weighment';
  @override String get captureWeight => 'Capture Weight';
  @override String get printDocket => 'Print Docket';
  @override String get stable => 'Stable';
  @override String get unstable => 'Unstable';

  @override String get addCustomer => 'Add Customer';
  @override String get customerName => 'Customer Name';
  @override String get phone => 'Phone';
  @override String get address => 'Address';
  @override String get search => 'Search';

  @override String get addOperator => 'Add Operator';
  @override String get operatorName => 'Operator Name';
  @override String get role => 'Role';
  @override String get active => 'Active';
  @override String get inactive => 'Inactive';

  @override String get dailyReport => 'Daily Report';
  @override String get monthlyReport => 'Monthly Report';
  @override String get exportReport => 'Export Report';
  @override String get dateRange => 'Date Range';
  @override String get totalWeighments => 'Total Weighments';
  @override String get totalWeight => 'Total Weight';

  @override String get general => 'General';
  @override String get customFields => 'Custom Fields';
  @override String get materials => 'Materials';
  @override String get gateControl => 'Gate Control';
  @override String get weighbridge => 'Weighbridge';
  @override String get cameras => 'Cameras & AI';
  @override String get notifications => 'Notifications';
  @override String get printing => 'Printing';
  @override String get backup => 'Backup';
  @override String get security => 'Security';
  @override String get integrations => 'Integrations';
  @override String get appearance => 'Appearance';
  @override String get dataBackup => 'Data & Backup';

  @override String get save => 'Save';
  @override String get cancel => 'Cancel';
  @override String get delete => 'Delete';
  @override String get edit => 'Edit';
  @override String get add => 'Add';
  @override String get confirm => 'Confirm';
  @override String get loading => 'Loading...';
  @override String get error => 'Error';
  @override String get success => 'Success';
  @override String get noData => 'No data';
  @override String get refresh => 'Refresh';
}

