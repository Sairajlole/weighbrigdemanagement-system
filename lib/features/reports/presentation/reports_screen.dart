import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:weighbridgemanagement/shared/theme/app_tokens.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';
import 'package:weighbridgemanagement/shared/widgets/app_loading.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weighbridgemanagement/shared/services/cloud_functions_service.dart';
import 'package:weighbridgemanagement/features/reports/presentation/widgets/report_charts.dart';

// ─── Report Tabs ────────────────────────────────────────────────────────────

enum _DatePreset { today, week, month, year, fy, all, custom }

enum ReportTab { daily, vehicle, customer, material, operator, throughput, turnaround, frequency, discrepancy, comparison, shift, audit }

extension ReportTabExt on ReportTab {
  String get label => switch (this) {
    ReportTab.daily => 'Daily',
    ReportTab.vehicle => 'Vehicles',
    ReportTab.customer => 'Customers',
    ReportTab.material => 'Materials',
    ReportTab.operator => 'Operators',
    ReportTab.throughput => 'Throughput',
    ReportTab.turnaround => 'Turnaround',
    ReportTab.frequency => 'Frequency',
    ReportTab.discrepancy => 'Anomalies',
    ReportTab.comparison => 'Compare',
    ReportTab.shift => 'Shifts',
    ReportTab.audit => 'Audit',
  };

  IconData get icon => switch (this) {
    ReportTab.daily => Icons.today_rounded,
    ReportTab.vehicle => Icons.local_shipping_rounded,
    ReportTab.customer => Icons.groups_rounded,
    ReportTab.material => Icons.inventory_2_rounded,
    ReportTab.operator => Icons.badge_rounded,
    ReportTab.throughput => Icons.bar_chart_rounded,
    ReportTab.turnaround => Icons.timer_rounded,
    ReportTab.frequency => Icons.repeat_rounded,
    ReportTab.discrepancy => Icons.warning_rounded,
    ReportTab.comparison => Icons.compare_arrows_rounded,
    ReportTab.shift => Icons.schedule_rounded,
    ReportTab.audit => Icons.security_rounded,
  };
}

// ─── Screen ─────────────────────────────────────────────────────────────────

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final GlobalKey _customChipKey = GlobalKey();
  ReportTab _activeTab = ReportTab.daily;
  _DatePreset _datePreset = _DatePreset.week;
  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );
  String _materialFilter = 'All';
  String _customerFilter = '';
  String _vehicleFilter = '';
  String _operatorFilter = 'All';
  String _scope = 'weighbridge'; // 'weighbridge', 'site', 'all'
  int _perPage = 50;
  int _currentPage = 0;
  bool _showVisual = true; // true = charts/visuals, false = list/table only
  List<Map<String, String>> _savedPresets = [];
  bool _emailScheduleEnabled = false;
  String _emailScheduleFrequency = 'daily'; // daily, weekly
  String _emailRecipient = '';

  List<Map<String, dynamic>> _data = [];
  bool _loading = false;
  Map<String, dynamic> _summary = {};

  // Comparison period state
  List<Map<String, dynamic>> _prevData = [];
  bool _prevLoading = false;

  // Cached audit-trail query so it isn't re-issued on every rebuild.
  Future<QuerySnapshot<Map<String, dynamic>>>? _auditFuture;

  @override
  void initState() {
    super.initState();
    _loadPresets();
    _loadEmailSchedule();
    _loadReport();
  }

  Future<void> _loadPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('report_presets') ?? [];
    _savedPresets = raw.map((s) {
      final parts = s.split('|');
      if (parts.length >= 4) return {'name': parts[0], 'tab': parts[1], 'preset': parts[2], 'scope': parts[3]};
      return <String, String>{};
    }).where((m) => m.isNotEmpty).toList();
    if (mounted) setState(() {});
  }

  Future<void> _saveCurrentAsPreset() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Preset'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Preset name'), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    _savedPresets.add({'name': name, 'tab': _activeTab.name, 'preset': _datePreset.name, 'scope': _scope});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('report_presets', _savedPresets.map((m) => '${m['name']}|${m['tab']}|${m['preset']}|${m['scope']}').toList());
    if (mounted) setState(() {});
  }

  void _applyPreset(Map<String, String> preset) {
    final tab = ReportTab.values.where((t) => t.name == preset['tab']).firstOrNull;
    final dp = _DatePreset.values.where((p) => p.name == preset['preset']).firstOrNull;
    if (tab != null) _activeTab = tab;
    if (dp != null) _setDatePreset(dp);
    _scope = preset['scope'] ?? 'weighbridge';
    setState(() {});
  }

  Future<void> _deletePreset(int index) async {
    _savedPresets.removeAt(index);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('report_presets', _savedPresets.map((m) => '${m['name']}|${m['tab']}|${m['preset']}|${m['scope']}').toList());
    if (mounted) setState(() {});
  }

  Future<void> _loadEmailSchedule() async {
    try {
      final paths = ref.read(firestorePathsProvider);
      if (!paths.isConfigured) return;
      final doc = await paths.firestore.doc('companies/${paths.context.companyId}/settings/emailSchedule').get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _emailScheduleEnabled = data['enabled'] as bool? ?? false;
          _emailScheduleFrequency = data['frequency'] as String? ?? 'daily';
          _emailRecipient = data['recipient'] as String? ?? '';
        });
      }
    } catch (_) {}
  }

  Future<void> _saveEmailSchedule() async {
    try {
      final paths = ref.read(firestorePathsProvider);
      await paths.firestore.doc('companies/${paths.context.companyId}/settings/emailSchedule').set({
        'enabled': _emailScheduleEnabled,
        'frequency': _emailScheduleFrequency,
        'recipient': _emailRecipient,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email schedule saved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    try {
      final paths = ref.read(firestorePathsProvider);
      if (!paths.isConfigured) {
        setState(() => _loading = false);
        return;
      }

      final startTs = Timestamp.fromDate(_dateRange.start);
      final endTs = Timestamp.fromDate(_dateRange.end.add(const Duration(days: 1)));

      Query<Map<String, dynamic>> query;
      if (_scope == 'site') {
        query = paths.firestore.collectionGroup('weighments')
            .where('createdAt', isGreaterThanOrEqualTo: startTs)
            .where('createdAt', isLessThan: endTs)
            .orderBy('createdAt', descending: true);
      } else if (_scope == 'all') {
        query = paths.firestore.collectionGroup('weighments')
            .where('createdAt', isGreaterThanOrEqualTo: startTs)
            .where('createdAt', isLessThan: endTs)
            .orderBy('createdAt', descending: true);
      } else {
        query = paths.weighments
            .where('createdAt', isGreaterThanOrEqualTo: startTs)
            .where('createdAt', isLessThan: endTs)
            .orderBy('createdAt', descending: true);
      }

      final snap = await query.get();
      final ctx = paths.context;
      var docs = snap.docs.where((d) {
        if (_scope == 'weighbridge') return true;
        final path = d.reference.path;
        if (_scope == 'site') return path.startsWith('companies/${ctx.companyId}/sites/${ctx.siteId}/');
        return path.startsWith('companies/${ctx.companyId}/');
      }).map((d) => {'id': d.id, ...d.data()}).toList();

      // Apply filters
      if (_materialFilter != 'All') {
        docs = docs.where((d) => d['material'] == _materialFilter).toList();
      }
      if (_customerFilter.isNotEmpty) {
        final lower = _customerFilter.toLowerCase();
        docs = docs.where((d) => (d['customerName'] as String? ?? '').toLowerCase().contains(lower)).toList();
      }
      if (_vehicleFilter.isNotEmpty) {
        final lower = _vehicleFilter.toLowerCase();
        docs = docs.where((d) => (d['vehicleNumber'] as String? ?? '').toLowerCase().contains(lower)).toList();
      }
      if (_operatorFilter != 'All') {
        docs = docs.where((d) => d['operatorName'] == _operatorFilter).toList();
      }

      _data = docs;
      _computeSummary();
    } catch (e, stack) {
      debugPrint('[Reports] Load failed: $e\n$stack');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _computeSummary() {
    final completed = _data.where((d) => d['status'] == 'completed').toList();
    double totalNet = 0;
    double totalGross = 0;
    double totalTare = 0;
    int vehicleCount = 0;
    final vehicles = <String>{};
    final materials = <String, double>{};
    final customers = <String, double>{};
    final operators = <String, int>{};
    final hourly = List.filled(24, 0);

    for (final d in completed) {
      final net = (d['netWeight'] as num?)?.toDouble() ?? 0;
      final gross = (d['grossWeight'] as num?)?.toDouble() ?? 0;
      final tare = (d['tareWeight'] as num?)?.toDouble() ?? 0;
      totalNet += net;
      totalGross += gross;
      totalTare += tare;

      final veh = d['vehicleNumber'] as String? ?? '';
      if (veh.isNotEmpty) vehicles.add(veh);

      final mat = d['material'] as String? ?? 'Unknown';
      materials[mat] = (materials[mat] ?? 0) + net;

      final cust = d['customerName'] as String? ?? 'Unknown';
      customers[cust] = (customers[cust] ?? 0) + net;

      final op = d['operatorName'] as String? ?? 'Unknown';
      operators[op] = (operators[op] ?? 0) + 1;

      final ts = d['createdAt'];
      if (ts is Timestamp) {
        hourly[ts.toDate().hour]++;
      }
    }

    _summary = {
      'totalWeighments': completed.length,
      'pendingCount': _data.where((d) => d['status'] == 'awaitingTare').length,
      'totalNet': totalNet,
      'totalGross': totalGross,
      'totalTare': totalTare,
      'vehicleCount': vehicles.length,
      'materials': materials,
      'customers': customers,
      'operators': operators,
      'hourly': hourly,
    };
  }

  void _setDatePreset(_DatePreset preset) {
    final now = DateTime.now();
    DateTimeRange range;
    switch (preset) {
      case _DatePreset.today:
        range = DateTimeRange(start: DateTime(now.year, now.month, now.day), end: now);
      case _DatePreset.week:
        final start = now.subtract(Duration(days: now.weekday - 1));
        range = DateTimeRange(start: DateTime(start.year, start.month, start.day), end: now);
      case _DatePreset.month:
        range = DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      case _DatePreset.year:
        range = DateTimeRange(start: DateTime(now.year, 1, 1), end: now);
      case _DatePreset.fy:
        final fyStart = now.month >= 4 ? DateTime(now.year, 4, 1) : DateTime(now.year - 1, 4, 1);
        range = DateTimeRange(start: fyStart, end: now);
      case _DatePreset.all:
        range = DateTimeRange(start: DateTime(2020), end: now);
      case _DatePreset.custom:
        _pickCustomDateRange();
        return;
    }
    setState(() { _datePreset = preset; _dateRange = range; _prevData = []; });
    _loadReport();
  }

  Future<void> _exportCsv() async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Export report to');
    if (dir == null || dir.isEmpty) return;

    final buffer = StringBuffer();
    final completed = _data.where((d) => d['status'] == 'completed').toList();

    buffer.writeln('RST#,Vehicle,Customer,Material,Gross (kg),Tare (kg),Net (kg),Operator,Date');
    for (final d in completed) {
      final ts = d['createdAt'];
      final date = ts is Timestamp ? DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate()) : '';
      buffer.writeln([
        _esc(d['rstNumber']?.toString() ?? ''),
        _esc(d['vehicleNumber'] as String? ?? ''),
        _esc(d['customerName'] as String? ?? ''),
        _esc(d['material'] as String? ?? ''),
        (d['grossWeight'] as num? ?? 0).toStringAsFixed(0),
        (d['tareWeight'] as num? ?? 0).toStringAsFixed(0),
        (d['netWeight'] as num? ?? 0).toStringAsFixed(0),
        _esc(d['operatorName'] as String? ?? ''),
        date,
      ].join(','));
    }

    final fileName = 'report_${_activeTab.name}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    final filePath = '$dir/$fileName';
    await File(filePath).writeAsString(buffer.toString());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported to $filePath (${completed.length} records)')));
    }
  }

  String _esc(String v) {
    // Neutralize spreadsheet formula injection: prefix a single quote so a leading =,+,-,@ is treated as text.
    if (v.isNotEmpty && '=+-@'.contains(v[0])) v = "'$v";
    // Quote on comma/quote and on embedded CR/LF so a newline can't break the row.
    return v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r')
        ? '"${v.replaceAll('"', '""')}"'
        : v;
  }

  Future<void> _exportPdf() async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Export PDF to');
    if (dir == null || dir.isEmpty) return;

    final completed = _data.where((d) => d['status'] == 'completed').toList();
    final totalNet = completed.fold(0.0, (sum, d) => sum + ((d['netWeight'] as num?)?.toDouble() ?? 0));

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Weighment Report', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('${DateFormat('dd MMM yyyy').format(_dateRange.start)} – ${DateFormat('dd MMM yyyy').format(_dateRange.end)}', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
            pw.SizedBox(height: 4),
            pw.Text('Total: ${completed.length} weighments | ${(totalNet / 1000).toStringAsFixed(1)} tonnes${completed.length > 200 ? ' (showing first 200)' : ''}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
            pw.Divider(),
          ],
        ),
        build: (ctx) => [
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            headers: ['RST#', 'Vehicle', 'Customer', 'Material', 'Gross', 'Tare', 'Net', 'Date'],
            data: completed.take(200).map((d) {
              final ts = d['createdAt'];
              return [
                d['rstNumber']?.toString() ?? '',
                d['vehicleNumber'] as String? ?? '',
                d['customerName'] as String? ?? '',
                d['material'] as String? ?? '',
                '${(d['grossWeight'] as num? ?? 0).toStringAsFixed(0)}',
                '${(d['tareWeight'] as num? ?? 0).toStringAsFixed(0)}',
                '${(d['netWeight'] as num? ?? 0).toStringAsFixed(0)}',
                ts is Timestamp ? DateFormat('dd/MM HH:mm').format(ts.toDate()) : '',
              ];
            }).toList(),
          ),
        ],
      ),
    );

    final fileName = 'report_${_activeTab.name}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    final filePath = '$dir/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF exported: $filePath')));
    }
  }

  void _showEmailScheduleDialog() {
    final emailCtrl = TextEditingController(text: _emailRecipient);
    showDialog(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final text = Theme.of(ctx).textTheme;
        return StatefulBuilder(
          builder: (ctx, setDState) => AlertDialog(
            title: const Text('Email Report Schedule'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Enable scheduled emails', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Switch(value: _emailScheduleEnabled, onChanged: (v) { setDState(() => _emailScheduleEnabled = v); setState(() {}); }),
                    ],
                  ),
                  if (_emailScheduleEnabled) ...[
                    SizedBox(height: AppSpacing.md),
                    Text('Recipient email', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(height: AppSpacing.xs),
                    TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(hintText: 'admin@company.com', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                      style: text.bodySmall,
                    ),
                    SizedBox(height: AppSpacing.md),
                    Text('Frequency', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        for (final freq in ['daily', 'weekly'])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => setDState(() => _emailScheduleFrequency = freq),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _emailScheduleFrequency == freq ? scheme.primaryContainer.withValues(alpha: 0.5) : Colors.transparent,
                                  borderRadius: AppRadius.button,
                                  border: Border.all(color: _emailScheduleFrequency == freq ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.3)),
                                ),
                                child: Text(freq == 'daily' ? 'Daily (8 AM)' : 'Weekly (Monday 8 AM)', style: text.bodySmall?.copyWith(fontWeight: _emailScheduleFrequency == freq ? FontWeight.w700 : FontWeight.w500, color: _emailScheduleFrequency == freq ? scheme.primary : scheme.onSurfaceVariant)),
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: AppSpacing.md),
                    Text('Report includes: daily summary, top customers, material breakdown, anomalies.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
                    SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final recipient = emailCtrl.text.trim();
                        if (recipient.isEmpty) return;
                        try {
                          final paths = ref.read(firestorePathsProvider);
                          final result = await CloudFunctionsService.call('sendReportEmail', {
                            'companyId': paths.context.companyId,
                            'recipient': recipient,
                            'period': _emailScheduleFrequency,
                          });
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Test email sent! ${result['weighments']} weighments, ${result['tonnage']}T')));
                        } catch (e) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                        }
                      },
                      icon: const Icon(Icons.send_rounded, size: 14),
                      label: const Text('Send Test Now'),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(onPressed: () {
                _emailRecipient = emailCtrl.text.trim();
                _saveEmailSchedule();
                Navigator.pop(ctx);
              }, child: const Text('Save')),
            ],
          ),
        );
      },
    );
  }

  Future<void> _printReport() async {
    final completed = _data.where((d) => d['status'] == 'completed').toList();
    final totalNet = completed.fold(0.0, (sum, d) => sum + ((d['netWeight'] as num?)?.toDouble() ?? 0));

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(30),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('${_activeTab.label} Report', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text('${DateFormat('dd MMM yyyy').format(_dateRange.start)} – ${DateFormat('dd MMM yyyy').format(_dateRange.end)} | ${completed.length} records | ${(totalNet / 1000).toStringAsFixed(1)}T${completed.length > 500 ? ' (showing first 500)' : ''}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
            pw.Divider(),
          ],
        ),
        build: (ctx) => [
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 7),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            headers: ['RST#', 'Vehicle', 'Customer', 'Material', 'Gross', 'Tare', 'Net', 'Operator', 'Date'],
            data: completed.take(500).map((d) {
              final ts = d['createdAt'];
              return [
                d['rstNumber']?.toString() ?? '',
                d['vehicleNumber'] as String? ?? '',
                d['customerName'] as String? ?? '',
                d['material'] as String? ?? '',
                '${(d['grossWeight'] as num? ?? 0).toStringAsFixed(0)}',
                '${(d['tareWeight'] as num? ?? 0).toStringAsFixed(0)}',
                '${(d['netWeight'] as num? ?? 0).toStringAsFixed(0)}',
                d['operatorName'] as String? ?? '',
                ts is Timestamp ? DateFormat('dd/MM HH:mm').format(ts.toDate()) : '',
              ];
            }).toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (_) => pdf.save());
  }

  void _pickCustomDateRange() async {
    final scheme = Theme.of(context).colorScheme;
    final renderBox = _customChipKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final chipSize = renderBox.size;
    final chipOffset = renderBox.localToGlobal(Offset.zero);
    const dialogWidth = 320.0;
    final left = chipOffset.dx + chipSize.width - dialogWidth;
    final top = chipOffset.dy + chipSize.height + 6;

    DateTime? start;
    DateTime? end;

    await showDialog(
      context: context,
      barrierColor: Colors.black12,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                elevation: 8,
                borderRadius: AppRadius.card,
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: dialogWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Row(
                          children: [
                            Text(
                              start != null && end != null
                                  ? '${DateFormat('dd MMM').format(start!)} – ${DateFormat('dd MMM').format(end!)}'
                                  : start != null
                                      ? '${DateFormat('dd MMM').format(start!)} – select end'
                                      : 'Select date range',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface),
                            ),
                          ],
                        ),
                      ),
                      CalendarDatePicker(
                        initialDate: _dateRange.start,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        onDateChanged: (date) {
                          if (start == null || end != null) {
                            setDialogState(() { start = date; end = null; });
                          } else {
                            if (date.isBefore(start!)) {
                              setDialogState(() { end = start; start = date; });
                            } else {
                              setDialogState(() { end = date; });
                            }
                            setState(() { _datePreset = _DatePreset.custom; _dateRange = DateTimeRange(start: start!, end: end!); _prevData = []; });
                            Navigator.pop(ctx);
                            _loadReport();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: AppSpacing.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(scheme, text),
            _buildFilters(scheme, text),
            SizedBox(height: AppSpacing.lg),
            if (_activeTab != ReportTab.audit) ...[
              _buildSummaryCards(scheme, text),
              SizedBox(height: AppSpacing.lg),
            ],
            Expanded(
              child: _loading
                  ? const AppLoading()
                  : SingleChildScrollView(
                      child: _buildReportContent(scheme, text),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme, TextTheme text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      child: Row(
        children: [
          Text('Reports', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          // Date preset chips
          for (final preset in _DatePreset.values)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                key: preset == _DatePreset.custom ? _customChipKey : null,
                onTap: () => _setDatePreset(preset),
                child: Container(
                  height: 32,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: _datePreset == preset ? scheme.primary : scheme.surfaceContainerHigh,
                    borderRadius: AppRadius.chip,
                  ),
                  child: Text(
                    preset == _DatePreset.custom && _datePreset == _DatePreset.custom
                        ? '${DateFormat('dd/MM').format(_dateRange.start)} – ${DateFormat('dd/MM').format(_dateRange.end)}'
                        : switch (preset) {
                            _DatePreset.today => 'Today',
                            _DatePreset.week => 'Week',
                            _DatePreset.month => 'Month',
                            _DatePreset.year => 'Year',
                            _DatePreset.fy => 'FY',
                            _DatePreset.all => 'All',
                            _DatePreset.custom => 'Custom',
                          },
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _datePreset == preset ? scheme.onPrimary : scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          SizedBox(width: AppSpacing.md),
          // Export
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'csv') _exportCsv();
              if (v == 'pdf') _exportPdf();
              if (v == 'print') _printReport();
            },
            shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'csv', child: Row(children: [Icon(Icons.table_chart_rounded, size: 16, color: scheme.onSurfaceVariant), SizedBox(width: AppSpacing.sm), const Text('Export CSV')])),
              PopupMenuItem(value: 'pdf', child: Row(children: [Icon(Icons.picture_as_pdf_rounded, size: 16, color: scheme.onSurfaceVariant), SizedBox(width: AppSpacing.sm), const Text('Export PDF')])),
              PopupMenuItem(value: 'print', child: Row(children: [Icon(Icons.print_rounded, size: 16, color: scheme.onSurfaceVariant), SizedBox(width: AppSpacing.sm), const Text('Print')])),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: AppRadius.button,
                border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download_rounded, size: 14, color: scheme.primary),
                  SizedBox(width: 6.rs),
                  Text('Export', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.primary)),
                  SizedBox(width: 4.rs),
                  Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: scheme.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(ColorScheme scheme, TextTheme text) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          // Scope selector
          Container(
            height: 32,
            decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: AppRadius.chip),
            padding: const EdgeInsets.all(3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final s in ['weighbridge', 'site', 'all'])
                  GestureDetector(
                    onTap: () { setState(() => _scope = s); _loadReport(); },
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _scope == s ? scheme.primary : Colors.transparent,
                        borderRadius: AppRadius.chip,
                      ),
                      child: Text(
                        switch (s) { 'weighbridge' => 'WB', 'site' => 'Site', _ => 'All' },
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _scope == s ? scheme.onPrimary : scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.md),
          // Search fields
          SizedBox(
            width: 140,
            height: 32,
            child: Center(
              child: TextField(
                onChanged: (v) { _customerFilter = v; if (v.length > 2 || v.isEmpty) _loadReport(); },
                expands: true,
                maxLines: null,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Customer (3+)...',
                  hintStyle: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  filled: true,
                  fillColor: scheme.surfaceContainerHigh,
                  border: OutlineInputBorder(borderRadius: AppRadius.chip, borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: AppRadius.chip, borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: AppRadius.chip, borderSide: BorderSide(color: scheme.primary, width: 1.5)),
                ),
              ),
            ),
          ),
          SizedBox(width: AppSpacing.xs),
          SizedBox(
            width: 130,
            height: 32,
            child: Center(
              child: TextField(
                onChanged: (v) { _vehicleFilter = v; if (v.length > 2 || v.isEmpty) _loadReport(); },
                expands: true,
                maxLines: null,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Vehicle (3+)...',
                  hintStyle: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  filled: true,
                  fillColor: scheme.surfaceContainerHigh,
                  border: OutlineInputBorder(borderRadius: AppRadius.chip, borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: AppRadius.chip, borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: AppRadius.chip, borderSide: BorderSide(color: scheme.primary, width: 1.5)),
                ),
              ),
            ),
          ),
          SizedBox(width: AppSpacing.md),
          // Tabs
          for (final tab in ReportTab.values)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                onTap: () => setState(() => _activeTab = tab),
                child: Container(
                  height: 32,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: _activeTab == tab ? scheme.primary : scheme.surfaceContainerHigh,
                    borderRadius: AppRadius.chip,
                  ),
                  child: Text(tab.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _activeTab == tab ? scheme.onPrimary : scheme.onSurfaceVariant)),
                ),
              ),
            ),
          const Spacer(),
          // Saved presets
          if (_savedPresets.isNotEmpty) ...[
            for (final preset in _savedPresets.asMap().entries)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: () => _applyPreset(preset.value),
                  onLongPress: () => _deletePreset(preset.key),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: scheme.tertiaryContainer.withValues(alpha: 0.3), borderRadius: AppRadius.chip, border: Border.all(color: scheme.tertiary.withValues(alpha: 0.3))),
                    child: Text(preset.value['name'] ?? '', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.tertiary)),
                  ),
                ),
              ),
          ],
          // Save preset
          GestureDetector(
            onTap: _saveCurrentAsPreset,
            child: Container(
              height: 32, width: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: AppRadius.chip),
              child: Icon(Icons.bookmark_add_outlined, size: 16, color: scheme.onSurfaceVariant),
            ),
          ),
          SizedBox(width: AppSpacing.sm),
          // Email schedule
          GestureDetector(
            onTap: _showEmailScheduleDialog,
            child: Container(
              height: 32, width: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _emailScheduleEnabled ? scheme.primaryContainer.withValues(alpha: 0.5) : scheme.surfaceContainerHigh, borderRadius: AppRadius.chip),
              child: Icon(Icons.email_outlined, size: 16, color: _emailScheduleEnabled ? scheme.primary : scheme.onSurfaceVariant),
            ),
          ),
          SizedBox(width: AppSpacing.sm),
          // Count
          if (_activeTab != ReportTab.audit)
            Text('${_data.length}', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
          SizedBox(width: AppSpacing.sm),
          // View toggle (List / Visual)
          Container(
            height: 32,
            decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: AppRadius.chip),
            padding: const EdgeInsets.all(3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _showVisual = true),
                  child: Container(
                    height: 26, padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _showVisual ? scheme.primary : Colors.transparent, borderRadius: AppRadius.chip),
                    child: Icon(Icons.bar_chart_rounded, size: 14, color: _showVisual ? scheme.onPrimary : scheme.onSurfaceVariant),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _showVisual = false),
                  child: Container(
                    height: 26, padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: !_showVisual ? scheme.primary : Colors.transparent, borderRadius: AppRadius.chip),
                    child: Icon(Icons.view_list_rounded, size: 14, color: !_showVisual ? scheme.onPrimary : scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.sm),
          // Refresh
          IconButton(
            onPressed: _loadReport,
            icon: Icon(Icons.refresh_rounded, size: 18, color: scheme.onSurfaceVariant),
            tooltip: 'Refresh',
            style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHigh, shape: RoundedRectangleBorder(borderRadius: AppRadius.button)),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(ColorScheme scheme, TextTheme text) {
    final totalWeighments = _summary['totalWeighments'] as int? ?? 0;
    final pendingCount = _summary['pendingCount'] as int? ?? 0;
    final totalNet = (_summary['totalNet'] as double? ?? 0) / 1000; // tonnes
    final vehicleCount = _summary['vehicleCount'] as int? ?? 0;

    return Row(
      children: [
        _SummaryCard(icon: Icons.scale_rounded, label: 'Weighments', value: '$totalWeighments', subtitle: '$pendingCount pending', scheme: scheme, text: text),
        SizedBox(width: AppSpacing.md),
        _SummaryCard(icon: Icons.local_shipping_rounded, label: 'Vehicles', value: '$vehicleCount', subtitle: 'unique', scheme: scheme, text: text),
        SizedBox(width: AppSpacing.md),
        _SummaryCard(icon: Icons.monitor_weight_rounded, label: 'Net Tonnage', value: '${totalNet.toStringAsFixed(1)} T', subtitle: 'total processed', scheme: scheme, text: text),
        SizedBox(width: AppSpacing.md),
        _SummaryCard(icon: Icons.speed_rounded, label: 'Avg/Day', value: _dateRange.duration.inDays > 0 ? '${(totalWeighments / max(1, _dateRange.duration.inDays)).toStringAsFixed(0)}' : '0', subtitle: 'weighments', scheme: scheme, text: text),
      ],
    );
  }

  Widget _buildReportContent(ColorScheme scheme, TextTheme text) {
    return switch (_activeTab) {
      ReportTab.daily => _buildDailyReport(scheme, text),
      ReportTab.vehicle => _buildVehicleReport(scheme, text),
      ReportTab.customer => _buildCustomerReport(scheme, text),
      ReportTab.material => _buildMaterialReport(scheme, text),
      ReportTab.operator => _buildOperatorReport(scheme, text),
      ReportTab.throughput => _buildThroughputReport(scheme, text),
      ReportTab.turnaround => _buildTurnaroundReport(scheme, text),
      ReportTab.frequency => _buildFrequencyReport(scheme, text),
      ReportTab.discrepancy => _buildDiscrepancyReport(scheme, text),
      ReportTab.comparison => _buildComparisonReport(scheme, text),
      ReportTab.shift => _buildShiftReport(scheme, text),
      ReportTab.audit => _buildAuditReport(scheme, text),
    };
  }

  // ─── Daily Summary ──────────────────────────────────────────────────────────

  Widget _buildDailyReport(ColorScheme scheme, TextTheme text) {
    final completed = _data.where((d) => d['status'] == 'completed').toList();
    // Group by date
    final byDate = <String, List<Map<String, dynamic>>>{};
    for (final d in completed) {
      final ts = d['createdAt'];
      final date = ts is Timestamp ? DateFormat('dd MMM').format(ts.toDate()) : 'Unknown';
      byDate.putIfAbsent(date, () => []).add(d);
    }

    // Daily tonnage for trend chart
    final dailyTonnage = <String, double>{};
    for (final e in byDate.entries) {
      dailyTonnage[e.key] = e.value.fold(0.0, (sum, d) => sum + ((d['netWeight'] as num?)?.toDouble() ?? 0)) / 1000;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Chart
        if (_showVisual) TonnageTrendChart(dailyTonnage: dailyTonnage, scheme: scheme),
        SizedBox(height: AppSpacing.lg),
        // Table
        _ReportTable(      columns: const ['Date', 'Weighments', 'Vehicles', 'Net (T)', 'Avg Net (kg)'],
      rows: byDate.entries.map((e) {
        final nets = e.value.map((d) => (d['netWeight'] as num?)?.toDouble() ?? 0).toList();
        final total = nets.fold(0.0, (a, b) => a + b);
        final vehicles = e.value.map((d) => d['vehicleNumber']).toSet().length;
        return [e.key, '${e.value.length}', '$vehicles', (total / 1000).toStringAsFixed(2), nets.isNotEmpty ? (total / nets.length).toStringAsFixed(0) : '0'];
      }).toList(),
      scheme: scheme,
      text: text,
      perPage: _perPage,
      currentPage: _currentPage,
      onPageChanged: (p) => setState(() => _currentPage = p),
      onPerPageChanged: (pp) => setState(() { _perPage = pp; _currentPage = 0; }),
    ),
      ],
    );
  }

  // ─── Vehicle Movement ───────────────────────────────────────────────────────

  Widget _buildVehicleReport(ColorScheme scheme, TextTheme text) {
    // Camera evidence — show recent weighments that have snapshots
    final withSnapshots = _data.where((d) => d['cameraSnapshots'] != null && (d['cameraSnapshots'] as Map).isNotEmpty).take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (withSnapshots.isNotEmpty) ...[
          Container(
            padding: AppSpacing.cardPadding,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: AppRadius.card,
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.photo_library_rounded, size: 16, color: scheme.primary),
                    SizedBox(width: AppSpacing.sm),
                    Text('Camera Evidence', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text('${withSnapshots.length} with photos', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
                SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: withSnapshots.length,
                    itemBuilder: (_, i) {
                      final d = withSnapshots[i];
                      final veh = d['vehicleNumber'] as String? ?? '?';
                      final ts = d['createdAt'];
                      final time = ts is Timestamp ? DateFormat('HH:mm').format(ts.toDate()) : '';
                      final snapMap = d['cameraSnapshots'] as Map;
                      String? firstImagePath;
                      for (final phase in snapMap.values) {
                        if (phase is Map) {
                          for (final path in phase.values) {
                            if (path is String && path.isNotEmpty) { firstImagePath = path; break; }
                          }
                        }
                        if (firstImagePath != null) break;
                      }
                      return Container(
                        width: 130,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: AppRadius.button,
                          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.15)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: firstImagePath != null && File(firstImagePath).existsSync()
                                  ? Image.file(File(firstImagePath), fit: BoxFit.cover)
                                  : Container(
                                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                      child: Icon(Icons.videocam_rounded, size: 24, color: scheme.primary.withValues(alpha: 0.5)),
                                    ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(child: Text(veh, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurface), overflow: TextOverflow.ellipsis)),
                                  Text(time, style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.lg),
        ],
        _ReportTable(
          columns: const ['RST#', 'Vehicle', 'Customer', 'Material', 'Gross', 'Tare', 'Net', 'Time', '📷'],
          rows: _data.map((d) {
            final ts = d['createdAt'];
            final time = ts is Timestamp ? DateFormat('dd/MM HH:mm').format(ts.toDate()) : '';
            final hasSnap = d['cameraSnapshots'] != null && (d['cameraSnapshots'] as Map).isNotEmpty;
            return [
              d['rstNumber']?.toString() ?? '',
              d['vehicleNumber'] as String? ?? '',
              d['customerName'] as String? ?? '',
              d['material'] as String? ?? '',
              '${(d['grossWeight'] as num? ?? 0).toStringAsFixed(0)}',
              '${(d['tareWeight'] as num? ?? 0).toStringAsFixed(0)}',
              '${(d['netWeight'] as num? ?? 0).toStringAsFixed(0)}',
              time,
              hasSnap ? '✓' : '',
            ];
          }).toList(),
          scheme: scheme,
          text: text,
          perPage: _perPage,
          currentPage: _currentPage,
          onPageChanged: (p) => setState(() => _currentPage = p),
          onPerPageChanged: (pp) => setState(() { _perPage = pp; _currentPage = 0; }),
        ),
      ],
    );
  }

  // ─── Customer Ledger ────────────────────────────────────────────────────────

  Widget _buildCustomerReport(ColorScheme scheme, TextTheme text) {
    final customers = _summary['customers'] as Map<String, double>? ?? {};
    final sorted = customers.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showVisual) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: RankingBars(title: 'Top Customers by Tonnage', data: Map.fromEntries(sorted.take(10).map((e) => MapEntry(e.key, e.value / 1000))), unit: 'T', scheme: scheme)),
              SizedBox(width: AppSpacing.md),
              Expanded(child: BreakdownDonutChart(title: 'Customer Share', data: customers, scheme: scheme)),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
        ],
        _ReportTable(      columns: const ['Customer', 'Net Tonnage', 'Weighments', '% Share'],
      rows: sorted.take(50).map((e) {
        final total = customers.values.fold(0.0, (a, b) => a + b);
        final count = _data.where((d) => d['customerName'] == e.key && d['status'] == 'completed').length;
        final pct = total > 0 ? (e.value / total * 100) : 0.0;
        return [e.key, (e.value / 1000).toStringAsFixed(2), '$count', '${pct.toStringAsFixed(1)}%'];
      }).toList(),
      scheme: scheme,
      text: text,
      perPage: _perPage,
      currentPage: _currentPage,
      onPageChanged: (p) => setState(() => _currentPage = p),
      onPerPageChanged: (pp) => setState(() { _perPage = pp; _currentPage = 0; }),
    ),
      ],
    );
  }

  // ─── Material Summary ───────────────────────────────────────────────────────

  Widget _buildMaterialReport(ColorScheme scheme, TextTheme text) {
    final materials = _summary['materials'] as Map<String, double>? ?? {};
    final sorted = materials.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = materials.values.fold(0.0, (a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BreakdownDonutChart(title: 'Material Breakdown', data: materials, scheme: scheme),
        SizedBox(height: AppSpacing.lg),
        _ReportTable(      columns: const ['Material', 'Net Tonnage', 'Weighments', '% Share'],
      rows: sorted.map((e) {
        final count = _data.where((d) => d['material'] == e.key && d['status'] == 'completed').length;
        final pct = total > 0 ? (e.value / total * 100) : 0.0;
        return [e.key, (e.value / 1000).toStringAsFixed(2), '$count', '${pct.toStringAsFixed(1)}%'];
      }).toList(),
      scheme: scheme,
      text: text,
      perPage: _perPage,
      currentPage: _currentPage,
      onPageChanged: (p) => setState(() => _currentPage = p),
      onPerPageChanged: (pp) => setState(() { _perPage = pp; _currentPage = 0; }),
    ),
      ],
    );
  }

  // ─── Operator Activity ──────────────────────────────────────────────────────

  Widget _buildOperatorReport(ColorScheme scheme, TextTheme text) {
    final operators = _summary['operators'] as Map<String, int>? ?? {};
    final sorted = operators.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = operators.values.fold(0, (a, b) => a + b);

    return _ReportTable(      columns: const ['Operator', 'Weighments', '% Share', 'Avg/Day'],
      rows: sorted.map((e) {
        final pct = total > 0 ? (e.value / total * 100) : 0.0;
        final days = max(1, _dateRange.duration.inDays);
        return [e.key, '${e.value}', '${pct.toStringAsFixed(1)}%', (e.value / days).toStringAsFixed(1)];
      }).toList(),
      scheme: scheme,
      text: text,
      perPage: _perPage,
      currentPage: _currentPage,
      onPageChanged: (p) => setState(() => _currentPage = p),
      onPerPageChanged: (pp) => setState(() { _perPage = pp; _currentPage = 0; }),
    );
  }

  // ─── Throughput ─────────────────────────────────────────────────────────────

  Widget _buildThroughputReport(ColorScheme scheme, TextTheme text) {
    final hourly = _summary['hourly'] as List<int>? ?? List.filled(24, 0);
    final maxH = hourly.reduce(max);

    // Build 7×24 heatmap grid from data
    final heatGrid = List.generate(7, (_) => List.filled(24, 0));
    final completed = _data.where((d) => d['status'] == 'completed').toList();
    for (final d in completed) {
      final ts = d['createdAt'];
      if (ts is Timestamp) {
        final dt = ts.toDate();
        final dow = (dt.weekday - 1) % 7; // 0=Mon
        heatGrid[dow][dt.hour]++;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hourly Distribution', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        SizedBox(height: AppSpacing.md),
        Container(
          height: 180,
          padding: AppSpacing.cardPadding,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: AppRadius.card,
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(24, (i) {
              final h = maxH > 0 ? hourly[i] / maxH : 0.0;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (hourly[i] > 0) Text('${hourly[i]}', style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant)),
                      SizedBox(height: 2.rs),
                      Container(
                        height: max(2, h * 120),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.7),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                      ),
                      SizedBox(height: 4.rs),
                      Text('${i}h', style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        SizedBox(height: AppSpacing.xl),
        if (_showVisual) ActivityHeatmap(grid: heatGrid, scheme: scheme),
        SizedBox(height: AppSpacing.xl),
        _buildDailyReport(scheme, text),
      ],
    );
  }

  // ─── Turnaround Time ─────────────────────────────────────────────────────────

  Widget _buildTurnaroundReport(ColorScheme scheme, TextTheme text) {
    final completed = _data.where((d) => d['status'] == 'completed').toList();
    final turnarounds = <Map<String, dynamic>>[];

    for (final d in completed) {
      final grossTs = d['grossDateTime'] ?? d['createdAt'];
      final tareTs = d['tareDateTime'];
      if (grossTs is Timestamp && tareTs is Timestamp) {
        final diff = tareTs.toDate().difference(grossTs.toDate());
        turnarounds.add({...d, '_turnaroundMin': diff.inMinutes});
      }
    }
    turnarounds.sort((a, b) => (b['_turnaroundMin'] as int).compareTo(a['_turnaroundMin'] as int));

    final avgMin = turnarounds.isNotEmpty ? turnarounds.map((t) => t['_turnaroundMin'] as int).reduce((a, b) => a + b) / turnarounds.length : 0.0;
    final maxMin = turnarounds.isNotEmpty ? turnarounds.map((t) => t['_turnaroundMin'] as int).reduce(max) : 0;
    final minMin = turnarounds.isNotEmpty ? turnarounds.map((t) => t['_turnaroundMin'] as int).reduce(min) : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary
        Row(children: [
          _SummaryCard(icon: Icons.timer_rounded, label: 'Avg Turnaround', value: '${avgMin.toStringAsFixed(0)} min', subtitle: 'gross to tare', scheme: scheme, text: text),
          SizedBox(width: AppSpacing.md),
          _SummaryCard(icon: Icons.speed_rounded, label: 'Fastest', value: '$minMin min', subtitle: 'minimum', scheme: scheme, text: text),
          SizedBox(width: AppSpacing.md),
          _SummaryCard(icon: Icons.hourglass_bottom_rounded, label: 'Slowest', value: '$maxMin min', subtitle: 'maximum', scheme: scheme, text: text),
          SizedBox(width: AppSpacing.md),
          _SummaryCard(icon: Icons.format_list_numbered_rounded, label: 'Measured', value: '${turnarounds.length}', subtitle: 'weighments', scheme: scheme, text: text),
        ]),
        SizedBox(height: AppSpacing.lg),
        _ReportTable(
          columns: const ['Vehicle', 'Customer', 'Material', 'Turnaround', 'Gross Time', 'Tare Time'],
          rows: turnarounds.take(100).map((d) {
            final mins = d['_turnaroundMin'] as int;
            final grossTs = d['grossDateTime'] ?? d['createdAt'];
            final tareTs = d['tareDateTime'];
            return [
              d['vehicleNumber'] as String? ?? '',
              d['customerName'] as String? ?? '',
              d['material'] as String? ?? '',
              mins >= 60 ? '${mins ~/ 60}h ${mins % 60}m' : '${mins}m',
              grossTs is Timestamp ? DateFormat('dd/MM HH:mm').format(grossTs.toDate()) : '',
              tareTs is Timestamp ? DateFormat('dd/MM HH:mm').format(tareTs.toDate()) : '',
            ];
          }).toList(),
          scheme: scheme,
          text: text,
          perPage: _perPage,
          currentPage: _currentPage,
          onPageChanged: (p) => setState(() => _currentPage = p),
          onPerPageChanged: (pp) => setState(() { _perPage = pp; _currentPage = 0; }),
        ),
      ],
    );
  }

  // ─── Vehicle Frequency ──────────────────────────────────────────────────────

  Widget _buildFrequencyReport(ColorScheme scheme, TextTheme text) {
    final completed = _data.where((d) => d['status'] == 'completed').toList();
    final vehicleCounts = <String, int>{};
    final vehicleLastSeen = <String, DateTime>{};
    final vehicleCustomer = <String, String>{};

    for (final d in completed) {
      final veh = d['vehicleNumber'] as String? ?? '';
      if (veh.isEmpty) continue;
      vehicleCounts[veh] = (vehicleCounts[veh] ?? 0) + 1;
      vehicleCustomer[veh] = d['customerName'] as String? ?? '';
      final ts = d['createdAt'];
      if (ts is Timestamp) {
        final dt = ts.toDate();
        if (!vehicleLastSeen.containsKey(veh) || dt.isAfter(vehicleLastSeen[veh]!)) {
          vehicleLastSeen[veh] = dt;
        }
      }
    }

    final sorted = vehicleCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final vehicleTonnage = <String, double>{};
    for (final d in completed) {
      final veh = d['vehicleNumber'] as String? ?? '';
      if (veh.isEmpty) continue;
      vehicleTonnage[veh] = (vehicleTonnage[veh] ?? 0) + ((d['netWeight'] as num?)?.toDouble() ?? 0) / 1000;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showVisual) ...[
          RankingBars(title: 'Most Frequent Vehicles', data: Map.fromEntries(sorted.take(10).map((e) => MapEntry(e.key, e.value.toDouble()))), unit: 'trips', scheme: scheme),
          SizedBox(height: AppSpacing.lg),
        ],
        _ReportTable(
          columns: const ['Vehicle', 'Customer', 'Trips', 'Total (T)', 'Last Seen'],
          rows: sorted.take(100).map((e) {
            final lastSeen = vehicleLastSeen[e.key];
            return [
              e.key,
              vehicleCustomer[e.key] ?? '',
              '${e.value}',
              (vehicleTonnage[e.key] ?? 0).toStringAsFixed(1),
              lastSeen != null ? DateFormat('dd/MM HH:mm').format(lastSeen) : '',
            ];
          }).toList(),
          scheme: scheme,
          text: text,
          perPage: _perPage,
          currentPage: _currentPage,
          onPageChanged: (p) => setState(() => _currentPage = p),
          onPerPageChanged: (pp) => setState(() { _perPage = pp; _currentPage = 0; }),
        ),
      ],
    );
  }

  // ─── Discrepancy / Anomaly Detection ────────────────────────────────────────

  Widget _buildDiscrepancyReport(ColorScheme scheme, TextTheme text) {
    final completed = _data.where((d) => d['status'] == 'completed').toList();

    // Group by vehicle, find anomalies (>20% deviation from that vehicle's average)
    final vehicleWeights = <String, List<double>>{};
    for (final d in completed) {
      final veh = d['vehicleNumber'] as String? ?? '';
      if (veh.isEmpty) continue;
      final net = (d['netWeight'] as num?)?.toDouble() ?? 0;
      if (net > 0) vehicleWeights.putIfAbsent(veh, () => []).add(net);
    }

    final anomalies = <Map<String, dynamic>>[];
    for (final d in completed) {
      final veh = d['vehicleNumber'] as String? ?? '';
      final net = (d['netWeight'] as num?)?.toDouble() ?? 0;
      if (veh.isEmpty || net <= 0) continue;

      final weights = vehicleWeights[veh];
      if (weights == null || weights.length < 3) continue;

      final avg = weights.reduce((a, b) => a + b) / weights.length;
      final deviation = ((net - avg) / avg).abs();
      if (deviation > 0.20) {
        anomalies.add({...d, '_deviation': deviation, '_avg': avg});
      }
    }
    anomalies.sort((a, b) => (b['_deviation'] as double).compareTo(a['_deviation'] as double));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: AppSpacing.cardPadding,
          decoration: BoxDecoration(
            color: anomalies.isNotEmpty ? scheme.errorContainer.withValues(alpha: 0.2) : scheme.surface,
            borderRadius: AppRadius.card,
            border: Border.all(color: anomalies.isNotEmpty ? scheme.error.withValues(alpha: 0.3) : scheme.outlineVariant.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(anomalies.isNotEmpty ? Icons.warning_rounded : Icons.check_circle_rounded, size: 20, color: anomalies.isNotEmpty ? scheme.error : AppTheme.successColor),
              SizedBox(width: AppSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(anomalies.isNotEmpty ? '${anomalies.length} anomalies detected' : 'No anomalies detected', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: anomalies.isNotEmpty ? scheme.error : AppTheme.successColor)),
                  Text('Weighments where net weight deviates >20% from vehicle average', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.lg),
        if (anomalies.isNotEmpty)
          _ReportTable(
            columns: const ['Vehicle', 'Customer', 'Net (kg)', 'Avg (kg)', 'Deviation', 'Date'],
            rows: anomalies.take(100).map((d) {
              final dev = d['_deviation'] as double;
              final avg = d['_avg'] as double;
              final ts = d['createdAt'];
              return [
                d['vehicleNumber'] as String? ?? '',
                d['customerName'] as String? ?? '',
                '${(d['netWeight'] as num? ?? 0).toStringAsFixed(0)}',
                avg.toStringAsFixed(0),
                '${(dev * 100).toStringAsFixed(0)}%',
                ts is Timestamp ? DateFormat('dd/MM HH:mm').format(ts.toDate()) : '',
              ];
            }).toList(),
            scheme: scheme,
            text: text,
            perPage: _perPage,
            currentPage: _currentPage,
            onPageChanged: (p) => setState(() => _currentPage = p),
            onPerPageChanged: (pp) => setState(() { _perPage = pp; _currentPage = 0; }),
          ),
      ],
    );
  }

  // ─── Comparison Report (Current vs Previous Period) ──────────────────────────

  Future<void> _loadPreviousPeriod() async {
    final duration = _dateRange.duration;
    final prevStart = _dateRange.start.subtract(duration);
    setState(() => _prevLoading = true);
    try {
      final paths = ref.read(firestorePathsProvider);
      final snap = await paths.weighments
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(prevStart))
          .where('createdAt', isLessThan: Timestamp.fromDate(_dateRange.start))
          .orderBy('createdAt', descending: true)
          .get();
      _prevData = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load previous period: $e')));
    }
    if (mounted) setState(() => _prevLoading = false);
  }

  Widget _buildComparisonReport(ColorScheme scheme, TextTheme text) {
    final duration = _dateRange.duration;
    final prevStart = _dateRange.start.subtract(duration);
    final prevEnd = _dateRange.start.subtract(const Duration(seconds: 1));

    final currentCompleted = _data.where((d) => d['status'] == 'completed').toList();
    final currentNet = currentCompleted.fold(0.0, (sum, d) => sum + ((d['netWeight'] as num?)?.toDouble() ?? 0));
    final currentVehicles = currentCompleted.map((d) => d['vehicleNumber']).toSet().length;
    final currentAvgNet = currentCompleted.isNotEmpty ? currentNet / currentCompleted.length : 0.0;

    final prevCompleted = _prevData.where((d) => d['status'] == 'completed').toList();
    final prevNet = prevCompleted.fold(0.0, (sum, d) => sum + ((d['netWeight'] as num?)?.toDouble() ?? 0));
    final prevVehicles = prevCompleted.map((d) => d['vehicleNumber']).toSet().length;
    final prevAvgNet = prevCompleted.isNotEmpty ? prevNet / prevCompleted.length : 0.0;
    final hasPrev = _prevData.isNotEmpty;

    double pctChange(double current, double previous) {
      if (previous == 0) return current > 0 ? 100 : 0;
      return ((current - previous) / previous) * 100;
    }

    Widget changeIndicator(double pct) {
      if (pct == 0) return const SizedBox.shrink();
      final isUp = pct > 0;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 14, color: isUp ? Colors.green : Colors.red),
          const SizedBox(width: 2),
          Text('${isUp ? '+' : ''}${pct.toStringAsFixed(1)}%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: isUp ? Colors.green : Colors.red)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: AppSpacing.cardPadding,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: AppRadius.card,
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Period Comparison', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (!hasPrev && !_prevLoading)
                    FilledButton.tonal(
                      onPressed: _loadPreviousPeriod,
                      child: const Text('Load Previous Period'),
                    ),
                  if (_prevLoading)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
              SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: AppSpacing.cardPadding,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.1),
                        borderRadius: AppRadius.button,
                        border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Current Period', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary)),
                          Text('${DateFormat('dd MMM').format(_dateRange.start)} – ${DateFormat('dd MMM').format(_dateRange.end)}', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                          SizedBox(height: AppSpacing.sm),
                          Text('${currentCompleted.length} weighments', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          Text('${(currentNet / 1000).toStringAsFixed(1)} T net | $currentVehicles vehicles', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: AppSpacing.md),
                  Icon(Icons.compare_arrows_rounded, size: 24, color: scheme.outlineVariant),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Container(
                      padding: AppSpacing.cardPadding,
                      decoration: BoxDecoration(
                        color: hasPrev ? scheme.tertiaryContainer.withValues(alpha: 0.1) : scheme.surfaceContainerLow,
                        borderRadius: AppRadius.button,
                        border: Border.all(color: hasPrev ? scheme.tertiary.withValues(alpha: 0.2) : scheme.outlineVariant.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Previous Period', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: hasPrev ? scheme.tertiary : scheme.onSurfaceVariant)),
                          Text('${DateFormat('dd MMM').format(prevStart)} – ${DateFormat('dd MMM').format(prevEnd)}', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                          SizedBox(height: AppSpacing.sm),
                          if (hasPrev) ...[
                            Text('${prevCompleted.length} weighments', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                            Text('${(prevNet / 1000).toStringAsFixed(1)} T net | $prevVehicles vehicles', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                          ] else ...[
                            Text('—', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: scheme.onSurfaceVariant)),
                            Text('Tap "Load" to compare', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (hasPrev) ...[
                SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(child: _comparisonMetric(scheme, text, 'Weighments', currentCompleted.length.toDouble(), prevCompleted.length.toDouble(), pctChange, changeIndicator, isCount: true)),
                    SizedBox(width: AppSpacing.md),
                    Expanded(child: _comparisonMetric(scheme, text, 'Tonnage', currentNet / 1000, prevNet / 1000, pctChange, changeIndicator, suffix: 'T')),
                    SizedBox(width: AppSpacing.md),
                    Expanded(child: _comparisonMetric(scheme, text, 'Vehicles', currentVehicles.toDouble(), prevVehicles.toDouble(), pctChange, changeIndicator, isCount: true)),
                    SizedBox(width: AppSpacing.md),
                    Expanded(child: _comparisonMetric(scheme, text, 'Avg Net', currentAvgNet / 1000, prevAvgNet / 1000, pctChange, changeIndicator, suffix: 'T')),
                  ],
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: AppSpacing.lg),
        _buildDailyReport(scheme, text),
      ],
    );
  }

  Widget _comparisonMetric(ColorScheme scheme, TextTheme text, String label, double current, double previous, double Function(double, double) pctChange, Widget Function(double) changeIndicator, {bool isCount = false, String suffix = ''}) {
    final pct = pctChange(current, previous);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadius.button,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          SizedBox(height: AppSpacing.xs),
          Text(isCount ? '${current.toInt()}' : '${current.toStringAsFixed(1)}$suffix', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          Text(isCount ? 'was ${previous.toInt()}' : 'was ${previous.toStringAsFixed(1)}$suffix', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          SizedBox(height: AppSpacing.xs),
          changeIndicator(pct),
        ],
      ),
    );
  }

  // ─── Shift Report ───────────────────────────────────────────────────────────

  Widget _buildShiftReport(ColorScheme scheme, TextTheme text) {
    final completed = _data.where((d) => d['status'] == 'completed').toList();

    // Group by operator + date for shift-like breakdown
    final shifts = <String, Map<String, dynamic>>{};
    for (final d in completed) {
      final op = d['operatorName'] as String? ?? 'Unknown';
      final ts = d['createdAt'];
      final date = ts is Timestamp ? DateFormat('dd MMM').format(ts.toDate()) : 'Unknown';
      final key = '$op|$date';

      if (!shifts.containsKey(key)) {
        shifts[key] = {'operator': op, 'date': date, 'count': 0, 'net': 0.0, 'firstTs': ts, 'lastTs': ts};
      }
      shifts[key]!['count'] = (shifts[key]!['count'] as int) + 1;
      shifts[key]!['net'] = (shifts[key]!['net'] as double) + ((d['netWeight'] as num?)?.toDouble() ?? 0);
      if (ts is Timestamp) {
        final existing = shifts[key]!['lastTs'];
        if (existing is Timestamp && ts.toDate().isAfter(existing.toDate())) {
          shifts[key]!['lastTs'] = ts;
        }
        final existingFirst = shifts[key]!['firstTs'];
        if (existingFirst is Timestamp && ts.toDate().isBefore(existingFirst.toDate())) {
          shifts[key]!['firstTs'] = ts;
        }
      }
    }

    final shiftList = shifts.values.toList()
      ..sort((a, b) {
        final dateComp = (b['date'] as String).compareTo(a['date'] as String);
        if (dateComp != 0) return dateComp;
        return (b['count'] as int).compareTo(a['count'] as int);
      });

    return _ReportTable(
      columns: const ['Operator', 'Date', 'Weighments', 'Net (T)', 'First', 'Last', 'Duration'],
      rows: shiftList.take(100).map((s) {
        final firstTs = s['firstTs'];
        final lastTs = s['lastTs'];
        String duration = '';
        if (firstTs is Timestamp && lastTs is Timestamp) {
          final diff = lastTs.toDate().difference(firstTs.toDate());
          duration = diff.inHours > 0 ? '${diff.inHours}h ${diff.inMinutes % 60}m' : '${diff.inMinutes}m';
        }
        return [
          s['operator'] as String,
          s['date'] as String,
          '${s['count']}',
          ((s['net'] as double) / 1000).toStringAsFixed(1),
          firstTs is Timestamp ? DateFormat('HH:mm').format(firstTs.toDate()) : '',
          lastTs is Timestamp ? DateFormat('HH:mm').format(lastTs.toDate()) : '',
          duration,
        ];
      }).toList(),
      scheme: scheme,
      text: text,
      perPage: _perPage,
      currentPage: _currentPage,
      onPageChanged: (p) => setState(() => _currentPage = p),
      onPerPageChanged: (pp) => setState(() { _perPage = pp; _currentPage = 0; }),
    );
  }

  // ─── Audit Trail ────────────────────────────────────────────────────────────

  Widget _buildAuditReport(ColorScheme scheme, TextTheme text) {
    _auditFuture ??= ref.read(firestorePathsProvider).auditLog
        .orderBy('timestamp', descending: true)
        .limit(100)
        .get();
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _auditFuture,
      builder: (context, snap) {
        if (!snap.hasData) return const AppLoading();
        final logs = snap.data!.docs.map((d) => d.data()).toList();
        return _ReportTable(          columns: const ['Event', 'Description', 'User', 'Time'],
          rows: logs.map((d) {
            final ts = d['timestamp'];
            final time = ts is Timestamp ? DateFormat('dd/MM HH:mm').format(ts.toDate()) : '';
            return [
              d['event'] as String? ?? '',
              d['description'] as String? ?? '',
              d['user'] as String? ?? '',
              time,
            ];
          }).toList(),
          scheme: scheme,
          text: text,
      perPage: _perPage,
      currentPage: _currentPage,
      onPageChanged: (p) => setState(() => _currentPage = p),
      onPerPageChanged: (pp) => setState(() { _perPage = pp; _currentPage = 0; }),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// REUSABLE WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  final ColorScheme scheme;
  final TextTheme text;

  const _SummaryCard({required this.icon, required this.label, required this.value, required this.subtitle, required this.scheme, required this.text});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: AppSpacing.cardPadding,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: AppRadius.card,
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
          boxShadow: AppElevation.card(scheme.shadow),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: scheme.primary),
                SizedBox(width: AppSpacing.sm),
                Text(label, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
              ],
            ),
            SizedBox(height: AppSpacing.sm),
            Text(value, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: scheme.onSurface)),
            Text(subtitle, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _ReportTable extends StatelessWidget {
  final List<String> columns;
  final List<List<String>> rows;
  final ColorScheme scheme;
  final TextTheme text;
  final int perPage;
  final int currentPage;
  final ValueChanged<int>? onPageChanged;
  final ValueChanged<int>? onPerPageChanged;

  const _ReportTable({required this.columns, required this.rows, required this.scheme, required this.text, this.perPage = 50, this.currentPage = 0, this.onPageChanged, this.onPerPageChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          // Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: scheme.surfaceContainerLow,
            child: Row(
              children: [
                Text('${rows.length} total', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                SizedBox(width: AppSpacing.md),
                Text('Per page:', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                SizedBox(width: 4.0),
                for (final pp in [25, 50, 100])
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: GestureDetector(
                      onTap: onPerPageChanged != null ? () => onPerPageChanged!(pp) : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: perPage == pp ? scheme.primary : Colors.transparent,
                          borderRadius: AppRadius.chip,
                          border: Border.all(color: perPage == pp ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.3)),
                        ),
                        child: Text('$pp', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: perPage == pp ? scheme.onPrimary : scheme.onSurfaceVariant)),
                      ),
                    ),
                  ),
                const Spacer(),
                Builder(builder: (_) {
                  final totalPages = (rows.length / perPage).ceil();
                  final page = currentPage.clamp(0, max(0, totalPages - 1)) as int;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: page > 0 && onPageChanged != null ? () => onPageChanged!(page - 1) : null,
                        icon: Icon(Icons.chevron_left_rounded, size: 18, color: page > 0 ? scheme.onSurfaceVariant : scheme.outlineVariant),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                      Text('${page + 1} / $totalPages', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                      IconButton(
                        onPressed: page < totalPages - 1 && onPageChanged != null ? () => onPageChanged!(page + 1) : null,
                        icon: Icon(Icons.chevron_right_rounded, size: 18, color: page < totalPages - 1 ? scheme.onSurfaceVariant : scheme.outlineVariant),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
          // Column Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
            child: Row(
              children: columns.map((c) => Expanded(
                child: Text(c, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
              )).toList(),
            ),
          ),
          // Rows
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(Icons.inbox_rounded, size: 32, color: scheme.outlineVariant),
                  SizedBox(height: AppSpacing.sm),
                  Text('No data for selected period', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            )
          else
            ...(() {
              final totalPages = (rows.length / perPage).ceil();
              final page = currentPage.clamp(0, max(0, totalPages - 1)) as int;
              final start = page * perPage;
              final end = min(start + perPage, rows.length) as int;
              final pageRows = rows.sublist(start, end);
              return pageRows.asMap().entries.map((entry) {
                final isEven = entry.key % 2 == 0;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  color: isEven ? Colors.transparent : scheme.surfaceContainerLowest.withValues(alpha: 0.5),
                  child: Row(
                    children: entry.value.map((cell) => Expanded(
                      child: Text(cell, style: text.bodySmall, overflow: TextOverflow.ellipsis),
                    )).toList(),
                  ),
                );
              });
            })(),
        ],
      ),
    );
  }
}
