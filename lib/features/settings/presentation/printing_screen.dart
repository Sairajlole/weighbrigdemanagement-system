import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';

// ─── Providers ──────────────────────────────────────────────────────────────

final _printSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestoreProvider);
  final doc = await db.collection('settings').doc('printing').get();
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
  _Placeholder('{time}', 'Current Time', 'System'),
  _Placeholder('{serial_no}', 'Serial Number', 'System'),
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

  // ── Printer Assignment ──
  String _grossPrinter = 'default';
  String _tarePrinter = 'default';
  String _backupPrinter = '';
  bool _backupEnabled = false;
  bool _materialRoutingEnabled = false;
  List<Map<String, dynamic>> _materialPrinterRules = [];

  // ── Print Rules ──
  int _copies = 2;
  bool _printOnGross = false;
  bool _printOnTare = true;
  bool _autoPrint = true;
  bool _reprintAllowed = true;
  int _maxReprints = 3;

  // ── Dot Matrix ──
  int _dmColumns = 80;
  String _dmCharSet = 'Normal';
  bool _dmBorders = true;
  int _dmMarginTop = 1;
  int _dmMarginBottom = 1;
  int _dmMarginLeft = 2;
  List<Map<String, dynamic>> _dmLines = [];

  // ── Thermal ──
  String _thermalWidth = '80mm';
  bool _thermalLogo = true;
  bool _thermalPdf417 = false;
  String _thermalCutMode = 'Full';
  int _thermalFontSize = 12;
  List<Map<String, dynamic>> _thermalLines = [];

  // ── Header Layout (normal printer only) ──
  String _headerLayout = 'inline';  // 'stacked' or 'inline' (logo beside text)
  int _headerRows = 3; // number of top lines logo sits beside when inline

  // ── Per-template Logo ──
  double _thermalLogoWidth = 30;
  double _thermalLogoHeight = 30;
  double _normalLogoWidth = 80;
  double _normalLogoHeight = 80;

  // ── Font Size ──
  int _normalFontSize = 14;

  // ── Multi-column ──
  int _dmColumnCount = 1;
  int _thermalColumnCount = 1;

  // ── Normal ──
  String _normalPaperSize = 'A4';
  String _normalOrientation = 'Portrait';
  double _normalMarginTop = 15;
  double _normalMarginBottom = 15;
  double _normalMarginLeft = 15;
  double _normalMarginRight = 15;
  bool _normalLogo = true;
  bool _normalPdf417 = false;
  String _normalPdf417Position = 'bottom';
  bool _normalCctv = false;
  List<String> _normalCctvCameras = [];
  bool _normalCustomFields = true;
  List<Map<String, dynamic>> _normalLines = [];

  // Per-size config store
  final Map<String, Map<String, dynamic>> _perSizeConfigs = {};

  Map<String, dynamic> _getCurrentSizeConfig() => {
    'orientation': _normalOrientation,
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
    'customFields': _normalCustomFields,
    'fontSize': _normalFontSize,
    'normalLines': _normalLines.map((l) => Map<String, dynamic>.from(l)).toList(),
  };

  void _applySizeConfig(Map<String, dynamic> cfg) {
    _normalOrientation = cfg['orientation'] as String? ?? 'Portrait';
    _normalMarginTop = (cfg['marginTop'] as num?)?.toDouble() ?? 15;
    _normalMarginBottom = (cfg['marginBottom'] as num?)?.toDouble() ?? 15;
    _normalMarginLeft = (cfg['marginLeft'] as num?)?.toDouble() ?? 15;
    _normalMarginRight = (cfg['marginRight'] as num?)?.toDouble() ?? 15;
    _headerLayout = cfg['headerLayout'] as String? ?? 'inline';
    _headerRows = cfg['headerRows'] as int? ?? 3;
    _normalLogo = cfg['logo'] as bool? ?? true;
    _normalLogoWidth = (cfg['logoWidth'] as num?)?.toDouble() ?? 80;
    _normalLogoHeight = (cfg['logoHeight'] as num?)?.toDouble() ?? 80;
    _normalPdf417 = cfg['pdf417'] as bool? ?? false;
    _normalPdf417Position = cfg['pdf417Position'] as String? ?? 'bottom';
    _normalCctv = cfg['cctv'] as bool? ?? false;
    _normalCctvCameras = List<String>.from(cfg['cctvCameras'] as List? ?? []);
    _normalCustomFields = cfg['customFields'] as bool? ?? true;
    _normalFontSize = cfg['fontSize'] as int? ?? 14;
    final lines = cfg['normalLines'] as List?;
    _normalLines = lines != null
        ? lines.map((l) => Map<String, dynamic>.from(l as Map)).toList()
        : _getDefaultNormalLines();
  }

  static Map<String, dynamic> _getDefaultSizeConfig(String size) {
    switch (size) {
      case 'A5':
        return {
          'orientation': 'Portrait',
          'marginTop': 10.0, 'marginBottom': 10.0, 'marginLeft': 10.0, 'marginRight': 10.0,
          'headerLayout': 'inline', 'headerRows': 3,
          'logo': true, 'logoWidth': 50.0, 'logoHeight': 50.0,
          'pdf417': false, 'pdf417Position': 'bottom',
          'cctv': false, 'cctvCameras': <String>[],
          'customFields': true, 'fontSize': 10,
          'normalLines': _getDefaultNormalLines(),
        };
      case 'Legal':
        return {
          'orientation': 'Portrait',
          'marginTop': 15.0, 'marginBottom': 15.0, 'marginLeft': 15.0, 'marginRight': 15.0,
          'headerLayout': 'inline', 'headerRows': 3,
          'logo': true, 'logoWidth': 80.0, 'logoHeight': 80.0,
          'pdf417': true, 'pdf417Position': 'bottom',
          'cctv': true, 'cctvCameras': ['Front', 'Rear', 'Top', 'Side', 'Operator', 'Customer'],
          'customFields': true, 'fontSize': 14,
          'normalLines': _getDefaultNormalLines(),
        };
      default: // A4, Letter
        return {
          'orientation': 'Portrait',
          'marginTop': 15.0, 'marginBottom': 15.0, 'marginLeft': 15.0, 'marginRight': 15.0,
          'headerLayout': 'inline', 'headerRows': 3,
          'logo': true, 'logoWidth': 80.0, 'logoHeight': 80.0,
          'pdf417': true, 'pdf417Position': 'bottom',
          'cctv': true, 'cctvCameras': ['Front', 'Rear', 'Top', 'Side'],
          'customFields': true, 'fontSize': 14,
          'normalLines': _getDefaultNormalLines(),
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
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initDefaults();
  }

  void _initDefaults() {
    _dmLines = _getDefaultDmLines();
    _thermalLines = _getDefaultThermalLines();
    _normalLines = _getDefaultNormalLines();
  }

  static List<Map<String, dynamic>> _getDefaultDmLines() => [
    {'text': '{company_name}', 'align': 'left', 'style': 'double'},
    {'text': '{company_address1}', 'align': 'left', 'style': 'normal'},
    {'text': '{company_address2}', 'align': 'left', 'style': 'normal'},
    {'text': '', 'align': 'left', 'style': 'separator'},
    {'text': 'RST: {rst}', 'align': 'left', 'style': 'normal', 'group': 1},
    {'text': 'Material: {material}', 'align': 'left', 'style': 'normal', 'group': 1},
    {'text': '', 'align': 'left', 'style': 'separator'},
    {'text': 'Vehicle: {vehicle}', 'align': 'left', 'style': 'normal', 'group': 2},
    {'text': 'Phone:    {customer_phone}', 'align': 'left', 'style': 'normal', 'group': 2},
    {'text': 'Customer: {customer_name}', 'align': 'left', 'style': 'normal', 'group': 3},
    {'text': 'Address: {customer_address}', 'align': 'left', 'style': 'normal', 'group': 3},
    {'text': '', 'align': 'left', 'style': 'separator'},
    {'text': 'Gross:  {gross} kg', 'align': 'left', 'style': 'normal', 'group': 4},
    {'text': '({gross_datetime})', 'align': 'left', 'style': 'normal', 'group': 4},
    {'text': 'Tare:   {tare} kg', 'align': 'left', 'style': 'normal', 'group': 5},
    {'text': '({tare_datetime})', 'align': 'left', 'style': 'normal', 'group': 5},
    {'text': 'Net:    {net} kg', 'align': 'left', 'style': 'normal', 'group': 6},
    {'text': '({net_datetime})', 'align': 'left', 'style': 'normal', 'group': 6},
    {'text': '', 'align': 'left', 'style': 'separator'},
    {'text': 'Operator: {operator}', 'align': 'left', 'style': 'normal', 'group': 7},
    {'text': 'Time: {time}', 'align': 'left', 'style': 'normal', 'group': 7},
    {'text': 'Weighbridge: {weighbridge_name}', 'align': 'left', 'style': 'normal', 'group': 8},
    {'text': 'Serial: {serial_no}', 'align': 'left', 'style': 'normal', 'group': 8},
  ];

  static List<Map<String, dynamic>> _getDefaultThermalLines() => [
    {'text': '{company_name}', 'align': 'left', 'size': 'double'},
    {'text': '', 'align': 'left', 'size': 'separator'},
    {'text': 'RST: {rst}', 'align': 'left', 'size': 'normal'},
    {'text': 'Date: {date} {time}', 'align': 'left', 'size': 'normal'},
    {'text': 'Material: {material}', 'align': 'left', 'size': 'normal'},
    {'text': '', 'align': 'left', 'size': 'separator'},
    {'text': 'Vehicle: {vehicle}', 'align': 'left', 'size': 'normal'},
    {'text': 'Phone:    {customer_phone}', 'align': 'left', 'size': 'normal'},
    {'text': 'Customer: {customer_name}', 'align': 'left', 'size': 'normal'},
    {'text': 'Address: {customer_address}', 'align': 'left', 'size': 'normal'},
    {'text': '', 'align': 'left', 'size': 'separator'},
    {'text': 'Gross: {gross} kg', 'align': 'left', 'size': 'normal'},
    {'text': 'Tare:  {tare} kg', 'align': 'left', 'size': 'normal'},
    {'text': 'Net:   {net} kg', 'align': 'left', 'size': 'bold'},
    {'text': '', 'align': 'left', 'size': 'separator'},
    {'text': 'Operator: {operator}', 'align': 'left', 'size': 'normal'},
    {'text': 'Weighbridge: {weighbridge_name}', 'align': 'left', 'size': 'normal'},
  ];

  static List<Map<String, dynamic>> _getDefaultNormalLines() => [
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
    {'text': 'Gross: {gross} kg', 'align': 'left', 'style': 'normal', 'group': 4},
    {'text': '({gross_datetime})', 'align': 'left', 'style': 'normal', 'group': 4},
    {'text': 'Tare: {tare} kg', 'align': 'left', 'style': 'normal', 'group': 5},
    {'text': '({tare_datetime})', 'align': 'left', 'style': 'normal', 'group': 5},
    {'text': 'Net: {net} kg', 'align': 'left', 'style': 'bold', 'group': 6},
    {'text': '({net_datetime})', 'align': 'left', 'style': 'normal', 'group': 6},
    {'text': '', 'align': 'left', 'style': 'blank'},
    {'text': 'Operator: {operator}', 'align': 'left', 'style': 'normal', 'group': 7},
    {'text': 'Time: {time}', 'align': 'left', 'style': 'normal', 'group': 7},
    {'text': 'Weighbridge: {weighbridge_name}', 'align': 'left', 'style': 'normal', 'group': 8},
    {'text': 'Serial: {serial_no}', 'align': 'left', 'style': 'normal', 'group': 8},
  ];

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
    _tarePrinter = data['tarePrinter'] as String? ?? 'default';
    _backupPrinter = data['backupPrinter'] as String? ?? '';
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
    _thermalColumnCount = data['thermalColumnCount'] as int? ?? 1;

    // Dot Matrix
    _dmColumns = data['dmColumns'] as int? ?? 80;
    _dmCharSet = data['dmCharSet'] as String? ?? 'Normal';
    _dmBorders = data['dmBorders'] as bool? ?? true;
    _dmMarginTop = data['dmMarginTop'] as int? ?? 1;
    _dmMarginBottom = data['dmMarginBottom'] as int? ?? 1;
    _dmMarginLeft = data['dmMarginLeft'] as int? ?? 2;
    final dmLines = data['dmLines'] as List<dynamic>?;
    if (dmLines != null) _dmLines = dmLines.map((l) => Map<String, dynamic>.from(l as Map)).toList();

    // Thermal
    _thermalWidth = data['thermalWidth'] as String? ?? '80mm';
    _thermalLogo = data['thermalLogo'] as bool? ?? true;
    _thermalPdf417 = data['thermalPdf417'] as bool? ?? false;
    _thermalCutMode = data['thermalCutMode'] as String? ?? 'Full';
    _thermalFontSize = data['thermalFontSize'] as int? ?? 12;
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
      _normalOrientation = data['normalOrientation'] as String? ?? 'Portrait';
      _normalMarginTop = (data['normalMarginTop'] as num?)?.toDouble() ?? 15;
      _normalMarginBottom = (data['normalMarginBottom'] as num?)?.toDouble() ?? 15;
      _normalMarginLeft = (data['normalMarginLeft'] as num?)?.toDouble() ?? 15;
      _normalMarginRight = (data['normalMarginRight'] as num?)?.toDouble() ?? 15;
      _normalLogo = data['normalLogo'] as bool? ?? true;
      _normalLogoWidth = (data['normalLogoWidth'] as num?)?.toDouble() ?? 80;
      _normalLogoHeight = (data['normalLogoHeight'] as num?)?.toDouble() ?? 80;
      _normalPdf417 = data['normalPdf417'] as bool? ?? false;
      _normalPdf417Position = data['normalPdf417Position'] as String? ?? 'bottom';
      _normalCctv = data['normalCctv'] as bool? ?? false;
      final cctvCams = data['normalCctvCameras'] as List<dynamic>?;
      if (cctvCams != null) _normalCctvCameras = cctvCams.cast<String>();
      _normalCustomFields = data['normalCustomFields'] as bool? ?? true;
      _normalFontSize = data['normalFontSize'] as int? ?? 14;
      final nLines = data['normalLines'] as List<dynamic>?;
      if (nLines != null) _normalLines = nLines.map((l) => Map<String, dynamic>.from(l as Map)).toList();
    }
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Map<String, dynamic> _buildPayload() => {
    'printers': _printers,
    'grossPrinter': _grossPrinter,
    'tarePrinter': _tarePrinter,
    'backupPrinter': _backupPrinter,
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
    'thermalColumnCount': _thermalColumnCount,
    'dmColumns': _dmColumns,
    'dmCharSet': _dmCharSet,
    'dmBorders': _dmBorders,
    'dmMarginTop': _dmMarginTop,
    'dmMarginBottom': _dmMarginBottom,
    'dmMarginLeft': _dmMarginLeft,
    'dmLines': _dmLines,
    'thermalWidth': _thermalWidth,
    'thermalLogo': _thermalLogo,
    'thermalPdf417': _thermalPdf417,
    'thermalCutMode': _thermalCutMode,
    'thermalFontSize': _thermalFontSize,
    'thermalLines': _thermalLines,
    'normalPaperSize': _normalPaperSize,
    'normalOrientation': _normalOrientation,
    'normalMarginTop': _normalMarginTop,
    'normalMarginBottom': _normalMarginBottom,
    'normalMarginLeft': _normalMarginLeft,
    'normalMarginRight': _normalMarginRight,
    'normalLogo': _normalLogo,
    'normalPdf417': _normalPdf417,
    'normalPdf417Position': _normalPdf417Position,
    'normalCctv': _normalCctv,
    'normalCctvCameras': _normalCctvCameras,
    'normalCustomFields': _normalCustomFields,
    'normalFontSize': _normalFontSize,
    'normalLines': _normalLines,
    'perSizeConfigs': {
      ..._perSizeConfigs,
      _normalPaperSize: _getCurrentSizeConfig(),
    },
  };

  Future<void> _save() async {
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final settingsAsync = ref.watch(_printSettingsProvider);
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
                        Tab(text: 'Normal Printer'),
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
              Text('Docket templates, printer setup, and print rules', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
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
            label: const Text('Save All'),
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
                  _buildDropdownRow('Column Mode', _dmColumns.toString(), ['80', '132'], (v) { setState(() => _dmColumns = int.parse(v!)); _markDirty(); }, text),
                  const SizedBox(height: 10),
                  _buildDropdownRow('Character Set', _dmCharSet, ['Condensed', 'Normal', 'Expanded', 'Double-Height'], (v) { setState(() => _dmCharSet = v!); _markDirty(); }, text),
                  const SizedBox(height: 10),
                  _SwitchRow(label: 'Box-Drawing Borders', value: _dmBorders, onChanged: (v) { setState(() => _dmBorders = v); _markDirty(); }),
                  const SizedBox(height: 10),
                  Text('Margins (lines)', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: _buildNumberInput('Top', _dmMarginTop, (v) { _dmMarginTop = v; _markDirty(); }, text)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildNumberInput('Bottom', _dmMarginBottom, (v) { _dmMarginBottom = v; _markDirty(); }, text)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildNumberInput('Left', _dmMarginLeft, (v) { _dmMarginLeft = v; _markDirty(); }, text)),
                    ],
                  ),
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
                      if (!_isTemplateDefault(_dmLines, _getDefaultDmLines()))
                        TextButton.icon(
                          onPressed: () { setState(() => _dmLines = _getDefaultDmLines()); _markDirty(); },
                          icon: const Icon(Icons.restore_rounded, size: 14),
                          label: const Text('Reset to Default'),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), foregroundColor: scheme.error),
                        ),
                    ],
                  ),
                ]),
                const SizedBox(height: 16),
                _Section(scheme: scheme, icon: Icons.preview_rounded, title: 'Live Preview', children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFFFDE8), borderRadius: BorderRadius.circular(8), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3))),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topLeft,
                      child: Text(
                        _generateDmPreview(),
                        softWrap: false,
                        style: const TextStyle(fontFamily: 'Courier', fontSize: 12, height: 1.4, color: Color(0xFF1A1A1A)),
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

  String _generateDmPreview() {
    final buf = StringBuffer();
    final cols = _dmColumns;
    final usableWidth = cols - _dmMarginLeft;
    for (var i = 0; i < _dmMarginTop; i++) {
      buf.writeln();
    }
    final leftPad = ' ' * _dmMarginLeft;

    String formatLine(String content, String align, String style, int usable) {
      if (style == 'separator') {
        return '-' * usable;
      }
      if (style == 'blank') {
        return ' ' * usable;
      }
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
      return formatted.padRight(usable);
    }

    // Render lines — grouped lines render side-by-side, ungrouped render full-width
    var i = 0;
    while (i < _dmLines.length) {
      final line = _dmLines[i];
      final group = line['group'] as int? ?? 0;

      if (group > 0) {
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
          final content = gl['text'] as String? ?? '';
          final align = gl['align'] as String? ?? 'left';
          final style = gl['style'] as String? ?? 'normal';
          rowBuf.write(formatLine(content, align, style, colWidth));
        }
        buf.writeln(rowBuf.toString());
      } else {
        final content = line['text'] as String? ?? '';
        final align = line['align'] as String? ?? 'left';
        final style = line['style'] as String? ?? 'normal';
        buf.writeln('$leftPad${formatLine(content, align, style, usableWidth)}');
        i++;
      }
    }

    for (var i = 0; i < _dmMarginBottom; i++) {
      buf.writeln();
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
                  _buildDropdownRow('Paper Width', _thermalWidth, ['58mm', '80mm'], (v) { setState(() => _thermalWidth = v!); _markDirty(); }, text),
                  const SizedBox(height: 10),
                  _buildDropdownRow('Print Columns', _thermalColumnCount.toString(), ['1', '2'], (v) { setState(() => _thermalColumnCount = int.parse(v!)); _markDirty(); }, text),
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
                  _buildDropdownRow('Font Size', '${_thermalFontSize}pt', ['8pt', '10pt', '12pt', '14pt', '16pt'], (v) { setState(() => _thermalFontSize = int.parse(v!.replaceAll('pt', ''))); _markDirty(); }, text),
                  const SizedBox(height: 10),
                  _buildDropdownRow('Cut Mode', _thermalCutMode, ['Full', 'Partial', 'None'], (v) { setState(() => _thermalCutMode = v!); _markDirty(); }, text),
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
                  ..._thermalLines.asMap().entries.map((e) => _ThermalLineEditor(
                    index: e.key,
                    line: e.value,
                    colCount: _thermalColumnCount,
                    onChanged: (updated) { setState(() => _thermalLines[e.key] = updated); _markDirty(); },
                    onRemove: () { setState(() => _thermalLines.removeAt(e.key)); _markDirty(); },
                    onMoveUp: e.key > 0 ? () { setState(() { final item = _thermalLines.removeAt(e.key); _thermalLines.insert(e.key - 1, item); }); _markDirty(); } : null,
                    onMoveDown: e.key < _thermalLines.length - 1 ? () { setState(() { final item = _thermalLines.removeAt(e.key); _thermalLines.insert(e.key + 1, item); }); _markDirty(); } : null,
                  )),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () { setState(() => _thermalLines.add({'text': '', 'align': 'left', 'size': 'normal', 'col': 1})); _markDirty(); },
                        icon: const Icon(Icons.add_rounded, size: 14),
                        label: const Text('Add Line'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      ),
                      const SizedBox(width: 8),
                      if (!_isTemplateDefault(_thermalLines, _getDefaultThermalLines()))
                        TextButton.icon(
                          onPressed: () { setState(() => _thermalLines = _getDefaultThermalLines()); _markDirty(); },
                          icon: const Icon(Icons.restore_rounded, size: 14),
                          label: const Text('Reset to Default'),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), foregroundColor: scheme.error),
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
              child: Container(
                width: _thermalLogoWidth * 0.5 * scale,
                height: _thermalLogoHeight * 0.5 * scale,
                margin: EdgeInsets.only(bottom: 6 * scale),
                decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
                child: Icon(Icons.image_rounded, size: 9 * scale, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
              ),
            ),
          if (_thermalColumnCount > 1) ...[
            ..._buildThermalMultiColumn(text, scale: scale),
          ] else ...[
            ..._thermalLines.map((line) => _buildThermalPreviewLine(line, text, scale: scale)),
          ],
          if (_thermalPdf417) ...[
            SizedBox(height: 6 * scale),
            Container(
              height: 22 * scale,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: const Color(0xFFDDDDDD)),
              ),
              child: Center(child: Text('║║║║ PDF417 ║║║║', style: TextStyle(fontFamily: 'monospace', fontSize: 8 * scale, color: const Color(0xFF555555), letterSpacing: 0.5))),
            ),
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

  List<Widget> _buildThermalMultiColumn(TextTheme text, {double scale = 1.0}) {
    final lines = _thermalLines.toList();
    final colCount = _thermalColumnCount.clamp(1, 2);

    final colLines = List.generate(colCount, (_) => <Map<String, dynamic>>[]);
    for (final line in lines) {
      final assignedCol = ((line['col'] as int? ?? 1) - 1).clamp(0, colCount - 1);
      colLines[assignedCol].add(line);
    }
    final maxRows = colLines.map((l) => l.length).fold(0, (a, b) => a > b ? a : b);

    final rows = <Widget>[];
    for (var row = 0; row < maxRows; row++) {
      final rowChildren = <Widget>[];
      for (var c = 0; c < colCount; c++) {
        if (row < colLines[c].length) {
          rowChildren.add(Expanded(child: _buildThermalPreviewLine(colLines[c][row], text, scale: scale)));
        } else {
          rowChildren.add(const Expanded(child: SizedBox()));
        }
      }
      rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: rowChildren));
    }
    return rows;
  }

  Widget _buildThermalPreviewLine(Map<String, dynamic> line, TextTheme text, {double scale = 1.0}) {
    final content = line['text'] as String? ?? '';
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

    double fontSize;
    FontWeight fw;
    switch (size) {
      case 'bold': fontSize = 11 * scale; fw = FontWeight.w700; break;
      case 'double': fontSize = 14 * scale; fw = FontWeight.w800; break;
      default: fontSize = 11 * scale; fw = FontWeight.w400;
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 1 * scale),
      child: Text(content, textAlign: ta, style: TextStyle(fontFamily: 'monospace', fontSize: fontSize, fontWeight: fw, color: const Color(0xFF1A1A1A))),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NORMAL PRINTER TAB
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
                  _buildDropdownRow('Orientation', _normalOrientation, ['Portrait', 'Landscape'], (v) { setState(() => _normalOrientation = v!); _markDirty(); }, text),
                  const SizedBox(height: 12),
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
                  _buildDropdownRow('Font Size', '${_normalFontSize}pt', ['8pt', '9pt', '10pt', '11pt', '12pt', '14pt', '16pt', '18pt'], (v) { setState(() => _normalFontSize = int.parse(v!.replaceAll('pt', ''))); _markDirty(); }, text),
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
                  _SwitchRow(label: 'Include Custom Fields', value: _normalCustomFields, onChanged: (v) { setState(() => _normalCustomFields = v); _markDirty(); }),
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
                      if (!_isTemplateDefault(_normalLines, _getDefaultNormalLines()))
                        TextButton.icon(
                          onPressed: () { setState(() => _normalLines = _getDefaultNormalLines()); _markDirty(); },
                          icon: const Icon(Icons.restore_rounded, size: 14),
                          label: const Text('Reset to Default'),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), foregroundColor: scheme.error),
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
    final isLandscape = _normalOrientation == 'Landscape';

    double paperW, paperH;
    switch (_normalPaperSize) {
      case 'A5': paperW = 148; paperH = 210; break;
      case 'Letter': paperW = 216; paperH = 279; break;
      case 'Legal': paperW = 216; paperH = 356; break;
      default: paperW = 210; paperH = 297;
    }
    if (isLandscape) { final tmp = paperW; paperW = paperH; paperH = tmp; }

    final previewW = enlarged ? 500.0 : 280.0;
    final aspectRatio = paperW / paperH;
    final previewH = previewW / aspectRatio;
    final scale = previewW / paperW;
    final fontScale = scale;

    final contentWidgets = <Widget>[];

    // Logo (stacked: logo above lines)
    if (_normalLogo && _headerLayout == 'stacked') {
      contentWidgets.add(Center(
        child: Container(
          width: _normalLogoWidth * 0.4 * scale,
          height: _normalLogoHeight * 0.4 * scale,
          margin: EdgeInsets.only(bottom: 4 * scale),
          decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(3), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3))),
          child: Icon(Icons.image_rounded, size: 10 * fontScale, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
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
          while (hi < _normalLines.length && (_normalLines[hi]['group'] as int? ?? 0) == hGroup) {
            gLines.add(_normalLines[hi]);
            hi++;
          }
          headerLineWidgets.add(Padding(
            padding: EdgeInsets.symmetric(vertical: 0.3 * scale),
            child: Row(children: gLines.map((gl) => Expanded(child: _buildNormalPreviewLine(gl, fontScale, scheme))).toList()),
          ));
        } else {
          final hStyle = hLine['style'] as String? ?? 'normal';
          if (hStyle == 'blank') {
            headerLineWidgets.add(SizedBox(height: 3 * scale));
          } else {
            headerLineWidgets.add(Padding(
              padding: EdgeInsets.symmetric(vertical: 0.3 * scale),
              child: _buildNormalPreviewLine(hLine, fontScale, scheme),
            ));
          }
          hi++;
        }
        rowsConsumed++;
      }
      inlineHeaderConsumed = hi;
      contentWidgets.add(Padding(
        padding: EdgeInsets.only(bottom: 4 * scale),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: _normalLogoWidth * 0.4 * scale,
              height: _normalLogoHeight * 0.4 * scale,
              margin: EdgeInsets.only(right: 6 * scale),
              decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(3), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3))),
              child: Icon(Icons.image_rounded, size: 8 * fontScale, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
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
        while (i < _normalLines.length && (_normalLines[i]['group'] as int? ?? 0) == group) {
          groupLines.add(_normalLines[i]);
          i++;
        }
        contentWidgets.add(Padding(
          padding: EdgeInsets.symmetric(vertical: 0.3 * scale),
          child: Row(
            children: groupLines.map((gl) {
              return Expanded(child: _buildNormalPreviewLine(gl, fontScale, scheme));
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
            child: _buildNormalPreviewLine(line, fontScale, scheme),
          ));
        }
        i++;
      }
    }

    // PDF417 after text
    if (_normalPdf417 && _normalPdf417Position == 'afterText') {
      contentWidgets.add(Container(
        height: 16 * fontScale,
        width: double.infinity,
        margin: EdgeInsets.symmetric(vertical: 4 * scale),
        decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(2), border: Border.all(color: const Color(0xFFDDDDDD))),
        child: Center(child: Text('║║║║ PDF417 ║║║║', style: TextStyle(fontFamily: 'monospace', fontSize: 6 * fontScale, color: const Color(0xFF555555)))),
      ));
    }

    // CCTV snapshots
    if (_normalCctv && _normalCctvCameras.isNotEmpty) {
      final maxCams = _normalPaperSize == 'Legal' ? 6 : 4;
      final cameras = _normalCctvCameras.take(maxCams).toList();
      contentWidgets.add(SizedBox(height: 4 * scale));
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

    // PDF417 at bottom
    if (_normalPdf417 && _normalPdf417Position == 'bottom') {
      contentWidgets.add(Container(
        height: 16 * fontScale,
        width: double.infinity,
        margin: EdgeInsets.only(top: 4 * scale),
        decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(2), border: Border.all(color: const Color(0xFFDDDDDD))),
        child: Center(child: Text('║║║║ PDF417 ║║║║', style: TextStyle(fontFamily: 'monospace', fontSize: 6 * fontScale, color: const Color(0xFF555555)))),
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

  Widget _buildNormalPreviewLine(Map<String, dynamic> line, double fontScale, ColorScheme scheme) {
    final content = line['text'] as String? ?? '';
    final align = line['align'] as String? ?? 'left';
    final style = line['style'] as String? ?? 'normal';

    TextAlign ta;
    switch (align) {
      case 'center': ta = TextAlign.center; break;
      case 'right': ta = TextAlign.right; break;
      default: ta = TextAlign.left;
    }

    final baseFontSize = _normalFontSize * 0.35 * fontScale;
    double fontSize;
    FontWeight fw;
    switch (style) {
      case 'bold': fontSize = baseFontSize + (1 * 0.35 * fontScale); fw = FontWeight.w700; break;
      case 'double': fontSize = baseFontSize + (2 * 0.35 * fontScale); fw = FontWeight.w800; break;
      default: fontSize = baseFontSize; fw = FontWeight.w400;
    }

    return Text(content, textAlign: ta, style: TextStyle(fontSize: fontSize, fontWeight: fw, color: const Color(0xFF1A1A1A)));
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
        return StatefulBuilder(builder: (ctx, setD) {
          return AlertDialog(
            title: const Row(children: [Icon(Icons.print_rounded, size: 20), SizedBox(width: 8), Text('Manage Printers')]),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...printers.asMap().entries.map((e) {
                    final p = e.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: TextEditingController(text: p['name'] as String? ?? ''),
                              onChanged: (v) => printers[e.key]['name'] = v,
                              decoration: const InputDecoration(hintText: 'Printer name', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              initialValue: p['type'] as String? ?? 'normal',
                              items: const [
                                DropdownMenuItem(value: 'dotMatrix', child: Text('Dot Matrix', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: 'thermal', child: Text('Thermal', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: 'normal', child: Text('Normal', style: TextStyle(fontSize: 12))),
                              ],
                              onChanged: (v) { setD(() => printers[e.key]['type'] = v); },
                              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: TextEditingController(text: p['address'] as String? ?? ''),
                              onChanged: (v) => printers[e.key]['address'] = v,
                              decoration: const InputDecoration(hintText: 'IP / Port', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                            ),
                          ),
                          const SizedBox(width: 6),
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
                    );
                  }),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => setD(() => printers.add({'name': '', 'type': 'normal', 'address': ''})),
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
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  setState(() => _printers = printers.where((p) => (p['name'] as String?)?.isNotEmpty == true).toList());
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
            final match = RegExp(r'^printer\s+(\S+)\s').firstMatch(line);
            if (match != null) {
              final name = match.group(1)!;
              printers.add({'name': name, 'type': 'normal', 'address': 'cups://$name'});
            }
          }
        }
        final ippResult = await Process.run('ippfind', []);
        if (ippResult.exitCode == 0) {
          final ippOutput = ippResult.stdout as String;
          for (final uri in ippOutput.split('\n').where((l) => l.trim().isNotEmpty)) {
            final uriMatch = RegExp(r'://([^/]+)').firstMatch(uri);
            final ip = uriMatch?.group(1) ?? uri;
            final exists = printers.any((p) => p['address'] == uri);
            if (!exists) {
              printers.add({'name': 'Network ($ip)', 'type': 'normal', 'address': uri});
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
              printers.add({'name': parts[1].trim(), 'type': 'normal', 'address': parts[2].trim()});
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

  List<String> get _printerNames {
    final names = _printers.map((p) => p['name'] as String? ?? 'Unnamed').toList();
    if (names.isEmpty) return ['Default Printer'];
    return names;
  }

  Widget _buildPrinterAssignmentBar(ColorScheme scheme, TextTheme text) {
    final printerOptions = ['default', ..._printerNames];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.print_rounded, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Text('Printer Assignment', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 24),
            // Gross weighment printer
            Text('1st Weighment:', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            _MiniPrinterDropdown(
              value: _grossPrinter,
              items: printerOptions,
              onChanged: (v) { setState(() => _grossPrinter = v); _markDirty(); },
            ),
            const SizedBox(width: 20),
            // Tare weighment printer
            Text('2nd Weighment:', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            _MiniPrinterDropdown(
              value: _tarePrinter,
              items: printerOptions,
              onChanged: (v) { setState(() => _tarePrinter = v); _markDirty(); },
            ),
            const SizedBox(width: 20),
            // Backup
            _CompactToggle(label: 'Backup', value: _backupEnabled, onChanged: (v) { setState(() => _backupEnabled = v); _markDirty(); }),
            if (_backupEnabled) ...[
              const SizedBox(width: 8),
              _MiniPrinterDropdown(
                value: _backupPrinter.isEmpty ? printerOptions.first : _backupPrinter,
                items: printerOptions,
                onChanged: (v) { setState(() => _backupPrinter = v); _markDirty(); },
              ),
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
                  setState(() => _materialPrinterRules.add({'material': '', 'printer': 'default'}));
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
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 180,
                      child: TextField(
                        controller: TextEditingController(text: material),
                        style: text.bodySmall,
                        onChanged: (v) { setState(() => _materialPrinterRules[e.key] = {...rule, 'material': v}); _markDirty(); },
                        decoration: InputDecoration(
                          hintText: 'Material name',
                          hintStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
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
        SizedBox(width: 120, child: Text(label, style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: value,
            items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: text.bodySmall))).toList(),
            onChanged: onChanged,
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
            Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
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
  final int colCount;

  const _ThermalLineEditor({required this.index, required this.line, required this.onChanged, required this.onRemove, this.onMoveUp, this.onMoveDown, this.colCount = 1});

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
    final col = (widget.line['col'] as int? ?? 1).clamp(1, widget.colCount);
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
          if (widget.colCount > 1) ...[
            const SizedBox(width: 4),
            _MiniDropdown(value: 'C$col', items: List.generate(widget.colCount, (i) => 'C${i + 1}'), onChanged: (v) => widget.onChanged({...widget.line, 'col': int.parse(v.substring(1))})),
          ],
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
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e == 'default' ? 'Default' : e, style: const TextStyle(fontSize: 11)))).toList(),
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
