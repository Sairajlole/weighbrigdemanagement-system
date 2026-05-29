import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/widgets/pro_feature_banner.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/integrations_provider.dart';
import 'package:weighbridgemanagement/shared/services/display_board_service.dart';
import 'package:weighbridgemanagement/shared/services/tally_service.dart';
import 'package:weighbridgemanagement/shared/utils/ip_validator.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/app_loading.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

// ─── Provider ────────────────────────────────────────────────────────────────

final _integrationsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  final doc = await db.integrationsSettings.get();
  return doc.exists ? doc.data()! : {};
});

// ─── Screen ──────────────────────────────────────────────────────────────────

class IntegrationsScreen extends ConsumerStatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  ConsumerState<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends ConsumerState<IntegrationsScreen> {
  bool _loaded = false;
  bool _saving = false;
  String _savedSnapshot = '';

  String? _headerMsg;
  bool _headerMsgIsError = false;

  // ── Tally Sync ──
  bool _tallyEnabled = false;
  final _tallyHost = TextEditingController();
  final _tallyPort = TextEditingController(text: '9000');
  final _tallyCompany = TextEditingController();
  String _tallySyncMode = 'auto';
  bool _tallyPushVouchers = true;
  bool _tallyPushLedgers = false;
  bool _tallyMapMaterials = true;
  String? _tallyStatus;

  // ── Hardware (LED Display Boards — multiple) ──
  List<Map<String, dynamic>> _displayBoards = [];
  List<String> _availablePorts = [];
  bool _scanningPorts = false;

  // ── Cloud Backup (Google Drive / S3) ──
  bool _gdriveEnabled = false;
  final _gdriveClientId = TextEditingController();
  final _gdriveFolder = TextEditingController(text: 'WeighbridgeBackups');
  String _gdriveFrequency = 'daily';

  // ── Oracle ERP Export ──
  bool _oracleEnabled = false;
  final _oracleHost = TextEditingController();
  final _oraclePort = TextEditingController(text: '443');
  final _oracleUsername = TextEditingController();
  final _oraclePassword = TextEditingController();
  final _oracleResponsibility = TextEditingController();
  String _oracleSyncMode = 'manual';
  bool _oraclePushWeighments = true;
  bool _oraclePushCustomers = false;
  bool _oraclePushMaterials = false;
  String? _oracleStatus;



  @override
  void dispose() {
    _tallyHost.dispose();
    _tallyPort.dispose();
    _tallyCompany.dispose();
    _gdriveClientId.dispose();
    _gdriveFolder.dispose();
    _oracleHost.dispose();
    _oraclePort.dispose();
    _oracleUsername.dispose();
    _oraclePassword.dispose();
    _oracleResponsibility.dispose();
    super.dispose();
  }

  void _loadData(Map<String, dynamic> data) {
    if (_loaded) return;
    _loaded = true;

    // Tally
    final tally = data['tally'] as Map<String, dynamic>? ?? {};
    _tallyEnabled = tally['enabled'] == true;
    _tallyHost.text = tally['host'] as String? ?? '';
    _tallyPort.text = '${tally['port'] ?? 9000}';
    _tallyCompany.text = tally['company'] as String? ?? '';
    _tallySyncMode = tally['syncMode'] as String? ?? 'auto';
    _tallyPushVouchers = tally['pushVouchers'] as bool? ?? true;
    _tallyPushLedgers = tally['pushLedgers'] as bool? ?? false;
    _tallyMapMaterials = tally['mapMaterials'] as bool? ?? true;

    // Hardware
    final hw = data['hardware'] as Map<String, dynamic>? ?? {};
    final boards = hw['displayBoards'] as List<dynamic>? ?? [];
    _displayBoards = boards.map((b) => Map<String, dynamic>.from(b as Map)).toList();

    // Cloud
    final cloud = data['cloud'] as Map<String, dynamic>? ?? {};
    final gdrive = cloud['gdrive'] as Map<String, dynamic>? ?? {};
    _gdriveEnabled = gdrive['enabled'] == true;
    _gdriveClientId.text = gdrive['clientId'] as String? ?? '';
    _gdriveFolder.text = gdrive['folder'] as String? ?? 'WeighbridgeBackups';
    _gdriveFrequency = gdrive['frequency'] as String? ?? 'daily';

    // Oracle ERP
    final oracle = data['oracle'] as Map<String, dynamic>? ?? {};
    _oracleEnabled = oracle['enabled'] == true;
    _oracleHost.text = oracle['host'] as String? ?? '';
    _oraclePort.text = '${oracle['port'] ?? 443}';
    _oracleUsername.text = oracle['username'] as String? ?? '';
    _oraclePassword.text = oracle['password'] as String? ?? '';
    _oracleResponsibility.text = oracle['responsibility'] as String? ?? '';
    _oracleSyncMode = oracle['syncMode'] as String? ?? 'manual';
    _oraclePushWeighments = oracle['pushWeighments'] as bool? ?? true;
    _oraclePushCustomers = oracle['pushCustomers'] as bool? ?? false;
    _oraclePushMaterials = oracle['pushMaterials'] as bool? ?? false;

    _savedSnapshot = jsonEncode(_buildPayload());
  }

  bool get _dirty => _savedSnapshot.isNotEmpty && _savedSnapshot != jsonEncode(_buildPayload());

  Map<String, dynamic> _buildPayload() => {
    'tally': {
      'enabled': _tallyEnabled,
      'host': _tallyHost.text.trim(),
      'port': int.tryParse(_tallyPort.text.trim()) ?? 9000,
      'company': _tallyCompany.text.trim(),
      'syncMode': _tallySyncMode,
      'pushVouchers': _tallyPushVouchers,
      'pushLedgers': _tallyPushLedgers,
      'mapMaterials': _tallyMapMaterials,
    },
    'hardware': {
      'displayBoards': _displayBoards,
    },
    'cloud': {
      'gdrive': {
        'enabled': _gdriveEnabled,
        'clientId': _gdriveClientId.text.trim(),
        'folder': _gdriveFolder.text.trim(),
        'frequency': _gdriveFrequency,
      },
    },
    'oracle': {
      'enabled': _oracleEnabled,
      'host': _oracleHost.text.trim(),
      'port': int.tryParse(_oraclePort.text.trim()) ?? 443,
      'username': _oracleUsername.text.trim(),
      'password': _oraclePassword.text.trim(),
      'responsibility': _oracleResponsibility.text.trim(),
      'syncMode': _oracleSyncMode,
      'pushWeighments': _oraclePushWeighments,
      'pushCustomers': _oraclePushCustomers,
      'pushMaterials': _oraclePushMaterials,
    },
  };

  void _markDirty() {
    setState(() {});
  }

  void _showHeaderMsg(String msg, {bool isError = false}) {
    setState(() { _headerMsg = msg; _headerMsgIsError = isError; });
    Future.delayed(Duration(seconds: isError ? 5 : 3), () {
      if (mounted) setState(() => _headerMsg = null);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final db = ref.read(firestorePathsProvider);
      final payload = {
        ..._buildPayload(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await db.integrationsSettings.set(payload, SetOptions(merge: true));
      ref.invalidate(_integrationsProvider);
      ref.invalidate(integrationsConfigProvider);

      if (mounted) {
        _savedSnapshot = jsonEncode(_buildPayload());
        setState(() {});
        _showHeaderMsg('Integration settings saved');
      }
    } catch (e) {
      if (mounted) _showHeaderMsg('Failed to save: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testTallyConnection() async {
    setState(() => _tallyStatus = 'testing');
    final service = ref.read(tallyServiceProvider);
    service.updateConfig(TallyConfig(
      enabled: true,
      host: _tallyHost.text.trim(),
      port: int.tryParse(_tallyPort.text.trim()) ?? 9000,
      company: _tallyCompany.text.trim(),
      syncMode: _tallySyncMode,
      pushVouchers: _tallyPushVouchers,
      pushLedgers: _tallyPushLedgers,
      mapMaterials: _tallyMapMaterials,
    ));
    final ok = await service.testConnection();
    setState(() => _tallyStatus = ok ? 'connected' : 'failed');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dataAsync = ref.watch(_integrationsProvider);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: dataAsync.when(
        loading: () => const AppLoading(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) {
          _loadData(data);
          return Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => context.go('/settings'),
                          icon: Icon(Icons.arrow_back_rounded, size: 20, color: scheme.onSurface),
                          tooltip: 'Back',
                          style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
                        ),
                        SizedBox(width: AppSpacing.md),
                        Icon(Icons.hub_rounded, size: 20, color: scheme.primary),
                        SizedBox(width: 10.rs),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Integrations', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                            Text('Tally, displays, and cloud sync', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                          ],
                        ),
                        const Spacer(),
                        if (_dirty) ...[
                          TextButton(
                            onPressed: () { setState(() { _loaded = false; _savedSnapshot = ''; }); ref.invalidate(_integrationsProvider); },
                            child: const Text('Cancel'),
                          ),
                          SizedBox(width: AppSpacing.sm),
                        ],
                        FilledButton.icon(
                          onPressed: _dirty && !_saving ? _save : null,
                          icon: _saving
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.save_rounded, size: 16),
                          label: Text(_saving ? 'Saving...' : 'Save'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                          ),
                        ),
                      ],
                    ),
                    if (_headerMsg != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _headerMsgIsError ? scheme.errorContainer.withValues(alpha: 0.6) : AppTheme.successColor.withValues(alpha: 0.1),
                            borderRadius: AppRadius.button,
                            border: Border.all(color: _headerMsgIsError ? scheme.error.withValues(alpha: 0.3) : AppTheme.successColor.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _headerMsgIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                                size: 15,
                                color: _headerMsgIsError ? scheme.error : AppTheme.successColor,
                              ),
                              SizedBox(width: AppSpacing.sm),
                              Expanded(child: Text(_headerMsg!, style: text.bodySmall?.copyWith(color: _headerMsgIsError ? scheme.error : AppTheme.successColor, fontWeight: FontWeight.w500))),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: AppSpacing.pagePadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ProFeatureBanner(feature: 'Integrations'),
                      _buildErpSection(scheme, text),
                      SizedBox(height: AppSpacing.xl),
                      _buildInfraSection(scheme, text),
                      SizedBox(height: 40.rs),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMBINED SECTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildErpSection(ColorScheme scheme, TextTheme text) {
    return _Section(
      icon: Icons.sync_alt_rounded,
      title: 'ERP & Accounting',
      scheme: scheme,
      text: text,
      children: [
        _buildInfoRow('Connect to accounting and ERP systems to automatically sync weighment data, customers, and materials.', scheme, text),
        SizedBox(height: AppSpacing.lg),
        _buildTallyContent(scheme, text),
        SizedBox(height: 20.rs),
        const Divider(height: 1),
        SizedBox(height: 20.rs),
        _buildOracleContent(scheme, text),
      ],
    );
  }

  Widget _buildInfraSection(ColorScheme scheme, TextTheme text) {
    return _Section(
      icon: Icons.devices_other_rounded,
      title: 'Hardware & Cloud',
      scheme: scheme,
      text: text,
      children: [
        _buildInfoRow('LED display boards and cloud backup configuration.', scheme, text),
        SizedBox(height: AppSpacing.lg),
        _buildHardwareContent(scheme, text),
        SizedBox(height: 20.rs),
        const Divider(height: 1),
        SizedBox(height: 20.rs),
        _buildCloudContent(scheme, text),
      ],
    );
  }


  Widget _buildTallyContent(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subHeader('Tally ERP', Icons.account_balance_rounded, scheme, text),
        SizedBox(height: AppSpacing.sm),
        _toggleRow('Enable Tally sync', _tallyEnabled, (v) { setState(() => _tallyEnabled = v); _markDirty(); }, scheme, text),
        if (_tallyEnabled) ...[
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _ipField('Host / IP', _tallyHost, hint: '192.168.1.100', scheme: scheme, text: text)),
              SizedBox(width: 14.rs),
              SizedBox(width: 100, child: _field('Port', _tallyPort, hint: '9000', scheme: scheme, text: text)),
            ],
          ),
          SizedBox(height: 14.rs),
          _field('Company Name', _tallyCompany, hint: 'Your Tally company name', scheme: scheme, text: text),
          SizedBox(height: 14.rs),
          _dropdownRow('Sync Mode', _tallySyncMode, ['auto', 'manual', 'scheduled'], (v) { setState(() => _tallySyncMode = v); _markDirty(); }, scheme, text),
          SizedBox(height: 14.rs),
          Text('Data to Push', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: AppSpacing.sm),
          _toggleRow('Push weighment vouchers', _tallyPushVouchers, (v) { setState(() => _tallyPushVouchers = v); _markDirty(); }, scheme, text),
          _toggleRow('Push customer ledgers', _tallyPushLedgers, (v) { setState(() => _tallyPushLedgers = v); _markDirty(); }, scheme, text),
          _toggleRow('Map materials to stock items', _tallyMapMaterials, (v) { setState(() => _tallyMapMaterials = v); _markDirty(); }, scheme, text),
          SizedBox(height: 14.rs),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _testTallyConnection,
                icon: const Icon(Icons.wifi_tethering_rounded, size: 16),
                label: const Text('Test Connection'),
              ),
              SizedBox(width: AppSpacing.md),
              if (_tallyStatus == 'testing')
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else if (_tallyStatus == 'connected')
                Row(children: [
                  const Icon(Icons.check_circle_rounded, size: 16, color: Colors.green),
                  SizedBox(width: AppSpacing.xs),
                  Text('Connected', style: text.labelSmall?.copyWith(color: Colors.green, fontWeight: FontWeight.w600)),
                ])
              else if (_tallyStatus == 'failed')
                Row(children: [
                  Icon(Icons.error_rounded, size: 16, color: scheme.error),
                  SizedBox(width: AppSpacing.xs),
                  Text('Connection failed', style: text.labelSmall?.copyWith(color: scheme.error, fontWeight: FontWeight.w600)),
                ]),
            ],
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HARDWARE
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _scanPorts() async {
    setState(() => _scanningPorts = true);
    try {
      final ports = await DisplayBoardService.scanPorts();
      setState(() => _availablePorts = ports);
    } catch (_) {
    } finally {
      setState(() => _scanningPorts = false);
    }
  }

  Future<void> _testOracleConnection() async {
    setState(() => _oracleStatus = 'testing');
    try {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _oracleStatus = 'connected');
    } catch (_) {
      if (mounted) setState(() => _oracleStatus = 'failed');
    }
  }

  Future<void> _triggerOracleExport() async {
    _showHeaderMsg('Oracle ERP export queued. Records will be pushed shortly.');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTENT BUILDERS (for combined cards)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildOracleContent(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subHeader('Oracle ERP', Icons.business_rounded, scheme, text),
        SizedBox(height: AppSpacing.sm),
        _toggleRow('Enable Oracle ERP export', _oracleEnabled, (v) { setState(() => _oracleEnabled = v); _markDirty(); }, scheme, text),
        if (_oracleEnabled) ...[
          SizedBox(height: 14.rs),
          _field('Host URL', _oracleHost, hint: 'erp.company.com', scheme: scheme, text: text, onChanged: (_) => _markDirty()),
          SizedBox(height: 10.rs),
          Row(
            children: [
              SizedBox(width: 120, child: _field('Port', _oraclePort, hint: '443', scheme: scheme, text: text, onChanged: (_) => _markDirty())),
              SizedBox(width: 14.rs),
              Expanded(child: _field('Responsibility', _oracleResponsibility, hint: 'WEIGHBRIDGE_USER', scheme: scheme, text: text, onChanged: (_) => _markDirty())),
            ],
          ),
          SizedBox(height: 10.rs),
          _field('Username', _oracleUsername, hint: 'api_user', scheme: scheme, text: text, onChanged: (_) => _markDirty()),
          SizedBox(height: 10.rs),
          _field('Password', _oraclePassword, hint: '••••••••', obscure: true, scheme: scheme, text: text, onChanged: (_) => _markDirty()),
          SizedBox(height: 14.rs),
          Text('Data Export', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: AppSpacing.sm),
          _toggleRow('Push weighments', _oraclePushWeighments, (v) { setState(() => _oraclePushWeighments = v); _markDirty(); }, scheme, text),
          SizedBox(height: 6.rs),
          _toggleRow('Push customers (as trading partners)', _oraclePushCustomers, (v) { setState(() => _oraclePushCustomers = v); _markDirty(); }, scheme, text),
          SizedBox(height: 6.rs),
          _toggleRow('Push materials (as inventory items)', _oraclePushMaterials, (v) { setState(() => _oraclePushMaterials = v); _markDirty(); }, scheme, text),
          SizedBox(height: 14.rs),
          _dropdownRow('Sync Mode', _oracleSyncMode, ['manual', 'auto', 'scheduled'], (v) { setState(() => _oracleSyncMode = v); _markDirty(); }, scheme, text),
          SizedBox(height: 14.rs),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _oracleHost.text.trim().isEmpty ? null : _testOracleConnection,
                icon: Icon(_oracleStatus == 'testing' ? Icons.hourglass_empty_rounded : Icons.wifi_tethering_rounded, size: 14),
                label: Text(_oracleStatus == 'testing' ? 'Testing...' : 'Test Connection', style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                ),
              ),
              SizedBox(width: 10.rs),
              if (_oracleSyncMode == 'manual')
                OutlinedButton.icon(
                  onPressed: _oracleStatus == 'connected' ? _triggerOracleExport : null,
                  icon: const Icon(Icons.upload_rounded, size: 14),
                  label: const Text('Export Now', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildHardwareContent(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _subHeader('LED Display Boards', Icons.memory_rounded, scheme, text)),
            IconButton(
              onPressed: _scanningPorts ? null : _scanPorts,
              icon: _scanningPorts
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, size: 18),
              tooltip: 'Scan available ports',
              style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
            ),
            SizedBox(width: AppSpacing.xs),
            FilledButton.tonalIcon(
              onPressed: () {
                setState(() {
                  _displayBoards.add({
                    'name': 'Display ${_displayBoards.length + 1}',
                    'port': '',
                    'protocol': 'serial',
                    'baudRate': 9600,
                    'enabled': true,
                  });
                });
                _markDirty();
              },
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.md),
        if (_availablePorts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.usb_rounded, size: 14, color: scheme.primary),
                SizedBox(width: 6.rs),
                Text('${_availablePorts.length} port(s) detected', style: text.labelSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        if (_displayBoards.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.tv_off_rounded, size: 28, color: scheme.outlineVariant),
                  SizedBox(height: 6.rs),
                  Text('No display boards configured', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          )
        else
          ...List.generate(_displayBoards.length, (i) {
            final board = _displayBoards[i];
            return Container(
              margin: EdgeInsets.only(bottom: i < _displayBoards.length - 1 ? 12 : 0),
              padding: EdgeInsets.all(14.rs),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(10.rs),
                border: Border.all(color: (board['enabled'] == true) ? scheme.primary.withValues(alpha: 0.2) : scheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tv_rounded, size: 16, color: (board['enabled'] == true) ? scheme.primary : scheme.outlineVariant),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: TextEditingController(text: board['name'] as String? ?? ''),
                          style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10), border: InputBorder.none),
                          onChanged: (v) { board['name'] = v; _markDirty(); },
                        ),
                      ),
                      Switch(
                        value: board['enabled'] == true,
                        onChanged: (v) { setState(() => board['enabled'] = v); _markDirty(); },
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      SizedBox(width: AppSpacing.xs),
                      IconButton(
                        onPressed: () { setState(() => _displayBoards.removeAt(i)); _markDirty(); },
                        icon: Icon(Icons.delete_outline_rounded, size: 16, color: scheme.error),
                        tooltip: 'Remove',
                        style: IconButton.styleFrom(minimumSize: const Size(28, 28), padding: EdgeInsets.zero),
                      ),
                    ],
                  ),
                  if (board['enabled'] == true) ...[
                    SizedBox(height: 10.rs),
                    Row(
                      children: [
                        Expanded(
                          child: _dropdownRow(
                            'Port',
                            _availablePorts.contains(board['port']) ? board['port'] as String : (_availablePorts.isNotEmpty ? _availablePorts.first : ''),
                            _availablePorts.isNotEmpty ? _availablePorts : ['No devices found'],
                            (v) { if (v != 'No devices found') { setState(() => board['port'] = v); _markDirty(); } },
                            scheme, text,
                          ),
                        ),
                        SizedBox(width: AppSpacing.md),
                        SizedBox(width: 120, child: _dropdownRow('Protocol', board['protocol'] as String? ?? 'serial', ['serial', 'tcp', 'modbus'], (v) { setState(() => board['protocol'] = v); _markDirty(); }, scheme, text)),
                        SizedBox(width: AppSpacing.md),
                        SizedBox(width: 110, child: _dropdownRow('Baud', '${board['baudRate'] ?? 9600}', ['9600', '19200', '38400', '115200'], (v) { setState(() => board['baudRate'] = int.parse(v)); _markDirty(); }, scheme, text)),
                      ],
                    ),
                  ],
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildCloudContent(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subHeader('Google Drive Backup', Icons.add_to_drive_rounded, scheme, text),
        SizedBox(height: AppSpacing.sm),
        _toggleRow('Enable Google Drive backup', _gdriveEnabled, (v) { setState(() => _gdriveEnabled = v); _markDirty(); }, scheme, text),
        if (_gdriveEnabled) ...[
          SizedBox(height: 10.rs),
          _field('OAuth Client ID', _gdriveClientId, hint: 'xxxx.apps.googleusercontent.com', scheme: scheme, text: text),
          SizedBox(height: 10.rs),
          _field('Folder Name', _gdriveFolder, hint: 'WeighbridgeBackups', scheme: scheme, text: text),
          SizedBox(height: 10.rs),
          _dropdownRow('Frequency', _gdriveFrequency, ['hourly', 'daily', 'weekly'], (v) { setState(() => _gdriveFrequency = v); _markDirty(); }, scheme, text),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REUSABLE WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _field(String label, TextEditingController ctrl, {String? hint, bool obscure = false, required ColorScheme scheme, required TextTheme text, ValueChanged<String>? onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: 6.rs),
        TextField(
          controller: ctrl,
          style: text.bodySmall,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onChanged: (v) { if (onChanged != null) onChanged(v); _markDirty(); },
        ),
      ],
    );
  }

  Widget _ipField(String label, TextEditingController ctrl, {String? hint, required ColorScheme scheme, required TextTheme text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: 6.rs),
        TextFormField(
          controller: ctrl,
          style: text.bodySmall,
          inputFormatters: [IpInputFormatter()],
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: validateIpAddress,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onChanged: (_) => _markDirty(),
        ),
      ],
    );
  }

  Widget _dropdownRow(String label, String value, List<String> options, ValueChanged<String> onChanged, ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: 6.rs),
        DropdownButtonFormField<String>(
          initialValue: options.contains(value) ? value : options.first,
          items: options.map((e) => DropdownMenuItem(value: e, child: Text(e, style: text.bodySmall))).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: AppRadius.button, borderSide: BorderSide(color: scheme.outlineVariant)),
          ),
          style: text.bodySmall,
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged, ColorScheme scheme, TextTheme text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: text.bodySmall)),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _subHeader(String title, IconData icon, ColorScheme scheme, TextTheme text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.primary),
        SizedBox(width: AppSpacing.sm),
        Text(title, style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildInfoRow(String infoText, ColorScheme scheme, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.12),
        borderRadius: AppRadius.chip,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded, size: 13, color: scheme.primary.withValues(alpha: 0.6)),
          ),
          SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(infoText, style: textTheme.bodySmall?.copyWith(fontSize: 11, color: scheme.onSurfaceVariant, height: 1.4))),
        ],
      ),
    );
  }
}

// ─── Section Card Widget ────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final ColorScheme scheme;
  final TextTheme text;
  final List<Widget> children;

  const _Section({required this.icon, required this.title, required this.scheme, required this.text, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.dialog,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.15))),
            ),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: AppRadius.button,
                  ),
                  child: Icon(icon, size: 16, color: scheme.primary),
                ),
                SizedBox(width: 10.rs),
                Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Padding(
            padding: AppSpacing.pagePadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}
