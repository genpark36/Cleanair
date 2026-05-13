import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../features/disaster_device/disaster_device_draft.dart';

@immutable
class PlugCommandResult {
  const PlugCommandResult({
    required this.ok,
    this.requestId,
    this.error,
    this.manualOverrideUntil,
  });

  final bool ok;
  final String? requestId;
  final String? error;
  final String? manualOverrideUntil;
}

class TasmotaPlugService {
  static const Duration _timeout = Duration(seconds: 5);
  static const String _functionsBaseUrl = String.fromEnvironment(
    'CLOUD_FUNCTION_BASE_URL',
    defaultValue:
        'https://us-central1-capstone-cleanair-2026.cloudfunctions.net',
  );
  static const String _fallbackBaseUrl =
      String.fromEnvironment('BACKEND_BASE_URL', defaultValue: '');
  static const String _deviceApiKey = String.fromEnvironment(
    'DEVICE_API_KEY',
    defaultValue: 'capstone-iaq-2026-secure-key',
  );

  bool preferLocalControl = true;
  String plugIpAddress = '';
  String plugId = '';

  String get _localTarget => _normalizeLocalTarget(plugIpAddress);
  bool get _hasLocalTarget => _localTarget.isNotEmpty;
  bool get _hasRemoteTarget => _baseUrl.isNotEmpty && plugId.trim().isNotEmpty;

  String get _baseUrl {
    if (_functionsBaseUrl.trim().isNotEmpty) return _functionsBaseUrl.trim();
    return _fallbackBaseUrl.trim();
  }

  Map<String, String> _headers() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_deviceApiKey.trim().isNotEmpty) {
      headers['X-API-Key'] = _deviceApiKey.trim();
    }
    return headers;
  }

  String _normalizeLocalTarget(String value) {
    var text = value.trim();
    if (text.isEmpty) return '';
    text = text.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    final slash = text.indexOf('/');
    if (slash >= 0) {
      text = text.substring(0, slash);
    }
    return text.trim();
  }

  Uri _commandUri(String command) {
    final target = _localTarget;
    return Uri.parse(
      'http://$target/cm?cmnd=${Uri.encodeQueryComponent(command)}',
    );
  }

  Future<Map<String, dynamic>?> _postJson(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    if (_baseUrl.isEmpty) return null;

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/$endpoint'),
            headers: _headers(),
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return <String, dynamic>{
          ...decoded,
          '_statusCode': response.statusCode,
        };
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Plug API call failed ($endpoint): $error');
      }
    }

    return null;
  }

  String _normalizeState(dynamic value) {
    final text = value?.toString().toUpperCase() ?? '';
    if (text == 'ON') return 'ON';
    if (text == 'OFF') return 'OFF';
    return 'UNKNOWN';
  }

  bool _isPowerOnOff(dynamic value) {
    final state = _normalizeState(value);
    return state == 'ON' || state == 'OFF';
  }

  bool _isLocalCommandAccepted(dynamic payload) {
    if (payload is! Map<String, dynamic>) return false;
    final command = payload['Command']?.toString().toUpperCase();
    if (command == 'ERROR') return false;
    final powerValue = payload['POWER'] ??
        payload['Power'] ??
        payload['POWER1'] ??
        payload['Power1'];
    return _isPowerOnOff(powerValue);
  }

  double? _numberFrom(dynamic value) {
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  Map<String, dynamic> _normalizeEnergyTelemetry(dynamic payload) {
    if (payload is! Map<String, dynamic>) return const <String, dynamic>{};
    final status = payload['StatusSNS'];
    final energy = status is Map
        ? status['ENERGY']
        : payload['ENERGY'] ?? payload['Energy'];
    if (energy is! Map) return const <String, dynamic>{};
    final normalized = <String, dynamic>{};
    void add(String key, dynamic value) {
      final parsed = _numberFrom(value);
      if (parsed != null) normalized[key] = parsed;
    }

    add('voltage', energy['Voltage']);
    add('current', energy['Current']);
    add('power', energy['Power'] ?? energy['ApparentPower']);
    add('total', energy['Total']);
    add('today', energy['Today']);
    add('yesterday', energy['Yesterday']);
    return normalized;
  }

  Future<bool?> getPlugState() async {
    if (preferLocalControl && _hasLocalTarget) {
      final localState = await _getLocalPlugState();
      if (localState != null) return localState;
    }

    final remotePlugId = plugId.trim();
    if (_hasRemoteTarget) {
      final result = await _postJson('getPlug', {'plugId': remotePlugId});
      final statusCode = result?['_statusCode'] as int?;
      if (statusCode != null && statusCode >= 200 && statusCode < 300) {
        final plug = result?['plug'];
        if (plug is Map<String, dynamic>) {
          final state = _normalizeState(plug['actualState']);
          if (state == 'ON') return true;
          if (state == 'OFF') return false;
        }
      }
    }

    if (!preferLocalControl && _hasLocalTarget) {
      return _getLocalPlugState();
    }

    return null;
  }

  Future<Map<String, dynamic>> getPlugTelemetry() async {
    if (preferLocalControl && _hasLocalTarget) {
      try {
        final response =
            await http.get(_commandUri('Status 8')).timeout(_timeout);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            final telemetry = _normalizeEnergyTelemetry(decoded);
            if (telemetry.isNotEmpty) return telemetry;
          }
        }
      } catch (error) {
        if (kDebugMode) {
          debugPrint('Tasmota telemetry check failed: $error');
        }
      }
    }

    final details = await getPlugDetails();
    final telemetry = details?['telemetry'];
    if (telemetry is Map) {
      return Map<String, dynamic>.from(telemetry);
    }
    return const <String, dynamic>{};
  }

  Future<bool?> _getLocalPlugState() async {
    if (!_hasLocalTarget) return null;

    try {
      final response = await http.get(_commandUri('Power')).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) return null;
      final value = (payload['POWER'] ??
              payload['Power'] ??
              payload['POWER1'] ??
              payload['Power1'])
          ?.toString()
          .toUpperCase();
      if (value == 'ON') return true;
      if (value == 'OFF') return false;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Tasmota state check failed: $error');
      }
    }

    return null;
  }

  Future<bool> setPlugState(
    bool turnOn, {
    String mode = 'manual',
    String actor = 'mobile-app',
    String? requestedByToken,
    int manualOverrideSeconds = 15 * 60,
    String? reason,
  }) async {
    final remotePlugId = plugId.trim();
    if (preferLocalControl && _hasLocalTarget) {
      final localOk = await _setLocalPlugState(turnOn);
      if (localOk) {
        if (_hasRemoteTarget) {
          final result = await sendCommand(
            plugId: remotePlugId,
            command: turnOn ? 'ON' : 'OFF',
            mode: mode,
            actor: actor,
            requestedByToken: requestedByToken,
            manualOverrideSeconds: manualOverrideSeconds,
            reason: reason,
            transportHint: 'HTTP',
          );
          if (result.requestId != null) {
            await ackCommand(
              requestId: result.requestId!,
              actualState: turnOn ? 'ON' : 'OFF',
              ok: true,
              message: 'local_http_success',
            );
          }
          await updatePlugState(
            plugId: remotePlugId,
            actualState: turnOn ? 'ON' : 'OFF',
            online: true,
          );
        }
        return true;
      }
    }

    if (_hasRemoteTarget) {
      final result = await sendCommand(
        plugId: remotePlugId,
        command: turnOn ? 'ON' : 'OFF',
        mode: mode,
        actor: actor,
        requestedByToken: requestedByToken,
        manualOverrideSeconds: manualOverrideSeconds,
        reason: reason,
      );
      if (result.ok) return true;
    }

    if (!preferLocalControl && _hasLocalTarget) {
      return _setLocalPlugState(turnOn);
    }

    return false;
  }

  Future<bool> _setLocalPlugState(bool turnOn) async {
    if (!_hasLocalTarget) return false;
    final command = turnOn ? 'Power ON' : 'Power OFF';

    try {
      final response = await http.get(_commandUri(command)).timeout(_timeout);
      if (response.statusCode != 200) return false;
      final payload = jsonDecode(response.body);
      return _isLocalCommandAccepted(payload);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Tasmota power set failed: $error');
      }
      return false;
    }
  }

  Future<bool> togglePlug({
    String mode = 'manual',
    String actor = 'mobile-app',
    String? requestedByToken,
    int manualOverrideSeconds = 15 * 60,
    String? reason,
  }) async {
    final remotePlugId = plugId.trim();
    if (preferLocalControl && _hasLocalTarget) {
      final localOk = await _toggleLocalPlug();
      if (localOk) return true;
    }

    if (_hasRemoteTarget) {
      final result = await sendCommand(
        plugId: remotePlugId,
        command: 'TOGGLE',
        mode: mode,
        actor: actor,
        requestedByToken: requestedByToken,
        manualOverrideSeconds: manualOverrideSeconds,
        reason: reason,
      );
      if (result.ok) return true;
    }

    if (!preferLocalControl && _hasLocalTarget) {
      return _toggleLocalPlug();
    }

    return false;
  }

  Future<bool> _toggleLocalPlug() async {
    if (!_hasLocalTarget) return false;

    try {
      final response =
          await http.get(_commandUri('Power TOGGLE')).timeout(_timeout);
      if (response.statusCode != 200) return false;
      final payload = jsonDecode(response.body);
      return _isLocalCommandAccepted(payload);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Tasmota toggle failed: $error');
      }
      return false;
    }
  }

  Future<PlugCommandResult> sendCommand({
    required String plugId,
    required String command,
    String mode = 'manual',
    String actor = 'mobile-app',
    String? requestedByToken,
    int manualOverrideSeconds = 15 * 60,
    String? reason,
    Map<String, dynamic>? sensorSnapshot,
    String transportHint = 'MQTT',
  }) async {
    if (_baseUrl.isEmpty) {
      return const PlugCommandResult(
        ok: false,
        error: 'base_url_not_configured',
      );
    }

    final result = await _postJson('commandPlug', {
      'plugId': plugId,
      'command': command,
      'mode': mode,
      'actor': actor,
      'requestedByToken': requestedByToken,
      'manualOverrideSeconds': manualOverrideSeconds,
      'reason': reason,
      'sensorSnapshot': sensorSnapshot,
      'transportHint': transportHint,
    });

    final statusCode = result?['_statusCode'] as int?;
    if (result == null ||
        statusCode == null ||
        statusCode < 200 ||
        statusCode >= 300) {
      return PlugCommandResult(
        ok: false,
        error: result?['error']?.toString() ?? 'command_failed',
      );
    }

    if (result['ok'] == true) {
      return PlugCommandResult(
        ok: true,
        requestId: result['requestId']?.toString(),
        manualOverrideUntil: result['manualOverrideUntil']?.toString(),
      );
    }

    return PlugCommandResult(
      ok: false,
      error: result['error']?.toString() ?? 'command_failed',
    );
  }

  Future<bool> ackCommand({
    required String requestId,
    required String actualState,
    required bool ok,
    String? message,
  }) async {
    final result = await _postJson('ackPlugCommand', {
      'requestId': requestId,
      'status': ok ? 'acknowledged' : 'failed',
      'actualState': actualState,
      'online': ok,
      'workerId': 'cleanair-mobile-local-http',
      'errorMessage': ok ? null : message,
      'responsePayloadRaw': {
        'message': message,
        'source': 'mobile_local_http',
      },
    });
    final statusCode = result?['_statusCode'] as int?;
    return result?['ok'] == true &&
        statusCode != null &&
        statusCode >= 200 &&
        statusCode < 300;
  }

  Future<bool> updatePlugState({
    required String plugId,
    required String actualState,
    required bool online,
    Map<String, dynamic>? telemetry,
  }) async {
    final result = await _postJson('updatePlugState', {
      'plugId': plugId,
      'actualState': actualState,
      'online': online,
      'source': 'mobile_local_http',
      'telemetry': telemetry,
    });
    final statusCode = result?['_statusCode'] as int?;
    return result?['ok'] == true &&
        statusCode != null &&
        statusCode >= 200 &&
        statusCode < 300;
  }

  Future<Map<String, dynamic>?> getPlugDetails({String? targetPlugId}) async {
    final id = (targetPlugId ?? plugId).trim();
    if (id.isEmpty) return null;

    final result = await _postJson('getPlug', {'plugId': id});
    final statusCode = result?['_statusCode'] as int?;
    if (result == null ||
        statusCode == null ||
        statusCode < 200 ||
        statusCode >= 300) {
      return null;
    }

    final plug = result['plug'];
    if (plug is Map<String, dynamic>) return plug;
    return null;
  }

  Future<List<Map<String, dynamic>>> listPlugs({
    String? stationId,
    String? sensorId,
    int limit = 20,
  }) async {
    final result = await _postJson('listPlugs', {
      'stationId': stationId,
      'sensorId': sensorId,
      'limit': limit,
    });
    final statusCode = result?['_statusCode'] as int?;
    if (result == null ||
        statusCode == null ||
        statusCode < 200 ||
        statusCode >= 300) {
      return const [];
    }

    final plugs = result['plugs'];
    if (plugs is! List) return const [];
    return plugs.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<bool> registerPlug({
    required String plugId,
    String? displayName,
    String? stationId,
    String? sensorId,
    String? tasmotaTopic,
    String? profileId,
    String mode = 'auto',
    bool controlEnabled = true,
    String transportPrimary = 'MQTT',
    String transportFallback = 'HTTP',
  }) async {
    final result = await _postJson('registerPlug', {
      'plugId': plugId,
      'displayName': displayName,
      'stationId': stationId,
      'sensorId': sensorId,
      'tasmotaTopic': tasmotaTopic,
      'profileId': profileId,
      'mode': mode,
      'controlEnabled': controlEnabled,
      'transportPrimary': transportPrimary,
      'transportFallback': transportFallback,
    });

    final statusCode = result?['_statusCode'] as int?;
    return result != null &&
        statusCode != null &&
        statusCode >= 200 &&
        statusCode < 300 &&
        result['ok'] == true;
  }

  Future<String?> upsertAqiProfile({
    required String profileId,
    String name = 'AQI Auto Profile',
    int? aqiOn,
    int? aqiOff,
    String metric = 'iaqi',
    double? onThreshold,
    double? offThreshold,
    List<DisasterAutoRule>? rules,
    int minCommandIntervalSeconds = 120,
  }) async {
    final normalizedId = profileId.trim();
    if (normalizedId.isEmpty) return null;

    final normalizedMetric = _normalizeAutoMetric(metric);
    final resolvedOn = onThreshold ??
        (aqiOn == null ? null : aqiOn / (normalizedMetric == 'iaqi' ? 100 : 1));
    final resolvedOff = offThreshold ??
        (aqiOff == null ? null : aqiOff / (normalizedMetric == 'iaqi' ? 100 : 1));
    if (resolvedOn == null || resolvedOff == null) return null;

    final legacyAqiOn = aqiOn ?? (resolvedOn * 100).round();
    final legacyAqiOff = aqiOff ?? (resolvedOff * 100).round();
    final hysteresis = (resolvedOn - resolvedOff).abs();
    final result = await _postJson('upsertPlugProfile', {
      'profileId': normalizedId,
      'name': name,
      'metric': normalizedMetric,
      if (rules != null && rules.isNotEmpty)
        'rules': rules
            .map((rule) => {
                  'metric': _normalizeAutoMetric(rule.metric),
                  'thresholds': {
                    'metric': _normalizeAutoMetric(rule.metric),
                    'onThreshold': rule.onThreshold,
                    'offThreshold': rule.offThreshold,
                    if (_normalizeAutoMetric(rule.metric) == 'iaqi') ...{
                      'aqiOn': (rule.onThreshold * 100).round(),
                      'aqiOff': (rule.offThreshold * 100).round(),
                      'iaqiOn': rule.onThreshold,
                      'iaqiOff': rule.offThreshold,
                    },
                    '${_normalizeAutoMetric(rule.metric)}On':
                        rule.onThreshold,
                    '${_normalizeAutoMetric(rule.metric)}Off':
                        rule.offThreshold,
                  },
                  'hysteresis': {
                    'metric': _normalizeAutoMetric(rule.metric),
                    'value':
                        (rule.onThreshold - rule.offThreshold).abs(),
                    _normalizeAutoMetric(rule.metric):
                        (rule.onThreshold - rule.offThreshold).abs(),
                  },
                })
            .toList(),
      'thresholds': {
        'metric': normalizedMetric,
        'onThreshold': resolvedOn,
        'offThreshold': resolvedOff,
        if (normalizedMetric == 'iaqi') ...{
          'aqiOn': legacyAqiOn,
          'aqiOff': legacyAqiOff,
          'iaqiOn': resolvedOn,
          'iaqiOff': resolvedOff,
        },
        '${normalizedMetric}On': resolvedOn,
        '${normalizedMetric}Off': resolvedOff,
      },
      'hysteresis': {
        'metric': normalizedMetric,
        'value': hysteresis,
        if (normalizedMetric == 'iaqi') 'aqi': (legacyAqiOn - legacyAqiOff).abs(),
        normalizedMetric: hysteresis,
      },
      'constraints': {'minCommandIntervalSeconds': minCommandIntervalSeconds},
    });

    final statusCode = result?['_statusCode'] as int?;
    final ok = result != null &&
        statusCode != null &&
        statusCode >= 200 &&
        statusCode < 300 &&
        result['ok'] == true;

    if (!ok) return null;
    return (result['profileId'] ?? normalizedId).toString();
  }

  String _normalizeAutoMetric(String value) {
    final normalized = value.trim().toLowerCase();
    const allowed = {'iaqi', 'co2', 'pm25', 'tvoc', 'nox'};
    return allowed.contains(normalized) ? normalized : 'iaqi';
  }

  Future<List<Map<String, dynamic>>> getControlTrace({
    String? targetPlugId,
    int limit = 12,
  }) async {
    final id = (targetPlugId ?? plugId).trim();
    if (id.isEmpty) return const [];

    final normalizedLimit = limit.clamp(1, 50).toInt();
    final result = await _postJson('getPlugControlTrace', {
      'plugId': id,
      'limit': normalizedLimit,
    });

    final statusCode = result?['_statusCode'] as int?;
    if (result == null ||
        statusCode == null ||
        statusCode < 200 ||
        statusCode >= 300) {
      return const [];
    }

    final traces = result['traces'];
    if (traces is! List) return const [];
    return traces.whereType<Map<String, dynamic>>().toList(growable: false);
  }
}
