import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/air_quality_snapshot.dart';

class AirGradientDeviceInfo {
  const AirGradientDeviceInfo({
    required this.host,
    this.deviceId,
    this.serialNo,
    this.firmware,
    this.model,
    this.board,
    this.hostname,
    this.ip,
    this.wifiRssi,
    this.wifiConnected,
    this.provisionSsid,
    this.provisionPassword,
  });

  final String host;
  final String? deviceId;
  final String? serialNo;
  final String? firmware;
  final String? model;
  final String? board;
  final String? hostname;
  final String? ip;
  final double? wifiRssi;
  final bool? wifiConnected;
  final String? provisionSsid;
  final String? provisionPassword;
}

class AirGradientLocalClient {
  AirGradientLocalClient({http.Client? client})
      : _client = client ?? http.Client();

  static const Duration _timeout = Duration(seconds: 4);
  static const List<String> _paths = <String>[
    '/measures/current',
    '/measurement/current',
  ];

  final http.Client _client;

  Future<AirGradientDeviceInfo?> fetchInfo(String host) async {
    final trimmed = host.trim();
    if (trimmed.isEmpty) return null;
    final base = trimmed.startsWith('http') ? trimmed : 'http://$trimmed';

    try {
      final response =
          await _client.get(Uri.parse('$base/info')).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final payload = jsonDecode(response.body);
      if (payload is Map<String, dynamic>) {
        return _mapInfoPayload(payload, trimmed);
      }
      if (payload is Map) {
        return _mapInfoPayload(
          payload.map((key, value) => MapEntry(key.toString(), value)),
          trimmed,
        );
      }
    } catch (_) {
      // Older AirGradient firmware exposes /config but not /info.
    }

    try {
      final response =
          await _client.get(Uri.parse('$base/config')).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final payload = jsonDecode(response.body);
      if (payload is Map<String, dynamic>) {
        return _mapConfigPayload(payload, trimmed);
      }
      if (payload is Map) {
        return _mapConfigPayload(
          payload.map((key, value) => MapEntry(key.toString(), value)),
          trimmed,
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<bool> reboot(String host) async {
    final trimmed = host.trim();
    if (trimmed.isEmpty) return false;
    final base = trimmed.startsWith('http') ? trimmed : 'http://$trimmed';

    try {
      final response =
          await _client.post(Uri.parse('$base/reboot')).timeout(_timeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<AirQualitySnapshot?> fetchSnapshot(String host) async {
    final trimmed = host.trim();
    if (trimmed.isEmpty) return null;
    final base = trimmed.startsWith('http') ? trimmed : 'http://$trimmed';

    for (final path in _paths) {
      try {
        final response =
            await _client.get(Uri.parse('$base$path')).timeout(_timeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }
        final payload = jsonDecode(response.body);
        if (payload is Map<String, dynamic>) {
          return _mapPayload(payload, trimmed);
        }
        if (payload is Map) {
          return _mapPayload(
            payload.map((key, value) => MapEntry(key.toString(), value)),
            trimmed,
          );
        }
      } catch (_) {
        // Try the next known firmware path.
      }
    }
    return null;
  }

  AirGradientDeviceInfo _mapInfoPayload(
    Map<String, dynamic> payload,
    String host,
  ) {
    return AirGradientDeviceInfo(
      host: host,
      deviceId: payload['deviceId']?.toString(),
      serialNo: payload['serialno']?.toString(),
      firmware: payload['firmware']?.toString(),
      model: payload['model']?.toString(),
      board: payload['board']?.toString(),
      hostname: payload['hostname']?.toString(),
      ip: payload['ip']?.toString(),
      wifiRssi: _toDouble(payload['wifiRssi'] ?? payload['wifi_rssi']),
      wifiConnected: _toBool(payload['wifiConnected']),
      provisionSsid: payload['provisionSsid']?.toString(),
      provisionPassword: payload['provisionPassword']?.toString(),
    );
  }

  AirGradientDeviceInfo _mapConfigPayload(
    Map<String, dynamic> payload,
    String host,
  ) {
    return AirGradientDeviceInfo(
      host: host,
      deviceId: payload['deviceId']?.toString(),
      serialNo: payload['serialno']?.toString(),
      firmware: payload['firmware']?.toString() ??
          payload['fwVersion']?.toString() ??
          payload['version']?.toString() ??
          'AirGradient local config',
      model: payload['model']?.toString(),
      board: payload['board']?.toString(),
      hostname: payload['hostname']?.toString(),
      ip: payload['ip']?.toString(),
      wifiRssi: _toDouble(payload['wifiRssi'] ?? payload['wifi_rssi']),
      wifiConnected: _toBool(payload['wifiConnected']),
      provisionSsid: payload['provisionSsid']?.toString(),
      provisionPassword: payload['provisionPassword']?.toString(),
    );
  }

  AirQualitySnapshot _mapPayload(Map<String, dynamic> payload, String host) {
    final meta = SnapshotMeta(
      firmware: payload['firmware']?.toString(),
      serialNo: payload['serialno']?.toString(),
      wifiRssi: _toDouble(payload['wifi'] ?? payload['wifi_rssi']),
      sensorSource: 'airgradient-local',
    );

    return AirQualitySnapshot(
      id: meta.serialNo ?? host,
      timestamp: DateTime.now(),
      pm25: _toDouble(payload['pm02'] ?? payload['pm25']),
      co2: _toDouble(payload['rco2'] ?? payload['co2']),
      tvoc: _toDouble(payload['tvocIndex'] ?? payload['tvoc']),
      nox: _toDouble(payload['noxIndex'] ?? payload['nox']),
      co: _toDouble(
        payload['co'] ??
            payload['co_ppm'] ??
            payload['carbon_monoxide'] ??
            payload['carbonMonoxide'],
      ),
      temperature: _toDouble(payload['atmp'] ?? payload['temp']),
      humidity: _toDouble(payload['rhum'] ?? payload['humidity']),
      meta: meta,
    );
  }

  void dispose() {
    _client.close();
  }

  double? _toDouble(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null && parsed.isFinite) return parsed;
    }
    return null;
  }

  bool? _toBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return null;
  }
}
