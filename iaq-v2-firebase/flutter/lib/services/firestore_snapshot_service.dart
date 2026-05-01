import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/air_quality_snapshot.dart';

enum FirestoreConnectionState { disconnected, connecting, connected, error }

class FirestoreSnapshotService {
  FirestoreSnapshotService({
    FirebaseFirestore? firestore,
    String? firestoreDocPath,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _firestoreDocPath = _normalizeDocPath(firestoreDocPath);

  final FirebaseFirestore _firestore;

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
    if (path == null) {
      _connectionStateController.add(FirestoreConnectionState.error);
      _snapshotController.addError(
        StateError('firestoreDocPath is not set. Example: sensors/ag-one-abc123'),
      );
      return;
    }

    _connectionStateController.add(FirestoreConnectionState.connecting);

    _subscription = _firestore.doc(path).snapshots().listen(
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
    _connectionStateController.add(FirestoreConnectionState.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
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
      'co2': _pick(latest, doc, 'co2'),
      'tvoc': _pick(latest, doc, 'tvoc'),
      'nox': _pick(latest, doc, 'nox'),
      'temp': _pick(latest, doc, 'temp'),
      'humidity': _pick(latest, doc, 'humidity'),
    };

    final timestamp = _toIsoString(
      latest?['timestamp'] ?? doc['lastSeen'] ?? doc['updatedAt'],
    );

    return <String, dynamic>{
      'id': id,
      'timestamp': timestamp,
      'raw': raw,
      'meta': <String, dynamic>{
        'serialno': doc['serial']?.toString() ?? id,
      },
    };
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  dynamic _pick(Map<String, dynamic>? latest, Map<String, dynamic> doc, String key) {
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
