import 'dart:convert';

import 'package:http/http.dart' as http;

class LedControlService {
  LedControlService({this.timeout = const Duration(seconds: 3)});

  final Duration timeout;

  Uri _configUri(String deviceIp) => Uri.parse('http://$deviceIp/config');

  bool _isSuccess(int statusCode) => statusCode >= 200 && statusCode < 300;

  int _normalizeBrightness(double brightness) {
    final normalized = brightness <= 1 ? brightness * 100 : brightness;
    return normalized.round().clamp(0, 100).toInt();
  }

  Future<bool> _putConfig(String deviceIp, Map<String, dynamic> body) async {
    try {
      final before = await http.get(_configUri(deviceIp)).timeout(timeout);
      if (!_isSuccess(before.statusCode)) return false;
      final current = jsonDecode(before.body);
      if (current is! Map) return false;

      final response = await http
          .put(
            _configUri(deviceIp),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
      if (!_isSuccess(response.statusCode)) return false;

      final expectedMode = body['ledBarMode'];
      final expectedBrightness = body['ledBarBrightness'];
      if (expectedMode == null && expectedBrightness == null) return true;

      final after = await http.get(_configUri(deviceIp)).timeout(timeout);
      if (!_isSuccess(after.statusCode)) return true;
      final payload = jsonDecode(after.body);
      if (payload is! Map) return true;
      if (expectedMode != null && payload['ledBarMode'] != expectedMode) {
        return false;
      }
      if (expectedBrightness != null &&
          payload['ledBarBrightness'] != expectedBrightness) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> turnOn(String deviceIp, {double? brightness}) async {
    final body = <String, dynamic>{'ledBarMode': 'co2'};
    if (brightness != null) {
      body['ledBarBrightness'] = _normalizeBrightness(brightness);
    }
    return _putConfig(deviceIp, body);
  }

  Future<bool> turnOff(String deviceIp) {
    return _putConfig(deviceIp, const {'ledBarMode': 'off'});
  }

  Future<bool> setBrightness(String deviceIp, double brightness) {
    return _putConfig(deviceIp, {
      'ledBarBrightness': _normalizeBrightness(brightness),
    });
  }

  Future<bool> toggle(String deviceIp) async {
    try {
      final response = await http.get(_configUri(deviceIp)).timeout(timeout);
      if (!_isSuccess(response.statusCode)) return false;

      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) return false;

      final currentMode = payload['ledBarMode'] as String?;
      if (currentMode == 'off') return turnOn(deviceIp);
      return turnOff(deviceIp);
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestCo2Calibration(String deviceIp) async {
    const payloads = <Map<String, dynamic>>[
      {'co2CalibrationRequested': true},
      {'co2CalibrationRequest': true},
    ];

    for (final payload in payloads) {
      if (await _putConfig(deviceIp, payload)) return true;
    }
    return false;
  }

  Future<bool> isReachable(String deviceIp) async {
    try {
      final response = await http.get(_configUri(deviceIp)).timeout(timeout);
      return _isSuccess(response.statusCode);
    } catch (_) {
      return false;
    }
  }
}
