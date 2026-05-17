import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final connectivityProvider = StreamProvider<bool>((ref) {
  final controller = StreamController<bool>();
  Timer? pingTimer;

  Future<bool> checkInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void startPinging() {
    checkInternet().then((ok) {
      if (!controller.isClosed) controller.add(ok);
    });
    pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      checkInternet().then((ok) {
        if (!controller.isClosed) controller.add(ok);
      });
    });
  }

  final sub = Connectivity().onConnectivityChanged.listen((results) {
    final hasInterface = results.any((r) => r != ConnectivityResult.none);
    if (!hasInterface) {
      if (!controller.isClosed) controller.add(false);
    } else {
      checkInternet().then((ok) {
        if (!controller.isClosed) controller.add(ok);
      });
    }
  });

  startPinging();

  ref.onDispose(() {
    pingTimer?.cancel();
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});
