import 'package:flutter/material.dart';

class WeighmentActionBar extends StatelessWidget {
  final bool hasSession;
  final bool hasFirstWeight;
  final bool isComplete;
  final bool isMultiEntry;
  final bool canCapture;
  final bool canManualEntry;
  final VoidCallback onNew;
  final VoidCallback onCapture;
  final VoidCallback? onManualEntry;
  final VoidCallback onSaveWait;
  final VoidCallback onPrint;
  final VoidCallback onDone;
  final VoidCallback onCancel;

  const WeighmentActionBar({
    super.key,
    required this.hasSession,
    required this.hasFirstWeight,
    required this.isComplete,
    required this.isMultiEntry,
    required this.canCapture,
    this.canManualEntry = false,
    required this.onNew,
    required this.onCapture,
    this.onManualEntry,
    required this.onSaveWait,
    required this.onPrint,
    required this.onDone,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          // Left side: primary actions
          if (!hasSession) ...[
            _ActionButton(
              icon: Icons.add_rounded,
              label: 'New Weighment',
              shortcut: 'F2',
              onPressed: onNew,
              filled: true,
              scheme: scheme,
            ),
          ],

          if (hasSession && !isComplete) ...[
            _ActionButton(
              icon: Icons.camera_alt_rounded,
              label: 'Capture Weight',
              shortcut: 'F5',
              onPressed: canCapture ? onCapture : null,
              filled: true,
              scheme: scheme,
            ),
            if (canManualEntry && onManualEntry != null) ...[
              const SizedBox(width: 10),
              _ActionButton(
                icon: Icons.edit_rounded,
                label: 'Manual',
                onPressed: onManualEntry,
                scheme: scheme,
              ),
            ],
            if (isMultiEntry && hasFirstWeight) ...[
              const SizedBox(width: 10),
              _ActionButton(
                icon: Icons.save_rounded,
                label: 'Save & Wait',
                shortcut: 'F4',
                onPressed: onSaveWait,
                scheme: scheme,
              ),
            ],
          ],

          if (isComplete) ...[
            _ActionButton(
              icon: Icons.print_rounded,
              label: 'Print Slip',
              shortcut: 'F4',
              onPressed: onPrint,
              scheme: scheme,
            ),
            const SizedBox(width: 10),
            _ActionButton(
              icon: Icons.check_circle_rounded,
              label: 'Done — Next',
              onPressed: onDone,
              filled: true,
              color: Colors.green,
              scheme: scheme,
            ),
          ],

          const Spacer(),

          // Right side: cancel
          if (hasSession)
            _ActionButton(
              icon: Icons.close_rounded,
              label: 'Cancel',
              shortcut: 'Esc',
              onPressed: onCancel,
              color: scheme.error,
              scheme: scheme,
            ),

          if (!hasSession)
            Text(
              'Press F2 to begin weighment',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? shortcut;
  final VoidCallback? onPressed;
  final bool filled;
  final Color? color;
  final ColorScheme scheme;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.shortcut,
    this.onPressed,
    this.filled = false,
    this.color,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final btnColor = color ?? scheme.primary;

    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            if (shortcut != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(shortcut!, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
        style: FilledButton.styleFrom(
          backgroundColor: onPressed != null ? btnColor : null,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: onPressed != null ? btnColor : null),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: onPressed != null ? btnColor : null)),
          if (shortcut != null) ...[
            const SizedBox(width: 6),
            Text(shortcut!, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
          ],
        ],
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: BorderSide(color: (onPressed != null ? btnColor : scheme.outlineVariant).withValues(alpha: 0.4)),
      ),
    );
  }
}
