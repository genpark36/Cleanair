const severityRank = { notice: 1, warning: 2, critical: 3 };
const SUPPRESS_MS = 30 * 60 * 1000;
const DEFAULT_MIN_DURATION = 90 * 1000;
const DEFAULT_QUIET_HOURS = { start: "22:00", end: "07:00" };
const STATE_PRUNE_MS = 24 * 60 * 60 * 1000;

const alertState = new Map();
const fireRiskHistory = new Map();

const safeStateId = (value) => encodeURIComponent(String(value || "snapshot"))
  .replace(/\./g, "%2E")
  .replace(/%/g, "_");

async function loadFireRiskRuntimeState(firestore, snapshotId, now) {
  const minTs = now - 35 * 60 * 1000;
  const memoryKey = `${snapshotId}:fire_risk_history`;
  const fallback = {
    ref: null,
    samples: (fireRiskHistory.get(memoryKey) || []).filter(
      (sample) => sample.ts >= minTs
    ),
    entry: ensureEntry(`${snapshotId}:fire_risk`)
  };
  if (!firestore) return fallback;

  const ref = firestore.collection("alert_runtime_state")
    .doc(`fire_risk_${safeStateId(snapshotId)}`);
  try {
    const doc = await ref.get();
    const data = doc.exists ? (doc.data() || {}) : {};
    const samples = Array.isArray(data.samples)
      ? data.samples
          .map((sample) => ({
            ts: Number(sample.ts),
            values: sample.values || {}
          }))
          .filter((sample) => Number.isFinite(sample.ts) && sample.ts >= minTs)
      : [];
    return {
      ref,
      samples,
      entry: {
        activeSince: null,
        pendingSeverity: null,
        lastEventTs: Number(data.lastEventTs) || 0,
        lastEventSeverity: data.lastEventSeverity || null,
        lastEventId: data.lastEventId || null,
        lastValue: null,
        lastUpdated: Number(data.lastUpdated) || null
      }
    };
  } catch (error) {
    console.warn("fire_risk_state_load_failed", error?.message || error);
    return fallback;
  }
}

async function saveFireRiskRuntimeState(state, snapshotId, samples, entry, now) {
  const cappedSamples = samples.slice(-240);
  fireRiskHistory.set(`${snapshotId}:fire_risk_history`, cappedSamples);
  alertState.set(`${snapshotId}:fire_risk`, entry);
  if (!state?.ref) return;
  try {
    await state.ref.set({
      kind: "fire_risk",
      snapshotId,
      samples: cappedSamples,
      lastEventTs: entry.lastEventTs || 0,
      lastEventSeverity: entry.lastEventSeverity || null,
      lastEventId: entry.lastEventId || null,
      lastUpdated: now,
      updatedAtMs: now
    }, { merge: true });
  } catch (error) {
    console.warn("fire_risk_state_save_failed", error?.message || error);
  }
}

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
      { limit: 2, severity: "warning", title: "NOx 높음", action: "환기 및 오염원 점검", message: "NOx 지수 2 이상입니다." },
      { limit: 1, severity: "notice", title: "NOx 관찰", action: "추세 확인", message: "NOx 지수 1 이상입니다." }
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

const readNumber = (...values) => {
  for (const value of values) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return null;
};

const fireMetricScore = (value, cautionLine, dangerLine) => {
  if (!Number.isFinite(value) || cautionLine === dangerLine) return 0;
  const score = (value - cautionLine) / (dangerLine - cautionLine);
  return Math.max(0, Math.min(2.5, score));
};

const fireRise = (current, previous) => (
  Number.isFinite(current) && Number.isFinite(previous) ? current - previous : null
);

const nearestFireSample = (samples, targetTs) => {
  if (!samples.length) return null;
  return samples.reduce((best, sample) => (
    Math.abs(sample.ts - targetTs) < Math.abs(best.ts - targetTs) ? sample : best
  ), samples[0]);
};

const averageFireWindow = (samples, centerTs, windowMs) => {
  const half = Math.floor(windowMs / 2);
  const start = centerTs - half;
  const end = centerTs + half;
  const matches = samples.filter((sample) => sample.ts >= start && sample.ts <= end);
  const source = matches.length ? matches : [nearestFireSample(samples, centerTs)].filter(Boolean);
  const avg = (key) => {
    let sum = 0;
    let count = 0;
    for (const sample of source) {
      const value = sample.values[key];
      if (Number.isFinite(value)) {
        sum += value;
        count += 1;
      }
    }
    return count ? sum / count : null;
  };
  return {
    pm25: avg("pm25"),
    tvoc: avg("tvoc"),
    temp: avg("temp"),
    nox: avg("nox"),
    co: avg("co"),
    co2: avg("co2")
  };
};

const evaluateFireRisk = (current, previous, tempBase) => {
  const pm = {
    key: "pm25",
    label: "PM2.5",
    score: Math.max(
      fireMetricScore(fireRise(current.pm25, previous.pm25), 35, 100),
      fireMetricScore(current.pm25, 75, 150)
    )
  };
  const voc = {
    key: "tvoc",
    label: "TVOC",
    score: Math.max(
      fireMetricScore(fireRise(current.tvoc, previous.tvoc), 100, 200),
      fireMetricScore(current.tvoc, 200, 350)
    )
  };
  const temp = {
    key: "temp",
    label: "온도",
    score: Math.max(
      fireMetricScore(fireRise(current.temp, previous.temp), 3, 5),
      fireMetricScore(fireRise(current.temp, tempBase.temp), 5, 8)
    )
  };
  const nox = {
    key: "nox",
    label: "NOx",
    score: Math.max(
      fireMetricScore(fireRise(current.nox, previous.nox), 1, 2),
      fireMetricScore(current.nox, 2, 5)
    )
  };
  const co = {
    key: "co",
    label: "CO",
    score: Math.max(
      fireMetricScore(fireRise(current.co, previous.co), 5, 20),
      fireMetricScore(current.co, 10, 35)
    )
  };
  const co2 = {
    key: "co2",
    label: "CO₂",
    score: Math.min(1, Math.max(
      fireMetricScore(fireRise(current.co2, previous.co2), 300, 500),
      fireMetricScore(current.co2, 1500, 2500)
    ))
  };

  const coConnected = Number.isFinite(current.co);
  const metrics = [pm, voc, temp, nox, ...(coConnected ? [co] : []), co2];
  const core = [pm, voc, temp, nox, ...(coConnected ? [co] : [])];
  const riskCount = core.filter((metric) => metric.score >= 1.0).length;
  const cautionCount = metrics.filter((metric) => metric.score >= 0.5).length;
  const coPmTogether = coConnected && co.score >= 1.0 && pm.score >= 1.0;
  const fireCandidate = coConnected
    ? riskCount >= 3 || coPmTogether || (co.score >= 1.0 && voc.score >= 1.0 && temp.score >= 1.0)
    : riskCount >= 3;
  const biggestCoreScore = core.reduce((maxScore, metric) => Math.max(maxScore, metric.score), 0);
  const sameTimeBonus = riskCount >= 2 ? 0.5 * (riskCount - 1) : 0;
  const coPmBonus = coPmTogether ? 0.25 : 0;
  const co2Weight = coConnected ? 0.15 : 0.2;
  const totalScore = biggestCoreScore + sameTimeBonus + coPmBonus + co2Weight * co2.score;

  return {
    metrics,
    totalScore,
    riskCount,
    cautionCount,
    fireCandidate,
    coConnected,
    coPmTogether,
    coOnly: coConnected && co.score >= 1.0 && riskCount === 1
  };
};

const fireLevelFor = (evaluation, persistenceGrade) => {
  if (evaluation.coOnly) return { level: "co_only", severity: "critical", label: "CO 위험", title: "CO 상승, 환기 및 연소기기 확인" };
  if (evaluation.fireCandidate && persistenceGrade === 2) {
    return { level: "fire_suspected", severity: "critical", label: "화재 의심", title: "화재 의심, 즉시 확인" };
  }
  if (evaluation.coPmTogether || (evaluation.riskCount >= 3 && persistenceGrade >= 1) || (evaluation.riskCount >= 2 && persistenceGrade === 2)) {
    return { level: "strong_warning", severity: "warning", label: "강한 경고", title: "복합 이상 흐름 확인" };
  }
  if (evaluation.riskCount >= 1 || evaluation.totalScore >= 1.0) {
    return { level: "warning", severity: "warning", label: "경고", title: "원인 확인 필요" };
  }
  if (evaluation.cautionCount >= 1 || evaluation.totalScore >= 0.5) {
    return { level: "notice", severity: "notice", label: "주의", title: "공기질 이상 감지" };
  }
  return { level: "normal", severity: "notice", label: "정상", title: "현재 이상 징후 없음" };
};

const buildFireRiskEvent = async (
  snapshot,
  raw,
  snapshotId,
  now,
  quietHoursWindow,
  options = {}
) => {
  const values = {
    pm25: readNumber(raw?.pm25, raw?.pm02, snapshot?.pm25),
    tvoc: readNumber(raw?.tvoc, raw?.tvocIndex, snapshot?.tvoc),
    temp: readNumber(raw?.temp, raw?.temperature, raw?.atmp, snapshot?.temp, snapshot?.temperature),
    nox: readNumber(raw?.nox, raw?.noxIndex, snapshot?.nox),
    co: readNumber(raw?.co, raw?.co_ppm, raw?.carbon_monoxide, raw?.carbonMonoxide, snapshot?.co),
    co2: readNumber(raw?.co2, raw?.rco2, snapshot?.co2)
  };
  if (!Object.values(values).some(Number.isFinite)) return null;

  const runtimeState = await loadFireRiskRuntimeState(
    options.firestore,
    snapshotId,
    now
  );
  const history = runtimeState.samples || [];
  history.push({ ts: now, values });
  const minTs = now - 35 * 60 * 1000;
  const samples = history.filter((sample) => sample.ts >= minTs);

  const current = averageFireWindow(samples, now, 60 * 1000);
  const previous = averageFireWindow(samples, now - 5 * 60 * 1000, 60 * 1000);
  const tempBase = averageFireWindow(samples, now - 15 * 60 * 1000, 30 * 60 * 1000);
  const evaluation = evaluateFireRisk(current, previous, tempBase);

  const buckets = new Map();
  for (const sample of samples) {
    if (sample.ts < now - 5 * 60 * 1000 || sample.ts > now) continue;
    buckets.set(Math.floor(sample.ts / 60000), sample);
  }
  let candidateCount = 0;
  for (const sample of buckets.values()) {
    const bucketEval = evaluateFireRisk(
      averageFireWindow(samples, sample.ts, 60 * 1000),
      averageFireWindow(samples, sample.ts - 5 * 60 * 1000, 60 * 1000),
      averageFireWindow(samples, sample.ts - 15 * 60 * 1000, 30 * 60 * 1000)
    );
    if (bucketEval.fireCandidate) candidateCount += 1;
  }
  candidateCount = Math.max(0, Math.min(5, candidateCount));
  const persistenceGrade = candidateCount >= 4 ? 2 : candidateCount >= 2 ? 1 : 0;
  const level = fireLevelFor(evaluation, persistenceGrade);
  const entry = runtimeState.entry || ensureEntry(`${snapshotId}:fire_risk`);
  if (level.level === "normal") {
    entry.lastUpdated = now;
    await saveFireRiskRuntimeState(runtimeState, snapshotId, samples, entry, now);
    return null;
  }

  const activeMetrics = evaluation.metrics
    .filter((metric) => metric.score >= 0.5)
    .sort((a, b) => b.score - a.score)
    .map((metric) => metric.label);
  const message = level.level === "fire_suspected"
    ? "여러 지표의 위험 조합이 최근 5분 동안 반복됐습니다. 즉시 현장을 확인하세요."
    : level.level === "co_only"
      ? "CO만 의미 있게 상승했습니다. 환기와 연소기기 상태를 확인하세요."
      : `${activeMetrics.slice(0, 3).join(", ") || "복합 지표"} 변화가 감지되었습니다.`;
  const recommendedAction = level.level === "fire_suspected"
    ? "현장 즉시 확인 및 대피 동선 확보"
    : level.level === "co_only"
      ? "즉시 환기 및 연소기기 확인"
      : "현장 원인 확인 및 환기/연결 장치 작동";

  const priority = severityRank[level.severity] || 1;
  const eventId = `fire_risk-${level.level}-${Math.floor(now / 60000)}`;
  const suppressed = entry.lastEventTs
    && (now - entry.lastEventTs) < SUPPRESS_MS
    && (severityRank[entry.lastEventSeverity] || 0) >= priority;
  if (!suppressed) {
    entry.lastEventTs = now;
    entry.lastEventSeverity = level.severity;
    entry.lastEventId = eventId;
  }
  entry.lastUpdated = now;
  await saveFireRiskRuntimeState(runtimeState, snapshotId, samples, entry, now);

  return {
    type: "fire_risk",
    label: "방재모드",
    severity: level.severity,
    priority,
    title: level.title,
    message,
    recommendedAction,
    value: round(evaluation.totalScore, 2),
    unit: "점",
    eventId,
    topic: "all",
    quietHours: false,
    quietHoursWindow,
    suppressed,
    suppressedUntil: suppressed ? entry.lastEventTs + SUPPRESS_MS : null,
    trend: "fire_risk",
    trendMeta: {
      code: level.level,
      label: level.label,
      coConnected: evaluation.coConnected,
      coMode: evaluation.coConnected ? "co_extended" : "basic",
      riskCount: evaluation.riskCount,
      cautionCount: evaluation.cautionCount,
      candidateCount,
      persistenceGrade
    },
    ventilation: {
      recommended: true,
      suppressed: false,
      reason: null,
      altAction: null
    },
    context: {
      snapshotId,
      location: snapshot?.location || null,
      metrics: evaluation.metrics.map((metric) => ({
        key: metric.key,
        label: metric.label,
        score: round(metric.score, 2)
      })),
      coMode: evaluation.coConnected ? "co_extended" : "basic"
    },
    duration: {
      accumulatedMs: 5 * 60 * 1000,
      requiredMs: 5 * 60 * 1000,
      met: persistenceGrade >= 1,
      source: "fire_risk:pdf"
    },
    hysteresis: {
      trigger: 1.0,
      clear: 0.5,
      value: evaluation.totalScore
    }
  };
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

async function generateAlertsFromSnapshot(snapshot, options = {}) {
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

  const fireRiskEvent = await buildFireRiskEvent(
    snapshot,
    raw,
    snapshotId,
    now,
    quietHoursWindow,
    { firestore: options.firestore }
  );
  if (fireRiskEvent) {
    events.push(fireRiskEvent);
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
