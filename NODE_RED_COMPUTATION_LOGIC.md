# Node-RED flows.json — Complete Computation Logic Extraction

Extracted from `Indoorairqualityappv2-main/flows.json` (4070 lines)

---

## 1. `toNumber` Helper Function (used in HiveMQ Fanout Node)

```js
const toNumber = (value, fallback = 0) => {
    const num = Number(value);
    return Number.isFinite(num) ? num : fallback;
};
```

---

## 2. PM2.5 k-calc Node — "k 계산 (PM2.5 감소구간)"

**Full code:**

```js
// ═══════════════════════════════════════════════════════════════
// PM2.5 Decay Rate (k) Calculation Node
// Output 1: Gauge (k value)
// Output 2: Chart ({ topic: 'PM2.5 Purification', payload: k })
// Output 3: Log entry
// ═══════════════════════════════════════════════════════════════

const WINDOW_MS = 300 * 1000;  // 5분 윈도우
const MIN_SAMPLES = 15;
const BUFFER_LIMIT = 400;
const EPS = 1e-6;
const NOISE_THRESHOLD = 0.99;  // 저농도 컷오프

const now = Date.now();
const timestampIso = new Date(now).toISOString();

// 입력 파싱
let rawValue = msg.payload;
if (rawValue && typeof rawValue === 'object') {
    rawValue = rawValue.pm25 ?? rawValue.value ?? rawValue.pm ?? rawValue.payload;
}
const pm25 = Number(rawValue);

if (!Number.isFinite(pm25) || pm25 <= 0) {
    node.status({ fill: 'red', shape: 'ring', text: 'PM2.5 데이터 없음' });
    return [null, null, null];
}

// 슬라이딩 윈도우 버퍼
let buffer = context.get('pm120sBuffer') || [];
buffer = buffer.filter(entry => now - entry.t <= WINDOW_MS);
buffer.push({ t: now, v: pm25 });
if (buffer.length > BUFFER_LIMIT) {
    buffer = buffer.slice(buffer.length - BUFFER_LIMIT);
}
context.set('pm120sBuffer', buffer);

if (buffer.length < MIN_SAMPLES) {
    node.status({ fill: 'yellow', shape: 'ring', text: `샘플 ${buffer.length}/${MIN_SAMPLES}` });
    return [null, null, null];
}

const maxVal = Math.max(...buffer.map(e => e.v));
if (maxVal < NOISE_THRESHOLD) {
    node.status({ fill: 'grey', shape: 'ring', text: `노이즈 수준 (max=${maxVal.toFixed(2)})` });
    return [null, null, null];
}

// Log-Linear 회귀: ln(PM2.5) vs time
const firstTs = buffer[0].t;
const points = buffer.map(entry => ({
    x: (entry.t - firstTs) / 3600000,  // hours
    y: Math.log(Math.max(entry.v, EPS))
}));

const sums = points.reduce((acc, p) => {
    acc.x += p.x; acc.y += p.y;
    acc.xy += p.x * p.y;
    acc.xx += p.x * p.x;
    acc.yy += p.y * p.y;
    return acc;
}, { x: 0, y: 0, xy: 0, xx: 0, yy: 0 });

const n = points.length;
const denom = (n * sums.xx) - (sums.x * sums.x);
let slope = 0, rSquared = 0;

if (denom !== 0) {
    slope = ((n * sums.xy) - (sums.x * sums.y)) / denom;
    const intercept = (sums.y - slope * sums.x) / n;
    const ssTot = sums.yy - ((sums.y * sums.y) / n);
    const ssRes = points.reduce((acc, p) => {
        const fitted = slope * p.x + intercept;
        return acc + Math.pow(p.y - fitted, 2);
    }, 0);
    rSquared = ssTot === 0 ? 1 : Math.max(0, 1 - (ssRes / ssTot));
}

const kRaw = Number((-slope).toFixed(3));
const kEffective = Number(Math.max(0, kRaw).toFixed(3));

// ★ flow context에 저장 (마스터 노드에서 읽음)
flow.set('k_pm25', kRaw);
flow.set('k_pm25_effective', kEffective);
flow.set('k_pm25_timestamp', now);
flow.set('k_pm25_r2', rSquared);

// 4-Level 분류
function getLevel(k) {
    if (k >= 1.0) return 'HIGH_POS';
    if (k >= 0.2) return 'LOW_POS';
    if (k > -0.1) return 'ZERO';
    return 'NEGATIVE';
}

const level = getLevel(kRaw);
const levelLabels = {
    'HIGH_POS': 'Rapid Decay',
    'LOW_POS': 'Natural Decay',
    'ZERO': 'Stagnant',
    'NEGATIVE': 'Accumulating'
};

// 로그 엔트리
const logEntry = {
    Timestamp: timestampIso,
    kRaw: kRaw,
    kEffective: kEffective,
    R2: Number(rSquared.toFixed(3)),
    PM_Concentration: Number(pm25.toFixed(1)),
    Level: level
};

node.status({
    fill: kRaw < 0 ? 'red' : (kRaw >= 1.0 ? 'green' : 'blue'),
    shape: 'dot',
    text: `${levelLabels[level]} k=${kRaw.toFixed(2)}/h`
});

// 3개 출력
return [
    { payload: kEffective },  // Output 1: Gauge
    { topic: 'PM2.5 Purification', payload: kRaw },  // Output 2: Chart
    { payload: logEntry }  // Output 3: Log
];
```

### Key Constants (PM2.5 k-calc):
| Constant | Value | Purpose |
|---|---|---|
| `WINDOW_MS` | 300000 (5 min) | Sliding window duration |
| `MIN_SAMPLES` | 15 | Minimum samples needed |
| `BUFFER_LIMIT` | 400 | Max buffer size |
| `EPS` | 1e-6 | Epsilon for log(0) protection |
| `NOISE_THRESHOLD` | 0.99 | Low-concentration cutoff (µg/m³) |

### Flow Context Written:
- `k_pm25` — raw k value (can be negative)
- `k_pm25_effective` — max(0, kRaw)
- `k_pm25_timestamp` — Date.now()
- `k_pm25_r2` — R² goodness of fit

---

## 3. CO2 k-calc Node — "k 계산 (CO2) — 환기"

**Full code:**

```js
// ═══════════════════════════════════════════════════════════════
// CO2 Decay Rate (k) Calculation Node - Ventilation Indicator
// Output 1: Text summary
// Output 2: Chart ({ topic: 'CO2 Ventilation', payload: k })
// ═══════════════════════════════════════════════════════════════

const WINDOW_MS = 300 * 1000;  // 5분 윈도우
const MIN_SAMPLES = 15;
const BUFFER_LIMIT = 400;
const CO2_BASELINE = 420;  // 외기 배경농도
const EPS = 1e-6;

const now = Date.now();
const timestampIso = new Date(now).toISOString();

// 입력 파싱
let rawValue = msg.payload;
if (rawValue && typeof rawValue === 'object') {
    rawValue = rawValue.co2 ?? rawValue.value ?? rawValue.payload;
}
const co2 = Number(rawValue);

if (!Number.isFinite(co2) || co2 < 300) {
    node.status({ fill: 'red', shape: 'ring', text: 'CO₂ 데이터 없음' });
    return [null, null];
}

// CO2 - Background (최소 10ppm 보호)
const excess = Math.max(co2 - CO2_BASELINE, 10);

// 슬라이딩 윈도우 버퍼
let buffer = context.get('co2120sBuffer') || [];
buffer = buffer.filter(entry => now - entry.t <= WINDOW_MS);
buffer.push({ t: now, eff: excess, co2 });
if (buffer.length > BUFFER_LIMIT) {
    buffer = buffer.slice(buffer.length - BUFFER_LIMIT);
}
context.set('co2120sBuffer', buffer);

if (buffer.length < MIN_SAMPLES) {
    node.status({ fill: 'yellow', shape: 'ring', text: `CO₂ 샘플 ${buffer.length}/${MIN_SAMPLES}` });
    return [null, null];
}

// Log-Linear 회귀: ln(CO2 - 420) vs time
const firstTs = buffer[0].t;
const points = buffer.map(entry => ({
    x: (entry.t - firstTs) / 3600000,  // hours
    y: Math.log(Math.max(entry.eff, EPS))
}));

const sums = points.reduce((acc, p) => {
    acc.x += p.x; acc.y += p.y;
    acc.xy += p.x * p.y;
    acc.xx += p.x * p.x;
    acc.yy += p.y * p.y;
    return acc;
}, { x: 0, y: 0, xy: 0, xx: 0, yy: 0 });

const n = points.length;
const denom = (n * sums.xx) - (sums.x * sums.x);
let slope = 0, rSquared = 0;

if (denom !== 0) {
    slope = ((n * sums.xy) - (sums.x * sums.y)) / denom;
    const intercept = (sums.y - slope * sums.x) / n;
    const ssTot = sums.yy - ((sums.y * sums.y) / n);
    const ssRes = points.reduce((acc, p) => {
        const fitted = slope * p.x + intercept;
        return acc + Math.pow(p.y - fitted, 2);
    }, 0);
    rSquared = ssTot === 0 ? 1 : Math.max(0, 1 - (ssRes / ssTot));
}

const kRaw = Number((-slope).toFixed(3));
const kEffective = Number(Math.max(0, kRaw).toFixed(3));

// ★ flow context에 저장 (마스터 노드에서 읽음)
flow.set('k_co2', kRaw);
flow.set('k_co2_effective', kEffective);
flow.set('k_co2_timestamp', now);
flow.set('k_co2_r2', rSquared);
flow.set('co2_current', co2);

// 4-Level 분류
function getLevel(k) {
    if (k >= 1.0) return 'HIGH_POS';
    if (k >= 0.2) return 'LOW_POS';
    if (k > -0.1) return 'ZERO';
    return 'NEGATIVE';
}

const level = getLevel(kRaw);
const levelLabels = {
    'HIGH_POS': 'Rapid Decay',
    'LOW_POS': 'Natural Decay',
    'ZERO': 'Stagnant',
    'NEGATIVE': 'Accumulating'
};

// 텍스트 요약
const summary = `CO₂ k=${kRaw.toFixed(2)}/h (${levelLabels[level]}) | ${co2}ppm`;

node.status({
    fill: kRaw < 0 ? 'red' : (kRaw >= 1.0 ? 'cyan' : 'blue'),
    shape: 'dot',
    text: `${levelLabels[level]} k=${kRaw.toFixed(2)}/h`
});

// 2개 출력
return [
    { payload: summary },  // Output 1: Text
    { topic: 'CO2 Ventilation', payload: kRaw }  // Output 2: Chart
];
```

### Key Constants (CO2 k-calc):
| Constant | Value | Purpose |
|---|---|---|
| `WINDOW_MS` | 300000 (5 min) | Sliding window |
| `MIN_SAMPLES` | 15 | Minimum samples |
| `BUFFER_LIMIT` | 400 | Max buffer size |
| `CO2_BASELINE` | 420 ppm | Outdoor background concentration |
| `EPS` | 1e-6 | Log epsilon |

### Key Difference vs PM2.5:
- CO2 uses `excess = Math.max(co2 - CO2_BASELINE, 10)` (subtracts 420 ppm baseline)
- PM2.5 uses raw value directly: `Math.log(Math.max(entry.v, EPS))`

### Flow Context Written:
- `k_co2` — raw k value
- `k_co2_effective` — max(0, kRaw)
- `k_co2_timestamp` — Date.now()
- `k_co2_r2` — R² goodness of fit
- `co2_current` — current CO2 ppm

---

## 4. Hybrid ACH Master Node — "k 통합"

**Full code:**

```js
// ═══════════════════════════════════════════════════════════════
// Hybrid ACH Master - Dual K-Value Analysis
// 4-Level Classification + 5-Scenario Diagnosis
// ═══════════════════════════════════════════════════════════════

const DATA_TTL_MS = 10 * 60 * 1000;  // 10분

const now = Date.now();

// ★ flow context에서 k 값 읽기
const kPm = flow.get('k_pm25') ?? null;
const kCo2 = flow.get('k_co2') ?? null;
const kPmTs = flow.get('k_pm25_timestamp') ?? 0;
const kCo2Ts = flow.get('k_co2_timestamp') ?? 0;
const co2Current = flow.get('co2_current') ?? 0;

// ★ R² 신뢰도 값 읽기
const r2Pm = flow.get('k_pm25_r2') ?? 0;
const r2Co2 = flow.get('k_co2_r2') ?? 0;
const R2_THRESHOLD = 0.7;  // 신뢰도 임계값

// 데이터 유효성 검사
const pmValid = kPm !== null && (now - kPmTs) < DATA_TTL_MS;
const co2Valid = kCo2 !== null && (now - kCo2Ts) < DATA_TTL_MS;

if (!pmValid && !co2Valid) {
    node.status({ fill: 'yellow', shape: 'ring', text: 'k 데이터 수집 중' });
    return [null, null, null, { payload: '센서 데이터 대기중...' }];
}

// 유효한 값만 사용 (없으면 0)
const kPmVal = pmValid ? kPm : 0;
const kCo2Val = co2Valid ? kCo2 : 0;

// ═══════════════════════════════════════════════════════════════
// 4-Level Classification
// ═══════════════════════════════════════════════════════════════
function getLevel(k) {
    if (k >= 1.0) return 'HIGH_POS';   // Rapid Decay
    if (k >= 0.2) return 'LOW_POS';    // Natural Decay
    if (k > -0.1) return 'ZERO';       // Stagnant
    return 'NEGATIVE';                  // Accumulating
}

// CADR 등급 계산 함수
function getCadrGrade(k) {
    if (k >= 2.0) return 'S';
    if (k >= 1.0) return 'A';
    if (k >= 0.5) return 'B';
    return 'C';
}

const levelPm = getLevel(kPmVal);
const levelCo2 = getLevel(kCo2Val);

// ★ 개별 CADR 등급
const gradePm25 = getCadrGrade(kPmVal);
const gradeCo2 = getCadrGrade(kCo2Val);

// ═══════════════════════════════════════════════════════════════
// 5-Scenario Diagnosis Matrix
// ═══════════════════════════════════════════════════════════════
let status = '';
let statusKr = '';
let action = '';
let actionKr = '';
let mode = '';

// Scenario 1: Purification Dominant (Sealed)
if (levelPm === 'HIGH_POS' && (levelCo2 === 'LOW_POS' || levelCo2 === 'ZERO')) {
    mode = 'purification';
}
// Scenario 2: Ventilation Dominant
else if ((levelPm === 'LOW_POS' || levelPm === 'ZERO' || levelPm === 'NEGATIVE') && levelCo2 === 'HIGH_POS') {
    mode = 'ventilation';
}
// Scenario 3: Combined Decay
else if (levelPm === 'HIGH_POS' && levelCo2 === 'HIGH_POS') {
    mode = 'combined';
}
// Scenario 5: Accumulating (Pollution Event)
else if ((levelPm === 'NEGATIVE' && levelCo2 !== 'HIGH_POS') || (levelCo2 === 'NEGATIVE' && levelPm !== 'HIGH_POS')) {
    mode = 'polluting';
}
// Scenario 4: Stagnant
else {
    mode = 'stagnant';
}

// ═══════════════════════════════════════════════════════════════
// k_final Selection & Smoothing
// ═══════════════════════════════════════════════════════════════
let kFinal;
let dominantSource;

if (kPmVal < 0 && co2Valid) {
    kFinal = Math.max(kCo2Val, 0);
    dominantSource = 'CO2';
} else if (pmValid && co2Valid) {
    if (kPmVal >= kCo2Val) {
        kFinal = kPmVal;
        dominantSource = 'PM2.5';
    } else {
        kFinal = kCo2Val;
        dominantSource = 'CO2';
    }
} else if (pmValid) {
    kFinal = kPmVal;
    dominantSource = 'PM2.5';
} else {
    kFinal = kCo2Val;
    dominantSource = 'CO2';
}

// 스무딩 없음 — 원본 kFinal 사용

// ═══════════════════════════════════════════════════════════════
// CADR Metrics
// ═══════════════════════════════════════════════════════════════
const kEffective = Math.max(kFinal, 0);
const t50 = kEffective > 0 ? Math.round((Math.log(2) / kEffective) * 60) : null;
const t50Pm25 = kPmVal > 0.001 ? Math.round((Math.log(2) / kPmVal) * 60) : 999;
const t50Co2 = kCo2Val > 0.001 ? Math.round((Math.log(2) / kCo2Val) * 60) : 999;

let grade = getCadrGrade(kEffective);
let index = grade === 'S' ? 4 : grade === 'A' ? 3 : grade === 'B' ? 2 : 1;

const cadr = {
    k: Number(kFinal.toFixed(2)),
    kEffective: Number(kEffective.toFixed(2)),
    t50_min: t50,
    grade,
    index,
    mode,
    dominantSource,
    kPm25: Number(kPmVal.toFixed(2)),
    kCo2: Number(kCo2Val.toFixed(2)),
    gradePm25: gradePm25,
    gradeCo2: gradeCo2,
    t50Pm25: t50Pm25,
    t50Co2: t50Co2,
    updatedAt: new Date(now).toISOString()
};

flow.set('purifier_cadr_latest', cadr);
```

---

## 5. ALL Formulas Summary

### 5a. t50 (Half-life) Formula
```
t50 [minutes] = (ln(2) / k) * 60
             = (0.693 / k) * 60
```
Where k is in units of 1/hour.

- If k ≤ 0.001: t50 = 999 (sentinel value)
- If k ≤ 0: t50 = null

### 5b. t90 (90% removal) Formula
```
t90 [minutes] = (ln(10) / k) * 60
             = (2.303 / k) * 60
```

### 5c. Log-Linear Regression (shared by PM2.5 and CO2 k-calc)
```
Model: ln(C) = slope * t + intercept  (where t in hours)
k_raw = -slope

R² = 1 - (SS_res / SS_tot)
SS_tot = Σ(y²) - (Σy)²/n
SS_res = Σ(y - ŷ)²

k_effective = max(0, k_raw)
```

---

## 6. CADR Grading Thresholds (S/A/B/C)

```js
function getCadrGrade(k) {
    if (k >= 2.0) return 'S';   // index = 4
    if (k >= 1.0) return 'A';   // index = 3
    if (k >= 0.5) return 'B';   // index = 2
    return 'C';                  // index = 1
}
```

| Grade | k range (1/h) | t50 (min) | t90 (min) | Meaning |
|-------|---------------|-----------|-----------|---------|
| C | < 0.5 | ≥ 83 | ≥ 276 | Very slow purification |
| B | 0.5–1.0 | 41–83 | 138–276 | Normal (natural ventilation) |
| A | 1.0–2.0 | 21–41 | 69–138 | Fast purification |
| S | ≥ 2.0 | ≤ 21 | ≤ 69 | Very fast purification |

---

## 7. 4-Level k Classification

```js
function getLevel(k) {
    if (k >= 1.0) return 'HIGH_POS';   // 급속감소 (Rapid Decay)
    if (k >= 0.2) return 'LOW_POS';    // 자연감소 (Natural Decay)
    if (k > -0.1) return 'ZERO';       // 정체 (Stagnant)
    return 'NEGATIVE';                  // 축적중 (Accumulating)
}
```

---

## 8. 5-Scenario Diagnosis Matrix

| # | Scenario | PM2.5 Level | CO2 Level | Mode |
|---|----------|-------------|-----------|------|
| 1 | PM Rapid Decay (Sealed) | HIGH_POS | LOW_POS or ZERO | `purification` |
| 2 | CO2 Rapid Decay (Ventilation) | LOW_POS/ZERO/NEGATIVE | HIGH_POS | `ventilation` |
| 3 | Combined Decay | HIGH_POS | HIGH_POS | `combined` |
| 4 | Stagnant | (else) | (else) | `stagnant` |
| 5 | Concentration Rising | NEGATIVE (and CO2 not HIGH_POS) | OR CO2 NEGATIVE (and PM not HIGH_POS) | `polluting` |

---

## 9. IPI (Indoor Purification Index) — "바이러스 잔류 위험지수"

**Full code:**

```js
const c = msg.cadr;
if (!c) {
    return [null, null];
}

// CO2 k값 가져오기 (IPI는 CO2 기반)
const kCo2Raw = Number(flow.get('k_co2')) || 0;
const kPm25Raw = Number(flow.get('k_pm25')) || 0;

// ★ k가 음수면 0으로 처리 (게이지 표시용)
const kCo2 = Math.max(kCo2Raw, 0);
const kPm25 = Math.max(kPm25Raw, 0);

// ★ k가 0 이하면 등급 1 (경고)로 처리
if (kCo2Raw <= 0) {
    const ipi = {
        k_co2: 0,
        k_pm25: kPm25,
        t90_co2: 999,
        t90_pm25: kPm25 > 0 ? Math.round(Math.log(10) / kPm25 * 60) : 999,
        level: '경고',
        score: 1,
        updatedAt: c.updatedAt || Date.now()
    };
    flow.set('purifier_ipi_latest', ipi);
    return [{ payload: 1, ipi }, { ... }];
}

// 90% 제거시간 t90 [분] = ln(10)/k [h] → 분 (CO2 기준)
const t90_co2 = Math.round(Math.log(10) / kCo2 * 60);
const t90_pm25 = kPm25 > 0 ? Math.round(Math.log(10) / kPm25 * 60) : 999;

// IPI 등급 (CO2 k값 단독 기준)
let level, score, shortMsg;
if (kCo2 >= 3.0) {
    level = '안심';    // Safe
    score = 3;
    shortMsg = '빠른 환기';
} else if (kCo2 >= 1.0) {
    level = '보통';    // Normal
    score = 2;
    shortMsg = '보통 환기';
} else {
    level = '경고';    // Warning
    score = 1;
    shortMsg = '환기 부족';
}

const ipi = {
    k_co2: Number(kCo2.toFixed(2)),
    k_pm25: Number(kPm25.toFixed(2)),
    t90_co2,
    t90_pm25,
    level,
    score,
    updatedAt: c.updatedAt || Date.now()
};

flow.set('purifier_ipi_latest', ipi);
```

### IPI Grading Table:

| Level | Score | k_CO2 range | t90 | Meaning |
|-------|-------|-------------|-----|---------|
| 경고 (Warning) | 1 | < 1.0 | > 140 min | Slow recovery, high residual risk |
| 보통 (Normal) | 2 | 1.0–3.0 | 46–140 min | Normal recovery, needs management |
| 안심 (Safe) | 3 | ≥ 3.0 | ≤ 46 min | Fast recovery, low residual risk |

**NOTE:** The IPI in the snapshot builder has a DIFFERENT scale (4 levels):
```js
// In HiveMQ fanout node, IPI fallback:
if (kCo2Val >= 3.0) { level = '안심'; score = 4; }
else if (kCo2Val >= 1.0) { level = '보통'; score = 3; }
else if (kCo2Val >= 0.3) { level = '주의'; score = 2; }
else { level = '경고'; score = 1; }
```
This is the fallback when `purifier_ipi_latest` is not yet populated. The dedicated IPI node uses 3 levels (score 1-3).

---

## 10. Respiratory Health Index — "호흡기 건강 지표"

**Full code:**

```js
const d = msg.payload || {};

const temp = d.temp ?? d.temperature;
const rh = d.humidity ?? flow.get('humidity');
const tvoc = d.tvoc ?? flow.get('tvoc');

if (temp == null || rh == null || tvoc == null) {
    return [
        { payload: 0, resp: { temp, rh, tvoc, level: "데이터 부족" } },
        { payload: `호흡기 데이터 부족 (T=${temp}, RH=${rh}, TVOC=${tvoc})` }
    ];
}

let score = 100;

// --- Humidity scoring ---
let rhMsg = "";
if (rh >= 40 && rh <= 60) {
    rhMsg = "습도 양호";
} else if ((rh >= 30 && rh < 40) || (rh > 60 && rh <= 70)) {
    score -= 10;
    rhMsg = "약간 건조/다습";
} else if ((rh >= 20 && rh < 30) || (rh > 70 && rh < 80)) {
    score -= 25;
    rhMsg = "건조/다습 — 관리 필요";
} else { // <20 또는 ≥80
    score -= 35;
    rhMsg = "심한 건조/다습 — 호흡기 부담";
}

// --- Temperature scoring ---
let tMsg = "";
if (temp >= 20 && temp <= 24) {
    tMsg = "쾌적한 온도";
} else if ((temp >= 18 && temp < 20) || (temp > 24 && temp <= 26)) {
    score -= 10;
    tMsg = "약간 춥거나 더운 편";
} else if ((temp >= 16 && temp < 18) || (temp > 26 && temp < 28)) {
    score -= 20;
    tMsg = "온도 민감 구간";
} else { // <16 or ≥28
    score -= 30;
    tMsg = "온도 위험 구간";
}

// --- TVOC scoring ---
let vocMsg = "";
if (tvoc < 200) {
    vocMsg = "VOC 낮음";
} else if (tvoc < 400) {
    score -= 10;
    vocMsg = "약간 높음 — 환기 권장";
} else if (tvoc < 1000) {
    score -= 20;
    vocMsg = "높음";
} else {
    score -= 30;
    vocMsg = "매우 높음";
}

if (score < 0) score = 0;
if (score > 100) score = 100;

let level;
if (score >= 80) level = "좋음";
else if (score >= 60) level = "보통";
else if (score >= 40) level = "주의";
else level = "경고";
```

### Respiratory Scoring Deductions:

| Factor | Range | Deduction |
|--------|-------|-----------|
| Humidity | 40–60 | 0 |
| Humidity | 30–40 or 60–70 | -10 |
| Humidity | 20–30 or 70–80 | -25 |
| Humidity | <20 or ≥80 | -35 |
| Temperature | 20–24 | 0 |
| Temperature | 18–20 or 24–26 | -10 |
| Temperature | 16–18 or 26–28 | -20 |
| Temperature | <16 or ≥28 | -30 |
| TVOC | < 200 | 0 |
| TVOC | 200–400 | -10 |
| TVOC | 400–1000 | -20 |
| TVOC | ≥ 1000 | -30 |

---

## 11. Infection Risk Index — "면역, 감염 위험 지표"

**Full code:**

```js
const d = msg.payload || {};
const co2 = d.co2 ?? flow.get('co2');
const rh = d.humidity ?? d.rh ?? d.RH ?? flow.get('humidity');

if (co2 == null || rh == null) { ... return; }

let co2Band;
if (co2 < 800)        co2Band = 0;
else if (co2 < 1000)  co2Band = 1;
else if (co2 < 1500)  co2Band = 2;
else                  co2Band = 3;

let rhBand;
if (rh >= 40 && rh <= 60) {
    rhBand = 0;
} else if ((rh >= 30 && rh < 40) || (rh > 60 && rh <= 70)) {
    rhBand = 1;
} else if ((rh >= 20 && rh < 30) || (rh > 70 && rh < 80)) {
    rhBand = 2;
} else {
    rhBand = 3;
}

const combo = co2Band + rhBand;

const map = [10, 25, 40, 55, 70, 85, 95];
let score = map[Math.max(0, Math.min(combo, 6))];

let level;
if (score < 30) level = "낮음";        // Low
else if (score < 60) level = "보통";    // Normal
else if (score < 80) level = "높음";    // High
else level = "매우 높음";               // Very High
```

### Infection Risk Combo Map:

| combo (co2Band + rhBand) | score |
|---------------------------|-------|
| 0 | 10 |
| 1 | 25 |
| 2 | 40 |
| 3 | 55 |
| 4 | 70 |
| 5 | 85 |
| 6 | 95 |

---

## 12. Cardiovascular Protection Score — "심혈관 보호점수"

**Full code:**

```js
const d = msg.payload || {};
let pm = d.pm25 ?? d.pm ?? d.pm2_5;
if (pm == null) {
    pm = flow.get('pm');
}
const c = msg.cadr || {};
let k = (typeof c.kEffective === 'number') ? c.kEffective : c.k;

if (pm == null || k == null) { return [null, null]; }
if (k <= 0) k = 0.1;

const now = Date.now();
const windowMs = 10 * 60 * 1000; // 10 min (demo: normally 24h)

let hist = context.get('hist') || [];
hist.push({ ts: now, pm, k });
hist = hist.filter(d => now - d.ts <= windowMs);
context.set('hist', hist);

const HIGH_TH = 5; // PM2.5 high threshold (demo: normally 25)
const high = hist.filter(d => d.pm > HIGH_TH);
const total = hist.length;

let highHours = 0;
if (high.length > 0) {
    let dtSum = 0;
    for (let i = 1; i < high.length; i++) {
        dtSum += (high[i].ts - high[i - 1].ts);
    }
    const avgDt = (dtSum > 0 && high.length > 1) ? dtSum / (high.length - 1) : 60 * 1000;
    highHours = high.length * avgDt / (1000 * 60 * 60);
}

let kAvg;
if (high.length > 0) {
    kAvg = high.reduce((a, b) => a + (b.k > 0 ? b.k : 0.1), 0) / high.length;
} else if (hist.length > 0) {
    kAvg = hist.reduce((a, b) => a + (b.k > 0 ? b.k : 0.1), 0) / hist.length;
} else {
    kAvg = 0.1;
}
if (!Number.isFinite(kAvg) || kAvg <= 0) kAvg = 0.1;

// Risk formula: highHours × (1 / kAvg)
const riskRaw = highHours === 0 ? 0 : highHours * (1 / kAvg);

const L = 8;  // Scale factor
let score = 100 * (1 - (riskRaw / L));
if (score < 0) score = 0;
if (score > 100) score = 100;
score = Math.round(score);

let level;
if (score >= 80) level = "우수";     // Excellent
else if (score >= 60) level = "양호"; // Good
else if (score >= 40) level = "주의"; // Caution
else level = "위험";                  // Danger

flow.set('senior_cardio_latest', cardio);
```

### Cardiovascular Formula:
```
riskRaw = highHours * (1 / kAvg)
score = 100 * (1 - riskRaw / L)    where L = 8
score = clamp(score, 0, 100)
```

---

## 13. Sleep Comfort Index — "쾌적 수면지수"

**Full code:**

```js
const d = msg.payload || {};
const co2 = d.co2 ?? flow.get('co2');
const tvoc = d.tvoc ?? flow.get('tvoc');

if (co2 == null) { return [null, null]; }

const windowMs = 10 * 60 * 1000;  // 10 min (demo: normally overnight 22:00-06:00)
let hist = context.get('sleepHist') || [];
hist.push({ ts: now.getTime(), co2, tvoc });
hist = hist.filter(d => nowMs - d.ts <= windowMs);
context.set('sleepHist', hist);

if (hist.length < 1) { return fallback (80); }

const goodCo2 = hist.filter(d => d.co2 != null && d.co2 < 1000).length / hist.length;

const vocSamples = hist.filter(d => d.tvoc != null);
let goodVoc;
if (vocSamples.length > 0) {
    goodVoc = vocSamples.filter(d => d.tvoc < 200).length / vocSamples.length;
} else {
    goodVoc = 0.7;  // default when no TVOC data
}

const scoreRaw = (goodCo2 * 0.7 + goodVoc * 0.3) * 100;
let score = Math.round(scoreRaw);
score = clamp(score, 0, 100);

let level;
if (score >= 80) level = "좋음";
else if (score >= 60) level = "보통";
else if (score >= 40) level = "나쁨";
else level = "매우 나쁨";

flow.set('senior_sleep_latest', sleep);
```

### Sleep Formula:
```
goodCo2 = (count of samples where co2 < 1000) / totalSamples
goodVoc = (count of VOC samples where tvoc < 200) / vocSampleCount   [default 0.7]
score = (goodCo2 × 0.7 + goodVoc × 0.3) × 100
```

---

## 14. HiveMQ Snapshot Builder — "HiveMQ payload fanout"

### Default/Fallback Values in Snapshot:

```js
const snapshot = {
    raw: {
        pm25: toNumber(base.pm25),              // fallback 0
        co2: toNumber(base.co2, 400),           // fallback 400
        tvoc: toNumber(base.tvoc),              // fallback 0
        nox: toNumber(base.nox),                // fallback 0
        temp: toNumber(base.temp, 24),          // fallback 24
        humidity: toNumber(base.humidity, 45)    // fallback 45
    },
    health: {
        respiratoryIndex: toNumber(base.respiratoryIndex, 70),
        immunityRisk: toNumber(base.immunityRisk, 30),
        cognitiveFocus: toNumber(base.cognitiveFocus, 70),
        cardioScore: toNumber(base.cardioScore, 80),
        cardioRisk: toNumber(base.cardioRisk, 20),
        sleepComfort: toNumber(base.sleepComfort, 75),
        purifier: {
            k: toNumber(base.k, 1.2),
            kEffective: toNumber(base.kEffective, 1.0),
            t50_min: toNumber(base.t50_min, 30),
            cadrIndex: toNumber(base.cadrIndex, 3),
            cadrGrade: base.cadrGrade || 'B'
        },
        ipi: {
            k: toNumber(base.ipi && base.ipi.k, 1.0),
            t90_min: toNumber(base.ipi && base.ipi.t90_min, 60),
            level: 'default' → '보통',
            score: toNumber(base.ipi && base.ipi.score, 2)
        }
    }
};
```

### Senior > Ventilation t50 calculation:
```js
t50Minutes: Math.max(10, Math.round(60 / Math.max(0.1, toNumber(base.k, 1.2))))
```

### Dual-k values read from flow context:
```js
const kPm25 = toNumber(flow.get('k_pm25'), 0);
const kCo2 = toNumber(flow.get('k_co2'), 0);
const r2Pm25 = toNumber(flow.get('k_pm25_r2'), 0);
const r2Co2 = toNumber(flow.get('k_co2_r2'), 0);
const R2_THRESHOLD = 0.7;
```

### CADR Object (in purification output):

```js
// t50 계산 (각각) - 반감기
const t50_pm25 = kPmVal > 0.001 ? Math.round(0.693 / kPmVal * 60) : 999;
const t50_co2 = kCo2Val > 0.001 ? Math.round(0.693 / kCo2Val * 60) : 999;

// CADR 등급 계산 (듀얼)
const kMax = Math.max(kPmVal, kCo2Val);
let grade = 'C', index = 1;
if (kMax >= 2) { grade = 'S'; index = 4; }
else if (kMax >= 1) { grade = 'A'; index = 3; }
else if (kMax >= 0.5) { grade = 'B'; index = 2; }

// PM2.5 개별 등급
let gradePm25 = 'C';
if (kPmVal >= 2) gradePm25 = 'S';
else if (kPmVal >= 1) gradePm25 = 'A';
else if (kPmVal >= 0.5) gradePm25 = 'B';

// CO2 개별 등급 (same thresholds)
let gradeCo2 = 'C';
if (kCo2Val >= 2) gradeCo2 = 'S';
else if (kCo2Val >= 1) gradeCo2 = 'A';
else if (kCo2Val >= 0.5) gradeCo2 = 'B';
```

### IPI in snapshot (fallback when purifier_ipi_latest missing):
```js
// t90 계산 (각각)
const t90_pm25 = kPmVal > 0.001 ? Math.round(2.303 / kPmVal * 60) : 999;
const t90_co2 = kCo2Val > 0.001 ? Math.round(2.303 / kCo2Val * 60) : 999;

// IPI 등급 (CO2 k값 단독 기준)
let level = '양호'; let score = 3;
if (kCo2Val >= 3.0) { level = '안심'; score = 4; }
else if (kCo2Val >= 1.0) { level = '보통'; score = 3; }
else if (kCo2Val >= 0.3) { level = '주의'; score = 2; }
else { level = '경고'; score = 1; }
```

---

## 15. Alert/Warning Thresholds (from "우선순위 알림 감지")

### PM2.5 Thresholds:
| Severity | Limit | Hysteresis Clear |
|----------|-------|------------------|
| notice | ≥ 15 µg/m³ | clearBelow: 12 |
| warning | ≥ 35 µg/m³ | |
| critical | ≥ 55 µg/m³ | |
| minDurationMs | 90s | |

### CO2 Thresholds:
| Severity | Limit | Hysteresis Clear |
|----------|-------|------------------|
| notice | ≥ 800 ppm | clearBelow: 700 |
| warning | ≥ 1000 ppm | |
| critical | ≥ 1500 ppm | |
| minDurationMs | 120s | |

### TVOC Thresholds:
| Severity | Limit | Hysteresis Clear |
|----------|-------|------------------|
| notice | ≥ 200 | clearBelow: 150 |
| warning | ≥ 300 | |
| critical | ≥ 400 | |
| minDurationMs | 120s | |

### NOx Thresholds:
| Severity | Limit | Hysteresis Clear |
|----------|-------|------------------|
| warning | ≥ 2 | clearBelow: 0.5 |
| minDurationMs | 90s | |

### Respiratory Score Thresholds:
| Severity | Limit | Direction |
|----------|-------|-----------|
| warning | ≤ 60 | compare: 'lte' |
| critical | ≤ 40 | clearAbove: 65 |
| minDurationMs | 5 min | |

### Infection Risk Thresholds:
| Severity | Limit | Direction |
|----------|-------|-----------|
| warning | ≥ 60 | compare: 'gte' |
| critical | ≥ 80 | clearBelow: 55 |
| minDurationMs | 5 min | |

### Focus/CO2 Thresholds:
| Severity | Limit |
|----------|-------|
| warning | ≥ 1000 ppm |
| critical | ≥ 1500 ppm |
| clearBelow | 900 |
| minDurationMs | 3 min |

### Cardiovascular Score Thresholds:
| Severity | Limit |
|----------|-------|
| warning | ≤ 60 |
| critical | ≤ 40 |
| clearAbove | 65 |
| minDurationMs | 10 min |

### Sleep Quality Thresholds:
| Severity | Limit |
|----------|-------|
| warning | ≤ 60 |
| critical | ≤ 40 |
| clearAbove | 65 |
| minDurationMs | 10 min |

### Mold Risk Thresholds:
| Severity | Limit |
|----------|-------|
| notice | ≥ 2 |
| warning | ≥ 3 |
| critical | ≥ 4 |
| clearBelow | 1 |
| minDurationMs | 10 min |

### Alert System Constants:
```js
const SUPPRESS_MS = 30 * 60 * 1000;     // 30 min suppression
const DEFAULT_MIN_DURATION = 90 * 1000;  // 90 sec default hold
const QUIET_HOURS = { start: 22, end: 7 };
const severityRank = { notice: 1, warning: 2, critical: 3 };
```

### Trend Classification (k-based):
```js
if (k >= 1.5) { code = 'fast_drop'; label = '급속 감소'; }
else if (k >= 0.5) { code = 'slow_drop'; label = '완만 감소'; }
else if (k >= -0.05) { code = 'flat'; label = '정체'; }
else { code = 'rising'; label = '상승'; }
```

---

## 16. Data Conversion Node — "🔄 데이터 변환 (API → MQTT 형식)"

### Dew Point:
```js
function calculateDewPoint(temp, humidity) {
    const a = 17.27;
    const b = 237.7;
    const alpha = ((a * temp) / (b + temp)) + Math.log(humidity / 100);
    return (b * alpha) / (a - alpha);
}
```

### Discomfort Index:
```js
function calculateDiscomfortIndex(temp, humidity) {
    const di = 0.81 * temp + 0.01 * humidity * (0.99 * temp - 14.3) + 46.3;
    return Math.round(di * 10) / 10;
}
```

### Discomfort Level:
```js
function getDiscomfortLevel(di) {
    if (di < 68) return { level: '쾌적', color: '#4CAF50', score: 100 };
    if (di < 75) return { level: '보통', color: '#FFC107', score: 80 };
    if (di < 80) return { level: '약간 불쾌', color: '#FF9800', score: 60 };
    return { level: '불쾌', color: '#F44336', score: 40 };
}
```

### US AQI from PM2.5:
```js
function calculateUSAQI(pm25) {
    const ranges = [
        { cLow: 0, cHigh: 12, iLow: 0, iHigh: 50 },
        { cLow: 12.1, cHigh: 35.4, iLow: 51, iHigh: 100 },
        { cLow: 35.5, cHigh: 55.4, iLow: 101, iHigh: 150 },
        { cLow: 55.5, cHigh: 150.4, iLow: 151, iHigh: 200 },
        { cLow: 150.5, cHigh: 250.4, iLow: 201, iHigh: 300 },
        { cLow: 250.5, cHigh: 500.4, iLow: 301, iHigh: 500 }
    ];
    for (const bp of ranges) {
        if (pm25 >= bp.cLow && pm25 <= bp.cHigh) {
            const aqi = ((bp.iHigh - bp.iLow) / (bp.cHigh - bp.cLow)) * (pm25 - bp.cLow) + bp.iLow;
            return Math.round(aqi);
        }
    }
    return pm25 > 500 ? 500 : 0;
}
```

### AQI Level:
```js
function getAQILevel(aqi) {
    if (aqi <= 50) return { level: '좋음', color: '#00E400', category: 'Good' };
    if (aqi <= 100) return { level: '보통', color: '#FFFF00', category: 'Moderate' };
    if (aqi <= 150) return { level: '민감군 주의', color: '#FF7E00', category: 'USG' };
    if (aqi <= 200) return { level: '나쁨', color: '#FF0000', category: 'Unhealthy' };
    if (aqi <= 300) return { level: '매우 나쁨', color: '#8F3F97', category: 'Very Unhealthy' };
    return { level: '위험', color: '#7E0023', category: 'Hazardous' };
}
```

---

## 17. Mold Risk — (inside "🔄 새로운 데이터 처리" node)

```js
// 4-level mold risk
let moldRiskLevel = 1;
if (durationHours > 24) {
    moldRiskLevel = 4;  // 위험: 24h+ high humidity
} else if (humidity > 70) {
    moldRiskLevel = 3;  // 경고: >70% humidity
} else if (humidity > 60 && pm25 > 35) {
    moldRiskLevel = 3;  // 경고: >60% humidity AND PM2.5 bad
} else if (humidity > 60) {
    moldRiskLevel = 2;  // 주의: >60% humidity
}
// else level 1: 안전
```

---

## 18. Apparent Temperature (Seasonal) — "체감온도 통합 계산"

### Summer (체감온도):
```js
// Stull wet-bulb approximation
let Tw = Ta * Math.atan(0.151977 * Math.pow(RH + 8.313659, 0.5)) +
    Math.atan(Ta + RH) - Math.atan(RH - 1.676331) +
    0.00391838 * Math.pow(RH, 1.5) * Math.atan(0.023101 * RH) - 4.686035;
let Tw2 = Tw * Tw;
let TwTa = Tw * Ta;
let sTemp = -0.2442 + (0.55399 * Tw) + (0.45535 * Ta) - (0.0022 * Tw2) + (0.00278 * TwTa) + 3.0;
```

### Summer Risk Levels:
```
≥ 38°C → 위험 (Danger)
≥ 35°C → 경고 (Warning)
≥ 33°C → 주의 (Caution)
< 33°C → 관심 (Watch)
```

### Winter (Wind Chill):
```js
// Conditions: Ta ≤ 10°C AND V_ms ≥ 1.3 m/s
const V_kmh = V_ms * 3.6;
const V_pow = Math.pow(V_kmh, 0.16);
let calc_temp = 13.12 + (0.6215 * Ta) - (11.37 * V_pow) + (0.3965 * Ta * V_pow);
```

### Winter Risk Levels:
```
≤ -15°C → 매우 위험
≤ -10°C → 동상 위험
≤  -5°C → 손발 시림
>  -5°C → 관심
```

### Season Mode:
```js
// Month 5-9 → 'summer', Month 10-4 → 'winter'
```

---

## 19. Flow Context Variables Summary (how k-values flow node-to-node)

### Written by PM2.5 k-calc:
- `flow.k_pm25` — raw k (can be negative)
- `flow.k_pm25_effective` — max(0, kRaw)
- `flow.k_pm25_timestamp` — ms epoch
- `flow.k_pm25_r2` — R² goodness of fit

### Written by CO2 k-calc:
- `flow.k_co2` — raw k (can be negative)
- `flow.k_co2_effective` — max(0, kRaw)
- `flow.k_co2_timestamp` — ms epoch
- `flow.k_co2_r2` — R²
- `flow.co2_current` — current CO2 ppm

### Written by Hybrid ACH Master:
- `flow.purifier_cadr_latest` — full CADR object

### Written by IPI Node:
- `flow.purifier_ipi_latest` — full IPI object

### Written by Health Nodes:
- `flow.child_resp_latest` — respiratory scores
- `flow.child_inf_latest` — infection risk scores
- `flow.child_focus_latest` — focus/CO2 scores
- `flow.senior_cardio_latest` — cardiovascular scores
- `flow.senior_sleep_latest` — sleep scores
- `flow.mold_latest` — mold risk data
- `flow.seasonal_apparent_latest` — apparent temperature

### Written by Location/API Nodes:
- `flow.latest_api_data` — outdoor API data
- `flow.sensor_stats_latest` — stats (RMSE, MAPE, CV, R²)
- `flow.location_override` — GPS location

### Read by Fanout (snapshot builder):
All of the above are read to build the 5 MQTT outputs (snapshot, child, senior, purification, locationDetail).

---

## 20. calculateT50Minutes Helper (used in CSV nodes)

```js
const calculateT50Minutes = (kValue) => {
    if (kValue == null || !Number.isFinite(kValue) || kValue <= 0) {
        return null;
    }
    return Math.round((Math.log(2) / kValue) * 60);
};
```

---

## 21. No EMA / Smoothing Applied

The Hybrid ACH Master explicitly states:
```js
// 스무딩 없음 — 원본 kFinal 사용
```
No exponential moving average or smoothing is applied to k-values.

---

## 22. Focus Environment (CO2 thresholds for children)

```js
// "어린이 모드 → flow 저장 (집중)"
if (co2 < 700) {
    level = '좋음';        action = '현재 상태 유지';
} else if (co2 < 1000) {
    level = '보통';        action = '10분 환기 권장';
} else if (co2 < 1500) {
    level = '주의';        action = '즉시 환기';
} else {
    level = '높음';        action = '반드시 환기';
}
```

---

## 23. Apparent Temperature Thresholds (Alerts)

```js
// Summer:
if (apparentTemp >= 38) severity = 'critical';
else if (apparentTemp >= 35) severity = 'warning';
else if (apparentTemp >= 33) severity = 'notice';

// Winter:
if (apparentTemp <= -15) severity = 'critical';
else if (apparentTemp <= -10) severity = 'warning';
else if (apparentTemp <= -5) severity = 'notice';
```

---

## 24. R² Threshold

```js
const R2_THRESHOLD = 0.7;  // Used for accuracy warnings
// pmAccuracyWarning: r2Pm25 < R2_THRESHOLD
// co2AccuracyWarning: r2Co2 < R2_THRESHOLD
```
