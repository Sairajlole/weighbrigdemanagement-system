import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

enum _PrimaryAction { newSession, capture, print }

class WeighmentActionBar extends StatelessWidget {
  final bool hasSession;
  final bool hasFirstWeight;
  final bool isComplete;
  final bool canCapture;
  final bool canManualEntry;
  final VoidCallback onNew;
  final VoidCallback onCapture;
  final VoidCallback? onManualEntry;
  final VoidCallback onSaveWait;
  final VoidCallback onPrint;
  final VoidCallback onCancel;
  final bool gateEnabled;
  final VoidCallback? onOpenGate;
  final VoidCallback? onCloseGate;
  final VoidCallback? onCustomerSearch;
  final bool printConfigured;

  const WeighmentActionBar({
    super.key,
    required this.hasSession,
    required this.hasFirstWeight,
    required this.isComplete,
    required this.canCapture,
    this.canManualEntry = false,
    required this.onNew,
    required this.onCapture,
    this.onManualEntry,
    required this.onSaveWait,
    required this.onPrint,
    required this.onCancel,
    this.gateEnabled = false,
    this.onOpenGate,
    this.onCloseGate,
    this.onCustomerSearch,
    this.printConfigured = false,
  });

  _PrimaryAction get _primaryAction {
    if (isComplete) return _PrimaryAction.print;
    if (canCapture) return _PrimaryAction.capture;
    return _PrimaryAction.newSession;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final primary = _primaryAction;

    final newEnabled = !hasSession || isComplete;
    final leftButtons = <_BtnDef>[
      _BtnDef('NEW', 'F1', newEnabled, newEnabled ? onNew : null, isPrimary: primary == _PrimaryAction.newSession),
      _BtnDef('CAPTURE', 'F5', canCapture, canCapture ? onCapture : null, isPrimary: primary == _PrimaryAction.capture),
      if (canManualEntry && hasSession && !isComplete)
        _BtnDef('MANUAL', 'F3', true, onManualEntry),
      if (hasSession && hasFirstWeight && !isComplete)
        _BtnDef('SAVE', 'F4', true, onSaveWait),
    ];

    final rightButtons = <_BtnDef>[
      if (gateEnabled) _BtnDef('OPEN GATE', 'F6', true, onOpenGate),
      if (gateEnabled) _BtnDef('CLOSE GATE', 'F7', true, onCloseGate),
      if (hasSession) _BtnDef('SEARCH', 'F10', true, onCustomerSearch),
      _BtnDef('PRINT', 'F11', printConfigured, printConfigured ? onPrint : null, isPrimary: primary == _PrimaryAction.print),
      if (hasSession) _BtnDef('CANCEL', 'Esc', true, onCancel, destructive: true),
    ];

    return BottomAppBar(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      child: Row(
        children: [
          ..._buildGroup(leftButtons, scheme, textTheme),
          const Spacer(),
          ..._buildGroup(rightButtons, scheme, textTheme),
        ],
      ),
    );
  }

  List<Widget> _buildGroup(List<_BtnDef> buttons, ColorScheme scheme, TextTheme textTheme) {
    final widgets = <Widget>[];
    for (var i = 0; i < buttons.length; i++) {
      if (i > 0) widgets.add(SizedBox(width: 6.rs));
      widgets.add(_buildButton(buttons[i], scheme, textTheme));
    }
    return widgets;
  }

  Widget _buildButton(_BtnDef def, ColorScheme scheme, TextTheme textTheme) {
    final active = def.enabled && def.onPressed != null;
    final isPrimary = def.isPrimary && active;

    final ButtonStyle style;
    if (isPrimary) {
      style = FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const StadiumBorder(),
      );
    } else if (def.destructive && active) {
      style = FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: scheme.errorContainer,
        foregroundColor: scheme.onErrorContainer,
        shape: const StadiumBorder(),
      );
    } else {
      style = FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: active ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        foregroundColor: active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant.withValues(alpha: 0.4),
        shape: const StadiumBorder(),
      );
    }

    return SizedBox(
      height: 40,
      child: FilledButton(
        onPressed: active ? def.onPressed : null,
        style: style,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              def.label,
              style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(width: 6.rs),
            Text(
              def.shortcut,
              style: textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: isPrimary
                    ? scheme.onPrimary.withValues(alpha: 0.7)
                    : def.destructive && active
                        ? scheme.onErrorContainer.withValues(alpha: 0.7)
                        : active
                            ? scheme.onPrimaryContainer.withValues(alpha: 0.6)
                            : scheme.onSurfaceVariant.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BtnDef {
  final String label;
  final String shortcut;
  final bool enabled;
  final VoidCallback? onPressed;
  final bool destructive;
  final bool isPrimary;

  const _BtnDef(
    this.label,
    this.shortcut,
    this.enabled,
    this.onPressed, {
    this.destructive = false,
    this.isPrimary = false,
  });
}
