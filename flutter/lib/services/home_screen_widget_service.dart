import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../features/disaster_mode/fire_risk_assessment.dart';
import '../features/sensor_location/sensor_location_storage.dart';
import '../models/air_quality_snapshot.dart';

class HomeScreenWidgetService {
  HomeScreenWidgetService._();

  static final SensorLocationStorage _locationStorage = SensorLocationStorage();
  static const _statusWidget = 'CleanAirStatusWidget';
  static const _trendWidget = 'CleanAirTrendWidget';
  static const _maxTrendSamples = 96;

  static Future<void> update({
    required AirQualitySnapshot? latest,
    required List<AirQualitySnapshot> history,
  }) async {
    if (kIsWeb || !Platform.isAndroid || latest == null) return;

    final usableHistory = _historyWithLatest(history, latest);
    final fire = FireRiskAssessment.fromHistory(usableHistory);
    final iaqi = latest.iaqiScore;
    final locationLabel = await _locationLabel(latest);

    await Future.wait(<Future<bool?>>[
      HomeWidget.saveWidgetData<String>('location_label', locationLabel),
      HomeWidget.saveWidgetData<String>('iaqi_value', _formatNumber(iaqi)),
      HomeWidget.saveWidgetData<String>('iaqi_label', _iaqiLabel(iaqi)),
      HomeWidget.saveWidgetData<String>('disaster_label', fire.levelLabel),
      HomeWidget.saveWidgetData<String>('disaster_summary', fire.summary),
      HomeWidget.saveWidgetData<String>('pm25_value', _metric(latest.pm25, '')),
      HomeWidget.saveWidgetData<String>('co2_value', _metric(latest.co2, '')),
      HomeWidget.saveWidgetData<String>('co_value', _metric(latest.co, '')),
      HomeWidget.saveWidgetData<String>('tvoc_value', _metric(latest.tvoc, '')),
      HomeWidget.saveWidgetData<String>('nox_value', _metric(latest.nox, '')),
      HomeWidget.saveWidgetData<String>(
          'temperature_value', _metric(latest.temperature, '')),
      HomeWidget.saveWidgetData<String>(
          'humidity_value', _metric(latest.humidity, '')),
      HomeWidget.saveWidgetData<String>(
          'updated_at', _timeLabel(latest.timestamp)),
      HomeWidget.saveWidgetData<String>(
        'trend_values',
        _trendValues(usableHistory, (item) => item.iaqiScore),
      ),
      HomeWidget.saveWidgetData<String>(
        'trend_pm25_values',
        _trendValues(usableHistory, (item) => item.pm25),
      ),
      HomeWidget.saveWidgetData<String>(
        'trend_co2_values',
        _trendValues(usableHistory, (item) => item.co2),
      ),
      HomeWidget.saveWidgetData<String>(
        'trend_tvoc_values',
        _trendValues(usableHistory, (item) => item.tvoc),
      ),
      HomeWidget.saveWidgetData<String>(
        'trend_nox_values',
        _trendValues(usableHistory, (item) => item.nox),
      ),
      HomeWidget.saveWidgetData<String>(
        'trend_co_values',
        _trendValues(usableHistory, (item) => item.co),
      ),
      HomeWidget.saveWidgetData<String>(
          'trend_label', _trendLabel(usableHistory)),
    ]);

    unawaited(HomeWidget.updateWidget(androidName: _statusWidget));
    unawaited(HomeWidget.updateWidget(androidName: _trendWidget));
  }

  static List<AirQualitySnapshot> _historyWithLatest(
    List<AirQualitySnapshot> history,
    AirQualitySnapshot latest,
  ) {
    final entries = <AirQualitySnapshot>[
      ...history,
      if (!history.any((item) =>
          item.timestamp.millisecondsSinceEpoch ==
          latest.timestamp.millisecondsSinceEpoch))
        latest,
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return entries;
  }

  static String _trendValues(
    List<AirQualitySnapshot> history,
    double? Function(AirQualitySnapshot item) valueOf,
  ) {
    final now = history.isNotEmpty ? history.last.timestamp : DateTime.now();
    final cutoff = now.subtract(const Duration(hours: 24));
    final values = history
        .where((item) => !item.timestamp.isBefore(cutoff))
        .map(valueOf)
        .whereType<double>()
        .where((value) => value.isFinite)
        .toList(growable: false);
    if (values.isEmpty) return '';
    if (values.length <= _maxTrendSamples) {
      return values.map((value) => value.toStringAsFixed(2)).join(',');
    }
    final step = values.length / _maxTrendSamples;
    return List<String>.generate(_maxTrendSamples, (index) {
      final sourceIndex = (index * step).floor().clamp(0, values.length - 1);
      return values[sourceIndex].toStringAsFixed(2);
    }).join(',');
  }

  static String _trendLabel(List<AirQualitySnapshot> history) {
    final values = history
        .map((item) => item.iaqiScore)
        .whereType<double>()
        .where((value) => value.isFinite)
        .toList(growable: false);
    if (values.length < 2) return '최근 기록 대기 중';
    final delta = values.last - values.first;
    if (delta.abs() < 0.05) return '큰 변화 없음';
    return delta > 0 ? '나빠지는 흐름' : '개선되는 흐름';
  }

  static Future<String> _locationLabel(AirQualitySnapshot latest) async {
    final saved = await _locationStorage.loadForSensor(latest.id);
    for (final value in <String?>[
      saved?.spaceName,
      saved?.buildingName,
      latest.location?.source,
      saved?.address,
    ]) {
      final text = value?.trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return '실내';
  }

  static String _iaqiLabel(double? value) {
    if (value == null || !value.isFinite) return '대기 중';
    if (value < 0.5) return '좋음';
    if (value < 1.0) return '보통';
    if (value < 2.0) return '조금 나쁨';
    if (value < 3.0) return '나쁨';
    if (value < 4.0) return '상당히 나쁨';
    return '매우 나쁨';
  }

  static String _metric(double? value, String unit) {
    if (value == null || !value.isFinite) return '-';
    return '${_formatNumber(value)}$unit';
  }

  static String _formatNumber(double? value) {
    if (value == null || !value.isFinite) return '--';
    if (value.abs() >= 100) return value.round().toString();
    return value.toStringAsFixed(value.abs() >= 10 ? 1 : 2);
  }

  static String _timeLabel(DateTime time) {
    final local = time.toLocal();
    return '${local.month}/${local.day} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
