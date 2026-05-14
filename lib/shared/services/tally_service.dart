import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum TallyConnectionStatus { disconnected, connecting, connected, error }

class TallyConfig {
  final bool enabled;
  final String host;
  final int port;
  final String company;
  final String syncMode;
  final bool pushVouchers;
  final bool pushLedgers;
  final bool mapMaterials;

  const TallyConfig({
    this.enabled = false,
    this.host = '',
    this.port = 9000,
    this.company = '',
    this.syncMode = 'auto',
    this.pushVouchers = true,
    this.pushLedgers = false,
    this.mapMaterials = true,
  });

  factory TallyConfig.fromMap(Map<String, dynamic> data) {
    return TallyConfig(
      enabled: data['enabled'] as bool? ?? false,
      host: data['host'] as String? ?? '',
      port: data['port'] as int? ?? 9000,
      company: data['company'] as String? ?? '',
      syncMode: data['syncMode'] as String? ?? 'auto',
      pushVouchers: data['pushVouchers'] as bool? ?? true,
      pushLedgers: data['pushLedgers'] as bool? ?? false,
      mapMaterials: data['mapMaterials'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'host': host,
    'port': port,
    'company': company,
    'syncMode': syncMode,
    'pushVouchers': pushVouchers,
    'pushLedgers': pushLedgers,
    'mapMaterials': mapMaterials,
  };
}

class TallySyncResult {
  final bool success;
  final String message;
  final int? recordsPushed;
  final DateTime timestamp;

  TallySyncResult({required this.success, required this.message, this.recordsPushed})
      : timestamp = DateTime.now();
}

class TallyService {
  TallyConfig _config;
  final _statusController = StreamController<TallyConnectionStatus>.broadcast();
  final _syncLogController = StreamController<TallySyncResult>.broadcast();
  TallyConnectionStatus _status = TallyConnectionStatus.disconnected;
  Timer? _autoSyncTimer;

  TallyService(this._config) {
    if (_config.enabled && _config.syncMode == 'auto') {
      _startAutoSync();
    }
  }

  Stream<TallyConnectionStatus> get statusStream => _statusController.stream;
  Stream<TallySyncResult> get syncLogStream => _syncLogController.stream;
  TallyConnectionStatus get status => _status;
  TallyConfig get config => _config;

  void updateConfig(TallyConfig config) {
    _config = config;
    _autoSyncTimer?.cancel();
    if (_config.enabled && _config.syncMode == 'auto') {
      _startAutoSync();
    }
  }

  Future<bool> testConnection() async {
    if (_config.host.isEmpty) return false;
    _setStatus(TallyConnectionStatus.connecting);

    try {
      final socket = await Socket.connect(_config.host, _config.port, timeout: const Duration(seconds: 5));
      socket.destroy();
      _setStatus(TallyConnectionStatus.connected);
      return true;
    } catch (_) {
      _setStatus(TallyConnectionStatus.error);
      return false;
    }
  }

  Future<TallySyncResult> pushWeighment(Map<String, dynamic> weighment) async {
    if (!_config.enabled || !_config.pushVouchers) {
      return TallySyncResult(success: false, message: 'Tally sync disabled or voucher push off');
    }

    try {
      final xml = _buildVoucherXml(weighment);
      final response = await _sendToTally(xml);

      if (response.contains('<LINEERROR>')) {
        final result = TallySyncResult(success: false, message: 'Tally rejected the voucher');
        _syncLogController.add(result);
        return result;
      }

      final result = TallySyncResult(success: true, message: 'Voucher pushed', recordsPushed: 1);
      _syncLogController.add(result);
      return result;
    } catch (e) {
      final result = TallySyncResult(success: false, message: 'Push failed: $e');
      _syncLogController.add(result);
      return result;
    }
  }

  Future<TallySyncResult> pushLedger(Map<String, dynamic> customer) async {
    if (!_config.enabled || !_config.pushLedgers) {
      return TallySyncResult(success: false, message: 'Ledger push disabled');
    }

    try {
      final xml = _buildLedgerXml(customer);
      final response = await _sendToTally(xml);

      if (response.contains('<LINEERROR>')) {
        final result = TallySyncResult(success: false, message: 'Tally rejected the ledger');
        _syncLogController.add(result);
        return result;
      }

      final result = TallySyncResult(success: true, message: 'Ledger pushed', recordsPushed: 1);
      _syncLogController.add(result);
      return result;
    } catch (e) {
      final result = TallySyncResult(success: false, message: 'Ledger push failed: $e');
      _syncLogController.add(result);
      return result;
    }
  }

  Future<List<String>> fetchMaterialsList() async {
    if (!_config.enabled) return [];

    try {
      const xml = '''
<ENVELOPE>
  <HEADER><TALLYREQUEST>Export Data</TALLYREQUEST></HEADER>
  <BODY><EXPORTDATA><REQUESTDESC>
    <REPORTNAME>List of Accounts</REPORTNAME>
    <STATICVARIABLES><ACCOUNTTYPE>Stock Item</ACCOUNTTYPE></STATICVARIABLES>
  </REQUESTDESC></EXPORTDATA></BODY>
</ENVELOPE>''';

      final response = await _sendToTally(xml);
      final nameRegex = RegExp(r'<STOCKITEMNAME[^>]*>([^<]+)</STOCKITEMNAME>');
      return nameRegex.allMatches(response).map((m) => m.group(1)!).toList();
    } catch (_) {
      return [];
    }
  }

  String _buildVoucherXml(Map<String, dynamic> weighment) {
    final date = weighment['date'] as String? ?? _tallyDate(DateTime.now());
    final vehicleNo = weighment['vehicleNumber'] as String? ?? '';
    final material = weighment['material'] as String? ?? '';
    final netWeight = weighment['netWeight'] as num? ?? 0;
    final customer = weighment['customerName'] as String? ?? 'Cash';

    return '''
<ENVELOPE>
  <HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER>
  <BODY><IMPORTDATA><REQUESTDESC>
    <REPORTNAME>Vouchers</REPORTNAME>
    <STATICVARIABLES><SVCURRENTCOMPANY>${ _config.company }</SVCURRENTCOMPANY></STATICVARIABLES>
  </REQUESTDESC>
  <REQUESTDATA>
    <TALLYMESSAGE xmlns:UDF="TallyUDF">
      <VOUCHER VCHTYPE="Sales" ACTION="Create">
        <DATE>$date</DATE>
        <NARRATION>Vehicle: $vehicleNo | Material: $material | Net: ${netWeight}kg</NARRATION>
        <PARTYLEDGERNAME>$customer</PARTYLEDGERNAME>
        <ALLINVENTORYENTRIES.LIST>
          <STOCKITEMNAME>$material</STOCKITEMNAME>
          <ACTUALQTY>$netWeight kg</ACTUALQTY>
        </ALLINVENTORYENTRIES.LIST>
      </VOUCHER>
    </TALLYMESSAGE>
  </REQUESTDATA></IMPORTDATA></BODY>
</ENVELOPE>''';
  }

  String _buildLedgerXml(Map<String, dynamic> customer) {
    final name = customer['name'] as String? ?? '';
    final phone = customer['phone'] as String? ?? '';
    final address = customer['address'] as String? ?? '';

    return '''
<ENVELOPE>
  <HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER>
  <BODY><IMPORTDATA><REQUESTDESC>
    <REPORTNAME>All Masters</REPORTNAME>
    <STATICVARIABLES><SVCURRENTCOMPANY>${ _config.company }</SVCURRENTCOMPANY></STATICVARIABLES>
  </REQUESTDESC>
  <REQUESTDATA>
    <TALLYMESSAGE xmlns:UDF="TallyUDF">
      <LEDGER NAME="$name" ACTION="Create">
        <PARENT>Sundry Debtors</PARENT>
        <LEDGERPHONE>$phone</LEDGERPHONE>
        <ADDRESS.LIST><ADDRESS>$address</ADDRESS></ADDRESS.LIST>
      </LEDGER>
    </TALLYMESSAGE>
  </REQUESTDATA></IMPORTDATA></BODY>
</ENVELOPE>''';
  }

  Future<String> _sendToTally(String xml) async {
    final socket = await Socket.connect(_config.host, _config.port, timeout: const Duration(seconds: 10));

    final body = utf8.encode(xml);
    final header = 'POST / HTTP/1.1\r\n'
        'Host: ${_config.host}:${_config.port}\r\n'
        'Content-Type: application/xml\r\n'
        'Content-Length: ${body.length}\r\n'
        '\r\n';

    socket.add(utf8.encode(header));
    socket.add(body);
    await socket.flush();

    final response = StringBuffer();
    await for (final chunk in socket.timeout(const Duration(seconds: 15))) {
      response.write(utf8.decode(chunk, allowMalformed: true));
    }
    socket.destroy();

    return response.toString();
  }

  void _startAutoSync() {
    _autoSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      // Auto-sync checks are handled by the weighment flow calling pushWeighment
    });
  }

  String _tallyDate(DateTime dt) => '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';

  void _setStatus(TallyConnectionStatus s) {
    _status = s;
    _statusController.add(s);
  }

  void dispose() {
    _autoSyncTimer?.cancel();
    _statusController.close();
    _syncLogController.close();
  }
}
