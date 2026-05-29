import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:weighbridgemanagement/shared/providers/camera_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/widgets/weighbridge_context_bar.dart';
import 'package:weighbridgemanagement/shared/providers/general_settings_provider.dart';
import 'package:weighbridgemanagement/shared/providers/print_provider.dart';
import 'package:weighbridgemanagement/shared/providers/scale_provider.dart';
import 'package:weighbridgemanagement/shared/providers/security_provider.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/app_loading.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';

// ─── Providers ──────────────────────────────────────────────────────────────

final _printSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  final doc = await db.printingSettings.get();
  return doc.exists ? doc.data()! : {};
});

final _companyLogoProvider = FutureProvider<Uint8List?>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  final doc = await db.generalDocsSettings.get();
  if (!doc.exists) return null;
  final dataUri = doc.data()?['company_logo'] as String?;
  if (dataUri == null || !dataUri.startsWith('data:')) return null;
  final b64 = dataUri.split(',').last;
  return base64Decode(b64);
});


final _companyInfoProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  final doc = await db.generalSettings.get();
  final data = doc.exists ? Map<String, dynamic>.from(doc.data()!) : <String, dynamic>{};
  if ((data['companyName'] as String? ?? '').isEmpty ||
      (data['address1'] as String? ?? '').isEmpty) {
    try {
      final companyDoc = await db.firestore.doc(db.context.companyPath).get();
      if (companyDoc.exists) {
        final cd = companyDoc.data()!;
        if ((data['companyName'] as String? ?? '').isEmpty) data['companyName'] = cd['name'] ?? '';
        if ((data['address1'] as String? ?? '').isEmpty) data['address1'] = cd['address1'] ?? '';
        if ((data['address2'] as String? ?? '').isEmpty) data['address2'] = cd['address2'] ?? '';
      }
    } catch (_) {}
  }
  return data;
});

final _customFieldsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  final doc = await db.customFieldsSettings.get();
  if (!doc.exists) return [];
  final fields = doc.data()?['fields'] as List<dynamic>?;
  if (fields == null) return [];
  return fields
      .map((f) => Map<String, dynamic>.from(f as Map))
      .where((f) => f['enabled'] == true && (f['label'] as String?)?.isNotEmpty == true)
      .toList();
});

final _materialsProvider = StreamProvider<List<String>>((ref) {
  final db = ref.watch(firestorePathsProvider);
  return db.materials.orderBy('order').snapshots().map(
    (snap) => snap.docs.map((d) => d.data()['name'] as String? ?? '').where((n) => n.isNotEmpty).toList(),
  );
});

class _DmPreviewSegment {
  final String text;
  final bool bold;
  final bool doubleWidth;
  const _DmPreviewSegment(this.text, {this.bold = false, this.doubleWidth = false});
}

class _DmPreviewLine {
  final List<_DmPreviewSegment> segments;
  const _DmPreviewLine(this.segments);

  factory _DmPreviewLine.simple(String text, bool bold) =>
      _DmPreviewLine([_DmPreviewSegment(text, bold: bold)]);
}

// ─── Placeholders ───────────────────────────────────────────────────────────

class _Placeholder {
  final String key;
  final String label;
  final String category;

  const _Placeholder(this.key, this.label, this.category);
}

const _builtInPlaceholders = [
  // Company
  _Placeholder('{company_name}', 'Name', 'Company'),
  _Placeholder('{company_address1}', 'Address Line 1', 'Company'),
  _Placeholder('{company_address2}', 'Address Line 2', 'Company'),
  _Placeholder('{company_phone}', 'Phone', 'Company'),
  _Placeholder('{company_email}', 'Email', 'Company'),
  _Placeholder('{company_gstin}', 'GSTIN', 'Company'),
  _Placeholder('{company_pan}', 'PAN', 'Company'),
  // Customer
  _Placeholder('{customer_name}', 'Name', 'Customer'),
  _Placeholder('{customer_address}', 'Address', 'Customer'),
  _Placeholder('{customer_phone}', 'Phone', 'Customer'),
  // Weighment
  _Placeholder('{vehicle}', 'Vehicle Number', 'Weighment'),
  _Placeholder('{material}', 'Material', 'Weighment'),
  _Placeholder('{gross}', 'Gross Weight (includes KG)', 'Weighment'),
  _Placeholder('{tare}', 'Tare Weight (includes KG)', 'Weighment'),
  _Placeholder('{net}', 'Net Weight (includes KG)', 'Weighment'),
  _Placeholder('{gross_datetime}', 'Gross Date & Time', 'Weighment'),
  _Placeholder('{gross_date}', 'Gross Date', 'Weighment'),
  _Placeholder('{gross_time}', 'Gross Time', 'Weighment'),
  _Placeholder('{tare_datetime}', 'Tare Date & Time', 'Weighment'),
  _Placeholder('{tare_date}', 'Tare Date', 'Weighment'),
  _Placeholder('{tare_time}', 'Tare Time', 'Weighment'),
  _Placeholder('{net_datetime}', 'Net Date & Time', 'Weighment'),
  _Placeholder('{net_date}', 'Net Date', 'Weighment'),
  _Placeholder('{net_time}', 'Net Time', 'Weighment'),
  _Placeholder('{rst}', 'RST Number', 'Weighment'),
  _Placeholder('{operator}', 'Operator', 'Weighment'),
  _Placeholder('{status}', 'Status', 'Weighment'),
  _Placeholder('{weigh_type}', 'First Weigh Type', 'Weighment'),
  // System
  _Placeholder('{date}', 'Current Date', 'System'),
  _Placeholder('{time}', 'Current Time', 'System'),
  _Placeholder('{pc_name}', 'PC Name', 'System'),
  _Placeholder('{port_name}', 'Scale Port', 'System'),
  _Placeholder('{weighbridge_name}', 'Weighbridge', 'System'),
  _Placeholder('{site_name}', 'Site Name', 'System'),
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
  String _savedSnapshot = '';
  bool get _dirty => _savedSnapshot.isNotEmpty && _savedSnapshot != jsonEncode(_buildPayload());
  bool _normalOverflows = false;
  late TabController _tabController;

  String? _headerMsg;
  bool _headerMsgIsError = false;

  // ── Printers ──
  List<Map<String, dynamic>> _printers = [];
  Map<String, List<String>> _printerTrays = {};

  // ── Printer Assignment ──
  String _grossPrinter = 'default';
  String _grossTray = '';
  String _grossPaperSize = '';
  String _tarePrinter = 'default';
  String _tareTray = '';
  String _tarePaperSize = '';
  String _backupPrinter = '';
  String _backupTray = '';
  String _backupPaperSize = '';
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

  Map<String, String> _getTrayMapping(String printerName) {
    for (final p in _printers) {
      final nickname = p['nickname'] as String? ?? '';
      final sysName = p['name'] as String? ?? '';
      final match = nickname.isNotEmpty ? nickname : sysName;
      if (match == printerName) {
        final mapping = p['trayMapping'] as Map<String, dynamic>?;
        return mapping?.map((k, v) => MapEntry(k, v as String)) ?? {};
      }
    }
    return {};
  }

  List<String> _getAvailableSizesForPrinter(String printerName) {
    final mapping = _getTrayMapping(printerName);
    if (mapping.isEmpty) return [];
    final sizes = <String>{};
    for (final size in mapping.values) {
      if (size == 'Dynamic') {
        sizes.addAll(['A4', 'A5', 'Letter', 'Legal']);
      } else {
        sizes.add(size);
      }
    }
    return sizes.toList();
  }

  String _resolveTrayForSize(String printerName, String paperSize) {
    final mapping = _getTrayMapping(printerName);
    for (final entry in mapping.entries) {
      if (entry.value == paperSize) return entry.key;
    }
    for (final entry in mapping.entries) {
      if (entry.value == 'Dynamic') return entry.key;
    }
    return '';
  }

  Future<void> _loadPrinterTrays() async {
    final trays = <String, List<String>>{};
    for (final p in _printers) {
      final name = p['name'] as String? ?? '';
      if (name.isEmpty) continue;
      try {
        if (Platform.isWindows) {
          // Try multiple methods to detect trays
          final result = await Process.run('powershell', ['-NoProfile', '-Command', '''
\$bins = @()
# Method 1: WMI PrinterConfiguration
try {
  \$wmi = Get-CimInstance -ClassName Win32_PrinterConfiguration -Filter "Name='$name'" -ErrorAction Stop
  if (\$wmi.PaperSources) { \$bins += \$wmi.PaperSources }
} catch {}
# Method 2: PrinterProperty InputBin
try {
  \$props = Get-PrinterProperty -PrinterName "$name" -ErrorAction Stop
  \$ib = \$props | Where-Object { \$_.PropertyName -match "InputBin|InputSlot|TraySelect" }
  foreach (\$p in \$ib) {
    if (\$p.Type -eq "PickOne" -and \$p.Value) { \$bins += \$p.Value }
  }
} catch {}
# Method 3: Enumerate all properties containing Tray/Bin
if (\$bins.Count -eq 0) {
  try {
    \$props = Get-PrinterProperty -PrinterName "$name" -ErrorAction Stop
    \$trayProps = \$props | Where-Object { \$_.PropertyName -match "Tray|Bin|Cassette" -and \$_.Type -eq "PickOne" }
    foreach (\$p in \$trayProps) { \$bins += \$p.PropertyName + "=" + \$p.Value }
  } catch {}
}
# Method 4: devmode paper sources via .NET
if (\$bins.Count -eq 0) {
  try {
    Add-Type -AssemblyName System.Drawing
    \$ps = New-Object System.Drawing.Printing.PrinterSettings
    \$ps.PrinterName = "$name"
    foreach (\$s in \$ps.PaperSources) { \$bins += \$s.SourceName }
  } catch {}
}
\$bins | Select-Object -Unique | ForEach-Object { Write-Output \$_ }
'''
          ]);
          if (result.exitCode == 0) {
            final output = (result.stdout as String).trim();
            if (output.isNotEmpty) {
              final options = output.split(RegExp(r'[\r\n]+')).map((o) => o.trim()).where((o) => o.isNotEmpty).toList();
              if (options.length > 0) trays[name] = options;
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
    if (mounted) {
      setState(() {
        _printerTrays = trays;
        for (final p in _printers) {
          final name = p['name'] as String? ?? '';
          final detected = trays[name];
          if (detected == null || detected.isEmpty) continue;
          final mapping = Map<String, dynamic>.from((p['trayMapping'] as Map<String, dynamic>?) ?? {});
          var changed = false;
          final defaultSize = detected.length > 1 ? _normalPaperSize : 'Dynamic';
          for (final tray in detected) {
            if (!mapping.containsKey(tray)) {
              mapping[tray] = defaultSize;
              changed = true;
            }
          }
          if (changed) p['trayMapping'] = mapping;
        }
      });
    }
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
  int _maxReprints = 2;

  // ── Dot Matrix ──
  double _dmPaperWidth = 8.0; // inches
  int get _dmColumns => (_dmPaperWidth * _dmCpi).round();
  double _dmPageHeight = 4.0; // cut length in inches
  int _dmMarginTop = 1;
  int _dmMarginBottom = 1;
  int _dmMarginLeft = 2;
  bool _dmLogo = false;
  double _dmLogoAspectRatio = 2.0; // width / height of original logo image
  int _dmLogoHeight = 6;
  // Physical width = (height_lines / lpi) * aspect_ratio inches, expressed as chars at 10 CPI
  int get _dmLogoWidth => ((_dmLogoHeight.toDouble() / _dmLpi) * _dmLogoAspectRatio * 10).round().clamp(4, 80);
  bool _dmPdf417 = true;
  double _dmPdf417Height = 0.8; // inches (0.5 to 1.0)
  List<Map<String, dynamic>> _dmLines = [];

  // ── Dot Matrix Paper Handling ──
  int _dmFeedAfterPrint = 0;
  bool _dmFormFeed = false;
  int _dmTopMargin = 0;
  bool _dmTearOffAdvance = false;
  int _dmCpi = 10;
  int _dmLpi = 6;
  String _dmPrintQuality = 'draft';

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
  double _thermalLogoWidth = 160;
  double _thermalLogoHeight = 160;
  double _normalLogoWidth = 80;
  double _normalLogoHeight = 80;

  // ── Font ──
  int _normalFontSize = 14;
  String _normalFont = 'Helvetica';

  // ── Multi-column ──
  int _dmColumnCount = 1;

  // ── Normal ──
  String _normalPaperSize = 'A4';
  double _normalMarginTop = 10;
  double _normalMarginBottom = 10;
  double _normalMarginLeft = 10;
  double _normalMarginRight = 10;
  bool _normalLogo = true;
  bool _normalPdf417 = true;
  String _normalPdf417Position = 'bottom';
  bool _normalCctv = false;
  List<String> _normalCctvCameras = [];
  List<Map<String, dynamic>> _normalLines = [];

  // Per-size config store (normal printer)
  final Map<String, Map<String, dynamic>> _perSizeConfigs = {};

  // Per-width config store (thermal printer)
  final Map<String, Map<String, dynamic>> _perThermalWidthConfigs = {};

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
    'cctvMaxSlots': 2,
    'fontSize': _normalFontSize,
    'normalLines': _normalLines.map((l) => Map<String, dynamic>.from(l)).toList(),
  };

  void _applySizeConfig(Map<String, dynamic> cfg) {
    _normalMarginTop = (cfg['marginTop'] as num?)?.toDouble() ?? 10;
    _normalMarginBottom = (cfg['marginBottom'] as num?)?.toDouble() ?? 10;
    _normalMarginLeft = (cfg['marginLeft'] as num?)?.toDouble() ?? 10;
    _normalMarginRight = (cfg['marginRight'] as num?)?.toDouble() ?? 10;
    _headerLayout = 'inline';
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
          'marginTop': 5.0, 'marginBottom': 5.0, 'marginLeft': 5.0, 'marginRight': 5.0,
          'headerLayout': 'inline', 'headerRows': 3,
          'logo': true, 'logoWidth': 50.0, 'logoHeight': 50.0,
          'pdf417': true, 'pdf417Position': 'bottom',
          'cctv': true, 'cctvCameras': <String>[], 'cctvMaxSlots': 2,
          'fontSize': 10,
          'normalLines': _getDefaultNormalLines(paperSize: 'A5'),
        };
      case 'Legal':
        return {
          'marginTop': 10.0, 'marginBottom': 10.0, 'marginLeft': 10.0, 'marginRight': 10.0,
          'headerLayout': 'inline', 'headerRows': 3,
          'logo': true, 'logoWidth': 90.0, 'logoHeight': 90.0,
          'pdf417': true, 'pdf417Position': 'bottom',
          'cctv': true, 'cctvCameras': <String>[], 'cctvMaxSlots': 2,
          'fontSize': 16,
          'normalLines': _getDefaultNormalLines(paperSize: 'Legal'),
        };
      case 'Letter':
        return {
          'marginTop': 15.0, 'marginBottom': 15.0, 'marginLeft': 15.0, 'marginRight': 15.0,
          'headerLayout': 'inline', 'headerRows': 4,
          'logo': true, 'logoWidth': 80.0, 'logoHeight': 80.0,
          'pdf417': true, 'pdf417Position': 'bottom',
          'cctv': true, 'cctvCameras': <String>[], 'cctvMaxSlots': 2,
          'fontSize': 14,
          'normalLines': _getDefaultNormalLines(paperSize: 'Letter'),
        };
      default: // A4
        return {
          'marginTop': 10.0, 'marginBottom': 10.0, 'marginLeft': 10.0, 'marginRight': 10.0,
          'headerLayout': 'inline', 'headerRows': 3,
          'logo': true, 'logoWidth': 80.0, 'logoHeight': 80.0,
          'pdf417': true, 'pdf417Position': 'bottom',
          'cctv': true, 'cctvCameras': <String>[], 'cctvMaxSlots': 2,
          'fontSize': 16,
          'normalLines': _getDefaultNormalLines(paperSize: 'A4'),
        };
    }
  }

  Map<String, dynamic> _getCurrentThermalWidthConfig() => {
    'logo': _thermalLogo,
    'logoWidth': _thermalLogoWidth,
    'logoHeight': _thermalLogoHeight,
    'pdf417': _thermalPdf417,
    'cutMode': _thermalCutMode,
    'fontSize': _thermalFontSize,
    'font': _thermalFont,
    'thermalLines': _thermalLines.map((l) => Map<String, dynamic>.from(l)).toList(),
  };

  void _applyThermalWidthConfig(Map<String, dynamic> cfg) {
    _thermalLogo = cfg['logo'] as bool? ?? true;
    _thermalLogoWidth = (cfg['logoWidth'] as num?)?.toDouble() ?? 160;
    _thermalLogoHeight = (cfg['logoHeight'] as num?)?.toDouble() ?? 160;
    _thermalPdf417 = cfg['pdf417'] as bool? ?? true;
    _thermalCutMode = cfg['cutMode'] as String? ?? 'Full';
    _thermalFontSize = cfg['fontSize'] as int? ?? 12;
    _thermalFont = cfg['font'] as String? ?? 'Font A';
    final lines = cfg['thermalLines'] as List?;
    _thermalLines = lines != null
        ? lines.map((l) => Map<String, dynamic>.from(l as Map)).toList()
        : _getDefaultThermalLines(width: _thermalWidth);
  }

  static Map<String, dynamic> _getDefaultThermalWidthConfig(String width) {
    if (width == '58mm') {
      return {
        'logo': true, 'logoWidth': 160.0, 'logoHeight': 160.0,
        'pdf417': true, 'cutMode': 'Full',
        'fontSize': 12, 'font': 'Font A',
        'thermalLines': _getDefaultThermalLines(width: '58mm'),
      };
    }
    return {
      'logo': true, 'logoWidth': 200.0, 'logoHeight': 200.0,
      'pdf417': true, 'cutMode': 'Full',
      'fontSize': 14, 'font': 'Font A',
      'thermalLines': _getDefaultThermalLines(width: '80mm'),
    };
  }

  void _switchThermalWidth(String newWidth) {
    _perThermalWidthConfigs[_thermalWidth] = _getCurrentThermalWidthConfig();
    _thermalWidth = newWidth;
    if (_perThermalWidthConfigs.containsKey(newWidth)) {
      _applyThermalWidthConfig(_perThermalWidthConfigs[newWidth]!);
    } else {
      _applyThermalWidthConfig(_getDefaultThermalWidthConfig(newWidth));
    }
    _syncTemplateToPrinters('thermal', thermalWidth: newWidth);
  }

  void _switchPaperSize(String newSize) {
    _perSizeConfigs[_normalPaperSize] = _getCurrentSizeConfig();
    _normalPaperSize = newSize;
    if (_perSizeConfigs.containsKey(newSize)) {
      _applySizeConfig(_perSizeConfigs[newSize]!);
    } else {
      _applySizeConfig(_getDefaultSizeConfig(newSize));
    }
    // Clean up any cameras no longer in configured set
    // (resolved dynamically at print time from activeWeighbridgeCamerasProvider)
    _syncTemplateToPrinters('normal', paperSize: newSize);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initDefaults();
  }

  void _initDefaults() {
    _dmPaperWidth = 8.0;
    _dmPageHeight = 4.0;
    _dmLogo = false;
    _dmLogoHeight = 10;
    _dmPdf417 = true;
    _dmPdf417Height = 0.8;
    _dmMarginTop = 1;
    _dmMarginBottom = 1;
    _dmMarginLeft = 2;
    _dmFeedAfterPrint = 0;
    _dmFormFeed = false;
    _dmTopMargin = 0;
    _dmTearOffAdvance = false;
    _dmCpi = 10;
    _dmLpi = 6;
    _dmPrintQuality = 'draft';
    _dmLines = _getDefaultDmLines(columns: 100);
    _thermalLines = _getDefaultThermalLines(width: _thermalWidth);
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
      {'text': 'Gross: {gross}', 'align': 'left', 'style': 'normal', 'group': 4},
      {'text': '({gross_datetime})', 'align': 'left', 'style': 'normal', 'group': 4},
      {'text': 'Tare: {tare}', 'align': 'left', 'style': 'normal', 'group': 5},
      {'text': '({tare_datetime})', 'align': 'left', 'style': 'normal', 'group': 5},
      {'text': 'Net: {net}', 'align': 'left', 'style': 'bold', 'group': 6},
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

  static List<Map<String, dynamic>> _getDefaultThermalLines({String width = '80mm'}) => [
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
    {'text': 'Gross: {gross}', 'align': 'left', 'size': 'normal'},
    {'text': 'Tare: {tare}', 'align': 'left', 'size': 'normal'},
    {'text': 'Net: {net}', 'align': 'left', 'size': 'bold'},
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
      {'text': 'Gross: {gross}', 'align': 'left', 'style': 'normal', 'group': 4},
      {'text': '({gross_datetime})', 'align': 'left', 'style': 'normal', 'group': 4},
      {'text': 'Tare: {tare}', 'align': 'left', 'style': 'normal', 'group': 5},
      {'text': '({tare_datetime})', 'align': 'left', 'style': 'normal', 'group': 5},
      {'text': 'Net: {net}', 'align': 'left', 'style': 'bold', 'group': 6},
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
    if (_dmCpi != 10 || _dmPrintQuality != 'draft') return false;
    if (_dmFeedAfterPrint != 0 || _dmFormFeed || _dmTopMargin != 0 || _dmTearOffAdvance) return false;
    if (_dmPageHeight == 3.0) {
      if (_dmLogo) return false;
      if (_dmPdf417) return false;
      if (_dmLpi != 6) return false;
    } else if (_dmPageHeight == 4.0) {
      if (_dmLogo) return false;
      if (!_dmPdf417 || _dmPdf417Height != 0.8) return false;
      if (_dmLpi != 6) return false;
    } else {
      if (!_dmLogo || _dmLogoHeight != 10) return false;
      if (!_dmPdf417 || _dmPdf417Height != 1.0) return false;
      if (_dmLpi != 6) return false;
    }
    return true;
  }

  bool _isDmTemplateDefault() {
    return _isTemplateDefault(_dmLines, _getDefaultDmLines(columns: _dmColumns));
  }

  bool _isThermalConfigDefault() {
    final def = _getDefaultThermalWidthConfig(_thermalWidth);
    return _thermalLogo == def['logo'] && _thermalPdf417 == def['pdf417'] &&
        _thermalCutMode == def['cutMode'] && _thermalFontSize == def['fontSize'] &&
        _thermalFont == def['font'];
  }

  void _resetDmConfig() {
    _dmMarginTop = 1;
    _dmMarginBottom = 1;
    _dmMarginLeft = 2;
    _dmCpi = 10;
    _dmPrintQuality = 'draft';
    _dmFeedAfterPrint = 0;
    _dmFormFeed = false;
    _dmTopMargin = 0;
    _dmTearOffAdvance = false;
    if (_dmPageHeight == 3.0) {
      _dmLogo = false;
      _dmPdf417 = false;
      _dmLpi = 6;
    } else if (_dmPageHeight == 4.0) {
      _dmLogo = false;
      _dmLogoHeight = 10;
      _dmPdf417 = true;
      _dmPdf417Height = 0.8;
      _dmLpi = 6;
    } else {
      _dmLogo = true;
      _dmLogoHeight = 10;
      _dmPdf417 = true;
      _dmPdf417Height = 1.0;
      _dmLpi = 6;
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
    _grossPaperSize = data['grossPaperSize'] as String? ?? '';
    _tarePrinter = data['tarePrinter'] as String? ?? 'default';
    _tareTray = data['tareTray'] as String? ?? '';
    _tarePaperSize = data['tarePaperSize'] as String? ?? '';
    _backupPrinter = data['backupPrinter'] as String? ?? '';
    _backupTray = data['backupTray'] as String? ?? '';
    _backupPaperSize = data['backupPaperSize'] as String? ?? '';
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
    _maxReprints = data['maxReprints'] as int? ?? 2;

    _headerLayout = 'inline';
    _headerRows = data['headerRows'] as int? ?? 3;

    // Per-template Logo
    _thermalLogoWidth = (data['thermalLogoWidth'] as num?)?.toDouble() ?? 160;
    _thermalLogoHeight = (data['thermalLogoHeight'] as num?)?.toDouble() ?? 160;
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
    _dmLogoAspectRatio = (data['dmLogoAspectRatio'] as num?)?.toDouble() ?? 2.0;
    _dmLogoHeight = data['dmLogoHeight'] as int? ?? 8;
    _dmPdf417 = data['dmPdf417'] as bool? ?? (_dmPageHeight >= 4.0);
    _dmPdf417Height = (data['dmPdf417Height'] as num?)?.toDouble() ?? (_dmPageHeight >= 6.0 ? 1.0 : 0.8);
    final dmLines = data['dmLines'] as List<dynamic>?;
    if (dmLines != null) _dmLines = dmLines.map((l) => Map<String, dynamic>.from(l as Map)).toList();
    _dmFeedAfterPrint = data['dmFeedAfterPrint'] as int? ?? 0;
    _dmFormFeed = data['dmFormFeed'] as bool? ?? false;
    _dmTopMargin = data['dmTopMargin'] as int? ?? 0;
    _dmTearOffAdvance = data['dmTearOffAdvance'] as bool? ?? false;
    _dmCpi = data['dmCpi'] as int? ?? 10;
    _dmLpi = data['dmLpi'] as int? ?? 6;
    _dmPrintQuality = data['dmPrintQuality'] as String? ?? 'draft';

    // Thermal — per-width configs
    _thermalWidth = data['thermalWidth'] as String? ?? '80mm';
    final savedPerThermalWidth = data['perThermalWidthConfigs'] as Map<String, dynamic>?;
    if (savedPerThermalWidth != null) {
      for (final entry in savedPerThermalWidth.entries) {
        _perThermalWidthConfigs[entry.key] = Map<String, dynamic>.from(entry.value as Map);
      }
    }
    if (_perThermalWidthConfigs.containsKey(_thermalWidth)) {
      _applyThermalWidthConfig(_perThermalWidthConfigs[_thermalWidth]!);
    } else {
      // Legacy: load from flat keys
      _thermalLogo = data['thermalLogo'] as bool? ?? true;
      _thermalPdf417 = data['thermalPdf417'] as bool? ?? true;
      _thermalCutMode = data['thermalCutMode'] as String? ?? 'Full';
      _thermalFontSize = data['thermalFontSize'] as int? ?? 12;
      _thermalFont = data['thermalFont'] as String? ?? 'Font A';
      _thermalLogoWidth = (data['thermalLogoWidth'] as num?)?.toDouble() ?? 160;
      _thermalLogoHeight = (data['thermalLogoHeight'] as num?)?.toDouble() ?? 160;
      final tLines = data['thermalLines'] as List<dynamic>?;
      if (tLines != null) _thermalLines = tLines.map((l) => Map<String, dynamic>.from(l as Map)).toList();
    }

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
      _normalMarginTop = (data['normalMarginTop'] as num?)?.toDouble() ?? 10;
      _normalMarginBottom = (data['normalMarginBottom'] as num?)?.toDouble() ?? 10;
      _normalMarginLeft = (data['normalMarginLeft'] as num?)?.toDouble() ?? 10;
      _normalMarginRight = (data['normalMarginRight'] as num?)?.toDouble() ?? 10;
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
    _savedSnapshot = jsonEncode(_buildPayload());
  }

  void _markDirty() {
    setState(() {});
  }

  Map<String, dynamic> _buildPayload() => {
    'printers': _printers,
    'grossPrinter': _grossPrinter,
    'grossTray': _grossTray,
    'grossPaperSize': _grossPaperSize,
    'tarePrinter': _tarePrinter,
    'tareTray': _tareTray,
    'tarePaperSize': _tarePaperSize,
    'backupPrinter': _backupPrinter,
    'backupTray': _backupTray,
    'backupPaperSize': _backupPaperSize,
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
    'dmLogoAspectRatio': _dmLogoAspectRatio,
    'dmLogoWidth': _dmLogoWidth,
    'dmLogoHeight': _dmLogoHeight,
    'dmPdf417': _dmPdf417,
    'dmPdf417Height': _dmPdf417Height,
    'dmFeedAfterPrint': _dmFeedAfterPrint,
    'dmFormFeed': _dmFormFeed,
    'dmTopMargin': _dmTopMargin,
    'dmTearOffAdvance': _dmTearOffAdvance,
    'dmCpi': _dmCpi,
    'dmLpi': _dmLpi,
    'dmPrintQuality': _dmPrintQuality,
    'dmLines': _dmLines,
    'thermalWidth': _thermalWidth,
    'thermalLogo': _thermalLogo,
    'thermalPdf417': _thermalPdf417,
    'thermalCutMode': _thermalCutMode,
    'thermalFontSize': _thermalFontSize,
    'thermalFont': _thermalFont,
    'thermalLines': _thermalLines,
    'perThermalWidthConfigs': {
      ..._perThermalWidthConfigs,
      _thermalWidth: _getCurrentThermalWidthConfig(),
    },
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

  void _showHeaderMsg(String msg, {bool isError = false}) {
    setState(() { _headerMsg = msg; _headerMsgIsError = isError; });
    Future.delayed(Duration(seconds: isError ? 5 : 3), () {
      if (mounted) setState(() => _headerMsg = null);
    });
  }

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

      final db = ref.read(firestorePathsProvider);
      await db.printingSettings.set({
        ...payload,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      ref.invalidate(_printSettingsProvider);
      ref.read(auditServiceProvider).log(event: 'settingChange', description: 'Printing settings updated');

      if (mounted) {
        setState(() => _savedSnapshot = jsonEncode(_buildPayload()));
        _showHeaderMsg('Print settings saved');
      }
    } catch (e) {
      if (mounted) _showHeaderMsg('Failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testPrint(String type) async {
    try {
      await _save();
      final printService = ref.read(printServiceProvider);
      final result = await printService.testPrint(type: type);
      if (mounted) {
        _showHeaderMsg(
          result.success ? 'Test print sent' : 'Print failed: ${result.error}',
          isError: !result.success,
        );
      }
    } catch (e) {
      if (mounted) _showHeaderMsg('Print failed: $e', isError: true);
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
    final grossDateStr = '${grossTime.day.toString().padLeft(2, '0')}/${grossTime.month.toString().padLeft(2, '0')}/${grossTime.year}';
    return {
      '{company_name}': company['companyName'] as String? ?? 'Your Company Name',
      '{company_address1}': company['address1'] as String? ?? 'Address Line 1',
      '{company_address2}': company['address2'] as String? ?? 'Address Line 2',
      '{company_phone}': company['phone'] as String? ?? '+91 98765 43210',
      '{company_email}': company['email'] as String? ?? 'info@company.com',
      '{company_gstin}': company['gstin'] as String? ?? '22AAAAA0000A1Z5',
      '{company_pan}': company['pan'] as String? ?? 'AAAAA0000A',
      '{customer_name}': 'Sample Customer',
      '{customer_address}': 'Customer Address',
      '{customer_phone}': '+91 91234 56789',
      '{vehicle}': 'MH-12-AB-1234',
      '{material}': 'Iron Ore',
      '{gross}': '48,520 KG',
      '{tare}': '16,200 KG',
      '{net}': '32,320 KG',
      '{gross_datetime}': '$grossDateStr ${timeFmt.format(grossTime)}',
      '{gross_date}': grossDateStr,
      '{gross_time}': timeFmt.format(grossTime),
      '{tare_datetime}': '$dateStr ${timeFmt.format(now)}',
      '{tare_date}': dateStr,
      '{tare_time}': timeFmt.format(now),
      '{net_datetime}': '$dateStr ${timeFmt.format(now)}',
      '{net_date}': dateStr,
      '{net_time}': timeFmt.format(now),
      '{rst}': '1042',
      '{operator}': 'Rajesh Kumar',
      '{status}': 'completed',
      '{weigh_type}': 'gross',
      '{date}': dateStr,
      '{time}': timeFmt.format(now),
      '{pc_name}': Platform.localHostname,
      '{port_name}': ref.read(scaleConfigProvider).valueOrNull?.port ?? '',
      '{weighbridge_name}': company['weighbridgeName'] as String? ?? 'Weighbridge',
      '{site_name}': company['siteName'] as String? ?? 'Main Site',
    };
  }

  String _substituteLine(String text) {
    var result = text;
    final placeholders = _previewPlaceholders();
    // Align weight numbers (strip " KG", pad numbers, re-append " KG")
    final grossNum = placeholders['{gross}']!.replaceAll(' KG', '');
    final tareNum = placeholders['{tare}']!.replaceAll(' KG', '');
    final netNum = placeholders['{net}']!.replaceAll(' KG', '');
    final maxW = [grossNum.length, tareNum.length, netNum.length].reduce((a, b) => a > b ? a : b);
    final padded = Map<String, String>.from(placeholders);
    padded['{gross}'] = '${grossNum.padLeft(maxW)} KG';
    padded['{tare}'] = '${tareNum.padLeft(maxW)} KG';
    padded['{net}'] = '${netNum.padLeft(maxW)} KG';
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
          WeighbridgeContextBar(
            label: 'Printing for',
            onSwitched: () {
              ref.invalidate(_printSettingsProvider);
              ref.invalidate(_companyInfoProvider);
              ref.invalidate(_companyLogoProvider);
              setState(() => _loaded = false);
            },
          ),
          Expanded(
            child: settingsAsync.when(
              loading: () => const AppLoading(),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(onPressed: () { context.go('/settings'); }, icon: const Icon(Icons.arrow_back_rounded, size: 20), style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: AppRadius.button))),
              SizedBox(width: AppSpacing.md),
              Icon(Icons.print_rounded, size: 20, color: scheme.primary),
              SizedBox(width: 10.rs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Printing', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text('Docket layout and printers', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
              const Spacer(),
              if (_dirty) ...[
                TextButton(onPressed: () { setState(() { _loaded = false; _savedSnapshot = ''; }); ref.invalidate(_printSettingsProvider); }, child: const Text('Cancel')),
                SizedBox(width: AppSpacing.sm),
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
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
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
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DOT MATRIX TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDotMatrixTab(ColorScheme scheme, TextTheme text) {
    return SingleChildScrollView(
      padding: AppSpacing.pagePadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 320,
            child: Column(
              children: [
                _Section(scheme: scheme, icon: Icons.grid_on_rounded, title: 'Dot Matrix Configuration', children: [
                  Text('Paper Width', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  SizedBox(height: AppSpacing.xs),
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
                  SizedBox(height: 10.rs),
                  _buildDropdownRow('Cut Length', '${_dmPageHeight.toStringAsFixed(0)}″', ['3″', '4″', '6″'], (v) { setState(() { _dmPageHeight = double.parse(v!.replaceAll('″', '')); if (_dmPageHeight == 3.0) { _dmLogo = false; _dmPdf417 = false; _dmLpi = 6; } else if (_dmPageHeight == 4.0) { _dmLogo = false; _dmPdf417 = true; _dmPdf417Height = 0.8; _dmLpi = 6; _dmLogoHeight = 10; } else { _dmLogo = true; _dmPdf417 = true; _dmPdf417Height = 1.0; _dmLpi = 6; _dmLogoHeight = 10; } }); _markDirty(); }, text),
                  SizedBox(height: 10.rs),
                  SizedBox(height: 10.rs),
                  _SwitchRow(label: 'Logo (Monochrome)', value: _dmLogo, onChanged: (v) { setState(() { _dmLogo = v; }); _markDirty(); }),
                  if (_dmLogo) ...[
                    SizedBox(height: AppSpacing.sm),
                    Text('Logo Height (lines)', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(height: 6.rs),
                    Row(
                      children: [
                        SizedBox(width: 100, child: _buildNumberInput('H', _dmLogoHeight, (v) { setState(() => _dmLogoHeight = v); _markDirty(); }, text)),
                        SizedBox(width: AppSpacing.md),
                        Text('W: $_dmLogoWidth chars (auto)', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                    SizedBox(height: 6.rs),
                    Text('Width derived from logo aspect ratio. PNG → 1-bit threshold.', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
                  ],
                  SizedBox(height: 10.rs),
                  _SwitchRow(label: 'PDF417 Barcode', value: _dmPdf417, onChanged: (v) { setState(() { _dmPdf417 = v; }); _markDirty(); }),
                  if (_dmPdf417) ...[
                    SizedBox(height: 6.rs),
                    Row(
                      children: [
                        Text('Height: ${_dmPdf417Height.toStringAsFixed(2)}″', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                        SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Slider(
                            value: _dmPdf417Height,
                            min: 0.5,
                            max: 1.0,
                            divisions: 10,
                            label: '${_dmPdf417Height.toStringAsFixed(2)}″',
                            onChanged: (v) { setState(() => _dmPdf417Height = double.parse(v.toStringAsFixed(2))); _markDirty(); },
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('5″ × ${_dmPdf417Height.toStringAsFixed(2)}″ barcode after last line. Encodes weighment data.', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
                    ),
                  ],
                  SizedBox(height: 10.rs),
                  Text('Margins (lines)', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                  SizedBox(height: 6.rs),
                  Row(
                    children: [
                      Expanded(child: _buildNumberInput('Top', _dmMarginTop, (v) { _dmMarginTop = v; _markDirty(); }, text)),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(child: _buildNumberInput('Bottom', _dmMarginBottom, (v) { _dmMarginBottom = v; _markDirty(); }, text)),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(child: _buildNumberInput('L & R', _dmMarginLeft, (v) { _dmMarginLeft = v; _markDirty(); }, text)),
                    ],
                  ),
                  SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isDmConfigDefault() ? null : () { setState(_resetDmConfig); _markDirty(); },
                      icon: const Icon(Icons.settings_backup_restore_rounded, size: 16),
                      label: Text('Reset Config (${_dmPageHeight.toStringAsFixed(0)}″)'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        foregroundColor: scheme.error,
                        side: BorderSide(color: _isDmConfigDefault() ? scheme.outline.withValues(alpha: 0.2) : scheme.error.withValues(alpha: 0.5)),
                        disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                      ),
                    ),
                  ),
                  SizedBox(height: 10.rs),
                ]),
                SizedBox(height: AppSpacing.lg),
                _Section(scheme: scheme, icon: Icons.settings_ethernet_rounded, title: 'Paper Handling', children: [
                  Text(
                    'These settings control how the printer feeds and positions paper. '
                    'They send ESC/P commands to the printer — incorrect values may cause misalignment or wasted paper.',
                    style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                  ),
                  SizedBox(height: 14.rs),
                  Text('Characters Per Inch (CPI)', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  SizedBox(height: 2.rs),
                  Text('Controls how tightly characters are packed horizontally. Higher CPI = more text per line but smaller print. '
                       'Affects the column count for your template.', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  SizedBox(height: 6.rs),
                  Row(
                    children: [10, 12, 15, 17].map((cpi) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('$cpi', style: TextStyle(fontWeight: FontWeight.w600, color: _dmCpi == cpi ? scheme.onPrimary : scheme.onSurface)),
                        selected: _dmCpi == cpi,
                        selectedColor: scheme.primary,
                        backgroundColor: scheme.surfaceContainerHighest,
                        side: BorderSide(color: _dmCpi == cpi ? scheme.primary : scheme.outline.withValues(alpha: 0.4)),
                        onSelected: (sel) { if (sel) setState(() => _dmCpi = cpi); _markDirty(); },
                        visualDensity: VisualDensity.compact,
                      ),
                    )).toList(),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Current: $_dmColumns columns at $_dmCpi CPI × ${_dmPaperWidth.toStringAsFixed(1)}″', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  const Divider(height: 24),
                  Text('Lines Per Inch (LPI)', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  SizedBox(height: 2.rs),
                  Text('Controls vertical line spacing. Lower LPI = more space between lines. Affects how many lines fit on the page.', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  SizedBox(height: 6.rs),
                  Row(
                    children: [6, 8].map((lpi) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('$lpi', style: TextStyle(fontWeight: FontWeight.w600, color: _dmLpi == lpi ? scheme.onPrimary : scheme.onSurface)),
                        selected: _dmLpi == lpi,
                        selectedColor: scheme.primary,
                        backgroundColor: scheme.surfaceContainerHighest,
                        side: BorderSide(color: _dmLpi == lpi ? scheme.primary : scheme.outline.withValues(alpha: 0.4)),
                        onSelected: (sel) { if (sel) setState(() => _dmLpi = lpi); _markDirty(); },
                        visualDensity: VisualDensity.compact,
                      ),
                    )).toList(),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Line height: ${(72.0 / _dmLpi).toStringAsFixed(1)}pt  •  ${(_dmPageHeight * _dmLpi).round()} lines per page', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  const Divider(height: 24),
                  Text('Print Quality', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  SizedBox(height: 2.rs),
                  Text('Draft prints faster with lower ink usage. Near Letter Quality (NLQ) produces crisper, darker text but is slower.', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  SizedBox(height: 6.rs),
                  Row(
                    children: [
                      ChoiceChip(
                        label: Text('Draft', style: TextStyle(fontWeight: FontWeight.w600, color: _dmPrintQuality == 'draft' ? scheme.onPrimary : scheme.onSurface)),
                        selected: _dmPrintQuality == 'draft',
                        selectedColor: scheme.primary,
                        backgroundColor: scheme.surfaceContainerHighest,
                        side: BorderSide(color: _dmPrintQuality == 'draft' ? scheme.primary : scheme.outline.withValues(alpha: 0.4)),
                        onSelected: (sel) { if (sel) setState(() => _dmPrintQuality = 'draft'); _markDirty(); },
                        visualDensity: VisualDensity.compact,
                      ),
                      SizedBox(width: AppSpacing.sm),
                      ChoiceChip(
                        label: Text('NLQ', style: TextStyle(fontWeight: FontWeight.w600, color: _dmPrintQuality == 'nlq' ? scheme.onPrimary : scheme.onSurface)),
                        selected: _dmPrintQuality == 'nlq',
                        selectedColor: scheme.primary,
                        backgroundColor: scheme.surfaceContainerHighest,
                        side: BorderSide(color: _dmPrintQuality == 'nlq' ? scheme.primary : scheme.outline.withValues(alpha: 0.4)),
                        onSelected: (sel) { if (sel) setState(() => _dmPrintQuality = 'nlq'); _markDirty(); },
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Text('Feed After Print', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  SizedBox(height: 2.rs),
                  Text('Number of blank lines to advance after the last printed line. '
                       'Ensures the printed area clears the print head so you can tear or cut cleanly.', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  SizedBox(height: 6.rs),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _dmFeedAfterPrint.toDouble(),
                          min: 0,
                          max: 12,
                          divisions: 12,
                          label: '$_dmFeedAfterPrint lines',
                          onChanged: (v) { setState(() => _dmFeedAfterPrint = v.round()); _markDirty(); },
                        ),
                      ),
                      SizedBox(width: 60, child: Text('$_dmFeedAfterPrint lines', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600))),
                    ],
                  ),
                  const Divider(height: 24),
                  Text('Top Margin', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  SizedBox(height: 2.rs),
                  Text('Blank lines inserted before the first printed line on each page. '
                       'Use this if your printer starts printing too close to the top edge of the paper.', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  SizedBox(height: 6.rs),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _dmTopMargin.toDouble(),
                          min: 0,
                          max: 12,
                          divisions: 12,
                          label: '$_dmTopMargin lines',
                          onChanged: (v) { setState(() => _dmTopMargin = v.round()); _markDirty(); },
                        ),
                      ),
                      SizedBox(width: 60, child: Text('$_dmTopMargin lines', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600))),
                    ],
                  ),
                  const Divider(height: 24),
                  _SwitchRow(label: 'Form Feed', value: _dmFormFeed, onChanged: (v) { setState(() { _dmFormFeed = v; if (v) _dmTearOffAdvance = false; }); _markDirty(); }),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('When enabled, sends a page-eject command (FF) after printing. '
                                'The printer will advance to the top of the next page. '
                                'Use this with continuous/fanfold paper that has page perforations.', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                  const Divider(height: 24),
                  _SwitchRow(label: 'Tear-off Advance', value: _dmTearOffAdvance, onChanged: (v) { setState(() { _dmTearOffAdvance = v; if (v) _dmFormFeed = false; }); _markDirty(); }),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Advances paper to the tear bar after printing, then reverses it back before the next print job. '
                                'Only works on printers with a tear bar and reverse-feed capability. '
                                'Mutually exclusive with Form Feed.', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                  SizedBox(height: 10.rs),
                ]),
                SizedBox(height: AppSpacing.lg),
                _buildPlaceholderReference(scheme, text),
              ],
            ),
          ),
          SizedBox(width: 20.rs),
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
                  SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () { setState(() => _dmLines.add({'text': '', 'align': 'left', 'style': 'normal'})); _markDirty(); },
                        icon: const Icon(Icons.add_rounded, size: 14),
                        label: const Text('Add Line'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
                      ),
                      SizedBox(width: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: _isDmTemplateDefault() ? null : () { setState(_resetDmTemplate); _markDirty(); },
                        icon: const Icon(Icons.restore_rounded, size: 16),
                        label: const Text('Reset Lines'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          foregroundColor: scheme.error,
                          side: BorderSide(color: _isDmTemplateDefault() ? scheme.outline.withValues(alpha: 0.2) : scheme.error.withValues(alpha: 0.5)),
                          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.3),
                          shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: () => _testPrint('dm'),
                        icon: const Icon(Icons.print_rounded, size: 14),
                        label: const Text('Test Print'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
                      ),
                    ],
                  ),
                ]),
                SizedBox(height: AppSpacing.lg),
                _Section(scheme: scheme, icon: Icons.preview_rounded, title: 'Live Preview  •  ${_dmPaperWidth.toStringAsFixed(1)}″ × ${_dmPageHeight.toStringAsFixed(0)}″  ($_dmColumns col @ $_dmCpi CPI, $_dmLpi LPI)', children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const ppi = 100.0;
                      final boxWidth = _dmPaperWidth * ppi;
                      final boxHeight = _dmPageHeight * ppi;
                      final linePx = ppi / _dmLpi;
                      final topMarginPx = _dmTopMargin * linePx;
                      final feedAfterPx = _dmFeedAfterPrint * linePx;
                      final tearOffPx = _dmTearOffAdvance ? (255.0 / 180.0) * ppi : 0.0;
                      final ffPx = _dmFormFeed ? linePx * 2 : 0.0;
                      final totalHeight = boxHeight + topMarginPx + feedAfterPx + tearOffPx + ffPx;
                      final totalInches = totalHeight / ppi;

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
                                // Vertical inch ruler (spans full window)
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                  width: 18,
                                  height: totalHeight,
                                  child: CustomPaint(
                                    painter: _RulerPainter(
                                      totalInches: totalInches,
                                      ppi: ppi,
                                      horizontal: false,
                                      color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ),
                                // The paper window
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                  width: boxWidth,
                                  height: totalHeight,
                                  clipBehavior: Clip.antiAlias,
                                  decoration: BoxDecoration(
                                    borderRadius: AppRadius.button,
                                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                                  ),
                                  child: Column(
                                    children: [
                                      // Top margin zone
                                      if (topMarginPx > 0)
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 300),
                                          curve: Curves.easeInOut,
                                          height: topMarginPx,
                                          width: boxWidth,
                                          color: const Color(0xFFE8F5E9),
                                          alignment: Alignment.center,
                                          child: Text('↓ TOP MARGIN  $_dmTopMargin lines',
                                            style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: Colors.green.shade700, letterSpacing: 0.5)),
                                        ),
                                      // Print content area (fills remaining space)
                                      Expanded(
                                        child: Container(
                                          width: boxWidth,
                                          color: const Color(0xFFFFFDE8),
                                          child: _buildDmPreviewContent(boxWidth, scheme),
                                        ),
                                      ),
                                      // Feed after print zone
                                      if (feedAfterPx > 0)
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 300),
                                          curve: Curves.easeInOut,
                                          height: feedAfterPx,
                                          width: boxWidth,
                                          color: const Color(0xFFFFF3E0),
                                          alignment: Alignment.center,
                                          child: Text('↓ FEED  $_dmFeedAfterPrint lines',
                                            style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: Colors.orange.shade800, letterSpacing: 0.5)),
                                        ),
                                      // Form feed zone
                                      if (_dmFormFeed)
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 300),
                                          curve: Curves.easeInOut,
                                          height: ffPx,
                                          width: boxWidth,
                                          color: const Color(0xFFE3F2FD),
                                          alignment: Alignment.center,
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              CustomPaint(size: const Size(30, 1), painter: _DashedLinePainter(color: Colors.blue.shade400)),
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                                child: Text('✂ FORM FEED', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.blue.shade700, letterSpacing: 0.5)),
                                              ),
                                              CustomPaint(size: const Size(30, 1), painter: _DashedLinePainter(color: Colors.blue.shade400)),
                                            ],
                                          ),
                                        ),
                                      // Tear-off advance zone
                                      if (_dmTearOffAdvance)
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 300),
                                          curve: Curves.easeInOut,
                                          height: tearOffPx,
                                          width: boxWidth,
                                          color: const Color(0xFFFCE4EC),
                                          alignment: Alignment.center,
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              CustomPaint(size: const Size(30, 1), painter: _DashedLinePainter(color: Colors.red.shade300)),
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                                child: Text('↕ TEAR-OFF ADVANCE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.red.shade700, letterSpacing: 0.5)),
                                              ),
                                              CustomPaint(size: const Size(30, 1), painter: _DashedLinePainter(color: Colors.red.shade300)),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
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

  ui.Image? _dmPreviewImage;
  int _dmPreviewHash = 0;
  bool _dmPreviewLoading = false;

  int _computeDmPreviewHash() {
    var h = _dmColumns.hashCode ^ _dmPaperWidth.hashCode ^ _dmPageHeight.hashCode;
    h ^= _dmMarginTop.hashCode ^ _dmMarginBottom.hashCode ^ _dmMarginLeft.hashCode;
    h ^= _dmLogo.hashCode ^ _dmLogoAspectRatio.hashCode ^ _dmLogoHeight.hashCode ^ _dmPdf417.hashCode ^ _dmPdf417Height.hashCode;
    h ^= _dmCpi.hashCode ^ _dmLpi.hashCode;
    h ^= _dmFeedAfterPrint.hashCode ^ _dmTopMargin.hashCode;
    h ^= _dmFormFeed.hashCode ^ _dmTearOffAdvance.hashCode;
    for (final l in _dmLines) {
      h ^= l.toString().hashCode;
    }
    return h;
  }

  Future<ui.Image> _generateDmPdfPreview(double boxWidth, Uint8List? logoBytes) async {
    // Actual paper dimensions (points)
    final pageW = _dmPaperWidth * PdfPageFormat.inch;
    final pageH = _dmPageHeight * PdfPageFormat.inch;

    final lineHeight = 72.0 / _dmLpi;
    const baseFontSize = 12.0;
    const charAdvance = 0.6 * baseFontSize; // 7.2pt per char

    final font = pw.Font.courier();
    final fontBold = pw.Font.courierBold();
    final previewLines = _generateDmPreviewLines();

    final textPageW = _dmColumns * charAdvance;
    final marginLeftPt = _dmMarginLeft * charAdvance;
    final marginTopPt = _dmMarginTop * lineHeight;
    final marginBottomPt = _dmMarginBottom * lineHeight;
    final renderFormat = PdfPageFormat(textPageW, pageH);

    // Logo: process separately (composited after CPI compression to stay CPI-immune)
    Uint8List? logoMonoPng;
    if (_dmLogo && logoBytes != null) {
      var decoded = img.decodeImage(logoBytes);
      if (decoded != null) {
        decoded = img.bakeOrientation(decoded);
        if (decoded.height > 0) {
          _dmLogoAspectRatio = decoded.width / decoded.height;
        }
        // Match actual print resolution: 60 DPI horizontal (ESC/P single density mode)
        final targetPx = ((_dmLogoWidth / 10.0) * 60).round().clamp(12, 600);
        if (decoded.width != targetPx) {
          decoded = img.copyResize(decoded, width: targetPx, interpolation: img.Interpolation.nearest);
        }

        final hasAlpha = decoded.numChannels >= 4;
        int darkCount = 0;
        int totalOpaque = 0;
        for (var y = 0; y < decoded.height; y++) {
          for (var x = 0; x < decoded.width; x++) {
            final pixel = decoded.getPixel(x, y);
            final a = hasAlpha ? pixel.a.toInt() : 255;
            if (a >= 128) {
              totalOpaque++;
              if (img.getLuminance(pixel).toInt() < 128) darkCount++;
            }
          }
        }
        final invert = totalOpaque > 0 && darkCount > totalOpaque * 0.5;

        final bw = img.Image(width: decoded.width, height: decoded.height, numChannels: 3);
        for (var y = 0; y < decoded.height; y++) {
          for (var x = 0; x < decoded.width; x++) {
            final pixel = decoded.getPixel(x, y);
            final ha = decoded.numChannels >= 4;
            final a = ha ? pixel.a.toInt() : 255;
            final lum = img.getLuminance(pixel).toInt();
            final isDark = a >= 128 && lum < 128;
            final isInk = invert ? !isDark && a >= 128 : isDark;
            if (isInk) {
              bw.setPixelRgb(x, y, 0, 0, 0);
            } else {
              bw.setPixelRgb(x, y, 0xFF, 0xFD, 0xE8);
            }
          }
        }
        logoMonoPng = Uint8List.fromList(img.encodePng(bw));
      }
    }
    final hasLogo = _dmLogo && logoMonoPng != null;

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: renderFormat,
        margin: pw.EdgeInsets.only(left: marginLeftPt, top: marginTopPt, bottom: marginBottomPt, right: marginLeftPt),
        build: (context) {
          // If logo present, reserve blank space and skip placeholder lines
          final linesToRender = hasLogo
              ? previewLines.skip(_dmLogoHeight.clamp(2, 20)).toList()
              : previewLines;

          pw.Widget buildLine(_DmPreviewLine pl) {
            final hasContent = pl.segments.any((s) => s.text.isNotEmpty);
            if (!hasContent) {
              return pw.Container(
                height: lineHeight,
                child: pw.Text(' ', style: pw.TextStyle(font: font, fontSize: baseFontSize)),
              );
            }
            final children = <pw.Widget>[];
            for (final seg in pl.segments) {
              if (seg.text.isEmpty) continue;
              final segFont = seg.bold ? fontBold : font;
              final textWidget = pw.Text(
                seg.text,
                style: pw.TextStyle(font: segFont, fontSize: baseFontSize, lineSpacing: 0),
              );
              if (seg.doubleWidth) {
                children.add(
                  pw.Transform(
                    adjustLayout: true,
                    transform: Matrix4.diagonal3Values(2.0, 1.0, 1.0),
                    child: textWidget,
                  ),
                );
              } else {
                children.add(textWidget);
              }
            }
            return pw.Container(
              height: lineHeight,
              alignment: pw.Alignment.centerLeft,
              child: pw.Row(mainAxisSize: pw.MainAxisSize.min, children: children),
            );
          }

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Blank space for logo (composited separately after compression)
              if (hasLogo) pw.SizedBox(height: _dmLogoHeight * lineHeight),
              ...linesToRender.map(buildLine),
            ],
          );
        },
      ),
    );

    final bytes = await doc.save();

    // Render at 3x target height for sharp text, then composite to final size
    final targetH = boxWidth * (pageH / pageW);
    final scale = 3.0;
    final rasterDpi = (targetH * scale / (pageH / 72.0));
    final rasterStream = Printing.raster(bytes, pages: [0], dpi: rasterDpi);
    final page = await rasterStream.first;
    final fullImage = await page.toImage();

    // Squish horizontally to paper width — CPI compression effect
    final outW = (boxWidth * scale).round();
    final outH = (targetH * scale).round();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
      Paint()..color = const Color(0xFFFFFDE8),
    );
    canvas.drawImageRect(
      fullImage,
      Rect.fromLTWH(0, 0, fullImage.width.toDouble(), fullImage.height.toDouble()),
      Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
      Paint()..filterQuality = FilterQuality.high..blendMode = BlendMode.darken,
    );

    // Composite logo on top — not affected by CPI compression
    if (hasLogo) {
      final codec = await ui.instantiateImageCodec(logoMonoPng);
      final frame = await codec.getNextFrame();
      final logoImage = frame.image;

      final marginFrac = _dmMarginLeft.toDouble() / _dmColumns;
      final logoPhysicalW = (_dmLogoWidth / 10.0) / _dmPaperWidth;
      final logoX = (outW * (0.5 - logoPhysicalW / 2)).clamp(outW * marginFrac, outW.toDouble());
      final logoY = outH * ((_dmMarginTop * lineHeight) / pageH);
      final logoW = outW * logoPhysicalW;
      final logoH = outH * ((_dmLogoHeight * lineHeight) / pageH);

      canvas.drawImageRect(
        logoImage,
        Rect.fromLTWH(0, 0, logoImage.width.toDouble(), logoImage.height.toDouble()),
        Rect.fromLTWH(logoX, logoY, logoW, logoH),
        Paint()..filterQuality = FilterQuality.high,
      );
    }

    // Composite PDF417 barcode just after last template line (physical: 5″ × H″)
    // Print renders at 300×(H*72) px then centers on paper. Preview matches that ratio.
    if (_dmPdf417) {
      const bcPhysicalW = 5.0;
      final pxPerInch = outW / _dmPaperWidth;
      final bcW = bcPhysicalW * pxPerInch;
      final bcH = _dmPdf417Height * pxPerInch;
      final bcX = (outW - bcW) / 2;
      final totalLines = previewLines.length;
      final contentTopPt = _dmMarginTop * lineHeight;
      final contentEndPt = contentTopPt + (totalLines * lineHeight) + lineHeight;
      final bcY = outH * (contentEndPt / pageH);

      // Generate barcode at print-resolution dimensions (matches print service exactly)
      const printW = 300.0; // 5″ × 60 DPI
      final printH = (_dmPdf417Height * 72).roundToDouble(); // H″ × 72 DPI
      final bc = Barcode.pdf417();
      final sampleData = _buildPreviewBarcodeData();
      final elements = bc.make(sampleData, width: printW, height: printH);

      // Scale from print pixels to preview pixels
      final scaleX = bcW / printW;
      final scaleY = bcH / printH;

      canvas.drawRect(
        Rect.fromLTWH(bcX, bcY, bcW, bcH),
        Paint()..color = const Color(0xFFFFFDE8),
      );
      final barPaint = Paint()..color = const Color(0xFF000000);
      for (final elem in elements) {
        if (elem is BarcodeBar && elem.black) {
          canvas.drawRect(
            Rect.fromLTWH(bcX + elem.left * scaleX, bcY + elem.top * scaleY, elem.width * scaleX, elem.height * scaleY),
            barPaint,
          );
        }
      }
    }

    final picture = recorder.endRecording();
    return picture.toImage(outW, outH);
  }

  Widget _buildDmPreviewContent(double boxWidth, ColorScheme scheme) {
    final currentHash = _computeDmPreviewHash();
    final logoBytes = _dmLogo ? ref.watch(_companyLogoProvider).valueOrNull : null;

    // Kick off render if needed
    if (_dmPreviewImage == null || _dmPreviewHash != currentHash) {
      if (!_dmPreviewLoading || _dmPreviewHash != currentHash) {
        _dmPreviewLoading = true;
        final capturedHash = currentHash;
        _generateDmPdfPreview(boxWidth, logoBytes).then((image) {
          if (mounted && capturedHash == _computeDmPreviewHash()) {
            setState(() {
              _dmPreviewImage = image;
              _dmPreviewHash = capturedHash;
              _dmPreviewLoading = false;
            });
          } else {
            _dmPreviewLoading = false;
          }
        }).catchError((_) {
          _dmPreviewLoading = false;
        });
      }
    }

    if (_dmPreviewImage != null && _dmPreviewHash == currentHash) {
      return RawImage(image: _dmPreviewImage, width: boxWidth, fit: BoxFit.fitWidth);
    } else if (_dmPreviewImage != null) {
      return Opacity(opacity: 0.5, child: RawImage(image: _dmPreviewImage, width: boxWidth, fit: BoxFit.fitWidth));
    }

    return Center(
      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary)),
    );
  }


  String _buildPreviewBarcodeData() {
    final placeholders = _previewPlaceholders();
    final usedKeys = <String>{};
    final placeholderPattern = RegExp(r'\{[^}]+\}');
    for (final line in _dmLines) {
      final text = line['text'] as String? ?? '';
      for (final match in placeholderPattern.allMatches(text)) {
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
    return parts.join('|');
  }

  List<_DmPreviewLine> _generateDmPreviewLines() {
    final result = <_DmPreviewLine>[];
    final usableWidth = _dmColumns - _dmMarginLeft - _dmMarginLeft;

    String alignText(String content, String align, int usable) {
      if (content.length > usable) content = content.substring(0, usable);
      if (align == 'center' && content.length < usable) {
        final pad = ((usable - content.length) / 2).floor();
        content = '${' ' * pad}$content';
      } else if (align == 'right' && content.length < usable) {
        content = content.padLeft(usable);
      }
      return content;
    }

    if (_dmLogo) {
      final logoW = _dmLogoWidth.clamp(6, usableWidth ~/ 2);
      final logoH = _dmLogoHeight.clamp(2, 20);
      for (var row = 0; row < logoH; row++) {
        if (row == 0 || row == logoH - 1) {
          final line = '+${'-' * (logoW - 2)}+';
          final pad = ((usableWidth - line.length) / 2).floor().clamp(0, usableWidth);
          result.add(_DmPreviewLine.simple('${' ' * pad}$line', false));
        } else if (row == logoH ~/ 2) {
          final line = '|${'LOGO'.padLeft((logoW - 2 + 4) ~/ 2).padRight(logoW - 2)}|';
          final pad = ((usableWidth - line.length) / 2).floor().clamp(0, usableWidth);
          result.add(_DmPreviewLine.simple('${' ' * pad}$line', false));
        } else {
          final line = '|${' ' * (logoW - 2)}|';
          final pad = ((usableWidth - line.length) / 2).floor().clamp(0, usableWidth);
          result.add(_DmPreviewLine.simple('${' ' * pad}$line', false));
        }
      }
    }

    var i = 0;
    while (i < _dmLines.length) {
      final line = _dmLines[i];
      final group = line['group'] as int? ?? 0;
      final style = line['style'] as String? ?? 'normal';

      if (style == 'separator') {
        result.add(_DmPreviewLine.simple('-' * usableWidth, false));
        i++;
      } else if (group > 0) {
        final groupLines = <Map<String, dynamic>>[];
        while (i < _dmLines.length && (_dmLines[i]['group'] as int? ?? 0) == group) {
          groupLines.add(_dmLines[i]);
          i++;
        }
        final groupColCount = groupLines.length.clamp(1, 3);
        final colWidth = usableWidth ~/ groupColCount;
        final segments = <_DmPreviewSegment>[];
        for (var c = 0; c < groupColCount; c++) {
          final gl = groupLines[c];
          final content = _substituteLine(gl['text'] as String? ?? '');
          final align = gl['align'] as String? ?? 'left';
          final gStyle = gl['style'] as String? ?? 'normal';
          final isBold = gStyle == 'bold';
          final isDouble = gStyle == 'double';
          final aligned = alignText(content, align, isDouble ? colWidth ~/ 2 : colWidth);
          segments.add(_DmPreviewSegment(
            aligned.padRight(isDouble ? colWidth ~/ 2 : colWidth),
            bold: isBold,
            doubleWidth: isDouble,
          ));
        }
        result.add(_DmPreviewLine(segments));
      } else {
        final content = _substituteLine(line['text'] as String? ?? '');
        final align = line['align'] as String? ?? 'left';
        final isBold = style == 'bold';
        final isDouble = style == 'double';
        final effectiveWidth = isDouble ? usableWidth ~/ 2 : usableWidth;
        final aligned = alignText(content, align, effectiveWidth);
        result.add(_DmPreviewLine([
          _DmPreviewSegment(aligned, bold: isBold, doubleWidth: isDouble),
        ]));
        i++;
      }
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // THERMAL TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildThermalTab(ColorScheme scheme, TextTheme text) {
    return SingleChildScrollView(
      padding: AppSpacing.pagePadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Config + Placeholders
          SizedBox(
            width: 370,
            child: Column(
              children: [
                _Section(scheme: scheme, icon: Icons.receipt_long_rounded, title: 'Thermal Configuration', children: [
                  _buildDropdownRow('Paper Width', _thermalWidth, ['58mm', '80mm'], (v) { setState(() => _switchThermalWidth(v!)); _markDirty(); }, text),
                  SizedBox(height: 10.rs),
                  _SwitchRow(label: 'Include Logo', value: _thermalLogo, onChanged: (v) { setState(() => _thermalLogo = v); _markDirty(); }),
                  if (_thermalLogo) ...[
                    SizedBox(height: AppSpacing.sm),
                    Text('Logo Size (mm)', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(height: 6.rs),
                    Row(
                      children: [
                        Expanded(child: _buildDoubleInput('W', _thermalLogoWidth, (v) { setState(() => _thermalLogoWidth = v); _markDirty(); }, text)),
                        SizedBox(width: AppSpacing.sm),
                        Expanded(child: _buildDoubleInput('H', _thermalLogoHeight, (v) { setState(() => _thermalLogoHeight = v); _markDirty(); }, text)),
                      ],
                    ),
                  ],
                  SizedBox(height: 10.rs),
                  _SwitchRow(label: 'PDF417 Barcode', value: _thermalPdf417, onChanged: (v) { setState(() => _thermalPdf417 = v); _markDirty(); }),
                  if (_thermalPdf417)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Encodes template placeholders automatically', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
                    ),
                  SizedBox(height: 10.rs),
                  _buildDropdownRow('Font', _thermalFont, ['Font A', 'Font B', 'Font C'], (v) { setState(() => _thermalFont = v!); _markDirty(); }, text),
                  SizedBox(height: 10.rs),
                  _buildDropdownRow('Font Size', '${_thermalFontSize}pt', ['6pt', '7pt', '8pt', '10pt', '12pt', '14pt', '16pt'], (v) { setState(() => _thermalFontSize = int.parse(v!.replaceAll('pt', ''))); _markDirty(); }, text),
                  SizedBox(height: 10.rs),
                  _buildDropdownRow('Cut Mode', _thermalCutMode, ['Full', 'Partial', 'None'], (v) { setState(() => _thermalCutMode = v!); _markDirty(); }, text),
                  SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isThermalConfigDefault() ? null : () { setState(() => _applyThermalWidthConfig(_getDefaultThermalWidthConfig(_thermalWidth))); _markDirty(); },
                      icon: const Icon(Icons.settings_backup_restore_rounded, size: 16),
                      label: Text('Reset Config ($_thermalWidth)'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        foregroundColor: scheme.error,
                        side: BorderSide(color: _isThermalConfigDefault() ? scheme.outline.withValues(alpha: 0.2) : scheme.error.withValues(alpha: 0.5)),
                        disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                      ),
                    ),
                  ),
                  SizedBox(height: 10.rs),
                ]),
                SizedBox(height: AppSpacing.lg),
                _buildPlaceholderReference(scheme, text),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.lg),
          // Center: Template Lines
          Flexible(
            flex: 1,
            child: _Section(scheme: scheme, icon: Icons.edit_note_rounded, title: 'Template Lines', children: [
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
              SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () { setState(() => _thermalLines.add({'text': '', 'align': 'left', 'size': 'normal'})); _markDirty(); },
                    icon: const Icon(Icons.add_rounded, size: 14),
                    label: const Text('Add Line'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
                  ),
                  SizedBox(width: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _isTemplateDefault(_thermalLines, _getDefaultThermalLines(width: _thermalWidth)) ? null : () { setState(() => _thermalLines = _getDefaultThermalLines(width: _thermalWidth)); _markDirty(); },
                    icon: const Icon(Icons.restore_rounded, size: 16),
                    label: const Text('Reset Lines'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      foregroundColor: scheme.error,
                      side: BorderSide(color: _isTemplateDefault(_thermalLines, _getDefaultThermalLines(width: _thermalWidth)) ? scheme.outline.withValues(alpha: 0.2) : scheme.error.withValues(alpha: 0.5)),
                      disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => _testPrint('thermal'),
                    icon: const Icon(Icons.print_rounded, size: 14),
                    label: const Text('Test Print'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
                  ),
                ],
              ),
            ]),
          ),
          SizedBox(width: AppSpacing.lg),
          // Right: Live Preview
          SizedBox(
            width: 360,
            child: _Section(scheme: scheme, icon: Icons.preview_rounded, title: 'Live Preview', children: [
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
                          padding: EdgeInsets.all(4.rs),
                          decoration: BoxDecoration(color: scheme.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(4.rs)),
                          child: Icon(Icons.zoom_in_rounded, size: 14, color: scheme.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildThermalPreview(ColorScheme scheme, TextTheme text, {bool enlarged = false}) {
    final scale = enlarged ? 1.8 : 1.0;

    final paperWidth = (_thermalWidth == '58mm' ? 220.0 : 300.0) * scale;
    return Center(child: Container(
      width: paperWidth,
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4.rs), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]),
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
    ));
  }

  void _showEnlargedThermalPreview(ColorScheme scheme, TextTheme text) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.all(40.rs),
        child: Container(
          constraints: BoxConstraints(maxWidth: 600, maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: AppRadius.dialog,
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
                    SizedBox(width: AppSpacing.sm),
                    Text('Thermal Preview (Enlarged)', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, size: 20)),
                  ],
                ),
              ),
              Flexible(
                child: Padding(
                  padding: AppSpacing.pagePadding,
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
    return LayoutBuilder(builder: (context, constraints) {
      final renderW = constraints.maxWidth > 0 ? constraints.maxWidth : 400.0;
      final renderH = renderW * 0.2;
      final elements = bc.make(data, width: renderW, height: renderH);
      return SizedBox(
        width: renderW,
        height: renderH,
        child: CustomPaint(
          painter: _Pdf417Painter(elements.toList(), renderW, renderH),
        ),
      );
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildNormalTab(ColorScheme scheme, TextTheme text) {
    return SingleChildScrollView(
      padding: AppSpacing.pagePadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Config + Placeholders
          SizedBox(
            width: 370,
            child: Column(
              children: [
                _Section(scheme: scheme, icon: Icons.description_rounded, title: 'Page Setup', children: [
                  _buildDropdownRow('Paper Size', _normalPaperSize, ['A4', 'A5', 'Letter', 'Legal'], (v) { setState(() => _switchPaperSize(v!)); _markDirty(); }, text),
                  SizedBox(height: 10.rs),
                  Text('Margins (mm)', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                  SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(child: _buildDoubleInput('T', _normalMarginTop, (v) { setState(() => _normalMarginTop = v); _markDirty(); }, text)),
                      SizedBox(width: 6.rs),
                      Expanded(child: _buildDoubleInput('B', _normalMarginBottom, (v) { setState(() => _normalMarginBottom = v); _markDirty(); }, text)),
                      SizedBox(width: 6.rs),
                      Expanded(child: _buildDoubleInput('L', _normalMarginLeft, (v) { setState(() => _normalMarginLeft = v); _markDirty(); }, text)),
                      SizedBox(width: 6.rs),
                      Expanded(child: _buildDoubleInput('R', _normalMarginRight, (v) { setState(() => _normalMarginRight = v); _markDirty(); }, text)),
                    ],
                  ),
                  SizedBox(height: 10.rs),
                  _buildDropdownRow('Font', _normalFont, ['Helvetica', 'Times', 'Courier', 'Roboto', 'Open Sans'], (v) { setState(() => _normalFont = v!); _markDirty(); }, text),
                  SizedBox(height: 10.rs),
                  _buildDropdownRow('Font Size', '${_normalFontSize}pt', ['6pt', '7pt', '8pt', '9pt', '10pt', '11pt', '12pt', '14pt', '16pt', '18pt'], (v) { setState(() => _normalFontSize = int.parse(v!.replaceAll('pt', ''))); _markDirty(); }, text),
                  if (_normalLogo) ...[
                    SizedBox(height: 10.rs),
                    Row(
                      children: [
                        Text('Header Rows (beside logo)', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        _CounterButton(value: _headerRows, min: 1, max: 10, onChanged: (v) { setState(() => _headerRows = v); _markDirty(); }),
                      ],
                    ),
                  ],
                ]),
                SizedBox(height: AppSpacing.lg),
                _Section(scheme: scheme, icon: Icons.image_rounded, title: 'Content Options', children: [
                  _SwitchRow(label: 'Company Logo', value: _normalLogo, onChanged: (v) { setState(() => _normalLogo = v); _markDirty(); }),
                  if (_normalLogo) ...[
                    SizedBox(height: AppSpacing.sm),
                    Text('Logo Size (mm)', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(height: 6.rs),
                    Row(
                      children: [
                        Expanded(child: _buildDoubleInput('W', _normalLogoWidth, (v) { setState(() => _normalLogoWidth = v); _markDirty(); }, text)),
                        SizedBox(width: AppSpacing.sm),
                        Expanded(child: _buildDoubleInput('H', _normalLogoHeight, (v) { setState(() => _normalLogoHeight = v); _markDirty(); }, text)),
                      ],
                    ),
                  ],
                  SizedBox(height: AppSpacing.sm),
                  _SwitchRow(label: 'PDF417 Barcode', value: _normalPdf417, onChanged: (v) { setState(() => _normalPdf417 = v); _markDirty(); }),
                  if (_normalPdf417) ...[
                    SizedBox(height: 6.rs),
                    _buildDropdownRow('Position', _normalPdf417Position, ['bottom', 'afterText'], (v) { setState(() => _normalPdf417Position = v!); _markDirty(); }, text),
                  ],
                  SizedBox(height: AppSpacing.sm),
                  _SwitchRow(label: 'CCTV Snapshots', value: _normalCctv, onChanged: (v) { setState(() => _normalCctv = v); _markDirty(); }),
                  if (_normalCctv) ...[
                    SizedBox(height: 10.rs),
                    Builder(builder: (context) {
                      final camerasAsync = ref.watch(activeWeighbridgeCamerasProvider);
                      final cameras = camerasAsync.valueOrNull ?? [];
                      if (cameras.isEmpty) {
                        return Text('No cameras configured', style: text.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant));
                      }
                      final availableRoles = cameras.map((c) => c.grossRole).toSet().toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Select cameras to include (empty = auto by priority)', style: text.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          SizedBox(height: 6.rs),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: availableRoles.map((role) {
                              final selected = _normalCctvCameras.contains(role);
                              return FilterChip(
                                label: Text(role),
                                selected: selected,
                                onSelected: (v) {
                                  setState(() {
                                    if (v) { _normalCctvCameras.add(role); } else { _normalCctvCameras.remove(role); }
                                  });
                                  _markDirty();
                                },
                                labelStyle: text.labelSmall,
                                shape: RoundedRectangleBorder(borderRadius: AppRadius.chip),
                              );
                            }).toList(),
                          ),
                        ],
                      );
                    }),
                  ],
                  SizedBox(height: AppSpacing.md),
                  Builder(builder: (context) {
                    final def = _getDefaultSizeConfig(_normalPaperSize);
                    final isDefault = _normalLogo && _normalPdf417 &&
                        _normalFontSize == (def['fontSize'] as int) && _normalFont == 'Helvetica' &&
                        _normalMarginTop == ((def['marginTop'] as num).toDouble()) &&
                        _normalMarginBottom == ((def['marginBottom'] as num).toDouble()) &&
                        _normalMarginLeft == ((def['marginLeft'] as num).toDouble()) &&
                        _normalMarginRight == ((def['marginRight'] as num).toDouble());
                    return SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: isDefault ? null : () { setState(() { _normalLogo = true; _normalPdf417 = true; _normalFontSize = def['fontSize'] as int; _normalFont = 'Helvetica'; _normalMarginTop = (def['marginTop'] as num).toDouble(); _normalMarginBottom = (def['marginBottom'] as num).toDouble(); _normalMarginLeft = (def['marginLeft'] as num).toDouble(); _normalMarginRight = (def['marginRight'] as num).toDouble(); }); _markDirty(); },
                        icon: const Icon(Icons.settings_backup_restore_rounded, size: 16),
                        label: Text('Reset Config ($_normalPaperSize)'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          foregroundColor: scheme.error,
                          side: BorderSide(color: isDefault ? scheme.outline.withValues(alpha: 0.2) : scheme.error.withValues(alpha: 0.5)),
                          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.3),
                          shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                        ),
                      ),
                    );
                  }),
                  SizedBox(height: 10.rs),
                ]),
                SizedBox(height: AppSpacing.lg),
                _buildPlaceholderReference(scheme, text),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.lg),
          // Center: Template Lines
          Flexible(
            flex: 1,
            child: _Section(scheme: scheme, icon: Icons.edit_note_rounded, title: 'Template Lines', children: [
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
              SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () { setState(() => _normalLines.add({'text': '', 'align': 'left', 'style': 'normal'})); _markDirty(); },
                    icon: const Icon(Icons.add_rounded, size: 14),
                    label: const Text('Add Line'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
                  ),
                  SizedBox(width: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _isTemplateDefault(_normalLines, _getDefaultNormalLines(paperSize: _normalPaperSize)) ? null : () { setState(() => _normalLines = _getDefaultNormalLines(paperSize: _normalPaperSize)); _markDirty(); },
                    icon: const Icon(Icons.restore_rounded, size: 16),
                    label: const Text('Reset Lines'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      foregroundColor: scheme.error,
                      side: BorderSide(color: _isTemplateDefault(_normalLines, _getDefaultNormalLines(paperSize: _normalPaperSize)) ? scheme.outline.withValues(alpha: 0.2) : scheme.error.withValues(alpha: 0.5)),
                      disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => _testPrint('normal'),
                    icon: const Icon(Icons.print_rounded, size: 14),
                    label: const Text('Test Print'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
                  ),
                ],
              ),
            ]),
          ),
          SizedBox(width: AppSpacing.lg),
          // Right: Page Preview
          SizedBox(
            width: 360,
            child: _Section(scheme: scheme, icon: Icons.preview_rounded, title: 'Page Preview  •  $_normalPaperSize', children: [
              LayoutBuilder(builder: (context, constraints) {
                return GestureDetector(
                  onTap: () => _showEnlargedPreview(scheme, text),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.zoomIn,
                    child: Stack(
                      children: [
                        _buildNormalPreview(scheme, text, availableWidth: constraints.maxWidth),
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            padding: EdgeInsets.all(4.rs),
                            decoration: BoxDecoration(color: scheme.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(4.rs)),
                            child: Icon(Icons.zoom_in_rounded, size: 14, color: scheme.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ]),
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
        insetPadding: EdgeInsets.all(40.rs),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 900),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: AppRadius.dialog,
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
                    SizedBox(width: AppSpacing.sm),
                    Text('Page Preview (Enlarged)', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, size: 20)),
                  ],
                ),
              ),
              Flexible(
                child: Padding(
                  padding: AppSpacing.pagePadding,
                  child: Center(child: _buildNormalPreview(scheme, text, enlarged: true)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNormalPreview(ColorScheme scheme, TextTheme text, {bool enlarged = false, double? availableWidth}) {
    double paperW, paperH;
    switch (_normalPaperSize) {
      case 'A5': paperW = 148; paperH = 210; break;
      case 'Letter': paperW = 216; paperH = 279; break;
      case 'Legal': paperW = 216; paperH = 356; break;
      default: paperW = 210; paperH = 297;
    }

    final previewW = enlarged ? 500.0 : (availableWidth ?? 280.0);
    final aspectRatio = paperW / paperH;
    final previewH = previewW / aspectRatio;
    final scale = previewW / paperW;
    final fontScale = scale;

    final contentWidgets = <Widget>[];

    // Inline header: logo beside first N lines
    int inlineHeaderConsumed = 0;
    if (_normalLogo) {
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

    // CCTV snapshots — two-column preview (1st weighment | 2nd weighment)
    if (_normalCctv) {
      final camerasAsync = ref.read(activeWeighbridgeCamerasProvider);
      final configuredCameras = camerasAsync.valueOrNull ?? [];
      final availableRoles = configuredCameras.map((c) => c.grossRole).toList();
      const priorityOrder = ['Front', 'Rear', 'Top', 'Side-Right', 'Side-Left'];

      List<String> resolved;
      if (_normalCctvCameras.isNotEmpty) {
        resolved = availableRoles.where((r) => _normalCctvCameras.contains(r)).toList();
      } else {
        resolved = [...availableRoles]..sort((a, b) {
          final ai = priorityOrder.indexOf(a);
          final bi = priorityOrder.indexOf(b);
          return (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
        });
      }
      resolved = resolved.take(4).toList();

      if (resolved.isNotEmpty) {
        final subheadingSize = (_normalFontSize + 2) * 0.30 * fontScale;
        final labelSize = _normalFontSize * 0.30 * fontScale;
        contentWidgets.add(SizedBox(height: 4 * scale));
        contentWidgets.add(Divider(height: 1, thickness: 0.5 * scale, color: scheme.outlineVariant.withValues(alpha: 0.4)));
        contentWidgets.add(SizedBox(height: 2 * scale));
        contentWidgets.add(Row(
          children: [
            Expanded(child: Center(child: Text('GROSS', style: TextStyle(fontSize: subheadingSize, fontWeight: FontWeight.bold, color: scheme.onSurfaceVariant)))),
            SizedBox(width: AppSpacing.xs),
            Expanded(child: Center(child: Text('TARE', style: TextStyle(fontSize: subheadingSize, fontWeight: FontWeight.bold, color: scheme.onSurfaceVariant)))),
          ],
        ));
        contentWidgets.add(SizedBox(height: 2 * scale));
        for (final role in resolved) {
          contentWidgets.add(Padding(
            padding: EdgeInsets.only(bottom: 3 * scale),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(right: 2),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Container(
                        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(2), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3))),
                        child: Center(child: Text(role, style: TextStyle(fontSize: labelSize, color: scheme.onSurfaceVariant))),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(left: 2),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Container(
                        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(2), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3))),
                        child: Center(child: Text(role, style: TextStyle(fontSize: labelSize, color: scheme.onSurfaceVariant))),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ));
        }
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
        SizedBox(width: AppSpacing.sm),
        Text('Print Rules', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        SizedBox(width: AppSpacing.xl),
        // Copies
        Text('Copies:', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(width: AppSpacing.sm),
        _CounterButton(value: _copies, min: 1, max: 10, onChanged: (v) { setState(() => _copies = v); _markDirty(); }),
        SizedBox(width: 20.rs),
        // Toggles
        _CompactToggle(label: 'Gross', value: _printOnGross, onChanged: (v) { setState(() => _printOnGross = v); _markDirty(); }),
        SizedBox(width: AppSpacing.md),
        _CompactToggle(label: 'Tare', value: _printOnTare, onChanged: (v) { setState(() => _printOnTare = v); _markDirty(); }),
        SizedBox(width: AppSpacing.md),
        _CompactToggle(label: 'Auto', value: _autoPrint, onChanged: (v) { setState(() => _autoPrint = v); _markDirty(); }),
        SizedBox(width: AppSpacing.md),
        _CompactToggle(label: 'Reprint', value: _reprintAllowed, onChanged: (v) { setState(() => _reprintAllowed = v); _markDirty(); }),
        if (_reprintAllowed) ...[
          SizedBox(width: AppSpacing.sm),
          Text('max:', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          SizedBox(width: AppSpacing.xs),
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
          final scheme = Theme.of(ctx).colorScheme;
          final typeIcon = {'normal': Icons.description_rounded, 'thermal': Icons.receipt_long_rounded, 'dotMatrix': Icons.grid_on_rounded};
          final typeLabel = {'normal': 'Page', 'thermal': 'Thermal', 'dotMatrix': 'Dot Matrix'};
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
            title: Row(children: [
              Icon(Icons.print_rounded, size: 20, color: scheme.primary),
              SizedBox(width: 10.rs),
              const Text('Manage Printers', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${printers.length} printer${printers.length != 1 ? 's' : ''}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w400)),
            ]),
            content: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 700, maxHeight: MediaQuery.of(ctx).size.height * 0.7),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  if (errorMsg != null) Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: AppRadius.button),
                      child: Row(children: [
                        Icon(Icons.error_outline_rounded, size: 14, color: scheme.onErrorContainer),
                        SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(errorMsg!, style: TextStyle(fontSize: 11, color: scheme.onErrorContainer))),
                      ]),
                    ),
                  ),
                  ...printers.asMap().entries.map((e) {
                    final p = e.value;
                    final pType = p['type'] as String? ?? 'normal';
                    final pName = p['name'] as String? ?? '';
                    final nickname = p['nickname'] as String? ?? '';
                    final trays = _printerTrays[pName] ?? [];
                    final paperW = (p['paperWidth'] as num?)?.toDouble() ?? 8.0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: EdgeInsets.all(14.rs),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: AppRadius.card,
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Row 1: Icon + Name + System Name + Delete
                          Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(6.rs),
                                decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.5), borderRadius: AppRadius.chip),
                                child: Icon(typeIcon[pType] ?? Icons.print_rounded, size: 14, color: scheme.primary),
                              ),
                              SizedBox(width: 10.rs),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TextField(
                                      controller: TextEditingController(text: nickname),
                                      onChanged: (v) => printers[e.key]['nickname'] = v,
                                      decoration: InputDecoration(
                                        hintText: pName.isNotEmpty ? 'Nickname ($pName)' : 'Display Name',
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: OutlineInputBorder(borderRadius: AppRadius.chip, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
                                        enabledBorder: OutlineInputBorder(borderRadius: AppRadius.chip, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
                                      ),
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: AppSpacing.sm),
                              SizedBox(
                                width: 180,
                                child: TextField(
                                  controller: TextEditingController(text: p['address'] as String? ?? ''),
                                  onChanged: (v) => printers[e.key]['address'] = v,
                                  decoration: InputDecoration(
                                    hintText: 'Address / IP',
                                    prefixIcon: Padding(padding: const EdgeInsets.only(left: 8, right: 4), child: Icon(Icons.link_rounded, size: 13, color: scheme.onSurfaceVariant)),
                                    prefixIconConstraints: const BoxConstraints(minWidth: 28),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    border: OutlineInputBorder(borderRadius: AppRadius.chip, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
                                    enabledBorder: OutlineInputBorder(borderRadius: AppRadius.chip, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
                                  ),
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              SizedBox(width: 6.rs),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 16),
                                onPressed: () => setD(() => printers.removeAt(e.key)),
                                color: scheme.error,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                style: IconButton.styleFrom(backgroundColor: scheme.errorContainer.withValues(alpha: 0.3)),
                              ),
                            ],
                          ),
                          SizedBox(height: 10.rs),
                          // Row 2: Type + Config
                          Row(
                            children: [
                              _MiniChipDropdown(
                                label: 'Type',
                                value: typeLabel[pType] ?? 'Page',
                                items: ['Page', 'Thermal', 'Dot Matrix'],
                                onChanged: (v) {
                                  final mapped = {'Page': 'normal', 'Thermal': 'thermal', 'Dot Matrix': 'dotMatrix'}[v] ?? 'normal';
                                  setD(() { printers[e.key]['type'] = mapped; printers[e.key]['lines'] = _defaultLinesForType(mapped); if (mapped == 'normal') printers[e.key]['paperSize'] ??= 'A4'; });
                                },
                              ),
                              SizedBox(width: 10.rs),
                              if (pType == 'normal' && trays.isEmpty)
                                _MiniChipDropdown(
                                  label: 'Paper',
                                  value: p['paperSize'] as String? ?? 'A4',
                                  items: const ['A4', 'A5', 'Letter', 'Legal'],
                                  onChanged: (v) { setD(() { printers[e.key]['paperSize'] = v; }); },
                                ),
                              if (pType == 'thermal')
                                _MiniChipDropdown(
                                  label: 'Width',
                                  value: p['thermalWidth'] as String? ?? '80mm',
                                  items: const ['58mm', '80mm'],
                                  onChanged: (v) { setD(() => printers[e.key]['thermalWidth'] = v); },
                                ),
                              if (pType == 'dotMatrix') ...[
                                Text('Width', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                                SizedBox(width: 6.rs),
                                SizedBox(
                                  width: 140,
                                  child: SliderTheme(
                                    data: SliderThemeData(thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), overlayShape: const RoundSliderOverlayShape(overlayRadius: 12), trackHeight: 3),
                                    child: Slider(
                                      value: paperW.clamp(8.0, 13.2),
                                      min: 8.0,
                                      max: 13.2,
                                      divisions: 26,
                                      onChanged: (v) { setD(() => printers[e.key]['paperWidth'] = double.parse(v.toStringAsFixed(1))); },
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(4.rs)),
                                  child: Text('${paperW.toStringAsFixed(1)}″ · ${(paperW * 10).round()} col', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: scheme.onSecondaryContainer)),
                                ),
                              ],
                              if (trays.isNotEmpty) ...[
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: scheme.tertiaryContainer.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(4.rs)),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.inventory_2_outlined, size: 11, color: scheme.tertiary),
                                      SizedBox(width: AppSpacing.xs),
                                      Text('${trays.length} tray${trays.length > 1 ? 's' : ''}', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: scheme.tertiary)),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          // Row 3: Tray → Size mapping (page printers only)
                          if (trays.isNotEmpty && pType == 'normal') ...[
                            SizedBox(height: 10.rs),
                            Container(
                              padding: EdgeInsets.all(8.rs),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                borderRadius: AppRadius.button,
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
                                      final mapping = (p['trayMapping'] as Map<String, dynamic>?) ?? {};
                                      final currentSize = mapping[tray] as String? ?? 'Dynamic';
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: scheme.primaryContainer.withValues(alpha: 0.3),
                                          borderRadius: AppRadius.chip,
                                          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(tray, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: scheme.onSurface)),
                                            SizedBox(width: 6.rs),
                                            Icon(Icons.arrow_forward_rounded, size: 10, color: scheme.onSurfaceVariant),
                                            SizedBox(width: AppSpacing.xs),
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
                                                  setD(() {
                                                    final m = Map<String, dynamic>.from(mapping);
                                                    m[tray] = v ?? 'Dynamic';
                                                    printers[e.key]['trayMapping'] = m;
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
                        ],
                      ),
                    );
                  }),
                  SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => setD(() => printers.add({'name': '', 'type': 'normal', 'address': '', 'paperSize': 'A4', 'lines': _defaultLinesForType('normal')})),
                        icon: const Icon(Icons.add_rounded, size: 14),
                        label: const Text('Add Manually'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
                      ),
                      SizedBox(width: 10.rs),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          final detected = await _detectSystemPrinters();
                          if (detected.isNotEmpty) {
                            setD(() {
                              for (final dp in detected) {
                                final exists = printers.any((p) => p['name'] == dp['name']);
                                if (!exists) printers.add(dp);
                              }
                            });
                            setState(() => _printers = List.from(printers));
                            await _loadPrinterTrays();
                            setD(() {});
                          }
                        },
                        icon: const Icon(Icons.radar_rounded, size: 14),
                        label: const Text('Auto-Detect'),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
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

  static String _guessTypeFromInfo(String combined) {
    final lower = combined.toLowerCase();
    if (RegExp(r'thermal|receipt|pos[-_ ]|tm-|tmt|rp-|xprinter|star\s*tsp|epson\s*t[0-9]|zj-|rongta|munbyn|bixolon|citizen\s*ct|sewoo|80mm|58mm').hasMatch(lower)) return 'thermal';
    if (RegExp(r'dot.?matrix|impact|fx-|lx-|lq-|dfx|dlq|plq|okidata|oki\s*ml|printronix|tally').hasMatch(lower)) return 'dotMatrix';
    return 'normal';
  }

  static String _cleanNickname(String name) {
    var nick = name
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'[-]{2,}'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Remove common prefixes/suffixes that aren't useful
    nick = nick.replaceAll(RegExp(r'\b(cups|ipp|usb|serial)\b', caseSensitive: false), '').trim();
    // Title case each word
    nick = nick.split(' ').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
    return nick;
  }

  static Map<String, dynamic> _buildDetectedPrinter(String name, String address, {String extraInfo = ''}) {
    final type = _guessTypeFromInfo('$name $address $extraInfo');
    final entry = <String, dynamic>{'name': name, 'type': type, 'address': address, 'nickname': _cleanNickname(name), 'lines': _defaultLinesForType(type)};
    if (type == 'normal') entry['paperSize'] = 'A4';
    if (type == 'thermal') entry['thermalWidth'] = '80mm';
    return entry;
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
                final infoResult = await Process.run('lpoptions', ['-p', name, '-l']);
                final info = infoResult.exitCode == 0 ? infoResult.stdout as String : '';
                final deviceResult = await Process.run('lpstat', ['-v', name]);
                final deviceUri = deviceResult.exitCode == 0 ? deviceResult.stdout as String : '';
                printers.add(_buildDetectedPrinter(name, 'cups://$name', extraInfo: '$info $deviceUri'));
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
              printers.add(_buildDetectedPrinter('Network ($ip)', uri));
            }
          }
        }
      } else if (Platform.isWindows) {
        final result = await Process.run('powershell', ['-Command', r"Get-Printer | Select-Object Name,PortName,DriverName,PrinterStatus | ConvertTo-Csv -NoTypeInformation"]);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).split('\n').skip(1);
          for (final line in lines) {
            final parts = line.replaceAll('"', '').split(',');
            if (parts.length >= 3) {
              final name = parts[0].trim();
              final port = parts[1].trim();
              final driver = parts.length >= 3 ? parts[2].trim() : '';
              if (name.isEmpty) continue;
              printers.add(_buildDetectedPrinter(name, port, extraInfo: driver));
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

  List<Widget> _buildTrayOrSizeSelector(String printerName, String currentTray, String currentSize, void Function(String tray, String size) onChanged) {
    if (printerName.isEmpty || !_printerNames.contains(printerName)) return [];
    final availableSizes = _getAvailableSizesForPrinter(printerName);
    if (availableSizes.isNotEmpty) {
      final effectiveSize = availableSizes.contains(currentSize) ? currentSize : availableSizes.first;
      return [
        SizedBox(width: AppSpacing.xs),
        _MiniDropdown(
          value: effectiveSize,
          items: availableSizes,
          onChanged: (v) => onChanged(_resolveTrayForSize(printerName, v), v),
        ),
      ];
    }
    final trays = _getTraysForPrinter(printerName);
    if (trays.isNotEmpty) {
      return [
        SizedBox(width: AppSpacing.xs),
        _MiniDropdown(
          value: trays.contains(currentTray) ? currentTray : trays.first,
          items: trays,
          onChanged: (v) => onChanged(v, ''),
        ),
      ];
    }
    return [];
  }

  void _fixBackupPrinter(List<String> options, String gross, String tare) {
    if (!_backupEnabled) return;
    final backupOptions = (gross == tare)
        ? options.where((p) => p != gross).toList()
        : options;
    if (!backupOptions.contains(_backupPrinter) && backupOptions.isNotEmpty) {
      _backupPrinter = backupOptions.first;
    }
  }

  Widget _buildPrinterAssignmentBar(ColorScheme scheme, TextTheme text) {
    final printerOptions = _printerNames;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.print_rounded, size: 16, color: scheme.primary),
            SizedBox(width: AppSpacing.sm),
            Text('Printer Assignment', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            SizedBox(width: AppSpacing.xl),
            Text('1st Weighment:', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            SizedBox(width: AppSpacing.sm),
            _MiniPrinterDropdown(
              value: _grossPrinter,
              items: printerOptions,
              onChanged: (v) { setState(() { _grossPrinter = v; _grossPaperSize = ''; _grossTray = ''; _fixBackupPrinter(printerOptions, v, _tarePrinter); }); _markDirty(); },
            ),
            ..._buildTrayOrSizeSelector(_grossPrinter, _grossTray, _grossPaperSize, (tray, size) { setState(() { _grossTray = tray; _grossPaperSize = size; }); _markDirty(); }),
            SizedBox(width: AppSpacing.lg),
            Text('2nd Weighment:', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            SizedBox(width: AppSpacing.sm),
            _MiniPrinterDropdown(
              value: _tarePrinter,
              items: printerOptions,
              onChanged: (v) { setState(() { _tarePrinter = v; _tarePaperSize = ''; _tareTray = ''; _fixBackupPrinter(printerOptions, _grossPrinter, v); }); _markDirty(); },
            ),
            ..._buildTrayOrSizeSelector(_tarePrinter, _tareTray, _tarePaperSize, (tray, size) { setState(() { _tareTray = tray; _tarePaperSize = size; }); _markDirty(); }),
            SizedBox(width: AppSpacing.lg),
            _CompactToggle(label: 'Backup', value: _backupEnabled, onChanged: (v) {
              final backupAvailable = !(_grossPrinter == _tarePrinter && printerOptions.length <= 1);
              if (v && !backupAvailable) return;
              setState(() => _backupEnabled = v);
              _markDirty();
            }),
            if (_backupEnabled && _grossPrinter == _tarePrinter && printerOptions.length <= 1) ...[
              SizedBox(width: AppSpacing.sm),
              Text('No alternate printer available', style: text.bodySmall?.copyWith(color: scheme.error, fontSize: 10)),
            ] else if (_backupEnabled) ...[
              SizedBox(width: AppSpacing.sm),
              Builder(builder: (_) {
                final backupOptions = (_grossPrinter == _tarePrinter)
                    ? printerOptions.where((p) => p != _grossPrinter).toList()
                    : printerOptions;
                final effectiveValue = backupOptions.contains(_backupPrinter) ? _backupPrinter : backupOptions.first;
                return _MiniPrinterDropdown(
                  value: effectiveValue,
                  items: backupOptions,
                  onChanged: (v) { setState(() => _backupPrinter = v); _markDirty(); },
                );
              }),
              ..._buildTrayOrSizeSelector(_backupPrinter, _backupTray, _backupPaperSize, (tray, size) { setState(() { _backupTray = tray; _backupPaperSize = size; }); _markDirty(); }),
            ],
            const Spacer(),
            _CompactToggle(label: 'Material Routing', value: _materialRoutingEnabled, onChanged: (v) { setState(() => _materialRoutingEnabled = v); _markDirty(); }),
            SizedBox(width: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _showManagePrintersDialog,
              icon: const Icon(Icons.settings_rounded, size: 14),
              label: const Text('Manage Printers'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 11), shape: RoundedRectangleBorder(borderRadius: AppRadius.chip)),
            ),
          ],
        ),
        if (_materialRoutingEnabled) ...[
          SizedBox(height: AppSpacing.md),
          _buildMaterialRoutingSection(scheme, text, printerOptions),
        ],
      ],
    );
  }

  Widget _buildMaterialRoutingSection(ColorScheme scheme, TextTheme text, List<String> printerOptions) {
    return Container(
      padding: EdgeInsets.all(12.rs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10.rs),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, size: 14, color: scheme.secondary),
              SizedBox(width: 6.rs),
              Text('Route to printer by material', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _materialPrinterRules.add({'material': '', 'printer': _printerNames.first, 'tray': 'Auto', 'copies': _copies}));
                  _markDirty();
                },
                icon: const Icon(Icons.add_rounded, size: 12),
                label: const Text('Add Rule'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), textStyle: const TextStyle(fontSize: 11), shape: RoundedRectangleBorder(borderRadius: AppRadius.chip)),
              ),
            ],
          ),
          if (_materialPrinterRules.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No material routing rules. All materials use the default printer assignment above.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
            )
          else ...[
            SizedBox(height: AppSpacing.sm),
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
                          borderRadius: AppRadius.chip,
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
                    SizedBox(width: AppSpacing.sm),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: scheme.onSurfaceVariant),
                    SizedBox(width: AppSpacing.sm),
                    _MiniPrinterDropdown(
                      value: printer,
                      items: printerOptions,
                      onChanged: (v) { setState(() => _materialPrinterRules[e.key] = {...rule, 'printer': v}); _markDirty(); },
                    ),
                    if (_getTraysForPrinter(printer).isNotEmpty) ...[
                      SizedBox(width: AppSpacing.xs),
                      _MiniDropdown(value: _getTraysForPrinter(printer).contains(rule['tray'] as String? ?? '') ? (rule['tray'] as String) : _getTraysForPrinter(printer).first, items: _getTraysForPrinter(printer), onChanged: (v) { setState(() => _materialPrinterRules[e.key] = {...rule, 'tray': v}); _markDirty(); }),
                    ],
                    SizedBox(width: AppSpacing.sm),
                    Text('×', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                    SizedBox(width: AppSpacing.xs),
                    _CounterButton(value: copies, min: 1, max: 10, onChanged: (v) { setState(() => _materialPrinterRules[e.key] = {...rule, 'copies': v}); _markDirty(); }),
                    SizedBox(width: AppSpacing.sm),
                    _MiniDropdown(value: printOn, items: const ['—', '1st', '2nd', 'both'], onChanged: (v) { setState(() => _materialPrinterRules[e.key] = {...rule, 'printOn': v}); _markDirty(); }),
                    SizedBox(width: AppSpacing.sm),
                    InkWell(
                      onTap: () { setState(() => _materialPrinterRules.removeAt(e.key)); _markDirty(); },
                      child: Padding(padding: EdgeInsets.all(4.rs), child: Icon(Icons.close_rounded, size: 14, color: scheme.error)),
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

    Widget buildItem(String key, String label, Color chipColor) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 140,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: chipColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(3.rs),
              ),
              child: Text(key, style: TextStyle(fontFamily: 'monospace', fontSize: 9.5, fontWeight: FontWeight.w600, color: chipColor, letterSpacing: -0.3)),
            ),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(label, style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant))),
          ],
        ),
      );
    }

    return _Section(scheme: scheme, icon: Icons.code_rounded, title: 'Placeholders', children: [
      Text('Tokens are replaced with actual data when printing.', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
      ...['Company', 'Customer', 'Weighment', 'System'].map((cat) {
        final items = _builtInPlaceholders.where((p) => p.category == cat).toList();
        final catColor = cat == 'Company' ? scheme.primary
            : cat == 'Customer' ? scheme.tertiary
            : cat == 'System' ? scheme.secondary
            : scheme.primary;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 3),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 11,
                    decoration: BoxDecoration(color: catColor, borderRadius: BorderRadius.circular(2)),
                  ),
                  SizedBox(width: 6.rs),
                  Text(cat, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: catColor)),
                ],
              ),
            ),
            ...items.map((p) => buildItem(p.key, p.label, catColor)),
          ],
        );
      }),
      if (customFields.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 3),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 11,
                decoration: BoxDecoration(color: scheme.secondary, borderRadius: BorderRadius.circular(2)),
              ),
              SizedBox(width: 6.rs),
              Text('Custom Fields', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: scheme.secondary)),
            ],
          ),
        ),
        ...customFields.asMap().entries.map((e) {
          final label = e.value['label'] as String;
          final key = '{custom_${e.key + 1}}';
          return buildItem(key, label, scheme.secondary);
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
        SizedBox(height: AppSpacing.xs),
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
        SizedBox(height: AppSpacing.xs),
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
      padding: AppSpacing.pagePadding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.dialog,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: scheme.primary),
            SizedBox(width: AppSpacing.sm),
            Flexible(child: Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
          ]),
          SizedBox(height: 14.rs),
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
      decoration: BoxDecoration(borderRadius: AppRadius.button, border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: value > min ? () => onChanged(value - 1) : null,
            child: Padding(padding: EdgeInsets.all(6.rs), child: Icon(Icons.remove_rounded, size: 14, color: value > min ? scheme.primary : scheme.outlineVariant)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('$value', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface)),
          ),
          InkWell(
            onTap: value < max ? () => onChanged(value + 1) : null,
            child: Padding(padding: EdgeInsets.all(6.rs), child: Icon(Icons.add_rounded, size: 14, color: value < max ? scheme.primary : scheme.outlineVariant)),
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
          borderRadius: AppRadius.chip,
          border: Border.all(color: value ? scheme.primary.withValues(alpha: 0.4) : scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(value ? Icons.check_circle_rounded : Icons.circle_outlined, size: 12, color: value ? scheme.primary : scheme.outlineVariant),
            SizedBox(width: AppSpacing.xs),
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
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: AppRadius.chip,
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: widget.onMoveUp,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    child: Icon(Icons.arrow_drop_up_rounded, size: 20, color: widget.onMoveUp != null ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                ),
                Container(height: 1, width: 16, color: scheme.outlineVariant.withValues(alpha: 0.3)),
                InkWell(
                  onTap: widget.onMoveDown,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    child: Icon(Icons.arrow_drop_down_rounded, size: 20, color: widget.onMoveDown != null ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 6.rs),
          Expanded(
            child: isNoText
                ? Container(
                    height: 34,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: AppRadius.chip,
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
                      border: OutlineInputBorder(borderRadius: AppRadius.chip, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
                    ),
                  ),
          ),
          SizedBox(width: 6.rs),
          _MiniDropdown(value: align, items: const ['left', 'center', 'right'], onChanged: (v) => widget.onChanged({...widget.line, 'align': v})),
          SizedBox(width: AppSpacing.xs),
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
          SizedBox(width: AppSpacing.xs),
          _MiniDropdown(
            value: group == 0 ? '—' : 'G$group',
            items: ['—', ...List.generate(((widget.totalLines + 1) / 2).ceil().clamp(1, 10), (i) => 'G${i + 1}')],
            onChanged: (v) => widget.onChanged({...widget.line, 'group': v == '—' ? 0 : int.parse(v.substring(1))}),
          ),
          SizedBox(width: 6.rs),
          InkWell(
            onTap: widget.onRemove,
            borderRadius: AppRadius.chip,
            child: Container(
              padding: EdgeInsets.all(4.rs),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: AppRadius.chip,
              ),
              child: Icon(Icons.close_rounded, size: 16, color: scheme.error),
            ),
          ),
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
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: AppRadius.chip,
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: widget.onMoveUp,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    child: Icon(Icons.arrow_drop_up_rounded, size: 20, color: widget.onMoveUp != null ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                ),
                Container(height: 1, width: 16, color: scheme.outlineVariant.withValues(alpha: 0.3)),
                InkWell(
                  onTap: widget.onMoveDown,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    child: Icon(Icons.arrow_drop_down_rounded, size: 20, color: widget.onMoveDown != null ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 6.rs),
          Expanded(
            child: isSeparator
                ? Container(
                    height: 34,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: AppRadius.chip,
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
                      border: OutlineInputBorder(borderRadius: AppRadius.chip, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
                    ),
                  ),
          ),
          SizedBox(width: 6.rs),
          _MiniDropdown(value: align, items: const ['left', 'center', 'right'], onChanged: (v) => widget.onChanged({...widget.line, 'align': v})),
          SizedBox(width: AppSpacing.xs),
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
          SizedBox(width: AppSpacing.xs),
          _MiniDropdown(value: group == 0 ? '—' : 'G$group', items: ['—', 'G1', 'G2', 'G3', 'G4', 'G5', 'G6', 'G7', 'G8'], onChanged: (v) => widget.onChanged({...widget.line, 'group': v == '—' ? 0 : int.parse(v.substring(1))})),
          SizedBox(width: 6.rs),
          InkWell(
            onTap: widget.onRemove,
            borderRadius: AppRadius.chip,
            child: Container(
              padding: EdgeInsets.all(4.rs),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: AppRadius.chip,
              ),
              child: Icon(Icons.close_rounded, size: 16, color: scheme.error),
            ),
          ),
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
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(4.rs), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3))),
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
      decoration: BoxDecoration(borderRadius: AppRadius.chip, border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3))),
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
            borderRadius: BorderRadius.circular(4.rs),
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
                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(4.rs)),
                child: const Text('Content exceeds page', style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
      ],
    );
  }
}

class _MiniChipDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  const _MiniChipDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: AppRadius.button,
        border: Border.all(color: scheme.outline.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
          SizedBox(width: 6.rs),
          SizedBox(
            height: 22,
            child: DropdownButton<String>(
              value: items.contains(value) ? value : items.first,
              items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 11)))).toList(),
              onChanged: (v) { if (v != null) onChanged(v); },
              underline: const SizedBox.shrink(),
              isDense: true,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: scheme.onSecondaryContainer),
              icon: Icon(Icons.arrow_drop_down, size: 16, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
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

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashW = 4.0;
    const gapW = 3.0;
    final y = size.height / 2;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset((x + dashW).clamp(0, size.width), y), paint);
      x += dashW + gapW;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
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
