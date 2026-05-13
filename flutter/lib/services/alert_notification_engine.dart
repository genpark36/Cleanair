import '../models/air_quality_snapshot.dart';
import '../utils/nodered_health_engine.dart';
import 'notification_preferences.dart';

/// Extracts alert messages and decides whether they should be delivered based
/// on quiet hours, snooze state, muted alert types, and recent duplicates.
class AlertNotificationEngine {
  AlertNotificationEngine({
    Duration dedupeWindow = const Duration(minutes: 15),
  }) : _dedupeWindow = dedupeWindow;

  final Duration _dedupeWindow;
  final NodeRedHealthEngine _healthEngine = NodeRedHealthEngine();
  final Map<String, DateTime> _recentAlerts = <String, DateTime>{};
  final Map<String, _WatcherState> _watcherState = <String, _WatcherState>{};
  final Map<String, String> _lastApparentSlotDay = <String, String>{};

  /// Returns a list of alert strings embedded in the snapshot payload.
  List<String> extractMessages(SnapshotAlerts? alerts) {
    if (alerts == null) return const [];
    final results = <String>{};
    final primary = alerts.airQualityAlert?.trim();
    if (primary != null && primary.isNotEmpty) {
      results.add(primary);
    }
    final mold = alerts.moldRiskMessage?.trim();
    if (mold != null && mold.isNotEmpty) {
      results.add(mold);
    }
    final supplemental = alerts.messages;
    if (supplemental != null) {
      for (final raw in supplemental) {
        final value = raw.trim();
        if (value.isNotEmpty) {
          results.add(value);
        }
      }
    }
    return results.toList(growable: false);
  }

  /// Returns messages that should trigger notifications at [now].
  List<String> notifiableMessages(
    AirQualitySnapshot snapshot,
    NotificationPreferences prefs,
    DateTime now,
  ) {
    if (prefs.shouldSuppress(now)) {
      return const [];
    }
    final messages = <String>{
      ...extractMessages(snapshot.alerts),
      ..._legacyComputedMessages(snapshot),
      ..._backendWatcherMessages(snapshot, now, prefs),
      ..._scheduledApparentMessages(snapshot, now, prefs),
    }.toList(growable: false);
    if (messages.isEmpty) {
      return const [];
    }

    final muted = prefs.mutedTypes;
    final accepted = <String>[];
    for (final message in messages) {
      final type = _classifyAlertType(message);
      if (type != null && (muted[type] ?? false)) continue;
      if (_shouldEmit(message, type, now, prefs.notificationIntervalMinutes)) {
        accepted.add(message);
      }
    }
    purgeExpired(now, prefs.notificationIntervalMinutes);
    return accepted;
  }

  static String? _classifyAlertType(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('pm2.5') ||
        lower.contains('pm25') ||
        lower.contains('미세먼지')) {
      return 'pm25_high';
    }
    if (lower.contains('co₂') ||
        lower.contains('co2') ||
        lower.contains('이산화탄소')) {
      return 'co2_high';
    }
    if (lower.contains('tvoc') ||
        lower.contains('voc') ||
        lower.contains('휘발성')) {
      return 'tvoc_high';
    }
    if (lower.contains('nox') || lower.contains('질소산화물')) {
      return 'nox_high';
    }
    if (lower.contains('곰팡이') || lower.contains('mold')) {
      return 'mold_risk';
    }
    if (lower.contains('호흡기')) return 'respiratory_low';
    if (lower.contains('감염') || lower.contains('면역')) {
      return 'infection_risk';
    }
    if (lower.contains('집중')) return 'focus_poor';
    if (lower.contains('심혈관')) return 'cardio_low';
    if (lower.contains('수면')) return 'sleep_quality_low';
    if (lower.contains('체감온도')) {
      if (lower.contains('저녁') || lower.contains('evening')) {
        return 'apparent_temp_evening';
      }
      return 'apparent_temp_morning';
    }
    return null;
  }

  List<String> _legacyComputedMessages(AirQualitySnapshot snapshot) {
    final health = _healthEngine.compute(
      pm25: snapshot.pm25,
      co2: snapshot.co2,
      tvoc: snapshot.tvoc,
      temp: snapshot.temperature,
      humidity: snapshot.humidity,
      timestampMs: snapshot.timestamp.millisecondsSinceEpoch,
    );
    final alerts = health['alerts'];
    if (alerts is! Map<String, dynamic>) {
      return const [];
    }
    return extractMessages(SnapshotAlerts.tryParse(alerts));
  }

  List<String> _scheduledApparentMessages(
    AirQualitySnapshot snapshot,
    DateTime now,
    NotificationPreferences prefs,
  ) {
    final slot = switch (now.hour) {
      7 when now.minute < 10 => (
          type: 'apparent_temp_morning',
          label: '체감온도(아침)',
        ),
      19 when now.minute < 10 => (
          type: 'apparent_temp_evening',
          label: '체감온도(저녁)',
        ),
      _ => null,
    };
    if (slot == null) return const [];

    final snapshotId = snapshot.id ?? snapshot.meta?.serialNo ?? 'snapshot';
    final localDay = '${now.year}-${now.month}-${now.day}';
    final key = '$snapshotId:${slot.type}';
    if (_lastApparentSlotDay[key] == localDay) return const [];

    final seasonal = snapshot.seasonalApparent;
    final mode = seasonal?.seasonMode;
    final summerTemp = seasonal?.summer?.apparentTemp;
    final winterTemp = seasonal?.winter?.apparentTemp;
    final apparentTemp = mode == 'summer'
        ? summerTemp ?? snapshot.apparentTemp
        : mode == 'winter'
            ? winterTemp ?? snapshot.apparentTemp
            : snapshot.apparentTemp;
    if (apparentTemp == null || !apparentTemp.isFinite) {
      return const [];
    }

    var message = '체감온도 ${apparentTemp.toStringAsFixed(1)}°C';
    var action = '실내 온열/보온 환경 점검';
    if (mode == 'summer') {
      final severity = apparentTemp >= 38
          ? 3
          : apparentTemp >= 35
              ? 2
              : apparentTemp >= 33
                  ? 1
                  : 0;
      if (severity < _minimumSeverityForType(prefs, slot.type)) return const [];
      message = seasonal?.summer?.riskMessage?.trim().isNotEmpty == true
          ? seasonal!.summer!.riskMessage!
          : message;
      action = '수분 보충 및 환기/냉방';
    } else if (mode == 'winter') {
      final severity = apparentTemp <= -15
          ? 3
          : apparentTemp <= -10
              ? 2
              : apparentTemp <= -5
                  ? 1
                  : 0;
      if (severity < _minimumSeverityForType(prefs, slot.type)) return const [];
      message = seasonal?.winter?.message?.trim().isNotEmpty == true
          ? seasonal!.winter!.message!
          : message;
      action = '보온 유지 및 한파 대비';
    }

    _lastApparentSlotDay[key] = localDay;
    return ['${slot.label}: $message · $action'];
  }

  bool _shouldEmit(
    String message,
    String? type,
    DateTime now,
    int notificationIntervalMinutes,
  ) {
    // Treat changing text for the same alert type as the same notification
    // during the dedupe window.
    final key = type ?? message;
    final last = _recentAlerts[key];
    final interval = Duration(
      minutes: notificationIntervalMinutes.clamp(1, 24 * 60).toInt(),
    );
    if (last != null && now.difference(last) < interval) {
      return false;
    }
    _recentAlerts[key] = now;
    return true;
  }

  List<String> _backendWatcherMessages(
    AirQualitySnapshot snapshot,
    DateTime now,
    NotificationPreferences prefs,
  ) {
    final nowMs = now.millisecondsSinceEpoch;
    final events = <String>[];
    _addWatcherEvent(
      events,
      snapshot,
      nowMs,
      prefs,
      _AlertWatcher(
        type: 'pm25_high',
        label: 'PM2.5',
        unit: 'µg/m³',
        decimals: 1,
        minDurationMs: 90 * 1000,
        value: () => snapshot.pm25,
        thresholds: const [
          _AlertThreshold(55, 3, 'PM2.5 매우 나쁨', '창문 단기 환기 + 정화기 터보',
              'WHO 24h 권고의 4배 이상입니다.'),
          _AlertThreshold(
              35, 2, 'PM2.5 나쁨', '정화기 강풍 모드로 전환', '환경부 나쁨 기준을 초과했습니다.'),
          _AlertThreshold(
              15, 1, 'PM2.5 주의', '실내 재순환/필터 점검', 'WHO 일평균 권고(15)를 초과했습니다.'),
        ],
        clearBelow: 12,
      ),
    );
    _addWatcherEvent(
      events,
      snapshot,
      nowMs,
      prefs,
      _AlertWatcher(
        type: 'co2_high',
        label: 'CO₂',
        unit: 'ppm',
        decimals: 0,
        minDurationMs: 120 * 1000,
        value: () => snapshot.co2,
        thresholds: const [
          _AlertThreshold(1500, 3, 'CO₂ 매우 높음', '즉시 환기 10분 이상',
              'CO₂가 1500ppm을 넘어 집중력 저하/두통 구간입니다.'),
          _AlertThreshold(
              1000, 2, 'CO₂ 높음', '창문 5~10분 환기', 'CO₂가 1000ppm을 넘었습니다.'),
          _AlertThreshold(
              800, 1, 'CO₂ 주의', '부분 환기 또는 인원 분산', 'CO₂가 800ppm을 넘었습니다.'),
        ],
        clearBelow: 700,
      ),
    );
    _addWatcherEvent(
      events,
      snapshot,
      nowMs,
      prefs,
      _AlertWatcher(
        type: 'tvoc_high',
        label: 'TVOC',
        unit: 'Index',
        decimals: 0,
        minDurationMs: 120 * 1000,
        value: () => snapshot.tvoc,
        thresholds: const [
          _AlertThreshold(400, 3, 'TVOC 매우 높음', '3~5분 급환기 + 오염원 제거',
              'TVOC Index 400 이상 — WHO 권고를 크게 초과했습니다.'),
          _AlertThreshold(
              300, 2, 'TVOC 높음', '환기 및 오염원 확인', 'TVOC Index 300 이상입니다.'),
          _AlertThreshold(
              200, 1, 'TVOC 주의', '부분 환기 및 공기정화기 점검', 'TVOC Index 200 이상입니다.'),
        ],
        clearBelow: 150,
      ),
    );
    _addWatcherEvent(
      events,
      snapshot,
      nowMs,
      prefs,
      _AlertWatcher(
        type: 'nox_high',
        label: 'NOx',
        unit: 'Index',
        decimals: 0,
        minDurationMs: 90 * 1000,
        value: () => snapshot.nox,
        thresholds: const [
          _AlertThreshold(2, 2, 'NOx 높음', '환기 및 오염원 점검', 'NOx 지수 2 이상입니다.'),
          _AlertThreshold(1, 1, 'NOx 관찰', '추세 확인', 'NOx 지수 1 이상입니다.'),
        ],
        clearBelow: 0.5,
      ),
    );
    _addWatcherEvent(
      events,
      snapshot,
      nowMs,
      prefs,
      _AlertWatcher(
        type: 'respiratory_low',
        label: '호흡기 지표',
        unit: '점',
        decimals: 0,
        minDurationMs: 5 * 60 * 1000,
        compare: _AlertCompare.lte,
        value: () =>
            snapshot.respiratoryIndex ?? snapshot.child?.respiratory?.score,
        thresholds: const [
          _AlertThreshold(
              40, 3, '호흡기 지표 경고', '실내 환경 개선 및 환기', '호흡기 점수가 경고 구간입니다.'),
          _AlertThreshold(60, 2, '호흡기 지표 주의', '환기 및 오염원 확인', '호흡기 점수가 낮습니다.'),
        ],
        clearAbove: 65,
      ),
    );
    _addWatcherEvent(
      events,
      snapshot,
      nowMs,
      prefs,
      _AlertWatcher(
        type: 'infection_risk',
        label: '감염 위험',
        unit: '점',
        decimals: 0,
        minDurationMs: 5 * 60 * 1000,
        value: () => snapshot.immunityRisk ?? snapshot.child?.infection?.score,
        thresholds: const [
          _AlertThreshold(
              80, 3, '감염 위험 매우 높음', '환기 및 밀집도 관리', '감염 위험 점수가 매우 높습니다.'),
          _AlertThreshold(60, 2, '감염 위험 높음', '환기 및 밀집도 관리', '감염 위험 점수가 높습니다.'),
        ],
        clearBelow: 55,
      ),
    );
    _addWatcherEvent(
      events,
      snapshot,
      nowMs,
      prefs,
      _AlertWatcher(
        type: 'focus_poor',
        label: '집중 환경',
        unit: 'ppm',
        decimals: 0,
        minDurationMs: 3 * 60 * 1000,
        value: () => snapshot.co2,
        thresholds: const [
          _AlertThreshold(1500, 3, '집중 환경 나쁨', '즉시 환기', 'CO₂가 1500ppm 이상입니다.'),
          _AlertThreshold(
              1000, 2, '집중 환경 주의', '10분 환기 권장', 'CO₂가 1000ppm 이상입니다.'),
        ],
        clearBelow: 900,
      ),
    );
    _addWatcherEvent(
      events,
      snapshot,
      nowMs,
      prefs,
      _AlertWatcher(
        type: 'cardio_low',
        label: '심혈관 보호점수',
        unit: '점',
        decimals: 0,
        minDurationMs: 10 * 60 * 1000,
        compare: _AlertCompare.lte,
        value: () => snapshot.cardioScore ?? snapshot.senior?.cardio?.score,
        thresholds: const [
          _AlertThreshold(
              40, 3, '심혈관 보호점수 위험', '실내 활동 권장', '심혈관 보호점수가 위험 구간입니다.'),
          _AlertThreshold(
              60, 2, '심혈관 보호점수 주의', '공기질 개선 및 활동 조절', '심혈관 보호점수가 낮습니다.'),
        ],
        clearAbove: 65,
      ),
    );
    _addWatcherEvent(
      events,
      snapshot,
      nowMs,
      prefs,
      _AlertWatcher(
        type: 'sleep_quality_low',
        label: '수면 환경',
        unit: '점',
        decimals: 0,
        minDurationMs: 10 * 60 * 1000,
        compare: _AlertCompare.lte,
        value: () => snapshot.sleepComfort ?? snapshot.senior?.sleep?.score,
        thresholds: const [
          _AlertThreshold(
              40, 3, '수면 환경 매우 나쁨', '취침 전 환기 권장', '수면 환경 점수가 매우 낮습니다.'),
          _AlertThreshold(60, 2, '수면 환경 주의', '취침 전 환기 권장', '수면 환경 점수가 낮습니다.'),
        ],
        clearAbove: 65,
      ),
    );
    _addWatcherEvent(
      events,
      snapshot,
      nowMs,
      prefs,
      _AlertWatcher(
        type: 'mold_risk',
        label: '곰팡이 위험',
        unit: '단계',
        decimals: 0,
        minDurationMs: 10 * 60 * 1000,
        value: () =>
            (snapshot.alerts?.moldRiskLevel ?? snapshot.child?.mold?.riskLevel)
                ?.toDouble(),
        thresholds: const [
          _AlertThreshold(4, 3, '곰팡이 위험', '제습 및 환기 즉시 실행', '고습 24시간 이상 지속 위험'),
          _AlertThreshold(3, 2, '곰팡이 경고', '습도 60% 이하 유지', '곰팡이 성장 위험 구간입니다.'),
          _AlertThreshold(2, 1, '곰팡이 주의', '환기/제습 준비', '곰팡이 위험이 증가했습니다.'),
        ],
        clearBelow: 1,
      ),
    );
    return events;
  }

  void _addWatcherEvent(
    List<String> events,
    AirQualitySnapshot snapshot,
    int nowMs,
    NotificationPreferences prefs,
    _AlertWatcher watcher,
  ) {
    final value = watcher.value();
    final key = '${snapshot.id ?? 'snapshot'}:${watcher.type}';
    if (value == null || !value.isFinite) {
      _watcherState.remove(key);
      return;
    }

    final threshold = watcher.resolve(value);
    final state = _watcherState.putIfAbsent(key, _WatcherState.new);
    if (threshold == null) {
      if (watcher.shouldClear(value)) {
        _watcherState.remove(key);
      } else {
        state.activeSinceMs = null;
        state.pendingSeverity = null;
      }
      return;
    }

    final activeSince = state.activeSinceMs;
    final pendingSeverity = state.pendingSeverity;
    if (activeSince == null ||
        pendingSeverity == null ||
        threshold.severity > pendingSeverity) {
      state.activeSinceMs = nowMs;
      state.pendingSeverity = threshold.severity;
      return;
    }

    if (nowMs - activeSince < watcher.minDurationMs) {
      return;
    }

    if (threshold.severity < _minimumSeverityForType(prefs, watcher.type)) {
      state.activeSinceMs = nowMs;
      state.pendingSeverity = null;
      return;
    }

    state.activeSinceMs = nowMs;
    state.pendingSeverity = null;
    events.add(
      '${threshold.title}: ${watcher.format(value)} ${watcher.unit} · '
      '${threshold.action}. ${threshold.message}',
    );
  }

  void purgeExpired(DateTime now, [int? notificationIntervalMinutes]) {
    final window = notificationIntervalMinutes == null
        ? _dedupeWindow
        : Duration(
            minutes: notificationIntervalMinutes.clamp(1, 24 * 60).toInt(),
          );
    _recentAlerts.removeWhere((_, ts) => now.difference(ts) >= window);
  }

  int _minimumSeverityForType(NotificationPreferences prefs, String type) {
    return (prefs.minimumSeverityByType[type] ?? prefs.minimumSeverityPriority)
        .clamp(1, 3)
        .toInt();
  }
}

enum _AlertCompare { gte, lte }

class _AlertThreshold {
  const _AlertThreshold(
    this.limit,
    this.severity,
    this.title,
    this.action,
    this.message,
  );

  final double limit;
  final int severity;
  final String title;
  final String action;
  final String message;
}

class _AlertWatcher {
  const _AlertWatcher({
    required this.type,
    required this.label,
    required this.unit,
    required this.decimals,
    required this.minDurationMs,
    required this.value,
    required this.thresholds,
    this.compare = _AlertCompare.gte,
    this.clearBelow,
    this.clearAbove,
  });

  final String type;
  final String label;
  final String unit;
  final int decimals;
  final int minDurationMs;
  final double? Function() value;
  final List<_AlertThreshold> thresholds;
  final _AlertCompare compare;
  final double? clearBelow;
  final double? clearAbove;

  _AlertThreshold? resolve(double value) {
    for (final threshold in thresholds) {
      if (compare == _AlertCompare.lte) {
        if (value <= threshold.limit) return threshold;
      } else if (value >= threshold.limit) {
        return threshold;
      }
    }
    return null;
  }

  bool shouldClear(double value) {
    if (compare == _AlertCompare.lte) {
      final limit = clearAbove;
      return limit != null && value >= limit;
    }
    final limit = clearBelow;
    return limit != null && value <= limit;
  }

  String format(double value) {
    if (decimals <= 0) return value.round().toString();
    return value.toStringAsFixed(decimals);
  }
}

class _WatcherState {
  int? activeSinceMs;
  int? pendingSeverity;
}
