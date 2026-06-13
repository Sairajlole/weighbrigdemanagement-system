import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/ip_location_provider.dart';
import 'package:weighbridgemanagement/shared/services/sun_position.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/widgets/setup_background.dart';

/// Wraps a screen and, after [idleDelay] with no pointer/keyboard activity,
/// overlays a full-screen screensaver (the welcome-page background art) ON TOP
/// of the child — the child stays mounted underneath. Any interaction dismisses
/// the overlay and restarts the idle countdown.
///
/// Used by the session lock / authorization screen and the welcome page so both
/// behave like a screensaver without tearing down their own UI.
class ScreensaverScope extends StatefulWidget {
  final Widget child;
  final Duration idleDelay;

  /// When true and the app is in light mode, the screensaver follows day/night
  /// from the device's IP-geolocated sunrise/sunset: light art during the day,
  /// dark art after sunset — and it transitions live while displayed.
  final bool dayNightAware;

  const ScreensaverScope({
    super.key,
    required this.child,
    this.dayNightAware = false,
    // Fallback used pre-login (welcome page). The session-lock screen overrides
    // this with the admin's Security → "Lock-screen screensaver" timeout.
    this.idleDelay = const Duration(minutes: 5),
  });

  @override
  State<ScreensaverScope> createState() => _ScreensaverScopeState();
}

class _ScreensaverScopeState extends State<ScreensaverScope> {
  Timer? _timer;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _resetTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(widget.idleDelay, () {
      if (mounted) setState(() => _active = true);
    });
  }

  // Any interaction wakes the screen from the screensaver and restarts the idle
  // countdown. While inactive this only resets the timer (no rebuild).
  void _wake([_]) {
    if (_active && mounted) setState(() => _active = false);
    _resetTimer();
  }

  bool _onKey(KeyEvent _) {
    _wake();
    return false; // observe only — never consume the key
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _wake,
      onPointerMove: _wake,
      onPointerHover: _wake,
      onPointerSignal: _wake,
      child: Stack(
        children: [
          widget.child,
          // Overlay the screensaver on top — the child is untouched underneath.
          // The opaque background absorbs the first click (which only wakes the
          // screen), so it can't accidentally trigger anything below.
          if (_active) Positioned.fill(child: _ScreensaverScreen(dayNightAware: widget.dayNightAware)),
        ],
      ),
    );
  }
}

class _ScreensaverScreen extends ConsumerStatefulWidget {
  final bool dayNightAware;
  const _ScreensaverScreen({required this.dayNightAware});

  @override
  ConsumerState<_ScreensaverScreen> createState() => _ScreensaverScreenState();
}

class _ScreensaverScreenState extends ConsumerState<_ScreensaverScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Re-evaluate day/night while the screensaver stays up, so it crosses the
    // sunrise/sunset boundary live — no interaction needed.
    if (widget.dayNightAware) {
      _tick = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appBrightness = Theme.of(context).brightness;
    // In light mode, follow day/night (real sunrise/sunset from IP geolocation,
    // clock fallback until it resolves); dark mode stays dark. We only ever
    // override light → dark, never the reverse.
    Brightness target = appBrightness;
    if (widget.dayNightAware && appBrightness == Brightness.light) {
      final loc = ref.watch(ipLocationProvider).valueOrNull;
      target = sunBrightness(lat: loc?.lat, lng: loc?.lng);
    }

    Widget saver = Builder(
      builder: (context) => Material(
        color: Theme.of(context).colorScheme.surface,
        child: const SetupBackground(child: SizedBox.expand()),
      ),
    );

    if (target != appBrightness) {
      // Render the art under an overridden theme so the background follows the
      // day/night brightness instead of the app's.
      saver = Theme(
        data: target == Brightness.dark
            ? AppTheme.darkFrom(seed: AppTheme.defaultAccent)
            : AppTheme.lightFrom(seed: AppTheme.defaultAccent),
        child: saver,
      );
    }

    // Crossfade when the day/night brightness flips while the screensaver is up
    // (sunrise/sunset), so the change is smooth and needs no interaction.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 800),
      child: KeyedSubtree(key: ValueKey(target), child: saver),
    );
  }
}
