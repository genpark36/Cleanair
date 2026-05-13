import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Local OS notification presenter restored from the legacy Cleanair pipeline.
///
/// This stays UI-independent so the remake/Stitch screens can use the same
/// alert and CSV completion channels without pulling legacy widgets back in.
class AlertNotificationPresenter {
  static const String channelId = 'iaq_alerts';
  static const String channelName = '실내 공기질 알림';
  static const String channelDescription = '우선순위 공기질 경보를 표시합니다';
  static const String downloadChannelId = 'iaq_downloads';
  static const String downloadChannelName = 'CSV 다운로드';
  static const String downloadChannelDescription = 'CSV 다운로드 완료 알림을 표시합니다';
  static const String emergencyChannelId = 'iaq_emergency_alerts';
  static const String emergencyChannelName = '긴급 방재 알림';
  static const String emergencyChannelDescription =
      '화재 의심 또는 CO 위험 상황을 강하게 알립니다';
  static const String openFilePayloadPrefix = 'open_file:';
  static const String _androidIcon = '@drawable/ic_stat_cleanair';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static Future<void> Function(String payload)? _payloadHandler;

  static FlutterLocalNotificationsPlugin get plugin => _plugin;

  static void setPayloadHandler(
      Future<void> Function(String payload)? handler) {
    _payloadHandler = handler;
  }

  static Future<void> ensureInitialized() async {
    if (_initialized || kIsWeb) return;

    const androidInit = AndroidInitializationSettings(_androidIcon);
    const darwinInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        final handler = _payloadHandler;
        if (payload == null || payload.isEmpty || handler == null) {
          return;
        }
        unawaited(handler(payload));
      },
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        importance: Importance.high,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        downloadChannelId,
        downloadChannelName,
        description: downloadChannelDescription,
        importance: Importance.defaultImportance,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        emergencyChannelId,
        emergencyChannelName,
        description: emergencyChannelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    await _requestNotificationPermission();
    _initialized = true;
  }

  static Future<void> showAlert(
    String title,
    String body, {
    String? payload,
  }) async {
    if (kIsWeb) return;
    await ensureInitialized();

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        icon: _androidIcon,
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
    );

    await _plugin.show(
      DateTime.now().microsecondsSinceEpoch & 0x7fffffff,
      title,
      body,
      details,
      payload: payload,
    );
  }

  static Future<void> showEmergencyAlert(
    String title,
    String body, {
    String? payload,
  }) async {
    if (kIsWeb) return;
    await ensureInitialized();

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        emergencyChannelId,
        emergencyChannelName,
        channelDescription: emergencyChannelDescription,
        importance: Importance.max,
        priority: Priority.max,
        icon: _androidIcon,
        playSound: true,
        enableVibration: true,
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: const DarwinNotificationDetails(
        presentSound: true,
        presentAlert: true,
        presentBadge: true,
      ),
      macOS: const DarwinNotificationDetails(
        presentSound: true,
        presentAlert: true,
        presentBadge: true,
      ),
    );

    await _plugin.show(
      DateTime.now().microsecondsSinceEpoch & 0x7fffffff,
      title,
      body,
      details,
      payload: payload,
    );
  }

  static Future<void> showDownloadCompleted({
    required String filePath,
    required String fileName,
  }) async {
    if (kIsWeb) return;
    await ensureInitialized();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        downloadChannelId,
        downloadChannelName,
        channelDescription: downloadChannelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: _androidIcon,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );

    await _plugin.show(
      DateTime.now().microsecondsSinceEpoch & 0x7fffffff,
      'CSV 다운로드 완료',
      filePath.startsWith('Download/')
          ? filePath
          : 'Download/AirGradient/$fileName',
      details,
      payload: '$openFilePayloadPrefix$filePath',
    );
  }

  static Future<void> _requestNotificationPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final status = await Permission.notification.status;
      if (kDebugMode) {
        // ignore: avoid_print
        print('[push] notification permission status: ${status.name}');
      }
      if (!status.isGranted) {
        await Permission.notification.request();
      }
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }
}
