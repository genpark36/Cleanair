const severityRank = { notice: 1, warning: 2, critical: 3 };
const SUPPRESS_MS = 30 * 60 * 1000;
const DEFAULT_MIN_DURATION = 90 * 1000;
const DEFAULT_QUIET_HOURS = { start: "22:00", end: "07:00" };
const STATE_PRUNE_MS = 24 * 60 * 60 * 1000;

const alertState = new Map();

const watchers = [
  {
    type: "pm25_high",
    label: "PM2.5",
    unit: "µg/m³",
    decimals: 1,
    minDurationMs: 90 * 1000,
    ventilationRecommended: true,
    altActionWhenVentSuppressed: "정화기 강풍/플라즈마 모드로 전환",
    valueKey: "pm25",
    thresholds: [
      { limit: 55, severity: "critical", title: "PM2.5 매우 나쁨", action: "창문 단기 환기 + 정화기 터보", message: "WHO 24h 권고의 4배 이상입니다." },
      { limit: 35, severity: "warning", title: "PM2.5 나쁨", action: "정화기 강풍 모드로 전환", message: "환경부 나쁨 기준을 초과했습니다." },
      { limit: 15, severity: "notice", title: "PM2.5 주의", action: "실내 재순환/필터 점검", message: "WHO 일평균 권고(15)를 초과했습니다." }
    ],
    hysteresis: { clearBelow: 12 }
  },
  {
    type: "co2_high",
    label: "CO₂",
    unit: "ppm",
    decimals: 0,
    minDurationMs: 120 * 1000,
    ventilationRecommended: true,
    valueKey: "co2",
    thresholds: [
      { limit: 1500, severity: "critical", title: "CO₂ 매우 높음", action: "즉시 환기 10분 이상", message: "CO₂가 1500ppm을 넘어 집중력 저하/두통 구간입니다." },
      { limit: 1000, severity: "warning", title: "CO₂ 높음", action: "창문 5~10분 환기", message: "CO₂가 1000ppm을 넘었습니다." },
      { limit: 800, severity: "notice", title: "CO₂ 주의", action: "부분 환기 또는 인원 분산", message: "CO₂가 800ppm을 넘었습니다." }
    ],
    hysteresis: { clearBelow: 700 }
  },
  {
    type: "tvoc_high",
    label: "TVOC",
    unit: "Index",
    decimals: 0,
    minDurationMs: 120 * 1000,
    ventilationRecommended: true,
    altActionWhenVentSuppressed: "정화기 플라즈마/흡착 모드 사용",
    valueKey: "tvoc",
    thresholds: [
      { limit: 400, severity: "critical", title: "TVOC 매우 높음", action: "3~5분 급환기 + 오염원 제거", message: "TVOC Index 400 이상 — WHO 권고를 크게 초과했습니다." },
      { limit: 300, severity: "warning", title: "TVOC 높음", action: "환기 및 오염원 확인", message: "TVOC Index 300 이상입니다." },
      { limit: 200, severity: "notice", title: "TVOC 주의", action: "부분 환기 및 공기정화기 점검", message: "TVOC Index 200 이상입니다." }
    ],
    hysteresis: { clearBelow: 150 }
  },
  {
    type: "nox_high",
    label: "NOx",
    unit: "Index",
    decimals: 0,
    minDurationMs: 90 * 1000,
    ventilationRecommended: true,
    valueKey: "nox",
    thresholds: [
      { limit: 2, severity: "warning", title: "NOx 주의", action: "환기 및 오염원 점검", message: "NOx 지수 2 이상입니다." },
      { limit: 1, severity: "notice", title: "NOx 경계", action: "환기 준비", message: "NOx 지수 1 이상입니다." }
    ],
    hysteresis: { clearBelow: 0.5 }
  },
  {
    type: "respiratory_low",
    label: "호흡기 지표",
    unit: "점",
    decimals: 0,
    minDurationMs: 5 * 60 * 1000,
    compare: "lte",
    valueAccessor: (snapshot) => Number(
      snapshot?.health?.respiratoryIndex ?? snapshot?.child?.respiratory?.score
    ),
    thresholds: [
      { limit: 40, severity: "critical", title: "호흡기 지표 경고", action: "실내 환경 개선 및 환기", message: "호흡기 점수가 경고 구간입니다." },
      { limit: 60, severity: "warning", title: "호흡기 지표 주의", action: "환기 및 오염원 확인", message: "호흡기 점수가 낮습니다." }
    ],
    hysteresis: { clearAbove: 65 }
  },
  {
    type: "infection_risk",
    label: "감염 위험",
    unit: "점",
    decimals: 0,
    minDurationMs: 5 * 60 * 1000,
    compare: "gte",
    valueAccessor: (snapshot) => Number(
      snapshot?.health?.immunityRisk ?? snapshot?.child?.infection?.score
    ),
    thresholds: [
      { limit: 80, severity: "critical", title: "감염 위험 매우 높음", action: "환기 및 밀집도 관리", message: "감염 위험 점수가 매우 높습니다." },
      { limit: 60, severity: "warning", title: "감염 위험 높음", action: "환기 및 밀집도 관리", message: "감염 위험 점수가 높습니다." }
    ],
    hysteresis: { clearBelow: 55 }
  },
  {
    type: "focus_poor",
    label: "집중 환경",
    unit: "ppm",
    decimals: 0,
    minDurationMs: 3 * 60 * 1000,
    compare: "gte",
    valueAccessor: (snapshot, raw) => Number(raw?.co2 ?? snapshot?.raw?.co2 ?? snapshot?.co2),
    thresholds: [
      { limit: 1500, severity: "critical", title: "집중 환경 나쁨", action: "즉시 환기", message: "CO₂가 1500ppm 이상입니다." },
      { limit: 1000, severity: "warning", title: "집중 환경 주의", action: "10분 환기 권장", message: "CO₂가 1000ppm 이상입니다." }
    ],
    hysteresis: { clearBelow: 900 }
  },
  {
    type: "cardio_low",
    label: "심혈관 보호점수",
    unit: "점",
    decimals: 0,
    minDurationMs: 10 * 60 * 1000,
    compare: "lte",
    valueAccessor: (snapshot) => Number(
      snapshot?.health?.cardioScore ?? snapshot?.senior?.cardio?.score
    ),
    thresholds: [
      { limit: 40, severity: "critical", title: "심혈관 보호점수 위험", action: "실내 활동 권장", message: "심혈관 보호점수가 위험 구간입니다." },
      { limit: 60, severity: "warning", title: "심혈관 보호점수 주의", action: "공기질 개선 및 활동 조절", message: "심혈관 보호점수가 낮습니다." }
    ],
    hysteresis: { clearAbove: 65 }
  },
  {
    type: "sleep_quality_low",
    label: "수면 환경",
    unit: "점",
    decimals: 0,
    minDurationMs: 10 * 60 * 1000,
    compare: "lte",
    valueAccessor: (snapshot) => Number(
      snapshot?.health?.sleepComfort ?? snapshot?.senior?.sleep?.score
    ),
    thresholds: [
      { limit: 40, severity: "critical", title: "수면 환경 매우 나쁨", action: "취침 전 환기 권장", message: "수면 환경 점수가 매우 낮습니다." },
      { limit: 60, severity: "warning", title: "수면 환경 주의", action: "취침 전 환기 권장", message: "수면 환경 점수가 낮습니다." }
    ],
    hysteresis: { clearAbove: 65 }
  },
  {
    type: "mold_risk",
    label: "곰팡이 위험",
    unit: "단계",
    decimals: 0,
    minDurationMs: 10 * 60 * 1000,
    compare: "gte",
    valueAccessor: (snapshot) => Number(
      snapshot?.moldRiskLevel ?? snapshot?.alerts?.moldRiskLevel ?? snapshot?.child?.mold?.riskLevel
    ),
    thresholds: [
      { limit: 4, severity: "critical", title: "곰팡이 위험", action: "제습 및 환기 즉시 실행", message: "고습 24시간 이상 지속 위험" },
      { limit: 3, severity: "warning", title: "곰팡이 경고", action: "습도 60% 이하 유지", message: "곰팡이 성장 위험 구간입니다." },
      { limit: 2, severity: "notice", title: "곰팡이 주의", action: "환기/제습 준비", message: "곰팡이 위험이 증가했습니다." }
    ],
    hysteresis: { clearBelow: 1 }
  }
];

const round = (value, digits = 1) => {
  if (!Number.isFinite(value)) return null;
  const factor = Math.pow(10, digits);
  return Math.round(value * factor) / factor;
};

const toMinutes = (hhmm) => {
  if (!hhmm) return null;
  const [h, m] = String(hhmm).split(":").map((part) => parseInt(part, 10));
  return h * 60 + (m || 0);
};

const isQuietHour = (date, window) => {
  const startMinutes = toMinutes(window?.start);
  const endMinutes = toMinutes(window?.end);
  if (startMinutes == null || endMinutes == null) return false;
  const minutes = date.getHours() * 60 + date.getMinutes();
  if (startMinutes === endMinutes) return false;
  if (startMinutes < endMinutes) {
    return minutes >= startMinutes && minutes < endMinutes;
  }
  return minutes >= startMinutes || minutes < endMinutes;
};

const resolveSnapshotId = (snapshot) => (
  snapshot?.id || snapshot?.meta?.serialno || snapshot?.serialno || snapshot?.serial || "snapshot"
);

const ensureEntry = (key) => {
  if (!alertState.has(key)) {
    alertState.set(key, {
      activeSince: null,
      pendingSeverity: null,
      lastEventTs: 0,
      lastEventSeverity: null,
      lastEventId: null,
      lastValue: null,
      lastUpdated: null,
      durationBuffer: null
    });
  }
  return alertState.get(key);
};

const pruneState = (now) => {
  const pruneBefore = now - STATE_PRUNE_MS;
  for (const [key, entry] of alertState.entries()) {
    if (!entry) {
      alertState.delete(key);
      continue;
    }
    if (entry.activeSince) continue;
    if (!entry.lastEventTs || entry.lastEventTs < pruneBefore) {
      alertState.delete(key);
    }
  }
};

const buildTrendMeta = (snapshot) => {
  const purifier = snapshot?.health?.purifier || snapshot?.purifier || {};
  const k = Number(purifier.kEffective ?? purifier.k);
  let code = "unknown";
  let label = "변화 추정 불가";
  if (Number.isFinite(k)) {
    if (k >= 1.5) { code = "fast_drop"; label = "급속 감소"; }
    else if (k >= 0.5) { code = "slow_drop"; label = "완만 감소"; }
    else if (k >= -0.05) { code = "flat"; label = "정체"; }
    else { code = "rising"; label = "상승"; }
  }
  return {
    code,
    label,
    k: Number.isFinite(k) ? k : null,
    kSource: purifier.cadrGrade || null
  };
};

const isSameLocalDay = (leftTs, rightTs) => {
  if (!leftTs || !rightTs) return false;
  const left = new Date(leftTs);
  const right = new Date(rightTs);
  return left.getFullYear() === right.getFullYear()
    && left.getMonth() === right.getMonth()
    && left.getDate() === right.getDate();
};

const resolveApparentSnapshot = (snapshot) => {
  const seasonal = snapshot?.health?.seasonalApparent || snapshot?.seasonalApparent || null;
  const seasonMode = seasonal?.seasonMode || null;
  const summerTemp = seasonal?.summer?.apparentTemp ?? null;
  const winterTemp = seasonal?.winter?.apparentTemp ?? null;
  const fallbackTemp = snapshot?.health?.apparentTemp ?? null;
  const apparentTemp = seasonMode === "summer" ? (summerTemp ?? fallbackTemp)
    : seasonMode === "winter" ? (winterTemp ?? fallbackTemp)
      : (fallbackTemp ?? summerTemp ?? winterTemp);
  const summerMessage = seasonal?.summer?.riskMessage || null;
  const winterMessage = seasonal?.winter?.message || null;
  return {
    apparentTemp: Number.isFinite(apparentTemp) ? apparentTemp : null,
    seasonMode,
    summerMessage,
    winterMessage
  };
};

function generateAlertsFromSnapshot(snapshot, options = {}) {
  const now = options.now ?? Date.now();
  const quietHoursWindow = options.quietHoursWindow || DEFAULT_QUIET_HOURS;
  pruneState(now);

  const raw = snapshot?.raw || snapshot || {};
  const snapshotId = resolveSnapshotId(snapshot);
  const trendMeta = buildTrendMeta(snapshot);
  const events = [];

  for (const watcher of watchers) {
    const rawValue = watcher.valueAccessor
      ? watcher.valueAccessor(snapshot, raw)
      : (raw?.[watcher.valueKey] ?? snapshot?.[watcher.valueKey]);
    const value = Number(rawValue);
    if (!Number.isFinite(value)) {
      alertState.delete(`${snapshotId}:${watcher.type}`);
      continue;
    }

    const compare = watcher.compare || "gte";
    const threshold = watcher.thresholds.find((t) => (
      compare === "lte" ? value <= t.limit : value >= t.limit
    ));
    const hysteresisClearBelow = watcher.hysteresis?.clearBelow ?? watcher.resetBelow;
    const hysteresisClearAbove = watcher.hysteresis?.clearAbove ?? watcher.resetAbove;
    const entry = ensureEntry(`${snapshotId}:${watcher.type}`);
    entry.lastValue = value;
    entry.lastUpdated = now;

    if (!threshold) {
      const shouldClear = compare === "lte"
        ? (hysteresisClearAbove != null && value >= hysteresisClearAbove)
        : (hysteresisClearBelow != null && value <= hysteresisClearBelow);
      if (shouldClear) {
        alertState.delete(`${snapshotId}:${watcher.type}`);
      } else {
        entry.activeSince = null;
        entry.pendingSeverity = null;
        entry.durationBuffer = null;
      }
      continue;
    }

    if (!entry.activeSince || !entry.pendingSeverity || (severityRank[threshold.severity] || 0) > (severityRank[entry.pendingSeverity] || 0)) {
      entry.activeSince = now;
      entry.pendingSeverity = threshold.severity;
    }

    const minDuration = watcher.minDurationMs ?? DEFAULT_MIN_DURATION;
    const durationMs = now - entry.activeSince;
    if (durationMs < minDuration) {
      entry.durationBuffer = {
        accumulatedMs: durationMs,
        requiredMs: minDuration,
        source: watcher.minDurationMs ? `${watcher.type}:config` : "default"
      };
      continue;
    }

    const quietHours = isQuietHour(new Date(now), quietHoursWindow);
    const ventilationSuppressed = quietHours && threshold.severity !== "critical" && watcher.ventilationRecommended;
    const recommendedAction = ventilationSuppressed && watcher.altActionWhenVentSuppressed
      ? watcher.altActionWhenVentSuppressed
      : threshold.action;

    const severity = threshold.severity;
    const priority = severityRank[severity] || 0;
    const eventIdSeed = entry.activeSince || now;
    const eventId = `${watcher.type}-${severity}-${Math.floor(eventIdSeed / 1000)}`;

    const suppressed = entry.lastEventTs && (now - entry.lastEventTs) < SUPPRESS_MS && (severityRank[entry.lastEventSeverity] || 0) >= priority;
    const suppressedUntil = suppressed ? entry.lastEventTs + SUPPRESS_MS : null;

    if (!suppressed) {
      entry.lastEventTs = now;
      entry.lastEventSeverity = severity;
      entry.lastEventId = eventId;
    }
    entry.activeSince = now;
    entry.pendingSeverity = null;
    entry.durationBuffer = null;

    const hysteresisClear = compare === "lte"
      ? (hysteresisClearAbove ?? null)
      : (hysteresisClearBelow ?? null);

    events.push({
      type: watcher.type,
      label: watcher.label,
      severity,
      priority,
      title: threshold.title,
      message: threshold.message,
      recommendedAction,
      value: round(value, watcher.decimals),
      unit: watcher.unit,
      eventId,
      topic: "all",
      quietHours,
      quietHoursWindow,
      suppressed,
      suppressedUntil,
      trend: trendMeta.code,
      trendMeta,
      ventilation: watcher.ventilationRecommended ? {
        recommended: !ventilationSuppressed,
        suppressed: ventilationSuppressed,
        reason: ventilationSuppressed ? "quiet_hours" : null,
        altAction: ventilationSuppressed ? watcher.altActionWhenVentSuppressed : null
      } : null,
      context: {
        snapshotId,
        location: snapshot?.location || null
      },
      duration: {
        accumulatedMs: durationMs,
        requiredMs: minDuration,
        met: true,
        source: watcher.minDurationMs ? `${watcher.type}:config` : "default"
      },
      hysteresis: {
        trigger: threshold.limit,
        clear: hysteresisClear ?? null,
        value
      }
    });
  }

  const apparentSnapshot = resolveApparentSnapshot(snapshot);
  const nowDate = new Date(now);
  const scheduleSlots = [
    { type: "apparent_temp_morning", hour: 7, label: "체감온도(아침)" },
    { type: "apparent_temp_evening", hour: 19, label: "체감온도(저녁)" }
  ];
  if (Number.isFinite(apparentSnapshot.apparentTemp)) {
    for (const slot of scheduleSlots) {
      if (nowDate.getHours() !== slot.hour || nowDate.getMinutes() >= 10) continue;
      const entry = ensureEntry(`${snapshotId}:${slot.type}`);
      if (isSameLocalDay(entry.lastEventTs, now)) continue;

      const apparentTemp = apparentSnapshot.apparentTemp;
      let severity = "notice";
      let recommendedAction = "실내 온열/보온 환경 점검";
      let message = `체감온도 ${round(apparentTemp, 1)}°C`;
      if (apparentSnapshot.seasonMode === "summer") {
        if (apparentTemp >= 38) severity = "critical";
        else if (apparentTemp >= 35) severity = "warning";
        else if (apparentTemp >= 33) severity = "notice";
        message = apparentSnapshot.summerMessage || message;
        recommendedAction = "수분 보충 및 환기/냉방";
      } else if (apparentSnapshot.seasonMode === "winter") {
        if (apparentTemp <= -15) severity = "critical";
        else if (apparentTemp <= -10) severity = "warning";
        else if (apparentTemp <= -5) severity = "notice";
        message = apparentSnapshot.winterMessage || message;
        recommendedAction = "보온 유지 및 한파 대비";
      }

      const priority = severityRank[severity] || 0;
      const eventId = `${slot.type}-${severity}-${Math.floor(now / 1000)}`;
      entry.lastEventTs = now;
      entry.lastEventSeverity = severity;
      entry.lastEventId = eventId;
      entry.activeSince = null;
      entry.pendingSeverity = null;
      entry.durationBuffer = null;

      events.push({
        type: slot.type,
        label: "체감온도",
        severity,
        priority,
        title: slot.label,
        message,
        recommendedAction,
        value: round(apparentTemp, 1),
        unit: "°C",
        eventId,
        topic: "all",
        quietHours: false,
        quietHoursWindow,
        suppressed: false,
        suppressedUntil: null,
        trend: trendMeta.code,
        trendMeta,
        ventilation: null,
        context: {
          snapshotId,
          location: snapshot?.location || null,
          schedule: slot.type
        }
      });
    }
  }

  return events;
}

module.exports = {
  generateAlertsFromSnapshot,
  DEFAULT_QUIET_HOURS
};
