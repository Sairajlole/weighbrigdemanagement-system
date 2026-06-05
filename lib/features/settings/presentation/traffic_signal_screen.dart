import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/traffic_signal_provider.dart';
import 'package:weighbridgemanagement/shared/services/scale_service.dart';
import 'package:weighbridgemanagement/shared/services/traffic_signal_service.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/app_card.dart';

class TrafficSignalScreen extends ConsumerStatefulWidget {
  const TrafficSignalScreen({super.key});

  @override
  ConsumerState<TrafficSignalScreen> createState() => _TrafficSignalScreenState();
}

class _TrafficSignalScreenState extends ConsumerState<TrafficSignalScreen> {
  bool _loaded = false;
  bool _saving = false;

  String _type = 'serial';
  bool _enabled = false;
  int _baudRate = 9600;

  String _entryPort = '';
  String _exitPort = '';
  final _entryUrlCtrl = TextEditingController();
  final _exitUrlCtrl = TextEditingController();

  List<String> _availablePorts = [];

  String? _headerMsg;
  bool _headerMsgIsError = false;
  Timer? _headerMsgTimer;

  final _testingSignals = <String>{};

  static final _serialPortWhitelist = RegExp(
    r'(usbserial|usbmodem|ttyUSB|ttyS\d|ttyACM|COM\d|serial|SLAB|CH34|PL23|FT23|CP21)',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _detectPorts();
  }

  @override
  void dispose() {
    _headerMsgTimer?.cancel();
    _entryUrlCtrl.dispose();
    _exitUrlCtrl.dispose();
    super.dispose();
  }

  void _detectPorts() {
    final all = ScaleService.availablePorts;
    var detected = all.where((p) => _serialPortWhitelist.hasMatch(p)).toList();
    if (detected.isEmpty) {
      detected = all.where((p) {
        final lower = p.toLowerCase();
        return !lower.contains('bluetooth') &&
            !lower.contains('buds') &&
            !lower.contains('airpods') &&
            !lower.contains('headphone') &&
            !lower.contains('audio') &&
            !lower.contains('speaker') &&
            !lower.contains('beats') &&
            !lower.contains('wlan') &&
            !lower.contains('debug');
      }).toList();
    }
    setState(() {
      _availablePorts = detected;
      if (_entryPort.isNotEmpty && !detected.contains(_entryPort)) _entryPort = '';
      if (_exitPort.isNotEmpty && !detected.contains(_exitPort)) _exitPort = '';
    });
  }

  void _refreshPorts() => _detectPorts();

  void _loadConfig(TrafficSignalConfig config) {
    if (_loaded) return;
    _loaded = true;
    _enabled = config.enabled;
    _type = config.type;
    _baudRate = config.baudRate;
    _entryPort = config.entryPort;
    _exitPort = config.exitPort;
    _entryUrlCtrl.text = config.entryUrl;
    _exitUrlCtrl.text = config.exitUrl;
  }

  void _showHeaderMsg(String msg, {bool isError = false}) {
    _headerMsgTimer?.cancel();
    setState(() {
      _headerMsg = msg;
      _headerMsgIsError = isError;
    });
    _headerMsgTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _headerMsg = null);
    });
  }

  TrafficSignalConfig _buildConfig() => TrafficSignalConfig(
    enabled: _enabled,
    type: _type,
    entryPort: _entryPort,
    exitPort: _exitPort,
    entryUrl: _entryUrlCtrl.text.trim(),
    exitUrl: _exitUrlCtrl.text.trim(),
    baudRate: _baudRate,
  );

  Future<void> _save() async {
    // Auto-disable if no valid configuration
    if (_enabled) {
      final hasValidConfig = _type == 'http'
          ? _entryUrlCtrl.text.trim().isNotEmpty || _exitUrlCtrl.text.trim().isNotEmpty
          : _entryPort.isNotEmpty || _exitPort.isNotEmpty;
      if (!hasValidConfig) {
        setState(() => _enabled = false);
        _showHeaderMsg('No signal configured — disabled automatically');
      }
    }

    setState(() => _saving = true);
    try {
      final config = _buildConfig();
      await saveTrafficSignalConfig(ref, config);
      if (mounted) _showHeaderMsg('Traffic signal settings saved');
    } catch (e) {
      if (mounted) _showHeaderMsg('Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testSignal(SignalId signalId, SignalState state) async {
    final key = '${signalId.name}_${state.name}';
    setState(() => _testingSignals.add(key));
    try {
      final service = ref.read(trafficSignalServiceProvider);
      service.updateConfig(_buildConfig());
      final success = signalId == SignalId.entry
          ? await service.setEntrySignal(state)
          : await service.setExitSignal(state);
      if (mounted) {
        if (success) {
          _showHeaderMsg('${signalId.name} signal set to ${state.name}');
        } else {
          _showHeaderMsg('Failed to set ${signalId.name} signal', isError: true);
        }
      }
    } catch (e) {
      if (mounted) _showHeaderMsg('Test failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _testingSignals.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final configAsync = ref.watch(trafficSignalConfigProvider);
    configAsync.whenData(_loadConfig);

    final signalStates = ref.watch(trafficSignalStateProvider).valueOrNull ?? {};

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Column(
        children: [
          _buildHeader(scheme, text, signalStates),
          Expanded(
            child: configAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) => SingleChildScrollView(
                padding: AppSpacing.pagePadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildConnectionTypeCard(scheme, text),
                    SizedBox(height: AppSpacing.xl),
                    _buildEntrySignalCard(scheme, text),
                    SizedBox(height: AppSpacing.xl),
                    _buildExitSignalCard(scheme, text),
                    SizedBox(height: AppSpacing.xl),
                    _buildTestCard(scheme, text),
                    SizedBox(height: 40.rs),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme, TextTheme text, Map<SignalId, SignalState> signalStates) {
    final entryState = signalStates[SignalId.entry] ?? SignalState.off;
    final exitState = signalStates[SignalId.exit] ?? SignalState.off;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: AppRadius.card,
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
              boxShadow: AppElevation.card(scheme.shadow),
            ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.go('/settings'),
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
          ),
          SizedBox(width: 10.rs),
          Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.brandTeal,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Traffic Signals', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text('Entry & exit signal configuration', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          SizedBox(width: AppSpacing.xl),
          _buildStatusIndicator('Entry', entryState, scheme, text),
          SizedBox(width: AppSpacing.md),
          _buildStatusIndicator('Exit', exitState, scheme, text),
          if (_headerMsg != null) ...[
            SizedBox(width: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (_headerMsgIsError ? scheme.error : AppTheme.successColor).withValues(alpha: 0.1),
                borderRadius: AppRadius.chip,
                border: Border.all(color: (_headerMsgIsError ? scheme.error : AppTheme.successColor).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _headerMsgIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                    size: 14,
                    color: _headerMsgIsError ? scheme.error : AppTheme.successColor,
                  ),
                  SizedBox(width: 6.rs),
                  Text(
                    _headerMsg!,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _headerMsgIsError ? scheme.error : AppTheme.successColor),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.brandTeal,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save Settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(String label, SignalState state, ColorScheme scheme, TextTheme text) {
    final color = switch (state) {
      SignalState.red => Colors.red,
      SignalState.yellow => Colors.amber,
      SignalState.green => AppTheme.successColor,
      SignalState.off => scheme.outlineVariant,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadius.chip,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: state != SignalState.off
                  ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4)]
                  : null,
            ),
          ),
          SizedBox(width: 6.rs),
          Text(
            '$label: ${state.name.toUpperCase()}',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionTypeCard(ColorScheme scheme, TextTheme text) {
    return AppCard(
      title: 'Connection Type',
      icon: Icons.settings_input_component_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _switchRow('Enable Traffic Signals', 'Control entry/exit signals from this app', _enabled, (v) => setState(() => _enabled = v), scheme, text)),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              _buildTypeChip('serial', 'Serial', Icons.usb_rounded, scheme, text),
              _buildTypeChip('http', 'HTTP', Icons.language_rounded, scheme, text),
              _buildTypeChip('gpio', 'GPIO', Icons.developer_board_rounded, scheme, text),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String type, String label, IconData icon, ColorScheme scheme, TextTheme text) {
    final selected = _type == type;
    return GestureDetector(
      onTap: () => setState(() => _type = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer.withValues(alpha: 0.5) : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10.rs),
          border: Border.all(
            color: selected ? AppTheme.brandTeal.withValues(alpha: 0.6) : scheme.outlineVariant.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? AppTheme.brandTeal : scheme.onSurfaceVariant),
            SizedBox(width: AppSpacing.sm),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? AppTheme.brandTeal : scheme.onSurface)),
            if (selected) ...[
              SizedBox(width: 6.rs),
              Icon(Icons.check_circle_rounded, size: 14, color: AppTheme.brandTeal),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEntrySignalCard(ColorScheme scheme, TextTheme text) {
    return AppCard(
      title: 'Entry Signal',
      icon: Icons.login_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_type == 'serial' || _type == 'gpio') ...[
            Row(
              children: [
                Text('Port', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _refreshPorts,
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  label: Text('Refresh', style: TextStyle(fontSize: 11, color: scheme.primary)),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                ),
              ],
            ),
            SizedBox(height: 5.rs),
            DropdownButtonFormField<String>(
              value: _availablePorts.contains(_entryPort) ? _entryPort : null,
              items: _availablePorts
                  .map((p) => DropdownMenuItem(value: p, child: Text(p, style: text.bodySmall)))
                  .toList(),
              onChanged: (v) => setState(() => _entryPort = v ?? ''),
              decoration: InputDecoration(
                hintText: _availablePorts.isEmpty ? 'No ports detected' : 'Select port',
                prefixIcon: Icon(_type == 'serial' ? Icons.usb_rounded : Icons.developer_board_rounded, size: 16),
                prefixIconConstraints: const BoxConstraints(minWidth: 40),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            if (_type == 'serial') ...[
              SizedBox(height: AppSpacing.md),
              Text('Baud Rate', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
              SizedBox(height: 5.rs),
              DropdownButtonFormField<int>(
                value: _baudRate,
                items: [9600, 19200, 38400, 115200]
                    .map((b) => DropdownMenuItem(value: b, child: Text('$b', style: text.bodySmall)))
                    .toList(),
                onChanged: (v) => setState(() => _baudRate = v!),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
              ),
            ],
          ] else ...[
            Text('URL', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
            SizedBox(height: 5.rs),
            TextField(
              controller: _entryUrlCtrl,
              style: text.bodySmall,
              decoration: const InputDecoration(
                hintText: 'http://192.168.1.50/signal',
                prefixIcon: Icon(Icons.link_rounded, size: 16),
                prefixIconConstraints: BoxConstraints(minWidth: 40),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExitSignalCard(ColorScheme scheme, TextTheme text) {
    return AppCard(
      title: 'Exit Signal',
      icon: Icons.logout_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_type == 'serial' || _type == 'gpio') ...[
            Text('Port', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
            SizedBox(height: 5.rs),
            DropdownButtonFormField<String>(
              value: _availablePorts.contains(_exitPort) ? _exitPort : null,
              items: _availablePorts
                  .map((p) => DropdownMenuItem(value: p, child: Text(p, style: text.bodySmall)))
                  .toList(),
              onChanged: (v) => setState(() => _exitPort = v ?? ''),
              decoration: InputDecoration(
                hintText: _availablePorts.isEmpty ? 'No ports detected' : 'Select port',
                prefixIcon: Icon(_type == 'serial' ? Icons.usb_rounded : Icons.developer_board_rounded, size: 16),
                prefixIconConstraints: const BoxConstraints(minWidth: 40),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            if (_type == 'serial') ...[
              SizedBox(height: AppSpacing.md),
              Text('Baud Rate', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
              SizedBox(height: 5.rs),
              DropdownButtonFormField<int>(
                value: _baudRate,
                items: [9600, 19200, 38400, 115200]
                    .map((b) => DropdownMenuItem(value: b, child: Text('$b', style: text.bodySmall)))
                    .toList(),
                onChanged: (v) => setState(() => _baudRate = v!),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
              ),
            ],
          ] else ...[
            Text('URL', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
            SizedBox(height: 5.rs),
            TextField(
              controller: _exitUrlCtrl,
              style: text.bodySmall,
              decoration: const InputDecoration(
                hintText: 'http://192.168.1.51/signal',
                prefixIcon: Icon(Icons.link_rounded, size: 16),
                prefixIconConstraints: BoxConstraints(minWidth: 40),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTestCard(ColorScheme scheme, TextTheme text) {
    return AppCard(
      title: 'Test Signals',
      icon: Icons.science_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Entry Signal', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _buildTestButton(SignalId.entry, SignalState.red, 'Red', Colors.red, scheme),
              SizedBox(width: AppSpacing.sm),
              _buildTestButton(SignalId.entry, SignalState.yellow, 'Yellow', Colors.amber, scheme),
              SizedBox(width: AppSpacing.sm),
              _buildTestButton(SignalId.entry, SignalState.green, 'Green', AppTheme.successColor, scheme),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
          Text('Exit Signal', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _buildTestButton(SignalId.exit, SignalState.red, 'Red', Colors.red, scheme),
              SizedBox(width: AppSpacing.sm),
              _buildTestButton(SignalId.exit, SignalState.yellow, 'Yellow', Colors.amber, scheme),
              SizedBox(width: AppSpacing.sm),
              _buildTestButton(SignalId.exit, SignalState.green, 'Green', AppTheme.successColor, scheme),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTestButton(SignalId signalId, SignalState state, String label, Color color, ColorScheme scheme) {
    final key = '${signalId.name}_${state.name}';
    final testing = _testingSignals.contains(key);

    return OutlinedButton(
      onPressed: testing ? null : () => _testSignal(signalId, state),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
      ),
      child: testing
          ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                SizedBox(width: 6.rs),
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
    );
  }

  Widget _switchRow(String label, String subtitle, bool value, ValueChanged<bool> onChanged, ColorScheme scheme, TextTheme text) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              Text(subtitle, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
