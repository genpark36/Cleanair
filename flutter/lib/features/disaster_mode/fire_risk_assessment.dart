import 'dart:math' as math;

import '../../models/air_quality_snapshot.dart';

enum FireRiskLevel {
  normal,
  notice,
  warning,
  strongWarning,
  fireSuspected,
  coOnly,
}

class FireRiskAssessment {
  const FireRiskAssessment({
    required this.level,
    required this.levelLabel,
    required this.headline,
    required this.summary,
    required this.totalScore,
    required this.riskCount,
    required this.cautionCount,
    required this.persistenceGrade,
    required this.candidateCount,
    required this.fireCandidate,
    required this.coConnected,
    required this.coPmTogether,
    required this.metrics,
    required this.actions,
    required this.updatedAt,
  });

  final FireRiskLevel level;
  final String levelLabel;
  final String headline;
  final String summary;
  final double totalScore;
  final int riskCount;
  final int cautionCount;
  final int persistenceGrade;
  final int candidateCount;
  final bool fireCandidate;
  final bool coConnected;
  final bool coPmTogether;
  final List<FireMetricAssessment> metrics;
  final List<String> actions;
  final DateTime? updatedAt;

  bool get isRisky => level != FireRiskLevel.normal;
  bool get isUrgent =>
      level == FireRiskLevel.fireSuspected || level == FireRiskLevel.coOnly;
  String get modeLabel => coConnected ? 'CO 확장형' : '기본형';

  String get persistenceLabel {
    return switch (persistenceGrade) {
      2 => '반복 감지',
      1 => '확인 필요',
      _ => '지속 변화 없음',
    };
  }

  String get copyText {
    final activeMetrics = metrics
        .where((metric) => metric.score >= 0.5)
        .map((metric) =>
            '${metric.label}: 현재 ${_fmt(metric.current)}${metric.unit}, 5분 변화 ${_fmt(metric.rise5)}${metric.unit}, 점수 ${_fmt(metric.score)}')
        .join('\n');
    return [
      '방재모드: $levelLabel',
      '판단 모드: $modeLabel',
      summary,
      '위험점수 ${_fmt(totalScore)} · 동시에 나빠진 지표 $riskCount개 · $persistenceLabel',
      if (activeMetrics.isNotEmpty) activeMetrics,
      '권장 조치: ${actions.join(' / ')}',
    ].join('\n');
  }

  static FireRiskAssessment fromHistory(List<AirQualitySnapshot> history) {
    final samples = history.where(_hasAnyFireMetric).toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (samples.isEmpty) {
      return const FireRiskAssessment(
        level: FireRiskLevel.normal,
        levelLabel: '정상',
        headline: '센서값 대기 중',
        summary: '방재 판단에 필요한 센서값을 기다리는 중입니다.',
        totalScore: 0,
        riskCount: 0,
        cautionCount: 0,
        persistenceGrade: 0,
        candidateCount: 0,
        fireCandidate: false,
        coConnected: false,
        coPmTogether: false,
        metrics: <FireMetricAssessment>[],
        actions: ['센서 연결 상태 확인'],
        updatedAt: null,
      );
    }

    final current = _averageWindow(
      samples,
      samples.last.timestamp,
      const Duration(seconds: 60),
    );
    final previous = _averageWindow(
      samples,
      samples.last.timestamp.subtract(const Duration(minutes: 5)),
      const Duration(seconds: 60),
    );
    final tempBase = _averageWindow(
      samples,
      samples.last.timestamp.subtract(const Duration(minutes: 15)),
      const Duration(minutes: 30),
    );
    final evaluation = _evaluate(
      current: current,
      previous: previous,
      tempBase: tempBase,
    );
    final candidateCount = _candidateCount(samples);
    final persistenceGrade = candidateCount >= 4
        ? 2
        : candidateCount >= 2
            ? 1
            : 0;
    return _withLevel(
      evaluation: evaluation,
      candidateCount: candidateCount,
      persistenceGrade: persistenceGrade,
      updatedAt: samples.last.timestamp,
    );
  }

  static bool _hasAnyFireMetric(AirQualitySnapshot snapshot) {
    return snapshot.pm25 != null ||
        snapshot.tvoc != null ||
        snapshot.temperature != null ||
        snapshot.nox != null ||
        snapshot.co != null ||
        snapshot.co2 != null;
  }

  static _FireEvaluation _evaluate({
    required _FireAverages current,
    required _FireAverages previous,
    required _FireAverages tempBase,
  }) {
    final pm = FireMetricAssessment(
      key: 'pm25',
      label: 'PM2.5',
      unit: ' µg/m³',
      current: current.pm25,
      rise5: _rise(current.pm25, previous.pm25),
      score: math.max(
        _score(_rise(current.pm25, previous.pm25), 35, 100),
        _score(current.pm25, 75, 150),
      ),
    );
    final voc = FireMetricAssessment(
      key: 'tvoc',
      label: 'TVOC',
      unit: ' index',
      current: current.tvoc,
      rise5: _rise(current.tvoc, previous.tvoc),
      score: math.max(
        _score(_rise(current.tvoc, previous.tvoc), 100, 200),
        _score(current.tvoc, 200, 350),
      ),
    );
    final temp = FireMetricAssessment(
      key: 'temperature',
      label: '온도',
      unit: '℃',
      current: current.temperature,
      rise5: _rise(current.temperature, previous.temperature),
      score: math.max(
        _score(_rise(current.temperature, previous.temperature), 3, 5),
        _score(_rise(current.temperature, tempBase.temperature), 5, 8),
      ),
    );
    final nox = FireMetricAssessment(
      key: 'nox',
      label: 'NOx',
      unit: ' index',
      current: current.nox,
      rise5: _rise(current.nox, previous.nox),
      score: math.max(
        _score(_rise(current.nox, previous.nox), 1, 2),
        _score(current.nox, 2, 5),
      ),
    );
    final co = FireMetricAssessment(
      key: 'co',
      label: 'CO',
      unit: ' ppm',
      current: current.co,
      rise5: _rise(current.co, previous.co),
      score: math.max(
        _score(_rise(current.co, previous.co), 5, 20),
        _score(current.co, 10, 35),
      ),
    );
    final co2 = FireMetricAssessment(
      key: 'co2',
      label: 'CO₂',
      unit: ' ppm',
      current: current.co2,
      rise5: _rise(current.co2, previous.co2),
      score: math.min(
        1.0,
        math.max(
          _score(_rise(current.co2, previous.co2), 300, 500),
          _score(current.co2, 1500, 2500),
        ),
      ),
      core: false,
    );

    final metrics = <FireMetricAssessment>[
      pm,
      voc,
      temp,
      nox,
      if (current.co != null) co,
      co2,
    ];
    final core = <FireMetricAssessment>[pm, voc, temp, nox];
    if (current.co != null) core.add(co);
    final riskCount = core.where((metric) => metric.danger).length;
    final cautionCount = metrics.where((metric) => metric.caution).length;
    final coConnected = current.co != null;
    final coPmTogether = coConnected && co.danger && pm.danger;
    final fireCandidate = coConnected
        ? riskCount >= 3 ||
            coPmTogether ||
            (co.danger && voc.danger && temp.danger)
        : riskCount >= 3;
    final biggestCoreScore = core.fold<double>(
      0,
      (maxScore, metric) => math.max(maxScore, metric.score),
    );
    final sameTimeBonus = riskCount >= 2 ? 0.5 * (riskCount - 1) : 0.0;
    final coPmBonus = coPmTogether ? 0.25 : 0.0;
    final co2Weight = coConnected ? 0.15 : 0.2;
    final totalScore =
        biggestCoreScore + sameTimeBonus + coPmBonus + co2Weight * co2.score;

    return _FireEvaluation(
      metrics: metrics,
      totalScore: totalScore,
      riskCount: riskCount,
      cautionCount: cautionCount,
      fireCandidate: fireCandidate,
      coConnected: coConnected,
      coPmTogether: coPmTogether,
      coOnly: coConnected && co.danger && riskCount == 1,
    );
  }

  static FireRiskAssessment _withLevel({
    required _FireEvaluation evaluation,
    required int candidateCount,
    required int persistenceGrade,
    required DateTime updatedAt,
  }) {
    final level = _levelFor(evaluation, persistenceGrade);
    final active = evaluation.metrics
        .where((metric) => metric.score >= 0.5)
        .toList(growable: false)
      ..sort((a, b) => b.score.compareTo(a.score));
    final leading = active.take(3).map((metric) => metric.label).join(', ');
    final summary = switch (level) {
      FireRiskLevel.fireSuspected => '화재가 강하게 의심되는 패턴입니다. 즉시 현장을 확인하세요.',
      FireRiskLevel.strongWarning => evaluation.coPmTogether
          ? 'CO와 미세먼지가 함께 상승했습니다. 연소기기나 타는 냄새가 있는지 확인해 주세요.'
          : '${leading.isEmpty ? '여러 지표' : leading} 변화가 반복되고 있습니다. 현장을 확인해 주세요.',
      FireRiskLevel.warning =>
        '${leading.isEmpty ? '공기질' : leading} 상태가 나쁩니다. 환기와 오염원을 확인해 주세요.',
      FireRiskLevel.notice => '공기질이 조금 안좋아졌습니다. 환기를 권장해요.',
      FireRiskLevel.coOnly => 'CO가 높습니다. 즉시 환기하고 연소기기 상태를 확인하세요.',
      FireRiskLevel.normal => '화재 의심 패턴이 아닙니다. 정상적인 상태입니다.',
    };
    return FireRiskAssessment(
      level: level,
      levelLabel: _levelLabel(level),
      headline: _headline(level),
      summary: summary,
      totalScore: evaluation.totalScore,
      riskCount: evaluation.riskCount,
      cautionCount: evaluation.cautionCount,
      persistenceGrade: persistenceGrade,
      candidateCount: candidateCount,
      fireCandidate: evaluation.fireCandidate,
      coConnected: evaluation.coConnected,
      coPmTogether: evaluation.coPmTogether,
      metrics: evaluation.metrics,
      actions: _actionsFor(level),
      updatedAt: updatedAt,
    );
  }

  static FireRiskLevel _levelFor(
    _FireEvaluation evaluation,
    int persistenceGrade,
  ) {
    if (evaluation.coOnly) return FireRiskLevel.coOnly;
    if (evaluation.fireCandidate && persistenceGrade == 2) {
      return FireRiskLevel.fireSuspected;
    }
    if (evaluation.coPmTogether ||
        (evaluation.riskCount >= 3 && persistenceGrade >= 1) ||
        (evaluation.riskCount >= 2 && persistenceGrade == 2)) {
      return FireRiskLevel.strongWarning;
    }
    if (evaluation.riskCount >= 1 || evaluation.totalScore >= 1.0) {
      return FireRiskLevel.warning;
    }
    if (evaluation.cautionCount >= 1 || evaluation.totalScore >= 0.5) {
      return FireRiskLevel.notice;
    }
    return FireRiskLevel.normal;
  }

  static String _levelLabel(FireRiskLevel level) {
    return switch (level) {
      FireRiskLevel.normal => '정상',
      FireRiskLevel.notice => '주의',
      FireRiskLevel.warning => '경고',
      FireRiskLevel.strongWarning => '강한 경고',
      FireRiskLevel.fireSuspected => '화재 의심',
      FireRiskLevel.coOnly => 'CO 위험',
    };
  }

  static String _headline(FireRiskLevel level) {
    return switch (level) {
      FireRiskLevel.normal => '화재 의심 패턴 없음',
      FireRiskLevel.notice => '공기질이 조금 안좋습니다',
      FireRiskLevel.warning => '공기질이 나쁩니다',
      FireRiskLevel.strongWarning => '복합 이상 흐름 확인 필요',
      FireRiskLevel.fireSuspected => '화재 의심, 즉시 확인',
      FireRiskLevel.coOnly => 'CO 상승, 즉시 환기',
    };
  }

  static List<String> _actionsFor(FireRiskLevel level) {
    return switch (level) {
      FireRiskLevel.fireSuspected => const [
          '현장 즉시 확인',
          '연소원과 전기기기 차단 여부 확인',
          '대피 동선 확보',
          '필요 시 119 신고',
        ],
      FireRiskLevel.strongWarning => const [
          '현장 원인 확인',
          '환기팬 또는 연결 장치 작동',
          '조리·향·먼지 발생 여부 확인',
        ],
      FireRiskLevel.warning => const [
          '오염원 확인',
          '5~10분 환기',
          '지속되면 방재 장치 확인',
        ],
      FireRiskLevel.notice => const [
          '창문 또는 환기 상태 확인',
          '일시적 냄새·먼지 원인 확인',
        ],
      FireRiskLevel.coOnly => const [
          '즉시 환기',
          '가스레인지·보일러 등 연소기기 확인',
          '두통·어지럼이 있으면 공간에서 벗어나기',
        ],
      FireRiskLevel.normal => const ['상태 유지', '다음 측정 확인'],
    };
  }

  static int _candidateCount(List<AirQualitySnapshot> samples) {
    final end = samples.last.timestamp;
    final start = end.subtract(const Duration(minutes: 5));
    final buckets = <int, AirQualitySnapshot>{};
    for (final sample in samples) {
      if (sample.timestamp.isBefore(start) || sample.timestamp.isAfter(end)) {
        continue;
      }
      final key = sample.timestamp.millisecondsSinceEpoch ~/ 60000;
      buckets[key] = sample;
    }
    var count = 0;
    for (final sample in buckets.values) {
      final current = _averageWindow(
          samples, sample.timestamp, const Duration(seconds: 60));
      final previous = _averageWindow(
        samples,
        sample.timestamp.subtract(const Duration(minutes: 5)),
        const Duration(seconds: 60),
      );
      final tempBase = _averageWindow(
        samples,
        sample.timestamp.subtract(const Duration(minutes: 15)),
        const Duration(minutes: 30),
      );
      if (_evaluate(current: current, previous: previous, tempBase: tempBase)
          .fireCandidate) {
        count += 1;
      }
    }
    return count.clamp(0, 5).toInt();
  }

  static _FireAverages _averageWindow(
    List<AirQualitySnapshot> samples,
    DateTime center,
    Duration window,
  ) {
    final half = Duration(milliseconds: window.inMilliseconds ~/ 2);
    final start = center.subtract(half);
    final end = center.add(half);
    final matches = samples
        .where((sample) =>
            !sample.timestamp.isBefore(start) && !sample.timestamp.isAfter(end))
        .toList(growable: false);
    final fallback = _nearest(samples, center);
    final source = matches.isEmpty ? <AirQualitySnapshot>[fallback] : matches;
    return _FireAverages(
      pm25: _avg(source.map((sample) => sample.pm25)),
      tvoc: _avg(source.map((sample) => sample.tvoc)),
      temperature: _avg(source.map((sample) => sample.temperature)),
      nox: _avg(source.map((sample) => sample.nox)),
      co: _avg(source.map((sample) => sample.co)),
      co2: _avg(source.map((sample) => sample.co2)),
    );
  }

  static AirQualitySnapshot _nearest(
    List<AirQualitySnapshot> samples,
    DateTime target,
  ) {
    return samples.reduce((best, sample) {
      final bestDiff = best.timestamp.difference(target).inMilliseconds.abs();
      final nextDiff = sample.timestamp.difference(target).inMilliseconds.abs();
      return nextDiff < bestDiff ? sample : best;
    });
  }

  static double? _avg(Iterable<double?> values) {
    var sum = 0.0;
    var count = 0;
    for (final value in values) {
      if (value == null || !value.isFinite) continue;
      sum += value;
      count += 1;
    }
    if (count == 0) return null;
    return sum / count;
  }

  static double? _rise(double? current, double? previous) {
    if (current == null || previous == null) return null;
    return current - previous;
  }

  static double _score(double? value, double cautionLine, double dangerLine) {
    if (value == null || !value.isFinite || dangerLine == cautionLine) {
      return 0;
    }
    final score = (value - cautionLine) / (dangerLine - cautionLine);
    return score.clamp(0, 2.5).toDouble();
  }

  static String _fmt(double? value) {
    if (value == null || !value.isFinite) return '-';
    if (value.abs() >= 100 || value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }
}

class FireMetricAssessment {
  const FireMetricAssessment({
    required this.key,
    required this.label,
    required this.unit,
    required this.current,
    required this.rise5,
    required this.score,
    this.core = true,
  });

  final String key;
  final String label;
  final String unit;
  final double? current;
  final double? rise5;
  final double score;
  final bool core;

  bool get caution => score >= 0.5;
  bool get danger => score >= 1.0;
  String get status => danger
      ? '위험반응'
      : caution
          ? '주의반응'
          : '정상';

  String get formattedCurrent => FireRiskAssessment._fmt(current);
  String get formattedRise5 => FireRiskAssessment._fmt(rise5);
  String get formattedScore => FireRiskAssessment._fmt(score);
}

class _FireEvaluation {
  const _FireEvaluation({
    required this.metrics,
    required this.totalScore,
    required this.riskCount,
    required this.cautionCount,
    required this.fireCandidate,
    required this.coConnected,
    required this.coPmTogether,
    required this.coOnly,
  });

  final List<FireMetricAssessment> metrics;
  final double totalScore;
  final int riskCount;
  final int cautionCount;
  final bool fireCandidate;
  final bool coConnected;
  final bool coPmTogether;
  final bool coOnly;
}

class _FireAverages {
  const _FireAverages({
    required this.pm25,
    required this.tvoc,
    required this.temperature,
    required this.nox,
    required this.co,
    required this.co2,
  });

  final double? pm25;
  final double? tvoc;
  final double? temperature;
  final double? nox;
  final double? co;
  final double? co2;
}
