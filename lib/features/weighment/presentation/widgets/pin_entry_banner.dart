import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

class PinEntryBanner extends StatefulWidget {
  final void Function(String pin) onSubmit;
  final VoidCallback? onCancel;
  final String? errorMessage;

  const PinEntryBanner({super.key, required this.onSubmit, this.onCancel, this.errorMessage});

  @override
  State<PinEntryBanner> createState() => _PinEntryBannerState();
}

class _PinEntryBannerState extends State<PinEntryBanner> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _ctrl.text.trim();
    if (pin.length >= 4) {
      widget.onSubmit(pin);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 96,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12.rs),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3), width: 2),
      ),
      child: Row(
        children: [
          // Lock icon
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10.rs),
            ),
            child: Icon(Icons.lock_outlined, size: 20, color: scheme.primary),
          ),
          SizedBox(width: 16.rs),

          // PIN input
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter your PIN to verify',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                ),
                SizedBox(height: 6.rs),
                SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    obscureText: true,
                    maxLength: 6,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 8, color: scheme.onSurface),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '••••',
                      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.3), letterSpacing: 8),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.rs), borderSide: BorderSide(color: scheme.outlineVariant)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.rs), borderSide: BorderSide(color: scheme.primary, width: 2)),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                if (widget.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(widget.errorMessage!, style: TextStyle(fontSize: 10, color: scheme.error)),
                  ),
              ],
            ),
          ),

          SizedBox(width: 12.rs),

          // Submit button
          FilledButton(
            onPressed: _submit,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
            child: const Text('Verify', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),

          // Cancel
          if (widget.onCancel != null) ...[
            SizedBox(width: 8.rs),
            IconButton(
              onPressed: widget.onCancel,
              icon: Icon(Icons.close_outlined, size: 18, color: scheme.onSurfaceVariant),
              tooltip: 'Cancel',
            ),
          ],
        ],
      ),
    );
  }
}
