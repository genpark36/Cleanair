import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';

import './services/alert_notification_presenter.dart';
import './services/alert_notification_service.dart';
import './services/background_service.dart';
import './services/device_binding_service_v2.dart';
import './services/firestore_snapshot_service.dart';
import './services/local_snapshot_store.dart';
import './services/notification_preferences.dart';
import './services/push_notification_service_v2.dart';
import './state/air_quality_controller.dart';
import './ui/stitch_export_app.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await AlertNotificationPresenter.ensureInitialized();
  if (message.notification != null) {
    return;
  }

  final data = message.data;
  final title = data['title']?.toString().trim().isNotEmpty == true
      ? data['title'].toString()
      : '공기질 알림';
  final body = data['body']?.toString().trim().isNotEmpty == true
      ? data['body'].toString()
      : [
          data['type']?.toString(),
          data['severity']?.toString(),
          data['sensorId']?.toString(),
        ].where((value) => value != null && value.isNotEmpty).join(' · ');
  await AlertNotificationPresenter.showAlert(
    title,
    body.isEmpty ? '현재 공기질 상태를 확인해 주세요.' : body,
    payload: jsonEncode({
      if (data['type'] != null) 'type': data['type'].toString(),
      if (data['severity'] != null) 'severity': data['severity'].toString(),
      if (data['sensorId'] != null) 'sensorId': data['sensorId'].toString(),
      if (data['eventId'] != null) 'eventId': data['eventId'].toString(),
    }),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
    const [DeviceOrientation.portraitUp],
  );
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  try {
    // ignore: avoid_print
    print('[startup] main() - Widgets initialized, about to create providers');
  } catch (_) {}

  // 상태바를 투명하게 설정
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  final firestoreService = FirestoreSnapshotService();
  final snapshotStore = LocalSnapshotStore();
  final airQualityController =
      AirQualityController(firestoreService, snapshotStore);
  final notificationPrefs = NotificationPreferencesController(
    NotificationPreferencesStorage(),
  );
  await notificationPrefs.load();
  final deviceBinding = DeviceBindingControllerV2(DeviceBindingStorageV2());
  await deviceBinding.load();
  final backgroundService = BackgroundServiceManager.instance;
  try {
    await backgroundService.initialize();
  } catch (error) {
    // ignore: avoid_print
    print('[startup] Background service initialize skipped or failed: $error');
  }
  final alertService = AlertNotificationService(
    snapshotService: firestoreService,
    preferences: notificationPrefs,
  );
  await alertService.initialize();
  final pushService = PushNotificationServiceV2(
    onTokenRefreshed: (token) {
      try {
        // ignore: avoid_print
        print('[push] FCM token: $token');
      } catch (_) {}
    },
  );
  try {
    await pushService.initialize();
  } catch (error) {
    // ignore: avoid_print
    print('[startup] Push initialize skipped or failed: $error');
  }
  notificationPrefs.addListener(() {
    unawaited(pushService.syncNotificationPreferences(notificationPrefs.value));
  });
  deviceBinding.addListener(() {
    final binding = deviceBinding.value;
    unawaited(pushService.updateSensorId(binding.deviceId));
    unawaited(
      _applyDeviceBindingToLivePipeline(
        binding: binding,
        firestoreService: firestoreService,
        airQualityController: airQualityController,
      ),
    );
    unawaited(
      _syncBackgroundMonitoring(
        binding: binding,
        backgroundService: backgroundService,
      ),
    );
  });
  unawaited(pushService.syncNotificationPreferences(notificationPrefs.value));

  // 바인딩이 이미 되어 있으면 Firestore 문서 경로 설정
  if (deviceBinding.value.isBound) {
    await firestoreService.setFirestoreDocPath(
      deviceBinding.value.firestoreDocPath,
    );
    await pushService.updateSensorId(deviceBinding.value.deviceId);
    await _syncBackgroundMonitoring(
      binding: deviceBinding.value,
      backgroundService: backgroundService,
    );
  }

  try {
    // ignore: avoid_print
    print('[startup] created Firestore snapshot service');
  } catch (_) {}

  runApp(
    MultiProvider(
      providers: [
        Provider<FirestoreSnapshotService>.value(value: firestoreService),
        ChangeNotifierProvider<AirQualityController>.value(
          value: airQualityController..initialize(),
        ),
        ChangeNotifierProvider<NotificationPreferencesController>.value(
          value: notificationPrefs,
        ),
        ChangeNotifierProvider<DeviceBindingControllerV2>.value(
          value: deviceBinding,
        ),
        Provider<AlertNotificationService>.value(value: alertService),
        Provider<PushNotificationServiceV2>.value(value: pushService),
        Provider<BackgroundServiceManager>.value(value: backgroundService),
      ],
      child: const StitchExportApp(),
    ),
  );
}

Future<void> _syncBackgroundMonitoring({
  required DeviceBindingConfigV2 binding,
  required BackgroundServiceManager backgroundService,
}) async {
  if (!binding.isBound) {
    await backgroundService.stop(disable: false);
    return;
  }
  final enabled = await backgroundService.isEnabled();
  if (!enabled) {
    await backgroundService.refreshBinding();
    return;
  }
  await backgroundService.start();
  await backgroundService.refreshBinding();
}

Future<void> _applyDeviceBindingToLivePipeline({
  required DeviceBindingConfigV2 binding,
  required FirestoreSnapshotService firestoreService,
  required AirQualityController airQualityController,
}) async {
  if (!binding.isBound) {
    await firestoreService.setFirestoreDocPath(null);
    await firestoreService.disconnect();
    await airQualityController.clearLocalSnapshots();
    return;
  }

  await airQualityController.clearLocalSnapshots();
  await firestoreService.setFirestoreDocPath(binding.firestoreDocPath);
  await firestoreService.connect(forceReconnect: true);
  await airQualityController.refreshHistoryFromFirestore();
}
