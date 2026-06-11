import 'dart:async';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/foundation.dart';

/// Outcome of running the DigiLocker flow inside an in-app webview window.
enum MeonWebviewOutcome {
  /// The webview navigated to the redirect/thank-you URL — the user completed
  /// (or at least finished) the DigiLocker flow. Data should now be fetched.
  redirected,

  /// The user closed the window before reaching the redirect URL.
  closed,
}

/// Opens [url] in a native webview window owned by the app and resolves when
/// the webview either reaches [redirectUrl] (success) or is closed by the user.
///
/// Throws if the platform has no webview runtime available — callers should
/// catch and fall back to launching an external browser.
class MeonWebview {
  static Future<bool> isAvailable() => WebviewWindow.isWebviewAvailable();

  static Future<MeonWebviewOutcome> open({
    required String url,
    required String redirectUrl,
    String title = 'DigiLocker Verification',
  }) async {
    if (!await WebviewWindow.isWebviewAvailable()) {
      throw StateError('Webview runtime not available on this platform');
    }

    final webview = await WebviewWindow.create(
      configuration: CreateConfiguration(
        title: title,
        windowHeight: 760,
        windowWidth: 540,
      ),
    );

    final completer = Completer<MeonWebviewOutcome>();

    // Normalize for prefix matching — DigiLocker appends query params.
    final redirectPrefix = _stripQuery(redirectUrl);

    webview.addOnUrlRequestCallback((requestedUrl) {
      debugPrint('[MeonWebview] nav: $requestedUrl');
      if (_stripQuery(requestedUrl).startsWith(redirectPrefix)) {
        if (!completer.isCompleted) {
          completer.complete(MeonWebviewOutcome.redirected);
        }
        webview.close();
      }
    });

    webview.onClose.whenComplete(() {
      if (!completer.isCompleted) {
        completer.complete(MeonWebviewOutcome.closed);
      }
    });

    webview.launch(url);
    return completer.future;
  }

  static String _stripQuery(String url) {
    final q = url.indexOf('?');
    return q == -1 ? url : url.substring(0, q);
  }
}
