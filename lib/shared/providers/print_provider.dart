import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import 'package:weighbridgemanagement/shared/services/print_service.dart';

final printServiceProvider = Provider<PrintService>((ref) {
  final db = ref.watch(firestoreProvider);
  return PrintService(db);
});
