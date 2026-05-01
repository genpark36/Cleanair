import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/air_quality_snapshot.dart';
import '../services/firestore_snapshot_service.dart';
import '../services/local_snapshot_store.dart';
import '../utils/mock_data.dart';

enum LiveDataStatus { disconnected, connecting, connected, error }

class AirQualityController extends ChangeNotifier {
  AirQualityController(
    this._service,
    this._store,
  );

  static const Duration _historyWindow = Duration(days: 7);
  static const int _maxHistoryEntries = 120960; // 7일 @5초 간격

  final FirestoreSnapshotService _service;
  final LocalSnapshotStore _store;

  StreamSubscription<AirQualitySnapshot>? _snapshotSubscription;
  StreamSubscription<FirestoreConnectionState>? _connectionSubscription;

  AirQualitySnapshot? _latestSnapshot;
  final List<AirQualitySnapshot> _history = <AirQualitySnapshot>[];
  LiveDataStatus _status = LiveDataStatus.disconnected;
  String? _lastError;
  bool _initialized = false;

  AirQualitySnapshot? get latestSnapshot => _latestSnapshot;
  List<AirQualitySnapshot> get rawHistory => List.unmodifiable(_history);
  LiveDataStatus get status => _status;
  String? get lastError => _lastError;

  DateTime? get lastUpdated => _latestSnapshot?.timestamp;
  Duration? get timeSinceLastSnapshot {
    final ts = _latestSnapshot?.timestamp;
    if (ts == null) return null;
    return DateTime.now().difference(ts);
  }

  bool get isDataStale {
    final delta = timeSinceLastSnapshot;
    if (delta == null) return true;
    return delta.inSeconds > 15;
  }

  ChildHealthSnapshot? get childSnapshot => _latestSnapshot?.child;
  SeniorHealthSnapshot? get seniorSnapshot => _latestSnapshot?.senior;
  PurificationSummary? get purificationSnapshot => _latestSnapshot?.purification;
  PurifierSnapshot? get purifierSnapshot => _latestSnapshot?.purifier;
  PurificationCadrSnapshot? get purificationCadrSnapshot =>
      _latestSnapshot?.purification?.cadr;
  IpiSnapshot? get ipiSnapshot =>
      _latestSnapshot?.ipi ?? _latestSnapshot?.purification?.ipi;
  LocationComparisonSnapshot? get locationComparison =>
      _latestSnapshot?.locationComparison;
  SnapshotAlerts? get alertSnapshot => _latestSnapshot?.alerts;
  SnapshotLocation? get locationSnapshot => _latestSnapshot?.location;
  SnapshotMeta? get metaSnapshot => _latestSnapshot?.meta;

  bool get isConnected => _status == LiveDataStatus.connected;
  bool get isConnecting => _status == LiveDataStatus.connecting;

  AirQualityData? get currentData =>
      airQualityDataFromSnapshot(_latestSnapshot);

  List<AirQualityData> get historyData {
    return airQualityDataFromSnapshots(_history);
  }

  Future<void> initialize() async {
    try {
      // ignore: avoid_print
      print('[debug] AirQualityController.initialize() called');
    } catch (_) {}
    if (_initialized) return;
    _initialized = true;
    await _loadPersistedSnapshots();
    _snapshotSubscription ??=
        _service.snapshots.listen(_handleSnapshot, onError: _handleError);
    _connectionSubscription ??=
        _service.connectionStates.listen(_handleConnectionState);
    await _connectInternal();
  }

  Future<void> _loadPersistedSnapshots() async {
    try {
      final samples = await _store.loadRecent();
      if (samples.isEmpty) return;
      _history
        ..clear()
        ..addAll(samples.map((sample) => sample.toSnapshot()));
      _latestSnapshot = _history.isNotEmpty ? _history.last : null;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> retryConnection() async {
    await _connectInternal(force: true);
  }

  Future<void> _connectInternal({bool force = false}) async {
    if (!force && (_status == LiveDataStatus.connecting)) {
      return;
    }
    _status = LiveDataStatus.connecting;
    _lastError = null;
    notifyListeners();
    try {
      await _service.connect();
    } catch (error) {
      _lastError = error.toString();
      _status = LiveDataStatus.error;
      notifyListeners();
    }
  }

  void _handleSnapshot(AirQualitySnapshot snapshot) {
    try {
      // ignore: avoid_print
      final childState = snapshot.child != null ? 'child=yes' : 'child=no';
      final seniorState = snapshot.senior != null ? 'senior=yes' : 'senior=no';
      final purifyState =
          (snapshot.purification != null || snapshot.purifier != null)
              ? 'purify=yes'
              : 'purify=no';
      print(
        '[debug] AirQualityController snapshot @${snapshot.timestamp.toIso8601String()} ($childState, $seniorState, $purifyState)',
      );
    } catch (_) {}

    // 중복 데이터 방지: 같은 타임스탬프가 이미 있으면 무시
    final snapshotMs = snapshot.timestamp.millisecondsSinceEpoch;
    final isDuplicate = _history.any(
      (h) => h.timestamp.millisecondsSinceEpoch == snapshotMs,
    );
    if (isDuplicate) {
      // ignore: avoid_print
      try {
        print('[debug] Duplicate snapshot ignored: ${snapshot.timestamp}');
      } catch (_) {}
      return;
    }

    _latestSnapshot = snapshot;
    _history.add(snapshot);
    unawaited(_store.appendSnapshot(snapshot));

    final cutoff = DateTime.now().subtract(_historyWindow);
    _history.removeWhere((entry) => entry.timestamp.isBefore(cutoff));
    if (_history.length > _maxHistoryEntries) {
      _history.removeRange(0, _history.length - _maxHistoryEntries);
    }
    notifyListeners();
  }

  void _handleConnectionState(FirestoreConnectionState state) {
    switch (state) {
      case FirestoreConnectionState.connected:
        _status = LiveDataStatus.connected;
        _lastError = null;
        try {
          // ignore: avoid_print
          print('[debug] AirQualityController connected to Firestore');
        } catch (_) {}
        break;
      case FirestoreConnectionState.connecting:
        _status = LiveDataStatus.connecting;
        break;
      case FirestoreConnectionState.disconnected:
        _status = LiveDataStatus.disconnected;
        try {
          // ignore: avoid_print
          print('[debug] AirQualityController disconnected from Firestore');
        } catch (_) {}
        break;
      default:
        _status = LiveDataStatus.error;
        break;
    }
    notifyListeners();
  }

  void _handleError(Object error, StackTrace stackTrace) {
    _lastError = error.toString();
    _status = LiveDataStatus.error;
    try {
      // ignore: avoid_print
      print('[error] AirQualityController stream error: $error');
    } catch (_) {}
    notifyListeners();
  }

  @override
  void dispose() {
    _snapshotSubscription?.cancel();
    _connectionSubscription?.cancel();
    unawaited(_service.dispose());
    super.dispose();
  }
}
