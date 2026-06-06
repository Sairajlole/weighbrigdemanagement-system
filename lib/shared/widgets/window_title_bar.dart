import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

const _kTitleBarHeight = 32.0;

class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onDoubleTap: () async {
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      child: DragToMoveArea(
        child: Container(
          height: _kTitleBarHeight,
          color: scheme.surfaceContainerLow,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Text(
                'tulanam',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              const _WindowButtons(),
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowButtons extends StatelessWidget {
  const _WindowButtons();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowButton(
          icon: Icons.minimize_rounded,
          onTap: windowManager.minimize,
          hoverColor: scheme.surfaceContainerHighest,
          iconColor: scheme.onSurfaceVariant,
        ),
        _MaximizeButton(
          hoverColor: scheme.surfaceContainerHighest,
          iconColor: scheme.onSurfaceVariant,
        ),
        _WindowButton(
          icon: Icons.close_rounded,
          onTap: windowManager.close,
          hoverColor: const Color(0xFFE81123),
          iconColor: scheme.onSurfaceVariant,
          hoverIconColor: Colors.white,
        ),
      ],
    );
  }
}

class _MaximizeButton extends StatefulWidget {
  final Color hoverColor;
  final Color iconColor;

  const _MaximizeButton({required this.hoverColor, required this.iconColor});

  @override
  State<_MaximizeButton> createState() => _MaximizeButtonState();
}

class _MaximizeButtonState extends State<_MaximizeButton> with WindowListener {
  bool _isMaximized = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _checkMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (mounted && maximized != _isMaximized) {
      setState(() => _isMaximized = maximized);
    }
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);
  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  @override
  Widget build(BuildContext context) {
    return _WindowButton(
      icon: _isMaximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
      iconSize: _isMaximized ? 12 : 15,
      onTap: () async {
        if (_isMaximized) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      hoverColor: widget.hoverColor,
      iconColor: widget.iconColor,
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback onTap;
  final Color hoverColor;
  final Color iconColor;
  final Color? hoverIconColor;

  const _WindowButton({
    required this.icon,
    this.iconSize = 15,
    required this.onTap,
    required this.hoverColor,
    required this.iconColor,
    this.hoverIconColor,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 46,
          height: _kTitleBarHeight,
          alignment: Alignment.center,
          color: _hovering ? widget.hoverColor : Colors.transparent,
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: _hovering && widget.hoverIconColor != null
                ? widget.hoverIconColor
                : widget.iconColor,
          ),
        ),
      ),
    );
  }
}
