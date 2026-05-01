# Cleanair 앱 — 전체 구동 원리 및 파이프라인 분석

> 분석 기준일: 2026-04-30
> 분석 범위: `Indoorairqualityappv2-main/src/flutter` (Flutter, AndroidManifest 라벨 = "Cleanair") + `iaq-v2-firebase/functions` (활성 백엔드) + `iaq-v2-firebase/firmware` (ESPHome 펌웨어)
> 분석 방식: 소스 직접 정독 (`main.dart`, `air_quality_controller.dart`, `firestore_snapshot_service.dart`, `nodered_health_engine.dart`, `external_api_service.dart`, `device_binding_service_v2.dart`, `push_notification_service_v2.dart`, `alert_notification_engine.dart`, `notification_preferences.dart`, `local_snapshot_store.dart`, `background_service.dart`, `home_page.dart`, `settings_view.dart`, `tasmota_plug_service.dart`, `airgradient_local_api.dart`, `led_control_service.dart`, `index.js`, `alertEngine.js`, `plug_mqtt_worker.js`, `firestore.rules`, ESPHome YAML)

---

## 0. 한눈에 보기

```
┌──────────────────┐    HTTP POST(5s)    ┌───────────────────────┐
│  AirGradient ONE │───────────────────▶│ Firebase Functions    │
│  (ESPHome)       │  /ingest            │ • ingest              │
│  + OLED PIN      │   X-API-Key         │ • generateDeviceCode  │
│  (boot 1회)      │───────────────────▶│ • claimDevice          │
└──────────────────┘                     │ • registerDevice      │
        ▲                                 │ • updatePreferences   │
        │ LAN /config (PUT)               │ • relay (sub-routes)  │
        │ LAN /measures/current (GET)     │ • plug control APIs   │
        │                                 │ • alertEngine         │
        │                                 │ • scheduledDataCleanup│
┌──────────────────┐                     └─────────┬─────────────┘
│  Cleanair (Flutter)                              │
│ ┌──────────────────────────────────────────┐    │
│ │ Provider 트리                             │    │ Firestore writes
│ │  ├─ FirestoreSnapshotService(stream)      │    ▼
│ │  ├─ AirQualityController(history+watchdog)│  ┌──────────────────────┐
│ │  ├─ NotificationPreferencesController     │  │ Firestore            │
│ │  ├─ DeviceBindingControllerV2             │◀─┤ sensors/{id}         │
│ │  ├─ AlertNotificationService              │  │ ├─ history/{docId}   │
│ │  └─ PushNotificationServiceV2 (FCM)       │  │ └─ series/{docId}    │
│ └──────────────────────────────────────────┘   │ devices/{token}      │
│ ┌──────────────────────────────────────────┐   │ device_codes/{code}  │
│ │ NodeRedHealthEngine (stateful)            │   │ alerts/{id}          │
│ │  ↑ external weather (KMA)                 │   │ relay_servers/...    │
│ │  → derived/child/senior/purification…     │   │ plugs/...            │
│ └──────────────────────────────────────────┘   └──────────────────────┘
│ ┌──────────────────────────────────────────┐
│ │ ExternalApiService(10분 폴링)             │   ── ipinfo / WAQI / KMA
│ │ LocalSnapshotStore(파일 캐시)              │
│ │ BackgroundServiceManager(foreground svc)   │
│ │ LedControlService / AirGradientLocalClient │   ── LAN 직결
│ │ TasmotaPlugService                         │   ── plug 제어
│ └──────────────────────────────────────────┘
└──────────────────┘
                                              ▲
                                              │ FCM Push
                              ┌───────────────┴────────────┐
                              │ alertEngine.js              │
                              │ • watcher 10종 + 히스테리시스│
                              │ • dedupe 30분, quiet hours  │
                              └─────────────────────────────┘
```

---

## 1. 앱 부팅 파이프라인 (`main.dart`)

`main.dart:21-138`

### 1.1 부팅 단계

1. `WidgetsFlutterBinding.ensureInitialized()`
2. `Firebase.initializeApp()` — Firebase Core 초기화 (필수)
3. `AlertNotificationPresenter.setPayloadHandler(...)` — 알림 페이로드가 `open_file:`로 시작하면 다운로드된 파일 자동 오픈
4. SystemUI(상태바) 투명 처리
5. **핵심 서비스 객체 6종 인스턴스화**
   - `FirestoreSnapshotService()` — Firestore 문서 실시간 스트림
   - `LocalSnapshotStore()` — 로컬 파일 캐시
   - `NotificationPreferencesController(NotificationPreferencesStorage())` + `await load()` — SharedPreferences에서 알림 설정 로드
   - `DeviceBindingControllerV2(DeviceBindingStorageV2())` + `await load()` — 바인딩 상태 로드
   - `AlertNotificationService(...)` + `await initialize()` — Firestore snapshot 구독자 + flutter_local_notifications 채널 생성
   - `PushNotificationServiceV2(onTokenRefreshed: ...)` + `await initialize()` — FCM 권한·토큰
6. **Android 한정**: `BackgroundServiceManager.initialize() → startBackgroundService() → enableWakeLock()` 자동 실행
7. **이미 바인딩된 경우** (`deviceBinding.value.isBound`):
   - `firestoreService.setFirestoreDocPath(deviceBinding.value.firestoreDocPath)`
   - `pushService.updateSensorId(deviceBinding.value.deviceId)`
8. `runApp()`에서 `MultiProvider`로 6개 서비스를 트리에 노출, `AirQualityController`는 `..initialize()`로 즉시 활성화

### 1.2 Provider 트리

```
MultiProvider
 ├─ Provider<FirestoreSnapshotService>.value
 ├─ ChangeNotifierProvider<AirQualityController>(create: ...initialize())
 ├─ ChangeNotifierProvider<NotificationPreferencesController>.value
 ├─ ChangeNotifierProvider<DeviceBindingControllerV2>.value
 ├─ Provider<AlertNotificationService>.value
 └─ Provider<PushNotificationServiceV2>.value
       └─ child: IndoorAirQualityApp (MaterialApp, Pretendard 폰트, home: HomePage)
```

---

## 2. 상태/스트림 파이프라인 (`AirQualityController`)

`state/air_quality_controller.dart:12-301`

### 2.1 상수
| 상수 | 값 | 의미 |
|---|---|---|
| `_historyWindow` | 14일 | 메모리 history 보관 윈도우 |
| `_maxHistoryEntries` | 241,920 | 14일 × 5초 간격 상한 |
| `_watchdogInterval` | 20초 | 연결 watchdog tick |
| `_staleReconnectThreshold` | 30초 | 마지막 snapshot 이후 30초 경과 시 재연결 트리거 |
| `isDataStale` | >15초 | UI에서 "stale" 판정 임계 |

### 2.2 `initialize()` 흐름
1. **로컬 캐시 로드** `_loadPersistedSnapshots()` — `LocalSnapshotStore.loadRecent()` → `_history` 채움
2. **Firestore history 병합** `_loadFirestoreHistory()` — `sensors/{id}/history` 컬렉션에서 `since` 이후 문서 로드, timestamp 기준 중복 제거 후 병합·정렬, 윈도우 적용
3. **스트림 구독**
   - `_service.snapshots.listen(_handleSnapshot, onError: _handleError)`
   - `_service.connectionStates.listen(_handleConnectionState)`
4. `_connectInternal()` 호출 → `_service.connect()` → 상태 `connecting → connected`
5. `_startConnectionWatchdog()` — 20초마다 연결/staleness 검사, 필요 시 `force: true`로 재연결

### 2.3 `_handleSnapshot` 처리
- 동일 `timestamp.millisecondsSinceEpoch`이면 **중복 무시** (line 232-242)
- `_latestSnapshot = snapshot`
- `_history.add(snapshot)`
- `_store.appendSnapshot(snapshot)` (fire-and-forget로 로컬 영구 저장)
- 윈도우 컷오프(14일) + 상한(241,920)으로 truncate
- `notifyListeners()`

### 2.4 연결 상태 머신 (`LiveDataStatus`)
```
disconnected ─→ connecting ─→ connected
       ▲              │           │
       │              ▼           ▼
       └────────── error ◀──── stream onError
```
Watchdog: `disconnected | error | (latestSnapshot==null && !connected) | staleFor>30s` 중 하나면 재연결.

---

## 3. Firestore Snapshot 변환 파이프라인 (`FirestoreSnapshotService`)

`services/firestore_snapshot_service.dart:11-417`

### 3.1 핵심 책임
1. Firestore 문서 실시간 구독: `_firestore.doc(path).snapshots().listen(...)` (`path = sensors/{id}`)
2. raw 문서 → `AirQualitySnapshot` JSON 변환 (`_toSnapshotJson` line 234-314)
3. 변환 과정에서 **`NodeRedHealthEngine.compute()`** 호출하여 모든 파생/건강 지표 산출
4. **`ExternalApiService.start()`/`stop()`** 라이프사이클 동기화
5. 외부 API 데이터를 `_healthEngine.setExternalWeather(...)`로 주입(KMA 기반)
6. `_externalApi.updateComparison(sensorPm25, sensorTemp, sensorHumidity)` 로 측정소 비교 통계 업데이트
7. `loadHistory(since, limit)` — `sensors/{id}/history` 컬렉션을 createdAt 오름차순 + limit으로 페이징
8. `clearDeviceData(deviceId)` — `history/`, `series/` 하위 컬렉션을 batch(500)로 분할 삭제
9. `setFirestoreDocPath` / `setSensorId` — 경로 변경 시 자동 `connect(forceReconnect: true)`
10. `waitForFirstSnapshot(timeout)` — 페어링 직후 데이터 도착 대기(25초 기본)

### 3.2 변환 출력 JSON 구조
```jsonc
{
  "id": "<docId>",
  "timestamp": "<ISO8601>",
  "raw": { "pm25", "iaqiScore", "co2", "tvoc", "nox", "temp", "humidity" },
  "derived":  { … },         // health.derived spread
  "child":    { … },
  "senior":   { … },
  "purification": { … },
  "alerts":   { … },
  "seasonalApparent": { … },
  "apparentTemp": { … },
  "health":   { …, "derived": {…+ stored iaqiScore + aqiLevel/Category fallback} },
  "locationComparison": { … },  // 있을 때만
  "meta": { "serialno": "<doc.serial or id>" }
}
```
- `latest`(map) 우선, 없으면 doc top-level에서 fallback (`_pick`)
- timestamp는 `latest.timestamp → doc.lastSeen → doc.updatedAt → now()` 순으로 결정

---

## 4. 건강 지표 계산 엔진 (`NodeRedHealthEngine`)

`utils/nodered_health_engine.dart:1-1285`

상태를 들고 있는 stateful 엔진이며, Node-RED 원본의 계수/공식을 **그대로 포팅**.

### 4.1 입력
`compute({pm25, co2, tvoc, temp, humidity, timestampMs?})` — 모두 optional.

### 4.2 출력 카테고리

#### 4.2.1 `derived`
- **이슬점(dew point, Magnus 공식)** — `α = (17.27·T)/(237.7+T) + ln(RH/100)`, `dp = 237.7·α / (17.27 − α)`
- **불쾌지수(DI)** — `0.81·T + 0.01·RH·(0.99·T − 14.3) + 46.3`
- **IAQI 종합지수** (`calculate_iaqi`)
  - PM2.5 / CO2 / TVOC / K(환기상수) / 온습도를 각각 정규화하여 비율(ratio)로 환산
  - 등급 산출: `primary_grade ∈ {좋음, 보통, 나쁨}`, `sub_level ∈ {경미한, 중간, 심각, 매우위험}`
  - 부가 점수 `m_score`(max ratio), `e_score`(등급 임계 초과분), `i_score`(보통 구간 가중)
  - CO2 임계 600+400 밴드, PM2.5 15+35 밴드, K 6→2 밴드 등 Node-RED 동일 상수

#### 4.2.2 `child` (어린이 모드)
- `focus`(집중) — CO2 4단계 (`<700/700-1000/1000-1500/≥1500` → 좋음/보통/주의/높음)
- `respiratory`(호흡기) — RH 40-60%, T 20-24°C, TVOC<200 기준 0~−35 점 차감
- `infection`(감염위험) — CO2×RH 조합 → 0~6 매핑 → score map `[10,25,40,55,70,85,95]`
- `mold`(곰팡이) — RH>60% 지속시간(`_moldHighSinceMs` 영속)으로 4단계: >24h, >70%, >60%+PM>35 동시 발생 등

#### 4.2.3 `senior` (고령자 모드)
- `cardio`(심혈관) — 10분 PM2.5 history 중 >5 µg 비율, k 평균으로 `riskRaw = highHours · (1/kAvg)`, `score = 100·(1 − riskRaw/8)` clamp 0-100
- `sleep`(수면) — 10분 history에서 CO2<1000 비율(0.7 가중)·TVOC<200 비율(0.3 가중) → 0-100
- `pmExposure` — 4밴드 메시지(`<15/15-35/35-55/≥55`)
- `ventilation` — `t50 = 60/k` (분 단위 반감기 추정)

#### 4.2.4 `purification` (정화 모드)
- `cadr` — log-linear 회귀의 `kPm25, kCo2`로 등급 S/A/B/C, `t50 = ln(2)/k · 60`, scenario 분류(equilibrium_clean / purification / ventilation / combined / polluting / stagnant)
- `ipi` — 바이러스 잔류 위험 `t90 = ln(10)/kCo2 · 60`, 4단계(`kCo2≥3.0/≥1.0/≥0.3/else`)
- `ventilation` — CO2>1000 → "환기필요", else "정화중"

#### 4.2.5 `seasonalApparent` / `apparentTemp`
- 5~9월: Stull 습구 공식
- 그 외 + T≤10°C & V≥1.3 m/s: 풍속 냉각(wind chill)
- 색·메시지 매핑까지 포함

#### 4.2.6 `alerts`
- PM2.5(15/35/55), CO2(1000/1500), 곰팡이 단계로 메시지 트리거

### 4.3 엔진 영구 상태
- `_moldHighSinceMs` — 곰팡이 누적 시간
- `_cardioHist` (10분), `_sleepHist` (10분) — 슬라이딩 윈도우
- `_pm25Buffer / _co2Buffer` — 5분 회귀용(최대 400샘플)
- `_pm25TrendBuffer / _co2TrendBuffer / _tvocTrendBuffer` — 120 샘플 추세선
- `_kPm25, _kCo2`, `_r2Pm25, _r2Co2` — log-linear OLS 결과(시간축 = 시작부터의 시간(h), 값축 = `ln(PM2.5)` 또는 `ln(CO2-420)`). 최소 15샘플, 노이즈 임계 0.99 미만이면 skip
- `_externalTemp/_externalHumidity/_externalWindSpeed` — `setExternalWeather()`로 KMA 외기 주입(seasonalApparent 계산용)

---

## 5. 외부 API 파이프라인 (`ExternalApiService`)

`services/external_api_service.dart:1-506`

### 5.1 라이프사이클
- `start()` — 즉시 1회 fetch 후 **10분 주기 Timer.periodic** (line 245-251)
- `stop()` — 타이머 취소
- `dispose()` — 리소스 해제

### 5.2 외부 호출 3종

| API | 엔드포인트 | 인증 | 입력 | 추출 필드 |
|---|---|---|---|---|
| **ipinfo.io** | `https://ipinfo.io/json` | 없음 | (없음, 발신 IP) | `loc`(lat,lon), `city`, `region` |
| **WAQI(AQICN)** | `https://api.waqi.info/feed/geo:{lat};{lon}/?token=...` | **하드코딩 토큰** (`521285…2016c02c`) | ipinfo 좌표 | `data.aqi` (PM2.5 AQI), 측정소명 |
| **KMA 초단기실황** | `http://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getUltraSrtNcst` | **하드코딩 서비스키** | base_date/base_time(KST, 매시 45분 전이면 한 시간 전) + `nx,ny`(Lambert 변환) | `T1H`(온도), `REH`(습도), `WSD`(풍속) |

⚠️ 키 2개가 클라이언트 코드에 그대로 박혀있어 보안 부채.

### 5.3 ExternalApiData 필드
`pm25, temperature, humidity, windSpeed, stationName, city, region, retrievedAt`

### 5.4 비교 통계 산출 (`updateComparison`)
- 1시간(3,600,000 ms) 슬라이딩 버퍼에 (sensor, station) 페어 누적
- 메트릭별로 RMSE / MAPE / CV / R² 계산 (Node-RED 원공식)
- 결과 → `LocationComparisonSnapshot` (pm25/temperature/humidity 각각 sensor·station·delta·stats(rmse,mape,cv,r²,n))

---

## 6. 데이터 모델 (`AirQualitySnapshot`)

`models/air_quality_snapshot.dart:1-1005`

### 6.1 Top-level
`id, timestamp, pm25, co2, tvoc, nox, temperature, humidity, dewPoint, discomfortIndex, iaqiScore, aqiLevel, aqiCategory, respiratoryIndex, immunityRisk, cognitiveFocus, cardioScore, cardioRisk, sleepComfort, apparentTemp, child, senior, purification, purifier, ipi, locationComparison, alerts, location, meta, seasonalApparent`

### 6.2 주요 중첩 타입
| 타입 | 핵심 필드 |
|---|---|
| `ChildHealthSnapshot` | focus / respiratory / infection / mold |
| `ChildFocusSnapshot` | co2, level, message, recommendedAction |
| `ChildRespiratorySnapshot` | score, level, temp/rh/tvoc, 메시지 3종 |
| `InfectionRiskSnapshot` | score, level, combo, co2, rh |
| `MoldRiskSnapshot` | riskLevel, riskMessage, durationHours, humidity, pm25 |
| `SeniorHealthSnapshot` | cardio / sleep / pmExposure / ventilation |
| `SeniorCardioSnapshot` | score, level, highHours, kAvg, riskRaw, samples |
| `SeniorSleepSnapshot` | score, level, scoreRange, interpretation, goodCo2, goodVoc, samples |
| `SeniorPmExposureSnapshot` | pm25, band, message |
| `SeniorVentilationSnapshot` | k, t50Minutes, message |
| `PurificationSummary` | cadr / ipi / ventilation |
| `PurificationCadrSnapshot` | k, kEffective, t50Minutes, index, grade(S/A/B/C), trend, mode, scenario, kPm25/kCo2, gradePm25/gradeCo2, dualKDisplay, t50Pm25/t50Co2, dualT50Display, r2Pm25/r2Co2, accuracyWarning |
| `IpiSnapshot` | k, t90Minutes, level, score, kPm25/kCo2, dualK·dualT90Display, r2Co2, accuracyWarning |
| `PurificationVentilationSnapshot` | status, message, alerts |
| `SeasonalApparentSnapshot` | seasonMode, summer/winter sub-snapshots |
| `LocationComparisonSnapshot` | pm25 / temperature / humidity → 각각 LocationMetricComparison (+stats) |
| `SnapshotAlerts` | messages, airQualityAlert, moldRiskLevel, moldRiskMessage |
| `SnapshotLocation` | sensorLat/Lon, deviceLat/Lon, accuracy, source, recordedAt |
| `SnapshotMeta` | firmware, serialNo, wifiRssi, sensorSource |

---

## 7. 페어링/바인딩 파이프라인

### 7.1 PIN 클레임 (권장 경로)

`services/device_binding_service_v2.dart:101-157`, `widgets/settings_view.dart:2145-2351`

```
[ESP32 부팅]
   └─→ /generateDeviceCode (sensorId="airgradient:<MAC>") ── X-API-Key
        └─→ {code:"123456", expiresAt}
              └─→ OLED 약 120초 표시 (firmware/airgradient_api_esp32-c3.yaml line 91)

[사용자가 앱에서 6자리 PIN 입력]
   └─→ PushNotificationServiceV2.ensureClientToken() → 영구 client token
   └─→ DeviceBindingControllerV2.claimDevice(code, token)
         └─→ POST /claimDevice  body: {token, code}
               └─→ {ok:true, sensorId, firestoreDocPath:"sensors/<id>"}
                     ├─ DeviceBindingStorageV2.save(SharedPreferences)
                     ├─ FirestoreSnapshotService.setFirestoreDocPath(...)
                     └─ PushNotificationServiceV2.updateSensorId(...)
```

서버 에러 메시지: `invalid_code`, `code_expired`, `code_already_claimed` → 사용자 안내로 매핑.

### 7.2 mDNS 직접 바인딩 (보조)

`settings_view.dart:2198-2275`

1. `MDnsClient.lookup(_airgradient._tcp.local)` 5초 스캔
2. TXT(`serialno`) + SRV/A 레코드에서 IP 추출
3. serial을 정규화(접두사·콜론·대시 제거) → 후보 ID
4. `DeviceBindingControllerV2.applyBinding(deviceId, "sensors/<id>")`로 PIN 없이 즉시 바인딩

⚠️ 소유권 증명이 PIN보다 약함 — 기존 `CURRENT_SYSTEM_OVERVIEW.md` 메모와 동일.

### 7.3 백엔드 ID 정규화 후보 매칭

`functions/index.js:56-91`

- `compactSensorId()` — `airgradient:` 제거, non-hex 제거, 소문자
- `toColonMac()` — 12-hex → `AA:BB:CC:DD:EE:FF`
- `buildSensorIdCandidates()` — raw / no-prefix / compact / lower colon / upper colon / compact+prefix / colon+prefix 등 **8가지 변종** 생성
- `listDevicesForSensor()` — `devices` 컬렉션을 `IN`/`==` 쿼리로 매칭

→ ESPHome(`airgradient:<MAC>`)과 Arduino relay(소문자 compact MAC) 두 펌웨어 트랙의 표기 차이를 흡수.

---

## 8. 백엔드 (Firebase Cloud Functions)

`iaq-v2-firebase/functions/` — Node.js 20

### 8.1 HTTP 엔드포인트 일람 (region us-central1, CORS=true)

| 엔드포인트 | 인증 | 주요 입력 | Firestore 쓰기 |
|---|---|---|---|
| **POST /ingest** | **필수** `INGEST_API_KEY` | serial, pm25, co2, tvoc, nox, temp, humidity, k, firmware, ip, timestamp | `sensors/{id}` latest, `sensors/{id}/history/{}` |
| **POST /relay** (sub-route 분기) | 없음 | path별로 다름 | path별로 다름 (아래 참조) |
| POST /registerDevice | 선택 `DEVICE_API_KEY` | token, fcmToken, sensorId, timezone, alertsEnabled, quietHours, mutedTypes | `devices/{token}` |
| POST /claimDevice | 선택 | token, code | `devices/{token}`, `device_codes/{code}` |
| POST /updatePreferences | 선택 | token + 변경 필드 | `devices/{token}` 부분 갱신 |
| POST /generateDeviceCode | 선택 | sensorId | `device_codes/{code}` (TTL `DEVICE_CODE_TTL_MINUTES`, 기본 10분) |
| POST /registerPlug | 선택 | plugId, displayName, stationId, sensorId, tasmotaTopic, profileId, mode, transport | `plugs/{plugId}` |
| POST /upsertPlugProfile | 선택 | profileId?, name, weights, thresholds, hysteresis, constraints | `plug_profiles/{profileId}` |
| POST /commandPlug | 선택 | plugId, command(ON/OFF/TOGGLE), mode, manualOverrideSeconds, sensorSnapshot, transportHint | `plug_command_requests/{}`, `plug_command_queue/{}`, `plugs/{plugId}` |
| POST /ackPlugCommand | 선택 | requestId, status, actualState, online, latencyMs, workerId | request/queue/responses, `plugs/{plugId}` |
| POST /updatePlugState | 선택 | plugId, actualState, online, source, telemetry | `plugs/{plugId}`, `plug_state_history/{}` |
| POST /getPlug | 선택 | plugId | (read) |
| POST /listPlugs | 선택 | stationId / sensorId / limit | (read) |
| POST /getPlugControlTrace | 선택 | plugId, limit | (read, 결정·요청·응답 머지 정렬) |

### 8.2 `/relay` 서브 라우트 (`index.js:2540~2900`)

| 경로 | 역할 |
|---|---|
| `/api/relay/register-server` | `relay_servers/{serverId}` 등록 (URL+timestamp) |
| `/api/relay/register-server-path/{serverId}/{base64url}` | path 인코딩된 서버 등록 |
| `/api/relay/bind-token` | `relay_tokens/{token} → {serverId, serverUrl}` 바인딩 |
| `/api/relay/resolve-server` | token으로 server lookup, 없으면 최신 server에 매핑 후 반환 |
| `/api/relay/sensor` | MAC 정규화(`normalizeRelayMacAddress`: 콜론 제거 + 소문자) → `sensors/{mac}` latest + `series/{}` + `history/{}` 기록. `requestCode=true` 시 미클레임 코드 재사용/신규 발급 후 `{code, alreadyClaimed, expiresAt}` 응답 |

### 8.3 `/ingest` 부가 동작

1. 본문 검증·정규화
2. `sensors/{sensorId}` upsert (`latest`, `lastSeen`, IAQI 점수, k 회귀치, firmware 등)
3. `sensors/{sensorId}/history/{}` append (TTL `expireAt = now + SENSOR_HISTORY_RETENTION_DAYS`(30일))
4. `dispatchAlertsForSnapshot(...)` — alertEngine 실행 → FCM 발송
5. `dispatchAutoControlForSnapshot(...)` — 스마트 플러그 자동 제어 결정(profile/threshold/hysteresis/manualOverride 검사)
6. 응답: `{ok, sensorId, iaqi, iaqiScore, k, kEffective, kSource, timestamp}`

### 8.4 알림 엔진 (`alertEngine.js`)

**Watcher 10종**:

| type | critical | warning | notice | clearBelow/Above | minDuration | 비고 |
|---|---|---|---|---|---|---|
| pm25_high | ≥55 | ≥35 | ≥15 | <12 | 90s | quiet hours 시 정화기 강풍 모드 권장 |
| co2_high | ≥1500 | ≥1000 | ≥800 | <700 | 120s | 환기 권장 |
| tvoc_high | ≥400 | ≥300 | ≥200 | <150 | 120s | quiet hours 시 정화기 흡착 모드 |
| nox_high | — | ≥2 | ≥1 | <0.5 | 90s | 환기 권장 |
| respiratory_low | ≤40 | ≤60 | — | >65 | 5min | 역방향(`lte`) |
| infection_risk | ≥80 | ≥60 | — | <55 | 5min | |
| focus_poor | ≥1500 | ≥1000 | — | <900 | 3min | CO2 기반 |
| cardio_low | ≤40 | ≤60 | — | >65 | 10min | |
| sleep_quality_low | ≤40 | ≤60 | — | >65 | 10min | |
| mold_risk | ≥4단계 | ≥3 | ≥2 | <1 | 10min | |

**런타임 규칙**:
- `SUPPRESS_MS = 30 * 60 * 1000` — 동일 type+severity는 30분간 재발화 금지(이전 severity ≥ 현재 severity일 때만 차단)
- `DEFAULT_QUIET_HOURS = {start:"22:00", end:"07:00"}` — 자정 wraparound 처리
- quiet hours 중 critical이 아니고 환기 권장이면 `altAction`으로 대체
- `durationBuffer` 누적이 `minDuration`을 채워야 발화

**FCM dispatch (`index.js:125-159`)**:
1. `shouldDeliver(device, alert, now)` 검사: `alertsEnabled`, `mutedTypes`, snooze 윈도우, quiet hours
2. critical은 quiet hours 무시하고 발송
3. 무효 토큰이면 `fcmToken=null`, `pushDisabled=true`로 디바이스 마킹

### 8.5 스케줄 작업 — `scheduledDataCleanup`

- region: `asia-northeast3`
- cron: `0 0 * * *` Asia/Seoul (매일 자정)
- 보존: `SENSOR_HISTORY_RETENTION_DAYS=30` (sensors history/series), `PLUG_LOG_RETENTION_DAYS=90`
- 한 회당 최대 `CLEANUP_MAX_DELETES_PER_RUN=200,000` batch 삭제
- collectionGroup 우선, 실패 시 sensor별 fallback

### 8.6 MQTT 워커 — `plug_mqtt_worker.js`

- **별도 프로세스** (Cloud Function 아님). MQTT ↔ Firestore 브리지
- `plug_command_queue` 폴링(기본 1.5초) → Tasmota `cmnd/{topic}/Power` publish
- 응답 구독: `stat/+/RESULT`, `stat/+/POWER`, `tele/+/LWT` (online/offline)
- 응답 수신/타임아웃(15초) 시 `plug_command_responses` 기록 + `plugs/{}` 갱신 + `plug_command_requests` status 마감

### 8.7 Firestore 룰 요약 (`firestore.rules`)

| 컬렉션 | client read | client write |
|---|---|---|
| `sensors/{id}`, `sensors/{id}/history`, `sensors/{id}/series` | 허용 | **거부** |
| `devices/{token}` | 허용 | 거부 |
| `device_codes/{code}` | 허용 | 거부 |
| `alerts/{id}` | 허용 | 거부 |
| 그 외 | 거부 | 거부 |

→ 모든 쓰기는 Cloud Functions(Admin SDK) 경유. 인증은 룰이 아닌 코드의 X-API-Key 검증으로 위임.

### 8.8 핵심 환경변수
`INGEST_API_KEY`(필수), `DEVICE_API_KEY`, `DEVICE_CODE_TTL_MINUTES`(10), `MANUAL_OVERRIDE_DEFAULT_SECONDS`(900), `DEFAULT_AUTO_AQI_ON/OFF`, `INGEST_MIN_INTERVAL_SECONDS`, `SENSOR_HISTORY_RETENTION_DAYS`(30), `PLUG_LOG_RETENTION_DAYS`(90), `IAQI_K_REGRESSION_*`, `ENABLE_EXPIREAT_TTL_WRITES`, `MQTT_URL/USERNAME/PASSWORD`, `WORKER_*`.

---

## 9. 알림 파이프라인 (앱 측)

### 9.1 푸시 등록 (`PushNotificationServiceV2`)
`services/push_notification_service_v2.dart:80-200`

1. `ensureClientToken()` — SharedPreferences `device_binding_v2_client_token` 로드/생성
2. (mobile) `_messaging.requestPermission()` — alert/badge/sound
3. foreground notification presentation 활성화
4. `_messaging.onTokenRefresh.listen(_handleToken)` 구독
5. `_messaging.getToken()` → 즉시 `_handleToken()` 또는 `_syncRegistration()`

**`/registerDevice`** 페이로드: `{token, fcmToken, sensorId, platform}` + `X-API-Key: DEVICE_API_KEY`(기본 `capstone-iaq-2026-secure-key`).
**`/updatePreferences`** 페이로드: quiet hours(HH:MM 직렬화), snoozedUntil, mutedTypes(map).

### 9.2 인앱 로컬 알림 (`AlertNotificationService` + `Engine`)
`services/alert_notification_service.dart:25-52`, `alert_notification_engine.dart:18-66`

- `FirestoreSnapshotService.snapshots` 스트림 구독
- snapshot의 `SnapshotAlerts` 객체에서 `airQualityAlert / moldRiskMessage / messages[]` 추출 → 중복 제거
- `_classifyAlertType()`로 메시지 텍스트를 type(pm25/co2/tvoc/nox/mold/respiratory/infection/focus/cardio/sleep/temp)으로 분류
- `NotificationPreferences.shouldSuppress(now)` 검사 — alertsEnabled=false / 스누즈 / 조용시간이면 차단
- **dedupe 윈도우 15분** — 동일 type 메시지가 윈도우 내면 무시
- `AlertNotificationPresenter.showAlert(title:'공기질 경보', body:msg, payload:snapshot.id)` 호출

### 9.3 Presenter (`AlertNotificationPresenter`)
- 채널 2종: `iaq_alerts`(High importance), `iaq_downloads`(default)
- Android: `BigTextStyleInformation`, 아이콘 `@drawable/ic_stat_notification`
- iOS/macOS: `DarwinNotificationDetails` + 권한 요청
- 알림 ID: `DateTime.now().microsecondsSinceEpoch`의 하위 31비트
- payload `open_file:<path>` → main.dart가 `OpenFilex.open(path)`로 처리

### 9.4 Preferences (`NotificationPreferencesController`)
`services/notification_preferences.dart:8-298`

- 영구화 키: `alerts_enabled`, `quiet_hours_enabled`, `quiet_hours_start`, `quiet_hours_end`, `alerts_snoozed_until`, `alerts_muted_types`(StringList)
- 기본 quiet 22:00–07:00
- 12 mutedTypes 키: `pm25_high, co2_high, tvoc_high, nox_high, respiratory_low, infection_risk, focus_poor, mold_risk, cardio_low, sleep_quality_low, apparent_temp_morning, apparent_temp_evening`
- 변경 시 `_update()` → SharedPreferences 저장 + `notifyListeners()` + `PushNotificationServiceV2.syncNotificationPreferences()` 호출

---

## 10. 백그라운드 실행 (`BackgroundServiceManager`)

`services/background_service.dart:29-361`

### 10.1 설정
- Android `AndroidConfiguration`:
  - `onStart: _onStart`(pragma entry-point)
  - **`isForegroundMode: true`** (포그라운드 알림 상시)
  - 채널 `air_quality_channel`, type `dataSync`
  - 초기 알림: "실내 공기질 모니터링 · 백그라운드에서 공기질 데이터를 수신 중..."
- iOS: `IosConfiguration` (onForeground/onBackground)

### 10.2 백그라운드 isolate (`_BackgroundFirestoreRunner`)
- `SharedPreferencesHelper.getFirestoreDocPath()` 로드 → 별도 Firestore listener 작동
- snapshot마다 `LocalSnapshotStore` append + 자체 알림 검사
- `NotificationPreferences` 5분 TTL 캐시
- 알림 type별 **15분 쿨다운**, 단 severity가 critical로 상향되면 (이전 < 2) **쿨다운 우회**
- 자체 임계: PM2.5 critical 55 / warn 35, CO2 critical 1500 / warn 1000, TVOC critical 400 / warn 300

### 10.3 보조
- 5초 주기로 foreground notification에 timestamp 갱신 (`update` 이벤트 emit)
- `WakelockPlus.enable/disable` (line 104-120)
- 배터리 최적화 예외 요청 (`requestBatteryOptimizationExemption`)

---

## 11. 로컬 스냅샷 저장 (`LocalSnapshotStore`)

`services/local_snapshot_store.dart:8-180`

- 위치: `getApplicationDocumentsDirectory()`
- 두 파일:
  - **`snapshots_recent.json`** — JSON 배열, 최대 **2,000 샘플**(약 2.7시간 @5s) → 빠른 부팅 복원
  - **`snapshots.log`** — JSONL append-only 아카이브
- `appendSnapshot` — append + recent JSON 재작성 (truncate 2000)
- `loadRecent(limit=2000)` — recent JSON 파싱, 깨지면 빈 리스트
- `PersistedAirQualitySample` ↔ `AirQualitySnapshot` 변환

---

## 12. UI 파이프라인

### 12.1 `HomePage`
`screens/home_page.dart:29-429`

- 시간 기반 그라데이션 배경(`TimeGradient.getTimeBasedGradient()`) + `SkyBackground` 위젯, 1분 주기 갱신
- `AirQualityController` watch
- **하단 탭**:
  1. 개요 — `AirQualityOverview` (메트릭 클릭 시 탭 2번으로 점프, `_selectedMetricId` 설정)
  2. 모니터링 상세 — `MetricDetailView(metricId)` — pm25/co2/tvoc/nox 등
  3. 건강 모드 — `HealthModeDashboard`
  4. 측정소 비교 — `StationComparison`
- AppLifecycle resume 시 `controller.isConnected/isDataStale` 검사 후 `retryConnection()`

### 12.2 `AirQualityOverview` (개요)
`widgets/air_quality_overview.dart` — 미니 스파크라인에 다음 보호 적용:
- 비유한값 포인트 필터링
- 유효 포인트 <2이면 렌더 중단
- timestamp 정렬 + 차트 영역 clip

### 12.3 `SettingsView` 주요 조작
`widgets/settings_view.dart` (2,593줄 — 단일 거대 위젯)

| 기능 | 호출 경로 |
|---|---|
| **PIN 클레임** | `_submitPin()` → `pushService.ensureClientToken()` → `binding.claimDevice(code, token)` → 성공 시 `widget.onClaim(sensorId, docPath)` |
| **mDNS 스캔** | `_startMdnsScan()` → `MDnsClient.lookup(_airgradient._tcp.local)` 5초 → `_applyDirectBinding(sensorId, ip)` → `binding.applyBinding(...)` |
| **LED 제어** | `_toggleLed(turnOn, sensorId)` → `_fetchDeviceIp()` → `LedControlService.turnOn/turnOff(ip)` → `PUT http://<ip>/config {ledBarMode:'co2'\|'off'[, ledBarBrightness:0-100]}` |
| **CO2 수동 교정** | `_requestCo2Calibration()` → `LedControlService.requestCo2Calibration(ip)` → 두 가지 키(`co2CalibrationRequested`/`co2CalibrationRequest`) 순차 시도 |
| **데이터 초기화** | `_clearDeviceData(sensorId)` → `FirestoreSnapshotService.clearDeviceData(...)` (history/series batch 500 분할 삭제) |
| **알림 토글** | `notifPrefs.setAlertsEnabled / setQuietHoursEnabled / updateQuietHours / snoozeFor / setMutedType` → 자동 백엔드 동기화 |
| **백그라운드 토글** | `BackgroundServiceManager.enableWakeLock / disableWakeLock`, `requestBatteryOptimizationExemption` |
| **연결 해제** | `binding.clear()` |

### 12.4 로컬 LAN 직결 클라이언트
`services/airgradient_local_api.dart`

- `discoverHost()` — `airgradient.local` DNS 조회(2s 타임아웃)
- `fetchSnapshot(host)` — `GET http://<host>/measures/current` 또는 `/measurement/current` (4s 타임아웃)
- 응답 키 매핑: `pm02→pm25, rco2→co2, tvocIndex→tvoc, noxIndex→nox, atmp→temp, rhum→humidity, wifi→wifiRssi, firmware, serialno`

### 12.5 스마트 플러그 (`TasmotaPlugService`)
`services/tasmota_plug_service.dart`

- **로컬 우선** (`preferLocalControl`): `GET http://<plugIp>/cm?cmnd=Power%20{ON|OFF|TOGGLE}` (Tasmota HTTP)
- 실패 시 백엔드 cloud 경로 fallback: `/commandPlug, /getPlug, /listPlugs, /registerPlug, /upsertPlugProfile, /getPlugControlTrace`
- 명령 페이로드: `{plugId, command, mode, actor, requestedByToken, manualOverrideSeconds, reason, sensorSnapshot, transportHint}`

---

## 13. 펌웨어 (ESPHome) 파이프라인

### 13.1 핵심 설정 (`firmware/ag-one-capstone.yaml`, `airgradient_api_esp32-c3.yaml`)
- 보드: AirGradient ONE (ESP32-C3)
- 센서: PMS5003(PM2.5) + S8(CO2) + SHT40(T/RH) + SGP41(TVOC/NOx)
- `capstone_upload_interval: 5s`
- `capstone_api_key: capstone-iaq-2026-secure-key` (예시 파일에는 `CHANGE_ME`)

### 13.2 동작
1. WiFi 연결되면 5초 주기로 `/ingest` POST (X-API-Key 헤더)
   - 본문 키: `serial="airgradient:<MAC>", pm25, co2, tvoc, nox, temp, humidity, firmware="capstone-1.1", ip`
2. **부팅 후 1회만** WiFi 연결 직후 `/generateDeviceCode` 호출 (3초 폴링 + `pin_requested` flag)
   - 응답에서 `"code":"NNNNNN"` 파싱
   - `pin_display_until = millis() + 120000` → OLED에 약 120초 표시
3. ESPHome HA API, OTA, captive portal, watchdog 120s 활성

### 13.3 펌웨어 트랙 2종 병행
- ESPHome: `/ingest` + 부팅 시 `/generateDeviceCode` 1회
- Arduino: `/api/relay/sensor` + `requestCode=true` (relay 본문에 코드 포함 응답)
- 백엔드 ID 정규화 + relay sensor 분기로 양쪽 모두 수용

---

## 14. End-to-End 시퀀스 (권장 PIN 클레임 시나리오)

```
┌──ESP32──┐                    ┌──Functions──┐                ┌──App──┐
   |  부팅·WiFi 연결                |                            |
   |─── /generateDeviceCode ──▶|  device_codes/{NNNNNN} write |
   |  TTL 10분, MAC 정규화 후 매칭  |                            |
   |◀─── {code, expiresAt} ────|                            |
   | OLED PIN 120s 표시           |                            |
   |                              |  ◀─사용자 PIN 입력──── |
   |                              |◀── /claimDevice {token,code}|
   |                              |  device_codes 검증·소비     |
   |                              |  devices/{token}.sensorId 저장|
   |                              |─── {ok,sensorId,docPath}─▶|
   |                              |                              | binding.save → SharedPrefs
   |                              |                              | FirestoreSnapshotService.connect()
   |─── /ingest 5s주기 ──────▶|  sensors/{id} latest+history|
   |                              |  alertEngine 평가           |
   |                              |  → FCM token으로 push       |
   |                              |─── snapshot 변경 stream ─▶| _handleSnapshot
   |                              |                              | NodeRedHealthEngine.compute
   |                              |                              | LocalSnapshotStore.append
   |                              |                              | UI rebuild
```

---

## 15. 정합성·기술부채 메모

1. **병행 코드베이스**: 활성 = `iaq-v2-firebase/functions`. 레거시 = `Indoorairqualityappv2-main/functions`. 드리프트 위험.
2. **펌웨어 2 트랙**: ESPHome(`ingest+generateDeviceCode`)과 Arduino(`relay sensor + requestCode`). 배포 전 펌웨어와 백엔드 동작을 반드시 일치.
3. **시크릿 노출**: 클라이언트 코드에 `DEVICE_API_KEY`(`capstone-iaq-2026-secure-key`), WAQI 토큰, KMA 서비스키가 하드코딩. 펌웨어 키도 평문. 런타임 시크릿으로 이관 필요.
4. **mDNS 직접 바인딩**은 PIN보다 약한 소유권 증명.
5. **Firestore 룰**은 클라이언트 read는 광범위 허용, write는 전부 거부 — Admin SDK 의존. 사용자/소유권 기반 강화 여지.
6. **버전 표기 불일치**: `pubspec.yaml` 2.0.0+1 vs `settings_view`의 표시 버전 1.0.0.
7. **`scheduledDataCleanup`** 보존 기간 30일/90일 — TTL 인덱스(`expireAt`)와 이중 운영. `TTL_*_ENABLED` flag로 정합 관리.
8. **NodeRedHealthEngine**의 14일 메모리 windowing(241,920 entries)은 메모리 점유가 큼 — 디바이스에 따라 OOM 주의.
9. `clearDeviceData`는 history/series 전부 삭제(사용자 의도 확인 UI 필수).
10. WAQI 비교는 ipinfo IP 위치 기반이라 실제 센서 위치와 어긋날 수 있음.

---

## 16. UI 위젯 상세 분해

§12에서 큰 그림을 제시했고, 여기서는 위젯별 렌더 트리·바인딩·시각 결정을 정리한다.

### 16.1 `air_quality_overview.dart` (개요 탭, 1,293 lines)
- **트리**:
  - 200×200 AQI 원형 인디케이터 (`AirQualityCircle`) — 외곽 글로우 + CustomPaint 진행 호 + 중앙 점수(48pt) + 등급 배지
  - AI 권장 메시지 카드
  - 6장의 메트릭 카드 그리드 (PM2.5 / CO₂ / TVOC / NOx / 온도 / 습도) — 각 카드 미니 스파크라인 + 상태 배지
  - alerts 배너(있을 때만)
- **데이터 바인딩**: `AirQualityController.currentData`(timestamp + 6 raw + iaqiScore + k), `controller.historyData`(2시간 윈도우, 최소 24샘플)
- **계산**: `calculateComprehensiveAQI(pm25, co2, k, voc, temp, humidity)` 호출 (`air_quality_overview.dart:35-42`)
- **컬러 밴드**: 0=#00E400, 1=#FFD700, 2=#FF7E00, 3=#FF0000, 4=#8F3F97, 5=#7E0023
- **콜백**: 메트릭 카드 탭 → `onMetricClick(String id)` → HomePage가 `_selectedMetricId` 설정 후 모니터링 상세 탭으로 전환
- **방어 로직**: 비유한값(NaN/Inf) 필터, 유효 포인트 <2이면 차트 미렌더, timestamp 정렬, clip 적용

### 16.2 `air_quality_circle.dart` (210 lines)
- 200×200 Stack — 외곽 글로우 그림자 + CustomPaint 진행 호(0–360°) + 중앙 칼럼(점수 48pt bold + 등급 텍스트)
- 점수는 [0,5] clamp 후 비율로 호 채움 (`air_quality_circle.dart:47`)
- 컬러: switch(level) — 0~5 → 위 6색
- 점수 포맷: 후행 0 제거 (`air_quality_circle.dart:101-111`)

### 16.3 `metric_detail_view.dart` (모니터링 상세, 2,294 lines)
- **메트릭 탭 사이클**: PM2.5, CO₂, TVOC, NOx, 온도, 습도 — 상태 `_currentMetricId`, 이전/다음 버튼으로 사이클
- **차트**: fl_chart `LineChart` 단일 인스턴스, 시계열 라인 + 데이터 포인트 선택 지원(`_selectionStartIndex / _selectionEndIndex`)
- **시간 범위**: `_timeRange`(1h / 6h / 24h / 1w 가정) — `_historyForCurrentRange()`로 `controller.historyData` 슬라이싱
- **부가 카드**:
  - CSV 다운로드 카드(`_buildCsvDownloadCard`) — Documents 디렉토리에 저장 후 `AlertNotificationPresenter`가 다운로드 알림 + `open_file:` payload
  - 주간 히트맵
  - 위치 비교 카드 — `controller.locationComparison`의 sensor vs. station 델타·통계
- **인터랙션**: 차트 포인트 탭 선택, 범위 탭, 메트릭 사이클, export

### 16.4 `health_mode_dashboard.dart` (건강 모드 대시보드, 3,022 lines)
- **모드 라디오**(3종): **Children**(어린이) / **Elderly**(고령자) / **Purification**(정화)
- **데이터 바인딩**:
  - children: `controller.childSnapshot` → focus / respiratory / infection / mold (각 0–100 점수 + 등급/메시지)
  - elderly: `controller.seniorSnapshot` → cardio / sleep / pmExposure / ventilation
  - purification: `controller.purificationSnapshot.cadr` (k, kEffective, t50, grade S/A/B/C, scenario, kPm25/kCo2 dual), `controller.ipiSnapshot` (k, t90, level, score)
- **섹션 구조 per 모드**: 헤더 + 인디케이터 카드(타이틀, 현재값 0–100, 컬러 게이지, 가이드 텍스트) + 통계 카드
- **컬러 코드**: children=라이트블루, elderly=퍼플, purification=그린

### 16.5 `health_mode_view.dart` (3,438 lines)
- 같은 도메인을 다루지만 enum `HealthMode { children, elderly, ventilation }` 기반(대시보드는 string state)
- 모드별로 `LineChart` 3종 — k-history(`_KHistoryPoint(time, kPm25, kCo2)`, 최대 240포인트 = 30s × 2h), CO₂, PM2.5 추세
- `_updateKHistory()`로 매 snapshot마다 dual k 누적
- 데이터: `controller.latestSnapshot`, `controller.purificationCadrSnapshot` (k, kEffective, kPm25, kCo2, t50Minutes), child/senior, ipiSnapshot

### 16.6 `station_comparison.dart` (측정소 비교, 711 lines)
- **헤더**: 위치 아이콘 + 측정소명 + 거리 + 갱신 HH:MM
- **메트릭 카드 3장** (PM2.5 / 온도 / 습도):
  - sensor 값 | station 값 | delta(±, 색상 코드: + 빨강 / − 초록)
  - 통계: mean / min / max / RMSE / MAPE / CV / R² / n
  - 단위 + API source 배지
- **컬러**: PM2.5=blue, 온도=red, 습도=cyan
- **데이터**: `controller.currentData` + `controller.locationComparison`
- StatelessWidget — 인터랙션 없음

### 16.7 `sky_background.dart` + `time_gradient.dart`
- **그라데이션 시간대**(13개 밴드): midnight→4am 검정, 4–5am 인디고/퍼플 dawn, 5–6am 퍼플-블루, 6–7am 일출 오렌지-레드, 7–9am 소프트 오렌지, 9–11am 스카이 블루, 11–14 brightest, 14–17 warm blue, 17–18 sunset 직전, 18–19 dusk, 19–20 night-start, 20–22 night, 22–24 deep night
- **태양**(6–19시): top 위치 sin 보간(6h→80px, 12h→20px, 18h→90px), left는 가로 호
- **달**(20시–6시): 동일 보간 + 밝기 동적
- **별 25개**: 위치 (x,y∈[0,1]), 크기 1–3, sin 위상으로 개별 트윙클
- **구름 3장**: 0.5–1.0 스케일, 0.3–0.5/60s 속도로 좌→우 드리프트
- 입력: `DateTime.now()` 시각 + 화면 크기

### 16.8 `pollutant_info_page.dart` / `health_mode_info_page.dart`
- 정적 정보 페이지 — ListView + glass-morphic 카드 (다크 테마)
- 콘텐츠: 오염물질 — 제목/부제/설명/농도 밴드 막대/권고. 건강 모드 — 모드별 작동방식·평가기준·권장환경 + 수치 임계
- 컨트롤러 의존 없음, 인터랙션 없음

---

## 17. Utils / Config 보강

### 17.1 `utils/metric_status.dart` (74 lines)
모든 메트릭 임계의 단일 진실 소스:

| 메트릭 | 임계 / 라벨 |
|---|---|
| PM2.5 (µg/m³) | ≤15 좋음 / ≤35 보통 / ≤75 나쁨 / >75 매우나쁨 |
| CO₂ (ppm) | ≤600 좋음 / ≤1000 보통 / ≤2000 높음 / >2000 매우높음 |
| TVOC (SGP41 index, center=100) | ≤100 / ≤200 / ≤300 / ≤400 / >400 |
| NOx (SGP41 index, center=1) | ≤1 / ≤2 / >2 |
| 온도 (°C) | <18 서늘 / ≤24 쾌적 / ≤28 따뜻 / >28 더움 |
| 습도 (%) | <30 건조 / ≤60 쾌적 / ≤70 약간높음 / >70 높음 |

함수: `metricStatus(id, value, humidity=50)` 디스패처가 라벨 문자열 반환.

### 17.2 `utils/mock_data.dart` (81 lines)
- **`AirQualityData`** (timestamp, pm25, iaqiScore, k, co2, tvoc, nox, temperature, humidity)
- **`StationData`** (name, distance, pm25, temperature, humidity)
- **`airQualityDataFromSnapshot(AirQualitySnapshot?)`** — 음수 → NaN sanitize, k는 `purification.cadr`에서 추출(`mock_data.dart:61`)
- 위젯이 raw 스냅샷 스키마와 분리되도록 어댑터 역할

### 17.3 `utils/color_utils.dart`
- `ColorUtils.withOpacityCompat(opacity)` — `withAlpha((opacity*255).round())`로 deprecated `withOpacity()` 대체

### 17.4 `config/firebase_env_options.dart` (88 lines)
- 플랫폼 감지(`Platform.isAndroid/iOS/macOS`, `kIsWeb`) → `String.fromEnvironment(...)` dart-define에서 `FirebaseOptions` 빌드
- 필수 변수: `FIREBASE_API_KEY`, `FIREBASE_PROJECT_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_[ANDROID|IOS]_APP_ID`, iOS는 `FIREBASE_IOS_BUNDLE_ID`, web은 `FIREBASE_AUTH_DOMAIN` (그리고 web의 `FIREBASE_STORAGE_BUCKET` 옵션)
- 누락 시 null 반환 → 기본 google-services.json 경로로 fallback

---

## 18. 펌웨어 보강 — OLED / LED / Watchdog

### 18.1 `firmware/display_local.yaml` (366 lines, OLED)
- 패널: SH1106 128×64, I²C 0x3C (SSD1306 호환)
- 폰트: OpenSans 9/14/20/34pt + 단위 글리프(°, %, µ, ³)
- **페이지 11종** (스위치로 on/off):
  - `pairing_pin_page` — PIN 6자리(20pt) + WiFi setup AP 안내 + IP/MAC. `pin_display_until`이 만료될 때까지 표시
  - `airgradient_default` — 좌상 온도(°C/°F 토글), 우상 습도, 중앙 CO₂ 대형, 중앙우 PM2.5 대형, 우측 TVOC/NOx
  - `summary1` / `summary2` — 4행 메트릭(전자: CO₂/PM2.5/온도/습도, 후자: CO₂/PM2.5/VOC/NOx)
  - `huge_no_units` — 4 코너 34pt (CO₂ TL, RH TR, PM2.5 BL, 온도 BR)
  - `air_quality / air_temp / air_voc / combo` — 특화 레이아웃
  - `boot` — ID, config 버전, 디바이스명
  - `blank` — 비페이지
- **페이지 회전**: 5초 주기 `display.page.show_next`. 비활성 페이지는 `on_page_change` 컨디셔널로 skip
- **PIN 오버레이**: `pin_display_until > millis()` 동안만 PIN 페이지 활성
- 대비(contrast) 슬라이더 0–100% (line:354-365)

### 18.2 `firmware/led.yaml` (42 lines)
- WS2812b 11픽셀, GPIO10, GRB, addressable
- 슬라이더 2종: `led_brightness`(0–100, 초기 100), `led_fade`(0–100, 초기 20) — fade 강도

### 18.3 `firmware/led_co2.yaml` (83 lines)
- **5초 주기 lambda**가 11개 픽셀(외곽 3 + 중간 5 + 중앙 1) 각각의 CO₂ 매핑 RGB를 계산
- **임계 substitution**: green=400, yellow=1000, red=2000, purple=4000
- **컬러 함수**(zone별 lambda):
  - `R`: <400 → 0, 400–1000 선형 ramp, ≥1000 → 1
  - `G`: <1000 → 1, 1000–2000 선형 감쇠, ≥2000 → 0
  - `B`: <2000 → 0, 2000–4000 선형 ramp, ≥4000 → 1
- **구간별 밝기**: `(led_brightness − led_fade·N)/100`, N∈[0,5] (외곽 zone일수록 더 빨리 fade)
- CO₂ NaN이면 전체 OFF

### 18.4 `firmware/watchdog.yaml` (19 lines)
- 외부 하드웨어 watchdog (ESP32-C3 안전성 강화)
- GPIO2 출력 (strapping pin 경고 suppress)
- 2.5분마다 20ms on/off 펄스로 살아있음 신호 — 미발화 시 하드웨어 재시작

---

## 19. 빠른 참조 — 파일 매핑

| 영역 | 파일 |
|---|---|
| 부팅 | `lib/main.dart` |
| 상태 머신 | `lib/state/air_quality_controller.dart` |
| Firestore stream + 변환 | `lib/services/firestore_snapshot_service.dart` |
| 건강 엔진 | `lib/utils/nodered_health_engine.dart` (+ `aqi_calculator.dart`, `health_calculator.dart`) |
| 외부 API | `lib/services/external_api_service.dart` |
| 데이터 모델 | `lib/models/air_quality_snapshot.dart` (+ `air_quality_metric.dart`) |
| 페어링 | `lib/services/device_binding_service_v2.dart` |
| 로컬 LAN | `lib/services/airgradient_local_api.dart`, `airgradient_local_config.dart`, `led_control_service.dart` |
| 플러그 제어 | `lib/services/tasmota_plug_service.dart` |
| 알림 | `lib/services/alert_notification_service.dart`, `alert_notification_engine.dart`, `alert_notification_presenter.dart`, `notification_preferences.dart`, `push_notification_service_v2.dart` |
| 캐시 | `lib/services/local_snapshot_store.dart` |
| 백그라운드 | `lib/services/background_service.dart` |
| UI 루트 | `lib/screens/home_page.dart` |
| UI 위젯 | `lib/widgets/{air_quality_overview, metric_detail_view, health_mode_dashboard, station_comparison, settings_view, air_quality_circle, sky_background, ...}.dart` |
| 백엔드 함수 | `iaq-v2-firebase/functions/index.js` |
| 알림 엔진 | `iaq-v2-firebase/functions/alertEngine.js` |
| MQTT 워커 | `iaq-v2-firebase/functions/plug_mqtt_worker.js` |
| Firestore 룰 | `iaq-v2-firebase/firestore.rules` |
| 펌웨어 | `iaq-v2-firebase/firmware/ag-one-capstone.yaml`, `airgradient_api_esp32-c3.yaml`, `display_local.yaml`, `led*.yaml`, `watchdog.yaml` |
