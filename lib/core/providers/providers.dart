import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/core/services/auth_service.dart';
import 'package:weighbridgemanagement/core/services/firestore_service.dart';
import 'package:weighbridgemanagement/core/services/scale_service.dart';
import 'package:weighbridgemanagement/core/models/weighment.dart';
import 'package:weighbridgemanagement/core/models/customer.dart';
import 'package:weighbridgemanagement/core/models/operator_model.dart';
import 'package:weighbridgemanagement/core/models/camera_config.dart';

// Services
final authServiceProvider = Provider<AuthService>((ref) => AuthService());
final firestoreServiceProvider = Provider<FirestoreService>((ref) => FirestoreService());
final scaleServiceProvider = Provider<ScaleService>((ref) => ScaleService(
  connectionType: ScaleConnectionType.simulated,
));

// Auth state
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

// Current operator profile
final currentOperatorProvider = FutureProvider<Operator?>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  return ref.read(firestoreServiceProvider).getOperatorByUid(user.uid);
});

// Weighments
final weighmentsStreamProvider = StreamProvider<List<Weighment>>((ref) {
  return ref.watch(firestoreServiceProvider).streamWeighments();
});

// Customers
final customersStreamProvider = StreamProvider<List<Customer>>((ref) {
  return ref.watch(firestoreServiceProvider).streamCustomers();
});

// Operators for a company
final operatorsStreamProvider = StreamProvider.family<List<Operator>, String>((ref, companyId) {
  return ref.watch(firestoreServiceProvider).streamOperators(companyId);
});

// Awaiting tare (second weighment)
final awaitingTareProvider = StreamProvider<List<Weighment>>((ref) {
  return ref.watch(firestoreServiceProvider).streamAwaitingTare();
});

// Current company
final currentCompanyProvider = FutureProvider((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  return ref.read(firestoreServiceProvider).getCompanyByAdmin(user.uid);
});

// Cameras
final camerasStreamProvider = StreamProvider<List<CameraConfig>>((ref) {
  return ref.watch(firestoreServiceProvider).streamCameras();
});
