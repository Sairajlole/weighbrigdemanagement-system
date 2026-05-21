import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class StickerConfig {
  final bool enabled;
  final double widthMm;
  final double heightMm;
  final bool showBarcode;
  final String barcodeField;
  final List<String> fields;

  const StickerConfig({
    this.enabled = false,
    this.widthMm = 58,
    this.heightMm = 40,
    this.showBarcode = true,
    this.barcodeField = 'rstNumber',
    this.fields = const ['vehicleNumber', 'material', 'netWeight', 'rstNumber', 'dateTime', 'customerName'],
  });

  factory StickerConfig.fromMap(Map<String, dynamic> map) => StickerConfig(
    enabled: map['enabled'] as bool? ?? false,
    widthMm: (map['widthMm'] as num?)?.toDouble() ?? 58,
    heightMm: (map['heightMm'] as num?)?.toDouble() ?? 40,
    showBarcode: map['showBarcode'] as bool? ?? true,
    barcodeField: map['barcodeField'] as String? ?? 'rstNumber',
    fields: (map['fields'] as List?)?.cast<String>() ?? const ['vehicleNumber', 'material', 'netWeight', 'rstNumber', 'dateTime', 'customerName'],
  );
}

class StickerPrintService {
  final StickerConfig config;

  StickerPrintService(this.config);

  Future<Uint8List?> generateSticker(Map<String, dynamic> weighmentData) async {
    if (!config.enabled) return null;

    final pdf = pw.Document();
    final pageWidth = config.widthMm * PdfPageFormat.mm;
    final pageHeight = config.heightMm * PdfPageFormat.mm;
    final format = PdfPageFormat(pageWidth, pageHeight, marginAll: 2 * PdfPageFormat.mm);

    final barcodeValue = _getValue(weighmentData, config.barcodeField);

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (config.showBarcode && barcodeValue.isNotEmpty)
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: Barcode.pdf417(),
                  data: barcodeValue,
                  width: pageWidth - 8 * PdfPageFormat.mm,
                  height: 14 * PdfPageFormat.mm,
                ),
              ),
            if (config.showBarcode) pw.SizedBox(height: 2 * PdfPageFormat.mm),
            ...config.fields.map((field) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 1),
              child: pw.Row(
                children: [
                  pw.SizedBox(
                    width: 18 * PdfPageFormat.mm,
                    child: pw.Text(_fieldLabel(field), style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Expanded(
                    child: pw.Text(_getValue(weighmentData, field), style: const pw.TextStyle(fontSize: 7)),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  String _getValue(Map<String, dynamic> data, String field) {
    if (field == 'dateTime') {
      final dt = data['grossDateTime'] ?? data['createdAt'];
      if (dt is DateTime) return DateFormat('dd/MM/yy HH:mm').format(dt);
      return '';
    }
    if (field == 'netWeight') {
      final w = data['netWeight'];
      if (w is num) return '${w.toStringAsFixed(0)} kg';
      return '';
    }
    return data[field]?.toString() ?? '';
  }

  String _fieldLabel(String field) {
    return switch (field) {
      'vehicleNumber' => 'Vehicle:',
      'material' => 'Material:',
      'netWeight' => 'Net Wt:',
      'grossWeight' => 'Gross:',
      'tareWeight' => 'Tare:',
      'rstNumber' => 'RST:',
      'dateTime' => 'Date:',
      'customerName' => 'Customer:',
      'direction' => 'Dir:',
      _ => '$field:',
    };
  }
}
