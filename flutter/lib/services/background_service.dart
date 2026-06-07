import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/air_quality_snapshot.dart';
import 'home_screen_widget_service.dart';
import 'local_snapshot_store.dart';

class BackgroundServiceManager {
  BackgroundServiceManager._();

  static final BackgroundServiceManager instance = BackgroundServiceManager._();

  final FlutterBackgroundService _service = FlutterBackgroundService();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb || !Platform.isAndroid) return;

    await _createNotificationChannel();
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onBackgroundServiceStart,
        autoStart: false,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: _BackgroundPrefs.channelId,
        initialNotificationTitle: 'Cleanair 모니터링',
        initialNotificationContent: '센서 데이터를 확인하는 중입니다.',
        foregroundServiceNotificationId: _BackgroundPrefs.notificationId,
        foregroundServiceTypes: const [AndroidForegroundType.dataSync],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onBackgroundServiceStart,
        onBackground: _onIosBackground,
      ),
    );

    _initialized = true;
  }

  Future<bool> start() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    await initialize();
    await setEnabled(true);
    final running = await _service.isRunning();
    if (running) return true;
    return _service.startService();
  }

  Future<void> stop({bool disable = true}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (disable) await setEnabled(false);
    _service.invoke('stopService');
  }

  Future<bool> isRunning() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    await initialize();
    return _service.isRunning();
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_BackgroundPrefs.enabledKey) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_BackgroundPrefs.enabledKey, enabled);
  }

  Future<void> refreshBinding() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await initialize();
    _service.invoke('refreshBinding');
  }

  Future<bool> requestBatteryOptimizationExemption() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (status.isGranted) return true;
    final result = await Permission.ignoreBatteryOptimizations.request();
    return result.isGranted;
  }

  Future<bool> isBatteryOptimizationDisabled() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    return Permission.ignoreBatteryOptimizations.isGranted;
  }

  Future<void> enableWakeLock() => WakelockPlus.enable();

  Future<void> disableWakeLock() => WakelockPlus.disable();

  Future<bool> isWakeLockEnabled() => WakelockPlus.enabled;

  Future<void> _createNotificationChannel() async {
    final plugin = FlutterLocalNotificationsPlugin();
    const channel = AndroidNotificationChannel(
      _BackgroundPrefs.channelId,
      '공기질 백그라운드 모니터링',
      description: '앱이 닫혀 있어도 센서 값을 받아와 최근 기록을 유지합니다.',
      importance: Importance.low,
    );
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void _onBackgroundServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final runner = _BackgroundFirestoreRunner();
  await runner.start(service);

  service.on('refreshBinding').listen((_) {
    unawaited(runner.connect());
  });

  service.on('stopService').listen((_) async {
    await runner.stop();
    service.stopSelf();
  });

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((_) {
      service.setAsBackgroundService();
    });
  }
}

class _BackgroundFirestoreRunner {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  Timer? _statusTimer;
  final _store = LocalSnapshotStore();
  ServiceInstance? _service;
  AirQualitySnapshot? _lastSnapshot;

  Future<void> start(ServiceInstance service) async {
    _service = service;
    await _ensureFirebaseInitialized();
    await connect();
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _updateForegroundNotification();
    });
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  Future<void> connect() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_BackgroundPrefs.enabledKey) ?? true;
    final path = prefs.getString(_BackgroundPrefs.firestoreDocPathKey);
    await _subscription?.cancel();
    _subscription = null;

    if (!enabled || path == null || path.trim().isEmpty) {
      _updateForegroundNotification('연결된 센서가 없습니다.');
      return;
    }

    _updateForegroundNotification('센서 데이터를 기다리는 중입니다.');
    _subscription =
        FirebaseFirestore.instance.doc(path.trim()).snapshots().listen(
      (doc) async {
        final data = doc.data();
        if (data == null) return;
        final snapshot = _snapshotFromDocument(doc.id, data);
        _lastSnapshot = snapshot;
        await _store.appendSnapshot(snapshot);
        final recent = await _store.loadRecent();
        unawaited(
          HomeScreenWidgetService.update(
            latest: snapshot,
            history: recent.map((entry) => entry.toSnapshot()).toList(),
          ),
        );
        _updateForegroundNotification();
      },
      onError: (_) {
        _updateForegroundNotification('센서 데이터 수신을 다시 시도하는 중입니다.');
      },
    );
  }

  Future<void> _ensureFirebaseInitialized() async {
    if (Firebase.apps.isNotEmpty) return;
    await Firebase.initializeApp();
  }

  AirQualitySnapshot _snapshotFromDocument(
    String id,
    Map<String, dynamic> data,
  ) {
    final latest = _asMap(data['latest']);
    final raw = _asMap(data['raw']);
    final derived = _asMap(data['derived']);
    final health = _asMap(data['health']);
    final timestamp = _timestampToIso(
      data['timestamp'] ??
          data['createdAt'] ??
          data['updatedAt'] ??
          latest?['timestamp'],
    );

    return AirQualitySnapshot.fromJson(<String, dynamic>{
      'id': id,
      'timestamp': timestamp,
      'raw': <String, dynamic>{
        'pm25': _pick(data, latest, raw, 'pm25'),
        'co2': _pick(data, latest, raw, 'co2'),
        'tvoc': _pick(data, latest, raw, 'tvoc'),
        'nox': _pick(data, latest, raw, 'nox'),
        'co': _pick(data, latest, raw, 'co') ??
            _pick(data, latest, raw, 'co_ppm') ??
            _pick(data, latest, raw, 'carbonMonoxide'),
        'temp': _pick(data, latest, raw, 'temp') ??
            _pick(data, latest, raw, 'temperature'),
        'humidity': _pick(data, latest, raw, 'humidity'),
        'iaqiScore': _pick(data, latest, raw, 'iaqiScore'),
      },
      if (derived != null) 'derived': derived,
      if (health != null) 'health': health,
      if (_asMap(data['location']) != null)
        'location': _asMap(data['location']),
      if (_asMap(data['alerts']) != null) 'alerts': _asMap(data['alerts']),
    });
  }

  void _updateForegroundNotification([String? fallback]) {
    final service = _service;
    if (service is! AndroidServiceInstance) return;
    final snapshot = _lastSnapshot;
    final content = snapshot == null
        ? fallback ?? '센서 데이터를 확인하는 중입니다.'
        : [
            if (snapshot.pm25 != null)
              'PM2.5 ${snapshot.pm25!.toStringAsFixed(0)}',
            if (snapshot.co2 != null) 'CO₂ ${snapshot.co2!.toStringAsFixed(0)}',
            if (snapshot.tvoc != null)
              'TVOC ${snapshot.tvoc!.toStringAsFixed(0)}',
            _clockLabel(DateTime.now()),
          ].join(' · ');
    service.setForegroundNotificationInfo(
      title: 'Cleanair 모니터링',
      content: content.isEmpty ? '센서 데이터를 수신 중입니다.' : content,
    );
  }
}

class _BackgroundPrefs {
  static const enabledKey = 'background_monitoring_enabled';
  static const firestoreDocPathKey = 'device_binding_v2_firestore_doc_path';
  static const channelId = 'cleanair_background_monitoring';
  static const notificationId = 888;
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return null;
}

Object? _pick(
  Map<String, dynamic> root,
  Map<String, dynamic>? latest,
  Map<String, dynamic>? raw,
  String key,
) {
  return latest?[key] ?? raw?[key] ?? root[key];
}

String _timestampToIso(Object? value) {
  if (value is Timestamp) return value.toDate().toIso8601String();
  if (value is DateTime) return value.toIso8601String();
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return (parsed ?? DateTime.now()).toIso8601String();
}

String _clockLabel(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
