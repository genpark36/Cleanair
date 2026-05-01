# 대화 맥락 요약 — 새 창에서 이어서 작업하기 위한 문서

> **작성일**: 2026-03-01
> **용도**: Copilot 새 세션에서 이 파일을 먼저 읽고 기존 맥락을 파악하도록 함
> **사용법**: 새 창에서 "이 파일을 읽고 맥락을 파악한 뒤 작업을 이어줘" 라고 지시

---

## 1. 프로젝트 개요

- **프로젝트명**: Indoor Air Quality (IAQ) 캡스톤 프로젝트
- **작업 폴더**: `c:\Users\박건우\Desktop\capstoneapp`
- **Firebase 프로젝트**: `capstone-air-quality-yu25` (프로젝트 번호: 15643247366)
- **기존 코드**: `Indoorairqualityappv2-main/` — **절대 수정 금지**
- **신규 작업 폴더**: `iaq-v2-firebase/` — 여기서만 작업

---

## 2. 핵심 결정 사항 (변경 불가)

### 2.1 아키텍처 전환 결정
**기존 (7개 구성 요소):**
```
AirGradient(순정) → AG Cloud → publish_to_hivemq.py → HiveMQ MQTT
→ Node-RED (52 함수노드, ~3800줄 JS) → Flutter 앱
→ backend/notifications (1100줄 JS) → FCM
→ Firestore
```

**목표 (3개 구성 요소):**
```
AirGradient(ESPHome) → HTTPS POST(30초) → Cloud Function → Firestore → Flutter onSnapshot
                                            └── 임계값 초과 시 → FCM 푸시
```

### 2.2 전환 이유
1. 사용자가 센서 + 앱만으로 전체 기능을 사용할 수 있어야 함 (자체 서버 0)
2. Node-RED, HiveMQ, Python 브릿지 등 복잡한 서버 구성 제거
3. AG Cloud API는 2-3분 지연 → ESPHome으로 직접 HTTPS POST하면 30초면 실시간
4. Cloud Function은 MQTT 구독 불가 → 그래서 센서가 직접 HTTPS POST하는 구조로 결정

### 2.3 하드웨어
- **센서**: AirGradient ONE (ESP32-C3, 160MHz RISC-V, 400KB RAM, 4MB Flash)
- **탑재 센서**: PMS5003 (PM), Senseair S8 (CO₂), SHT40 (온습도), SGP41 (VOC/NOx)
- **ESPHome 설치 필요**: 순정 펌웨어 → ESPHome 플래싱 (web.esphome.io)

---

## 3. 코드베이스 핵심 파일 분석 (이미 완료)

### 3.1 그대로 복사 (MQTT 의존성 없음)
| 파일 | 줄 수 | 설명 |
|------|-------|------|
| `health_calculator.dart` | 594 | 건강지표 6종 계산 (호흡기, 감염, 집중, 심혈관, 수면, 체감온도) + CADR + IPI |
| `aqi_calculator.dart` | 80 | US EPA AQI 브레이크포인트 보간 계산 |
| `air_quality_snapshot.dart` | 996 | 데이터 모델, JSON 파싱 팩토리, PurificationCadrSnapshot 포함 |

### 3.2 완전 교체 (🔴 핵심 작업)
| 기존 파일 | 줄 수 | 신규 파일 | 예상 줄 수 |
|-----------|-------|-----------|-----------|
| `mqtt_snapshot_service.dart` | 702 | `firestore_snapshot_service.dart` | ~150 |
| `mqtt_js_bridge*.dart` (4파일) | — | (삭제) | 0 |

### 3.3 수정 필요 (🟡 소규모)
| 파일 | 수정 규모 | 내용 |
|------|----------|------|
| `air_quality_controller.dart` | 3줄 | import 변경 |
| `alert_notification_service.dart` | 2줄 | DI 대상 변경 |
| `push_notification_service.dart` | URL 변경 | API 엔드포인트 → Cloud Function |
| `device_binding_service.dart` | 경로 변경 | mqttTopicPrefix → firestoreDocPath |
| `settings_view.dart` | 10줄 | MQTT 브릿지 토글 UI 제거 |
| `main.dart` | 5줄 | Provider 등록 변경 |
| `pubspec.yaml` | 2줄 | mqtt_client 제거, cloud_firestore 추가 |

### 3.4 서버 측 포팅 대상
| 기존 파일 | 줄 수 | 신규 파일 | 방식 |
|-----------|-------|-----------|------|
| `backend/notifications/src/alertEngine.js` | 471 | `functions/alertEngine.js` | 거의 복붙 (같은 JS) |
| `backend/notifications/src/index.js` | 576 | `functions/index.js` | 재작성 (MQTT→HTTPS) |
| Node-RED 52개 함수노드 | ~3800 | 대부분 Flutter에 이미 존재 | 포팅 불필요 |

---

## 4. backend/notifications 상세 (포팅 대상)

### alertEngine.js (471줄) — 핵심 알림 로직
- **12개 watcher**: pm25_high, co2_high, tvoc_high, nox_high, respiratory_low, infection_risk, focus_poor, cardio_low, sleep_quality_low, mold_risk, apparent_temp_morning, apparent_temp_evening
- **히스테리시스**: clearBelow/clearAbove 값으로 on/off 토글
- **최소 지속시간**: minDurationMs (예: 3분 이상 초과 시에만 알림)
- **30분 억제**: SUPPRESS_MS — 같은 타입 알림 30분 내 재발송 방지
- **quiet hours**: 밤시간 notice/warning 등급 알림 미발송 (critical은 항상 발송)
- **트렌드 메타**: k값 기반으로 상승/하강 추세 포함
- **심각도**: notice / warning / critical

### index.js (576줄) — 서버 프레임워크 (재작성 대상)
- MQTT 리스너 (HiveMQ 연결) → **제거** (Cloud Function HTTPS 수신으로 대체)
- Express REST API (포트 4100):
  - `/api/devices/register` — FCM 토큰 등록
  - `/api/devices/code` — 6자리 페어링 코드 생성
  - `/api/devices/claim` — 코드로 센서-앱 바인딩
  - `/api/devices/preferences` — 알림 설정 CRUD
  - `/api/alerts/generate-latest` — 수동 알림 생성
  - `/api/push/test` — 테스트 푸시
- Firestore CRUD: snapshots, alerts, devices, device_codes, relay_servers
- FCM 디스패치

### HiveMQ 자격정보 (현재, 제거 예정)
- 서버: `7d18e3d75dbb4d12aa5951049f5868d2.s1.eu.hivemq.cloud`
- 사용자: `Capstone` / 비밀번호: `Capstone1`

---

## 5. Node-RED 52개 함수 노드 — 이전 결과

| 카테고리 | 개수 | 이전 방법 |
|----------|------|----------|
| 건강지표 계산 (호흡기, 감염, 집중 등) | 11 | Flutter에 이미 존재 → 포팅 불필요 |
| FCM 알림 + 히스테리시스 | 3 | → Cloud Function `alertEngine.js` |
| 디바이스 관리 API | 2 | → Cloud Function `index.js` |
| WAQI 야외 비교 | 1 | → Flutter `http.get()` (~30줄) |
| 기상청 API | 1 | → Flutter `http.get()` (~30줄) |
| AI 추천 시스템 | 1 | → Flutter 규칙 기반 함수 (~80줄) |
| EPA PM2.5 보정 / AQI 계산 | 2 | ESPHome에 이미 내장 |
| MQTT fanout 분배기 | 1 (507줄) | 삭제 (MQTT 제거됨) |
| Dashboard UI 노드 | 85 | 삭제 (앱으로 대체) |
| CSV, 차트, ACH 포맷터 | 3 | 삭제 또는 Flutter로 대체 |

---

## 6. ESPHome 수정 범위

기존 `ag-one.yaml` (1192줄)에서 **변경 3곳만:**

1. **URL**: `https://hw.airgradient.com/...` → Cloud Function URL
2. **간격**: `interval: 150s` → `interval: 30s`
3. **페이로드**: JSON에 `serial` 필드 추가

**나머지 전부 그대로**: 센서 설정, EPA 보정 공식, AQI 계산, LED, 디스플레이, WiFi, CO₂ 캘리브레이션

### EPA PM2.5 보정 공식 (ESPHome과 순정 펌웨어 동일)
- **출처**: Barkjohn et al. (2021) DOI: 10.5194/amt-14-4617-2021
- **공식**: `PM2.5_corrected = 0.524 × PM2.5_cf1 - 0.0862 × RH + 5.75`
- **ESPHome 구현 위치**: ag-one.yaml lambda 함수

---

## 7. 작업 진행 상황

### ✅ 완료
1. 전체 코드베이스 감사 (150+ 파일)
2. 4개 문서 작성 (SYSTEM_ARCHITECTURE.md, DEV_STATUS.md, DEV_PLAN.md, DEV_LOG.md)
3. 죽은 파일 정리
4. flows.json 정리 (701 → 187 노드)
5. airgradient_esphome-main 분석 완료
6. 아키텍처 결정 완료 (ESPHome + Firebase)
7. backend/notifications 완전 분석 (5개 소스 파일)
8. Node-RED 52개 함수 노드 분류 및 이전 맵 작성
9. 80+ 기능 포팅 가능성 감사
10. `iaq-v2-firebase/` 독립 폴더 생성
11. `MIGRATION_PLAN.md` 작성 (12개 섹션, 전체 체크리스트)

### 🔲 미착수 (Phase 0~7)
- **Phase 0**: Firebase/Firestore 설정
- **Phase 1**: Cloud Function — 데이터 수신 (`ingest` 함수)
- **Phase 2**: Cloud Function — 알림 엔진 (`alertEngine` 포트)
- **Phase 3**: Cloud Function — 디바이스 관리 (등록/클레임/설정)
- **Phase 4**: ESPHome YAML 작성 (`ag-one-capstone.yaml`)
- **Phase 5**: Flutter Firestore 서비스 (`firestore_snapshot_service.dart`)
- **Phase 6**: Flutter API 엔드포인트 전환
- **Phase 7**: 정리 (기존 파일 제거)

### 작업 순서 (의존성)
```
Phase 1 → Phase 2 → Phase 3    (Cloud Function, 순차)
Phase 1 → Phase 4              (ESPHome, Phase 1 URL 확정 후)
Phase 1 → Phase 5              (Flutter, Phase 1 Firestore 구조 확정 후)
Phase 3 → Phase 6              (Flutter API, Phase 3 엔드포인트 확정 후)
전체 검증 → Phase 7            (정리, 마지막)
```

---

## 8. Firestore 컬렉션 설계 (확정)

```
sensors/{serialNo}                    ← latest 데이터 + metadata
sensors/{serialNo}/history/{auto-id}  ← 시계열 (30초 간격)
devices/{fcmToken}                    ← FCM 토큰 → 센서 매핑 + 알림 설정
device_codes/{code}                   ← 6자리 페어링 코드
alerts/{auto-id}                      ← 알림 이력
```

---

## 9. 비용 추정

- 센서 1대 기준: **월 ~86,400회** Cloud Function 호출 (30초 × 24h × 30일)
- Firebase Spark(무료) 한도: 2,000,000회/월
- **센서 20대까지 완전 무료** 운영 가능
- FCM 푸시: 무제한 무료

---

## 10. 기술 참조

| 항목 | 참조 |
|------|------|
| EPA PM2.5 보정 논문 | Barkjohn et al. (2021) DOI: 10.5194/amt-14-4617-2021 |
| EPA AQI 브레이크포인트 | https://www.epa.gov/system/files/documents/2024-02/pm-naaqs-air-quality-index-fact-sheet.pdf |
| ESPHome http_request | https://esphome.io/components/http_request.html |
| Firebase Cloud Functions | https://firebase.google.com/docs/functions |
| Firestore 실시간 리스너 | https://firebase.google.com/docs/firestore/query-data/listen |
| AirGradient ESPHome 포크 | https://github.com/MallocArray/airgradient_esphome |

---

## 11. 지시사항 (새 세션 Copilot에게)

1. **기존 코드 수정 금지**: `Indoorairqualityappv2-main/` 폴더의 파일은 절대 수정하지 마세요.
2. **작업 폴더**: 모든 신규 코드는 `iaq-v2-firebase/` 에서만 작성하세요.
3. **참조 문서**: 작업 전 항상 `iaq-v2-firebase/MIGRATION_PLAN.md`를 확인하세요.
4. **다음 작업**: Phase 1 (Cloud Function `ingest` 함수)부터 시작하세요.
5. **언어**: 사용자는 한국어를 사용합니다. 코드 주석은 한국어도 가능합니다.
6. **작업 스타일**: 독립 폴더에서 먼저 개발 → 검증 완료 후 기존 앱에 교체 적용 (Phase 7)

---

_이 문서는 기존 대화의 핵심 맥락을 보존하기 위해 작성되었습니다._
_상세 체크리스트와 Firestore 스키마는 `MIGRATION_PLAN.md`를 참조하세요._
