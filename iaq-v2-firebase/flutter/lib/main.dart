import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import './screens/home_page.dart';
import './services/alert_notification_service.dart';
import './services/device_binding_service_v2.dart';
import './services/firestore_snapshot_service.dart';
import './services/local_snapshot_store.dart';
import './services/notification_preferences.dart';
import './services/push_notification_service_v2.dart';
import './state/air_quality_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  final notificationPrefs =
      NotificationPreferencesController(NotificationPreferencesStorage());
  await notificationPrefs.load();
  final deviceBinding =
      DeviceBindingControllerV2(DeviceBindingStorageV2());
  await deviceBinding.load();
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
  await pushService.initialize();

  // 바인딩이 이미 되어 있으면 Firestore 문서 경로 설정
  if (deviceBinding.value.isBound) {
    await firestoreService.setFirestoreDocPath(
      deviceBinding.value.firestoreDocPath,
    );
    await pushService.updateSensorId(deviceBinding.value.deviceId);
  }

  try {
    // ignore: avoid_print
    print('[startup] created Firestore snapshot service');
  } catch (_) {}

  runApp(
    MultiProvider(
      providers: [
        Provider<FirestoreSnapshotService>.value(value: firestoreService),
        ChangeNotifierProvider(
          create: (_) => AirQualityController(
            firestoreService,
            snapshotStore,
          )..initialize(),
        ),
        ChangeNotifierProvider<NotificationPreferencesController>.value(
          value: notificationPrefs,
        ),
        ChangeNotifierProvider<DeviceBindingControllerV2>.value(
          value: deviceBinding,
        ),
        Provider<AlertNotificationService>.value(value: alertService),
        Provider<PushNotificationServiceV2>.value(value: pushService),
      ],
      child: const IndoorAirQualityApp(),
    ),
  );
}

class IndoorAirQualityApp extends StatelessWidget {
  const IndoorAirQualityApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: '실내 공기질',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        textTheme: GoogleFonts.notoSansKrTextTheme(baseTheme.textTheme),
      ),
      home: const HomePage(),
    );
  }
}
