import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/services/print_service.dart';

final printServiceProvider = Provider<PrintService>((ref) {
  final paths = ref.watch(firestorePathsProvider);
  return PrintService(paths);
});
