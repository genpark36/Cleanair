import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'alert_notification_presenter.dart';
import 'notification_preferences.dart';

class PushNotificationOpenIntent {
  const PushNotificationOpenIntent({
    this.type,
    this.severity,
    this.sensorId,
    this.eventId,
  });

  final String? type;
  final String? severity;
  final String? sensorId;
  final String? eventId;

  bool get hasAlertType => type != null && type!.trim().isNotEmpty;

  static PushNotificationOpenIntent fromMap(Map<String, Object?> data) {
    String? clean(String key) {
      final value = data[key]?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }

    return PushNotificationOpenIntent(
      type: clean('type'),
      severity: clean('severity'),
      sensorId: clean('sensorId'),
      eventId: clean('eventId'),
    );
  }

  Map<String, Object?> toJson() => {
        if (type != null) 'type': type,
        if (severity != null) 'severity': severity,
        if (sensorId != null) 'sensorId': sensorId,
        if (eventId != null) 'eventId': eventId,
      };
}

class PushNotificationServiceV2 {
  PushNotificationServiceV2({
    this.onTokenRefreshed,
  });

  final ValueChanged<String>? onTokenRefreshed;

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
  static const String _clientTokenPrefsKey = 'device_binding_v2_client_token';

  FirebaseMessaging? _messaging;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  final StreamController<PushNotificationOpenIntent> _openedController =
      StreamController<PushNotificationOpenIntent>.broadcast();
  PushNotificationOpenIntent? _pendingOpenIntent;
  String? _currentToken;
  String? _clientToken;
  bool _initialized = false;
  String? _sensorId;
  String? _lastRegistrationMessage;
  DateTime? _lastRegistrationAt;
  AuthorizationStatus? _authorizationStatus;

  String get _baseUrl {
    if (_functionsBaseUrl.trim().isNotEmpty) return _functionsBaseUrl.trim();
    return _fallbackBaseUrl.trim();
  }

  String? get currentToken => _currentToken;
  String? get clientToken => _clientToken;
  String? get lastRegistrationMessage => _lastRegistrationMessage;
  DateTime? get lastRegistrationAt => _lastRegistrationAt;
  AuthorizationStatus? get authorizationStatus => _authorizationStatus;
  Stream<PushNotificationOpenIntent> get openedMessages =>
      _openedController.stream;

  PushNotificationOpenIntent? consumePendingOpenIntent() {
    final intent = _pendingOpenIntent;
    _pendingOpenIntent = null;
    return intent;
  }

  Future<String> ensureClientToken() async {
    if (_clientToken != null && _clientToken!.trim().isNotEmpty) {
      return _clientToken!;
    }

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_clientTokenPrefsKey)?.trim();
    if (existing != null && existing.isNotEmpty) {
      _clientToken = existing;
      return existing;
    }

    final preferred = _currentToken?.trim();
    if (preferred != null && preferred.isNotEmpty) {
      await prefs.setString(_clientTokenPrefsKey, preferred);
      _clientToken = preferred;
      return preferred;
    }

    final randomPart =
        Random().nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
    final generated =
        'local-client-${DateTime.now().millisecondsSinceEpoch}-$randomPart';
    await prefs.setString(_clientTokenPrefsKey, generated);
    _clientToken = generated;
    return generated;
  }

  Map<String, String> _headers() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_deviceApiKey.isNotEmpty) {
      headers['X-API-Key'] = _deviceApiKey;
    }
    return headers;
  }

  Future<void> initialize() async {
    if (_initialized) return;

    await ensureClientToken();
    if (kIsWeb) {
      _initialized = true;
      return;
    }

    await _ensureFirebaseInitialized();
    _messaging = FirebaseMessaging.instance;

    await _messaging!.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _installMessageListeners();
    AlertNotificationPresenter.setPayloadHandler(_handleLocalPayload);

    final token = await _messaging!.getToken();
    if (token != null) {
      await _handleToken(token);
    } else {
      await _syncRegistration();
    }

    final initialMessage = await _messaging!.getInitialMessage();
    if (initialMessage != null) {
      _handleOpenedMessage(initialMessage);
    }

    _initialized = true;
  }

  Future<void> requestNotificationPermissionAndRefresh() async {
    if (kIsWeb) return;
    await _ensureFirebaseInitialized();
    _messaging ??= FirebaseMessaging.instance;
    final settings = await _messaging!.requestPermission();
    _authorizationStatus = settings.authorizationStatus;
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      await _syncRegistration();
      return;
    }
    await _messaging!.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    _installMessageListeners();
    AlertNotificationPresenter.setPayloadHandler(_handleLocalPayload);
    final token = await _messaging!.getToken();
    if (token != null) {
      await _handleToken(token);
    } else {
      await _syncRegistration();
    }
  }

  Future<void> updateSensorId(String? sensorId) async {
    _sensorId = sensorId?.trim().isEmpty ?? true ? null : sensorId!.trim();
    await _syncRegistration();
  }

  Future<void> _handleToken(String token) async {
    _currentToken = token;
    onTokenRefreshed?.call(token);
    await _syncRegistration();
  }

  Future<bool> _syncRegistration() async {
    final clientToken = await ensureClientToken();
    return _registerToken(clientToken, fcmToken: _currentToken);
  }

  Future<bool> _registerToken(String token, {String? fcmToken}) async {
    if (_baseUrl.isEmpty) {
      _lastRegistrationMessage = 'Functions URL이 없어 기기 등록을 건너뜁니다.';
      _lastRegistrationAt = DateTime.now();
      return false;
    }

    final trimmedFcmToken = fcmToken?.trim();
    final resolvedFcmToken =
        (trimmedFcmToken == null || trimmedFcmToken.isEmpty)
            ? null
            : trimmedFcmToken;

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/registerDevice'),
        headers: _headers(),
        body: jsonEncode({
          'token': token,
          'fcmToken': resolvedFcmToken,
          'sensorId': _sensorId,
          'platform': kIsWeb ? 'web' : 'mobile',
        }),
      );

      if (kDebugMode) {
        // ignore: avoid_print
        print(
            '[push-v2] register status=${response.statusCode} body=${response.body}');
      }
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      _lastRegistrationAt = DateTime.now();
      _lastRegistrationMessage =
          ok ? '기기 토큰 등록 완료' : '기기 토큰 등록 실패 (${response.statusCode})';
      return ok;
    } catch (error) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[push-v2] register failed: $error');
      }
      _lastRegistrationAt = DateTime.now();
      _lastRegistrationMessage = '기기 토큰 등록 실패: $error';
      return false;
    }
  }

  Future<Map<String, Object?>?> fetchServerDevicePreferences() async {
    if (_baseUrl.isEmpty) {
      _lastRegistrationMessage = 'Functions URL이 없어 서버 설정을 확인할 수 없습니다.';
      _lastRegistrationAt = DateTime.now();
      return null;
    }

    final token = await ensureClientToken();
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/getDevicePreferences'),
        headers: _headers(),
        body: jsonEncode({'token': token}),
      );
      final decoded = jsonDecode(response.body);
      final ok = response.statusCode >= 200 &&
          response.statusCode < 300 &&
          decoded is Map &&
          decoded['ok'] == true;
      _lastRegistrationAt = DateTime.now();
      _lastRegistrationMessage =
          ok ? '서버 알림 설정 확인 완료' : '서버 알림 설정 확인 실패 (${response.statusCode})';
      if (!ok) return null;
      final device = decoded['device'];
      return device is Map ? Map<String, Object?>.from(device) : null;
    } catch (error) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[push-v2] fetch prefs failed: $error');
      }
      _lastRegistrationAt = DateTime.now();
      _lastRegistrationMessage = '서버 알림 설정 확인 실패: $error';
      return null;
    }
  }

  Future<Uri?> slackConnectUri() async {
    if (_baseUrl.isEmpty) {
      _lastRegistrationMessage = 'Functions URL이 없어 Slack 연결을 시작할 수 없습니다.';
      _lastRegistrationAt = DateTime.now();
      return null;
    }

    final token = await ensureClientToken();
    return Uri.parse('$_baseUrl/startSlackConnect').replace(
      queryParameters: {'token': token},
    );
  }

  Future<bool> sendSlackTestAlert() async {
    if (_baseUrl.isEmpty) {
      _lastRegistrationMessage = 'Functions URL이 없어 Slack 테스트를 보낼 수 없습니다.';
      _lastRegistrationAt = DateTime.now();
      return false;
    }

    final token = await ensureClientToken();
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/sendSlackTest'),
        headers: _headers(),
        body: jsonEncode({'token': token}),
      );
      final decoded = jsonDecode(response.body);
      final ok = response.statusCode >= 200 &&
          response.statusCode < 300 &&
          decoded is Map &&
          decoded['ok'] == true;
      _lastRegistrationAt = DateTime.now();
      _lastRegistrationMessage = ok
          ? 'Slack 테스트 알림 전송 완료'
          : 'Slack 테스트 전송 실패 (${response.statusCode})';
      return ok;
    } catch (error) {
      _lastRegistrationAt = DateTime.now();
      _lastRegistrationMessage = 'Slack 테스트 전송 실패: $error';
      return false;
    }
  }

  Future<bool> syncNotificationPreferences(
      NotificationPreferences prefs) async {
    if (_baseUrl.isEmpty) {
      _lastRegistrationMessage = 'Functions URL이 없어 알림 설정 동기화를 건너뜁니다.';
      _lastRegistrationAt = DateTime.now();
      return false;
    }

    final token = await ensureClientToken();

    final quietStart = _formatMinutes(prefs.quietHoursStartMinutes);
    final quietEnd = _formatMinutes(prefs.quietHoursEndMinutes);

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/updatePreferences'),
        headers: _headers(),
        body: jsonEncode({
          'token': token,
          'alertsEnabled': prefs.alertsEnabled,
          'quietHoursEnabled': prefs.quietHoursEnabled,
          'quietHours': {
            'start': quietStart,
            'end': quietEnd,
          },
          'snoozedUntil': prefs.snoozedUntil?.toIso8601String(),
          'mutedTypes': prefs.mutedTypes,
          'notificationIntervalMinutes': prefs.notificationIntervalMinutes,
          'minimumSeverityPriority': prefs.minimumSeverityPriority,
          'minimumSeverityByType': prefs.minimumSeverityByType,
          'fireRiskMinimumLevel': prefs.fireRiskMinimumLevel,
          'slackWebhookUrl': prefs.slackWebhookUrl,
        }),
      );

      if (kDebugMode) {
        // ignore: avoid_print
        print(
            '[push-v2] prefs sync status=${response.statusCode} body=${response.body}');
      }
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      _lastRegistrationAt = DateTime.now();
      _lastRegistrationMessage =
          ok ? '알림 설정 동기화 완료' : '알림 설정 동기화 실패 (${response.statusCode})';
      return ok;
    } catch (error) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[push-v2] prefs sync failed: $error');
      }
      _lastRegistrationAt = DateTime.now();
      _lastRegistrationMessage = '알림 설정 동기화 실패: $error';
      return false;
    }
  }

  void _installMessageListeners() {
    _tokenRefreshSubscription ??= _messaging!.onTokenRefresh.listen(
      _handleToken,
    );
    _foregroundMessageSubscription ??= FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
    );
    _messageOpenedSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen(
      _handleOpenedMessage,
    );
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    final data = message.data;
    final title = notification?.title?.trim().isNotEmpty == true
        ? notification!.title!
        : (data['title']?.toString().trim().isNotEmpty == true
            ? data['title'].toString()
            : '공기질 알림');
    final body = notification?.body?.trim().isNotEmpty == true
        ? notification!.body!
        : (data['body']?.toString().trim().isNotEmpty == true
            ? data['body'].toString()
            : _foregroundBodyFromData(data));
    final intent = PushNotificationOpenIntent.fromMap(
      data.map((key, value) => MapEntry(key, value as Object?)),
    );
    final payload = jsonEncode(intent.toJson());
    final isEmergency = data['type']?.toString() == 'fire_risk' &&
        data['severity']?.toString() == 'critical';
    unawaited(
      isEmergency
          ? AlertNotificationPresenter.showEmergencyAlert(
              title,
              body,
              payload: payload,
            )
          : AlertNotificationPresenter.showAlert(
              title,
              body,
              payload: payload,
            ),
    );
  }

  void _handleOpenedMessage(RemoteMessage message) {
    final intent = PushNotificationOpenIntent.fromMap(
      message.data.map((key, value) => MapEntry(key, value as Object?)),
    );
    _lastRegistrationMessage =
        '알림 열림: ${message.data['type'] ?? message.messageId ?? 'message'}';
    _lastRegistrationAt = DateTime.now();
    _publishOpenIntent(intent);
  }

  Future<void> _handleLocalPayload(String payload) async {
    if (payload.startsWith(AlertNotificationPresenter.openFilePayloadPrefix)) {
      return;
    }

    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        _publishOpenIntent(
          PushNotificationOpenIntent.fromMap(
            Map<String, Object?>.from(decoded),
          ),
        );
        return;
      }
    } catch (_) {
      // Older local notifications used raw eventId/sensorId payloads.
    }

    final value = payload.trim();
    if (value.isEmpty) return;
    _publishOpenIntent(PushNotificationOpenIntent(eventId: value));
  }

  void _publishOpenIntent(PushNotificationOpenIntent intent) {
    _pendingOpenIntent = intent;
    if (!_openedController.isClosed) {
      _openedController.add(intent);
    }
  }

  String _foregroundBodyFromData(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    final severity = data['severity']?.toString();
    final sensorId = data['sensorId']?.toString();
    final parts = [
      if (type != null && type.isNotEmpty) type,
      if (severity != null && severity.isNotEmpty) severity,
      if (sensorId != null && sensorId.isNotEmpty) sensorId,
    ];
    return parts.isEmpty ? '현재 공기질 상태를 확인해 주세요.' : parts.join(' · ');
  }

  String _formatMinutes(int value) {
    final normalized = value % (24 * 60);
    final hour = (normalized ~/ 60).toString().padLeft(2, '0');
    final minute = (normalized % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

Future<void> _ensureFirebaseInitialized() async {
  if (Firebase.apps.isNotEmpty) return;
  await Firebase.initializeApp();
}
