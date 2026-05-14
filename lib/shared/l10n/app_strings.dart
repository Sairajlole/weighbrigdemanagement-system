import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/appearance_provider.dart';

final stringsProvider = Provider<AppStrings>((ref) {
  final locale = ref.watch(appearanceProvider.select((s) => s.locale));
  return locale == 'hi' ? const HiStrings() : const EnStrings();
});

abstract class AppStrings {
  const AppStrings();

  // Navigation
  String get dashboard;
  String get weighment;
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
  @override String get weighment => 'Weighment';
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

class HiStrings extends AppStrings {
  const HiStrings();

  @override String get dashboard => 'डैशबोर्ड';
  @override String get weighment => 'तौल';
  @override String get customers => 'ग्राहक';
  @override String get operators => 'ऑपरेटर';
  @override String get reports => 'रिपोर्ट';
  @override String get settings => 'सेटिंग्स';
  @override String get profile => 'प्रोफ़ाइल';

  @override String get grossWeight => 'कुल वज़न';
  @override String get tareWeight => 'खाली वज़न';
  @override String get netWeight => 'शुद्ध वज़न';
  @override String get vehicleNumber => 'वाहन नंबर';
  @override String get material => 'सामग्री';
  @override String get supplier => 'आपूर्तिकर्ता';
  @override String get firstWeighment => 'पहली तौल';
  @override String get secondWeighment => 'दूसरी तौल';
  @override String get captureWeight => 'वज़न दर्ज करें';
  @override String get printDocket => 'पर्ची प्रिंट करें';
  @override String get stable => 'स्थिर';
  @override String get unstable => 'अस्थिर';

  @override String get addCustomer => 'ग्राहक जोड़ें';
  @override String get customerName => 'ग्राहक का नाम';
  @override String get phone => 'फ़ोन';
  @override String get address => 'पता';
  @override String get search => 'खोजें';

  @override String get addOperator => 'ऑपरेटर जोड़ें';
  @override String get operatorName => 'ऑपरेटर का नाम';
  @override String get role => 'भूमिका';
  @override String get active => 'सक्रिय';
  @override String get inactive => 'निष्क्रिय';

  @override String get dailyReport => 'दैनिक रिपोर्ट';
  @override String get monthlyReport => 'मासिक रिपोर्ट';
  @override String get exportReport => 'रिपोर्ट निर्यात';
  @override String get dateRange => 'तिथि सीमा';
  @override String get totalWeighments => 'कुल तौल';
  @override String get totalWeight => 'कुल वज़न';

  @override String get general => 'सामान्य';
  @override String get customFields => 'कस्टम फ़ील्ड';
  @override String get materials => 'सामग्री';
  @override String get gateControl => 'गेट नियंत्रण';
  @override String get weighbridge => 'वेब्रिज';
  @override String get cameras => 'कैमरा व AI';
  @override String get notifications => 'सूचनाएं';
  @override String get printing => 'प्रिंटिंग';
  @override String get backup => 'बैकअप';
  @override String get security => 'सुरक्षा';
  @override String get integrations => 'इंटीग्रेशन';
  @override String get appearance => 'दिखावट';
  @override String get dataBackup => 'डेटा व बैकअप';

  @override String get save => 'सहेजें';
  @override String get cancel => 'रद्द करें';
  @override String get delete => 'हटाएं';
  @override String get edit => 'संपादित करें';
  @override String get add => 'जोड़ें';
  @override String get confirm => 'पुष्टि करें';
  @override String get loading => 'लोड हो रहा है...';
  @override String get error => 'त्रुटि';
  @override String get success => 'सफल';
  @override String get noData => 'कोई डेटा नहीं';
  @override String get refresh => 'रिफ़्रेश';
}
