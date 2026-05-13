// Client-side health computation engine replicating all Node-RED function nodes.
//
// This engine is stateful — it tracks mold duration, cardio PM2.5 history,
// and sleep CO2/TVOC history, exactly as Node-RED did with flow.get/flow.set
// and context.get/context.set.
import 'dart:math' as math;

// ════════════════════════════════════════════════════════════════════════════
//  DERIVED VALUES  (IAQI, Dew Point, Discomfort Index)
// ════════════════════════════════════════════════════════════════════════════

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

/// 보만 IAQI 계산식.
/// 반환 키: primary_grade, sub_level, display_iaqi, m_score, e_score, i_score
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

  final rCo2 = math.max(0.0, (safeCo2 - 600.0) / 400.0);
  final rPm25 = math.max(0.0, (safePm25 - 15.0) / 35.0);
  final rVoc = math.max(0.0, (safeVoc - 100.0) / 100.0);

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
    iScore = mScore;
  } else {
    primaryGrade = '나쁨';
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

/// Magnus-formula dew point — exact Node-RED constants.
double calculateDewPoint(double temp, double humidity) {
  const a = 17.27;
  const b = 237.7;
  final alpha = ((a * temp) / (b + temp)) + math.log(humidity / 100);
  return (b * alpha) / (a - alpha);
}

/// Discomfort Index — exact Node-RED formula.
double calculateDiscomfortIndex(double temp, double humidity) {
  final di = 0.81 * temp + 0.01 * humidity * (0.99 * temp - 14.3) + 46.3;
  return (di * 10).roundToDouble() / 10;
}

/// Discomfort level — exact Node-RED thresholds.
({String level, String color, int score}) getDiscomfortLevel(double di) {
  if (di < 68) return (level: '쾌적', color: '#4CAF50', score: 100);
  if (di < 75) return (level: '보통', color: '#FFC107', score: 80);
  if (di < 80) return (level: '약간 불쾌', color: '#FF9800', score: 60);
  return (level: '불쾌', color: '#F44336', score: 40);
}

// ════════════════════════════════════════════════════════════════════════════
//  CHILD MODE — Focus, Respiratory, Infection, Mold
// ════════════════════════════════════════════════════════════════════════════

/// 어린이 집중 (Focus) — exact Node-RED 4-level CO2 thresholds.
Map<String, dynamic> computeChildFocus(double co2) {
  String level, message, action;
  final co2Int = co2.round();
  if (co2 < 700) {
    level = '좋음';
    message = 'CO₂ $co2Int ppm — 좋음 (집중하기 매우 좋아요)';
    action = '현재 상태 유지';
  } else if (co2 < 1000) {
    level = '보통';
    message = 'CO₂ $co2Int ppm — 보통 (10분 환기를 권장합니다.)';
    action = '10분 환기 권장';
  } else if (co2 < 1500) {
    level = '주의';
    message = 'CO₂ $co2Int ppm — 주의 (집중력 저하 가능성이 있습니다)';
    action = '즉시 환기';
  } else {
    level = '높음';
    message = 'CO₂ $co2Int ppm — 높음 (반드시 환기하세요!!)';
    action = '반드시 환기';
  }
  return {
    'co2': co2,
    'level': level,
    'message': message,
    'recommendedAction': action,
  };
}

/// 호흡기 건강 지표 (Respiratory) — exact Node-RED band-based deduction.
Map<String, dynamic> computeChildRespiratory(
    double temp, double humidity, double tvoc) {
  int score = 100;

  // === Humidity bands ===
  String rhMsg;
  if (humidity >= 40 && humidity <= 60) {
    rhMsg = '습도 양호'; // 0 deduction
  } else if ((humidity >= 30 && humidity < 40) ||
      (humidity > 60 && humidity <= 70)) {
    score -= 10;
    rhMsg = '약간 건조/다습';
  } else if ((humidity >= 20 && humidity < 30) ||
      (humidity > 70 && humidity < 80)) {
    score -= 25;
    rhMsg = '건조/다습 — 관리 필요';
  } else {
    // <20 or ≥80
    score -= 35;
    rhMsg = '심한 건조/다습 — 호흡기 부담';
  }

  // === Temperature bands ===
  String tMsg;
  if (temp >= 20 && temp <= 24) {
    tMsg = '쾌적한 온도'; // 0 deduction
  } else if ((temp >= 18 && temp < 20) || (temp > 24 && temp <= 26)) {
    score -= 10;
    tMsg = '약간 춥거나 더운 편';
  } else if ((temp >= 16 && temp < 18) || (temp > 26 && temp < 28)) {
    score -= 20;
    tMsg = '온도 민감 구간 - 컨디션 저하 주의';
  } else {
    // <16 or ≥28
    score -= 30;
    tMsg = '온도 위험 구간 - 실내 환경 개선 권장';
  }

  // === TVOC bands ===
  String vocMsg;
  if (tvoc < 200) {
    vocMsg = 'VOC 낮음'; // 0 deduction
  } else if (tvoc < 400) {
    score -= 10;
    vocMsg = '약간 높음 — 환기 권장';
  } else if (tvoc < 1000) {
    score -= 20;
    vocMsg = '높음 — 청소/자재 점검 필요';
  } else {
    score -= 30;
    vocMsg = '매우 높음 — 환기 필수/원인제거 실시';
  }

  score = score.clamp(0, 100).toInt();

  String level;
  if (score >= 80) {
    level = '좋음';
  } else if (score >= 60) {
    level = '보통';
  } else if (score >= 40) {
    level = '주의';
  } else {
    level = '경고';
  }

  return {
    'score': score.toDouble(),
    'level': level,
    'temp': temp,
    'rh': humidity,
    'tvoc': tvoc,
    'rhMsg': rhMsg,
    'tMsg': tMsg,
    'vocMsg': vocMsg,
  };
}

/// 면역/감염 위험 지표 (Infection Risk) — exact Node-RED combo scoring.
Map<String, dynamic> computeChildInfection(double co2, double humidity) {
  // CO2 band
  int co2Band;
  if (co2 < 800) {
    co2Band = 0;
  } else if (co2 < 1000) {
    co2Band = 1;
  } else if (co2 < 1500) {
    co2Band = 2;
  } else {
    co2Band = 3;
  }

  // Humidity band
  int rhBand;
  if (humidity >= 40 && humidity <= 60) {
    rhBand = 0;
  } else if ((humidity >= 30 && humidity < 40) ||
      (humidity > 60 && humidity <= 70)) {
    rhBand = 1;
  } else if ((humidity >= 20 && humidity < 30) ||
      (humidity > 70 && humidity < 80)) {
    rhBand = 2;
  } else {
    rhBand = 3;
  }

  final combo = co2Band + rhBand; // 0–6
  const scoreMap = [10, 25, 40, 55, 70, 85, 95];
  final score = scoreMap[combo.clamp(0, 6).toInt()].toDouble();

  String level;
  if (score < 30) {
    level = '낮음';
  } else if (score < 60) {
    level = '보통';
  } else if (score < 80) {
    level = '높음';
  } else {
    level = '매우 높음';
  }

  return {
    'score': score,
    'level': level,
    'combo': combo,
    'co2': co2,
    'rh': humidity,
  };
}

/// 곰팡이 위험 (Mold Risk) — exact Node-RED duration tracking.
///
/// This is called from the stateful engine which manages [moldHighSince].
Map<String, dynamic> computeChildMold(
  double humidity,
  double pm25, {
  required int moldHighSinceMs,
  required int nowMs,
}) {
  double durationHours = 0;
  int updatedHighSince = moldHighSinceMs;

  if (humidity > 60) {
    if (updatedHighSince == 0) {
      updatedHighSince = nowMs;
    }
    durationHours = (nowMs - updatedHighSince) / (1000 * 60 * 60);
  } else {
    updatedHighSince = 0;
  }

  int moldRiskLevel = 1;
  String moldRiskMessage = '안전: 곰팡이 위험 낮음 (CDC 기준 60% 미만)';

  String airQualityAlert = '';
  if (durationHours > 24) {
    moldRiskLevel = 4;
    moldRiskMessage = '위험: 고습 24시간 이상 지속. 곰팡이 발아 임계 시간 초과!';
  } else if (humidity > 70) {
    moldRiskLevel = 3;
    moldRiskMessage = '경고: 현재 습도 70% 초과. 곰팡이 성장에 \'최적\'인 상태입니다.';
  } else if (humidity > 60 && pm25 > 35) {
    moldRiskLevel = 3;
    moldRiskMessage = '경고: 고습도(60%+) 및 미세먼지 \'나쁨\'. 곰팡이 증식 가속 위험.';
  } else if (humidity > 60) {
    moldRiskLevel = 2;
    moldRiskMessage = '주의: 습도 60% 초과. 곰팡이 농도 증가 시작 임계점입니다.';
  }

  // Extra PM2.5 alert
  if (pm25 > 35 && moldRiskLevel < 3) {
    airQualityAlert = ' (참고: 미세먼지 수치가 높습니다. 환기 권장)';
  }

  return {
    'riskLevel': moldRiskLevel,
    'riskMessage': moldRiskMessage + airQualityAlert,
    'durationHours': double.parse(durationHours.toStringAsFixed(1)),
    'humidity': humidity,
    'pm25': pm25,
    '_updatedHighSince': updatedHighSince, // internal: returned to engine
  };
}

// ════════════════════════════════════════════════════════════════════════════
//  SENIOR MODE — Cardio, Sleep, PM Exposure, Ventilation
// ════════════════════════════════════════════════════════════════════════════

/// 심혈관 보호점수 (Cardio) — exact Node-RED history-based computation.
///
/// [hist] is the PM2.5 history maintained by the stateful engine.
Map<String, dynamic> computeSeniorCardio(
  List<PmHistoryEntry> hist,
) {
  const highTh = 5.0; // Node-RED 원본: HIGH_TH = 5
  final high = hist.where((d) => d.pm > highTh).toList();
  final total = hist.length;

  // Calculate high-exposure hours
  double highHours = 0;
  if (high.length > 1) {
    double dtSum = 0;
    for (int i = 1; i < high.length; i++) {
      dtSum += (high[i].ts - high[i - 1].ts);
    }
    final avgDt = dtSum / (high.length - 1);
    highHours = high.length * avgDt / (1000 * 60 * 60);
  } else if (high.length == 1) {
    // single sample = ~60s
    highHours = 60000 / (1000 * 60 * 60);
  }

  // Average k during high-PM samples (we use a default since we don't have real k)
  double kAvg;
  if (high.isNotEmpty) {
    kAvg = high.map((e) => e.k > 0 ? e.k : 0.1).reduce((a, b) => a + b) /
        high.length;
  } else if (hist.isNotEmpty) {
    kAvg = hist.map((e) => e.k > 0 ? e.k : 0.1).reduce((a, b) => a + b) /
        hist.length;
  } else {
    kAvg = 0.1;
  }
  if (!kAvg.isFinite || kAvg <= 0) kAvg = 0.1;

  // Risk formula: riskRaw = highHours × (1 / kAvg)
  final riskRaw = highHours == 0 ? 0.0 : highHours * (1 / kAvg);

  const l = 8.0; // Scale factor
  double score = 100 * (1 - (riskRaw / l));
  score = score.clamp(0, 100).toDouble();
  score = score.roundToDouble();

  String level;
  if (score >= 80) {
    level = '우수';
  } else if (score >= 60) {
    level = '양호';
  } else if (score >= 40) {
    level = '주의';
  } else {
    level = '위험';
  }

  return {
    'score': score,
    'level': level,
    'highHours': double.parse(highHours.toStringAsFixed(1)),
    'kAvg': double.parse(kAvg.toStringAsFixed(2)),
    'riskRaw': double.parse(riskRaw.toStringAsFixed(2)),
    'samples': total,
  };
}

/// 쾌적 수면 지수 (Sleep Quality) — exact Node-RED history-based computation.
Map<String, dynamic> computeSeniorSleep(
  List<SleepHistoryEntry> hist,
) {
  if (hist.isEmpty) {
    return {
      'score': 80.0,
      'level': '데이터 부족',
      'scoreRange': '80-100',
      'interpretation': '데이터 부족 (야간 데이터 축적 중)',
      'goodCo2': 80,
      'goodVoc': 80,
      'samples': 0,
    };
  }

  // Good CO₂ ratio: samples where co2 < 1000
  final goodCo2Ratio = hist.where((d) => d.co2 < 1000).length / hist.length;

  // Good VOC ratio: samples where tvoc < 200
  final vocSamples = hist.where((d) => d.tvoc != null).toList();
  double goodVocRatio;
  if (vocSamples.isNotEmpty) {
    goodVocRatio =
        vocSamples.where((d) => d.tvoc! < 200).length / vocSamples.length;
  } else {
    goodVocRatio = 0.7; // default fallback
  }

  // Weighted score formula
  final scoreRaw = (goodCo2Ratio * 0.7 + goodVocRatio * 0.3) * 100;
  int score = scoreRaw.round().clamp(0, 100).toInt();

  String level, interpretation, scoreRange;
  if (score >= 80) {
    level = '좋음';
    interpretation = 'CO₂·VOC 빠르게 회복 — 쾌적한 수면 환경';
    scoreRange = '80-100';
  } else if (score >= 60) {
    level = '보통';
    interpretation = '대체로 양호하나, CO₂ 또는 VOC가 잠깐 높아지는 구간 존재';
    scoreRange = '60-79';
  } else if (score >= 40) {
    level = '나쁨';
    interpretation = '일부 구간에서 환기 부족 — 야간 창문·환기 필요';
    scoreRange = '40-59';
  } else {
    level = '매우 나쁨';
    interpretation = '밤새 CO₂·VOC 높음, 회복 느림 — 수면 질 크게 저하';
    scoreRange = '0-39';
  }

  return {
    'score': score.toDouble(),
    'level': level,
    'scoreRange': scoreRange,
    'interpretation': interpretation,
    'goodCo2': (goodCo2Ratio * 100).round(),
    'goodVoc': (goodVocRatio * 100).round(),
    'samples': hist.length,
  };
}

/// 고령자 PM2.5 노출 (PM Exposure) — exact Node-RED 4-band message.
Map<String, dynamic> computeSeniorPmExposure(double pm25) {
  final pm = pm25.round();
  String band, message;
  if (pm25 < 15) {
    band = '양호';
    message = 'PM2.5 $pm µg/m³ — 양호 (리스크 낮음)';
  } else if (pm25 < 35) {
    band = '주의';
    message = 'PM2.5 $pm µg/m³ — 주의 (민감군 영향 가능)';
  } else if (pm25 < 55) {
    band = '나쁨';
    message = 'PM2.5 $pm µg/m³ — 나쁨 (체류시간 줄이기 권장)';
  } else {
    band = '매우 나쁨';
    message = 'PM2.5 $pm µg/m³ — 매우 나쁨 (즉시 환기/정화)';
  }
  return {
    'pm25': pm25,
    'band': band,
    'message': message,
  };
}

/// 고령자 환기 추정 (Ventilation) — from Node-RED snapshot builder.
Map<String, dynamic> computeSeniorVentilation(double kValue) {
  final t50 = kValue > 0 ? (60 / kValue).round().clamp(10, 9999) : 9999;
  return {
    'k': kValue,
    't50Minutes': t50.toDouble(),
    'message': '환기 속도 추정',
  };
}

// ════════════════════════════════════════════════════════════════════════════
//  PURIFICATION MODE — CADR, IPI, Ventilation Status
// ════════════════════════════════════════════════════════════════════════════

/// CADR grade — exact Node-RED thresholds.
String getCadrGrade(double k) {
  if (k >= 2.0) return 'S';
  if (k >= 1.0) return 'A';
  if (k >= 0.5) return 'B';
  return 'C';
}

int getCadrIndex(String grade) {
  switch (grade) {
    case 'S':
      return 4;
    case 'A':
      return 3;
    case 'B':
      return 2;
    default:
      return 1;
  }
}

/// Purification CADR computation — uses real k from log-linear regression.
Map<String, dynamic> computePurificationCadr(
  double pm25,
  double co2, {
  double? tvoc,
  double? pmSlopePerMin,
  double? co2SlopePerMin,
  double? tvocSlopePerMin,
  required double kPm25,
  required double kCo2,
  required double r2Pm25,
  required double r2Co2,
}) {
  // CADR는 PM2.5 정화 성능 지표이므로 유효 k는 PM 축 기준으로 계산한다.
  final kEffective = math.max(kPm25, 0.0);

  final gradePm25 = getCadrGrade(kPm25);
  final gradeCo2 = getCadrGrade(kCo2);
  final grade = getCadrGrade(kEffective);
  final index = getCadrIndex(grade);

  final t50 =
      kEffective > 0.001 ? ((math.log(2) / kEffective) * 60).round() : 999;
  final t50Pm25 = kPm25 > 0.001 ? ((math.log(2) / kPm25) * 60).round() : 999;
  final t50Co2 = kCo2 > 0.001 ? ((math.log(2) / kCo2) * 60).round() : 999;

  // Level classification
  String levelPm25 = _getKLevel(kPm25);
  String levelCo2 = _getKLevel(kCo2);

  // Scenario classification is descriptive only; it must not alter k values.
  // Scenario diagnosis
  String mode, scenario;
  final lPm = _getKLevelCode(kPm25);
  final lCo2 = _getKLevelCode(kCo2);
  const cleanPm25Threshold = 5.0;
  const cleanCo2Threshold = 500.0;
  const cleanTvocThreshold = 100.0;
  const pmSlopeThresholdPerMin = 0.2;
  const co2SlopeThresholdPerMin = 6.0;
  const tvocSlopeThresholdPerMin = 10.0;
  const pmRiseLimitPerMin = 0.1;
  const co2RiseLimitPerMin = 2.5;
  const tvocRiseLimitPerMin = 5.0;
  final hasMeaningfulRise = (pmSlopePerMin ?? 0.0) > pmRiseLimitPerMin ||
      (co2SlopePerMin ?? 0.0) > co2RiseLimitPerMin ||
      (tvocSlopePerMin ?? 0.0) > tvocRiseLimitPerMin;
  final isCleanSteadyState = pm25 <= cleanPm25Threshold &&
      co2 <= cleanCo2Threshold &&
      tvoc != null &&
      tvoc <= cleanTvocThreshold &&
      pmSlopePerMin != null &&
      pmSlopePerMin.abs() <= pmSlopeThresholdPerMin &&
      co2SlopePerMin != null &&
      co2SlopePerMin.abs() <= co2SlopeThresholdPerMin &&
      tvocSlopePerMin != null &&
      tvocSlopePerMin.abs() <= tvocSlopeThresholdPerMin &&
      !hasMeaningfulRise;

  if (isCleanSteadyState) {
    mode = 'equilibrium_clean';
    scenario = '정상 평형 (공기질 양호)';
  } else if (hasMeaningfulRise &&
      (lPm == 'ZERO' ||
          lPm == 'NEGATIVE' ||
          lCo2 == 'ZERO' ||
          lCo2 == 'NEGATIVE')) {
    mode = 'polluting';
    scenario = '완만한 상승 추세';
  } else if (lPm == 'HIGH_POS' && (lCo2 == 'LOW_POS' || lCo2 == 'ZERO')) {
    mode = 'purification';
    scenario = 'PM 급속감소 (밀폐상태)';
  } else if ((lPm == 'LOW_POS' || lPm == 'ZERO' || lPm == 'NEGATIVE') &&
      lCo2 == 'HIGH_POS') {
    mode = 'ventilation';
    scenario = 'CO₂ 급속감소 (환기중)';
  } else if (lPm == 'HIGH_POS' && lCo2 == 'HIGH_POS') {
    mode = 'combined';
    scenario = '복합 감소 (정화+환기)';
  } else if ((lPm == 'NEGATIVE' && lCo2 != 'HIGH_POS') ||
      (lCo2 == 'NEGATIVE' && lPm != 'HIGH_POS')) {
    mode = 'polluting';
    scenario = '농도 상승중';
  } else {
    mode = 'stagnant';
    scenario = '정체 상태';
  }

  return {
    'k': kEffective,
    'kEffective': kEffective,
    't50_min': t50,
    'index': index,
    'grade': grade,
    'trend': _getTrend(kEffective),
    'mode': mode,
    'scenario': scenario,
    'k_pm25': kPm25,
    'k_co2': kCo2,
    'gradePm25': gradePm25,
    'gradeCo2': gradeCo2,
    'levelPm25': levelPm25,
    'levelCo2': levelCo2,
    'dualKDisplay':
        'k_PM=${kPm25.toStringAsFixed(2)}, k_CO₂=${kCo2.toStringAsFixed(2)} (1/h)',
    't50_pm25': t50Pm25, // ignore: unnecessary_brace_in_string_interps
    't50_co2': t50Co2,
    'dualT50Display': 't₅₀_PM≈$t50Pm25분, t₅₀_CO₂≈$t50Co2분',
    'r2_pm25': r2Pm25,
    'r2_co2': r2Co2,
  };
}

/// IPI (바이러스 잔류 위험지수) — exact Node-RED 4-level grading (fanout version).
Map<String, dynamic> computeIpi(double kCo2, double kPm25) {
  final kCo2Clamped = math.max(kCo2, 0.0);
  final kPm25Clamped = math.max(kPm25, 0.0);

  // t90 formula: ln(10) / k × 60
  final t90Co2 =
      kCo2Clamped > 0.001 ? (math.log(10) / kCo2Clamped * 60).round() : 999;
  final t90Pm25 =
      kPm25Clamped > 0.001 ? (math.log(10) / kPm25Clamped * 60).round() : 999;

  // 4-level scoring from fanout node
  String level;
  int score;
  if (kCo2 <= 0) {
    level = '경고';
    score = 1;
  } else if (kCo2 >= 3.0) {
    level = '안심';
    score = 4;
  } else if (kCo2 >= 1.0) {
    level = '보통';
    score = 3;
  } else if (kCo2 >= 0.3) {
    level = '주의';
    score = 2;
  } else {
    level = '경고';
    score = 1;
  }

  return {
    'k': kCo2,
    't90_min': t90Co2,
    'level': level,
    'score': score,
    'k_pm25': kPm25,
    'k_co2': kCo2,
    't90_pm25': t90Pm25,
    't90_co2': t90Co2,
    'dualKDisplay':
        'k_PM=${kPm25Clamped.toStringAsFixed(2)}, k_CO₂=${kCo2Clamped.toStringAsFixed(2)} (1/h)',
    'dualT90Display': 't₉₀_PM≈$t90Pm25분, t₉₀_CO₂≈$t90Co2분',
  };
}

/// Purification ventilation status — exact Node-RED logic.
Map<String, dynamic> computePurificationVentilation(double co2) {
  if (co2 > 1000) {
    return {
      'status': '환기필요',
      'message': 'CO₂가 높습니다. 환기하세요.',
      'alerts': ['환기 필요', '창문 개방 권장'],
    };
  }
  return {
    'status': '정화중',
    'message': '정화 중',
    'alerts': ['정상 운전'],
  };
}

// ════════════════════════════════════════════════════════════════════════════
//  ALERTS/WATCHERS
// ════════════════════════════════════════════════════════════════════════════

/// Generate alert messages based on current values.
Map<String, dynamic> computeAlerts(
  double pm25,
  double co2,
  double humidity,
  int moldRiskLevel,
) {
  final messages = <String>[];

  // PM2.5
  if (pm25 >= 55) {
    messages.add('PM2.5 ${pm25.round()} µg/m³ — 매우 나쁨! 즉시 환기/정화 필요');
  } else if (pm25 >= 35) {
    messages.add('PM2.5 ${pm25.round()} µg/m³ — 나쁨. 환기를 권장합니다.');
  } else if (pm25 >= 15) {
    messages.add('PM2.5 ${pm25.round()} µg/m³ — 주의 필요');
  }

  // CO2
  if (co2 >= 1500) {
    messages.add('CO₂ ${co2.round()} ppm — 매우 높음! 즉시 환기하세요');
  } else if (co2 >= 1000) {
    messages.add('CO₂ ${co2.round()} ppm — 높음. 환기를 권장합니다.');
  }

  String? airQualityAlert;
  if (pm25 >= 35) {
    airQualityAlert = 'PM2.5 주의';
  }

  return {
    'messages': messages.isEmpty ? null : messages,
    'airQualityAlert': airQualityAlert,
    'moldRiskLevel': moldRiskLevel,
  };
}

// ════════════════════════════════════════════════════════════════════════════
//  STATEFUL ENGINE
// ════════════════════════════════════════════════════════════════════════════

/// PM2.5 history entry for cardio tracking.
class PmHistoryEntry {
  /// Timestamp in milliseconds.
  final int ts;

  /// PM2.5 value.
  final double pm;

  /// Estimated k value.
  final double k;

  /// Creates a PM history entry.
  PmHistoryEntry(this.ts, this.pm, this.k);
}

/// Sleep history entry for CO2/TVOC tracking.
class SleepHistoryEntry {
  /// Timestamp in milliseconds.
  final int ts;

  /// CO2 value.
  final double co2;

  /// TVOC value (nullable).
  final double? tvoc;

  /// Creates a sleep history entry.
  SleepHistoryEntry(this.ts, this.co2, this.tvoc);
}

/// Stateful health computation engine.
///
/// Maintains history windows for stateful calculations (mold, cardio, sleep)
/// exactly as Node-RED did with flow.get/flow.set and context.get/context.set.
class NodeRedHealthEngine {
  // History windows
  static const _cardioWindowMs = 10 * 60 * 1000; // Node-RED 원본: 10분
  static const _sleepWindowMs = 10 * 60 * 1000; // Node-RED 원본: 10분

  // Mold state
  int _moldHighSinceMs = 0;

  // Cardio history
  final List<PmHistoryEntry> _cardioHist = [];

  // Sleep history
  final List<SleepHistoryEntry> _sleepHist = [];

  // Log-linear regression k values (exact Node-RED algorithm)
  double _kPm25 = 0.0;
  double _kCo2 = 0.0;
  double _r2Pm25 = 0.0;
  double _r2Co2 = 0.0;

  // 5-min sliding window buffers for k regression
  static const _kWindowMs = 300 * 1000; // 5 minutes
  static const _kBufferLimit = 400;
  static const _trendBufferLimit = 120;
  static const _steadySlopeSampleCount = 6;
  static const _co2Baseline = 420.0; // outdoor background CO2
  final List<_KSample> _pm25Buffer = [];
  final List<_KSample> _co2Buffer = [];
  final List<_KSample> _pm25TrendBuffer = [];
  final List<_KSample> _co2TrendBuffer = [];
  final List<_KSample> _tvocTrendBuffer = [];

  // External (KMA) weather data for outdoor apparent temp
  double? _externalTemp;
  double? _externalHumidity;
  double? _externalWindSpeed;

  /// Set outdoor weather data from ExternalApiService.
  void setExternalWeather({
    double? temperature,
    double? humidity,
    double? windSpeed,
  }) {
    _externalTemp = temperature;
    _externalHumidity = humidity;
    _externalWindSpeed = windSpeed;
  }

  /// Compute ALL health data from raw sensor values.
  /// Returns a JSON map that can be merged into the snapshot JSON.
  Map<String, dynamic> compute({
    required double? pm25,
    required double? co2,
    required double? tvoc,
    required double? temp,
    required double? humidity,
    int? timestampMs,
  }) {
    final result = <String, dynamic>{};
    final nowMs = timestampMs ?? DateTime.now().millisecondsSinceEpoch;

    // ── Update k via log-linear regression (exact Node-RED algorithm) ──
    _updateKRegression(pm25, co2, nowMs);
    _updateTrendBuffers(pm25, co2, tvoc, nowMs);

    // ── Derived metrics (IAQI, Dew Point, Discomfort Index) ──
    final derived = <String, dynamic>{};

    if (temp != null && humidity != null) {
      final dp = calculateDewPoint(temp, humidity);
      final di = calculateDiscomfortIndex(temp, humidity);
      derived['dewPoint'] = (dp * 10).roundToDouble() / 10;
      derived['discomfortIndex'] = di;
    }

    if (pm25 != null && co2 != null && temp != null && humidity != null) {
      final iaqi = calculate_iaqi(
        co2: co2,
        pm25: pm25,
        // Keep IAQI ventilation term identical to server policy (CO2-based k).
        k: math.max(_kCo2, 0.0),
        voc: tvoc ?? 100.0,
        temp: temp,
        humi: humidity,
      );

      derived['iaqi'] = iaqi;
      derived['primary_grade'] = iaqi['primary_grade'];
      derived['sub_level'] = iaqi['sub_level'];
      derived['display_iaqi'] = iaqi['display_iaqi'];
      derived['base_display_iaqi'] = iaqi['base_display_iaqi'];
      derived['thermal_penalty'] = iaqi['thermal_penalty'];
      derived['thermal_deviation'] = iaqi['thermal_deviation'];
      derived['thermal_temp_deviation'] = iaqi['thermal_temp_deviation'];
      derived['thermal_humidity_deviation'] =
          iaqi['thermal_humidity_deviation'];
      derived['m_score'] = iaqi['m_score'];
      derived['e_score'] = iaqi['e_score'];
      derived['i_score'] = iaqi['i_score'];

      // IAQI score used by overview/trace cards (linear display scale).
      final displayIaqi = (iaqi['display_iaqi'] as num?)?.toDouble() ?? 0.0;
      derived['iaqiScore'] = _round3(displayIaqi);
      derived['aqiLevel'] = iaqi['primary_grade'];
      derived['aqiCategory'] = iaqi['sub_level'] ?? iaqi['primary_grade'];
    }

    if (derived.isNotEmpty) {
      result['derived'] = derived;
    }

    // ── Child mode ──
    final child = <String, dynamic>{};

    if (co2 != null) {
      child['focus'] = computeChildFocus(co2);
    }

    if (temp != null && humidity != null && tvoc != null) {
      child['respiratory'] = computeChildRespiratory(temp, humidity, tvoc);
    }

    if (co2 != null && humidity != null) {
      child['infection'] = computeChildInfection(co2, humidity);
    }

    if (humidity != null && pm25 != null) {
      final moldResult = computeChildMold(
        humidity,
        pm25,
        moldHighSinceMs: _moldHighSinceMs,
        nowMs: nowMs,
      );
      _moldHighSinceMs = moldResult['_updatedHighSince'] as int;
      moldResult.remove('_updatedHighSince');
      child['mold'] = moldResult;
    }

    if (child.isNotEmpty) {
      result['child'] = child;
    }

    // ── Senior mode ──
    final senior = <String, dynamic>{};

    // Cardio — push to history and compute
    if (pm25 != null) {
      _cardioHist.add(PmHistoryEntry(nowMs, pm25, _kPm25));
      _cardioHist.removeWhere((e) => nowMs - e.ts > _cardioWindowMs);
      senior['cardio'] = computeSeniorCardio(_cardioHist);

      senior['pmExposure'] = computeSeniorPmExposure(pm25);
    }

    // Sleep — push to history and compute
    if (co2 != null) {
      _sleepHist.add(SleepHistoryEntry(nowMs, co2, tvoc));
      _sleepHist.removeWhere((e) => nowMs - e.ts > _sleepWindowMs);
      senior['sleep'] = computeSeniorSleep(_sleepHist);
    }

    // Ventilation
    senior['ventilation'] = computeSeniorVentilation(_kPm25);

    if (senior.isNotEmpty) {
      result['senior'] = senior;
    }

    final pmSlopePerMin = _medianSlopePerMinute(_pm25TrendBuffer);
    final co2SlopePerMin = _medianSlopePerMinute(_co2TrendBuffer);
    final tvocSlopePerMin = _medianSlopePerMinute(_tvocTrendBuffer);

    // ── Purification mode ──
    if (pm25 != null && co2 != null) {
      final cadr = computePurificationCadr(
        pm25,
        co2,
        tvoc: tvoc,
        pmSlopePerMin: pmSlopePerMin,
        co2SlopePerMin: co2SlopePerMin,
        tvocSlopePerMin: tvocSlopePerMin,
        kPm25: _kPm25,
        kCo2: _kCo2,
        r2Pm25: _r2Pm25,
        r2Co2: _r2Co2,
      );
      final ipi = computeIpi(_kCo2, _kPm25);
      final vent = computePurificationVentilation(co2);

      result['purification'] = {
        'cadr': cadr,
        'ipi': ipi,
        'ventilation': vent,
      };
    }

    // ── Seasonal apparent temp (uses OUTDOOR KMA data) ──
    final outTemp = _externalTemp;
    final outHumidity = _externalHumidity;
    final outWind = _externalWindSpeed;
    if (outTemp != null && outHumidity != null) {
      result['seasonalApparent'] = _computeSeasonalApparent(
        outTemp,
        outHumidity,
        outWind ?? 2.0,
      );
    }

    // ── Apparent temp scalar (uses OUTDOOR KMA data) ──
    if (outTemp != null && outHumidity != null) {
      result['apparentTemp'] =
          _computeApparentTempValue(outTemp, outHumidity, outWind ?? 2.0);
    }

    // ── Alerts ──
    if (pm25 != null && co2 != null && humidity != null) {
      final moldLevel =
          (child['mold'] as Map<String, dynamic>?)?['riskLevel'] as int? ?? 0;
      result['alerts'] = computeAlerts(pm25, co2, humidity, moldLevel);
    }

    return result;
  }

  /// Log-linear regression k-value calculation — exact Node-RED algorithm.
  /// Uses 5-min sliding window with OLS on ln(C) vs time.
  void _updateKRegression(double? pm25, double? co2, int nowMs) {
    if (pm25 != null) {
      _pm25Buffer.removeWhere((e) => nowMs - e.t > _kWindowMs);
      _pm25Buffer.add(_KSample(nowMs, pm25));
      if (_pm25Buffer.length > _kBufferLimit) {
        _pm25Buffer.removeRange(0, _pm25Buffer.length - _kBufferLimit);
      }
      final result = _logLinearRegression(
        _pm25Buffer,
        (s) => math.log(math.max(s.v, 1e-6)),
        checkNoise: true, // Node-RED: skip if maxVal < 0.99
      );
      _kPm25 = result.k;
      _r2Pm25 = result.r2;
    }
    if (co2 != null) {
      _co2Buffer.removeWhere((e) => nowMs - e.t > _kWindowMs);
      final excess = math.max(co2 - _co2Baseline, 10.0);
      _co2Buffer.add(_KSample(nowMs, excess));
      if (_co2Buffer.length > _kBufferLimit) {
        _co2Buffer.removeRange(0, _co2Buffer.length - _kBufferLimit);
      }
      final result = _logLinearRegression(
        _co2Buffer,
        (s) => math.log(math.max(s.v, 1e-6)),
      );
      _kCo2 = result.k;
      _r2Co2 = result.r2;
    }
  }

  void _updateTrendBuffers(double? pm25, double? co2, double? tvoc, int nowMs) {
    if (pm25 != null) {
      _appendTrendSample(_pm25TrendBuffer, nowMs, pm25);
    }
    if (co2 != null) {
      _appendTrendSample(_co2TrendBuffer, nowMs, co2);
    }
    if (tvoc != null) {
      _appendTrendSample(_tvocTrendBuffer, nowMs, tvoc);
    }
  }

  void _appendTrendSample(List<_KSample> buffer, int nowMs, double value) {
    buffer.removeWhere((e) => nowMs - e.t > _kWindowMs);
    buffer.add(_KSample(nowMs, value));
    if (buffer.length > _trendBufferLimit) {
      buffer.removeRange(0, buffer.length - _trendBufferLimit);
    }
  }

  double? _medianSlopePerMinute(List<_KSample> buffer) {
    if (buffer.length < 2) {
      return null;
    }

    final start = math.max(0, buffer.length - _steadySlopeSampleCount);
    final recent = buffer.sublist(start);
    if (recent.length < 2) {
      return null;
    }

    final slopes = <double>[];
    for (var i = 1; i < recent.length; i++) {
      final prev = recent[i - 1];
      final curr = recent[i];
      final dtMs = curr.t - prev.t;
      if (dtMs <= 0) {
        continue;
      }
      final slopePerMin = ((curr.v - prev.v) * 60000.0) / dtMs;
      slopes.add(slopePerMin);
    }

    return _medianDouble(slopes);
  }

  static const _kMinSamples = 15; // Node-RED 원본: MIN_SAMPLES = 15
  static const _noiseThreshold = 0.99; // Node-RED 원본: NOISE_THRESHOLD = 0.99

  static ({double k, double r2}) _logLinearRegression(
    List<_KSample> buffer,
    double Function(_KSample) lnValue, {
    bool checkNoise = false,
  }) {
    if (buffer.length < _kMinSamples) return (k: 0.0, r2: 0.0);

    // Noise threshold check (Node-RED: skip if maxVal < 0.99)
    if (checkNoise) {
      final maxVal = buffer.map((e) => e.v).reduce(math.max);
      if (maxVal < _noiseThreshold) return (k: 0.0, r2: 0.0);
    }

    final firstTs = buffer.first.t;
    double sumX = 0, sumY = 0, sumXY = 0, sumXX = 0, sumYY = 0;
    final n = buffer.length;

    for (final entry in buffer) {
      final x = (entry.t - firstTs) / 3600000.0; // hours
      final y = lnValue(entry);
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumXX += x * x;
      sumYY += y * y;
    }

    final denom = (n * sumXX) - (sumX * sumX);
    if (denom == 0) return (k: 0.0, r2: 0.0);

    final slope = ((n * sumXY) - (sumX * sumY)) / denom;
    final intercept = (sumY - slope * sumX) / n;
    final ssTot = sumYY - ((sumY * sumY) / n);
    double ssRes = 0;
    for (final entry in buffer) {
      final x = (entry.t - firstTs) / 3600000.0;
      final y = lnValue(entry);
      final fitted = slope * x + intercept;
      ssRes += (y - fitted) * (y - fitted);
    }
    final r2 = ssTot == 0 ? 1.0 : math.max(0.0, 1.0 - (ssRes / ssTot));
    final kRaw = double.parse((-slope).toStringAsFixed(3));

    return (k: kRaw, r2: r2);
  }

  Map<String, dynamic> _computeSeasonalApparent(
    double temp,
    double humidity,
    double windSpeed,
  ) {
    final month = DateTime.now().month;
    final isSummer = month >= 5 && month <= 9;

    if (isSummer) {
      // Stull wet-bulb based apparent temperature
      final ta = temp;
      final rh = humidity;
      final tw = ta * _atan(0.151977 * math.sqrt(rh + 8.313659)) +
          _atan(ta + rh) -
          _atan(rh - 1.676331) +
          0.00391838 * math.pow(rh, 1.5) * _atan(0.023101 * rh) -
          4.686035;
      final tw2 = tw * tw;
      final twTa = tw * ta;
      final apparent = -0.2442 +
          (0.55399 * tw) +
          (0.45535 * ta) -
          (0.0022 * tw2) +
          (0.00278 * twTa) +
          3.0;
      final rounded = double.parse(apparent.toStringAsFixed(1));

      String risk, color;
      if (rounded >= 38) {
        risk = '위험';
        color = 'red';
      } else if (rounded >= 35) {
        risk = '경고';
        color = 'orange';
      } else if (rounded >= 33) {
        risk = '주의';
        color = 'yellow';
      } else {
        risk = '관심';
        color = 'green';
      }

      return {
        'seasonMode': 'summer',
        'summer': {
          'apparentTemp': rounded,
          'riskMessage': risk,
          'riskColor': color,
        },
      };
    } else {
      // Winter wind chill
      final ta = temp;
      final vMs = windSpeed;
      double apparent;
      if (ta <= 10 && vMs >= 1.3) {
        final vKmh = vMs * 3.6;
        final vPow = math.pow(vKmh, 0.16);
        apparent =
            13.12 + (0.6215 * ta) - (11.37 * vPow) + (0.3965 * ta * vPow);
      } else {
        apparent = ta;
      }
      final rounded = double.parse(apparent.toStringAsFixed(1));

      String message, color;
      if (rounded <= -15) {
        message = '매우 위험';
        color = 'red';
      } else if (rounded <= -10) {
        message = '동상 위험';
        color = 'orange';
      } else if (rounded <= -5) {
        message = '손발 시림';
        color = 'yellow';
      } else if (rounded <= 10) {
        message = '쌀쌀함';
        color = 'blue';
      } else {
        message = '온화함';
        color = 'green';
      }

      return {
        'seasonMode': 'winter',
        'winter': {
          'apparentTemp': rounded,
          'message': message,
          'color': color,
          'isWinterCalc': ta <= 10 && vMs >= 1.3,
          'realTemp': ta,
          'realWind': vMs,
        },
      };
    }
  }

  double _computeApparentTempValue(
    double temp,
    double humidity,
    double windSpeed,
  ) {
    final month = DateTime.now().month;
    final isSummer = month >= 5 && month <= 9;

    if (isSummer) {
      final ta = temp;
      final rh = humidity;
      final tw = ta * _atan(0.151977 * math.sqrt(rh + 8.313659)) +
          _atan(ta + rh) -
          _atan(rh - 1.676331) +
          0.00391838 * math.pow(rh, 1.5) * _atan(0.023101 * rh) -
          4.686035;
      return -0.2442 +
          (0.55399 * tw) +
          (0.45535 * ta) -
          (0.0022 * tw * tw) +
          (0.00278 * tw * ta) +
          3.0;
    } else {
      final ta = temp;
      final vMs = windSpeed;
      if (ta <= 10 && vMs >= 1.3) {
        final vKmh = vMs * 3.6;
        final vPow = math.pow(vKmh, 0.16);
        return 13.12 + (0.6215 * ta) - (11.37 * vPow) + (0.3965 * ta * vPow);
      }
      return ta;
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  PRIVATE HELPERS
// ════════════════════════════════════════════════════════════════════════════

double _atan(double x) => x.isNaN ? 0.0 : math.atan(x);

/// Sample for k regression buffer.
class _KSample {
  final int t; // timestamp ms
  final double v; // value (PM2.5 or CO2-excess)
  _KSample(this.t, this.v);
}

double? _medianDouble(List<double> values) {
  if (values.isEmpty) {
    return null;
  }
  final sorted = List<double>.of(values)..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[mid];
  }
  return (sorted[mid - 1] + sorted[mid]) / 2.0;
}

String _getKLevel(double k) {
  if (k >= 1.0) return '급속감소';
  if (k >= 0.2) return '자연감소';
  if (k > -0.1) return '정체';
  return '축적중';
}

String _getKLevelCode(double k) {
  if (k >= 1.0) return 'HIGH_POS';
  if (k >= 0.2) return 'LOW_POS';
  if (k > -0.1) return 'ZERO';
  return 'NEGATIVE';
}

String _getTrend(double k) {
  if (k >= 1.5) return 'fast_drop';
  if (k >= 0.5) return 'slow_drop';
  if (k >= -0.05) return 'flat';
  return 'rising';
}
