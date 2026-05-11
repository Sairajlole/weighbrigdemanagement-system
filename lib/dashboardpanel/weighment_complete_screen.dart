import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:weighbridgemanagement/core/services/weighment_engine.dart';

class WeighmentCompleteScreen extends ConsumerWidget {
  const WeighmentCompleteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engineState = ref.watch(weighmentEngineProvider);
    final session = engineState.session;
    final colorScheme = Theme.of(context).colorScheme;

    if (session == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("No weighment data"),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pushReplacementNamed(context, '/dashboard'),
                child: const Text("Go to Dashboard"),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: Center(
        child: Container(
          width: 600,
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Success icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check, size: 40, color: colorScheme.primary),
              ),
              const SizedBox(height: 20),

              Text(
                "Weighment Complete",
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                "All steps completed successfully.",
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 28),

              // Summary card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _summaryRow("RST Number", "#${session.rstNumber ?? '--'}", colorScheme),
                    _summaryRow("Vehicle", session.vehicleNumber ?? '--', colorScheme),
                    _summaryRow("Customer", session.customerName ?? '--', colorScheme),
                    _summaryRow("Material", session.material ?? '--', colorScheme),
                    _summaryRow("Gross Weight", session.grossWeight != null ? "${session.grossWeight!.toStringAsFixed(0)} kg" : '--', colorScheme),
                    if (session.tareWeight != null)
                      _summaryRow("Tare Weight", "${session.tareWeight!.toStringAsFixed(0)} kg", colorScheme),
                    if (session.netWeight != null)
                      _summaryRow("Net Weight", "${session.netWeight!.toStringAsFixed(0)} kg", colorScheme),
                    _summaryRow("Time", DateFormat('dd MMM yyyy, hh:mm a').format(session.startedAt), colorScheme),
                    const SizedBox(height: 12),
                    Divider(color: colorScheme.outlineVariant),
                    const SizedBox(height: 12),
                    // Status indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _statusPill("Printed", session.printed, colorScheme),
                        _statusPill("Sheets", session.sheetsSynced, colorScheme),
                        _statusPill("WhatsApp", session.whatsappSent, colorScheme),
                        _statusPill("Billing", session.billingSynced, colorScheme),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // Reprint
                      },
                      icon: const Icon(Icons.print, size: 18),
                      label: const Text("Reprint"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // Share PDF
                      },
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text("Share"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () {
                        ref.read(weighmentEngineProvider.notifier).cancelWeighment();
                        Navigator.pushReplacementNamed(context, '/dashboard');
                      },
                      icon: const Icon(Icons.dashboard, size: 18),
                      label: const Text("Back to Dashboard"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    ref.read(weighmentEngineProvider.notifier).cancelWeighment();
                    ref.read(weighmentEngineProvider.notifier).startWeighment();
                    Navigator.pushReplacementNamed(context, '/weighmentLive');
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text("Start Next Weighment"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String label, bool done, ColorScheme colorScheme) {
    return Column(
      children: [
        Icon(
          done ? Icons.check_circle : Icons.pending,
          size: 20,
          color: done ? colorScheme.primary : colorScheme.outlineVariant,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: done ? colorScheme.primary : colorScheme.onSurfaceVariant,
            fontWeight: done ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
