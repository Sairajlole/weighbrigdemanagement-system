import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PrintService {
  final FirebaseFirestore _db;

  PrintService(this._db);

  // ─── Data Fetching ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _fetchCompanyInfo() async {
    final doc = await _db.collection('settings').doc('general').get();
    return doc.exists ? doc.data()! : {};
  }

  Future<Uint8List?> _fetchCompanyLogo() async {
    final doc = await _db.collection('settings').doc('general_docs').get();
    if (!doc.exists) return null;
    final dataUri = doc.data()?['company_logo'] as String?;
    if (dataUri == null || !dataUri.startsWith('data:')) return null;
    final b64 = dataUri.split(',').last;
    return base64Decode(b64);
  }

  Future<Map<String, dynamic>> _fetchPrintSettings() async {
    final doc = await _db.collection('settings').doc('printing').get();
    return doc.exists ? doc.data()! : {};
  }

  Future<Map<String, dynamic>?> fetchWeighment(String weighmentId) async {
    final doc = await _db.collection('weighments').doc(weighmentId).get();
    return doc.exists ? {'id': doc.id, ...doc.data()!} : null;
  }

  Future<List<Map<String, dynamic>>> _fetchCustomFields() async {
    final doc = await _db.collection('settings').doc('customFields').get();
    if (!doc.exists) return [];
    final fields = doc.data()?['fields'] as List<dynamic>?;
    if (fields == null) return [];
    return fields
        .map((f) => Map<String, dynamic>.from(f as Map))
        .where((f) => f['enabled'] == true)
        .toList();
  }

  Future<String> _fetchScalePort() async {
    final doc = await _db.collection('settings').doc('scale').get();
    return doc.exists ? (doc.data()?['port'] as String? ?? '') : '';
  }

  // ─── Placeholder Substitution ──────────────────────────────────────────────

  Map<String, String> _buildPlaceholderMap({
    required Map<String, dynamic> company,
    required Map<String, dynamic> weighment,
    required String dateFormat,
    required String timeFormat,
    List<Map<String, dynamic>> customFields = const [],
    String scalePort = '',
  }) {
    final df = _getDateFormat(dateFormat);
    final tf = _getTimeFormat(timeFormat);

    String formatTs(dynamic ts) {
      if (ts == null) return '';
      DateTime dt;
      if (ts is Timestamp) {
        dt = ts.toDate();
      } else if (ts is DateTime) {
        dt = ts;
      } else {
        return ts.toString();
      }
      return '${df.format(dt)} ${tf.format(dt)}';
    }

    final gross = (weighment['grossWeight'] as num?)?.toDouble() ?? 0;
    final tare = (weighment['tareWeight'] as num?)?.toDouble() ?? 0;
    final net = weighment['netWeight'] as num? ?? (gross - tare);

    final map = <String, String>{
      '{company_name}': company['companyName'] as String? ?? '',
      '{company_address1}': company['address1'] as String? ?? '',
      '{company_address2}': company['address2'] as String? ?? '',
      '{company_phone}': company['phone'] as String? ?? '',
      '{company_gstin}': company['gstin'] as String? ?? '',
      '{customer_name}': weighment['customerName'] as String? ?? 'Walk-in',
      '{customer_address}': weighment['customerAddress'] as String? ?? '',
      '{customer_phone}': weighment['customerPhone'] as String? ?? '',
      '{vehicle}': weighment['vehicleNumber'] as String? ?? '',
      '{material}': weighment['material'] as String? ?? '',
      '{gross}': _padWeight(gross, tare, net, gross),
      '{tare}': _padWeight(gross, tare, net, tare),
      '{net}': _padWeight(gross, tare, net, net.toDouble()),
      '{gross_datetime}': formatTs(weighment['grossDateTime']),
      '{tare_datetime}': formatTs(weighment['tareDateTime']),
      '{net_datetime}': formatTs(weighment['netDateTime'] ?? weighment['tareDateTime']),
      '{rst}': weighment['rstNumber'] as String? ?? '',
      '{operator}': weighment['operatorName'] as String? ?? '',
      '{date}': df.format(DateTime.now()),
      '{pc_name}': Platform.localHostname,
      '{port_name}': scalePort,
      '{weighbridge_name}': company['weighbridgeName'] as String? ?? '',
    };

    for (final field in customFields) {
      final label = field['label'] as String? ?? '';
      if (label.isNotEmpty) {
        map['{custom_$label}'] = weighment['custom_$label'] as String? ?? '';
      }
    }

    return map;
  }

  static String _padWeight(double gross, double tare, num net, double value) {
    final gs = gross.toStringAsFixed(0);
    final ts = tare.toStringAsFixed(0);
    final ns = net.toStringAsFixed(0);
    final maxLen = [gs.length, ts.length, ns.length].reduce((a, b) => a > b ? a : b);
    return value.toStringAsFixed(0).padLeft(maxLen);
  }

  String _substitutePlaceholders(String template, Map<String, String> values) {
    var result = template;
    for (final entry in values.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }


  DateFormat _getDateFormat(String format) {
    return switch (format) {
      'MM/DD/YYYY' => DateFormat('MM/dd/yyyy'),
      'YYYY-MM-DD' => DateFormat('yyyy-MM-dd'),
      _ => DateFormat('dd/MM/yyyy'),
    };
  }

  DateFormat _getTimeFormat(String format) {
    return switch (format) {
      '12-hour' => DateFormat('hh:mm:ss a'),
      _ => DateFormat('HH:mm:ss'),
    };
  }

  // ─── Test Print ─────────────────────────────────────────────────────────────

  Future<PrintResult> testPrint({required String type}) async {
    try {
      final results = await Future.wait([
        _fetchCompanyInfo(),
        _fetchPrintSettings(),
        _fetchCompanyLogo(),
        _fetchCustomFields(),
        _fetchScalePort(),
      ]);

      final company = results[0] as Map<String, dynamic>;
      final settings = results[1] as Map<String, dynamic>;
      final logo = results[2] as Uint8List?;
      final customFields = results[3] as List<Map<String, dynamic>>;
      final scalePort = results[4] as String;

      final now = DateTime.now();
      final sampleWeighment = <String, dynamic>{
        'customerName': 'Sample Customer',
        'customerAddress': 'Customer Address',
        'customerPhone': '+91 91234 56789',
        'vehicleNumber': 'MH-12-AB-1234',
        'material': 'Iron Ore',
        'grossWeight': 48520,
        'tareWeight': 16200,
        'netWeight': 32320,
        'grossDateTime': now.subtract(const Duration(hours: 2)),
        'tareDateTime': now,
        'netDateTime': now,
        'rstNumber': '1042',
        'operatorName': 'Rajesh Kumar',
        'status': 'completed',
      };

      final placeholders = _buildPlaceholderMap(
        company: company,
        weighment: sampleWeighment,
        dateFormat: company['dateFormat'] as String? ?? 'DD/MM/YYYY',
        timeFormat: company['timeFormat'] as String? ?? '24-hour',
        customFields: customFields,
        scalePort: scalePort,
      );

      switch (type) {
        case 'thermal':
          return await _printThermal(settings, placeholders, logo, 'default', 1);
        case 'dm':
          return await _printDotMatrix(settings, placeholders, logo, 'default', 1);
        case 'normal':
          return await _printNormal(settings, placeholders, logo, company, 'default', 1);
        default:
          return PrintResult(success: false, error: 'Unknown type: $type');
      }
    } catch (e) {
      return PrintResult(success: false, error: e.toString());
    }
  }

  // ─── Print Execution ───────────────────────────────────────────────────────

  Future<PrintResult> printWeighment({
    required String weighmentId,
    String? printerType,
    String? printerName,
  }) async {
    try {
      final results = await Future.wait([
        _fetchCompanyInfo(),
        _fetchPrintSettings(),
        fetchWeighment(weighmentId),
        _fetchCompanyLogo(),
        _fetchCustomFields(),
        _fetchScalePort(),
      ]);

      final company = results[0] as Map<String, dynamic>;
      final settings = results[1] as Map<String, dynamic>;
      final weighment = results[2] as Map<String, dynamic>?;
      final logo = results[3] as Uint8List?;
      final customFields = results[4] as List<Map<String, dynamic>>;
      final scalePort = results[5] as String;

      if (weighment == null) {
        return PrintResult(success: false, error: 'Weighment not found');
      }

      final dateFormat = company['dateFormat'] as String? ?? 'DD/MM/YYYY';
      final timeFormat = company['timeFormat'] as String? ?? '24-hour';
      final placeholders = _buildPlaceholderMap(
        company: company,
        weighment: weighment,
        dateFormat: dateFormat,
        timeFormat: timeFormat,
        customFields: customFields,
        scalePort: scalePort,
      );

      final type = printerType ?? _determinePrinterType(settings, weighment);
      final targetPrinter = printerName ?? _resolveTargetPrinter(settings, weighment, type);
      final targetTray = _resolveTargetTray(settings, weighment);
      final copies = settings['copies'] as int? ?? 2;

      switch (type) {
        case 'thermal':
          return await _printThermal(settings, placeholders, logo, targetPrinter, copies, tray: targetTray);
        case 'dm':
          return await _printDotMatrix(settings, placeholders, logo, targetPrinter, copies, tray: targetTray);
        case 'normal':
          return await _printNormal(settings, placeholders, logo, company, targetPrinter, copies, tray: targetTray);
        default:
          return PrintResult(success: false, error: 'Unknown printer type: $type');
      }
    } catch (e) {
      return PrintResult(success: false, error: e.toString());
    }
  }

  String _determinePrinterType(Map<String, dynamic> settings, Map<String, dynamic> weighment) {
    final hasThermal = (settings['thermalLines'] as List?)?.isNotEmpty == true;
    final hasDm = (settings['dmLines'] as List?)?.isNotEmpty == true;
    final hasNormal = (settings['normalLines'] as List?)?.isNotEmpty == true;
    if (hasNormal) return 'normal';
    if (hasThermal) return 'thermal';
    if (hasDm) return 'dm';
    return 'normal';
  }

  String _resolveToSystemName(String displayName, List<Map<String, dynamic>> printers) {
    if (displayName.isEmpty || displayName == 'default') return '';
    for (final p in printers) {
      final nickname = p['nickname'] as String? ?? '';
      final sysName = p['name'] as String? ?? '';
      if (nickname.isNotEmpty && nickname == displayName) return sysName;
      if (sysName == displayName) return sysName;
    }
    return displayName;
  }

  String _resolveTargetPrinter(Map<String, dynamic> settings, Map<String, dynamic> weighment, String type) {
    final printers = (settings['printers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final status = weighment['status'] as String? ?? '';
    final materialRoutingEnabled = settings['materialRoutingEnabled'] as bool? ?? false;

    if (materialRoutingEnabled) {
      final rules = (settings['materialPrinterRules'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final material = weighment['material'] as String? ?? '';
      for (final rule in rules) {
        if (rule['material'] == material) {
          return _resolveToSystemName(rule['printer'] as String? ?? '', printers);
        }
      }
    }

    final displayName = status == 'awaitingTare'
        ? settings['grossPrinter'] as String? ?? ''
        : settings['tarePrinter'] as String? ?? '';
    return _resolveToSystemName(displayName, printers);
  }

  String _resolveTargetTray(Map<String, dynamic> settings, Map<String, dynamic> weighment) {
    final status = weighment['status'] as String? ?? '';
    final materialRoutingEnabled = settings['materialRoutingEnabled'] as bool? ?? false;

    if (materialRoutingEnabled) {
      final rules = (settings['materialPrinterRules'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final material = weighment['material'] as String? ?? '';
      for (final rule in rules) {
        if (rule['material'] == material) {
          return rule['tray'] as String? ?? '';
        }
      }
    }

    if (status == 'awaitingTare') {
      return settings['grossTray'] as String? ?? '';
    }
    return settings['tareTray'] as String? ?? '';
  }

  // ─── Thermal Printing ──────────────────────────────────────────────────────

  Uint8List _logoToEscPosRaster(Uint8List logoBytes, int maxWidthPx) {
    var decoded = img.decodeImage(logoBytes);
    if (decoded == null) return Uint8List(0);

    if (decoded.width > maxWidthPx) {
      decoded = img.copyResize(decoded, width: maxWidthPx);
    }

    final grayscale = img.grayscale(decoded);
    final mono = img.ditherImage(grayscale);
    final width = mono.width;
    final height = mono.height;
    final bytesPerRow = (width + 7) ~/ 8;

    // GS v 0 — raster bit image command
    final output = <int>[
      0x1D, 0x76, 0x30, 0x00, // GS v 0 m
      bytesPerRow & 0xFF, (bytesPerRow >> 8) & 0xFF,
      height & 0xFF, (height >> 8) & 0xFF,
    ];

    for (var y = 0; y < height; y++) {
      for (var byteX = 0; byteX < bytesPerRow; byteX++) {
        var byte = 0;
        for (var bit = 0; bit < 8; bit++) {
          final x = byteX * 8 + bit;
          if (x < width) {
            final pixel = mono.getPixel(x, y);
            if (img.getLuminance(pixel) < 128) {
              byte |= (0x80 >> bit);
            }
          }
        }
        output.add(byte);
      }
    }

    return Uint8List.fromList(output);
  }

  Future<PrintResult> _printThermal(
    Map<String, dynamic> settings,
    Map<String, String> placeholders,
    Uint8List? logo,
    String printer,
    int copies, {
    String tray = '',
  }) async {
    final lines = (settings['thermalLines'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final charWidth = (settings['thermalWidth'] as String? ?? '80mm') == '80mm' ? 48 : 32;
    final showLogo = settings['thermalLogo'] as bool? ?? true;
    final maxLogoPx = (settings['thermalWidth'] as String? ?? '80mm') == '80mm' ? 384 : 192;
    final font = settings['thermalFont'] as String? ?? 'Font A';
    final fontSize = settings['thermalFontSize'] as int? ?? 12;

    Uint8List? logoRaster;
    if (showLogo && logo != null) {
      logoRaster = _logoToEscPosRaster(logo, maxLogoPx);
    }

    // ESC/POS init + font select + size
    final initCmds = <int>[
      0x1B, 0x40, // ESC @ — initialize
      0x1B, 0x4D, font == 'Font B' ? 0x01 : font == 'Font C' ? 0x02 : 0x00, // ESC M n — font select
      0x1D, 0x21, fontSize >= 16 ? 0x11 : fontSize >= 14 ? 0x01 : 0x00, // GS ! n — character size
    ];

    final buf = StringBuffer();
    for (final line in lines) {
      final text = line['text'] as String? ?? '';
      final size = line['size'] as String? ?? 'normal';
      final align = line['align'] as String? ?? 'left';

      if (size == 'separator') {
        buf.writeln('-' * charWidth);
        continue;
      }

      final substituted = _substitutePlaceholders(text, placeholders);
      buf.writeln(_alignText(substituted, charWidth, align));
    }

    final textBytes = Uint8List.fromList(utf8.encode(buf.toString()));

    // PDF417 barcode raster
    final showPdf417 = settings['thermalPdf417'] as bool? ?? true;
    Uint8List? barcodeRaster;
    if (showPdf417) {
      final barcodeData = _buildBarcodeDataFromLines(lines, placeholders);
      barcodeRaster = _barcodeToEscPosRaster(barcodeData, maxLogoPx);
    }

    final centerCmd = Uint8List.fromList([0x1B, 0x61, 0x01]);
    final leftCmd = Uint8List.fromList([0x1B, 0x61, 0x00]);

    final parts = <int>[...initCmds];
    if (logoRaster != null && logoRaster.isNotEmpty) {
      parts.addAll(centerCmd);
      parts.addAll(logoRaster);
      parts.addAll(leftCmd);
    }
    parts.addAll(textBytes);
    if (barcodeRaster != null && barcodeRaster.isNotEmpty) {
      parts.addAll(centerCmd);
      parts.addAll(barcodeRaster);
      parts.addAll(leftCmd);
    }

    return _sendBinaryRawToLpr(Uint8List.fromList(parts), printer, copies, tray: tray);
  }

  Uint8List _barcodeToEscPosRaster(String data, int maxWidthPx) {
    final bc = Barcode.pdf417();
    final targetWidthPx = maxWidthPx;
    const targetHeightPx = 60;
    final elements = bc.make(data, width: targetWidthPx.toDouble(), height: targetHeightPx.toDouble());

    final bitmap = img.Image(width: targetWidthPx, height: targetHeightPx);
    img.fill(bitmap, color: img.ColorRgba8(255, 255, 255, 255));
    final black = img.ColorRgba8(0, 0, 0, 255);
    for (final elem in elements) {
      if (elem is BarcodeBar && elem.black) {
        final x1 = elem.left.round().clamp(0, targetWidthPx - 1);
        final x2 = (elem.left + elem.width).round().clamp(0, targetWidthPx);
        final y1 = elem.top.round().clamp(0, targetHeightPx - 1);
        final y2 = (elem.top + elem.height).round().clamp(0, targetHeightPx);
        for (var y = y1; y < y2; y++) {
          for (var x = x1; x < x2; x++) {
            bitmap.setPixel(x, y, black);
          }
        }
      }
    }

    // Convert to ESC/POS raster bit-image (GS v 0)
    final bytesPerRow = (targetWidthPx + 7) ~/ 8;
    final output = <int>[
      0x1D, 0x76, 0x30, 0x00, // GS v 0 — raster bit image
      bytesPerRow & 0xFF, (bytesPerRow >> 8) & 0xFF,
      targetHeightPx & 0xFF, (targetHeightPx >> 8) & 0xFF,
    ];
    for (var y = 0; y < targetHeightPx; y++) {
      for (var byteIdx = 0; byteIdx < bytesPerRow; byteIdx++) {
        var byte = 0;
        for (var bit = 0; bit < 8; bit++) {
          final x = byteIdx * 8 + bit;
          if (x < targetWidthPx) {
            final pixel = bitmap.getPixel(x, y);
            if (img.getLuminance(pixel) < 128) {
              byte |= (0x80 >> bit);
            }
          }
        }
        output.add(byte);
      }
    }
    return Uint8List.fromList(output);
  }

  Future<PrintResult> _sendBinaryRawToLpr(Uint8List data, String printer, int copies, {String tray = ''}) async {
    try {
      final tmpFile = File('${Directory.systemTemp.path}/weighbridge_thermal_${DateTime.now().millisecondsSinceEpoch}.prn');
      await tmpFile.writeAsBytes(data);

      final args = <String>['-#', '$copies', '-o', 'raw'];
      if (tray.isNotEmpty && tray != 'Auto') {
        args.addAll(['-o', 'InputSlot=$tray']);
      }
      if (printer.isNotEmpty && printer != 'default') {
        args.addAll(['-P', printer]);
      }
      args.add(tmpFile.path);

      final result = await Process.run('lpr', args);
      await tmpFile.delete().catchError((_) => tmpFile);

      if (result.exitCode != 0) {
        return PrintResult(success: false, error: 'lpr failed: ${result.stderr}');
      }
      return PrintResult(success: true);
    } catch (e) {
      return PrintResult(success: false, error: e.toString());
    }
  }

  // ─── Dot Matrix Printing ───────────────────────────────────────────────────

  Uint8List _logoToEscpBitImage(Uint8List logoBytes, int targetWidthPx) {
    var decoded = img.decodeImage(logoBytes);
    if (decoded == null) return Uint8List(0);

    // Resize to target width, maintaining aspect ratio
    if (decoded.width != targetWidthPx) {
      decoded = img.copyResize(decoded, width: targetWidthPx);
    }

    // Convert to monochrome (1-bit dithered)
    final grayscale = img.grayscale(decoded);
    final mono = img.ditherImage(grayscale);

    final width = mono.width;
    final height = mono.height;

    // ESC/P 8-pin bit-image mode: ESC * 0 nL nH [data...]
    // Each column is 8 vertical dots (1 byte), sent left-to-right per stripe
    final output = <int>[];
    for (var stripe = 0; stripe < height; stripe += 8) {
      // ESC * m nL nH — select bit image mode 0 (single density)
      output.addAll([0x1B, 0x2A, 0, width & 0xFF, (width >> 8) & 0xFF]);

      for (var x = 0; x < width; x++) {
        var byte = 0;
        for (var bit = 0; bit < 8; bit++) {
          final y = stripe + bit;
          if (y < height) {
            final pixel = mono.getPixel(x, y);
            // Dark pixel = bit set (print dot)
            if (img.getLuminance(pixel) < 128) {
              byte |= (0x80 >> bit);
            }
          }
        }
        output.add(byte);
      }
      output.addAll([0x0D, 0x0A]); // CR+LF after each stripe
    }

    return Uint8List.fromList(output);
  }

  Future<PrintResult> _printDotMatrix(
    Map<String, dynamic> settings,
    Map<String, String> placeholders,
    Uint8List? logo,
    String printer,
    int copies, {
    String tray = '',
  }) async {
    final lines = (settings['dmLines'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final columns = settings['dmColumns'] as int? ?? 100;
    final showLogo = settings['dmLogo'] as bool? ?? false;
    final marginLeft = settings['dmMarginLeft'] as int? ?? 2;
    final logoWidth = settings['dmLogoWidth'] as int? ?? 12;

    final buf = StringBuffer();
    final leftPad = ' ' * marginLeft;

    final contentWidth = columns - marginLeft * 2;

    // Logo is sent as binary ESC/P before the text content
    Uint8List? logoBinary;
    if (showLogo && logo != null) {
      final targetPx = logoWidth * 6;
      logoBinary = _logoToEscpBitImage(logo, targetPx);
    }

    var li = 0;
    while (li < lines.length) {
      final line = lines[li];
      final text = line['text'] as String? ?? '';
      final style = line['style'] as String? ?? 'normal';
      final align = line['align'] as String? ?? 'left';
      final group = line['group'] as int? ?? 0;

      if (style == 'separator') {
        buf.writeln('$leftPad${'-' * contentWidth}');
        li++;
        continue;
      }

      final substituted = _substitutePlaceholders(text, placeholders);

      if (group > 0) {
        final groupLines = <Map<String, dynamic>>[];
        final currentGroup = group;
        while (li < lines.length && (lines[li]['group'] as int? ?? 0) == currentGroup) {
          groupLines.add(lines[li]);
          li++;
        }
        final colWidth = contentWidth ~/ groupLines.length;
        final rowBuf = StringBuffer(leftPad);
        for (final gl in groupLines) {
          final gText = _substitutePlaceholders(gl['text'] as String? ?? '', placeholders);
          final gAlign = gl['align'] as String? ?? 'left';
          rowBuf.write(_alignText(gText, colWidth, gAlign));
        }
        buf.writeln(rowBuf.toString());
      } else {
        buf.writeln('$leftPad${_alignText(substituted, contentWidth, align)}');
        li++;
      }
    }

    // If logo binary present, send raw (ESC/P binary needs raw mode)
    final prefix = logoBinary ?? Uint8List(0);
    if (prefix.isNotEmpty) {
      final escpInit = <int>[
        0x1B, 0x40, // ESC @ - Initialize printer
        0x1B, 0x50, // ESC P - 10 CPI
        0x1B, 0x32, // ESC 2 - 6 LPI
      ];
      final textBytes = Uint8List.fromList(utf8.encode(buf.toString()));
      final combined = Uint8List.fromList([...escpInit, ...prefix, ...textBytes]);
      return _sendBinaryRawToLpr(combined, printer, copies, tray: tray);
    }
    // Text only: plain lpr (actual DM printer handles spacing natively)
    return _sendDmTextToLpr(buf.toString(), printer, copies, tray: tray);
  }


  // ─── Normal (PDF) Printing ─────────────────────────────────────────────────

  Future<PrintResult> _printNormal(
    Map<String, dynamic> settings,
    Map<String, String> placeholders,
    Uint8List? logo,
    Map<String, dynamic> company,
    String printer,
    int copies, {
    String tray = '',
  }) async {
    final paperSize = settings['normalPaperSize'] as String? ?? 'A4';
    final perSizeConfigs = settings['perSizeConfigs'] as Map<String, dynamic>?;
    final sizeConfig = perSizeConfigs?[paperSize] as Map<String, dynamic>? ?? settings;

    final marginTop = (sizeConfig['marginTop'] as num?)?.toDouble() ?? 15;
    final marginBottom = (sizeConfig['marginBottom'] as num?)?.toDouble() ?? 15;
    final marginLeft = (sizeConfig['marginLeft'] as num?)?.toDouble() ?? 15;
    final marginRight = (sizeConfig['marginRight'] as num?)?.toDouble() ?? 15;
    final showLogo = sizeConfig['logo'] as bool? ?? settings['normalLogo'] as bool? ?? true;
    final headerLayout = sizeConfig['headerLayout'] as String? ?? 'inline';
    final headerRows = sizeConfig['headerRows'] as int? ?? 3;
    final fontSize = (sizeConfig['fontSize'] as num?)?.toDouble() ?? 14;
    final fontName = settings['normalFont'] as String? ?? 'Helvetica';
    final logoWidth = (sizeConfig['logoWidth'] as num?)?.toDouble() ?? 80;
    final logoHeight = (sizeConfig['logoHeight'] as num?)?.toDouble() ?? 80;
    final lines = (sizeConfig['normalLines'] as List? ?? settings['normalLines'] as List? ?? [])
        .cast<Map<String, dynamic>>();

    final pageFormat = _getPageFormat(paperSize).copyWith(
      marginTop: marginTop * PdfPageFormat.mm,
      marginBottom: marginBottom * PdfPageFormat.mm,
      marginLeft: marginLeft * PdfPageFormat.mm,
      marginRight: marginRight * PdfPageFormat.mm,
    );

    pw.Font pdfFont;
    pw.Font pdfFontBold;
    switch (fontName) {
      case 'Times':
        pdfFont = pw.Font.times();
        pdfFontBold = pw.Font.timesBold();
        break;
      case 'Courier':
        pdfFont = pw.Font.courier();
        pdfFontBold = pw.Font.courierBold();
        break;
      default:
        pdfFont = pw.Font.helvetica();
        pdfFontBold = pw.Font.helveticaBold();
    }

    final pdf = pw.Document();
    pw.ImageProvider? logoImage;
    if (showLogo && logo != null) {
      try {
        logoImage = pw.MemoryImage(logo);
      } catch (_) {}
    }

    final showPdf417 = sizeConfig['pdf417'] as bool? ?? settings['normalPdf417'] as bool? ?? true;
    final pdf417Position = sizeConfig['pdf417Position'] as String? ?? settings['normalPdf417Position'] as String? ?? 'bottom';
    final showCctv = sizeConfig['cctv'] as bool? ?? settings['normalCctv'] as bool? ?? false;
    final cctvCameras = ((sizeConfig['cctvCameras'] ?? settings['normalCctvCameras']) as List?)?.cast<String>() ?? [];

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        theme: pw.ThemeData.withFont(base: pdfFont, bold: pdfFontBold),
        build: (context) {
          final widgets = <pw.Widget>[];

          // Header with logo
          if (logoImage != null && headerLayout == 'inline') {
            final headerLineWidgets = <pw.Widget>[];
            var hi = 0;
            var rowsConsumed = 0;
            while (hi < lines.length && rowsConsumed < headerRows) {
              final hLine = lines[hi];
              final hGroup = hLine['group'] as int? ?? 0;
              if (hGroup > 0) {
                final gLines = <Map<String, dynamic>>[];
                while (hi < lines.length && (lines[hi]['group'] as int? ?? 0) == hGroup) {
                  gLines.add(lines[hi]);
                  hi++;
                }
                headerLineWidgets.add(_buildPdfGroupRow(gLines, placeholders, fontSize));
              } else {
                headerLineWidgets.add(_buildPdfLine(lines[hi], placeholders, fontSize));
                hi++;
              }
              rowsConsumed++;
            }

            widgets.add(pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Image(logoImage, width: logoWidth, height: logoHeight),
                pw.SizedBox(width: 12),
                pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: headerLineWidgets)),
              ],
            ));
            widgets.add(pw.SizedBox(height: 3));

            _addPdfLines(widgets, lines, hi, placeholders, fontSize);
          } else if (logoImage != null && headerLayout == 'stacked') {
            widgets.add(pw.Center(child: pw.Image(logoImage, width: logoWidth, height: logoHeight)));
            widgets.add(pw.SizedBox(height: 3));
            _addPdfLines(widgets, lines, 0, placeholders, fontSize);
          } else {
            _addPdfLines(widgets, lines, 0, placeholders, fontSize);
          }

          // PDF417 barcode (afterText position)
          if (showPdf417 && pdf417Position == 'afterText') {
            final barcodeData = _buildBarcodeDataFromLines(lines, placeholders);
            widgets.add(pw.SizedBox(height: 12));
            widgets.add(pw.SizedBox(
              width: double.infinity,
              height: 80,
              child: pw.BarcodeWidget(barcode: Barcode.pdf417(), data: barcodeData),
            ));
          }

          // CCTV snapshot placeholders (16:9 aspect ratio)
          if (showCctv && cctvCameras.isNotEmpty) {
            widgets.add(pw.SizedBox(height: 10));
            widgets.add(pw.Divider(thickness: 0.5));
            widgets.add(pw.SizedBox(height: 4));
            // Available content width for 2 boxes per row
            final contentW = pageFormat.availableWidth;
            final boxWidth = (contentW - 8) / 2; // 2 boxes with 4pt margin each side
            final boxHeight = boxWidth * 9 / 16; // 16:9 aspect ratio
            for (var ci = 0; ci < cctvCameras.length; ci += 2) {
              final rowCams = cctvCameras.skip(ci).take(2).toList();
              widgets.add(pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Row(
                  children: rowCams.map((cam) => pw.Expanded(
                    child: pw.Container(
                      height: boxHeight,
                      margin: const pw.EdgeInsets.symmetric(horizontal: 2),
                      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                      child: pw.Center(child: pw.Text(cam, style: pw.TextStyle(fontSize: fontSize - 2, color: PdfColors.grey600))),
                    ),
                  )).toList(),
                ),
              ));
            }
          }

          // PDF417 barcode (bottom position)
          if (showPdf417 && pdf417Position == 'bottom') {
            final barcodeData = _buildBarcodeDataFromLines(lines, placeholders);
            widgets.add(pw.SizedBox(height: 4));
            widgets.add(pw.SizedBox(
              width: double.infinity,
              height: 80,
              child: pw.BarcodeWidget(barcode: Barcode.pdf417(), data: barcodeData),
            ));
          }

          return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: widgets);
        },
      ),
    );

    final pdfBytes = await pdf.save();
    return _sendPdfToLpr(pdfBytes, printer, copies, tray: tray);
  }

  void _addPdfLines(List<pw.Widget> widgets, List<Map<String, dynamic>> lines, int startIdx, Map<String, String> placeholders, double fontSize) {
    var i = startIdx;
    while (i < lines.length) {
      final line = lines[i];
      final group = line['group'] as int? ?? 0;
      if (group > 0) {
        final groupLines = <Map<String, dynamic>>[];
        final currentGroup = group;
        while (i < lines.length && (lines[i]['group'] as int? ?? 0) == currentGroup) {
          groupLines.add(lines[i]);
          i++;
        }
        widgets.add(_buildPdfGroupRow(groupLines, placeholders, fontSize));
      } else {
        widgets.add(_buildPdfLine(lines[i], placeholders, fontSize));
        i++;
      }
    }
  }

  pw.Widget _buildPdfGroupRow(List<Map<String, dynamic>> groupLines, Map<String, String> placeholders, double fontSize) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(children: groupLines.map((gl) {
        final gText = _substitutePlaceholders(gl['text'] as String? ?? '', placeholders);
        final gStyle = gl['style'] as String? ?? 'normal';
        final gAlign = gl['align'] as String? ?? 'left';
        final fw = gStyle == 'bold' ? pw.FontWeight.bold : pw.FontWeight.normal;
        final pdfAlign = switch (gAlign) {
          'center' => pw.TextAlign.center,
          'right' => pw.TextAlign.right,
          _ => pw.TextAlign.left,
        };
        return pw.Expanded(child: pw.Text(gText, textAlign: pdfAlign, style: pw.TextStyle(fontSize: fontSize, fontWeight: fw)));
      }).toList()),
    );
  }

  pw.Widget _buildPdfLine(Map<String, dynamic> line, Map<String, String> placeholders, double fontSize) {
    final text = line['text'] as String? ?? '';
    final style = line['style'] as String? ?? 'normal';
    final align = line['align'] as String? ?? 'left';

    if (style == 'blank') return pw.SizedBox(height: fontSize);
    if (style == 'separator') return pw.Divider(thickness: 0.5);

    final substituted = _substitutePlaceholders(text, placeholders);
    final pdfAlign = switch (align) {
      'center' => pw.TextAlign.center,
      'right' => pw.TextAlign.right,
      _ => pw.TextAlign.left,
    };
    final fontWeight = style == 'bold' ? pw.FontWeight.bold : pw.FontWeight.normal;
    final fSize = style == 'heading' ? fontSize + 4 : style == 'subheading' ? fontSize + 2 : fontSize;

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.SizedBox(
        width: double.infinity,
        child: pw.Text(substituted, textAlign: pdfAlign, style: pw.TextStyle(fontSize: fSize, fontWeight: fontWeight)),
      ),
    );
  }

  String _buildBarcodeDataFromLines(List<Map<String, dynamic>> lines, Map<String, String> placeholders) {
    final usedKeys = <String>{};
    final placeholderPattern = RegExp(r'\{[^}]+\}');
    for (final line in lines) {
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

  PdfPageFormat _getPageFormat(String size) {
    return switch (size) {
      'A5' => PdfPageFormat.a5,
      'Letter' => PdfPageFormat.letter,
      'Legal' => PdfPageFormat.legal,
      _ => PdfPageFormat.a4,
    };
  }

  // ─── Print Submission ──────────────────────────────────────────────────────

  Future<PrintResult> _sendDmTextToLpr(String content, String printer, int copies, {String tray = ''}) async {
    try {
      final tmpFile = File('${Directory.systemTemp.path}/weighbridge_dm_${DateTime.now().millisecondsSinceEpoch}.txt');
      await tmpFile.writeAsString(content);

      final args = <String>['-#', '$copies'];
      if (tray.isNotEmpty && tray != 'Auto') {
        args.addAll(['-o', 'InputSlot=$tray']);
      }
      if (printer.isNotEmpty && printer != 'default') {
        args.addAll(['-P', printer]);
      }
      args.add(tmpFile.path);

      final result = await Process.run('lpr', args);
      await tmpFile.delete().catchError((_) => tmpFile);

      if (result.exitCode != 0) {
        return PrintResult(success: false, error: 'lpr failed: ${result.stderr}');
      }
      return PrintResult(success: true);
    } catch (e) {
      return PrintResult(success: false, error: e.toString());
    }
  }

  Future<PrintResult> _sendPdfToLpr(Uint8List pdfBytes, String printer, int copies, {String tray = ''}) async {
    try {
      final tmpFile = File('${Directory.systemTemp.path}/weighbridge_docket_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await tmpFile.writeAsBytes(pdfBytes);

      final args = <String>['-#', '$copies'];
      if (tray.isNotEmpty && tray != 'Auto') {
        args.addAll(['-o', 'InputSlot=$tray']);
      }
      if (printer.isNotEmpty && printer != 'default') {
        args.addAll(['-P', printer]);
      }
      args.add(tmpFile.path);

      final result = await Process.run('lpr', args);
      await tmpFile.delete().catchError((_) => tmpFile);

      if (result.exitCode != 0) {
        final backupResult = await _tryBackupPrinter(tmpFile.path, copies);
        if (backupResult != null) return backupResult;
        return PrintResult(success: false, error: 'lpr failed: ${result.stderr}');
      }
      return PrintResult(success: true);
    } catch (e) {
      return PrintResult(success: false, error: e.toString());
    }
  }

  Future<PrintResult?> _tryBackupPrinter(String filePath, int copies) async {
    try {
      final settings = await _fetchPrintSettings();
      final backupEnabled = settings['backupEnabled'] as bool? ?? false;
      final backupPrinter = settings['backupPrinter'] as String? ?? '';
      final backupTray = settings['backupTray'] as String? ?? '';
      if (!backupEnabled || backupPrinter.isEmpty) return null;

      final args = <String>['-#', '$copies'];
      if (backupTray.isNotEmpty && backupTray != 'Auto') {
        args.addAll(['-o', 'InputSlot=$backupTray']);
      }
      args.addAll(['-P', backupPrinter, filePath]);

      final result = await Process.run('lpr', args);
      if (result.exitCode == 0) {
        return PrintResult(success: true, usedBackup: true);
      }
    } catch (_) {}
    return null;
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  String _alignText(String text, int width, String align) {
    if (text.length >= width) return text.substring(0, width);
    return switch (align) {
      'center' => text.padLeft((width + text.length) ~/ 2).padRight(width),
      'right' => text.padLeft(width),
      _ => text.padRight(width),
    };
  }

  // ─── Auto Print Hook ──────────────────────────────────────────────────────

  Future<bool> shouldAutoPrint() async {
    final settings = await _fetchPrintSettings();
    return settings['autoPrint'] as bool? ?? true;
  }

  Future<bool> shouldPrintOnGross() async {
    final settings = await _fetchPrintSettings();
    return settings['printOnGross'] as bool? ?? false;
  }

  Future<bool> shouldPrintOnTare() async {
    final settings = await _fetchPrintSettings();
    return settings['printOnTare'] as bool? ?? true;
  }

  Future<bool> canReprint(String weighmentId) async {
    final settings = await _fetchPrintSettings();
    final allowed = settings['reprintAllowed'] as bool? ?? true;
    if (!allowed) return false;

    final maxReprints = settings['maxReprints'] as int? ?? 3;
    final logDoc = await _db.collection('print_log').doc(weighmentId).get();
    final printCount = logDoc.exists ? (logDoc.data()?['count'] as int? ?? 0) : 0;
    return printCount < maxReprints;
  }

  Future<void> logPrint(String weighmentId) async {
    await _db.collection('print_log').doc(weighmentId).set({
      'count': FieldValue.increment(1),
      'lastPrintedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

class PrintResult {
  final bool success;
  final String? error;
  final bool usedBackup;

  const PrintResult({required this.success, this.error, this.usedBackup = false});
}
