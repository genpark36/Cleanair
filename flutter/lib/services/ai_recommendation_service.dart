import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/air_quality_snapshot.dart';

class AiRecommendation {
  const AiRecommendation({
    required this.summary,
    required this.recommendations,
    required this.source,
    required this.confidence,
  });

  final String summary;
  final List<String> recommendations;
  final String source;
  final String confidence;

  static AiRecommendation? fromJson(Map<String, Object?> json) {
    final summary = json['summary']?.toString().trim();
    if (summary == null || summary.isEmpty) return null;
    final rawRecommendations = json['recommendations'];
    return AiRecommendation(
      summary: summary,
      recommendations: rawRecommendations is List
          ? rawRecommendations
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .take(3)
              .toList(growable: false)
          : const <String>[],
      source: json['source']?.toString() ?? 'local',
      confidence: json['confidence']?.toString() ?? 'normal',
    );
  }
}

class AiRecommendationService {
  AiRecommendationService({http.Client? client})
      : _client = client ?? http.Client();

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

  final http.Client _client;

  String get _baseUrl {
    if (_functionsBaseUrl.trim().isNotEmpty) return _functionsBaseUrl.trim();
    return _fallbackBaseUrl.trim();
  }

  Map<String, String> _headers() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_deviceApiKey.trim().isNotEmpty) {
      headers['X-API-Key'] = _deviceApiKey.trim();
    }
    return headers;
  }

  Future<AiRecommendation?> generate({
    required AirQualitySnapshot snapshot,
    required List<AirQualitySnapshot> recentHistory,
    required String locationLabel,
    required List<String> alertMessages,
  }) async {
    final uri = Uri.parse('$_baseUrl/generateAiRecommendation');
    final response = await _client
        .post(
          uri,
          headers: _headers(),
          body: jsonEncode({
            'locationLabel': locationLabel,
            'snapshot': _snapshotJson(snapshot),
            'recentHistory': recentHistory
                .where(_hasAnyMetric)
                .map(_snapshotJson)
                .toList(growable: false),
            'alertMessages': alertMessages,
          }),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return null;
    return AiRecommendation.fromJson(decoded.cast<String, Object?>());
  }

  static bool _hasAnyMetric(AirQualitySnapshot snapshot) {
    return snapshot.pm25 != null ||
        snapshot.co2 != null ||
        snapshot.tvoc != null ||
        snapshot.nox != null ||
        snapshot.co != null ||
        snapshot.temperature != null ||
        snapshot.humidity != null ||
        snapshot.iaqiScore != null;
  }

  static Map<String, Object?> _snapshotJson(AirQualitySnapshot snapshot) {
    return {
      'id': snapshot.id,
      'timestamp': snapshot.timestamp.toIso8601String(),
      'pm25': snapshot.pm25,
      'co2': snapshot.co2,
      'tvoc': snapshot.tvoc,
      'nox': snapshot.nox,
      'co': snapshot.co,
      'temperature': snapshot.temperature,
      'humidity': snapshot.humidity,
      'iaqiScore': snapshot.iaqiScore,
      'aqiCategory': snapshot.aqiCategory,
      'aqiLevel': snapshot.aqiLevel,
    };
  }
}
