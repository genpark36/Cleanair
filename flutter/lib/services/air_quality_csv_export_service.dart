import '../models/air_quality_snapshot.dart';
import '../utils/aqi_calculator.dart' as aqi;
import '../utils/nodered_health_engine.dart';
import 'alert_notification_presenter.dart';
import 'csv_file_writer.dart';

class AirQualityCsvExportResult {
  const AirQualityCsvExportResult({
    required this.filePath,
    required this.fileName,
    required this.rowCount,
  });

  final String filePath;
  final String fileName;
  final int rowCount;
}

class AirQualityCsvExportService {
  Future<AirQualityCsvExportResult> exportSnapshots({
    required List<AirQualitySnapshot> snapshots,
    required String selectedMetric,
  }) async {
    final sorted = List<AirQualitySnapshot>.of(snapshots)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (sorted.isEmpty) {
      throw StateError('내보낼 히스토리 데이터가 없습니다.');
    }

    final buffer = StringBuffer(
      'timestamp,pm25_ugm3,iaqi_score,iaqi_base_score,thermal_penalty,thermal_deviation,iaqi_primary_grade,iaqi_sub_level,m_score,e_score,i_score,co2_ppm,tvoc_index,nox_index,temp_c,humidity_pct,selected_metric,selected_metric_value,k_effective_1ph,t50_min,k_pm25_1ph,k_co2_1ph,r2_pm25,r2_co2\n',
    );
    final computed = _computePurificationMetrics(sorted);

    for (final snapshot in sorted) {
      final tsMs = snapshot.timestamp.millisecondsSinceEpoch;
      final computedPurification = computed[tsMs];
      final cadr = snapshot.purification?.cadr;
      final purifier = snapshot.purifier;
      final kEffective = cadr?.kCo2 ??
          computedPurification?.kCo2 ??
          cadr?.kEffective ??
          cadr?.k ??
          purifier?.kEffective ??
          purifier?.k ??
          computedPurification?.kEffective;
      final t50Minutes = cadr?.t50Minutes ??
          purifier?.t50Minutes ??
          computedPurification?.t50Minutes;
      final canComputeIaqi = kEffective != null &&
          kEffective.isFinite &&
          _finite(snapshot.co2) != null &&
          _finite(snapshot.pm25) != null &&
          _finite(snapshot.temperature) != null &&
          _finite(snapshot.humidity) != null;
      final iaqi = canComputeIaqi
          ? _safeCalculateIaqi(
              co2: _finite(snapshot.co2)!,
              pm25: _finite(snapshot.pm25)!,
              k: kEffective,
              voc: _finite(snapshot.tvoc) ?? 100.0,
              temp: _finite(snapshot.temperature)!,
              humi: _finite(snapshot.humidity)!,
              fallbackScore: snapshot.iaqiScore,
            )
          : _fallbackIaqi(snapshot.iaqiScore);
      final displayIaqi = (iaqi['display_iaqi'] as num?)?.toDouble() ??
          (iaqi['m_score'] as num?)?.toDouble();

      final row = <String>[
        snapshot.timestamp.toIso8601String(),
        _csvNumber(snapshot.pm25, decimals: 2),
        _csvNumber(displayIaqi, decimals: 3),
        _csvNumber((iaqi['base_display_iaqi'] as num?)?.toDouble(),
            decimals: 3),
        _csvNumber((iaqi['thermal_penalty'] as num?)?.toDouble(), decimals: 3),
        _csvNumber((iaqi['thermal_deviation'] as num?)?.toDouble(),
            decimals: 3),
        (iaqi['primary_grade'] ?? '').toString(),
        (iaqi['sub_level'] ?? '').toString(),
        _csvNumber((iaqi['m_score'] as num?)?.toDouble(), decimals: 3),
        _csvNumber((iaqi['e_score'] as num?)?.toDouble(), decimals: 3),
        _csvNumber((iaqi['i_score'] as num?)?.toDouble(), decimals: 3),
        _csvNumber(snapshot.co2, decimals: 2),
        _csvNumber(snapshot.tvoc, decimals: 2),
        _csvNumber(snapshot.nox, decimals: 2),
        _csvNumber(snapshot.temperature, decimals: 2),
        _csvNumber(snapshot.humidity, decimals: 2),
        selectedMetric,
        _csvNumber(_selectedValue(snapshot, selectedMetric), decimals: 2),
        _csvNumber(kEffective, decimals: 4),
        _csvNumber(t50Minutes, decimals: 2),
        _csvNumber(cadr?.kPm25 ?? computedPurification?.kPm25, decimals: 4),
        _csvNumber(cadr?.kCo2 ?? computedPurification?.kCo2, decimals: 4),
        _csvNumber(cadr?.r2Pm25 ?? computedPurification?.r2Pm25, decimals: 4),
        _csvNumber(cadr?.r2Co2 ?? computedPurification?.r2Co2, decimals: 4),
      ];
      buffer.writeln(row.join(','));
    }

    final fileResult = await writeCsvFile(
      metricName: selectedMetric,
      csvContent: buffer.toString(),
    );
    await AlertNotificationPresenter.showDownloadCompleted(
      filePath: fileResult.filePath,
      fileName: fileResult.fileName,
    );
    return AirQualityCsvExportResult(
      filePath: fileResult.filePath,
      fileName: fileResult.fileName,
      rowCount: sorted.length,
    );
  }

  Map<int, _ComputedPurificationMetrics> _computePurificationMetrics(
    List<AirQualitySnapshot> snapshots,
  ) {
    final engine = NodeRedHealthEngine();
    final byTimestampMs = <int, _ComputedPurificationMetrics>{};
    for (final snapshot in snapshots) {
      final Map<String, dynamic> health;
      try {
        health = engine.compute(
          pm25: _finite(snapshot.pm25),
          co2: _finite(snapshot.co2),
          tvoc: _finite(snapshot.tvoc),
          temp: _finite(snapshot.temperature),
          humidity: _finite(snapshot.humidity),
          timestampMs: snapshot.timestamp.millisecondsSinceEpoch,
        );
      } catch (_) {
        continue;
      }
      final purification = _asMap(health['purification']);
      final cadr = _asMap(purification?['cadr']);
      if (cadr == null || cadr.isEmpty) continue;
      byTimestampMs[snapshot.timestamp.millisecondsSinceEpoch] =
          _ComputedPurificationMetrics(
        kEffective: _toFiniteDouble(
          cadr['k_co2'] ?? cadr['kCo2'] ?? cadr['kEffective'] ?? cadr['k'],
        ),
        t50Minutes: _toFiniteDouble(cadr['t50_min'] ?? cadr['t50Minutes']),
        kPm25: _toFiniteDouble(cadr['k_pm25']),
        kCo2: _toFiniteDouble(cadr['k_co2'] ?? cadr['kCo2']),
        r2Pm25: _toFiniteDouble(cadr['r2_pm25'] ?? cadr['r2Pm25']),
        r2Co2: _toFiniteDouble(cadr['r2_co2'] ?? cadr['r2Co2']),
      );
    }
    return byTimestampMs;
  }

  Map<String, dynamic> _safeCalculateIaqi({
    required double co2,
    required double pm25,
    required double k,
    required double voc,
    required double temp,
    required double humi,
    required double? fallbackScore,
  }) {
    try {
      return aqi.calculate_iaqi(
        co2: co2,
        pm25: pm25,
        k: k,
        voc: voc,
        temp: temp,
        humi: humi,
      );
    } catch (_) {
      return _fallbackIaqi(fallbackScore);
    }
  }

  Map<String, dynamic> _fallbackIaqi(double? fallbackScore) {
    return <String, dynamic>{
      'primary_grade': '',
      'sub_level': '',
      'display_iaqi': fallbackScore,
      'base_display_iaqi': fallbackScore,
      'thermal_penalty': 0,
      'thermal_deviation': 0,
      'm_score': fallbackScore,
      'e_score': null,
      'i_score': null,
    };
  }

  double? _selectedValue(AirQualitySnapshot snapshot, String metric) {
    switch (metric) {
      case 'pm25':
        return snapshot.pm25;
      case 'co2':
        return snapshot.co2;
      case 'tvoc':
        return snapshot.tvoc;
      case 'nox':
        return snapshot.nox;
      case 'temperature':
        return snapshot.temperature;
      case 'humidity':
        return snapshot.humidity;
      default:
        return snapshot.pm25;
    }
  }

  String _csvNumber(double? value, {required int decimals}) {
    if (value == null || !value.isFinite || value.isNaN) return '';
    return value.toStringAsFixed(decimals);
  }

  double? _finite(double? value) {
    if (value == null || !value.isFinite || value.isNaN) return null;
    return value;
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  double? _toFiniteDouble(dynamic value) {
    if (value is num) {
      final result = value.toDouble();
      return result.isFinite && !result.isNaN ? result : null;
    }
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed != null && parsed.isFinite && !parsed.isNaN ? parsed : null;
    }
    return null;
  }
}

class _ComputedPurificationMetrics {
  const _ComputedPurificationMetrics({
    this.kEffective,
    this.t50Minutes,
    this.kPm25,
    this.kCo2,
    this.r2Pm25,
    this.r2Co2,
  });

  final double? kEffective;
  final double? t50Minutes;
  final double? kPm25;
  final double? kCo2;
  final double? r2Pm25;
  final double? r2Co2;
}
