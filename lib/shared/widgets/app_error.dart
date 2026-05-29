import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

class AppError {
  AppError._();

  static void show(BuildContext context, String message, {VoidCallback? retry, Duration duration = const Duration(seconds: 4)}) {
    final scheme = Theme.of(context).colorScheme;
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => _ErrorToast(
        message: message,
        scheme: scheme,
        retry: retry,
        onDismiss: () => entry.remove(),
      ),
    );

    overlay.insert(entry);
    Future.delayed(duration, () {
      if (entry.mounted) entry.remove();
    });
  }

  static Future<bool?> confirm(BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(message, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: scheme.error)
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  static void success(BuildContext context, String message) {
    final scheme = Theme.of(context).colorScheme;
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => _SuccessToast(
        message: message,
        scheme: scheme,
        onDismiss: () => entry.remove(),
      ),
    );

    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () {
      if (entry.mounted) entry.remove();
    });
  }
}

class _ErrorToast extends StatelessWidget {
  final String message;
  final ColorScheme scheme;
  final VoidCallback? retry;
  final VoidCallback onDismiss;

  const _ErrorToast({required this.message, required this.scheme, this.retry, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 16.rs,
      right: 16.rs,
      child: Material(
        elevation: 8,
        borderRadius: AppRadius.card,
        color: scheme.errorContainer,
        child: Container(
          constraints: BoxConstraints(maxWidth: 360.rs),
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 18.rs, color: scheme.error),
              SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  message,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onErrorContainer),
                ),
              ),
              if (retry != null) ...[
                SizedBox(width: AppSpacing.sm),
                TextButton(
                  onPressed: () { onDismiss(); retry!(); },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('Retry', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.error)),
                ),
              ],
              SizedBox(width: AppSpacing.xs),
              GestureDetector(
                onTap: onDismiss,
                child: Icon(Icons.close_rounded, size: 14.rs, color: scheme.onErrorContainer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessToast extends StatelessWidget {
  final String message;
  final ColorScheme scheme;
  final VoidCallback onDismiss;

  const _SuccessToast({required this.message, required this.scheme, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 16.rs,
      right: 16.rs,
      child: Material(
        elevation: 8,
        borderRadius: AppRadius.card,
        color: const Color(0xFFDCFCE7),
        child: Container(
          constraints: BoxConstraints(maxWidth: 360.rs),
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 18.rs, color: const Color(0xFF16A34A)),
              SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF166534)),
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              GestureDetector(
                onTap: onDismiss,
                child: Icon(Icons.close_rounded, size: 14.rs, color: const Color(0xFF166534)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
