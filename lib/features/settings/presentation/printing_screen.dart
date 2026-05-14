import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';
import 'package:weighbridgemanagement/shared/providers/general_settings_provider.dart';
import 'package:weighbridgemanagement/shared/providers/print_provider.dart';
import 'package:weighbridgemanagement/shared/providers/scale_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';

// ─── Providers ──────────────────────────────────────────────────────────────

final _printSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestoreProvider);
  final doc = await db.collection('settings').doc('printing').get();
  return doc.exists ? doc.data()! : {};
});

final _companyLogoProvider = FutureProvider<Uint8List?>((ref) async {
  final db = ref.watch(firestoreProvider);
  final doc = await db.collection('settings').doc('general_docs').get();
  if (!doc.exists) return null;
  final dataUri = doc.data()?['company_logo'] as String?;
  if (dataUri == null || !dataUri.startsWith('data:')) return null;
  final b64 = dataUri.split(',').last;
  return base64Decode(b64);
});

class _DmDotData {
  final int width;
  final int height;
  final List<bool> dots;
  _DmDotData(this.width, this.height, this.dots);
}

final _dmMonoLogoProvider = FutureProvider<_DmDotData?>((ref) async {
  final logoBytes = await ref.watch(_companyLogoProvider.future);
  if (logoBytes == null) return null;
  var decoded = img.decodeImage(logoBytes);
  if (decoded == null) return null;

  final settings = await ref.watch(_printSettingsProvider.future);
  final logoCharW = settings['dmLogoWidth'] as int? ?? 18;
  // Match print service: 10 CPI ≈ 6px per char at 60 DPI
  final targetPx = logoCharW * 6;
  if (decoded.width != targetPx) {
    decoded = img.copyResize(decoded, width: targetPx);
  }

  final grayscale = img.grayscale(decoded);
  final mono = img.ditherImage(grayscale);
  final w = mono.width;
  final h = mono.height;
  final dots = List<bool>.filled(w * h, false);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      dots[y * w + x] = img.getLuminance(mono.getPixel(x, y)) < 128;
    }
  }
  return _DmDotData(w, h, dots);
});

final _companyInfoProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestoreProvider);
  final doc = await db.collection('settings').doc('general').get();
  return doc.exists ? doc.data()! : {};
});

final _customFieldsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final db = ref.watch(firestoreProvider);
  final doc = await db.collection('settings').doc('customFields').get();
  if (!doc.exists) return [];
  final fields = doc.data()?['fields'] as List<dynamic>?;
  if (fields == null) return [];
  return fields
      .map((f) => Map<String, dynamic>.from(f as Map))
      .where((f) => f['enabled'] == true && (f['label'] as String?)?.isNotEmpty == true)
      .toList();
});

final _materialsProvider = StreamProvider<List<String>>((ref) {
  final db = ref.watch(firestoreProvider);
  return db.collection('materials').orderBy('order').snapshots().map(
    (snap) => snap.docs.map((d) => d.data()['name'] as String? ?? '').where((n) => n.isNotEmpty).toList(),
  );
});

// ─── Placeholders ───────────────────────────────────────────────────────────

class _Placeholder {
  final String key;
  final String label;
  final String category;

  const _Placeholder(this.key, this.label, this.category);
}

const _builtInPlaceholders = [
  // Company
  _Placeholder('{company_name}', 'Company Name', 'Company'),
  _Placeholder('{company_address1}', 'Company Address Line 1', 'Company'),
  _Placeholder('{company_address2}', 'Company Address Line 2', 'Company'),
  _Placeholder('{company_phone}', 'Company Phone', 'Company'),
  _Placeholder('{company_gstin}', 'Company GSTIN', 'Company'),
  // Customer
  _Placeholder('{customer_name}', 'Customer Name', 'Customer'),
  _Placeholder('{customer_address}', 'Customer Address', 'Customer'),
  _Placeholder('{customer_phone}', 'Customer Phone', 'Customer'),
  // Weighment
  _Placeholder('{vehicle}', 'Vehicle Number', 'Weighment'),
  _Placeholder('{material}', 'Material', 'Weighment'),
  _Placeholder('{gross}', 'Gross Weight (kg)', 'Weighment'),
  _Placeholder('{tare}', 'Tare Weight (kg)', 'Weighment'),
  _Placeholder('{net}', 'Net Weight (kg)', 'Weighment'),
  _Placeholder('{gross_datetime}', 'Gross Weighment Date & Time', 'Weighment'),
  _Placeholder('{tare_datetime}', 'Tare Weighment Date & Time', 'Weighment'),
  _Placeholder('{net_datetime}', 'Net Weighment Date & Time', 'Weighment'),
  _Placeholder('{rst}', 'RST Number', 'Weighment'),
  _Placeholder('{operator}', 'Operator Name', 'Weighment'),
  // System
  _Placeholder('{date}', 'Current Date', 'System'),
  _Placeholder('{pc_name}', 'PC Name', 'System'),
  _Placeholder('{port_name}', 'Port Name', 'System'),
  _Placeholder('{weighbridge_name}', 'Weighbridge Name', 'System'),
];

// ─── Screen ─────────────────────────────────────────────────────────────────

class PrintingScreen extends ConsumerStatefulWidget {
  const PrintingScreen({super.key});

  @override
  ConsumerState<PrintingScreen> createState() => _PrintingScreenState();
}

class _PrintingScreenState extends ConsumerState<PrintingScreen> with SingleTickerProviderStateMixin {
  bool _loaded = false;
  bool _saving = false;
  bool _dirty = false;
  bool _normalOverflows = false;
  late TabController _tabController;

  // ── Printers ──
  List<Map<String, dynamic>> _printers = [];
  Map<String, List<String>> _printerTrays = {};

  // ── Printer Assignment ──
  String _grossPrinter = 'default';
  String _grossTray = '';
  String _tarePrinter = 'default';
  String _tareTray = '';
  String _backupPrinter = '';
  String _backupTray = '';
  bool _backupEnabled = false;
  bool _materialRoutingEnabled = false;
  List<Map<String, dynamic>> _materialPrinterRules = [];

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
          final cupsPrinterName = name.replaceAll(' ', '_');
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

  void _syncPrinterConfigToTemplates() {
    for (final p in _printers) {
      final type = p['type'] as String? ?? 'normal';
      final name = p['name'] as String? ?? '';
      final nickname = p['nickname'] as String? ?? '';
      final match = nickname.isNotEmpty ? nickname : name;
      if (type == 'dotMatrix' && (match == _grossPrinter || match == _tarePrinter)) {
        final w = (p['paperWidth'] as num?)?.toDouble();
        if (w != null) _dmPaperWidth = w;
      }
      if (type == 'thermal' && (match == _grossPrinter || match == _tarePrinter)) {
        final w = p['thermalWidth'] as String?;
        if (w != null) _thermalWidth = w;
      }
      if (type == 'normal' && (match == _grossPrinter || match == _tarePrinter)) {
        final ps = p['paperSize'] as String?;
        if (ps != null && ps != _normalPaperSize) {
          _normalPaperSize = ps;
          _applySizeConfig(_getDefaultSizeConfig(ps));
        }
      }
    }
  }

  void _syncTemplateToPrinters(String type, {double? paperWidth, String? thermalWidth, String? paperSize}) {
    for (final p in _printers) {
      final pType = p['type'] as String? ?? 'normal';
      if (pType != type) continue;
      if (type == 'dotMatrix' && paperWidth != null) {
        p['paperWidth'] = paperWidth;
      } else if (type == 'thermal' && thermalWidth != null) {
        p['thermalWidth'] = thermalWidth;
      } else if (type == 'normal' && paperSize != null) {
        p['paperSize'] = paperSize;
      }
    }
  }

  // ── Print Rules ──
  int _copies = 2;
  bool _printOnGross = false;
  bool _printOnTare = true;
  bool _autoPrint = true;
  bool _reprintAllowed = true;
  int _maxReprints = 3;

  // ── Dot Matrix ──
  double _dmPaperWidth = 10.0; // inches
  int get _dmColumns => (_dmPaperWidth * 10).round(); // 10 CPI (Normal)
  double _dmPageHeight = 4.0; // cut length in inches
  int _dmMarginTop = 1;
  int _dmMarginBottom = 1;
  int _dmMarginLeft = 2;
  bool _dmLogo = false;
  int _dmLogoWidth = 18;
  int _dmLogoHeight = 8;
  List<Map<String, dynamic>> _dmLines = [];

  // ── Thermal ──
  String _thermalWidth = '80mm';
  bool _thermalLogo = true;
  bool _thermalPdf417 = true;
  String _thermalCutMode = 'Full';
  int _thermalFontSize = 12;
  String _thermalFont = 'Font A';
  List<Map<String, dynamic>> _thermalLines = [];

  // ── Header Layout (normal printer only) ──
  String _headerLayout = 'inline';  // 'stacked' or 'inline' (logo beside text)
  int _headerRows = 3; // number of top lines logo sits beside when inline

  // ── Per-template Logo ──
  double _thermalLogoWidth = 30;
  double _thermalLogoHeight = 30;
  double _normalLogoWidth = 80;
  double _normalLogoHeight = 80;

  // ── Font ──
  int _normalFontSize = 14;
  String _normalFont = 'Helvetica';

  // ── Multi-column ──
  int _dmColumnCount = 1;

  // ── Normal ──
  String _normalPaperSize = 'A4';
  double _normalMarginTop = 15;
  double _normalMarginBottom = 15;
  double _normalMarginLeft = 15;
  double _normalMarginRight = 15;
  bool _normalLogo = true;
  bool _normalPdf417 = true;
  String _normalPdf417Position = 'bottom';
  bool _normalCctv = false;
  List<String> _normalCctvCameras = [];
  List<Map<String, dynamic>> _normalLines = [];

  // Per-size config store
  final Map<String, Map<String, dynamic>> _perSizeConfigs = {};

  Map<String, dynamic> _getCurrentSizeConfig() => {
    'marginTop': _normalMarginTop,
    'marginBottom': _normalMarginBottom,
    'marginLeft': _normalMarginLeft,
    'marginRight': _normalMarginRight,
    'headerLayout': _headerLayout,
    'headerRows': _headerRows,
    'logo': _normalLogo,
    'logoWidth': _normalLogoWidth,
    'logoHeight': _normalLogoHeight,
    'pdf417': _normalPdf417,
    'pdf417Position': _normalPdf417Position,
    'cctv': _normalCctv,
    'cctvCameras': List<String>.from(_normalCctvCameras),
    'fontSize': _normalFontSize,
    'normalLines': _normalLines.map((l) => Map<String, dynamic>.from(l)).toList(),
  };

  void _applySizeConfig(Map<String, dynamic> cfg) {
    _normalMarginTop = (cfg['marginTop'] as num?)?.toDouble() ?? 15;
    _normalMarginBottom = (cfg['marginBottom'] as num?)?.toDouble() ?? 15;
    _normalMarginLeft = (cfg['marginLeft'] as num?)?.toDouble() ?? 15;
    _normalMarginRight = (cfg['marginRight'] as num?)?.toDouble() ?? 15;
    _headerLayout = cfg['headerLayout'] as String? ?? 'inline';
    _headerRows = cfg['headerRows'] as int? ?? 3;
    _normalLogo = cfg['logo'] as bool? ?? true;
    _normalLogoWidth = (cfg['logoWidth'] as num?)?.toDouble() ?? 80;
    _normalLogoHeight = (cfg['logoHeight'] as num?)?.toDouble() ?? 80;
    _normalPdf417 = cfg['pdf417'] as bool? ?? true;
    _normalPdf417Position = cfg['pdf417Position'] as String? ?? 'bottom';
    _normalCctv = cfg['cctv'] as bool? ?? false;
    _normalCctvCameras = List<String>.from(cfg['cctvCameras'] as List? ?? []);
    _normalFontSize = cfg['fontSize'] as int? ?? 14;
    final lines = cfg['normalLines'] as List?;
    _normalLines = lines != null
        ? lines.map((l) => Map<String, dynamic>.from(l as Map)).toList()
        : _getDefaultNormalLines(paperSize: _normalPaperSize);
  }

  static Map<String, dynamic> _getDefaultSizeConfig(String size) {
    switch (size) {
      case 'A5':
        return {
          'marginTop': 5.0, 'marginBottom': 3.0, 'marginLeft': 10.0, 'marginRight': 10.0,
          'headerLayout': 'inline', 'headerRows': 3,
          'logo': true, 'logoWidth': 50.0, 'logoHeight': 50.0,
          'pdf417': false, 'pdf417Position': 'bottom',
          'cctv': false, 'cctvCameras': <String>[],
          'fontSize': 10,
          'normalLines': _getDefaultNormalLines(paperSize: 'A5'),
        };
      case 'Legal':
        return {
          'marginTop': 8.0, 'marginBottom': 5.0, 'marginLeft': 15.0, 'marginRight': 15.0,
          'headerLayout': 'inline', 'headerRows': 3,
          'logo': true, 'logoWidth': 80.0, 'logoHeight': 80.0,
          'pdf417': true, 'pdf417Position': 'bottom',
          'cctv': true, 'cctvCameras': ['Front', 'Rear', 'Top', 'Side', 'Operator', 'Customer'],
          'fontSize': 16,
          'normalLines': _getDefaultNormalLines(paperSize: 'Legal'),
        };
      case 'Letter':
        return {
          'marginTop': 8.0, 'marginBottom': 5.0, 'marginLeft': 15.0, 'marginRight': 15.0,
          'headerLayout': 'inline', 'headerRows': 3,
          'logo': true, 'logoWidth': 80.0, 'logoHeight': 80.0,
          'pdf417': true, 'pdf417Position': 'bottom',
          'cctv': true, 'cctvCameras': ['Front', 'Rear', 'Top', 'Side'],
          'fontSize': 14,
          'normalLines': _getDefaultNormalLines(paperSize: 'Letter'),
        };
      default: // A4
        return {
          'marginTop': 8.0, 'marginBottom': 5.0, 'marginLeft': 15.0, 'marginRight': 15.0,
          'headerLayout': 'inline', 'headerRows': 3,
          'logo': true, 'logoWidth': 80.0, 'logoHeight': 80.0,
          'pdf417': true, 'pdf417Position': 'bottom',
          'cctv': true, 'cctvCameras': ['Front', 'Rear', 'Top', 'Side'],
          'fontSize': 16,
          'normalLines': _getDefaultNormalLines(paperSize: 'A4'),
        };
    }
  }

  void _switchPaperSize(String newSize) {
    _perSizeConfigs[_normalPaperSize] = _getCurrentSizeConfig();
    _normalPaperSize = newSize;
    if (_perSizeConfigs.containsKey(newSize)) {
      _applySizeConfig(_perSizeConfigs[newSize]!);
    } else {
      _applySizeConfig(_getDefaultSizeConfig(newSize));
    }
    if (newSize != 'Legal') {
      _normalCctvCameras.removeWhere((c) => c == 'Operator' || c == 'Customer');
    }
    _syncTemplateToPrinters('normal', paperSize: newSize);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initDefaults();
  }

  void _initDefaults() {
    _dmPaperWidth = 10.0;
    _dmPageHeight = 4.0;
    _dmLogo = false;
    _dmLogoWidth = 18;
    _dmLogoHeight = 8;
    _dmMarginTop = 1;
    _dmMarginBottom = 1;
    _dmMarginLeft = 2;
    _dmLines = _getDefaultDmLines(columns: 100);
    _thermalLines = _getDefaultThermalLines();
    _normalLines = _getDefaultNormalLines(paperSize: _normalPaperSize);
  }

  static List<Map<String, dynamic>> _getDefaultDmLines({int columns = 100}) {
    return [
      {'text': '{company_name}', 'align': 'center', 'style': 'double'},
      {'text': '{company_address1}', 'align': 'center', 'style': 'normal'},
      {'text': '{company_address2}', 'align': 'center', 'style': 'normal'},
      {'text': '', 'align': 'left', 'style': 'separator'},
      {'text': 'RST: {rst}', 'align': 'left', 'style': 'normal', 'group': 1},
      {'text': 'Material: {material}', 'align': 'left', 'style': 'normal', 'group': 1},
      {'text': '', 'align': 'left', 'style': 'separator'},
      {'text': 'Vehicle: {vehicle}', 'align': 'left', 'style': 'normal', 'group': 2},
      {'text': 'Phone: {customer_phone}', 'align': 'left', 'style': 'normal', 'group': 2},
      {'text': 'Customer: {customer_name}', 'align': 'left', 'style': 'normal', 'group': 3},
      {'text': 'Address: {customer_address}', 'align': 'left', 'style': 'normal', 'group': 3},
      {'text': '', 'align': 'left', 'style': 'separator'},
      {'text': 'Gross: {gross} KG', 'align': 'left', 'style': 'normal', 'group': 4},
      {'text': '({gross_datetime})', 'align': 'left', 'style': 'normal', 'group': 4},
      {'text': 'Tare: {tare} KG', 'align': 'left', 'style': 'normal', 'group': 5},
      {'text': '({tare_datetime})', 'align': 'left', 'style': 'normal', 'group': 5},
      {'text': 'Net: {net} KG', 'align': 'left', 'style': 'bold', 'group': 6},
      {'text': '({net_datetime})', 'align': 'left', 'style': 'normal', 'group': 6},
      {'text': '', 'align': 'left', 'style': 'separator'},
      {'text': 'Operator: {operator}', 'align': 'left', 'style': 'normal', 'group': 7},
      {'text': 'PC: {pc_name}', 'align': 'left', 'style': 'normal', 'group': 7},
      {'text': 'Weighbridge: {weighbridge_name}', 'align': 'left', 'style': 'normal', 'group': 8},
      {'text': 'Port: {port_name}', 'align': 'left', 'style': 'normal', 'group': 8},
    ];
  }

  static List<Map<String, dynamic>> _defaultLinesForType(String type) {
    switch (type) {
      case 'dotMatrix': return _getDefaultDmLines();
      case 'thermal': return _getDefaultThermalLines();
      default: return _getDefaultNormalLines();
    }
  }

  static List<Map<String, dynamic>> _getDefaultThermalLines() => [
    {'text': '{company_name}', 'align': 'center', 'size': 'double'},
    {'text': '', 'align': 'left', 'size': 'separator'},
    {'text': 'RST: {rst}', 'align': 'left', 'size': 'normal'},
    {'text': 'Date: {date}', 'align': 'left', 'size': 'normal'},
    {'text': 'Material: {material}', 'align': 'left', 'size': 'normal'},
    {'text': '', 'align': 'left', 'size': 'separator'},
    {'text': 'Vehicle: {vehicle}', 'align': 'left', 'size': 'normal'},
    {'text': 'Phone: {customer_phone}', 'align': 'left', 'size': 'normal'},
    {'text': 'Customer: {customer_name}', 'align': 'left', 'size': 'normal'},
    {'text': 'Address: {customer_address}', 'align': 'left', 'size': 'normal'},
    {'text': '', 'align': 'left', 'size': 'separator'},
    {'text': 'Gross: {gross} KG', 'align': 'left', 'size': 'normal'},
    {'text': 'Tare: {tare} KG', 'align': 'left', 'size': 'normal'},
    {'text': 'Net: {net} KG', 'align': 'left', 'size': 'bold'},
    {'text': '', 'align': 'left', 'size': 'separator'},
    {'text': 'Operator: {operator}', 'align': 'left', 'size': 'normal'},
    {'text': 'Weighbridge: {weighbridge_name}', 'align': 'left', 'size': 'normal'},
  ];

  static List<Map<String, dynamic>> _getDefaultNormalLines({String paperSize = 'A4'}) {
    return [
      {'text': '{company_name}', 'align': 'left', 'style': 'bold'},
      {'text': '{company_address1}', 'align': 'left', 'style': 'normal'},
      {'text': '{company_address2}', 'align': 'left', 'style': 'normal'},
      {'text': '', 'align': 'left', 'style': 'blank'},
      {'text': 'Weighment Docket', 'align': 'center', 'style': 'bold'},
      {'text': '', 'align': 'left', 'style': 'blank'},
      {'text': 'RST: {rst}', 'align': 'left', 'style': 'normal', 'group': 1},
      {'text': 'Material: {material}', 'align': 'left', 'style': 'normal', 'group': 1},
      {'text': 'Vehicle: {vehicle}', 'align': 'left', 'style': 'normal', 'group': 2},
      {'text': 'Phone: {customer_phone}', 'align': 'left', 'style': 'normal', 'group': 2},
      {'text': 'Customer: {customer_name}', 'align': 'left', 'style': 'normal', 'group': 3},
      {'text': 'Address: {customer_address}', 'align': 'left', 'style': 'normal', 'group': 3},
      {'text': '', 'align': 'left', 'style': 'blank'},
      {'text': 'Gross: {gross} KG', 'align': 'left', 'style': 'normal', 'group': 4},
      {'text': '({gross_datetime})', 'align': 'left', 'style': 'normal', 'group': 4},
      {'text': 'Tare: {tare} KG', 'align': 'left', 'style': 'normal', 'group': 5},
      {'text': '({tare_datetime})', 'align': 'left', 'style': 'normal', 'group': 5},
      {'text': 'Net: {net} KG', 'align': 'left', 'style': 'bold', 'group': 6},
      {'text': '({net_datetime})', 'align': 'left', 'style': 'normal', 'group': 6},
      {'text': '', 'align': 'left', 'style': 'blank'},
      {'text': 'Operator: {operator}', 'align': 'left', 'style': 'normal', 'group': 7},
      {'text': 'PC: {pc_name}', 'align': 'left', 'style': 'normal', 'group': 7},
      {'text': 'Weighbridge: {weighbridge_name}', 'align': 'left', 'style': 'normal', 'group': 8},
      {'text': 'Port: {port_name}', 'align': 'left', 'style': 'normal', 'group': 8},
    ];
  }

  bool _isTemplateDefault(List<Map<String, dynamic>> current, List<Map<String, dynamic>> defaults) {
    if (current.length != defaults.length) return false;
    for (var i = 0; i < current.length; i++) {
      final c = current[i];
      final d = defaults[i];
      if (c['text'] != d['text'] || c['align'] != d['align'] ||
          c['style'] != d['style'] || c['size'] != d['size'] ||
          (c['group'] ?? 0) != (d['group'] ?? 0)) {
        return false;
      }
    }
    return true;
  }

  bool _isDmConfigDefault() {
    if (_dmMarginTop != 1 || _dmMarginBottom != 1 || _dmMarginLeft != 2) return false;
    if (_dmPageHeight == 4.0) {
      if (_dmLogo) return false;
    } else {
      if (!_dmLogo || _dmLogoWidth != 18 || _dmLogoHeight != 8) return false;
    }
    return true;
  }

  bool _isDmTemplateDefault() {
    return _isTemplateDefault(_dmLines, _getDefaultDmLines(columns: _dmColumns));
  }

  void _resetDmConfig() {
    _dmMarginTop = 1;
    _dmMarginBottom = 1;
    _dmMarginLeft = 2;
    if (_dmPageHeight == 6.0) {
      _dmLogo = true;
      _dmLogoWidth = 18;
      _dmLogoHeight = 8;
    } else {
      _dmLogo = false;
    }
  }

  void _resetDmTemplate() {
    _dmLines = _getDefaultDmLines(columns: _dmColumns);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadData(Map<String, dynamic> data) {
    if (_loaded) return;
    _loaded = true;

    // Printers
    final printers = data['printers'] as List<dynamic>?;
    if (printers != null) _printers = printers.map((p) => Map<String, dynamic>.from(p as Map)).toList();

    // Printer Assignment
    _grossPrinter = data['grossPrinter'] as String? ?? 'default';
    _grossTray = data['grossTray'] as String? ?? '';
    _tarePrinter = data['tarePrinter'] as String? ?? 'default';
    _tareTray = data['tareTray'] as String? ?? '';
    _backupPrinter = data['backupPrinter'] as String? ?? '';
    _backupTray = data['backupTray'] as String? ?? '';
    _backupEnabled = data['backupEnabled'] as bool? ?? false;
    _materialRoutingEnabled = data['materialRoutingEnabled'] as bool? ?? false;
    final matRules = data['materialPrinterRules'] as List<dynamic>?;
    if (matRules != null) _materialPrinterRules = matRules.map((r) => Map<String, dynamic>.from(r as Map)).toList();

    // Rules
    _copies = data['copies'] as int? ?? 2;
    _printOnGross = data['printOnGross'] as bool? ?? false;
    _printOnTare = data['printOnTare'] as bool? ?? true;
    _autoPrint = data['autoPrint'] as bool? ?? true;
    _reprintAllowed = data['reprintAllowed'] as bool? ?? true;
    _maxReprints = data['maxReprints'] as int? ?? 3;

    // Header Layout (normal printer only)
    _headerLayout = data['headerLayout'] as String? ?? 'inline';
    _headerRows = data['headerRows'] as int? ?? 3;

    // Per-template Logo
    _thermalLogoWidth = (data['thermalLogoWidth'] as num?)?.toDouble() ?? 30;
    _thermalLogoHeight = (data['thermalLogoHeight'] as num?)?.toDouble() ?? 30;
    _normalLogoWidth = (data['normalLogoWidth'] as num?)?.toDouble() ?? 80;
    _normalLogoHeight = (data['normalLogoHeight'] as num?)?.toDouble() ?? 80;

    // Multi-column
    _dmColumnCount = data['dmColumnCount'] as int? ?? 1;

    // Dot Matrix
    _dmPaperWidth = (data['dmPaperWidth'] as num?)?.toDouble() ?? 10.0;
    _dmPageHeight = (data['dmPageHeight'] as num?)?.toDouble() ?? 6.0;
    _dmMarginTop = data['dmMarginTop'] as int? ?? 1;
    _dmMarginBottom = data['dmMarginBottom'] as int? ?? 1;
    _dmMarginLeft = data['dmMarginLeft'] as int? ?? 1;
    _dmLogo = data['dmLogo'] as bool? ?? false;
    _dmLogoWidth = data['dmLogoWidth'] as int? ?? 18;
    _dmLogoHeight = data['dmLogoHeight'] as int? ?? 8;
    final dmLines = data['dmLines'] as List<dynamic>?;
    if (dmLines != null) _dmLines = dmLines.map((l) => Map<String, dynamic>.from(l as Map)).toList();

    // Thermal
    _thermalWidth = data['thermalWidth'] as String? ?? '80mm';
    _thermalLogo = data['thermalLogo'] as bool? ?? true;
    _thermalPdf417 = data['thermalPdf417'] as bool? ?? true;
    _thermalCutMode = data['thermalCutMode'] as String? ?? 'Full';
    _thermalFontSize = data['thermalFontSize'] as int? ?? 12;
    _thermalFont = data['thermalFont'] as String? ?? 'Font A';
    final tLines = data['thermalLines'] as List<dynamic>?;
    if (tLines != null) _thermalLines = tLines.map((l) => Map<String, dynamic>.from(l as Map)).toList();

    // Normal — per-size configs
    final loadedPaper = data['normalPaperSize'] as String? ?? 'A4';
    const validPapers = ['A4', 'A5', 'Letter', 'Legal'];
    _normalPaperSize = validPapers.contains(loadedPaper) ? loadedPaper : 'A4';

    final savedPerSize = data['perSizeConfigs'] as Map<String, dynamic>?;
    if (savedPerSize != null) {
      for (final entry in savedPerSize.entries) {
        _perSizeConfigs[entry.key] = Map<String, dynamic>.from(entry.value as Map);
      }
    }

    if (_perSizeConfigs.containsKey(_normalPaperSize)) {
      _applySizeConfig(_perSizeConfigs[_normalPaperSize]!);
    } else {
      // Legacy: load from flat keys
      _normalMarginTop = (data['normalMarginTop'] as num?)?.toDouble() ?? 15;
      _normalMarginBottom = (data['normalMarginBottom'] as num?)?.toDouble() ?? 15;
      _normalMarginLeft = (data['normalMarginLeft'] as num?)?.toDouble() ?? 15;
      _normalMarginRight = (data['normalMarginRight'] as num?)?.toDouble() ?? 15;
      _normalLogo = data['normalLogo'] as bool? ?? true;
      _normalLogoWidth = (data['normalLogoWidth'] as num?)?.toDouble() ?? 80;
      _normalLogoHeight = (data['normalLogoHeight'] as num?)?.toDouble() ?? 80;
      _normalPdf417 = data['normalPdf417'] as bool? ?? true;
      _normalPdf417Position = data['normalPdf417Position'] as String? ?? 'bottom';
      _normalCctv = data['normalCctv'] as bool? ?? false;
      final cctvCams = data['normalCctvCameras'] as List<dynamic>?;
      if (cctvCams != null) _normalCctvCameras = cctvCams.cast<String>();
      _normalFontSize = data['normalFontSize'] as int? ?? 14;
      _normalFont = data['normalFont'] as String? ?? 'Helvetica';
      final nLines = data['normalLines'] as List<dynamic>?;
      if (nLines != null) _normalLines = nLines.map((l) => Map<String, dynamic>.from(l as Map)).toList();
    }

    _loadPrinterTrays();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Map<String, dynamic> _buildPayload() => {
    'printers': _printers,
    'grossPrinter': _grossPrinter,
    'grossTray': _grossTray,
    'tarePrinter': _tarePrinter,
    'tareTray': _tareTray,
    'backupPrinter': _backupPrinter,
    'backupTray': _backupTray,
    'backupEnabled': _backupEnabled,
    'materialRoutingEnabled': _materialRoutingEnabled,
    'materialPrinterRules': _materialPrinterRules,
    'copies': _copies,
    'printOnGross': _printOnGross,
    'printOnTare': _printOnTare,
    'autoPrint': _autoPrint,
    'reprintAllowed': _reprintAllowed,
    'maxReprints': _maxReprints,
    'headerLayout': _headerLayout,
    'headerRows': _headerRows,
    'thermalLogoWidth': _thermalLogoWidth,
    'thermalLogoHeight': _thermalLogoHeight,
    'normalLogoWidth': _normalLogoWidth,
    'normalLogoHeight': _normalLogoHeight,
    'dmColumnCount': _dmColumnCount,
    'dmPaperWidth': _dmPaperWidth,
    'dmPageHeight': _dmPageHeight,
    'dmColumns': _dmColumns,
    'dmMarginTop': _dmMarginTop,
    'dmMarginBottom': _dmMarginBottom,
    'dmMarginLeft': _dmMarginLeft,
    'dmLogo': _dmLogo,
    'dmLogoLayout': 'stacked',
    'dmLogoWidth': _dmLogoWidth,
    'dmLogoHeight': _dmLogoHeight,
    'dmLines': _dmLines,
    'thermalWidth': _thermalWidth,
    'thermalLogo': _thermalLogo,
    'thermalPdf417': _thermalPdf417,
    'thermalCutMode': _thermalCutMode,
    'thermalFontSize': _thermalFontSize,
    'thermalFont': _thermalFont,
    'thermalLines': _thermalLines,
    'normalPaperSize': _normalPaperSize,
    'normalMarginTop': _normalMarginTop,
    'normalMarginBottom': _normalMarginBottom,
    'normalMarginLeft': _normalMarginLeft,
    'normalMarginRight': _normalMarginRight,
    'normalLogo': _normalLogo,
    'normalPdf417': _normalPdf417,
    'normalPdf417Position': _normalPdf417Position,
    'normalCctv': _normalCctv,
    'normalCctvCameras': _normalCctvCameras,
    'normalFontSize': _normalFontSize,
    'normalFont': _normalFont,
    'normalLines': _normalLines,
    'perSizeConfigs': {
      ..._perSizeConfigs,
      _normalPaperSize: _getCurrentSizeConfig(),
    },
  };

  Future<void> _save() async {
    if (_materialRoutingEnabled && _materialPrinterRules.isEmpty) {
      setState(() => _materialRoutingEnabled = false);
    }
    setState(() => _saving = true);
    try {
      final payload = _buildPayload();

      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
      final dir = Directory('$home/.weighbridge');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      await File('${dir.path}/printing_config.json').writeAsString(jsonEncode(payload));

      final db = ref.read(firestoreProvider);
      await db.collection('settings').doc('printing').set({
        ...payload,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      ref.invalidate(_printSettingsProvider);
      ref.read(auditServiceProvider).log(event: 'settingChange', description: 'Printing settings updated');

      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Print settings saved')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testPrint(String type) async {
    try {
      // Save current settings first so print service reads latest config
      await _save();
      final printService = ref.read(printServiceProvider);
      final result = await printService.testPrint(type: type);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.success ? 'Test print sent' : 'Print failed: ${result.error}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: $e')),
        );
      }
    }
  }


  Widget _logoPreview(double width, double height, ColorScheme scheme) {
    final logoAsync = ref.watch(_companyLogoProvider);
    final bytes = logoAsync.valueOrNull;
    if (bytes != null) {
      return Image.memory(bytes, width: width, height: height, fit: BoxFit.contain);
    }
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
      child: Icon(Icons.image_rounded, size: (width * 0.3).clamp(6, 14), color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
    );
  }

  Map<String, String> _previewPlaceholders() {
    final company = ref.read(_companyInfoProvider).valueOrNull ?? {};
    final tf = ref.read(timeFormatProvider);
    final timeFmt = getTimeFormatter(tf);
    final now = DateTime.now();
    final grossTime = now.subtract(const Duration(hours: 2, minutes: 27));
    final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    return {
      '{company_name}': company['companyName'] as String? ?? 'Your Company Name',
      '{company_address1}': company['address1'] as String? ?? 'Address Line 1',
      '{company_address2}': company['address2'] as String? ?? 'Address Line 2',
      '{company_phone}': company['phone'] as String? ?? '+91 98765 43210',
      '{company_gstin}': company['gstin'] as String? ?? '22AAAAA0000A1Z5',
      '{customer_name}': 'Sample Customer',
      '{customer_address}': 'Customer Address',
      '{customer_phone}': '+91 91234 56789',
      '{vehicle}': 'MH-12-AB-1234',
      '{material}': 'Iron Ore',
      '{gross}': '48,520',
      '{tare}': '16,200',
      '{net}': '32,320',
      '{gross_datetime}': '$dateStr ${timeFmt.format(grossTime)}',
      '{tare_datetime}': '$dateStr ${timeFmt.format(now)}',
      '{net_datetime}': '$dateStr ${timeFmt.format(now)}',
      '{rst}': '1042',
      '{operator}': 'Rajesh Kumar',
      '{date}': dateStr,
      '{pc_name}': Platform.localHostname,
      '{port_name}': ref.read(scaleConfigProvider).valueOrNull?.port ?? '',
      '{weighbridge_name}': company['weighbridgeName'] as String? ?? 'Weighbridge',
    };
  }

  String _substituteLine(String text) {
    var result = text;
    final placeholders = _previewPlaceholders();
    // Pad weight values to align KG
    final grossLen = placeholders['{gross}']!.length;
    final tareLen = placeholders['{tare}']!.length;
    final netLen = placeholders['{net}']!.length;
    final maxW = [grossLen, tareLen, netLen].reduce((a, b) => a > b ? a : b);
    final padded = Map<String, String>.from(placeholders);
    padded['{gross}'] = placeholders['{gross}']!.padLeft(maxW);
    padded['{tare}'] = placeholders['{tare}']!.padLeft(maxW);
    padded['{net}'] = placeholders['{net}']!.padLeft(maxW);
    for (final entry in padded.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final settingsAsync = ref.watch(_printSettingsProvider);
    ref.watch(_companyInfoProvider);
    settingsAsync.whenData(_loadData);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Column(
        children: [
          _buildHeader(scheme, text),
          Expanded(
            child: settingsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) => Column(
                children: [
                  // Print Rules — always visible
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.15))),
                    ),
                    child: _buildPrintRulesBar(scheme, text),
                  ),
                  // Printer Assignment bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.15))),
                    ),
                    child: _buildPrinterAssignmentBar(scheme, text),
                  ),
                  // Tabs
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      labelStyle: text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                      unselectedLabelStyle: text.labelMedium,
                      indicatorSize: TabBarIndicatorSize.label,
                      tabs: const [
                        Tab(text: 'Dot Matrix'),
                        Tab(text: 'Thermal'),
                        Tab(text: 'Page Printer'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildDotMatrixTab(scheme, text),
                        _buildThermalTab(scheme, text),
                        _buildNormalTab(scheme, text),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Header
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader(ColorScheme scheme, TextTheme text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: BoxDecoration(color: scheme.surface, border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2)))),
      child: Row(
        children: [
          IconButton(onPressed: () => context.go('/settings'), icon: const Icon(Icons.arrow_back_rounded, size: 20), style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(width: 12),
          Icon(Icons.print_rounded, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Printing', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text('Docket layout and printers', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          const Spacer(),
          if (_dirty) ...[
            TextButton(onPressed: () { setState(() { _loaded = false; _dirty = false; }); ref.invalidate(_printSettingsProvider); }, child: const Text('Discard')),
            const SizedBox(width: 8),
          ],
          if (_normalOverflows)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text('Content exceeds page', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
            ),
          FilledButton.icon(
            onPressed: _dirty && !_saving && !_normalOverflows ? _save : null,
            icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded, size: 16),
            label: Text(_saving ? 'Saving...' : 'Save'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DOT MATRIX TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDotMatrixTab(ColorScheme scheme, TextTheme text) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 320,
            child: Column(
              children: [
                _Section(scheme: scheme, icon: Icons.grid_on_rounded, title: 'Dot Matrix Configuration', children: [
                  Text('Paper Width', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _dmPaperWidth,
                          min: 8.0,
                          max: 13.2,
                          divisions: 26,
                          label: '${_dmPaperWidth.toStringAsFixed(1)}″',
                          onChanged: (v) { setState(() { _dmPaperWidth = double.parse(v.toStringAsFixed(1)); _syncTemplateToPrinters('dotMatrix', paperWidth: _dmPaperWidth); }); _markDirty(); },
                        ),
                      ),
                      SizedBox(
                        width: 90,
                        child: Text('${_dmPaperWidth.toStringAsFixed(1)}″ · $_dmColumns col', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildDropdownRow('Cut Length', '${_dmPageHeight.toStringAsFixed(0)}″', ['4″', '6″'], (v) { setState(() { _dmPageHeight = double.parse(v!.replaceAll('″', '')); _dmLogo = _dmPageHeight == 6.0; }); _markDirty(); }, text),
                  const SizedBox(height: 10),
                  const SizedBox(height: 10),
                  _SwitchRow(label: 'Logo (Monochrome)', value: _dmLogo, onChanged: (v) { setState(() { _dmLogo = v; }); _markDirty(); }),
                  if (_dmLogo) ...[
                    const SizedBox(height: 8),
                    Text('Logo Size (chars × lines)', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(child: _buildNumberInput('W', _dmLogoWidth, (v) { setState(() => _dmLogoWidth = v); _markDirty(); }, text)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildNumberInput('H', _dmLogoHeight, (v) { setState(() => _dmLogoHeight = v); _markDirty(); }, text)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('PNG → 1-bit dithered. Best for line-art logos.', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
                  ],
                  const SizedBox(height: 10),
                  Text('Margins (lines)', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: _buildNumberInput('Top', _dmMarginTop, (v) { _dmMarginTop = v; _markDirty(); }, text)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildNumberInput('Bottom', _dmMarginBottom, (v) { _dmMarginBottom = v; _markDirty(); }, text)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildNumberInput('L & R', _dmMarginLeft, (v) { _dmMarginLeft = v; _markDirty(); }, text)),
                    ],
                  ),
                  if (!_isDmConfigDefault()) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () { setState(_resetDmConfig); _markDirty(); },
                      icon: const Icon(Icons.settings_backup_restore_rounded, size: 14),
                      label: Text('Reset Config (${_dmPageHeight.toStringAsFixed(0)}″)'),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), foregroundColor: scheme.error),
                    ),
                  ],
                  const SizedBox(height: 10),
                ]),
                const SizedBox(height: 16),
                _buildPlaceholderReference(scheme, text),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [
                _Section(scheme: scheme, icon: Icons.edit_note_rounded, title: 'Template Lines', children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Assign same group (G1, G2…) to adjacent lines to column them together', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
                  ),
                  ..._dmLines.asMap().entries.map((e) => _DmLineEditor(
                    index: e.key,
                    line: e.value,
                    totalLines: _dmLines.length,
                    onChanged: (v) { setState(() => _dmLines[e.key] = v); _markDirty(); },
                    onRemove: () { setState(() => _dmLines.removeAt(e.key)); _markDirty(); },
                    onMoveUp: e.key > 0 ? () { setState(() { final item = _dmLines.removeAt(e.key); _dmLines.insert(e.key - 1, item); }); _markDirty(); } : null,
                    onMoveDown: e.key < _dmLines.length - 1 ? () { setState(() { final item = _dmLines.removeAt(e.key); _dmLines.insert(e.key + 1, item); }); _markDirty(); } : null,
                  )),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () { setState(() => _dmLines.add({'text': '', 'align': 'left', 'style': 'normal'})); _markDirty(); },
                        icon: const Icon(Icons.add_rounded, size: 14),
                        label: const Text('Add Line'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      ),
                      const SizedBox(width: 8),
                      if (!_isDmTemplateDefault())
                        TextButton.icon(
                          onPressed: () { setState(_resetDmTemplate); _markDirty(); },
                          icon: const Icon(Icons.restore_rounded, size: 14),
                          label: const Text('Reset Lines'),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), foregroundColor: scheme.error),
                        ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: () => _testPrint('dm'),
                        icon: const Icon(Icons.print_rounded, size: 14),
                        label: const Text('Test Print'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      ),
                    ],
                  ),
                ]),
                const SizedBox(height: 16),
                _Section(scheme: scheme, icon: Icons.preview_rounded, title: 'Live Preview  •  ${_dmPaperWidth.toStringAsFixed(1)}″ × ${_dmPageHeight.toStringAsFixed(0)}″  ($_dmColumns col)', children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const ppi = 100.0;
                      final boxWidth = _dmPaperWidth * ppi;
                      final boxHeight = _dmPageHeight * ppi;

                      return Center(
                        child: Column(
                          children: [
                            // Horizontal inch ruler
                            Padding(
                              padding: const EdgeInsets.only(left: 18),
                              child: SizedBox(
                                width: boxWidth,
                                height: 18,
                                child: CustomPaint(
                                  painter: _RulerPainter(
                                    totalInches: _dmPaperWidth,
                                    ppi: ppi,
                                    horizontal: true,
                                    color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Vertical inch ruler
                                SizedBox(
                                  width: 18,
                                  height: boxHeight,
                                  child: CustomPaint(
                                    painter: _RulerPainter(
                                      totalInches: _dmPageHeight,
                                      ppi: ppi,
                                      horizontal: false,
                                      color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ),
                                Container(
                                  width: boxWidth,
                                  height: boxHeight,
                                  clipBehavior: Clip.antiAlias,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFDE8),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: scheme.outlineVariant.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: _buildDmPreviewContent(boxWidth, scheme),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDmPreviewContent(double boxWidth, ColorScheme scheme) {
    const baseFontSize = 12.0;
    const baseStyle = TextStyle(fontFamily: 'Courier', fontSize: baseFontSize, height: 1.4, color: Color(0xFF1A1A1A));

    final dotData = _dmLogo ? ref.watch(_dmMonoLogoProvider).valueOrNull : null;
    final hMeasurer = TextPainter(
      text: const TextSpan(text: 'M', style: baseStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final lineH = hMeasurer.height;
    final charW = hMeasurer.width;
    int? actualLogoLines;
    if (dotData != null) {
      final logoW = _dmLogoWidth * charW;
      final logoScale = logoW / dotData.width;
      actualLogoLines = ((dotData.height * logoScale) / lineH).floor().clamp(1, 100);
    }
    final previewText = _generateDmPreview(hasRealLogo: dotData != null, actualLogoLines: actualLogoLines);

    // Separator spans full paper width (_dmColumns), so measure that
    final sepMeasurer = TextPainter(
      text: TextSpan(text: '-' * _dmColumns, style: baseStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final totalW = sepMeasurer.width;
    final marginPx = _dmMarginLeft * charW;
    final marginT = _dmMarginTop * lineH;

    final scale = boxWidth / totalW;
    return Transform.scale(
      scale: scale,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: totalW,
        height: totalW * 2,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(top: marginT),
              child: Text(previewText, softWrap: false, style: baseStyle),
            ),
            if (_dmLogo && dotData != null)
              Builder(builder: (_) {
                final logoW = _dmLogoWidth * charW;
                final logoScale = logoW / dotData.width;
                final logoH = dotData.height * logoScale;
                final usableW = totalW - 2 * marginPx;
                final leftOffset = marginPx + (usableW - logoW) / 2;
                return Positioned(
                  top: marginT,
                  left: leftOffset,
                  child: CustomPaint(
                    size: Size(logoW, logoH),
                    painter: _DmDotPainter(dotData),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  String _generateDmPreview({bool hasRealLogo = false, int? actualLogoLines}) {
    final buf = StringBuffer();
    final usableWidth = _dmColumns - _dmMarginLeft - _dmMarginLeft;
    final leftPad = ' ' * _dmMarginLeft;

    String formatLine(String content, String align, String style, int usable) {
      if (style == 'blank') return '';
      String formatted = content;
      if (style == 'bold') formatted = formatted.toUpperCase();
      if (style == 'double') formatted = '>> $formatted <<';
      if (formatted.length > usable) formatted = formatted.substring(0, usable);
      if (align == 'center' && formatted.length < usable) {
        final pad = ((usable - formatted.length) / 2).floor();
        formatted = '${' ' * pad}$formatted';
      } else if (align == 'right' && formatted.length < usable) {
        formatted = formatted.padLeft(usable);
      }
      return formatted;
    }

    var i = 0;
    if (_dmLogo) {
      final logoW = _dmLogoWidth.clamp(6, usableWidth ~/ 2);
      final logoH = (hasRealLogo && actualLogoLines != null) ? actualLogoLines : _dmLogoHeight.clamp(2, 20);
      if (hasRealLogo) {
        for (var row = 0; row < logoH; row++) {
          buf.writeln();
        }
      } else {
        for (var row = 0; row < logoH; row++) {
          if (row == 0 || row == logoH - 1) {
            final line = '+${'-' * (logoW - 2)}+';
            final pad = ((usableWidth - line.length) / 2).floor().clamp(0, usableWidth);
            buf.writeln('$leftPad${' ' * pad}$line');
          } else if (row == logoH ~/ 2) {
            final line = '|${'LOGO'.padLeft((logoW - 2 + 4) ~/ 2).padRight(logoW - 2)}|';
            final pad = ((usableWidth - line.length) / 2).floor().clamp(0, usableWidth);
            buf.writeln('$leftPad${' ' * pad}$line');
          } else {
            final line = '|${' ' * (logoW - 2)}|';
            final pad = ((usableWidth - line.length) / 2).floor().clamp(0, usableWidth);
            buf.writeln('$leftPad${' ' * pad}$line');
          }
        }
      }
    }
    while (i < _dmLines.length) {
      final line = _dmLines[i];
      final group = line['group'] as int? ?? 0;
      final style = line['style'] as String? ?? 'normal';

      if (style == 'separator') {
        buf.writeln('-' * _dmColumns);
        i++;
      } else if (group > 0) {
        final groupLines = <Map<String, dynamic>>[];
        while (i < _dmLines.length && (_dmLines[i]['group'] as int? ?? 0) == group) {
          groupLines.add(_dmLines[i]);
          i++;
        }
        final groupColCount = groupLines.length.clamp(1, 3);
        final colWidth = usableWidth ~/ groupColCount;
        final rowBuf = StringBuffer(leftPad);
        for (var c = 0; c < groupColCount; c++) {
          final gl = groupLines[c];
          final content = _substituteLine(gl['text'] as String? ?? '');
          final align = gl['align'] as String? ?? 'left';
          final gStyle = gl['style'] as String? ?? 'normal';
          rowBuf.write(formatLine(content, align, gStyle, colWidth).padRight(colWidth));
        }
        buf.writeln(rowBuf.toString());
      } else {
        final content = _substituteLine(line['text'] as String? ?? '');
        final align = line['align'] as String? ?? 'left';
        buf.writeln('$leftPad${formatLine(content, align, style, usableWidth)}');
        i++;
      }
    }
    return buf.toString();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // THERMAL TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildThermalTab(ColorScheme scheme, TextTheme text) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 340,
            child: Column(
              children: [
                _Section(scheme: scheme, icon: Icons.receipt_long_rounded, title: 'Thermal Configuration', children: [
                  _buildDropdownRow('Paper Width', _thermalWidth, ['58mm', '80mm'], (v) { setState(() { _thermalWidth = v!; _syncTemplateToPrinters('thermal', thermalWidth: _thermalWidth); }); _markDirty(); }, text),
                  const SizedBox(height: 10),
                  _SwitchRow(label: 'Include Logo', value: _thermalLogo, onChanged: (v) { setState(() => _thermalLogo = v); _markDirty(); }),
                  if (_thermalLogo) ...[
                    const SizedBox(height: 8),
                    Text('Logo Size (mm)', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(child: _buildDoubleInput('W', _thermalLogoWidth, (v) { setState(() => _thermalLogoWidth = v); _markDirty(); }, text)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildDoubleInput('H', _thermalLogoHeight, (v) { setState(() => _thermalLogoHeight = v); _markDirty(); }, text)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  _SwitchRow(label: 'PDF417 Barcode', value: _thermalPdf417, onChanged: (v) { setState(() => _thermalPdf417 = v); _markDirty(); }),
                  if (_thermalPdf417)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Encodes all weighment placeholders automatically', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
                    ),
                  const SizedBox(height: 10),
                  _buildDropdownRow('Font', _thermalFont, ['Font A', 'Font B', 'Font C'], (v) { setState(() => _thermalFont = v!); _markDirty(); }, text),
                  const SizedBox(height: 10),
                  _buildDropdownRow('Font Size', '${_thermalFontSize}pt', ['6pt', '7pt', '8pt', '10pt', '12pt', '14pt', '16pt'], (v) { setState(() => _thermalFontSize = int.parse(v!.replaceAll('pt', ''))); _markDirty(); }, text),
                  const SizedBox(height: 10),
                  _buildDropdownRow('Cut Mode', _thermalCutMode, ['Full', 'Partial', 'None'], (v) { setState(() => _thermalCutMode = v!); _markDirty(); }, text),
                  if (!_thermalLogo || !_thermalPdf417 || _thermalCutMode != 'Full' || _thermalFontSize != 12 || _thermalFont != 'Font A') ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () { setState(() { _thermalLogo = true; _thermalPdf417 = true; _thermalCutMode = 'Full'; _thermalFontSize = 12; _thermalFont = 'Font A'; }); _markDirty(); },
                      icon: const Icon(Icons.settings_backup_restore_rounded, size: 14),
                      label: Text('Reset Config ($_thermalWidth)'),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), foregroundColor: scheme.error),
                    ),
                  ],
                ]),
                const SizedBox(height: 16),
                _buildPlaceholderReference(scheme, text),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [
                _Section(scheme: scheme, icon: Icons.edit_note_rounded, title: 'Template Lines', children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Assign same group (G1, G2…) to adjacent lines to column them together', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
                  ),
                  ..._thermalLines.asMap().entries.map((e) => _ThermalLineEditor(
                    index: e.key,
                    line: e.value,
                    onChanged: (updated) { setState(() => _thermalLines[e.key] = updated); _markDirty(); },
                    onRemove: () { setState(() => _thermalLines.removeAt(e.key)); _markDirty(); },
                    onMoveUp: e.key > 0 ? () { setState(() { final item = _thermalLines.removeAt(e.key); _thermalLines.insert(e.key - 1, item); }); _markDirty(); } : null,
                    onMoveDown: e.key < _thermalLines.length - 1 ? () { setState(() { final item = _thermalLines.removeAt(e.key); _thermalLines.insert(e.key + 1, item); }); _markDirty(); } : null,
                  )),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () { setState(() => _thermalLines.add({'text': '', 'align': 'left', 'size': 'normal'})); _markDirty(); },
                        icon: const Icon(Icons.add_rounded, size: 14),
                        label: const Text('Add Line'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      ),
                      const SizedBox(width: 8),
                      if (!_isTemplateDefault(_thermalLines, _getDefaultThermalLines()))
                        TextButton.icon(
                          onPressed: () { setState(() => _thermalLines = _getDefaultThermalLines()); _markDirty(); },
                          icon: const Icon(Icons.restore_rounded, size: 14),
                          label: const Text('Reset Lines'),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), foregroundColor: scheme.error),
                        ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: () => _testPrint('thermal'),
                        icon: const Icon(Icons.print_rounded, size: 14),
                        label: const Text('Test Print'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      ),
                    ],
                  ),
                ]),
                const SizedBox(height: 16),
                _Section(scheme: scheme, icon: Icons.preview_rounded, title: 'Thermal Preview', children: [
                  GestureDetector(
                    onTap: () => _showEnlargedThermalPreview(scheme, text),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.zoomIn,
                      child: Stack(
                        children: [
                          _buildThermalPreview(scheme, text),
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(color: scheme.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(4)),
                              child: Icon(Icons.zoom_in_rounded, size: 14, color: scheme.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThermalPreview(ColorScheme scheme, TextTheme text, {bool enlarged = false}) {
    final scale = enlarged ? 1.8 : 1.0;
    final previewWidth = (_thermalWidth == '58mm' ? 220.0 : 300.0) * scale;

    return Container(
      width: previewWidth,
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_thermalLogo)
            Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 6 * scale),
                child: _logoPreview(_thermalLogoWidth * 0.5 * scale, _thermalLogoHeight * 0.5 * scale, scheme),
              ),
            ),
          ..._buildThermalLinesGrouped(text, scale: scale),
          if (_thermalPdf417) ...[
            SizedBox(height: 6 * scale),
            _buildPdf417Preview(scale, lines: _thermalLines),
          ],
        ],
      ),
    );
  }

  void _showEnlargedThermalPreview(ColorScheme scheme, TextTheme text) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(40),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 30, offset: const Offset(0, 10))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                child: Row(
                  children: [
                    Icon(Icons.receipt_long_rounded, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text('Thermal Preview (Enlarged)', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, size: 20)),
                  ],
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SingleChildScrollView(
                    child: Center(child: _buildThermalPreview(scheme, text, enlarged: true)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildThermalLinesGrouped(TextTheme text, {double scale = 1.0}) {
    final widgets = <Widget>[];
    var i = 0;
    while (i < _thermalLines.length) {
      final line = _thermalLines[i];
      final group = line['group'] as int? ?? 0;
      if (group > 0) {
        final groupLines = <Map<String, dynamic>>[];
        while (i < _thermalLines.length && (_thermalLines[i]['group'] as int? ?? 0) == group) {
          groupLines.add(_thermalLines[i]);
          i++;
        }
        widgets.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: groupLines.map((gl) => Expanded(child: _buildThermalPreviewLine(gl, text, scale: scale))).toList(),
        ));
      } else {
        widgets.add(_buildThermalPreviewLine(line, text, scale: scale));
        i++;
      }
    }
    return widgets;
  }

  Widget _buildThermalPreviewLine(Map<String, dynamic> line, TextTheme text, {double scale = 1.0}) {
    final content = _substituteLine(line['text'] as String? ?? '');
    final align = line['align'] as String? ?? 'left';
    final size = line['size'] as String? ?? 'normal';

    if (size == 'separator') {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 4 * scale),
        child: Divider(height: 1 * scale, thickness: 1, color: const Color(0xFF666666)),
      );
    }

    TextAlign ta;
    switch (align) {
      case 'center': ta = TextAlign.center; break;
      case 'right': ta = TextAlign.right; break;
      default: ta = TextAlign.left;
    }

    final baseSize = _thermalFontSize * 0.85 * scale;
    double fontSize;
    FontWeight fw;
    switch (size) {
      case 'bold': fontSize = baseSize; fw = FontWeight.w700; break;
      case 'double': fontSize = baseSize * 1.3; fw = FontWeight.w800; break;
      default: fontSize = baseSize; fw = FontWeight.w400;
    }

    String fontFamily;
    switch (_thermalFont) {
      case 'Font B': fontFamily = 'Courier New'; break;
      case 'Font C': fontFamily = 'Courier'; break;
      default: fontFamily = 'monospace';
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 1 * scale),
      child: Text(content, textAlign: ta, style: TextStyle(fontFamily: fontFamily, fontSize: fontSize, fontWeight: fw, color: const Color(0xFF1A1A1A))),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NORMAL PRINTER TAB
  Widget _buildPdf417Preview(double scale, {List<Map<String, dynamic>>? lines}) {
    final placeholders = _previewPlaceholders();
    final templateLines = lines ?? _normalLines;
    final usedKeys = <String>{};
    final pattern = RegExp(r'\{[^}]+\}');
    for (final line in templateLines) {
      final text = line['text'] as String? ?? '';
      for (final match in pattern.allMatches(text)) {
        usedKeys.add(match.group(0)!);
      }
    }
    final parts = <String>[];
    for (final key in usedKeys) {
      final val = placeholders[key]?.trim() ?? '';
      if (val.isNotEmpty) {
        parts.add('${key.replaceAll(RegExp(r'[{}]'), '')}=$val');
      }
    }
    parts.add('EOF=1');
    final data = parts.join('|');

    final bc = Barcode.pdf417();
    const renderW = 300.0;
    final renderH = 80 * 0.30 * scale;
    final elements = bc.make(data, width: renderW, height: renderH);

    return SizedBox(
      width: double.infinity,
      height: renderH,
      child: CustomPaint(
        painter: _Pdf417Painter(elements.toList(), renderW, renderH),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildNormalTab(ColorScheme scheme, TextTheme text) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 340,
            child: Column(
              children: [
                _Section(scheme: scheme, icon: Icons.description_rounded, title: 'Page Setup', children: [
                  _buildDropdownRow('Paper Size', _normalPaperSize, ['A4', 'A5', 'Letter', 'Legal'], (v) { setState(() => _switchPaperSize(v!)); _markDirty(); }, text),
                  const SizedBox(height: 10),
                  Text('Margins (mm)', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildDoubleInput('T', _normalMarginTop, (v) { _normalMarginTop = v; _markDirty(); }, text)),
                      const SizedBox(width: 6),
                      Expanded(child: _buildDoubleInput('B', _normalMarginBottom, (v) { _normalMarginBottom = v; _markDirty(); }, text)),
                      const SizedBox(width: 6),
                      Expanded(child: _buildDoubleInput('L', _normalMarginLeft, (v) { _normalMarginLeft = v; _markDirty(); }, text)),
                      const SizedBox(width: 6),
                      Expanded(child: _buildDoubleInput('R', _normalMarginRight, (v) { _normalMarginRight = v; _markDirty(); }, text)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildDropdownRow('Font', _normalFont, ['Helvetica', 'Times', 'Courier', 'Roboto', 'Open Sans'], (v) { setState(() => _normalFont = v!); _markDirty(); }, text),
                  const SizedBox(height: 10),
                  _buildDropdownRow('Font Size', '${_normalFontSize}pt', ['6pt', '7pt', '8pt', '9pt', '10pt', '11pt', '12pt', '14pt', '16pt', '18pt'], (v) { setState(() => _normalFontSize = int.parse(v!.replaceAll('pt', ''))); _markDirty(); }, text),
                  const SizedBox(height: 10),
                  _buildDropdownRow('Header Layout', _headerLayout, ['stacked', 'inline'], (v) { setState(() => _headerLayout = v!); _markDirty(); }, text),
                  if (_headerLayout == 'inline' && _normalLogo) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text('Header Rows', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        _CounterButton(value: _headerRows, min: 1, max: 10, onChanged: (v) { setState(() => _headerRows = v); _markDirty(); }),
                      ],
                    ),
                  ],
                ]),
                const SizedBox(height: 16),
                _Section(scheme: scheme, icon: Icons.image_rounded, title: 'Content Options', children: [
                  _SwitchRow(label: 'Company Logo', value: _normalLogo, onChanged: (v) { setState(() => _normalLogo = v); _markDirty(); }),
                  if (_normalLogo) ...[
                    const SizedBox(height: 8),
                    Text('Logo Size (mm)', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(child: _buildDoubleInput('W', _normalLogoWidth, (v) { setState(() => _normalLogoWidth = v); _markDirty(); }, text)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildDoubleInput('H', _normalLogoHeight, (v) { setState(() => _normalLogoHeight = v); _markDirty(); }, text)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  _SwitchRow(label: 'PDF417 Barcode', value: _normalPdf417, onChanged: (v) { setState(() => _normalPdf417 = v); _markDirty(); }),
                  if (_normalPdf417) ...[
                    const SizedBox(height: 6),
                    _buildDropdownRow('Position', _normalPdf417Position, ['bottom', 'afterText'], (v) { setState(() => _normalPdf417Position = v!); _markDirty(); }, text),
                  ],
                  const SizedBox(height: 8),
                  _SwitchRow(label: 'CCTV Snapshots', value: _normalCctv, onChanged: (v) { setState(() => _normalCctv = v); _markDirty(); }),
                  if (_normalCctv) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: (_normalPaperSize == 'Legal'
                          ? ['Front', 'Rear', 'Top', 'Side', 'Operator', 'Customer']
                          : ['Front', 'Rear', 'Top', 'Side']
                      ).map((cam) {
                        final selected = _normalCctvCameras.contains(cam);
                        return FilterChip(
                          label: Text(cam),
                          selected: selected,
                          onSelected: (v) {
                            setState(() {
                              if (v) { _normalCctvCameras.add(cam); } else { _normalCctvCameras.remove(cam); }
                            });
                            _markDirty();
                          },
                          labelStyle: text.labelSmall,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (!_normalLogo || !_normalPdf417 || _normalFontSize != (_getDefaultSizeConfig(_normalPaperSize)['fontSize'] as int) || _normalFont != 'Helvetica') ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () { setState(() { final def = _getDefaultSizeConfig(_normalPaperSize); _normalLogo = true; _normalPdf417 = true; _normalFontSize = def['fontSize'] as int; _normalFont = 'Helvetica'; }); _markDirty(); },
                      icon: const Icon(Icons.settings_backup_restore_rounded, size: 14),
                      label: Text('Reset Config ($_normalPaperSize)'),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), foregroundColor: scheme.error),
                    ),
                  ],
                ]),
                const SizedBox(height: 16),
                _buildPlaceholderReference(scheme, text),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [
                _Section(scheme: scheme, icon: Icons.edit_note_rounded, title: 'Template Lines', children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Assign same group to adjacent lines to column them together', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
                  ),
                  ..._normalLines.asMap().entries.map((e) => _DmLineEditor(
                    index: e.key,
                    line: e.value,
                    totalLines: _normalLines.length,
                    onChanged: (v) { setState(() => _normalLines[e.key] = v); _markDirty(); },
                    onRemove: () { setState(() => _normalLines.removeAt(e.key)); _markDirty(); },
                    onMoveUp: e.key > 0 ? () { setState(() { final item = _normalLines.removeAt(e.key); _normalLines.insert(e.key - 1, item); }); _markDirty(); } : null,
                    onMoveDown: e.key < _normalLines.length - 1 ? () { setState(() { final item = _normalLines.removeAt(e.key); _normalLines.insert(e.key + 1, item); }); _markDirty(); } : null,
                  )),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () { setState(() => _normalLines.add({'text': '', 'align': 'left', 'style': 'normal'})); _markDirty(); },
                        icon: const Icon(Icons.add_rounded, size: 14),
                        label: const Text('Add Line'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      ),
                      const SizedBox(width: 8),
                      if (!_isTemplateDefault(_normalLines, _getDefaultNormalLines(paperSize: _normalPaperSize)))
                        TextButton.icon(
                          onPressed: () { setState(() => _normalLines = _getDefaultNormalLines(paperSize: _normalPaperSize)); _markDirty(); },
                          icon: const Icon(Icons.restore_rounded, size: 14),
                          label: const Text('Reset Lines'),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), foregroundColor: scheme.error),
                        ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: () => _testPrint('normal'),
                        icon: const Icon(Icons.print_rounded, size: 14),
                        label: const Text('Test Print'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      ),
                    ],
                  ),
                ]),
                const SizedBox(height: 16),
                _Section(scheme: scheme, icon: Icons.preview_rounded, title: 'Page Preview', children: [
                  GestureDetector(
                    onTap: () => _showEnlargedPreview(scheme, text),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.zoomIn,
                      child: Stack(
                        children: [
                          _buildNormalPreview(scheme, text),
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(color: scheme.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(4)),
                              child: Icon(Icons.zoom_in_rounded, size: 14, color: scheme.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Normal Printer Preview
  // ═══════════════════════════════════════════════════════════════════════════

  void _showEnlargedPreview(ColorScheme scheme, TextTheme text) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(40),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 900),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 30, offset: const Offset(0, 10))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                child: Row(
                  children: [
                    Icon(Icons.preview_rounded, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text('Page Preview (Enlarged)', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, size: 20)),
                  ],
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: _buildNormalPreview(scheme, text, enlarged: true)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNormalPreview(ColorScheme scheme, TextTheme text, {bool enlarged = false}) {
    double paperW, paperH;
    switch (_normalPaperSize) {
      case 'A5': paperW = 148; paperH = 210; break;
      case 'Letter': paperW = 216; paperH = 279; break;
      case 'Legal': paperW = 216; paperH = 356; break;
      default: paperW = 210; paperH = 297;
    }

    final previewW = enlarged ? 500.0 : 280.0;
    final aspectRatio = paperW / paperH;
    final previewH = previewW / aspectRatio;
    final scale = previewW / paperW;
    final fontScale = scale;

    final contentWidgets = <Widget>[];

    // Logo (stacked: logo above lines)
    if (_normalLogo && _headerLayout == 'stacked') {
      contentWidgets.add(Center(
        child: Padding(
          padding: EdgeInsets.only(bottom: 1.5 * scale),
          child: _logoPreview(_normalLogoWidth * 0.4 * scale, _normalLogoHeight * 0.4 * scale, scheme),
        ),
      ));
    }

    // When inline: collect first N lines for the header block beside logo
    int inlineHeaderConsumed = 0;
    if (_normalLogo && _headerLayout == 'inline') {
      final headerLineWidgets = <Widget>[];
      var hi = 0;
      var rowsConsumed = 0;
      while (hi < _normalLines.length && rowsConsumed < _headerRows) {
        final hLine = _normalLines[hi];
        final hGroup = hLine['group'] as int? ?? 0;
        if (hGroup > 0) {
          final gLines = <Map<String, dynamic>>[];
          final gStart = hi;
          while (hi < _normalLines.length && (_normalLines[hi]['group'] as int? ?? 0) == hGroup) {
            gLines.add(_normalLines[hi]);
            hi++;
          }
          headerLineWidgets.add(Padding(
            padding: EdgeInsets.symmetric(vertical: 0.3 * scale),
            child: Row(children: gLines.asMap().entries.map((gl) => Expanded(child: _buildNormalPreviewLine(gl.value, fontScale, scheme, lineIndex: gStart + gl.key))).toList()),
          ));
        } else {
          final hStyle = hLine['style'] as String? ?? 'normal';
          if (hStyle == 'blank') {
            headerLineWidgets.add(SizedBox(height: 3 * scale));
          } else {
            headerLineWidgets.add(Padding(
              padding: EdgeInsets.symmetric(vertical: 0.3 * scale),
              child: _buildNormalPreviewLine(hLine, fontScale, scheme, lineIndex: hi),
            ));
          }
          hi++;
        }
        rowsConsumed++;
      }
      inlineHeaderConsumed = hi;
      contentWidgets.add(Padding(
        padding: EdgeInsets.only(bottom: 1.5 * scale),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.only(right: 6 * scale),
              child: _logoPreview(_normalLogoWidth * 0.4 * scale, _normalLogoHeight * 0.4 * scale, scheme),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: headerLineWidgets,
              ),
            ),
          ],
        ),
      ));
    }

    // Render remaining lines — same grouping logic as DM
    var i = inlineHeaderConsumed;
    while (i < _normalLines.length) {
      final line = _normalLines[i];
      final group = line['group'] as int? ?? 0;

      if (group > 0) {
        final groupLines = <Map<String, dynamic>>[];
        final groupStartIdx = i;
        while (i < _normalLines.length && (_normalLines[i]['group'] as int? ?? 0) == group) {
          groupLines.add(_normalLines[i]);
          i++;
        }
        contentWidgets.add(Padding(
          padding: EdgeInsets.symmetric(vertical: 0.3 * scale),
          child: Row(
            children: groupLines.asMap().entries.map((gl) {
              return Expanded(child: _buildNormalPreviewLine(gl.value, fontScale, scheme, lineIndex: groupStartIdx + gl.key));
            }).toList(),
          ),
        ));
      } else {
        final style = line['style'] as String? ?? 'normal';
        if (style == 'blank') {
          contentWidgets.add(SizedBox(height: 3 * scale));
        } else {
          contentWidgets.add(Padding(
            padding: EdgeInsets.symmetric(vertical: 0.3 * scale),
            child: _buildNormalPreviewLine(line, fontScale, scheme, lineIndex: i),
          ));
        }
        i++;
      }
    }

    // PDF417 after text
    if (_normalPdf417 && _normalPdf417Position == 'afterText') {
      contentWidgets.add(Padding(
        padding: EdgeInsets.only(top: 4 * scale),
        child: _buildPdf417Preview(fontScale),
      ));
    }

    // CCTV snapshots
    if (_normalCctv && _normalCctvCameras.isNotEmpty) {
      final maxCams = _normalPaperSize == 'Legal' ? 6 : 4;
      final cameras = _normalCctvCameras.take(maxCams).toList();
      contentWidgets.add(SizedBox(height: 4 * scale));
      contentWidgets.add(Divider(height: 1, thickness: 0.5 * scale, color: scheme.outlineVariant.withValues(alpha: 0.4)));
      contentWidgets.add(SizedBox(height: 2 * scale));
      for (var ci = 0; ci < cameras.length; ci += 2) {
        final rowCams = cameras.sublist(ci, (ci + 2).clamp(0, cameras.length));
        contentWidgets.add(Padding(
          padding: EdgeInsets.only(bottom: 3 * scale),
          child: Row(
            children: rowCams.map((cam) => Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(2), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3))),
                    child: Center(child: Text(cam, style: TextStyle(fontSize: 5 * fontScale, color: scheme.onSurfaceVariant))),
                  ),
                ),
              ),
            )).toList(),
          ),
        ));
      }
    }

    if (_normalPdf417 && _normalPdf417Position == 'bottom') {
      contentWidgets.add(Padding(
        padding: EdgeInsets.only(top: 1.5 * scale),
        child: _buildPdf417Preview(fontScale),
      ));
    }

    final marginScale = previewW / paperW;

    return _NormalPreviewContainer(
      width: previewW,
      height: previewH,
      padding: EdgeInsets.fromLTRB(
        _normalMarginLeft * marginScale,
        _normalMarginTop * marginScale,
        _normalMarginRight * marginScale,
        _normalMarginBottom * marginScale,
      ),
      scheme: scheme,
      children: contentWidgets,
      onOverflowChanged: (v) {
        if (v != _normalOverflows) setState(() => _normalOverflows = v);
      },
    );
  }

  Widget _buildNormalPreviewLine(Map<String, dynamic> line, double fontScale, ColorScheme scheme, {int lineIndex = -1}) {
    final content = _substituteLine(line['text'] as String? ?? '');
    final align = line['align'] as String? ?? 'left';
    final style = line['style'] as String? ?? 'normal';

    TextAlign ta;
    switch (align) {
      case 'center': ta = TextAlign.center; break;
      case 'right': ta = TextAlign.right; break;
      default: ta = TextAlign.left;
    }

    final baseFontSize = _normalFontSize * 0.30 * fontScale;
    double fontSize;
    FontWeight fw;
    if (lineIndex == 0) {
      fontSize = baseFontSize + (4 * 0.30 * fontScale);
      fw = FontWeight.w800;
    } else if (lineIndex > 0 && lineIndex <= 2) {
      fontSize = baseFontSize + (2 * 0.30 * fontScale);
      fw = FontWeight.w600;
    } else {
      switch (style) {
        case 'bold': fontSize = baseFontSize + (1 * 0.30 * fontScale); fw = FontWeight.w700; break;
        case 'double': fontSize = baseFontSize + (2 * 0.30 * fontScale); fw = FontWeight.w800; break;
        default: fontSize = baseFontSize; fw = FontWeight.w400;
      }
    }

    String? fontFamily;
    switch (_normalFont) {
      case 'Times': fontFamily = 'Times New Roman'; break;
      case 'Courier': fontFamily = 'Courier New'; break;
      case 'Roboto': fontFamily = 'Roboto'; break;
      case 'Open Sans': fontFamily = 'Open Sans'; break;
      default: fontFamily = 'Helvetica';
    }

    return Text(content, textAlign: ta, style: TextStyle(fontFamily: fontFamily, fontSize: fontSize, fontWeight: fw, color: const Color(0xFF1A1A1A)));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Print Rules Bar (permanent, above tabs)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPrintRulesBar(ColorScheme scheme, TextTheme text) {
    return Row(
      children: [
        Icon(Icons.tune_rounded, size: 16, color: scheme.primary),
        const SizedBox(width: 8),
        Text('Print Rules', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(width: 24),
        // Copies
        Text('Copies:', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        _CounterButton(value: _copies, min: 1, max: 10, onChanged: (v) { setState(() => _copies = v); _markDirty(); }),
        const SizedBox(width: 20),
        // Toggles
        _CompactToggle(label: 'Gross', value: _printOnGross, onChanged: (v) { setState(() => _printOnGross = v); _markDirty(); }),
        const SizedBox(width: 12),
        _CompactToggle(label: 'Tare', value: _printOnTare, onChanged: (v) { setState(() => _printOnTare = v); _markDirty(); }),
        const SizedBox(width: 12),
        _CompactToggle(label: 'Auto', value: _autoPrint, onChanged: (v) { setState(() => _autoPrint = v); _markDirty(); }),
        const SizedBox(width: 12),
        _CompactToggle(label: 'Reprint', value: _reprintAllowed, onChanged: (v) { setState(() => _reprintAllowed = v); _markDirty(); }),
        if (_reprintAllowed) ...[
          const SizedBox(width: 8),
          Text('max:', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(width: 4),
          _CounterButton(value: _maxReprints, min: 1, max: 20, onChanged: (v) { setState(() => _maxReprints = v); _markDirty(); }),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Manage Printers Dialog
  // ═══════════════════════════════════════════════════════════════════════════

  void _showManagePrintersDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        var printers = List<Map<String, dynamic>>.from(_printers.map((p) => Map<String, dynamic>.from(p)));
        String? errorMsg;
        return StatefulBuilder(builder: (ctx, setD) {
          return AlertDialog(
            title: const Row(children: [Icon(Icons.print_rounded, size: 20), SizedBox(width: 8), Text('Manage Printers')]),
            content: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 800, maxHeight: MediaQuery.of(ctx).size.height * 0.7),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  if (errorMsg != null) Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.errorContainer, borderRadius: BorderRadius.circular(6)),
                      child: Text(errorMsg!, style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onErrorContainer)),
                    ),
                  ),
                  ...printers.asMap().entries.map((e) {
                    final p = e.value;
                    final pType = p['type'] as String? ?? 'normal';
                    final pName = p['name'] as String? ?? '';
                    final trays = _printerTrays[pName] ?? [];
                    final paperW = (p['paperWidth'] as num?)?.toDouble() ?? 10.0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Theme.of(ctx).colorScheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: TextEditingController(text: p['nickname'] as String? ?? ''),
                                  onChanged: (v) => printers[e.key]['nickname'] = v,
                                  decoration: InputDecoration(hintText: pName.isNotEmpty ? pName : 'Nickname', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: TextEditingController(text: p['address'] as String? ?? ''),
                                  onChanged: (v) => printers[e.key]['address'] = v,
                                  decoration: const InputDecoration(hintText: 'IP / Port', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                onPressed: () => setD(() => printers.removeAt(e.key)),
                                color: Theme.of(ctx).colorScheme.error,
                                iconSize: 18,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              ),
                            ],
                          ),
                          if (pName.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, left: 2),
                              child: Text(pName, style: const TextStyle(fontSize: 10, color: Color(0xFF999999))),
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('Type', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 130,
                                child: DropdownButtonFormField<String>(
                                  initialValue: pType,
                                  items: const [
                                    DropdownMenuItem(value: 'dotMatrix', child: Text('Dot Matrix', style: TextStyle(fontSize: 11))),
                                    DropdownMenuItem(value: 'thermal', child: Text('Thermal', style: TextStyle(fontSize: 11))),
                                    DropdownMenuItem(value: 'normal', child: Text('Page Printer', style: TextStyle(fontSize: 11))),
                                  ],
                                  onChanged: (v) { setD(() { printers[e.key]['type'] = v; printers[e.key]['lines'] = _defaultLinesForType(v!); if (v == 'normal') printers[e.key]['paperSize'] ??= 'A4'; }); },
                                  decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 14),
                                ),
                              ),
                              const SizedBox(width: 16),
                              if (pType == 'normal') ...[
                                const Text('Paper', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 110,
                                  child: DropdownButtonFormField<String>(
                                    initialValue: p['paperSize'] as String? ?? 'A4',
                                    items: ['A4', 'A5', 'Legal', 'Letter'].map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 11)))).toList(),
                                    onChanged: (v) { setD(() { printers[e.key]['paperSize'] = v; printers[e.key]['lines'] = _defaultLinesForType('normal'); }); },
                                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 14),
                                  ),
                                ),
                              ],
                              if (pType == 'thermal') ...[
                                const Text('Width', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 110,
                                  child: DropdownButtonFormField<String>(
                                    initialValue: p['thermalWidth'] as String? ?? '80mm',
                                    items: ['58mm', '80mm'].map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 11)))).toList(),
                                    onChanged: (v) { setD(() => printers[e.key]['thermalWidth'] = v); },
                                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 14),
                                  ),
                                ),
                              ],
                              if (pType == 'dotMatrix') ...[
                                const Text('Width', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 200,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Slider(
                                          value: paperW.clamp(8.0, 13.2),
                                          min: 8.0,
                                          max: 13.2,
                                          divisions: 26,
                                          label: '${paperW.toStringAsFixed(1)}″',
                                          onChanged: (v) { setD(() => printers[e.key]['paperWidth'] = double.parse(v.toStringAsFixed(1))); },
                                        ),
                                      ),
                                      Text('${paperW.toStringAsFixed(1)}″ · ${(paperW * 10).round()} col', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              ],
                              if (trays.isNotEmpty) ...[
                                const SizedBox(width: 16),
                                Icon(Icons.inventory_2_outlined, size: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text('Trays: ${trays.join(", ")}', style: TextStyle(fontSize: 10, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                              ],
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => setD(() => printers.add({'name': '', 'type': 'normal', 'address': '', 'paperSize': 'A4', 'lines': _defaultLinesForType('normal')})),
                        icon: const Icon(Icons.add_rounded, size: 14),
                        label: const Text('Add Printer'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final detected = await _detectSystemPrinters();
                          if (detected.isNotEmpty) {
                            setD(() {
                              for (final dp in detected) {
                                final exists = printers.any((p) => p['name'] == dp['name']);
                                if (!exists) printers.add(dp);
                              }
                            });
                            // Refresh tray detection for newly added printers
                            setState(() => _printers = List.from(printers));
                            await _loadPrinterTrays();
                            setD(() {});
                          }
                        },
                        icon: const Icon(Icons.search_rounded, size: 14),
                        label: const Text('Auto-Detect'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                      ),
                    ],
                  ),
                ],
              ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final nicknames = printers
                      .map((p) => (p['nickname'] as String? ?? '').trim())
                      .where((n) => n.isNotEmpty)
                      .toList();
                  final duplicates = nicknames.where((n) => nicknames.indexOf(n) != nicknames.lastIndexOf(n)).toSet();
                  if (duplicates.isNotEmpty) {
                    setD(() => errorMsg = 'Duplicate nickname: "${duplicates.first}" — each printer must have a unique nickname.');
                    return;
                  }
                  setState(() {
                    _printers = printers.where((p) => (p['name'] as String?)?.isNotEmpty == true).toList();
                    _syncPrinterConfigToTemplates();
                  });
                  _markDirty();
                  Navigator.pop(ctx);
                },
                child: const Text('Apply'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<List<Map<String, dynamic>>> _detectSystemPrinters() async {
    final printers = <Map<String, dynamic>>[];
    try {
      if (Platform.isMacOS) {
        final result = await Process.run('lpstat', ['-p', '-d']);
        if (result.exitCode == 0) {
          final output = result.stdout as String;
          final lines = output.split('\n');
          for (final line in lines) {
            if (line.contains('disabled')) continue;
            final match = RegExp(r'^printer\s+(\S+)\s').firstMatch(line);
            if (match != null) {
              final name = match.group(1)!;
              final check = await Process.run('lpstat', ['-a', name]);
              if (check.exitCode == 0 && (check.stdout as String).contains('accepting')) {
                printers.add({'name': name, 'type': 'normal', 'address': 'cups://$name', 'lines': _defaultLinesForType('normal')});
              }
            }
          }
        }
        final ippResult = await Process.run('ippfind', ['--timeout', '3']);
        if (ippResult.exitCode == 0) {
          final ippOutput = ippResult.stdout as String;
          for (final uri in ippOutput.split('\n').where((l) => l.trim().isNotEmpty)) {
            final uriMatch = RegExp(r'://([^/]+)').firstMatch(uri);
            final ip = uriMatch?.group(1) ?? uri;
            final exists = printers.any((p) => p['address'] == uri);
            if (!exists) {
              printers.add({'name': 'Network ($ip)', 'type': 'normal', 'address': uri, 'lines': _defaultLinesForType('normal')});
            }
          }
        }
      } else if (Platform.isWindows) {
        final result = await Process.run('wmic', ['printer', 'get', 'Name,PortName', '/format:csv']);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).split('\n').skip(1);
          for (final line in lines) {
            final parts = line.split(',');
            if (parts.length >= 3) {
              printers.add({'name': parts[1].trim(), 'type': 'normal', 'address': parts[2].trim(), 'lines': _defaultLinesForType('normal')});
            }
          }
        }
      }
    } catch (_) {}
    return printers;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Printer Assignment Bar
  // ═══════════════════════════════════════════════════════════════════════════

  String _printerDisplayName(Map<String, dynamic> p) {
    final nickname = p['nickname'] as String? ?? '';
    if (nickname.isNotEmpty) return nickname;
    return p['name'] as String? ?? 'Unnamed';
  }

  List<String> get _printerNames {
    final names = _printers.map(_printerDisplayName).toList();
    if (names.isEmpty) return ['Default Printer'];
    return names;
  }

  Widget _buildPrinterAssignmentBar(ColorScheme scheme, TextTheme text) {
    final printerOptions = _printerNames;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.print_rounded, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Text('Printer Assignment', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 24),
            Text('1st Weighment:', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            _MiniPrinterDropdown(
              value: _grossPrinter,
              items: printerOptions,
              onChanged: (v) { setState(() => _grossPrinter = v); _markDirty(); },
            ),
            if (_getTraysForPrinter(_grossPrinter).isNotEmpty) ...[
              const SizedBox(width: 4),
              _MiniDropdown(value: _getTraysForPrinter(_grossPrinter).contains(_grossTray) ? _grossTray : _getTraysForPrinter(_grossPrinter).first, items: _getTraysForPrinter(_grossPrinter), onChanged: (v) { setState(() => _grossTray = v); _markDirty(); }),
            ],
            const SizedBox(width: 16),
            Text('2nd Weighment:', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            _MiniPrinterDropdown(
              value: _tarePrinter,
              items: printerOptions,
              onChanged: (v) { setState(() => _tarePrinter = v); _markDirty(); },
            ),
            if (_getTraysForPrinter(_tarePrinter).isNotEmpty) ...[
              const SizedBox(width: 4),
              _MiniDropdown(value: _getTraysForPrinter(_tarePrinter).contains(_tareTray) ? _tareTray : _getTraysForPrinter(_tarePrinter).first, items: _getTraysForPrinter(_tarePrinter), onChanged: (v) { setState(() => _tareTray = v); _markDirty(); }),
            ],
            const SizedBox(width: 16),
            _CompactToggle(label: 'Backup', value: _backupEnabled, onChanged: (v) {
              final backupAvailable = !(_grossPrinter == _tarePrinter && printerOptions.length <= 1);
              if (v && !backupAvailable) return;
              setState(() => _backupEnabled = v);
              _markDirty();
            }),
            if (_backupEnabled && _grossPrinter == _tarePrinter && printerOptions.length <= 1) ...[
              const SizedBox(width: 8),
              Text('No alternate printer available', style: text.bodySmall?.copyWith(color: scheme.error, fontSize: 10)),
            ] else if (_backupEnabled) ...[
              const SizedBox(width: 8),
              Builder(builder: (_) {
                final backupOptions = (_grossPrinter == _tarePrinter)
                    ? printerOptions.where((p) => p != _grossPrinter).toList()
                    : printerOptions;
                final effectiveValue = backupOptions.contains(_backupPrinter) ? _backupPrinter : backupOptions.first;
                if (effectiveValue != _backupPrinter) {
                  WidgetsBinding.instance.addPostFrameCallback((_) { setState(() => _backupPrinter = effectiveValue); _markDirty(); });
                }
                return _MiniPrinterDropdown(
                  value: effectiveValue,
                  items: backupOptions,
                  onChanged: (v) { setState(() => _backupPrinter = v); _markDirty(); },
                );
              }),
              if (_getTraysForPrinter(_backupPrinter).isNotEmpty) ...[
                const SizedBox(width: 4),
                _MiniDropdown(value: _getTraysForPrinter(_backupPrinter).contains(_backupTray) ? _backupTray : _getTraysForPrinter(_backupPrinter).first, items: _getTraysForPrinter(_backupPrinter), onChanged: (v) { setState(() => _backupTray = v); _markDirty(); }),
              ],
            ],
            const Spacer(),
            _CompactToggle(label: 'Material Routing', value: _materialRoutingEnabled, onChanged: (v) { setState(() => _materialRoutingEnabled = v); _markDirty(); }),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _showManagePrintersDialog,
              icon: const Icon(Icons.settings_rounded, size: 14),
              label: const Text('Manage Printers'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
            ),
          ],
        ),
        if (_materialRoutingEnabled) ...[
          const SizedBox(height: 12),
          _buildMaterialRoutingSection(scheme, text, printerOptions),
        ],
      ],
    );
  }

  Widget _buildMaterialRoutingSection(ColorScheme scheme, TextTheme text, List<String> printerOptions) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, size: 14, color: scheme.secondary),
              const SizedBox(width: 6),
              Text('Route to printer by material', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _materialPrinterRules.add({'material': '', 'printer': _printerNames.first, 'tray': 'Auto', 'copies': _copies}));
                  _markDirty();
                },
                icon: const Icon(Icons.add_rounded, size: 12),
                label: const Text('Add Rule'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), textStyle: const TextStyle(fontSize: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
              ),
            ],
          ),
          if (_materialPrinterRules.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No material routing rules. All materials use the default printer assignment above.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
            )
          else ...[
            const SizedBox(height: 8),
            ..._materialPrinterRules.asMap().entries.map((e) {
              final rule = e.value;
              final material = rule['material'] as String? ?? '';
              final printer = rule['printer'] as String? ?? 'default';
              final copies = rule['copies'] as int? ?? _copies;
              final printOn = rule['printOn'] as String? ?? '—';
              final materials = ref.watch(_materialsProvider).valueOrNull ?? [];
              final materialItems = materials.where((m) =>
                m == material || !_materialPrinterRules.any((r) {
                  if (r == rule || r['material'] != m) return false;
                  final rPrintOn = r['printOn'] as String? ?? '—';
                  if (rPrintOn == 'both' || printOn == 'both') return true;
                  if (rPrintOn == '—' || printOn == '—') return false;
                  return rPrintOn == printOn;
                })
              ).toList();
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 150,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                        ),
                        child: DropdownButton<String>(
                          value: materialItems.contains(material) ? material : null,
                          hint: Text('Select', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
                          isExpanded: true,
                          underline: const SizedBox(),
                          isDense: true,
                          style: text.bodySmall?.copyWith(color: scheme.onSurface),
                          items: materialItems.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                          onChanged: (v) { if (v != null) { setState(() => _materialPrinterRules[e.key] = {...rule, 'material': v}); _markDirty(); } },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    _MiniPrinterDropdown(
                      value: printer,
                      items: printerOptions,
                      onChanged: (v) { setState(() => _materialPrinterRules[e.key] = {...rule, 'printer': v}); _markDirty(); },
                    ),
                    if (_getTraysForPrinter(printer).isNotEmpty) ...[
                      const SizedBox(width: 4),
                      _MiniDropdown(value: _getTraysForPrinter(printer).contains(rule['tray'] as String? ?? '') ? (rule['tray'] as String) : _getTraysForPrinter(printer).first, items: _getTraysForPrinter(printer), onChanged: (v) { setState(() => _materialPrinterRules[e.key] = {...rule, 'tray': v}); _markDirty(); }),
                    ],
                    const SizedBox(width: 8),
                    Text('×', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(width: 4),
                    _CounterButton(value: copies, min: 1, max: 10, onChanged: (v) { setState(() => _materialPrinterRules[e.key] = {...rule, 'copies': v}); _markDirty(); }),
                    const SizedBox(width: 8),
                    _MiniDropdown(value: printOn, items: const ['—', '1st', '2nd', 'both'], onChanged: (v) { setState(() => _materialPrinterRules[e.key] = {...rule, 'printOn': v}); _markDirty(); }),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () { setState(() => _materialPrinterRules.removeAt(e.key)); _markDirty(); },
                      child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 14, color: scheme.error)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Placeholder reference card
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPlaceholderReference(ColorScheme scheme, TextTheme text) {
    final customFieldsAsync = ref.watch(_customFieldsProvider);
    final customFields = customFieldsAsync.valueOrNull ?? [];

    return _Section(scheme: scheme, icon: Icons.code_rounded, title: 'Placeholders', children: [
      ...['Company', 'Customer', 'Weighment', 'System'].map((cat) {
        final items = _builtInPlaceholders.where((p) => p.category == cat).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(cat, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary)),
            ),
            ...items.map((p) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(4)),
                    child: Text(p.key, style: const TextStyle(fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(p.label, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant))),
                ],
              ),
            )),
          ],
        );
      }),
      if (customFields.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text('Custom Fields', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.secondary)),
        ),
        ...customFields.asMap().entries.map((e) {
          final label = e.value['label'] as String;
          final key = '{custom_${e.key + 1}}';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: scheme.secondaryContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(4)),
                  child: Text(key, style: const TextStyle(fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(label, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant))),
              ],
            ),
          );
        }),
      ],
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDropdownRow(String label, String value, List<String> items, ValueChanged<String?> onChanged, TextTheme text) {
    return Row(
      children: [
        SizedBox(width: 100, child: Text(label, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: value,
            items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: text.bodySmall, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: onChanged,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildNumberInput(String label, int value, ValueChanged<int> onChanged, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          controller: TextEditingController(text: value.toString()),
          keyboardType: TextInputType.number,
          style: text.bodySmall,
          onChanged: (v) { final n = int.tryParse(v); if (n != null) onChanged(n); },
          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
        ),
      ],
    );
  }

  Widget _buildDoubleInput(String label, double value, ValueChanged<double> onChanged, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          controller: TextEditingController(text: value.toStringAsFixed(0)),
          keyboardType: TextInputType.number,
          style: text.bodySmall,
          onChanged: (v) { final n = double.tryParse(v); if (n != null) onChanged(n); },
          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Private Widgets
// ═══════════════════════════════════════════════════════════════════════════════

class _Section extends StatelessWidget {
  final ColorScheme scheme;
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _Section({required this.scheme, required this.icon, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Flexible(child: Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(child: Text(label, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w500))),
        Switch(value: value, onChanged: onChanged, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      ],
    );
  }
}

class _CounterButton extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _CounterButton({required this.value, required this.min, required this.max, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: value > min ? () => onChanged(value - 1) : null,
            child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.remove_rounded, size: 14, color: value > min ? scheme.primary : scheme.outlineVariant)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('$value', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface)),
          ),
          InkWell(
            onTap: value < max ? () => onChanged(value + 1) : null,
            child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.add_rounded, size: 14, color: value < max ? scheme.primary : scheme.outlineVariant)),
          ),
        ],
      ),
    );
  }
}

class _CompactToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CompactToggle({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: value ? scheme.primaryContainer.withValues(alpha: 0.4) : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: value ? scheme.primary.withValues(alpha: 0.4) : scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(value ? Icons.check_circle_rounded : Icons.circle_outlined, size: 12, color: value ? scheme.primary : scheme.outlineVariant),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: value ? scheme.primary : scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _DmLineEditor extends StatefulWidget {
  final int index;
  final Map<String, dynamic> line;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final int totalLines;

  const _DmLineEditor({required this.index, required this.line, required this.onChanged, required this.onRemove, this.onMoveUp, this.onMoveDown, this.totalLines = 0});

  @override
  State<_DmLineEditor> createState() => _DmLineEditorState();
}

class _DmLineEditorState extends State<_DmLineEditor> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.line['text'] as String? ?? '');
  }

  @override
  void didUpdateWidget(_DmLineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newText = widget.line['text'] as String? ?? '';
    if (newText != _controller.text) {
      _controller.text = newText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final align = widget.line['align'] as String? ?? 'left';
    final style = widget.line['style'] as String? ?? 'normal';
    final group = widget.line['group'] as int? ?? 0;
    final isNoText = style == 'separator' || style == 'blank';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Column(
            children: [
              InkWell(
                onTap: widget.onMoveUp,
                child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.keyboard_arrow_up_rounded, size: 14, color: widget.onMoveUp != null ? scheme.onSurfaceVariant : scheme.outlineVariant.withValues(alpha: 0.3))),
              ),
              InkWell(
                onTap: widget.onMoveDown,
                child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: widget.onMoveDown != null ? scheme.onSurfaceVariant : scheme.outlineVariant.withValues(alpha: 0.3))),
              ),
            ],
          ),
          const SizedBox(width: 4),
          Expanded(
            child: isNoText
                ? Container(
                    height: 34,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
                    ),
                    child: Text(style == 'blank' ? '(blank line)' : '── separator line ──', style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
                  )
                : TextField(
                    controller: _controller,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    onChanged: (v) => widget.onChanged({...widget.line, 'text': v}),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          _MiniDropdown(value: align, items: const ['left', 'center', 'right'], onChanged: (v) => widget.onChanged({...widget.line, 'align': v})),
          const SizedBox(width: 4),
          _MiniDropdown(
            value: style,
            items: const ['normal', 'bold', 'double', 'separator', 'blank'],
            onChanged: (v) {
              final updated = {...widget.line, 'style': v};
              if (v == 'separator' || v == 'blank') {
                updated['text'] = '';
                _controller.clear();
              }
              widget.onChanged(updated);
            },
          ),
          const SizedBox(width: 4),
          _MiniDropdown(
            value: group == 0 ? '—' : 'G$group',
            items: ['—', ...List.generate(((widget.totalLines + 1) / 2).ceil().clamp(1, 10), (i) => 'G${i + 1}')],
            onChanged: (v) => widget.onChanged({...widget.line, 'group': v == '—' ? 0 : int.parse(v.substring(1))}),
          ),
          const SizedBox(width: 4),
          InkWell(onTap: widget.onRemove, child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 14, color: scheme.error))),
        ],
      ),
    );
  }
}

class _ThermalLineEditor extends StatefulWidget {
  final int index;
  final Map<String, dynamic> line;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _ThermalLineEditor({required this.index, required this.line, required this.onChanged, required this.onRemove, this.onMoveUp, this.onMoveDown});

  @override
  State<_ThermalLineEditor> createState() => _ThermalLineEditorState();
}

class _ThermalLineEditorState extends State<_ThermalLineEditor> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.line['text'] as String? ?? '');
  }

  @override
  void didUpdateWidget(_ThermalLineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newText = widget.line['text'] as String? ?? '';
    if (newText != _controller.text) {
      _controller.text = newText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final align = widget.line['align'] as String? ?? 'left';
    final size = widget.line['size'] as String? ?? 'normal';
    final group = widget.line['group'] as int? ?? 0;
    final isSeparator = size == 'separator';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Column(
            children: [
              InkWell(
                onTap: widget.onMoveUp,
                child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.keyboard_arrow_up_rounded, size: 14, color: widget.onMoveUp != null ? scheme.onSurfaceVariant : scheme.outlineVariant.withValues(alpha: 0.3))),
              ),
              InkWell(
                onTap: widget.onMoveDown,
                child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: widget.onMoveDown != null ? scheme.onSurfaceVariant : scheme.outlineVariant.withValues(alpha: 0.3))),
              ),
            ],
          ),
          const SizedBox(width: 4),
          Expanded(
            child: isSeparator
                ? Container(
                    height: 34,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
                    ),
                    child: Text('── separator line ──', style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
                  )
                : TextField(
                    controller: _controller,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    onChanged: (v) => widget.onChanged({...widget.line, 'text': v}),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          _MiniDropdown(value: align, items: const ['left', 'center', 'right'], onChanged: (v) => widget.onChanged({...widget.line, 'align': v})),
          const SizedBox(width: 4),
          _MiniDropdown(
            value: size,
            items: const ['normal', 'bold', 'double', 'separator'],
            onChanged: (v) {
              final updated = {...widget.line, 'size': v};
              if (v == 'separator') {
                updated['text'] = '';
                _controller.clear();
              }
              widget.onChanged(updated);
            },
          ),
          const SizedBox(width: 4),
          _MiniDropdown(value: group == 0 ? '—' : 'G$group', items: ['—', 'G1', 'G2', 'G3', 'G4', 'G5', 'G6', 'G7', 'G8'], onChanged: (v) => widget.onChanged({...widget.line, 'group': v == '—' ? 0 : int.parse(v.substring(1))})),
          const SizedBox(width: 4),
          InkWell(onTap: widget.onRemove, child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 14, color: scheme.error))),
        ],
      ),
    );
  }
}

class _MiniDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  const _MiniDropdown({required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3))),
      child: DropdownButton<String>(
        value: value,
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 10)))).toList(),
        onChanged: (v) { if (v != null) onChanged(v); },
        underline: const SizedBox(),
        isDense: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 12),
      ),
    );
  }
}

class _MiniPrinterDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  const _MiniPrinterDropdown({required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveValue = items.contains(value) ? value : items.first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3))),
      child: DropdownButton<String>(
        value: effectiveValue,
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 11)))).toList(),
        onChanged: (v) { if (v != null) onChanged(v); },
        underline: const SizedBox(),
        isDense: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 14),
      ),
    );
  }
}


class _NormalPreviewContainer extends StatefulWidget {
  final double width;
  final double height;
  final EdgeInsets padding;
  final ColorScheme scheme;
  final List<Widget> children;
  final ValueChanged<bool>? onOverflowChanged;

  const _NormalPreviewContainer({required this.width, required this.height, required this.padding, required this.scheme, required this.children, this.onOverflowChanged});

  @override
  State<_NormalPreviewContainer> createState() => _NormalPreviewContainerState();
}

class _NormalPreviewContainerState extends State<_NormalPreviewContainer> {
  final _contentKey = GlobalKey();
  bool _overflows = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  @override
  void didUpdateWidget(_NormalPreviewContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  void _checkOverflow() {
    if (!mounted) return;
    final renderBox = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final contentHeight = renderBox.size.height;
    final availableHeight = widget.height - widget.padding.top - widget.padding.bottom;
    final overflows = contentHeight > availableHeight;
    if (overflows != _overflows) {
      setState(() => _overflows = overflows);
    }
    widget.onOverflowChanged?.call(overflows);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: widget.width,
          height: widget.height,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: _overflows ? Colors.red.withValues(alpha: 0.7) : widget.scheme.outlineVariant.withValues(alpha: 0.4),
              width: _overflows ? 2.0 : 1.0,
            ),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: ClipRect(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                key: _contentKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children,
              ),
            ),
          ),
        ),
        if (_overflows)
          Positioned(
            bottom: 6,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(4)),
                child: const Text('Content exceeds page', style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
      ],
    );
  }
}

class _DmDotPainter extends CustomPainter {
  final _DmDotData data;
  _DmDotPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final dotW = size.width / data.width;
    final dotH = size.height / data.height;
    final paint = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.fill;

    for (var y = 0; y < data.height; y++) {
      final rowOffset = y * data.width;
      for (var x = 0; x < data.width; x++) {
        if (data.dots[rowOffset + x]) {
          canvas.drawRect(
            Rect.fromLTWH(x * dotW, y * dotH, dotW, dotH),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_DmDotPainter oldDelegate) => oldDelegate.data != data;
}

class _RulerPainter extends CustomPainter {
  final double totalInches;
  final double ppi;
  final bool horizontal;
  final Color color;

  _RulerPainter({required this.totalInches, required this.ppi, required this.horizontal, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final textStyle = TextStyle(fontSize: 9, color: color);
    final maxPos = horizontal ? size.width : size.height;

    for (var inch = 0; inch <= totalInches.ceil(); inch++) {
      final pos = inch * ppi;
      if (pos > maxPos) break;

      if (horizontal) {
        canvas.drawLine(Offset(pos, size.height), Offset(pos, size.height - 10), paint);
        textPainter.text = TextSpan(text: '$inch', style: textStyle);
        textPainter.layout();
        textPainter.paint(canvas, Offset(pos + 2, 0));
      } else {
        canvas.drawLine(Offset(size.width, pos), Offset(size.width - 10, pos), paint);
        textPainter.text = TextSpan(text: '$inch', style: textStyle);
        textPainter.layout();
        textPainter.paint(canvas, Offset(1, pos + 2));
      }

      if (inch < totalInches.ceil()) {
        final half = pos + ppi / 2;
        final q1 = pos + ppi / 4;
        final q3 = pos + ppi * 3 / 4;
        if (horizontal) {
          if (half <= maxPos) canvas.drawLine(Offset(half, size.height), Offset(half, size.height - 6), paint);
          if (q1 <= maxPos) canvas.drawLine(Offset(q1, size.height), Offset(q1, size.height - 4), paint);
          if (q3 <= maxPos) canvas.drawLine(Offset(q3, size.height), Offset(q3, size.height - 4), paint);
        } else {
          if (half <= maxPos) canvas.drawLine(Offset(size.width, half), Offset(size.width - 6, half), paint);
          if (q1 <= maxPos) canvas.drawLine(Offset(size.width, q1), Offset(size.width - 4, q1), paint);
          if (q3 <= maxPos) canvas.drawLine(Offset(size.width, q3), Offset(size.width - 4, q3), paint);
        }
      }
    }
    if (horizontal) {
      canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), paint);
    } else {
      canvas.drawLine(Offset(size.width - 0.5, 0), Offset(size.width - 0.5, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) => old.totalInches != totalInches || old.ppi != ppi || old.color != color;
}

class _Pdf417Painter extends CustomPainter {
  final List<BarcodeElement> elements;
  final double barcodeW;
  final double barcodeH;
  _Pdf417Painter(this.elements, this.barcodeW, this.barcodeH);

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / barcodeW;
    final scaleY = size.height / barcodeH;
    final paint = Paint()..color = const Color(0xFF000000);

    for (final elem in elements) {
      if (elem is BarcodeBar && elem.black) {
        canvas.drawRect(
          Rect.fromLTWH(elem.left * scaleX, elem.top * scaleY, elem.width * scaleX, elem.height * scaleY),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Pdf417Painter oldDelegate) => false;
}
