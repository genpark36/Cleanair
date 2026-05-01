import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

@immutable
class DeviceBindingConfigV2 {
  const DeviceBindingConfigV2({
    required this.deviceId,
    required this.firestoreDocPath,
  });

  final String deviceId;
  final String firestoreDocPath;

  static const DeviceBindingConfigV2 empty = DeviceBindingConfigV2(
    deviceId: '',
    firestoreDocPath: '',
  );

  bool get isBound => deviceId.isNotEmpty && firestoreDocPath.isNotEmpty;
}

class DeviceBindingStorageV2 {
  static const _deviceIdKey = 'device_binding_v2_device_id';
  static const _docPathKey = 'device_binding_v2_firestore_doc_path';

  Future<DeviceBindingConfigV2> load() async {
    final prefs = await SharedPreferences.getInstance();
    return DeviceBindingConfigV2(
      deviceId: prefs.getString(_deviceIdKey) ?? '',
      firestoreDocPath: prefs.getString(_docPathKey) ?? '',
    );
  }

  Future<void> save(DeviceBindingConfigV2 config) async {
    final prefs = await SharedPreferences.getInstance();
    if (config.deviceId.isEmpty) {
      await prefs.remove(_deviceIdKey);
    } else {
      await prefs.setString(_deviceIdKey, config.deviceId);
    }

    if (config.firestoreDocPath.isEmpty) {
      await prefs.remove(_docPathKey);
    } else {
      await prefs.setString(_docPathKey, config.firestoreDocPath);
    }
  }
}

class DeviceBindingControllerV2 extends ChangeNotifier {
  DeviceBindingControllerV2(this._storage);

  final DeviceBindingStorageV2 _storage;
  DeviceBindingConfigV2 _config = DeviceBindingConfigV2.empty;
  bool _loaded = false;

  static const String _functionsBaseUrl =
      String.fromEnvironment('CLOUD_FUNCTION_BASE_URL', defaultValue: '');
  static const String _fallbackBaseUrl =
      String.fromEnvironment('BACKEND_BASE_URL', defaultValue: '');
  static const String _deviceApiKey =
      String.fromEnvironment('DEVICE_API_KEY', defaultValue: '');

  DeviceBindingConfigV2 get value => _config;
  bool get isLoaded => _loaded;

  String get _baseUrl {
    if (_functionsBaseUrl.trim().isNotEmpty) return _functionsBaseUrl.trim();
    return _fallbackBaseUrl.trim();
  }

  Map<String, String> _headers() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_deviceApiKey.isNotEmpty) {
      headers['X-API-Key'] = _deviceApiKey;
    }
    return headers;
  }

  Future<void> load() async {
    _config = await _storage.load();
    _loaded = true;
    notifyListeners();
  }

  Future<void> clear() async {
    _config = DeviceBindingConfigV2.empty;
    await _storage.save(_config);
    notifyListeners();
  }

  Future<DeviceBindingConfigV2> claimDevice({
    required String code,
    required String token,
  }) async {
    if (_baseUrl.isEmpty) {
      throw StateError('CLOUD_FUNCTION_BASE_URL is not configured');
    }
    if (code.trim().isEmpty) {
      throw ArgumentError('device code required');
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/claimDevice'),
      headers: _headers(),
      body: jsonEncode({
        'token': token,
        'code': code.trim(),
      }),
    );

    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        data = decoded;
      }
    } catch (_) {
      data = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final backendError = data?['error']?.toString();
      if (backendError != null && backendError.isNotEmpty) {
        throw StateError(backendError);
      }
      throw StateError('claim failed: ${response.statusCode}');
    }

    final payload = data ?? <String, dynamic>{};
    if (payload['ok'] != true) {
      throw StateError(payload['error']?.toString() ?? 'claim failed');
    }

    final deviceId = (payload['sensorId'] ?? '').toString();
    final firestoreDocPath =
        (payload['firestoreDocPath'] ?? (deviceId.isNotEmpty ? 'sensors/$deviceId' : ''))
            .toString();

    _config = DeviceBindingConfigV2(
      deviceId: deviceId,
      firestoreDocPath: firestoreDocPath,
    );

    await _storage.save(_config);
    notifyListeners();
    return _config;
  }

  Future<void> applyBinding({
    required String deviceId,
    required String firestoreDocPath,
  }) async {
    if (deviceId.isEmpty || firestoreDocPath.isEmpty) return;
    _config = DeviceBindingConfigV2(
      deviceId: deviceId,
      firestoreDocPath: firestoreDocPath,
    );
    await _storage.save(_config);
    notifyListeners();
  }
}
