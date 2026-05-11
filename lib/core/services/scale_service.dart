import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum ScaleConnectionType { http, serial, simulated }

enum ScaleStatus { disconnected, connecting, connected, reading, stable, error }

class ScaleReading {
  final double weight;
  final bool isStable;
  final DateTime timestamp;

  ScaleReading({required this.weight, required this.isStable, required this.timestamp});
}

class ScaleService {
  final ScaleConnectionType connectionType;
  final String endpoint;
  final http.Client _client;

  ScaleStatus _status = ScaleStatus.disconnected;
  double _lastWeight = 0;
  bool _isStable = false;
  Timer? _pollTimer;
  final StreamController<ScaleReading> _readingController = StreamController.broadcast();

  ScaleService({
    this.connectionType = ScaleConnectionType.http,
    this.endpoint = 'http://localhost:8421/weight',
  }) : _client = http.Client();

  ScaleStatus get status => _status;
  double get lastWeight => _lastWeight;
  bool get isStable => _isStable;
  Stream<ScaleReading> get readings => _readingController.stream;

  Future<bool> connect() async {
    _status = ScaleStatus.connecting;
    if (connectionType == ScaleConnectionType.simulated) {
      _status = ScaleStatus.connected;
      return true;
    }

    try {
      final response = await _client
          .get(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        _status = ScaleStatus.connected;
        return true;
      }
    } catch (e) {
      debugPrint('Scale connect error: $e');
    }
    _status = ScaleStatus.disconnected;
    return false;
  }

  void startPolling({Duration interval = const Duration(milliseconds: 500)}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) => _readWeight());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<ScaleReading> readOnce() async {
    return _readWeight();
  }

  Future<ScaleReading> _readWeight() async {
    if (connectionType == ScaleConnectionType.simulated) {
      // Simulated weight for testing
      _lastWeight = 24500;
      _isStable = true;
      _status = ScaleStatus.stable;
      final reading = ScaleReading(weight: _lastWeight, isStable: _isStable, timestamp: DateTime.now());
      _readingController.add(reading);
      return reading;
    }

    try {
      final response = await _client
          .get(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _lastWeight = (data['weight'] as num?)?.toDouble() ?? 0;
        _isStable = data['stable'] ?? false;
        _status = _isStable ? ScaleStatus.stable : ScaleStatus.reading;
        final reading = ScaleReading(weight: _lastWeight, isStable: _isStable, timestamp: DateTime.now());
        _readingController.add(reading);
        return reading;
      }
    } catch (e) {
      debugPrint('Scale read error: $e');
      _status = ScaleStatus.error;
    }
    return ScaleReading(weight: _lastWeight, isStable: _isStable, timestamp: DateTime.now());
  }

  /// Wait for stable weight reading (weight doesn't change for stabilizationTime)
  Future<ScaleReading> waitForStable({
    Duration stabilizationTime = const Duration(seconds: 3),
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final completer = Completer<ScaleReading>();
    double? lastStableWeight;
    DateTime? stableSince;

    startPolling();

    final sub = readings.listen((reading) {
      if (reading.isStable) {
        if (lastStableWeight == reading.weight && stableSince != null) {
          if (DateTime.now().difference(stableSince!) >= stabilizationTime) {
            if (!completer.isCompleted) {
              completer.complete(reading);
            }
          }
        } else {
          lastStableWeight = reading.weight;
          stableSince = DateTime.now();
        }
      } else {
        lastStableWeight = null;
        stableSince = null;
      }
    });

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(ScaleReading(weight: _lastWeight, isStable: _isStable, timestamp: DateTime.now()));
      }
    });

    final result = await completer.future;
    timer.cancel();
    await sub.cancel();
    stopPolling();
    return result;
  }

  /// Check if scale reads zero (empty platform)
  Future<bool> isZero({double tolerance = 50}) async {
    final reading = await readOnce();
    return reading.weight.abs() <= tolerance;
  }

  void dispose() {
    _pollTimer?.cancel();
    _readingController.close();
    _client.close();
  }
}
