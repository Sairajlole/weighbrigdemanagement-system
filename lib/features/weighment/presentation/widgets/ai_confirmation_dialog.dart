import 'dart:typed_data';

import 'package:flutter/material.dart';

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
        ? Colors.green
        : widget.confidence >= 0.7
            ? Colors.orange
            : Colors.red;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.smart_toy_rounded, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(widget.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: confColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('$confPercent%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: confColor)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (widget.frame != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(widget.frame!, height: 140, width: double.infinity, fit: BoxFit.cover),
                ),
                const SizedBox(height: 16),
              ],

              Text(widget.fieldLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),

              if (!_editing) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
              const SizedBox(height: 8),

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
                const SizedBox(height: 12),
              ],

              const SizedBox(height: 16),
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
                      icon: const Icon(Icons.edit_rounded, size: 14),
                      label: const Text('Correct'),
                    ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () {
                      final value = _editing ? _controller.text.trim() : widget.prediction;
                      Navigator.of(context).pop(AiConfirmationResult(
                        confirmedValue: value,
                        wasCorrect: value == widget.prediction,
                      ));
                    },
                    icon: const Icon(Icons.check_rounded, size: 16),
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
