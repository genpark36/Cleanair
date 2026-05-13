import 'dart:math' as math;

/// IAQI 결과 모델.
/// `aqi`는 사용자 표시용 대표 점수다.
///
/// - 좋음: 0
/// - 보통: 0 < m_score < 1
/// - 나쁨: 1 + e_score
///
/// `mScore`와 `eScore`는 기존 IAQI 판단 로직의 진단값으로 그대로 보존한다.
class AQIResult {
  final double aqi;
  final String category;
  final String color;
  final int level;
  final String primaryGrade;
  final String? subLevel;
  final double mScore;
  final double? eScore;
  final double? iScore;
  final double baseIaqi;
  final double thermalPenalty;
  final double thermalDeviation;

  const AQIResult({
    required this.aqi,
    required this.category,
    required this.color,
    required this.level,
    required this.primaryGrade,
    required this.subLevel,
    required this.mScore,
    required this.eScore,
    required this.iScore,
    required this.baseIaqi,
    required this.thermalPenalty,
    required this.thermalDeviation,
  });
}

double _round3(double value) {
  final factor = math.pow(10, 3).toDouble();
  return (value * factor).roundToDouble() / factor;
}

double _displayIaqiScore(double mScore, double? eScore) {
  if (mScore <= 0) return 0.0;
  if (mScore < 1) return mScore;
  return 1.0 + (eScore ?? math.max(0.0, mScore - 1.0));
}

({
  double penalty,
  double deviation,
  double tempDeviation,
  double humidityDeviation
}) _thermalComfortPenalty(double temp, double humi) {
  if (!temp.isFinite || !humi.isFinite) {
    return (
      penalty: 0.0,
      deviation: 0.0,
      tempDeviation: 0.0,
      humidityDeviation: 0.0,
    );
  }

  final tempExcess = math.max(0.0, math.max(20.0 - temp, temp - 26.0));
  final tempDeviation = math.min(1.0, math.pow(tempExcess / 4.0, 2).toDouble());
  final dryDeviation =
      math.pow(math.max(0.0, 30.0 - humi) / 10.0, 2).toDouble();
  final humidDeviation =
      math.pow(math.max(0.0, humi - 60.0) / 20.0, 2).toDouble();
  final humidityDeviation =
      math.min(1.0, math.max(dryDeviation, humidDeviation));
  final deviation = (0.7 * tempDeviation + 0.3 * humidityDeviation)
      .clamp(0.0, 1.0)
      .toDouble();

  return (
    penalty: _round3(0.5 * deviation),
    deviation: _round3(deviation),
    tempDeviation: _round3(tempDeviation),
    humidityDeviation: _round3(humidityDeviation),
  );
}

/// 실내 공기질 통합 지수(IAQI) 계산.
/// 반환 키: {primary_grade, sub_level, display_iaqi, m_score, e_score, i_score}
// ignore: non_constant_identifier_names
Map<String, dynamic> calculate_iaqi({
  required double co2,
  required double pm25,
  required double k,
  required double voc,
  required double temp,
  required double humi,
}) {
  final safeCo2 = co2.isFinite ? co2 : 600.0;
  final safePm25 = pm25.isFinite ? pm25 : 15.0;
  final safeVoc = voc.isFinite ? voc : 100.0;

  // Step 1) Normalization
  final rCo2 = math.max(0.0, (safeCo2 - 600.0) / 400.0);
  final rPm25 = math.max(0.0, (safePm25 - 15.0) / 35.0);
  final rVoc = math.max(0.0, (safeVoc - 100.0) / 100.0);

  // Step 2) Primary grade
  // Capstone calibration: exclude purification speed k and temperature/humidity
  // from IAQI for now. Keep the legacy "worst driver wins" IAQI behavior.
  final mScore = math.max(rCo2, math.max(rPm25, rVoc));

  String primaryGrade;
  String? subLevel;
  double? eScore;
  double? iScore;

  if (mScore == 0) {
    primaryGrade = '좋음';
  } else if (mScore < 1) {
    primaryGrade = '보통';
    // Step 4) Auxiliary index for moderate zone
    iScore = mScore;
  } else {
    primaryGrade = '나쁨';
    // Step 3) Severity analysis for bad zone
    eScore = math.max(0.0, rCo2 - 1.0) +
        math.max(0.0, rPm25 - 1.0) +
        math.max(0.0, rVoc - 1.0);

    if (eScore < 1) {
      subLevel = '조금 나쁨';
    } else if (eScore < 2) {
      subLevel = '나쁨';
    } else if (eScore < 3) {
      subLevel = '상당히 나쁨';
    } else {
      subLevel = '매우 나쁨';
    }
  }

  final baseDisplayIaqi = _displayIaqiScore(mScore, eScore);
  final thermal = _thermalComfortPenalty(temp, humi);
  final displayIaqi = math.min(6.0, baseDisplayIaqi + thermal.penalty);
  final displayExcess = math.max(0.0, displayIaqi - 1.0);
  if (displayIaqi >= 1 && primaryGrade != '나쁨') {
    primaryGrade = '나쁨';
    if (displayExcess < 1) {
      subLevel = '조금 나쁨';
    } else if (displayExcess < 2) {
      subLevel = '나쁨';
    } else if (displayExcess < 3) {
      subLevel = '상당히 나쁨';
    } else {
      subLevel = '매우 나쁨';
    }
  }

  return {
    'primary_grade': primaryGrade,
    'sub_level': subLevel,
    'display_iaqi': _round3(displayIaqi),
    'base_display_iaqi': _round3(baseDisplayIaqi),
    'thermal_penalty': thermal.penalty,
    'thermal_deviation': thermal.deviation,
    'thermal_temp_deviation': thermal.tempDeviation,
    'thermal_humidity_deviation': thermal.humidityDeviation,
    'm_score': _round3(mScore),
    'e_score': eScore == null ? null : _round3(eScore),
    'i_score': iScore == null ? null : _round3(iScore),
  };
}

AQIResult _toAqiResult(Map<String, dynamic> iaqi) {
  final primary = iaqi['primary_grade']?.toString() ?? '보통';
  final sub = iaqi['sub_level']?.toString();
  final mScore = (iaqi['m_score'] as num?)?.toDouble() ?? 0.0;
  final eScore = (iaqi['e_score'] as num?)?.toDouble();
  final iScore = (iaqi['i_score'] as num?)?.toDouble();
  final displayIaqi = (iaqi['display_iaqi'] as num?)?.toDouble() ??
      _displayIaqiScore(mScore, eScore);
  final baseIaqi = (iaqi['base_display_iaqi'] as num?)?.toDouble() ??
      _displayIaqiScore(mScore, eScore);
  final thermalPenalty = (iaqi['thermal_penalty'] as num?)?.toDouble() ?? 0.0;
  final thermalDeviation =
      (iaqi['thermal_deviation'] as num?)?.toDouble() ?? 0.0;

  int level;
  String color;
  if (primary == '좋음') {
    level = 0;
    color = '#00C853';
  } else if (primary == '보통') {
    level = 1;
    color = '#F9A825';
  } else if (sub != null && (sub.contains('조금 나쁨') || sub.contains('나쁨-1'))) {
    level = 2;
    color = '#FB8C00';
  } else if (sub != null && (sub == '나쁨' || sub.contains('나쁨-2'))) {
    level = 3;
    color = '#E53935';
  } else if (sub != null && (sub.contains('매우 나쁨') || sub.contains('나쁨-4'))) {
    level = 5;
    color = '#7E0023';
  } else {
    level = 4;
    color = '#B71C1C';
  }

  return AQIResult(
    aqi: _round3(displayIaqi),
    category: primary,
    color: color,
    level: level,
    primaryGrade: primary,
    subLevel: sub,
    mScore: mScore,
    eScore: eScore,
    iScore: iScore,
    baseIaqi: baseIaqi,
    thermalPenalty: thermalPenalty,
    thermalDeviation: thermalDeviation,
  );
}

/// 기존 호출부 호환용 엔트리 포인트.
/// 레거시 AQI 대신 IAQI를 계산해 반환한다.
AQIResult calculateComprehensiveAQI(
  double pm25, {
  double? co2,
  double? k,
  double? voc,
  double? temp,
  double? humi,
}) {
  final effectiveK = (k != null && k.isFinite && k >= 0) ? k : 0.0;
  final effectiveVoc = (voc != null && voc.isFinite) ? voc : 100.0;
  final iaqi = calculate_iaqi(
    co2: co2 ?? 600.0,
    pm25: pm25,
    k: effectiveK,
    voc: effectiveVoc,
    temp: temp ?? 24.0,
    humi: humi ?? 50.0,
  );
  return _toAqiResult(iaqi);
}

/// IAQI 결과 기반 권고 문구.
String getAQIRecommendation(AQIResult result) {
  if (result.primaryGrade == '좋음') {
    return result.thermalPenalty > 0
        ? '공기 오염도는 안정적이지만 온습도 쾌적도가 조금 떨어졌습니다.'
        : '실내 공기질이 안정적입니다. 현재 환기 상태를 유지하세요.';
  }

  if (result.primaryGrade == '보통') {
    return '주의 구간입니다. CO₂, PM2.5, TVOC 상대 지표(I=${(result.iScore ?? 0).toStringAsFixed(2)})를 참고해 환기와 오염원 확인을 권장합니다.';
  }

  if (result.subLevel?.contains('매우 나쁨') == true ||
      result.subLevel?.contains('나쁨-4') == true) {
    return '매우 나쁨 단계입니다. 즉시 강한 환기와 오염원 제거를 동시에 수행하세요.';
  }
  if (result.subLevel?.contains('상당히 나쁨') == true ||
      result.subLevel?.contains('나쁨-3') == true) {
    return '상당히 나쁨 단계입니다. 즉시 환기 강화 및 오염원 차단 조치를 수행하세요.';
  }
  if (result.subLevel == '나쁨' || result.subLevel?.contains('나쁨-2') == true) {
    return '나쁨 단계입니다. 단시간 내 강한 환기 또는 공기청정 강화가 필요합니다.';
  }
  return '조금 나쁨 단계입니다. 환기량을 늘리고 10~15분 후 재측정을 권장합니다.';
}
