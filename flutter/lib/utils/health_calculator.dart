import 'dart:math';

class RespiratoryHealthResult {
  final double score;
  final String level;
  final String color;

  const RespiratoryHealthResult({
    required this.score,
    required this.level,
    required this.color,
  });
}

RespiratoryHealthResult calculateRespiratoryHealth({
  required double temperature,
  required double humidity,
  required double tvoc,
}) {
  final double tempScore = 100 - (temperature - 23).abs() * 4;
  final double humidityScore = 100 - (humidity - 45).abs() * 2.5;
  final double vocPenalty = min(tvoc / 400, 1) * 30;

  double score = (tempScore * 0.4) + (humidityScore * 0.4) + ((100 - vocPenalty) * 0.2);
  score = _clampToRange(score, 0, 100);

  final _LevelColor band = _bandForScore(score);
  return RespiratoryHealthResult(score: score, level: band.level, color: band.color);
}

class ImmuneRiskResult {
  final double risk;
  final String level;
  final String color;

  const ImmuneRiskResult({
    required this.risk,
    required this.level,
    required this.color,
  });
}

ImmuneRiskResult calculateImmuneRisk({
  required double co2,
  required double humidity,
}) {
  final double co2Penalty = max(0, co2 - 800) / 8;
  final double humidityPenalty = (humidity - 45).abs();
  double risk = 30 + co2Penalty + humidityPenalty;
  risk = _clampToRange(risk, 0, 100);

  final _LevelColor band = _bandForRisk(risk);
  return ImmuneRiskResult(risk: risk, level: band.level, color: band.color);
}

class ConcentrationResult {
  final double score;
  final String level;
  final String color;
  final double co2Value;

  const ConcentrationResult({
    required this.score,
    required this.level,
    required this.color,
    required this.co2Value,
  });
}

ConcentrationResult calculateConcentration({required double co2}) {
  double score = 100 - max(0, co2 - 600) / 10;
  score = _clampToRange(score, 0, 100);

  final _LevelColor band = _bandForScore(score);
  return ConcentrationResult(
    score: score,
    level: band.level,
    color: band.color,
    co2Value: co2,
  );
}

class CardiovascularResult {
  final double score;
  final String level;
  final String color;
  final String recommendation;

  const CardiovascularResult({
    required this.score,
    required this.level,
    required this.color,
    required this.recommendation,
  });
}

CardiovascularResult calculateCardiovascular({required double pm25}) {
  final double penalty = pm25 * 2;
  double score = 100 - penalty;
  score = _clampToRange(score, 0, 100);

  final _LevelColor band = _bandForScore(score);
  String recommendation;
  if (pm25 <= 15) {
    recommendation = '공기질이 심혈관 보호에 이상적입니다.';
  } else if (pm25 <= 25) {
    recommendation = '청정기를 중간 단계로 두고 가끔 환기하세요.';
  } else if (pm25 <= 35) {
    recommendation = '격한 활동을 줄이고 정화 강도를 높이세요.';
  } else {
    recommendation = '청정기를 강하게 가동하고 실외 노출을 줄이세요.';
  }

  return CardiovascularResult(
    score: score,
    level: band.level,
    color: band.color,
    recommendation: recommendation,
  );
}

class CardiovascularRiskResult {
  final String level;
  final String riskLevel;
  final String action;
  final String color;

  const CardiovascularRiskResult({
    required this.level,
    required this.riskLevel,
    required this.action,
    required this.color,
  });
}

CardiovascularRiskResult calculateCardiovascularRisk({required double pm25}) {
  if (pm25 >= 40) {
    return const CardiovascularRiskResult(
      level: '주의',
      riskLevel: '높음',
      action: '청정기를 최대로 가동하고 실내에서 휴식하세요.',
      color: 'red',
    );
  } else if (pm25 >= 25) {
    return const CardiovascularRiskResult(
      level: '경고',
      riskLevel: '상승',
      action: '실외 활동을 줄이고 짧게 환기하세요.',
      color: 'orange',
    );
  } else if (pm25 >= 15) {
    return const CardiovascularRiskResult(
      level: '관찰',
      riskLevel: '보통',
      action: '정화 모드를 유지하며 추이를 살펴보세요.',
      color: 'yellow',
    );
  } else {
    return const CardiovascularRiskResult(
      level: '안정',
      riskLevel: '낮음',
      action: '평소처럼 생활해도 괜찮습니다.',
      color: 'green',
    );
  }
}

class SleepQualityResult {
  final double score;
  final String level;
  final String color;
  final bool isNight;

  const SleepQualityResult({
    required this.score,
    required this.level,
    required this.color,
    required this.isNight,
  });
}

SleepQualityResult calculateSleepQuality({
  required double co2,
  required double tvoc,
}) {
  final double co2Penalty = max(0, co2 - 900) / 12;
  final double vocPenalty = min(tvoc / 500, 1) * 25;
  double score = 90 - co2Penalty - vocPenalty;
  score = _clampToRange(score, 0, 100);

  final _LevelColor band = _bandForScore(score);
  final int hour = DateTime.now().hour;
  final bool isNight = hour >= 20 || hour < 6;

  return SleepQualityResult(
    score: score,
    level: band.level,
    color: band.color,
    isNight: isNight,
  );
}

class ApparentTempResult {
  final String temp;
  final String risk;
  final String color;
  final String recommendation;

  const ApparentTempResult({
    required this.temp,
    required this.risk,
    required this.color,
    required this.recommendation,
  });
}

/// Node-RED 체감온도 통합 계산과 동일한 로직
/// 여름 (5~9월): Stull 습구온도 기반 체감온도
/// 겨울 (10~4월): 체감풍냉 공식 (Ta ≤ 10°C, V ≥ 1.3m/s일 때)
ApparentTempResult calculateApparentTemp({
  required double temperature,
  required double humidity,
  double? windSpeed, // m/s, 풍속 데이터 (겨울철 체감풍냉용)
}) {
  final int month = DateTime.now().month;
  final bool isSummer = month >= 5 && month <= 9;
  
  double apparentTemp;
  
  if (isSummer) {
    // ────────────────────────────────────────
    // 여름철: Stull 습구온도 기반 체감온도
    // ────────────────────────────────────────
    final double Ta = temperature;
    final double RH = humidity;
    
    // Stull 습구온도(Tw) 공식
    final double Tw = Ta * _atan(0.151977 * _pow(RH + 8.313659, 0.5)) +
        _atan(Ta + RH) - _atan(RH - 1.676331) +
        0.00391838 * _pow(RH, 1.5) * _atan(0.023101 * RH) - 4.686035;
    
    final double Tw2 = Tw * Tw;
    final double TwTa = Tw * Ta;
    
    // 여름철 체감온도 공식
    apparentTemp = -0.2442 + (0.55399 * Tw) + (0.45535 * Ta) - 
                   (0.0022 * Tw2) + (0.00278 * TwTa) + 3.0;
  } else {
    // ────────────────────────────────────────
    // 겨울철: 체감풍냉 공식 (Wind Chill)
    // ────────────────────────────────────────
    final double Ta = temperature;
    final double vMs = windSpeed ?? 2.0; // 기본 풍속 2 m/s
    
    // 체감풍냉 적용 조건: Ta ≤ 10°C, V ≥ 1.3 m/s
    if (Ta <= 10 && vMs >= 1.3) {
      final double vKmh = vMs * 3.6;
      final double vPow = _pow(vKmh, 0.16);
      apparentTemp = 13.12 + (0.6215 * Ta) - (11.37 * vPow) + (0.3965 * Ta * vPow);
    } else {
      // 체감풍냉 조건 미충족 시 실제 온도 사용
      apparentTemp = Ta;
    }
  }
  
  final double rounded = double.parse(apparentTemp.toStringAsFixed(1));

  String risk;
  String color;
  String recommendation;
  
  if (isSummer) {
    // 여름철 기준 (Node-RED heatRisk와 동일)
    if (rounded >= 38) {
      risk = '위험';
      color = 'red';
      recommendation = '옥외 활동 중지, 실내에서 냉방 유지하세요.';
    } else if (rounded >= 35) {
      risk = '경고';
      color = 'orange';
      recommendation = '옥외 활동 자제, 충분한 수분 섭취하세요.';
    } else if (rounded >= 33) {
      risk = '주의';
      color = 'yellow';
      recommendation = '야외 활동 줄이고 그늘에서 휴식하세요.';
    } else {
      risk = '관심';
      color = 'green';
      recommendation = '온열질환에 주의하며 수분을 섭취하세요.';
    }
  } else {
    // 겨울철 기준 (Node-RED windChill와 동일)
    if (rounded <= -15) {
      risk = '매우 위험';
      color = 'red';
      recommendation = '피부 노출 금지, 외출을 삼가세요.';
    } else if (rounded <= -10) {
      risk = '동상 위험';
      color = 'orange';
      recommendation = '외출 자제, 보온에 각별히 신경쓰세요.';
    } else if (rounded <= -5) {
      risk = '손발 시림';
      color = 'yellow';
      recommendation = '보온장갑 필수, 따뜻하게 입으세요.';
    } else if (rounded <= 10) {
      risk = '쌀쌀함';
      color = 'blue';
      recommendation = '겹겹이 따뜻하게 입으세요.';
    } else {
      risk = '온화함';
      color = 'green';
      recommendation = '상태가 안정적입니다.';
    }
  }

  return ApparentTempResult(
    temp: rounded.toStringAsFixed(1),
    risk: risk,
    color: color,
    recommendation: recommendation,
  );
}

/// Node-RED에서 이미 계산된 체감온도 값을 받아 UI 매핑만 수행
/// 직접 계산 없이 Node-RED 값 사용
ApparentTempResult getApparentTempDisplay(double? nodeRedApparentTemp) {
  if (nodeRedApparentTemp == null) {
    return const ApparentTempResult(
      temp: '—',
      risk: '데이터 없음',
      color: 'grey',
      recommendation: 'Node-RED 데이터 수신 대기 중...',
    );
  }
  
  final double rounded = double.parse(nodeRedApparentTemp.toStringAsFixed(1));
  final int month = DateTime.now().month;
  final bool isSummer = month >= 5 && month <= 9;
  
  String risk;
  String color;
  String recommendation;
  
  if (isSummer) {
    if (rounded >= 38) {
      risk = '위험';
      color = 'red';
      recommendation = '옥외 활동 중지, 실내에서 냉방 유지하세요.';
    } else if (rounded >= 35) {
      risk = '경고';
      color = 'orange';
      recommendation = '옥외 활동 자제, 충분한 수분 섭취하세요.';
    } else if (rounded >= 33) {
      risk = '주의';
      color = 'yellow';
      recommendation = '야외 활동 줄이고 그늘에서 휴식하세요.';
    } else {
      risk = '관심';
      color = 'green';
      recommendation = '온열질환에 주의하며 수분을 섭취하세요.';
    }
  } else {
    if (rounded <= -15) {
      risk = '매우 위험';
      color = 'red';
      recommendation = '피부 노출 금지, 외출을 삼가세요.';
    } else if (rounded <= -10) {
      risk = '동상 위험';
      color = 'orange';
      recommendation = '외출 자제, 보온에 각별히 신경쓰세요.';
    } else if (rounded <= -5) {
      risk = '손발 시림';
      color = 'yellow';
      recommendation = '보온장갑 필수, 따뜻하게 입으세요.';
    } else if (rounded <= 10) {
      risk = '쌀쌀함';
      color = 'blue';
      recommendation = '겹겹이 따뜻하게 입으세요.';
    } else {
      risk = '온화함';
      color = 'green';
      recommendation = '상태가 안정적입니다.';
    }
  }
  
  return ApparentTempResult(
    temp: rounded.toStringAsFixed(1),
    risk: risk,
    color: color,
    recommendation: recommendation,
  );
}

// dart:math 헬퍼 (이미 import됨)
double _atan(double x) => x.isNaN ? 0.0 : atan(x);
double _pow(double x, double exponent) => (x.isNaN || x < 0) ? 0.0 : pow(x, exponent).toDouble();

class PurificationRateResult {
  final String k;
  final String level;
  final String color;

  const PurificationRateResult({
    required this.k,
    required this.level,
    required this.color,
  });
}

PurificationRateResult calculatePurificationRate({required double pm25}) {
  double k;
  if (pm25 >= 35) {
    k = 0.3;
  } else if (pm25 >= 25) {
    k = 0.8;
  } else if (pm25 >= 15) {
    k = 1.5;
  } else if (pm25 >= 10) {
    k = 2.2;
  } else {
    k = 3.0;
  }

  String level;
  String color;
  if (k >= 2.0) {
    level = 'S등급';
    color = 'green';
  } else if (k >= 1.0) {
    level = 'A등급';
    color = 'yellow';
  } else if (k >= 0.5) {
    level = 'B등급';
    color = 'orange';
  } else {
    level = 'C등급';
    color = 'red';
  }

  return PurificationRateResult(
    k: k.toStringAsFixed(1),
    level: level,
    color: color,
  );
}

class CADRIndexResult {
  final String cadr;
  final String level;
  final String color;

  const CADRIndexResult({
    required this.cadr,
    required this.level,
    required this.color,
  });
}

CADRIndexResult calculateCADRIndex({required double pm25}) {
  final PurificationRateResult rate = calculatePurificationRate(pm25: pm25);
  final double k = double.tryParse(rate.k) ?? 0;
  const double volume = 48; // Typical living room size in m³.
  final double cadr = k * volume;

  String level;
  String color;
  if (cadr >= 150) {
    level = '탁월';
    color = 'green';
  } else if (cadr >= 100) {
    level = '양호';
    color = 'yellow';
  } else if (cadr >= 60) {
    level = '보통';
    color = 'orange';
  } else {
    level = '부족';
    color = 'red';
  }

  return CADRIndexResult(
    cadr: cadr.toStringAsFixed(0),
    level: level,
    color: color,
  );
}

class IpiRiskResult {
  final double t90Minutes;
  final double kValue;
  final int grade;
  final String level;
  final String color;
  final String description;

  const IpiRiskResult({
    required this.t90Minutes,
    required this.kValue,
    required this.grade,
    required this.level,
    required this.color,
    required this.description,
  });
}

IpiRiskResult calculateIpiRisk({required double pm25}) {
  final PurificationRateResult rate = calculatePurificationRate(pm25: pm25);
  final double k = double.tryParse(rate.k) ?? 0;

  if (k <= 0) {
    return const IpiRiskResult(
      t90Minutes: double.infinity,
      kValue: 0,
      grade: 0,
      level: '데이터 없음',
      color: 'grey',
      description: '유효한 정화속도 값을 받지 못했습니다.',
    );
  }

  final double t90Minutes = (log(10) / k) * 60;

  int grade;
  String level;
  String color;
  String description;
  if (k >= 3.0) {
    grade = 3;
    level = '안심';
    color = 'green';
    description = '빠른 회복 — 잔류 위험 낮음';
  } else if (k >= 1.0) {
    grade = 2;
    level = '보통';
    color = 'yellow';
    description = '보통 회복 — 관리 필요';
  } else {
    grade = 1;
    level = '경고';
    color = 'red';
    description = '느린 회복 — 잔류 위험 높음';
  }

  return IpiRiskResult(
    t90Minutes: double.parse(t90Minutes.toStringAsFixed(0)),
    kValue: double.parse(k.toStringAsFixed(2)),
    grade: grade,
    level: level,
    color: color,
    description: description,
  );
}

class _LevelColor {
  final String level;
  final String color;

  const _LevelColor(this.level, this.color);
}

_LevelColor _bandForScore(double score) {
  if (score >= 80) {
    return const _LevelColor('탁월', 'green');
  } else if (score >= 60) {
    return const _LevelColor('양호', 'yellow');
  } else if (score >= 40) {
    return const _LevelColor('주의', 'orange');
  } else {
    return const _LevelColor('위험', 'red');
  }
}

_LevelColor _bandForRisk(double risk) {
  if (risk >= 80) {
    return const _LevelColor('심각', 'red');
  } else if (risk >= 60) {
    return const _LevelColor('높음', 'orange');
  } else if (risk >= 40) {
    return const _LevelColor('보통', 'yellow');
  } else {
    return const _LevelColor('낮음', 'green');
  }
}

double _clampToRange(double value, double min, double max) {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}
