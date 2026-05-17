import 'dart:async';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/general_settings_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';

class SecurityOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const SecurityOverlay({super.key, required this.child});

  @override
  ConsumerState<SecurityOverlay> createState() => _SecurityOverlayState();
}

class _SecurityOverlayState extends ConsumerState<SecurityOverlay> with WidgetsBindingObserver {
  bool _appInactive = false;
  Timer? _watermarkTimer;
  String _watermarkTime = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startWatermarkTimer();
    _checkRemoteDesktop();
    _checkUsbDevices();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watermarkTimer?.cancel();
    super.dispose();
  }

  void _startWatermarkTimer() {
    _watermarkTime = getTimeFormatter(ref.read(timeFormatProvider)).format(DateTime.now());
    _watermarkTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _watermarkTime = getTimeFormatter(ref.read(timeFormatProvider)).format(DateTime.now()));
    });
  }

  Future<void> _checkRemoteDesktop() async {
    if (!mounted) return;
    final monitor = ref.read(remoteDesktopMonitorProvider);
    if (!monitor.enabled) return;

    final running = await monitor.getRunningRemoteApps();
    if (!mounted) return;
    if (running.isNotEmpty) {
      await monitor.killRemoteApps();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Blocked remote desktop: ${running.join(", ")}'),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 5),
      ));
    }

    Future.delayed(const Duration(seconds: 30), () {
      if (mounted) _checkRemoteDesktop();
    });
  }

  Future<void> _checkUsbDevices() async {
    if (!mounted) return;
    final usbMonitor = ref.read(usbMonitorProvider);
    if (!usbMonitor.enabled) return;

    final hasUsb = await usbMonitor.hasExternalStorage();
    if (!mounted) return;
    if (hasUsb) {
      await usbMonitor.ejectAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('USB storage detected and ejected — external drives are restricted'),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 5),
      ));
    }

    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) _checkUsbDevices();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final settings = ref.read(securitySettingsProvider).valueOrNull ?? const SecuritySettings();

    if (settings.dimOnInactiveWindow || settings.preventScreenshots) {
      if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
        setState(() => _appInactive = true);
      } else if (state == AppLifecycleState.resumed) {
        setState(() => _appInactive = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(securitySettingsProvider);
    final settings = settingsAsync.valueOrNull ?? const SecuritySettings();
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.email ?? user?.displayName ?? 'Unknown';

    final showOverlay = _appInactive && (settings.preventScreenshots || settings.dimOnInactiveWindow);

    return Stack(
      children: [
        widget.child,

        // Dim/blank overlay when inactive AND setting is enabled
        if (showOverlay)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: settings.preventScreenshots ? 1.0 : 0.85),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_rounded, size: 48, color: Colors.white.withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    Text(
                      settings.preventScreenshots ? 'Screen capture blocked' : 'Content hidden',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Watermark overlay
        if (settings.watermarkEnabled && !_appInactive)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _WatermarkPainter(
                  text: '$userName  $_watermarkTime',
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _WatermarkPainter extends CustomPainter {
  final String text;

  _WatermarkPainter({required this.text});

  @override
  void paint(Canvas canvas, Size size) {
    final textStyle = TextStyle(
      color: Colors.black.withValues(alpha: 0.04),
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );

    final textSpan = TextSpan(text: text, style: textStyle);
    final textPainter = TextPainter(text: textSpan, textDirection: ui.TextDirection.ltr);
    textPainter.layout();

    canvas.save();
    canvas.rotate(-0.3);

    for (double y = -size.height; y < size.height * 2; y += 100) {
      for (double x = -size.width; x < size.width * 2; x += 250) {
        textPainter.paint(canvas, Offset(x, y));
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_WatermarkPainter oldDelegate) => oldDelegate.text != text;
}
