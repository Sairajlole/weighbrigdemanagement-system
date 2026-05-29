import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

class AiConfirmationResult {
  final String confirmedValue;
  final bool wasCorrect;
  final bool wasSkipped;

  const AiConfirmationResult({required this.confirmedValue, required this.wasCorrect, this.wasSkipped = false});
}

class AiConfirmationDialog extends StatefulWidget {
  final String title;
  final String prediction;
  final double confidence;
  final Uint8List? frame;
  final List<String>? suggestions;
  final String fieldLabel;

  const AiConfirmationDialog({
    super.key,
    required this.title,
    required this.prediction,
    required this.confidence,
    this.frame,
    this.suggestions,
    this.fieldLabel = 'Value',
  });

  @override
  State<AiConfirmationDialog> createState() => _AiConfirmationDialogState();
}

class _AiConfirmationDialogState extends State<AiConfirmationDialog> {
  late final TextEditingController _controller;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.prediction);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final confPercent = (widget.confidence * 100).toStringAsFixed(0);
    final confColor = widget.confidence >= 0.9
        ? scheme.onSurface
        : widget.confidence >= 0.7
            ? scheme.onSurfaceVariant
            : scheme.error;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.rs)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: EdgeInsets.all(24.rs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.memory_outlined, size: 20, color: scheme.primary),
                  SizedBox(width: 8.rs),
                  Text(widget.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: confColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4.rs),
                    ),
                    child: Text('$confPercent%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: confColor)),
                  ),
                ],
              ),
              SizedBox(height: 16.rs),

              if (widget.frame != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8.rs),
                  child: Image.memory(widget.frame!, height: 140, width: double.infinity, fit: BoxFit.cover),
                ),
                SizedBox(height: 16.rs),
              ],

              Text(widget.fieldLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
              SizedBox(height: 6.rs),

              if (!_editing) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8.rs),
                    border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    widget.prediction.isEmpty ? '(No detection)' : widget.prediction,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1, color: scheme.onSurface),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.rs)),
                  ),
                ),
              ],
              SizedBox(height: 8.rs),

              if (widget.suggestions != null && widget.suggestions!.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  children: widget.suggestions!.map((s) => ActionChip(
                    label: Text(s, style: const TextStyle(fontSize: 11)),
                    onPressed: () {
                      _controller.text = s;
                      setState(() => _editing = true);
                    },
                    visualDensity: VisualDensity.compact,
                  )).toList(),
                ),
                SizedBox(height: 12.rs),
              ],

              SizedBox(height: 16.rs),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(const AiConfirmationResult(confirmedValue: '', wasCorrect: false, wasSkipped: true)),
                    child: Text('Skip', style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                  const Spacer(),
                  if (!_editing)
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _editing = true),
                      icon: const Icon(Icons.edit_outlined, size: 14),
                      label: const Text('Correct'),
                    ),
                  SizedBox(width: 8.rs),
                  FilledButton.icon(
                    onPressed: () {
                      final value = _editing ? _controller.text.trim() : widget.prediction;
                      Navigator.of(context).pop(AiConfirmationResult(
                        confirmedValue: value,
                        wasCorrect: value == widget.prediction,
                      ));
                    },
                    icon: const Icon(Icons.check_outlined, size: 16),
                    label: Text(_editing ? 'Save' : 'Confirm'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<AiConfirmationResult?> showAiConfirmation(
  BuildContext context, {
  required String title,
  required String prediction,
  required double confidence,
  Uint8List? frame,
  List<String>? suggestions,
  String fieldLabel = 'Value',
}) {
  return showDialog<AiConfirmationResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AiConfirmationDialog(
      title: title,
      prediction: prediction,
      confidence: confidence,
      frame: frame,
      suggestions: suggestions,
      fieldLabel: fieldLabel,
    ),
  );
}
