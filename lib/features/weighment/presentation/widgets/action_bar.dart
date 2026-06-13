import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

class WeighmentActionBar extends StatelessWidget {
  final bool hasSession;
  final bool hasFirstWeight;
  final bool isComplete;
  final bool canCapture;
  // Whether the CAPTURE button is shown at all (live scale + verified).
  final bool showCapture;
  final bool canManualEntry;
  final bool canSave;
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
  // Operator verification is enforced and not yet satisfied this weighment —
  // hide SEARCH and PRINT until the operator is verified.
  final bool lockedUntilVerified;

  const WeighmentActionBar({
    super.key,
    required this.hasSession,
    required this.hasFirstWeight,
    required this.isComplete,
    required this.canCapture,
    this.showCapture = true,
    this.canManualEntry = false,
    this.canSave = true,
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
    this.lockedUntilVerified = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // NEW is hidden once a weighment is in the workflow cycle, and reappears
    // when it's finished (completed) or cleared (no session).
    final newEnabled = !hasSession || isComplete;
    final leftButtons = <_BtnDef>[
      if (newEnabled)
        _BtnDef('NEW', 'F1', true, onNew),
      if (showCapture)
        _BtnDef('CAPTURE', 'F5', canCapture, canCapture ? onCapture : null),
      if (canManualEntry && hasSession && !isComplete)
        _BtnDef('MANUAL', 'F3', true, onManualEntry),
      // SAVE is always visible during a weighment; greyed (but still tappable, so
      // it can flag the missing fields) until the required info is filled.
      if (hasSession && hasFirstWeight && !isComplete)
        _BtnDef('SAVE', 'F4', true, onSaveWait, muted: !canSave),
    ];

    final rightButtons = <_BtnDef>[
      if (gateEnabled) _BtnDef('OPEN GATE', 'F6', true, onOpenGate),
      if (gateEnabled) _BtnDef('CLOSE GATE', 'F7', true, onCloseGate),
      // Search (Browse) and Print are available any time — except while an
      // unverified operator is mid-verification (hidden until verified).
      if (!lockedUntilVerified) _BtnDef('SEARCH', 'F10', true, onCustomerSearch),
      if (!lockedUntilVerified) _BtnDef('PRINT', 'F11', printConfigured, printConfigured ? onPrint : null),
      if (hasSession) _BtnDef('CANCEL', 'Esc', true, onCancel, destructive: true),
    ];

    return BottomAppBar(
      height: 68,
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 20),
      // Transparent background — only the F-key buttons carry colour.
      color: Colors.transparent,
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
    // A `muted` button stays tappable (so SAVE can flag missing fields) but is
    // styled as if disabled.
    final showActive = active && !def.muted;

    // All actionable buttons share one neutral style; only CANCEL/Esc is red.
    final ButtonStyle style = (def.destructive && showActive)
        ? FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: scheme.errorContainer,
            foregroundColor: scheme.onErrorContainer,
            shape: const StadiumBorder(),
          )
        : FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: showActive ? scheme.primaryContainer : scheme.surfaceContainerHighest,
            foregroundColor: showActive ? scheme.onPrimaryContainer : scheme.onSurfaceVariant.withValues(alpha: 0.4),
            shape: const StadiumBorder(),
          );

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
                color: def.destructive && showActive
                    ? scheme.onErrorContainer.withValues(alpha: 0.7)
                    : showActive
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
  final bool muted;

  const _BtnDef(
    this.label,
    this.shortcut,
    this.enabled,
    this.onPressed, {
    this.destructive = false,
    this.muted = false,
  });
}
