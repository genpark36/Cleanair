import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/air_quality_snapshot.dart';
import '../utils/nodered_health_engine.dart';
import 'external_api_service.dart';

enum FirestoreConnectionState { disconnected, connecting, connected, error }

class FirestoreSnapshotService {
  FirestoreSnapshotService({
    FirebaseFirestore? firestore,
    String? firestoreDocPath,
    bool disabled = false,
  })  : _firestore =
            disabled ? null : (firestore ?? FirebaseFirestore.instance),
        _firestoreDocPath = _normalizeDocPath(firestoreDocPath),
        _externalApi = disabled ? null : ExternalApiService();

  final FirebaseFirestore? _firestore;

  final NodeRedHealthEngine _healthEngine = NodeRedHealthEngine();
  final ExternalApiService? _externalApi;

  final StreamController<AirQualitySnapshot> _snapshotController =
      StreamController<AirQualitySnapshot>.broadcast();
  final StreamController<FirestoreConnectionState> _connectionStateController =
      StreamController<FirestoreConnectionState>.broadcast();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  String? _firestoreDocPath;

  Stream<AirQualitySnapshot> get snapshots => _snapshotController.stream;
  Stream<FirestoreConnectionState> get connectionStates =>
      _connectionStateController.stream;

  String? get firestoreDocPath => _firestoreDocPath;

  void setExternalLocation({
    required double latitude,
    required double longitude,
    String? city,
  }) {
    _externalApi?.setLocation(
      latitude: latitude,
      longitude: longitude,
      city: city,
    );
  }

  static String? _normalizeDocPath(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  static String? _normalizeSensorId(String? sensorId) {
    if (sensorId == null) return null;
    final trimmed = sensorId.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<void> setFirestoreDocPath(String? docPath) async {
    final normalized = _normalizeDocPath(docPath);
    if (normalized == _firestoreDocPath) return;
    _firestoreDocPath = normalized;
    if (_subscription != null) {
      await connect(forceReconnect: true);
    }
  }

  Future<void> setSensorId(String? sensorId) async {
    final normalized = _normalizeSensorId(sensorId);
    await setFirestoreDocPath(
      normalized == null ? null : 'sensors/$normalized',
    );
  }

  Future<void> connect({bool forceReconnect = false}) async {
    if (_subscription != null && !forceReconnect) return;

    await disconnect();

    final path = _firestoreDocPath;
    final firestore = _firestore;
    if (firestore == null) {
      _connectionStateController.add(FirestoreConnectionState.error);
      _snapshotController.addError(
        StateError('Firebase is not configured for this app target.'),
      );
      return;
    }
    if (path == null) {
      _connectionStateController.add(FirestoreConnectionState.error);
      _snapshotController.addError(
        StateError(
            'firestoreDocPath is not set. Example: sensors/ag-one-abc123'),
      );
      return;
    }

    _connectionStateController.add(FirestoreConnectionState.connecting);
    _externalApi?.start();

    _subscription = firestore.doc(path).snapshots().listen(
      (doc) {
        final data = doc.data();
        if (data == null) return;

        final snapshotJson = _toSnapshotJson(doc.id, data);
        final snapshot = AirQualitySnapshot.fromJson(snapshotJson);
        _snapshotController.add(snapshot);
        _connectionStateController.add(FirestoreConnectionState.connected);
      },
      onError: (Object error, StackTrace stackTrace) {
        _connectionStateController.add(FirestoreConnectionState.error);
        _snapshotController.addError(error, stackTrace);
      },
    );
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    _externalApi?.stop();
    _connectionStateController.add(FirestoreConnectionState.disconnected);
  }

  Future<bool> waitForFirstSnapshot({
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final path = _firestoreDocPath;
    final firestore = _firestore;
    if (path == null || firestore == null) return false;

    try {
      final initial = await firestore.doc(path).get().timeout(timeout);
      final initialData = initial.data();
      if (initial.exists && initialData != null) {
        if (initialData['latest'] != null || initialData['lastSeen'] != null) {
          return true;
        }
      }
    } catch (_) {
      // Continue with live stream wait.
    }

    try {
      await firestore.doc(path).snapshots().firstWhere((doc) {
        final data = doc.data();
        return doc.exists &&
            data != null &&
            (data['latest'] != null || data['lastSeen'] != null);
      }).timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> findFirstLiveSensorDocPath(
    Iterable<String> sensorIds, {
    Duration perCandidateTimeout = const Duration(seconds: 2),
  }) async {
    final paths = <String>[];
    for (final sensorId in sensorIds) {
      final id = sensorId.trim();
      if (id.isEmpty) continue;
      final path = id.startsWith('sensors/') ? id : 'sensors/$id';
      if (!paths.contains(path)) paths.add(path);
    }

    for (final path in paths) {
      if (await hasLiveDataAtPath(path, timeout: perCandidateTimeout)) {
        return path;
      }
    }
    return null;
  }

  Future<bool> hasLiveDataAtPath(
    String docPath, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final firestore = _firestore;
    final path = _normalizeDocPath(docPath);
    if (firestore == null || path == null) return false;

    try {
      final doc = await firestore.doc(path).get().timeout(timeout);
      final data = doc.data();
      return doc.exists && data != null && _looksLikeLiveSensorDoc(data);
    } catch (_) {
      return false;
    }
  }

  bool _looksLikeLiveSensorDoc(Map<String, dynamic> data) {
    return data['latest'] != null ||
        data['lastSeen'] != null ||
        data['pm25'] != null ||
        data['co2'] != null ||
        data['serial'] != null;
  }

  Future<List<AirQualitySnapshot>> loadHistory({
    DateTime? since,
    int limit = 8640,
  }) async {
    final path = _firestoreDocPath;
    final firestore = _firestore;
    if (path == null || firestore == null) return const <AirQualitySnapshot>[];

    final historyRef = firestore.collection('$path/history');
    Query<Map<String, dynamic>> query =
        historyRef.orderBy('createdAt', descending: false);

    if (since != null) {
      query = query.where(
        'createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(since),
      );
    }
    query = query.limit(limit);

    try {
      final snap = await query.get();
      return snap.docs
          .map((doc) => _historyDocToSnapshot(doc.id, doc.data()))
          .toList(growable: false);
    } catch (error) {
      // ignore: avoid_print
      print('[firestore] history load failed: $error');
      return const <AirQualitySnapshot>[];
    }
  }

  Future<LocationComparisonSnapshot?> refreshExternalComparison(
    AirQualitySnapshot? current,
  ) async {
    final externalApi = _externalApi;
    if (externalApi == null || current == null) return null;

    await externalApi.refreshNow();
    externalApi.updateComparison(
      sensorPm25: current.pm25,
      sensorTemp: current.temperature,
      sensorHumidity: current.humidity,
    );
    return LocationComparisonSnapshot.tryParse(
      externalApi.latestComparison?.toJson(),
    );
  }

  Future<List<NearbyPm25Station>> loadNearbyPm25Stations({
    required double latitude,
    required double longitude,
    double radiusKm = 8,
  }) async {
    final externalApi = _externalApi;
    if (externalApi == null) return const <NearbyPm25Station>[];
    return externalApi.fetchNearbyPm25Stations(
      latitude: latitude,
      longitude: longitude,
      radiusKm: radiusKm,
    );
  }

  Future<List<NearbyPm25Station>> loadKoreaPm25Stations() async {
    final externalApi = _externalApi;
    if (externalApi == null) return const <NearbyPm25Station>[];
    return externalApi.fetchKoreaPm25Stations();
  }

  Future<List<NearbyWeatherGridPoint>> loadNearbyWeatherGrid({
    required double latitude,
    required double longitude,
    double radiusKm = 90,
  }) async {
    final externalApi = _externalApi;
    if (externalApi == null) return const <NearbyWeatherGridPoint>[];
    return externalApi.fetchNearbyWeatherGrid(
      latitude: latitude,
      longitude: longitude,
      radiusKm: radiusKm,
    );
  }

  AirQualitySnapshot _historyDocToSnapshot(
    String docId,
    Map<String, dynamic> data,
  ) {
    final ts = _parseHistoryTimestamp(data['createdAt'] ?? data['timestamp']);
    final rawMap = _asMap(data['raw']);
    final latest = _asMap(data['latest']);
    final derived = _asMap(data['derived']);
    final health = _asMap(data['health']);
    final pm25 = _toDouble(
      _pickHistoryValue(data, latest, rawMap, 'pm25'),
    );
    final storedIaqiScore =
        _toDouble(_pickHistoryValue(data, latest, rawMap, 'iaqiScore')) ??
            _toDouble(derived?['iaqiScore']) ??
            _toDouble(derived?['display_iaqi']);

    return AirQualitySnapshot.fromJson(<String, dynamic>{
      'id': docId,
      'timestamp': (ts ?? DateTime.now()).toIso8601String(),
      'raw': <String, dynamic>{
        'pm25': pm25,
        'iaqiScore': storedIaqiScore,
        'co2': _pickHistoryValue(data, latest, rawMap, 'co2'),
        'tvoc': _pickHistoryValue(data, latest, rawMap, 'tvoc'),
        'nox': _pickHistoryValue(data, latest, rawMap, 'nox'),
        'co': _pickHistoryValue(data, latest, rawMap, 'co') ??
            _pickHistoryValue(data, latest, rawMap, 'carbon_monoxide') ??
            _pickHistoryValue(data, latest, rawMap, 'carbonMonoxide'),
        'temp': _pickHistoryValue(data, latest, rawMap, 'temp') ??
            _pickHistoryValue(data, latest, rawMap, 'temperature'),
        'humidity': _pickHistoryValue(data, latest, rawMap, 'humidity'),
      },
      if (derived != null)
        'derived': <String, dynamic>{
          ...derived,
          if (storedIaqiScore != null) 'iaqiScore': storedIaqiScore,
        },
      if (health != null) 'health': health,
      if (_asMap(data['locationComparison']) != null)
        'locationComparison': _asMap(data['locationComparison']),
      if (_asMap(data['location_compare']) != null)
        'location_compare': _asMap(data['location_compare']),
    });
  }

  Future<void> dispose() async {
    await disconnect();
    _externalApi?.dispose();
    await _snapshotController.close();
    await _connectionStateController.close();
  }

  Map<String, dynamic> _toSnapshotJson(
    String id,
    Map<String, dynamic> doc,
  ) {
    final latest = _asMap(doc['latest']);

    final raw = <String, dynamic>{
      'pm25': _pick(latest, doc, 'pm25'),
      'iaqiScore': _pick(latest, doc, 'iaqiScore') ??
          _pick(latest, doc, 'display_iaqi') ??
          _pick(latest, doc, 'm_score') ??
          _pick(latest, doc, 'mScore'),
      'co2': _pick(latest, doc, 'co2'),
      'tvoc': _pick(latest, doc, 'tvoc'),
      'nox': _pick(latest, doc, 'nox'),
      'co': _pick(latest, doc, 'co') ??
          _pick(latest, doc, 'carbon_monoxide') ??
          _pick(latest, doc, 'carbonMonoxide'),
      'temp': _pick(latest, doc, 'temp') ?? _pick(latest, doc, 'temperature'),
      'humidity': _pick(latest, doc, 'humidity'),
    };

    final timestamp = _toIsoString(
      latest?['timestamp'] ?? doc['lastSeen'] ?? doc['updatedAt'],
    );

    final pm25 = _toDouble(raw['pm25']);
    final storedIaqiScore = _toDouble(raw['iaqiScore']);
    final co2 = _toDouble(raw['co2']);
    final tvoc = _toDouble(raw['tvoc']);
    final temp = _toDouble(raw['temp']);
    final humidity = _toDouble(raw['humidity']);

    final apiData = _externalApi?.latestApiData;
    if (apiData != null) {
      _healthEngine.setExternalWeather(
        temperature: apiData.temperature,
        humidity: apiData.humidity,
        windSpeed: apiData.windSpeed,
      );
    }

    final computed = _healthEngine.compute(
      pm25: pm25,
      co2: co2,
      tvoc: tvoc,
      temp: temp,
      humidity: humidity,
    );

    final mergedHealth = Map<String, dynamic>.from(computed);
    final mergedDerived = _asMap(computed['derived']) != null
        ? Map<String, dynamic>.from(_asMap(computed['derived'])!)
        : <String, dynamic>{};
    final existingDerived =
        _asMap(latest?['derived']) ?? _asMap(doc['derived']);
    if (existingDerived != null) {
      mergedDerived.addAll(existingDerived);
    }
    final existingDisplayIaqi = _toDouble(mergedDerived['display_iaqi']) ??
        _toDouble(mergedDerived['iaqiScore']);
    final existingMScore = _toDouble(mergedDerived['m_score']) ??
        _toDouble(mergedDerived['mScore']);
    if (storedIaqiScore == null &&
        (existingDisplayIaqi != null || existingMScore != null)) {
      mergedDerived['iaqiScore'] = existingDisplayIaqi ?? existingMScore;
      mergedDerived['aqiLevel'] ??= mergedDerived['primary_grade'];
      mergedDerived['aqiCategory'] ??=
          mergedDerived['sub_level'] ?? mergedDerived['primary_grade'];
    }
    if (storedIaqiScore != null) {
      mergedDerived['iaqiScore'] = storedIaqiScore;
      mergedDerived['aqiLevel'] ??= mergedDerived['primary_grade'];
      mergedDerived['aqiCategory'] ??=
          mergedDerived['sub_level'] ?? mergedDerived['primary_grade'];
    }
    if (mergedDerived.isNotEmpty) {
      mergedHealth['derived'] = mergedDerived;
    }

    final existingHealth = _asMap(latest?['health']) ?? _asMap(doc['health']);
    if (existingHealth != null) {
      for (final entry in existingHealth.entries) {
        mergedHealth.putIfAbsent(entry.key, () => entry.value);
      }
    }

    _externalApi?.updateComparison(
      sensorPm25: pm25,
      sensorTemp: temp,
      sensorHumidity: humidity,
    );
    final existingComparison = _asMap(latest?['locationComparison']) ??
        _asMap(latest?['location_compare']) ??
        _asMap(doc['locationComparison']) ??
        _asMap(doc['location_compare']);
    final comparisonJson =
        _externalApi?.latestComparison?.toJson() ?? existingComparison;

    return <String, dynamic>{
      'id': id,
      'timestamp': timestamp,
      'raw': raw,
      ...mergedHealth,
      'health': mergedHealth,
      if (comparisonJson != null) 'locationComparison': comparisonJson,
      'meta': <String, dynamic>{
        'serialno': doc['serial']?.toString() ?? id,
      },
    };
  }

  static double? _toDouble(dynamic value) {
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null && parsed.isFinite) return parsed;
    }
    return null;
  }

  DateTime? _parseHistoryTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  dynamic _pickHistoryValue(
    Map<String, dynamic> doc,
    Map<String, dynamic>? latest,
    Map<String, dynamic>? raw,
    String key,
  ) {
    if (raw != null && raw.containsKey(key)) return raw[key];
    if (latest != null && latest.containsKey(key)) return latest[key];
    return doc[key];
  }

  dynamic _pick(
      Map<String, dynamic>? latest, Map<String, dynamic> doc, String key) {
    if (latest != null && latest.containsKey(key)) {
      return latest[key];
    }
    return doc[key];
  }

  String _toIsoString(dynamic value) {
    if (value == null) {
      return DateTime.now().toIso8601String();
    }
    if (value is String) {
      return value;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value).toIso8601String();
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    }

    final dynamic maybeDate = _tryToDate(value);
    if (maybeDate is DateTime) {
      return maybeDate.toIso8601String();
    }

    return DateTime.now().toIso8601String();
  }

  dynamic _tryToDate(dynamic value) {
    try {
      return (value as dynamic).toDate();
    } catch (_) {
      return null;
    }
  }
}
