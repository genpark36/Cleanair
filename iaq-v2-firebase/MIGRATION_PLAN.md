# IAQ v2 Firebase 마이그레이션 계획서

> **작성일**: 2026-03-01
> **목적**: Node-RED + HiveMQ + backend/notifications → ESPHome + Firebase 단일 스택 전환
> **원칙**: 기존 코드(`Indoorairqualityappv2-main`)에 일절 간섭하지 않음

---

## 1. 폴더 구조

```
capstoneapp/
├── Indoorairqualityappv2-main/   ← 기존 프로젝트 (절대 수정하지 않음)
│
└── iaq-v2-firebase/              ← 이 폴더에서만 작업
    ├── MIGRATION_PLAN.md         ← 이 파일 (개발 중 항상 참조)
    ├── firmware/                 ← ESPHome 커스텀 YAML
    │   └── ag-one-capstone.yaml
    ├── functions/                ← Firebase Cloud Functions
    │   ├── package.json
    │   ├── index.js              ← ingest + alertCheck + deviceRegister
    │   └── alertEngine.js        ← backend/notifications에서 포팅
    └── flutter/                  ← 포팅된 Dart 코드 (나중에 기존 앱에 교체 적용)
        └── lib/
            ├── services/
            │   ├── firestore_snapshot_service.dart   ← mqtt_snapshot_service.dart 대체
            │   ├── push_notification_service_v2.dart ← 엔드포인트를 Cloud Function으로
            │   └── device_binding_service_v2.dart    ← mqttTopicPrefix → Firestore docPath
            └── utils/
                └── (변경 없음 — health_calculator.dart, aqi_calculator.dart는 그대로 복사)
```

---

## 2. 현재 아키텍처 vs 목표 아키텍처

### Before (현재)

```
AirGradient (순정)
  → AG Cloud → publish_to_hivemq.py → HiveMQ
                                        ↓
  Flutter ← MQTT ← Node-RED (52 함수노드, ~3800줄 JS) ← HiveMQ
                                        ↓
                   backend/notifications (1100줄 JS) → FCM
                                        ↓
                   Firestore (alerts, snapshots, devices)
```

**구성 요소**: 7개 (센서, AG Cloud, Python 브릿지, HiveMQ, Node-RED, backend/notifications, Flutter)
**서버 프로세스**: 3개 (Node-RED, backend/notifications, publish_to_hivemq.py)
**설정 파일**: .env, credential JSON, flows.json, settings.js, docker-compose 등 10+개

### After (목표)

```
AirGradient (ESPHome)
  → HTTPS POST (30초) → Cloud Function (ingest)
                          ├── Firestore 저장 (latest + history)
                          └── 임계값 초과 시 → FCM 푸시
                                ↓
  Flutter ← Firestore onSnapshot (실시간, 글로벌)
```

**구성 요소**: 3개 (센서, Firebase, Flutter)
**자체 서버**: 0개 (Cloud Function = 서버리스)
**설정 파일**: google-services.json 1개

---

## 3. 포팅 작업 목록 (체크리스트)

### Phase 0: 준비 (기반 작업)
- [x] Firebase 프로젝트 확인 (`capstone-air-quality-yu25` 기존 프로젝트 사용)
- [x] Firestore 컬렉션 구조 설계
- [x] Cloud Functions 프로젝트 초기화 (`functions/`)
- [x] ESPHome 빌드 환경 준비 (YAML 작성 완료, 플래싱은 Phase 4 검증에서)

### Phase 1: Cloud Function — 데이터 수신 (P0, 핵심)
- [x] `functions/index.js` → `ingest` 함수: HTTPS POST 수신 → Firestore 저장
- [x] Firestore 구조: `sensors/{serialNo}` (latest) + `sensors/{serialNo}/history` (시계열)
- [x] API 키 검증 (X-API-Key 헤더)
- [x] 응답 포맷: `{ ok: true, timestamp: ... }`

### Phase 2: Cloud Function — 알림 엔진 (P0)
- [x] `functions/alertEngine.js` ← `backend/notifications/src/alertEngine.js` 포팅
  - 12개 watcher (pm25, co2, tvoc, nox, respiratory, infection, focus, cardio, sleep, mold, apparent_temp ×2)
  - 히스테리시스 (clearBelow/clearAbove)
  - 최소 지속시간 (minDurationMs)
  - 30분 억제 (SUPPRESS_MS)
  - quiet hours 필터링
  - 트렌드 메타 (k값 기반)
- [x] FCM 발송: `admin.messaging().send()` → 등록된 디바이스로
- [x] Firestore `devices` 컬렉션에서 수신자 조회

### Phase 3: Cloud Function — 디바이스 관리 (P1)
- [x] `registerDevice` 함수: FCM 토큰 등록
- [x] `claimDevice` 함수: 6자리 코드로 센서-앱 바인딩
- [x] `updatePreferences` 함수: 알림 설정 (quiet hours, mute, snooze)

### Phase 4: ESPHome 펌웨어 (P0, 센서 측)
- [x] `firmware/ag-one-capstone.yaml` 작성
  - 기존 `airgradient-one.yaml` 기반
  - WiFi 설정 (secrets.yaml 사용)
  - http_request.post → Cloud Function URL
  - 기존 센서 설정(EPA 보정, AQI 계산) 유지 (변경 없음)
  - AirGradient Dashboard 업로드 토글 유지 (선택)
  - 전송 간격: 기본 5초(필요 시 조정)
  - JSON 페이로드: pm25, co2, tvoc, nox, temp, humidity, serial, firmware

### Phase 5: Flutter — Firestore 연결 (P0, 앱 측)
- [x] `firestore_snapshot_service.dart` 신규 작성
  - `MqttSnapshotService`와 동일한 인터페이스: `Stream<AirQualitySnapshot>`
  - `Firestore.instance.collection('sensors').doc(sensorId).snapshots()` 사용
  - `AirQualitySnapshot.fromJson()` 재사용 (기존 모델 그대로)
  - 연결 상태: `ConnectionState` enum (connected/disconnected/error)
- [x] `air_quality_controller.dart` 변경: `MqttSnapshotService` → `FirestoreSnapshotService`
- [x] `alert_notification_service.dart` 변경: 생성자 DI 대상만 변경

### Phase 6: Flutter — API 엔드포인트 전환 (P1)
- [x] `push_notification_service_v2.dart` 작성
  - `BACKEND_BASE_URL` → Cloud Function URL
  - `NR_API_KEY` 제거
  - `/api/devices/register` → `registerDevice` Cloud Function
  - `/api/devices/preferences` → `updatePreferences` Cloud Function
- [x] `device_binding_service_v2.dart` 작성
  - `mqttTopicPrefix` → `firestoreDocPath` (예: `sensors/ag-one-abc123`)
  - `/api/devices/claim` → `claimDevice` Cloud Function

### Phase 7: 정리 — 통합 준비 (P2, 마지막)
- [x] Firebase 배포 설정 (`.firebaserc`, `firebase.json`, `firestore.rules`) 완료
- [x] `flutter/pubspec.yaml` v2 작성 (`mqtt_client`/`webview_flutter` 제거, `cloud_firestore` 추가)
- [x] `flutter/lib/main.dart` v2 작성 (MQTT → Firestore DI 전환, `MqttBridgeHost` 제거)
- [x] `flutter/lib/state/air_quality_controller.dart` v2 작성
- [x] `flutter/lib/services/alert_notification_service.dart` v2 작성
- [x] `firmware/secrets.yaml.example` 작성
- [ ] 이전 완료 검증 후, 기존 프로젝트에서 제거 가능한 파일 목록:
  - `mqtt_snapshot_service.dart` (702줄)
  - `mqtt_js_bridge.dart` + `_web.dart` + `_mobile.dart` + `_stub.dart` (4파일)
  - `background_service.dart`의 MQTT 구독 코드 제거
  - `settings_view.dart`의 MQTT 브릿지 토글 제거
  - 루트: `flows.json`, `settings.js`, `docker-compose.dev.yml`, `Dockerfile`
  - 루트: `mqtt_bridge.py`, `publish_to_hivemq.py`
  - `backend/notifications/` 전체
  - `nodered/` 전체

---

## 4. Firestore 컬렉션 설계

```
firestore-root/
├── sensors/
│   ├── {serialNo}/                      ← 센서별 문서
│   │   ├── latest: { pm25, co2, tvoc, nox, temp, humidity, timestamp }
│   │   ├── firmware: "capstone-1.0"
│   │   ├── lastSeen: Timestamp
│   │   └── history/                     ← 서브컬렉션 (시계열)
│   │       ├── {auto-id}: { pm25, co2, ..., timestamp }
│   │       └── ...
│
├── devices/                             ← FCM 토큰 → 센서 매핑
│   ├── {fcmToken}/
│   │   ├── token: "fcm-token-string"
│   │   ├── sensorId: "ag-one-abc123"
│   │   ├── alertsEnabled: true
│   │   ├── quietHours: { start: "22:00", end: "07:00" }
│   │   ├── quietHoursEnabled: false
│   │   ├── snoozedUntil: null
│   │   ├── mutedTypes: { pm25_high: false, co2_high: false, ... }
│   │   └── updatedAt: Timestamp
│
├── device_codes/                        ← 6자리 페어링 코드
│   ├── {code}/
│   │   ├── sensorId: "ag-one-abc123"
│   │   ├── expiresAt: Timestamp
│   │   └── claimedBy: null | "fcm-token"
│
└── alerts/                              ← 알림 이력
    ├── {auto-id}/
    │   ├── type: "pm25_high"
    │   ├── severity: "warning"
    │   ├── value: 38.2
    │   ├── sensorId: "ag-one-abc123"
    │   ├── createdAt: Timestamp
    │   └── ...
```

---

## 5. 파일별 포팅 전략

### 5.1 변경 없이 복사 (그대로 사용)

| 파일 | 줄 수 | 이유 |
|------|-------|------|
| `health_calculator.dart` | 594 | 순수 계산, MQTT 의존 없음 |
| `aqi_calculator.dart` | 80 | 순수 계산, MQTT 의존 없음 |
| `air_quality_snapshot.dart` | 996 | 데이터 모델, JSON 파싱 |
| `health_mode_dashboard.dart` | ~400 | UI 위젯, 데이터만 받음 |
| `health_mode_view.dart` | ~300 | UI 위젯 |
| `air_quality_overview.dart` | ~250 | UI 위젯 |
| `sky_background.dart` | ~80 | UI 위젯 |
| `notification_preferences.dart` | ~180 | SharedPreferences 로컬 저장 |
| `local_snapshot_store.dart` | ~200 | 로컬 파일 저장 |
| `daily_log_service.dart` | ~100 | 로컬 로깅 |

### 5.2 신규 작성 (이 폴더에서 개발)

| 파일 | 예상 줄 수 | 대체 대상 | 설명 |
|------|-----------|-----------|------|
| `firestore_snapshot_service.dart` | ~150 | `mqtt_snapshot_service.dart` (702줄) | MQTT → Firestore 실시간 리스너 |
| `push_notification_service_v2.dart` | ~120 | `push_notification_service.dart` (248줄) | API URL 변경 |
| `device_binding_service_v2.dart` | ~100 | `device_binding_service.dart` (185줄) | 바인딩 경로 변경 |
| `functions/index.js` | ~200 | Node-RED + backend/notifications | 수신 + 알림 + 등록 |
| `functions/alertEngine.js` | ~400 | `backend/notifications/src/alertEngine.js` (471줄) | 거의 복붙 |
| `firmware/ag-one-capstone.yaml` | ~50 | (신규) | ESPHome YAML |

### 5.3 수정 필요 (기존 파일 수정, Phase 7에서)

| 파일 | 수정 내용 | 규모 |
|------|----------|------|
| `air_quality_controller.dart` | `MqttSnapshotService` → `FirestoreSnapshotService` import 변경 | 3줄 |
| `alert_notification_service.dart` | 생성자 DI 대상 변경 | 2줄 |
| `main.dart` | Provider 등록 변경 | 5줄 |
| `settings_view.dart` | MQTT 브릿지 토글 UI 제거 | 10줄 |
| `pubspec.yaml` | `mqtt_client` 제거, `cloud_firestore` 추가 | 2줄 |

---

## 6. Node-RED 52개 함수 노드 이전 맵

### 이미 Flutter에 있음 (포팅 불필요)

| Node-RED 함수 | Flutter 대응 파일 | 상태 |
|---------------|------------------|------|
| 건강지표 종합 계산 | `health_calculator.dart` | ✅ 완전 중복 |
| 호흡기 건강지표 | `health_calculator.dart:16` | ✅ |
| 감염 위험도 | `health_calculator.dart:48` | ✅ |
| 집중 환경 점수 | `health_calculator.dart:72` | ✅ |
| 심혈관 보호점수 | `health_calculator.dart:93` | ✅ |
| 수면 환경 점수 | `health_calculator.dart:165` | ✅ |
| 체감온도 계산 | `health_calculator.dart:202` | ✅ |
| IAQI 계산 | `aqi_calculator.dart` | ✅ |
| CADR 계산 | `health_calculator.dart:412` | ✅ |
| IPI 위험도 | `health_calculator.dart:502` | ✅ |
| 정화율 등급 | `health_calculator.dart:370` | ✅ |

### Cloud Function으로 이전

| Node-RED 함수 | 이전 위치 | 작업량 |
|---------------|----------|--------|
| FCM 알림 발송 | `functions/index.js` | 중 (alertEngine 포트) |
| 디바이스 등록 API | `functions/index.js` | 소 |
| 알림 12종 규칙 + 히스테리시스 | `functions/alertEngine.js` | 중 (거의 복붙) |

### Flutter에서 직접 호출로 전환

| Node-RED 함수 | 이전 방법 | 작업량 |
|---------------|----------|--------|
| WAQI 야외 비교 | `http.get('https://api.waqi.info/...')` | 소 (~30줄) |
| 기상청 API | `http.get(...)` | 소 (~30줄) |
| AI 추천 시스템 | 규칙 기반 → Dart 함수 | 소 (~80줄) |

### 센서(ESPHome)에서 이미 처리

| Node-RED 함수 | ESPHome 내장 | 비고 |
|---------------|-------------|------|
| EPA PM2.5 보정 | ag-one.yaml lambda | 같은 공식 |
| AQI 브레이크포인트 | ag-one.yaml pm_2_5_aqi | 같은 EPA 2024 기준 |

### 제거 (v2에서 불필요)

| Node-RED 함수 | 이유 |
|---------------|------|
| MQTT fanout 분배기 (507줄) | MQTT 자체가 제거됨 |
| Node-RED Dashboard UI 노드 (85개) | 모바일 앱으로 대체 |
| CSV 내보내기 | Flutter `csv` 패키지로 대체 가능 (Phase 2+) |
| Chart data transform | Flutter 차트가 직접 처리 |
| ACH 로그 포맷터 | k값에서 Flutter가 직접 계산 |

---

## 7. ESPHome YAML 수정 범위

기존 `ag-one.yaml`에서 **변경하는 부분:**

```yaml
# 변경 1: AirGradient Dashboard 업로드 대상 URL → 우리 Cloud Function
# 기존:
#   url: "https://hw.airgradient.com/sensors/airgradient:${mac}/measures"
# 변경:
#   url: "https://us-central1-capstone-air-quality-yu25.cloudfunctions.net/ingest"

# 변경 2: 전송 간격 (기존 150초 → 30초)
# 기존: interval: 150s
# 변경: interval: 30s

# 변경 3: JSON 페이로드에 serial 추가

# 그 외 센서 설정, EPA 보정, LED, 디스플레이 → 전부 그대로
```

**변경하지 않는 부분:**
- PMS5003 센서 설정
- EPA PM2.5 보정 공식
- AQI 브레이크포인트 계산
- SHT40 온습도 센서
- Senseair S8 CO₂ 센서
- SGP41 VOC/NOx 센서
- OLED 디스플레이 페이지
- LED 바 색상 로직
- WiFi/Captive Portal 설정
- CO₂ 캘리브레이션 버튼

---

## 8. 작업 순서 (의존성 기준)

```
Phase 1 ──→ Phase 2 ──→ Phase 3
  (CF 수신)    (CF 알림)    (CF 디바이스)
     │
     ↓
Phase 4 (ESPHome YAML) ← Phase 1 완료 후 URL 확정
     │
     ↓
Phase 5 (Flutter Firestore) ← Phase 1 완료 후 Firestore 구조 확정
     │
     ↓
Phase 6 (Flutter API 전환) ← Phase 3 완료 후 엔드포인트 확정
     │
     ↓
Phase 7 (정리) ← 전체 검증 후
```

**병렬 가능**: Phase 1~3 (Cloud Function)과 Phase 4 (ESPHome)는 동시 작업 가능
**직렬 필수**: Phase 5, 6은 Phase 1~3 이후

---

## 9. 검증 체크리스트

각 Phase 완료 후 검증:

### Phase 1 검증
- [ ] `curl -X POST {CF_URL}/ingest -H "Content-Type: application/json" -d '{...}'` → 200 OK
- [ ] Firestore 콘솔에서 `sensors/{id}` 문서 생성 확인
- [ ] `sensors/{id}/history` 서브컬렉션에 레코드 추가 확인

### Phase 2 검증
- [ ] PM2.5 > 35 데이터 전송 → FCM 푸시 수신 확인
- [ ] 30분 내 동일 알림 억제 확인
- [ ] quiet hours 중 notice/warning 알림 미발송 확인

### Phase 4 검증
- [ ] ESPHome 컴파일 성공
- [ ] 센서 플래싱 + WiFi 연결 확인
- [ ] Cloud Function에 데이터 도착 확인 (Firestore 확인)

### Phase 5 검증
- [ ] Flutter 앱에서 Firestore 실시간 데이터 수신 확인
- [ ] 센서 데이터 30초 내 앱에 표시 확인
- [ ] 건강지표 6종 정상 계산 확인
- [ ] 차트/그래프 정상 표시 확인

### 통합 검증
- [ ] 센서 전원 ON → 30초 내 앱에 데이터 표시
- [ ] PM2.5 위험 수준 → 앱 종료 상태에서 FCM 푸시 수신
- [ ] 서로 다른 WiFi 네트워크에서 원격 모니터링 확인
- [ ] 앱 + 센서만으로 전체 기능 동작 확인 (서버 프로세스 0)

---

## 10. 롤백 전략

**기존 코드에 일절 손대지 않았으므로**, 실패 시:
1. `iaq-v2-firebase/` 폴더 삭제
2. 센서에 순정 펌웨어 재플래싱 (web.esphome.io에서 AirGradient 공식 .bin)
3. 기존 시스템(`Indoorairqualityappv2-main`) 그대로 사용

**위험도: 0** — 기존 시스템은 이 작업과 완전히 격리됨

---

## 11. 비용 추정 (Firebase 무료 티어)

| 항목 | 월간 사용량 (센서 1대) | Spark 무료 한도 | 초과 여부 |
|------|----------------------|----------------|-----------|
| Cloud Function 호출 | ~86,400회 (30초×24h×30일) | 2,000,000회/월 | ✅ 무료 |
| Firestore 쓰기 | ~86,400회 | 600,000회/일 | ✅ 무료 |
| Firestore 읽기 | 앱 사용량 따라 | 50,000회/일 | ✅ 무료 |
| FCM | 무제한 | 무제한 | ✅ 무료 |
| Cloud Function 컴퓨팅 | ~2,880 GHz-초/일 | 125,000 GHz-초/월 | ✅ 무료 |

센서 20대까지 무료 티어 내에서 운영 가능.

---

## 12. 참조 문서

- EPA PM2.5 보정: Barkjohn et al. (2021) DOI: 10.5194/amt-14-4617-2021
- EPA AQI 브레이크포인트: https://www.epa.gov/system/files/documents/2024-02/pm-naaqs-air-quality-index-fact-sheet.pdf
- ESPHome http_request: https://esphome.io/components/http_request.html
- Firebase Cloud Functions: https://firebase.google.com/docs/functions
- Firestore 실시간 리스너: https://firebase.google.com/docs/firestore/query-data/listen
- AirGradient ESPHome 포크: https://github.com/MallocArray/airgradient_esphome
- ESPHome 웹 플래싱: https://web.esphome.io/

---

_이 문서는 개발 진행에 따라 업데이트됩니다. 각 Phase 완료 시 체크리스트를 표시하세요._
