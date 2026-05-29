import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:weighbridgemanagement/shared/providers/scale_provider.dart';
import 'package:weighbridgemanagement/shared/services/scale_service.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

class LiveWeightBanner extends ConsumerStatefulWidget {
  final bool canManualEntry;
  final ValueChanged<double>? onManualSubmit;

  const LiveWeightBanner({super.key, this.canManualEntry = false, this.onManualSubmit});

  @override
  ConsumerState<LiveWeightBanner> createState() => LiveWeightBannerState();
}

class LiveWeightBannerState extends ConsumerState<LiveWeightBanner> {
  bool _editing = false;
  final _controller = TextEditingController();
  late final FocusNode _focusNode = FocusNode(onKeyEvent: _handleKey);

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      cancelEditing();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void startEditing() {
    setState(() {
      _editing = true;
      _controller.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _submitManual() {
    final weight = double.tryParse(_controller.text);
    if (weight != null && weight > 0) {
      widget.onManualSubmit?.call(weight);
      setState(() => _editing = false);
    }
  }

  bool get isEditing => _editing;

  void cancelEditing() {
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final reading = ref.watch(scaleReadingProvider).valueOrNull ?? ScaleReading.zero;
    final status = ref.watch(scaleStatusProvider).valueOrNull ?? ScaleConnectionStatus.disconnected;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final connected = status == ScaleConnectionStatus.connected;
    final weight = reading.weight;
    final stable = reading.stable;

    final String weightText;
    if (connected) {
      final raw = weight.toStringAsFixed(0);
      if (raw.length > 3) {
        weightText = '${raw.substring(0, raw.length - 3)},${raw.substring(raw.length - 3)}';
      } else {
        weightText = raw;
      }
    } else {
      weightText = '---,---';
    }

    final Color accentColor;
    if (!connected) {
      accentColor = scheme.outlineVariant.withValues(alpha: 0.4);
    } else if (stable) {
      accentColor = scheme.onSurface;
    } else {
      accentColor = scheme.onSurfaceVariant.withValues(alpha: 0.6);
    }

    return Card.outlined(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.rs),
        side: BorderSide(
          color: _editing
              ? Colors.blue.withValues(alpha: 0.5)
              : accentColor.withValues(alpha: connected ? 0.3 : 0.2),
          width: _editing ? 2 : (stable ? 1.5 : 1),
        ),
      ),
      color: scheme.surfaceContainerLowest,
      child: SizedBox(
        height: 200,
        child: Stack(
          children: [
            // Status chip — top left
            Positioned(
              top: 10,
              left: 12,
              child: _editing
                  ? RawChip(
                      avatar: const Icon(Icons.edit_outlined, size: 14, color: Colors.blue),
                      label: Text(
                        'MANUAL ENTRY',
                        style: textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: Colors.blue,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.dialog,
                        side: BorderSide(color: Colors.blue.withValues(alpha: 0.3)),
                      ),
                      backgroundColor: Colors.blue.withValues(alpha: 0.08),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    )
                  : connected
                      ? RawChip(
                          avatar: Icon(
                            stable ? Icons.check_circle_outlined : Icons.pending_outlined,
                            size: 14,
                            color: accentColor,
                          ),
                          label: Text(
                            stable ? 'STABLE' : 'UNSTABLE',
                            style: textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: accentColor,
                            ),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.dialog,
                            side: BorderSide(color: accentColor.withValues(alpha: 0.2)),
                          ),
                          backgroundColor: accentColor.withValues(alpha: 0.06),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        )
                      : RawChip(
                          avatar: Icon(
                            Icons.link_off_outlined,
                            size: 14,
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                          ),
                          label: Text(
                            'DISCONNECTED',
                            style: textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                              color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                            ),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.dialog,
                            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                          ),
                          backgroundColor: scheme.surfaceContainerLow,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
            ),


            // Weight display or manual input — centered
            Center(
              child: _editing
                  ? _buildManualInput(scheme)
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$weightText KG',
                        style: TextStyle(
                          fontSize: 300,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontFamily: 'monospace',
                          color: connected && stable ? Colors.green : scheme.error,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualInput(ColorScheme scheme) {
    const digits = 6;
    final input = _controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    final padded = input.padLeft(digits, '-');
    final raw = padded.length > digits ? padded.substring(padded.length - digits) : padded;
    // Format as ---,--- with comma between position 3 and 4
    final display = '${raw.substring(0, 3)},${raw.substring(3)}';

    return Stack(
      children: [
        Opacity(
          opacity: 0,
          child: SizedBox(
            width: 1,
            height: 1,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(digits),
              ],
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submitManual(),
            ),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
            TextSpan(
              children: [
                for (int i = 0; i < display.length; i++)
                  TextSpan(
                    text: display[i],
                    style: TextStyle(
                      color: display[i] == '-' || display[i] == ','
                          ? Colors.blue.withValues(alpha: 0.25)
                          : Colors.blue,
                    ),
                  ),
                const TextSpan(text: ' KG'),
              ],
              style: const TextStyle(
                fontSize: 300,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
                fontFamily: 'monospace',
                color: Colors.blue,
                letterSpacing: 4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
