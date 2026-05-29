import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import '../../application/setup_wizard_provider.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/app_loading.dart';

class PrintingStep extends ConsumerStatefulWidget {
  const PrintingStep({super.key});

  @override
  ConsumerState<PrintingStep> createState() => _PrintingStepState();
}

class _PrintingStepState extends ConsumerState<PrintingStep> {
  bool _loaded = false;

  // Printers
  List<Map<String, dynamic>> _printers = [];
  Map<String, List<String>> _printerTrays = {};
  String _grossPrinter = 'default';
  String _grossTray = '';
  String _tarePrinter = 'default';
  String _tareTray = '';
  bool _backupEnabled = false;
  String _backupPrinter = '';
  String _backupTray = '';

  // Print Rules
  int _copies = 2;
  bool _printOnGross = false;
  bool _printOnTare = true;
  bool _autoPrint = true;
  bool _reprintAllowed = true;
  int _maxReprints = 2;

  // Normal Printer — per-size defaults from reference config
  String _normalPaperSize = 'A4';
  final Map<String, Map<String, dynamic>> _perSizeConfigs = {
    'A4': {'marginTop': 5.0, 'marginBottom': 5.0, 'marginLeft': 15.0, 'marginRight': 15.0, 'logo': true, 'logoWidth': 80.0, 'logoHeight': 80.0, 'pdf417': true, 'pdf417Position': 'bottom', 'cctv': true, 'fontSize': 18},
    'A5': {'marginTop': 5.0, 'marginBottom': 5.0, 'marginLeft': 10.0, 'marginRight': 10.0, 'logo': true, 'logoWidth': 50.0, 'logoHeight': 50.0, 'pdf417': true, 'pdf417Position': 'bottom', 'cctv': true, 'fontSize': 10},
    'Letter': {'marginTop': 5.0, 'marginBottom': 5.0, 'marginLeft': 15.0, 'marginRight': 15.0, 'logo': true, 'logoWidth': 80.0, 'logoHeight': 80.0, 'pdf417': true, 'pdf417Position': 'bottom', 'cctv': true, 'fontSize': 14},
    'Legal': {'marginTop': 10.0, 'marginBottom': 10.0, 'marginLeft': 15.0, 'marginRight': 15.0, 'logo': true, 'logoWidth': 90.0, 'logoHeight': 90.0, 'pdf417': true, 'pdf417Position': 'bottom', 'cctv': true, 'cctvCameras': ['Front', 'Rear', 'Top'], 'fontSize': 18},
  };

  Map<String, dynamic> get _currentSizeConfig => _perSizeConfigs[_normalPaperSize] ?? _perSizeConfigs['A4']!;
  double get _normalMarginTop => (_currentSizeConfig['marginTop'] as num).toDouble();
  double get _normalMarginBottom => (_currentSizeConfig['marginBottom'] as num).toDouble();
  double get _normalMarginLeft => (_currentSizeConfig['marginLeft'] as num).toDouble();
  double get _normalMarginRight => (_currentSizeConfig['marginRight'] as num).toDouble();
  bool get _normalLogo => _currentSizeConfig['logo'] as bool;
  set _normalLogo(bool v) => _currentSizeConfig['logo'] = v;
  double get _normalLogoWidth => (_currentSizeConfig['logoWidth'] as num).toDouble();
  double get _normalLogoHeight => (_currentSizeConfig['logoHeight'] as num).toDouble();
  bool get _normalPdf417 => _currentSizeConfig['pdf417'] as bool;
  set _normalPdf417(bool v) => _currentSizeConfig['pdf417'] = v;
  String get _normalPdf417Position => _currentSizeConfig['pdf417Position'] as String;
  set _normalPdf417Position(String v) => _currentSizeConfig['pdf417Position'] = v;
  bool get _normalCctv => _currentSizeConfig['cctv'] as bool;
  set _normalCctv(bool v) => _currentSizeConfig['cctv'] = v;
  int get _normalFontSize => _currentSizeConfig['fontSize'] as int;

  // Thermal
  String _thermalWidth = '80mm';
  bool _thermalLogo = true;
  bool _thermalPdf417 = true;
  String _thermalCutMode = 'Full';
  int _thermalFontSize = 12;

  // Dot Matrix
  double _dmPaperWidth = 8.0;
  double _dmPageHeight = 4.0;
  int _dmMarginTop = 1;
  int _dmMarginBottom = 1;
  int _dmMarginLeft = 2;
  bool _dmLogo = false;
  bool _dmPdf417 = true;
  int _dmCpi = 10;
  int _dmLpi = 6;

  // Header layout
  String _headerLayout = 'inline';
  int _headerRows = 3;

  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(stepSaveCallbackProvider.notifier).state = _save;
    });
  }

  @override
  void dispose() {
    try {
    } catch (_) {}
    super.dispose();
  }

  void _updateHasData() {
    ref.read(stepHasDataProvider.notifier).state = _printers.isNotEmpty;
  }

  Future<void> _loadData() async {
    final paths = ref.read(firestorePathsProvider);
    if (!paths.isConfigured) {
      await _detectPrinters();
      setState(() => _loaded = true);
      return;
    }

    try {
      final snap = await paths.printingSettings.get();
      final data = snap.data() ?? {};
      if (mounted) {
        setState(() {
          _printers = (data['printers'] as List<dynamic>?)
              ?.map((p) => Map<String, dynamic>.from(p as Map))
              .toList() ?? [];
          _grossPrinter = data['grossPrinter'] as String? ?? 'default';
          _grossTray = data['grossTray'] as String? ?? '';
          _tarePrinter = data['tarePrinter'] as String? ?? 'default';
          _tareTray = data['tareTray'] as String? ?? '';
          _backupEnabled = data['backupEnabled'] as bool? ?? false;
          _backupPrinter = data['backupPrinter'] as String? ?? '';
          _backupTray = data['backupTray'] as String? ?? '';
          _copies = data['copies'] as int? ?? 2;
          _printOnGross = data['printOnGross'] as bool? ?? false;
          _printOnTare = data['printOnTare'] as bool? ?? true;
          _autoPrint = data['autoPrint'] as bool? ?? true;
          _reprintAllowed = data['reprintAllowed'] as bool? ?? true;
          _maxReprints = data['maxReprints'] as int? ?? 2;
          _normalPaperSize = data['normalPaperSize'] as String? ?? 'A4';
          final savedPerSize = data['perSizeConfigs'] as Map<String, dynamic>?;
          if (savedPerSize != null) {
            for (final entry in savedPerSize.entries) {
              if (_perSizeConfigs.containsKey(entry.key) && entry.value is Map<String, dynamic>) {
                _perSizeConfigs[entry.key] = Map<String, dynamic>.from(entry.value);
              }
            }
          } else {
            _currentSizeConfig['marginTop'] = (data['normalMarginTop'] as num?)?.toDouble() ?? _currentSizeConfig['marginTop'];
            _currentSizeConfig['marginBottom'] = (data['normalMarginBottom'] as num?)?.toDouble() ?? _currentSizeConfig['marginBottom'];
            _currentSizeConfig['marginLeft'] = (data['normalMarginLeft'] as num?)?.toDouble() ?? _currentSizeConfig['marginLeft'];
            _currentSizeConfig['marginRight'] = (data['normalMarginRight'] as num?)?.toDouble() ?? _currentSizeConfig['marginRight'];
            _currentSizeConfig['logo'] = data['normalLogo'] as bool? ?? true;
            _currentSizeConfig['pdf417'] = data['normalPdf417'] as bool? ?? true;
            _currentSizeConfig['pdf417Position'] = data['normalPdf417Position'] as String? ?? 'bottom';
            _currentSizeConfig['cctv'] = data['normalCctv'] as bool? ?? true;
            _currentSizeConfig['fontSize'] = data['normalFontSize'] as int? ?? 18;
          }
          _thermalWidth = data['thermalWidth'] as String? ?? '80mm';
          _thermalLogo = data['thermalLogo'] as bool? ?? true;
          _thermalPdf417 = data['thermalPdf417'] as bool? ?? true;
          _thermalCutMode = data['thermalCutMode'] as String? ?? 'Full';
          _thermalFontSize = data['thermalFontSize'] as int? ?? 12;
          _dmPaperWidth = (data['dmPaperWidth'] as num?)?.toDouble() ?? 8.0;
          _dmPageHeight = (data['dmPageHeight'] as num?)?.toDouble() ?? 4.0;
          _dmMarginTop = data['dmMarginTop'] as int? ?? 1;
          _dmMarginBottom = data['dmMarginBottom'] as int? ?? 1;
          _dmMarginLeft = data['dmMarginLeft'] as int? ?? 2;
          _dmLogo = data['dmLogo'] as bool? ?? false;
          _dmPdf417 = data['dmPdf417'] as bool? ?? true;
          _dmCpi = data['dmCpi'] as int? ?? 10;
          _dmLpi = data['dmLpi'] as int? ?? 6;
          _headerLayout = data['headerLayout'] as String? ?? 'inline';
          _headerRows = data['headerRows'] as int? ?? 3;
          _loaded = true;
        });
        if (_printers.isEmpty) {
          await _detectPrinters();
        } else {
          _loadPrinterTrays();
        }
        _updateHasData();
      }
    } catch (_) {
      await _detectPrinters();
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _detectPrinters() async {
    try {
      final infos = await Printing.listPrinters();
      if (mounted && infos.isNotEmpty) {
        setState(() {
          _printers = infos.map((info) => <String, dynamic>{
            'name': info.name,
            'isDefault': info.isDefault,
            'type': 'normal',
            'nickname': '',
            'trayMapping': <String, dynamic>{},
          }).toList();
          final defaultPrinter = infos.where((p) => p.isDefault).firstOrNull;
          final defaultName = defaultPrinter?.name ?? infos.first.name;
          _grossPrinter = defaultName;
          _tarePrinter = defaultName;
        });
        _updateHasData();
        _loadPrinterTrays();
      }
    } catch (_) {}
  }

  String _resolveSystemName(String displayName) {
    if (displayName == 'default') return '';
    for (final p in _printers) {
      final nickname = p['nickname'] as String? ?? '';
      final sysName = p['name'] as String? ?? '';
      if (nickname.isNotEmpty && nickname == displayName) return sysName;
      if (sysName == displayName) return sysName;
    }
    return displayName;
  }

  List<String> _getTraysForPrinter(String printerName) => _printerTrays[_resolveSystemName(printerName)] ?? [];

  Future<void> _loadPrinterTrays() async {
    final trays = <String, List<String>>{};
    for (final p in _printers) {
      final name = p['name'] as String? ?? '';
      if (name.isEmpty) continue;
      try {
        if (Platform.isWindows) {
          final result = await Process.run('powershell', ['-Command', 'Get-PrinterProperty -PrinterName "$name" | Where-Object { \$_.PropertyName -eq "Config:InputBin" } | Select-Object -ExpandProperty Value']);
          if (result.exitCode == 0) {
            final output = (result.stdout as String).trim();
            if (output.isNotEmpty) {
              final options = output.split(RegExp(r'[\r\n]+')).map((o) => o.trim()).where((o) => o.isNotEmpty).toList();
              if (options.length > 1) trays[name] = options;
            }
          }
        } else {
          final cupsPrinterName = name.replaceAll(RegExp(r'[\s\-]+'), '_');
          final result = await Process.run('lpoptions', ['-p', cupsPrinterName, '-l']);
          if (result.exitCode == 0) {
            final output = result.stdout as String;
            for (final line in output.split('\n')) {
              if (line.startsWith('InputSlot/')) {
                final parts = line.split(':');
                if (parts.length == 2) {
                  final options = parts[1].trim().split(RegExp(r'\s+')).map((o) => o.replaceAll('*', '')).toList();
                  if (options.length > 1) trays[name] = options;
                }
                break;
              }
            }
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _printerTrays = trays);
  }

  List<String> get _printerNames {
    final names = <String>['default'];
    for (final p in _printers) {
      final nickname = p['nickname'] as String? ?? '';
      final name = p['name'] as String? ?? '';
      names.add(nickname.isNotEmpty ? nickname : name);
    }
    return names;
  }

  Future<bool> _save() async {
    try {
      final paths = ref.read(firestorePathsProvider);
      await paths.printingSettings.set({
        'printers': _printers,
        'grossPrinter': _grossPrinter,
        'grossTray': _grossTray,
        'tarePrinter': _tarePrinter,
        'tareTray': _tareTray,
        'backupEnabled': _backupEnabled,
        'backupPrinter': _backupPrinter,
        'backupTray': _backupTray,
        'copies': _copies,
        'printOnGross': _printOnGross,
        'printOnTare': _printOnTare,
        'autoPrint': _autoPrint,
        'reprintAllowed': _reprintAllowed,
        'maxReprints': _maxReprints,
        'normalPaperSize': _normalPaperSize,
        'normalMarginTop': _normalMarginTop,
        'normalMarginBottom': _normalMarginBottom,
        'normalMarginLeft': _normalMarginLeft,
        'normalMarginRight': _normalMarginRight,
        'normalLogo': _normalLogo,
        'normalLogoWidth': _normalLogoWidth,
        'normalLogoHeight': _normalLogoHeight,
        'normalPdf417': _normalPdf417,
        'normalPdf417Position': _normalPdf417Position,
        'normalCctv': _normalCctv,
        'normalFontSize': _normalFontSize,
        'perSizeConfigs': _perSizeConfigs,
        'thermalWidth': _thermalWidth,
        'thermalLogo': _thermalLogo,
        'thermalPdf417': _thermalPdf417,
        'thermalCutMode': _thermalCutMode,
        'thermalFontSize': _thermalFontSize,
        'dmPaperWidth': _dmPaperWidth,
        'dmPageHeight': _dmPageHeight,
        'dmMarginTop': _dmMarginTop,
        'dmMarginBottom': _dmMarginBottom,
        'dmMarginLeft': _dmMarginLeft,
        'dmLogo': _dmLogo,
        'dmPdf417': _dmPdf417,
        'dmCpi': _dmCpi,
        'dmLpi': _dmLpi,
        'headerLayout': _headerLayout,
        'headerRows': _headerRows,
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), behavior: SnackBarBehavior.floating),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (!_loaded) return const AppLoading();

    return SingleChildScrollView(
      padding: EdgeInsets.all(40.rs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Printing', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: 8.rs),
          Text(
            'Configure printers and docket printing rules for weighment records.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          SizedBox(height: 32.rs),

          // Row 1: Printers + Assignment side by side
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Detected Printers
              Expanded(
                child: _buildCard(scheme, children: [
                  _buildSectionHeader('Detected Printers', Icons.print_rounded, scheme, text),
                  SizedBox(height: 12.rs),
                  if (_printers.isEmpty)
                    _buildEmptyState('No printers detected.', scheme, text)
                  else
                    ..._printers.asMap().entries.map((e) => _buildPrinterCard(e.key, e.value, scheme, text)),
                  SizedBox(height: 8.rs),
                  OutlinedButton.icon(
                    onPressed: _detectPrinters,
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text('Refresh'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
                    ),
                  ),
                ]),
              ),
              SizedBox(width: 20.rs),
              // Right: Assignment + Rules
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCard(scheme, children: [
                      _buildSectionHeader('Printer Assignment', Icons.swap_horiz_rounded, scheme, text),
                      SizedBox(height: 12.rs),
                      _buildAssignmentRowWithTray('1st Weighment:', _grossPrinter, _grossTray,
                        (v) => setState(() { _grossPrinter = v; _grossTray = ''; }),
                        (v) => setState(() => _grossTray = v), scheme, text),
                      SizedBox(height: 10.rs),
                      _buildAssignmentRowWithTray('2nd Weighment:', _tarePrinter, _tareTray,
                        (v) => setState(() { _tarePrinter = v; _tareTray = ''; }),
                        (v) => setState(() => _tareTray = v), scheme, text),
                      SizedBox(height: 10.rs),
                      Row(
                        children: [
                          Text('Backup:', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                          SizedBox(width: 8.rs),
                          SizedBox(height: 28, child: Switch(value: _backupEnabled, onChanged: (v) => setState(() => _backupEnabled = v))),
                          if (_backupEnabled) ...[
                            SizedBox(width: 8.rs),
                            Flexible(child: _buildPrinterDropdown(_backupPrinter, _printerNames.where((n) => n != _grossPrinter || n != _tarePrinter).toList(),
                                (v) => setState(() { _backupPrinter = v; _backupTray = ''; }), scheme)),
                            if (_getTraysForPrinter(_backupPrinter).isNotEmpty) ...[
                              SizedBox(width: 8.rs),
                              _buildTrayDropdown(_backupTray, _getTraysForPrinter(_backupPrinter), (v) => setState(() => _backupTray = v), scheme),
                            ],
                          ],
                        ],
                      ),
                    ]),
                    SizedBox(height: 16.rs),
                    _buildCard(scheme, children: [
                      _buildSectionHeader('Print Rules', Icons.tune_rounded, scheme, text),
                      SizedBox(height: 12.rs),
                      Wrap(
                        spacing: 16,
                        runSpacing: 10,
                        children: [
                          _buildCounterField('Copies', _copies, 1, 10, (v) => setState(() => _copies = v), scheme, text),
                          _buildToggleChip('Gross', _printOnGross, (v) => setState(() => _printOnGross = v), scheme),
                          _buildToggleChip('Tare', _printOnTare, (v) => setState(() => _printOnTare = v), scheme),
                          _buildToggleChip('Auto', _autoPrint, (v) => setState(() => _autoPrint = v), scheme),
                          _buildToggleChip('Reprint', _reprintAllowed, (v) => setState(() => _reprintAllowed = v), scheme),
                          if (_reprintAllowed)
                            _buildCounterField('Max', _maxReprints, 1, 20, (v) => setState(() => _maxReprints = v), scheme, text),
                        ],
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: 24.rs),

          // Row 2: Show config only for printer types that exist in detected printers
          if (_detectedTypes.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_detectedTypes.contains('normal')) ...[
                  Expanded(
                    child: _buildCard(scheme, children: [
                      _buildSectionHeader('Page Printer', Icons.description_rounded, scheme, text),
                      SizedBox(height: 12.rs),
                      Text('Content', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                      SizedBox(height: 6.rs),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _buildToggleChip('Logo', _normalLogo, (v) => setState(() => _normalLogo = v), scheme),
                          _buildToggleChip('PDF417', _normalPdf417, (v) => setState(() => _normalPdf417 = v), scheme),
                          _buildToggleChip('CCTV', _normalCctv, (v) => setState(() => _normalCctv = v), scheme),
                        ],
                      ),
                      if (_normalPdf417) ...[
                        SizedBox(height: 8.rs),
                        Row(
                          children: [
                            Text('PDF417:', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                            SizedBox(width: 6.rs),
                            _buildSelectChip('Top', _normalPdf417Position == 'top', () => setState(() => _normalPdf417Position = 'top'), scheme),
                            SizedBox(width: 4.rs),
                            _buildSelectChip('Bottom', _normalPdf417Position == 'bottom', () => setState(() => _normalPdf417Position = 'bottom'), scheme),
                          ],
                        ),
                      ],
                    ]),
                  ),
                ],
                if (_detectedTypes.contains('normal') && (_detectedTypes.contains('thermal') || _detectedTypes.contains('dotMatrix')))
                  SizedBox(width: 16.rs),
                if (_detectedTypes.contains('thermal')) ...[
                  Expanded(
                    child: _buildCard(scheme, children: [
                      _buildSectionHeader('Thermal', Icons.receipt_long_rounded, scheme, text),
                      SizedBox(height: 12.rs),
                      Text('Content', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                      SizedBox(height: 6.rs),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _buildToggleChip('Logo', _thermalLogo, (v) => setState(() => _thermalLogo = v), scheme),
                          _buildToggleChip('PDF417', _thermalPdf417, (v) => setState(() => _thermalPdf417 = v), scheme),
                        ],
                      ),
                      SizedBox(height: 12.rs),
                      Text('Cut Mode', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                      SizedBox(height: 6.rs),
                      Wrap(
                        spacing: 6,
                        children: ['Full', 'Partial', 'None'].map((m) =>
                          _buildSelectChip(m, _thermalCutMode == m, () => setState(() => _thermalCutMode = m), scheme),
                        ).toList(),
                      ),
                    ]),
                  ),
                ],
                if (_detectedTypes.contains('thermal') && _detectedTypes.contains('dotMatrix'))
                  SizedBox(width: 16.rs),
                if (_detectedTypes.contains('dotMatrix')) ...[
                  Expanded(
                    child: _buildCard(scheme, children: [
                      _buildSectionHeader('Dot Matrix', Icons.grid_on_rounded, scheme, text),
                      SizedBox(height: 12.rs),
                      Text('Paper Width', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                      SizedBox(height: 6.rs),
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: _dmPaperWidth,
                              min: 8.0,
                              max: 13.2,
                              divisions: 26,
                              label: '${_dmPaperWidth.toStringAsFixed(1)}″',
                              onChanged: (v) => setState(() => _dmPaperWidth = double.parse(v.toStringAsFixed(1))),
                            ),
                          ),
                          Text('${_dmPaperWidth.toStringAsFixed(1)}″', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      SizedBox(height: 12.rs),
                      Text('Content', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                      SizedBox(height: 6.rs),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _buildToggleChip('Logo', _dmLogo, (v) => setState(() => _dmLogo = v), scheme),
                          _buildToggleChip('PDF417', _dmPdf417, (v) => setState(() => _dmPdf417 = v), scheme),
                        ],
                      ),
                    ]),
                  ),
                ],
              ],
            ),

          SizedBox(height: 24.rs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8.rs),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, size: 14, color: scheme.onSurfaceVariant),
                SizedBox(width: 10.rs),
                Expanded(
                  child: Text(
                    'Docket templates, live preview, margins, and material-based routing are available in Settings after setup.',
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Docket Preview ──────────────────────────────────────────────────────────

  Widget _buildDocketPreview(ColorScheme scheme, TextTheme text, {required bool isNormal}) {
    final showLogo = isNormal ? _normalLogo : _thermalLogo;
    final showPdf417 = isNormal ? _normalPdf417 : _thermalPdf417;
    final pdf417Pos = isNormal ? _normalPdf417Position : 'bottom';

    return Container(
      padding: EdgeInsets.all(10.rs),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          if (showPdf417 && pdf417Pos == 'top') ...[
            _buildPdf417Placeholder(scheme),
            SizedBox(height: 6.rs),
          ],
          if (showLogo) ...[
            _buildLogoPlaceholder(scheme,
              width: isNormal ? (_normalLogoWidth * 0.6).clamp(40, 100) : 60,
              height: isNormal ? (_normalLogoHeight * 0.6).clamp(20, 60) : 24,
            ),
            SizedBox(height: 6.rs),
          ],
          // Sample docket lines
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                Container(height: 2, width: double.infinity, color: Colors.black87),
                SizedBox(height: 4.rs),
                _buildDocketLine('Ticket No:', 'WB-00142', scheme),
                _buildDocketLine('Vehicle:', 'MH-04-AB-1234', scheme),
                _buildDocketLine('Material:', 'Sand', scheme),
                _buildDocketLine('Gross:', '24,500 kg', scheme),
                _buildDocketLine('Tare:', '8,200 kg', scheme),
                _buildDocketLine('Net:', '16,300 kg', scheme),
                SizedBox(height: 4.rs),
                Container(height: 1, width: double.infinity, color: Colors.black26),
              ],
            ),
          ),
          if (showPdf417 && pdf417Pos == 'bottom') ...[
            SizedBox(height: 6.rs),
            _buildPdf417Placeholder(scheme),
          ],
        ],
      ),
    );
  }

  Widget _buildLogoPlaceholder(ColorScheme scheme, {required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(4.rs),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Text(
          'LOGO',
          style: TextStyle(
            fontSize: height * 0.35,
            fontWeight: FontWeight.w800,
            color: scheme.primary.withValues(alpha: 0.6),
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildPdf417Placeholder(ColorScheme scheme) {
    return Container(
      width: 80,
      height: 18,
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(2),
      ),
      child: const Center(
        child: Text('||||||||||||', style: TextStyle(fontSize: 8, color: Colors.white70, letterSpacing: -0.5)),
      ),
    );
  }

  Widget _buildDocketLine(String label, String value, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 8, color: Colors.black54)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: Colors.black87)),
        ],
      ),
    );
  }

  // ─── Helper Widgets ─────────────────────────────────────────────────────────

  Widget _buildCard(ColorScheme scheme, {required List<Widget> children}) {
    return Container(
      padding: EdgeInsets.all(16.rs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, ColorScheme scheme, TextTheme text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        SizedBox(width: 8.rs),
        Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildEmptyState(String message, ColorScheme scheme, TextTheme text) {
    return Container(
      padding: EdgeInsets.all(16.rs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: scheme.onSurfaceVariant),
          SizedBox(width: 10.rs),
          Text(message, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Set<String> get _detectedTypes => _printers.map((p) => p['type'] as String? ?? 'normal').toSet();

  void _removePrinter(int index) {
    final name = _printers[index]['name'] as String? ?? '';
    setState(() {
      _printers.removeAt(index);
      if (_grossPrinter == name) _grossPrinter = _printerNames.first;
      if (_tarePrinter == name) _tarePrinter = _printerNames.first;
      if (_backupPrinter == name) _backupPrinter = '';
    });
    _updateHasData();
  }

  Widget _buildPrinterCard(int index, Map<String, dynamic> printer, ColorScheme scheme, TextTheme text) {
    final name = printer['name'] as String? ?? '';
    final type = printer['type'] as String? ?? 'normal';
    final isDefault = printer['isDefault'] as bool? ?? false;
    final trays = _printerTrays[name] ?? [];
    final typeIcons = {'normal': Icons.description_rounded, 'thermal': Icons.receipt_long_rounded, 'dotMatrix': Icons.grid_on_rounded};
    final typeLabels = {'normal': 'Page', 'thermal': 'Thermal', 'dotMatrix': 'Dot Matrix'};

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(typeIcons[type] ?? Icons.print_rounded, size: 16, color: scheme.primary),
              SizedBox(width: 10.rs),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                    ),
                    if (isDefault) ...[
                      SizedBox(width: 6.rs),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(4.rs)),
                        child: Text('Default', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: scheme.primary)),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6.rs),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: DropdownButton<String>(
                  value: type,
                  isDense: true,
                  underline: const SizedBox(),
                  style: TextStyle(fontSize: 11, color: scheme.onSurface),
                  items: typeLabels.entries.map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(typeIcons[e.key], size: 12, color: scheme.onSurfaceVariant),
                        SizedBox(width: 4.rs),
                        Text(e.value, style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  )).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _printers[index]['type'] = v);
                  },
                ),
              ),
              SizedBox(width: 8.rs),
              InkWell(
                onTap: () => _removePrinter(index),
                borderRadius: BorderRadius.circular(6.rs),
                child: Padding(
                  padding: EdgeInsets.all(4.rs),
                  child: Icon(Icons.close_rounded, size: 14, color: scheme.error),
                ),
              ),
            ],
          ),
          // Page printer: tray → paper size mapping (or single paper size if no trays)
          if (type == 'normal' && trays.isNotEmpty) ...[
            SizedBox(height: 8.rs),
            Container(
              padding: EdgeInsets.all(8.rs),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8.rs),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tray → Paper Size', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.5)),
                  SizedBox(height: 6.rs),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: trays.map((tray) {
                      final mapping = (printer['trayMapping'] as Map<String, dynamic>?) ?? {};
                      final currentSize = mapping[tray] as String? ?? 'Dynamic';
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(6.rs),
                          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(tray, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: scheme.onSurface)),
                            SizedBox(width: 6.rs),
                            Icon(Icons.arrow_forward_rounded, size: 10, color: scheme.onSurfaceVariant),
                            SizedBox(width: 4.rs),
                            SizedBox(
                              height: 22,
                              child: DropdownButton<String>(
                                value: currentSize,
                                isDense: true,
                                underline: const SizedBox(),
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: scheme.onSurface),
                                icon: Icon(Icons.keyboard_arrow_down_rounded, size: 12, color: scheme.onSurfaceVariant),
                                items: ['Dynamic', 'A4', 'A5', 'Letter', 'Legal'].map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 10)))).toList(),
                                onChanged: (v) {
                                  setState(() {
                                    final m = Map<String, dynamic>.from(mapping);
                                    m[tray] = v ?? 'Dynamic';
                                    _printers[index]['trayMapping'] = m;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
          // Page printer without trays: single paper size
          if (type == 'normal' && trays.isEmpty) ...[
            SizedBox(height: 8.rs),
            Row(
              children: [
                Text('Paper:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                SizedBox(width: 8.rs),
                ...['A4', 'A5', 'Letter', 'Legal'].map((size) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _buildSelectChip(size, (printer['paperSize'] as String? ?? _normalPaperSize) == size, () {
                    setState(() => _printers[index]['paperSize'] = size);
                  }, scheme),
                )),
              ],
            ),
          ],
          // Thermal: width selection per printer
          if (type == 'thermal') ...[
            SizedBox(height: 8.rs),
            Row(
              children: [
                Text('Width:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                SizedBox(width: 8.rs),
                ...['58mm', '80mm'].map((w) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _buildSelectChip(w, (printer['thermalWidth'] as String? ?? _thermalWidth) == w, () {
                    setState(() => _printers[index]['thermalWidth'] = w);
                  }, scheme),
                )),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAssignmentRowWithTray(String label, String printer, String tray, ValueChanged<String> onPrinterChanged, ValueChanged<String> onTrayChanged, ColorScheme scheme, TextTheme text) {
    final trays = _getTraysForPrinter(printer);
    return Row(
      children: [
        SizedBox(width: 120, child: Text(label, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
        Flexible(child: _buildPrinterDropdown(printer, _printerNames, onPrinterChanged, scheme)),
        if (trays.isNotEmpty) ...[
          SizedBox(width: 8.rs),
          _buildTrayDropdown(tray, trays, onTrayChanged, scheme),
        ],
      ],
    );
  }

  Widget _buildTrayDropdown(String value, List<String> trays, ValueChanged<String> onChanged, ColorScheme scheme) {
    final isAuto = value.isEmpty;
    final items = trays;
    final effectiveValue = isAuto ? null : (items.contains(value) ? value : null);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => onChanged(''),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: isAuto ? scheme.tertiary.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(6.rs),
              border: Border.all(color: isAuto ? scheme.tertiary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_mode_rounded, size: 11, color: isAuto ? scheme.tertiary : scheme.onSurfaceVariant),
                SizedBox(width: 4.rs),
                Text('Auto', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isAuto ? scheme.tertiary : scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
        SizedBox(width: 4.rs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: !isAuto ? scheme.tertiary.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(6.rs),
            border: Border.all(color: !isAuto ? scheme.tertiary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: DropdownButton<String>(
            value: effectiveValue,
            hint: Text('Tray', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            isDense: true,
            underline: const SizedBox(),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.tertiary),
            icon: Icon(Icons.inventory_2_outlined, size: 11, color: !isAuto ? scheme.tertiary : scheme.onSurfaceVariant),
            items: items.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 10)))).toList(),
            onChanged: (v) { if (v != null) onChanged(v); },
          ),
        ),
      ],
    );
  }

  Widget _buildPrinterDropdown(String value, List<String> items, ValueChanged<String> onChanged, ColorScheme scheme) {
    final effectiveValue = items.contains(value) ? value : items.first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: DropdownButton<String>(
        value: effectiveValue,
        isDense: true,
        underline: const SizedBox(),
        style: TextStyle(fontSize: 12, color: scheme.onSurface),
        items: items.map((n) => DropdownMenuItem(value: n, child: Text(n, style: const TextStyle(fontSize: 12)))).toList(),
        onChanged: (v) { if (v != null) onChanged(v); },
      ),
    );
  }

  Widget _buildCounterField(String label, int value, int min, int max, ValueChanged<int> onChanged, ColorScheme scheme, TextTheme text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label:', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(width: 6.rs),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(6.rs),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: value > min ? () => onChanged(value - 1) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Icon(Icons.remove, size: 12, color: value > min ? scheme.primary : scheme.outlineVariant),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(border: Border.symmetric(vertical: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)))),
                child: Text('$value', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
              ),
              InkWell(
                onTap: value < max ? () => onChanged(value + 1) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Icon(Icons.add, size: 12, color: value < max ? scheme.primary : scheme.outlineVariant),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToggleChip(String label, bool value, ValueChanged<bool> onChanged, ColorScheme scheme) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: value ? scheme.primary.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(8.rs),
          border: Border.all(color: value ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(value ? Icons.check_circle_rounded : Icons.circle_outlined, size: 14, color: value ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.5)),
            SizedBox(width: 6.rs),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: value ? scheme.primary : scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectChip(String label, bool selected, VoidCallback onTap, ColorScheme scheme) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6.rs),
          border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? scheme.surface : scheme.onSurfaceVariant)),
      ),
    );
  }


}
