import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Renders the Meon DigiLocker authorization page *inline* (embedded inside the
/// surrounding widget, not a separate OS window) on platforms with an
/// embeddable WebView — Windows (WebView2) and macOS (WKWebView).
///
/// The view sizes itself to the loaded page's content height (clamped to
/// [minHeight]..[maxHeight]), so the sign-in page stays compact while the
/// consent / document-selection page gets the room it needs.
///
/// Calls [onRedirected] once the page navigates to the redirect/thank-you URL,
/// which signals the DigiLocker flow finished and data can be fetched.
class MeonInlineWebview extends StatefulWidget {
  final String url;
  final String redirectUrl;
  final VoidCallback onRedirected;
  final ValueChanged<String>? onError;

  /// The view grows/shrinks to fit the page, clamped to this range.
  final double minHeight;
  final double maxHeight;

  const MeonInlineWebview({
    super.key,
    required this.url,
    required this.redirectUrl,
    required this.onRedirected,
    this.onError,
    this.minHeight = 380,
    this.maxHeight = 760,
  });

  @override
  State<MeonInlineWebview> createState() => _MeonInlineWebviewState();
}

class _MeonInlineWebviewState extends State<MeonInlineWebview> {
  bool _loading = true;
  bool _redirectFired = false;
  InAppWebViewController? _controller;
  double _contentHeight = 0;
  bool _dark = false;

  late final String _redirectPrefix = _stripQuery(widget.redirectUrl);

  static String _stripQuery(String url) {
    final q = url.indexOf('?');
    return q == -1 ? url : url.substring(0, q);
  }

  void _checkRedirect(String? url) {
    if (url == null || _redirectFired) return;
    if (_stripQuery(url).startsWith(_redirectPrefix)) {
      _redirectFired = true;
      widget.onRedirected();
    }
  }

  void _setContentHeight(double h) {
    if (h <= 0 || !mounted) return;
    final clamped = h.clamp(widget.minHeight, widget.maxHeight);
    if ((clamped - _contentHeight).abs() > 1) {
      setState(() => _contentHeight = clamped);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Track the app's brightness; if it flips while the webview is open,
    // re-skin the already-loaded page instantly.
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark != _dark) {
      _dark = dark;
      _applyTheme();
    }
  }

  /// Injects (or removes) a dark-mode stylesheet so the third-party DigiLocker
  /// page matches the app's theme. Uses a smart invert (images counter-inverted)
  /// toggled by adding/removing a single tagged <style> element.
  Future<void> _applyTheme() async {
    final c = _controller;
    if (c == null) return;
    const darkCss =
        "html{filter:invert(1) hue-rotate(180deg) !important;background:#ffffff !important;}"
        "img,picture,video,svg,canvas,iframe,[style*='background-image'],[style*='url(']"
        "{filter:invert(1) hue-rotate(180deg) !important;}";
    final css = _dark ? darkCss : '';
    final js = "(function(){var id='__app_dark_mode__';var el=document.getElementById(id);"
        "var css=${jsonEncode(css)};"
        "if(css){if(!el){el=document.createElement('style');el.id=id;(document.head||document.documentElement).appendChild(el);}el.textContent=css;}"
        "else if(el){el.remove();}})();";
    try {
      await c.evaluateJavascript(source: js);
    } catch (_) {}
  }

  /// Read the page's full content height and resize to it.
  Future<void> _measure() async {
    final c = _controller;
    if (c == null) return;
    try {
      final result = await c.evaluateJavascript(
        source:
            'Math.max(document.body ? document.body.scrollHeight : 0, document.documentElement ? document.documentElement.scrollHeight : 0)',
      );
      final h = result is num ? result.toDouble() : double.tryParse('$result');
      if (h != null) _setContentHeight(h);
    } catch (_) {
      // Measurement is best-effort; the clamp keeps a sane fallback height.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: SizedBox(
          height: _contentHeight <= 0 ? widget.minHeight : _contentHeight,
          width: double.infinity,
          child: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                initialSettings: InAppWebViewSettings(
                  transparentBackground: true,
                  useShouldOverrideUrlLoading: true,
                  javaScriptEnabled: true,
                ),
                onWebViewCreated: (c) => _controller = c,
                onContentSizeChanged: (_, __, newSize) => _setContentHeight(newSize.height),
                onLoadStart: (_, url) {
                  if (mounted) setState(() => _loading = true);
                  _checkRedirect(url?.toString());
                },
                onLoadStop: (_, url) async {
                  if (mounted) setState(() => _loading = false);
                  _checkRedirect(url?.toString());
                  await _applyTheme();
                  // Measure now and again shortly after, for late-rendering content.
                  await _measure();
                  await Future.delayed(const Duration(milliseconds: 450));
                  await _measure();
                },
                onUpdateVisitedHistory: (_, url, __) => _checkRedirect(url?.toString()),
                shouldOverrideUrlLoading: (_, action) async {
                  _checkRedirect(action.request.url?.toString());
                  return NavigationActionPolicy.ALLOW;
                },
                onReceivedError: (_, request, error) {
                  // Only surface errors for the main frame's initial load.
                  if (request.isForMainFrame ?? false) {
                    widget.onError?.call(error.description);
                  }
                },
              ),
              if (_loading)
                Container(
                  color: scheme.surface.withValues(alpha: 0.6),
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
