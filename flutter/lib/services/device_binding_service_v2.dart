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

@immutable
class DeviceBindingRecordV2 {
  const DeviceBindingRecordV2({
    required this.deviceId,
    required this.firestoreDocPath,
    this.displayName = '',
    this.localIp = '',
    this.registeredAt,
    this.updatedAt,
    this.lastSelectedAt,
  });

  final String deviceId;
  final String firestoreDocPath;
  final String displayName;
  final String localIp;
  final DateTime? registeredAt;
  final DateTime? updatedAt;
  final DateTime? lastSelectedAt;

  bool get isBound => deviceId.isNotEmpty && firestoreDocPath.isNotEmpty;

  String get label {
    final name = displayName.trim();
    return name.isEmpty ? deviceId : name;
  }

  DeviceBindingConfigV2 get config => DeviceBindingConfigV2(
        deviceId: deviceId,
        firestoreDocPath: firestoreDocPath,
      );

  DeviceBindingRecordV2 copyWith({
    String? deviceId,
    String? firestoreDocPath,
    String? displayName,
    String? localIp,
    DateTime? registeredAt,
    DateTime? updatedAt,
    DateTime? lastSelectedAt,
  }) {
    return DeviceBindingRecordV2(
      deviceId: deviceId ?? this.deviceId,
      firestoreDocPath: firestoreDocPath ?? this.firestoreDocPath,
      displayName: displayName ?? this.displayName,
      localIp: localIp ?? this.localIp,
      registeredAt: registeredAt ?? this.registeredAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastSelectedAt: lastSelectedAt ?? this.lastSelectedAt,
    );
  }

  factory DeviceBindingRecordV2.fromConfig(
    DeviceBindingConfigV2 config, {
    String displayName = '',
    String localIp = '',
    DateTime? registeredAt,
    DateTime? updatedAt,
    DateTime? lastSelectedAt,
  }) {
    return DeviceBindingRecordV2(
      deviceId: config.deviceId,
      firestoreDocPath: config.firestoreDocPath,
      displayName: displayName,
      localIp: localIp,
      registeredAt: registeredAt,
      updatedAt: updatedAt,
      lastSelectedAt: lastSelectedAt,
    );
  }

  factory DeviceBindingRecordV2.fromJson(Map<String, dynamic> json) {
    DateTime? readDate(String key) {
      final raw = json[key]?.toString();
      if (raw == null || raw.trim().isEmpty) return null;
      return DateTime.tryParse(raw);
    }

    return DeviceBindingRecordV2(
      deviceId: json['deviceId']?.toString().trim() ?? '',
      firestoreDocPath: json['firestoreDocPath']?.toString().trim() ?? '',
      displayName: json['displayName']?.toString().trim() ?? '',
      localIp: json['localIp']?.toString().trim() ?? '',
      registeredAt: readDate('registeredAt'),
      updatedAt: readDate('updatedAt'),
      lastSelectedAt: readDate('lastSelectedAt'),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'deviceId': deviceId,
      'firestoreDocPath': firestoreDocPath,
      if (displayName.trim().isNotEmpty) 'displayName': displayName.trim(),
      if (localIp.trim().isNotEmpty) 'localIp': localIp.trim(),
      if (registeredAt != null) 'registeredAt': registeredAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      if (lastSelectedAt != null)
        'lastSelectedAt': lastSelectedAt!.toIso8601String(),
    };
  }
}

class DeviceBindingStorageV2 {
  static const _deviceIdKey = 'device_binding_v2_device_id';
  static const _docPathKey = 'device_binding_v2_firestore_doc_path';
  static const _bindingsKey = 'device_binding_v2_bindings';

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

  Future<List<DeviceBindingRecordV2>> loadBindings() async {
    final prefs = await SharedPreferences.getInstance();
    final records = _decodeBindings(prefs.getString(_bindingsKey));
    final active = await load();
    if (!active.isBound) return records;

    final exists = records.any((record) => record.deviceId == active.deviceId);
    if (exists) return records;

    final migrated = <DeviceBindingRecordV2>[
      DeviceBindingRecordV2.fromConfig(
        active,
        registeredAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastSelectedAt: DateTime.now(),
      ),
      ...records,
    ];
    await saveBindings(migrated);
    return migrated;
  }

  Future<void> saveBindings(List<DeviceBindingRecordV2> bindings) async {
    final prefs = await SharedPreferences.getInstance();
    final deduped = <String, DeviceBindingRecordV2>{};
    for (final binding in bindings) {
      if (!binding.isBound) continue;
      deduped[binding.deviceId] = binding;
    }
    await prefs.setString(
      _bindingsKey,
      jsonEncode(deduped.values.map((record) => record.toJson()).toList()),
    );
  }

  List<DeviceBindingRecordV2> _decodeBindings(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const <DeviceBindingRecordV2>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <DeviceBindingRecordV2>[];
      return decoded
          .whereType<Map>()
          .map((item) => DeviceBindingRecordV2.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((record) => record.isBound)
          .toList(growable: false);
    } catch (_) {
      return const <DeviceBindingRecordV2>[];
    }
  }
}

class DeviceBindingControllerV2 extends ChangeNotifier {
  DeviceBindingControllerV2(this._storage);

  final DeviceBindingStorageV2 _storage;
  DeviceBindingConfigV2 _config = DeviceBindingConfigV2.empty;
  List<DeviceBindingRecordV2> _bindings = const <DeviceBindingRecordV2>[];
  bool _loaded = false;

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

  DeviceBindingConfigV2 get value => _config;
  List<DeviceBindingRecordV2> get bindings => _bindings;
  DeviceBindingRecordV2? get activeRecord {
    for (final record in _bindings) {
      if (record.deviceId == _config.deviceId) return record;
    }
    return null;
  }

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
    _bindings = await _storage.loadBindings();
    if (!_config.isBound && _bindings.isNotEmpty) {
      _config = _bindings.first.config;
      await _storage.save(_config);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> clear() async {
    _config = DeviceBindingConfigV2.empty;
    _bindings = const <DeviceBindingRecordV2>[];
    await _storage.save(_config);
    await _storage.saveBindings(_bindings);
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

    final deviceId =
        (payload['sensorId'] ?? payload['deviceId'] ?? '').toString().trim();
    final firestoreDocPath = (payload['firestoreDocPath'] ??
            (deviceId.isNotEmpty ? 'sensors/$deviceId' : ''))
        .toString()
        .trim();
    if (deviceId.isEmpty || firestoreDocPath.isEmpty) {
      throw StateError('claim response missing sensor binding');
    }

    await _setActiveBinding(
      DeviceBindingRecordV2.fromConfig(
        DeviceBindingConfigV2(
          deviceId: deviceId,
          firestoreDocPath: firestoreDocPath,
        ),
      ),
    );
    notifyListeners();
    return _config;
  }

  Future<void> applyBinding({
    required String deviceId,
    required String firestoreDocPath,
    String displayName = '',
    String localIp = '',
  }) async {
    if (deviceId.isEmpty || firestoreDocPath.isEmpty) return;
    await _setActiveBinding(
      DeviceBindingRecordV2(
        deviceId: deviceId,
        firestoreDocPath: firestoreDocPath,
        displayName: displayName,
        localIp: localIp,
      ),
    );
    notifyListeners();
  }

  Future<void> selectBinding(String deviceId) async {
    final id = deviceId.trim();
    if (id.isEmpty) return;
    DeviceBindingRecordV2? record;
    for (final entry in _bindings) {
      if (entry.deviceId == id) {
        record = entry;
        break;
      }
    }
    if (record == null) return;
    await _setActiveBinding(record);
    notifyListeners();
  }

  Future<void> removeBinding(String deviceId) async {
    final id = deviceId.trim();
    if (id.isEmpty) return;
    final remaining =
        _bindings.where((record) => record.deviceId != id).toList();
    _bindings = remaining;
    if (_config.deviceId == id) {
      _config = remaining.isEmpty
          ? DeviceBindingConfigV2.empty
          : remaining.first.config;
      await _storage.save(_config);
    }
    await _storage.saveBindings(_bindings);
    notifyListeners();
  }

  Future<void> updateBindingDetails({
    required String deviceId,
    String? displayName,
    String? localIp,
  }) async {
    final id = deviceId.trim();
    if (id.isEmpty) return;
    final now = DateTime.now();
    _bindings = _bindings.map((record) {
      if (record.deviceId != id) return record;
      return record.copyWith(
        displayName: displayName,
        localIp: localIp,
        updatedAt: now,
      );
    }).toList(growable: false);
    await _storage.saveBindings(_bindings);
    notifyListeners();
  }

  Future<void> _setActiveBinding(DeviceBindingRecordV2 record) async {
    final now = DateTime.now();
    DeviceBindingRecordV2? existing;
    for (final binding in _bindings) {
      if (binding.deviceId == record.deviceId) {
        existing = binding;
        break;
      }
    }
    final normalized = record.copyWith(
      displayName: record.displayName.trim().isEmpty
          ? existing?.displayName
          : record.displayName,
      localIp:
          record.localIp.trim().isEmpty ? existing?.localIp : record.localIp,
      registeredAt: record.registeredAt ?? existing?.registeredAt ?? now,
      updatedAt: now,
      lastSelectedAt: now,
    );
    final records = <String, DeviceBindingRecordV2>{
      for (final binding in _bindings) binding.deviceId: binding,
      normalized.deviceId: normalized,
    };
    _bindings = records.values.toList(growable: false);
    _config = normalized.config;
    await _storage.save(_config);
    await _storage.saveBindings(_bindings);
  }
}
