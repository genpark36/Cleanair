import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_preferences.dart';

class PushNotificationServiceV2 {
  PushNotificationServiceV2({
    this.onTokenRefreshed,
  });

  final ValueChanged<String>? onTokenRefreshed;

  static const String _functionsBaseUrl =
      String.fromEnvironment('CLOUD_FUNCTION_BASE_URL', defaultValue: '');
  static const String _fallbackBaseUrl =
      String.fromEnvironment('BACKEND_BASE_URL', defaultValue: '');
  static const String _deviceApiKey =
      String.fromEnvironment('DEVICE_API_KEY', defaultValue: '');
  static const String _clientTokenPrefsKey = 'device_binding_v2_client_token';

  FirebaseMessaging? _messaging;
  String? _currentToken;
  String? _clientToken;
  bool _initialized = false;
  String? _sensorId;

  String get _baseUrl {
    if (_functionsBaseUrl.trim().isNotEmpty) return _functionsBaseUrl.trim();
    return _fallbackBaseUrl.trim();
  }

  String? get currentToken => _currentToken;

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

    final randomPart = Random().nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
    final generated = 'local-client-${DateTime.now().millisecondsSinceEpoch}-$randomPart';
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

    final settings = await _messaging!.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      _initialized = true;
      return;
    }

    await _messaging!.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _messaging!.onTokenRefresh.listen(_handleToken);

    final token = await _messaging!.getToken();
    if (token != null) {
      await _handleToken(token);
    } else {
      await _syncRegistration();
    }

    _initialized = true;
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

  Future<void> _syncRegistration() async {
    final clientToken = await ensureClientToken();
    await _registerToken(clientToken, fcmToken: _currentToken);
  }

  Future<void> _registerToken(String token, {String? fcmToken}) async {
    if (_baseUrl.isEmpty) return;

    final trimmedFcmToken = fcmToken?.trim();
    final resolvedFcmToken =
        (trimmedFcmToken == null || trimmedFcmToken.isEmpty) ? null : trimmedFcmToken;

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
        print('[push-v2] register status=${response.statusCode} body=${response.body}');
      }
    } catch (error) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[push-v2] register failed: $error');
      }
    }
  }

  Future<void> syncNotificationPreferences(NotificationPreferences prefs) async {
    if (_baseUrl.isEmpty) return;

    final token = await ensureClientToken();

    final quietStart = prefs.quietHoursStart;
    final quietEnd = prefs.quietHoursEnd;

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/updatePreferences'),
        headers: _headers(),
        body: jsonEncode({
          'token': token,
          'alertsEnabled': prefs.alertsEnabled,
          'quietHoursEnabled': prefs.quietHoursEnabled,
          'quietHours': {
            'start': '${quietStart.hour.toString().padLeft(2, '0')}:${quietStart.minute.toString().padLeft(2, '0')}',
            'end': '${quietEnd.hour.toString().padLeft(2, '0')}:${quietEnd.minute.toString().padLeft(2, '0')}',
          },
          'snoozedUntil': prefs.snoozedUntil?.toIso8601String(),
          'mutedTypes': prefs.mutedTypes,
        }),
      );

      if (kDebugMode) {
        // ignore: avoid_print
        print('[push-v2] prefs sync status=${response.statusCode} body=${response.body}');
      }
    } catch (error) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[push-v2] prefs sync failed: $error');
      }
    }
  }
}

Future<void> _ensureFirebaseInitialized() async {
  if (Firebase.apps.isNotEmpty) return;
  await Firebase.initializeApp();
}
