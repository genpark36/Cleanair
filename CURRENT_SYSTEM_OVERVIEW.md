# 현재 시스템 개요

기준일: 2026-04-02

이 문서는 이 워크스페이스의 소스 코드와 이번 세션의 최신 구현 및 배포 내용을 기준으로, 현재 시스템의 End-to-End 상태를 통합 정리한 문서입니다.

## 1) 범위와 기준 소스

현재 운영 기준으로 보는 주요 경로:

- Flutter 앱(활성): [Indoorairqualityappv2-main/src/flutter](Indoorairqualityappv2-main/src/flutter)
- Cloud Functions(활성): [iaq-v2-firebase/functions/index.js](iaq-v2-firebase/functions/index.js)
- 알림 엔진(백엔드): [iaq-v2-firebase/functions/alertEngine.js](iaq-v2-firebase/functions/alertEngine.js)
- Firestore 규칙(백엔드 프로젝트): [iaq-v2-firebase/firestore.rules](iaq-v2-firebase/firestore.rules)
- AirGradient ESPHome 설정(워크스페이스 트랙): [iaq-v2-firebase/firmware](iaq-v2-firebase/firmware)

동일 워크스페이스에 병행 또는 레거시 코드도 존재:

- 병행 Cloud Functions: [Indoorairqualityappv2-main/functions/index.js](Indoorairqualityappv2-main/functions/index.js)
- 병행 Firestore 규칙: [Indoorairqualityappv2-main/firestore.rules](Indoorairqualityappv2-main/firestore.rules)

## 2) End-to-End 아키텍처

```mermaid
flowchart TD
  A[AirGradient 센서] -->|HTTP POST telemetry| B[Firebase Function: ingest 또는 relay]
  B --> C[(Firestore sensors/{id})]
  B --> D[(Firestore sensors/{id}/history)]
  B --> E[(Firestore sensors/{id}/series)]
  B --> F[(Firestore alerts)]
  F --> G[FCM Push 발송]

  H[Flutter 앱] -->|claim/register/update prefs| B
  H -->|실시간 snapshot 구독| C
  H -->|history 조회| D

  H -->|로컬 LAN 제어| A
  H -->|WAQI + KMA 조회| I[외부 API]
```

## 3) Flutter 앱 구조와 동작

### 3.1 앱 시작과 Provider 구성

엔트리: [Indoorairqualityappv2-main/src/flutter/lib/main.dart](Indoorairqualityappv2-main/src/flutter/lib/main.dart)

부팅 순서:

1. Firebase 초기화
2. 핵심 서비스 객체 구성
   - Firestore snapshot service
   - Local snapshot store
   - Notification preferences controller
   - Device binding controller
   - Local alert notification service
   - Push notification service(FCM)
3. 기존 바인딩이 있으면 Firestore 문서 경로를 즉시 설정하고 push service에 sensor id를 연결
4. Provider 트리 생성 후 AirQualityController 초기화

### 3.2 상태 파이프라인

컨트롤러: [Indoorairqualityappv2-main/src/flutter/lib/state/air_quality_controller.dart](Indoorairqualityappv2-main/src/flutter/lib/state/air_quality_controller.dart)

핵심 동작:

- 최신 snapshot과 메모리 history 윈도우(7일, 상한 개수) 유지
- 로컬 캐시를 먼저 로드한 뒤 sensors/{id}/history와 병합
- Firestore 문서 실시간 스트림 구독
- timestamp 기준 중복 snapshot 제거
- 연결 상태 추적: disconnected, connecting, connected, error

### 3.3 Firestore snapshot 서비스

서비스: [Indoorairqualityappv2-main/src/flutter/lib/services/firestore_snapshot_service.dart](Indoorairqualityappv2-main/src/flutter/lib/services/firestore_snapshot_service.dart)

역할:

- 설정된 Firestore 문서 경로(보통 sensors/{sensorId})에 연결
- Firestore latest/raw 데이터를 앱 snapshot 모델로 변환
- NodeRedHealthEngine으로 Node-RED 유사 건강 지표 계산
- ExternalApiService 폴링(WAQI/KMA)을 시작하고 위치 비교 데이터 주입
- history 로드 및 기기 데이터 초기화(history + series 삭제) 지원

### 3.4 UI 정보 구조

루트 화면: [Indoorairqualityappv2-main/src/flutter/lib/screens/home_page.dart](Indoorairqualityappv2-main/src/flutter/lib/screens/home_page.dart)

메인 탭:

1. 개요: [Indoorairqualityappv2-main/src/flutter/lib/widgets/air_quality_overview.dart](Indoorairqualityappv2-main/src/flutter/lib/widgets/air_quality_overview.dart)
2. 모니터링 상세: [Indoorairqualityappv2-main/src/flutter/lib/widgets/metric_detail_view.dart](Indoorairqualityappv2-main/src/flutter/lib/widgets/metric_detail_view.dart)
3. 건강 모드 대시보드: [Indoorairqualityappv2-main/src/flutter/lib/widgets/health_mode_dashboard.dart](Indoorairqualityappv2-main/src/flutter/lib/widgets/health_mode_dashboard.dart)
4. 측정소/API 비교: [Indoorairqualityappv2-main/src/flutter/lib/widgets/station_comparison.dart](Indoorairqualityappv2-main/src/flutter/lib/widgets/station_comparison.dart)

설정 화면:

- 파일: [Indoorairqualityappv2-main/src/flutter/lib/widgets/settings_view.dart](Indoorairqualityappv2-main/src/flutter/lib/widgets/settings_view.dart)
- 포함 기능:
  - 센서 연결과 해제
  - PIN 기반 클레임(권장)
  - mDNS 로컬 탐색 및 직접 바인딩
  - 로컬 API 기반 LED 제어와 CO2 수동 교정
  - 알림 설정(방해금지 시간, snooze, 알림 타입 mute)
  - Android 백그라운드 실행 관련 토글
  - 기기 데이터 초기화

### 3.5 센서 바인딩 및 클레임 흐름

바인딩 컨트롤러: [Indoorairqualityappv2-main/src/flutter/lib/services/device_binding_service_v2.dart](Indoorairqualityappv2-main/src/flutter/lib/services/device_binding_service_v2.dart)

기본 흐름:

1. 앱이 로컬 client token 확보
2. 사용자가 6자리 PIN 입력
3. 앱이 POST /claimDevice 호출(token + code)
4. 성공 시 deviceId, firestoreDocPath(sensors/{id}) 저장
5. Firestore 스트림을 해당 경로로 재연결
6. Push service에 sensor id 반영

보조 흐름:

- mDNS 스캔으로 서버 PIN 클레임 없이 sensors/{id} 직접 바인딩 가능
- 로컬 빠른 연결을 위한 의도적 경로

### 3.6 알림

Push 서비스: [Indoorairqualityappv2-main/src/flutter/lib/services/push_notification_service_v2.dart](Indoorairqualityappv2-main/src/flutter/lib/services/push_notification_service_v2.dart)

- POST /registerDevice로 토큰과 기기 메타 등록
- POST /updatePreferences로 알림 선호도 동기화

앱 내 로컬 알림:

- [Indoorairqualityappv2-main/src/flutter/lib/services/alert_notification_service.dart](Indoorairqualityappv2-main/src/flutter/lib/services/alert_notification_service.dart)
- [Indoorairqualityappv2-main/src/flutter/lib/services/alert_notification_engine.dart](Indoorairqualityappv2-main/src/flutter/lib/services/alert_notification_engine.dart)

동작 특성:

- quiet hours, snooze, muted types 반영
- 동일 타입 반복 알림 dedupe 윈도우 적용

### 3.7 건강지표 계산 및 외부 API 연동

건강 엔진:

- [Indoorairqualityappv2-main/src/flutter/lib/utils/nodered_health_engine.dart](Indoorairqualityappv2-main/src/flutter/lib/utils/nodered_health_engine.dart)

외부 API 서비스:

- [Indoorairqualityappv2-main/src/flutter/lib/services/external_api_service.dart](Indoorairqualityappv2-main/src/flutter/lib/services/external_api_service.dart)

계산 및 수집 항목:

- 파생 지표: AQI, 이슬점, 불쾌지수
- 어린이 모드: 집중, 호흡기, 감염, 곰팡이
- 고령자 모드: 심혈관, 수면, PM 노출, 환기 상태
- 정화 모드: CADR/환기/IPI 관련 지표
- 외부 비교 데이터:
  - WAQI(PM)
  - KMA(온도/습도/풍속)
  - ipinfo 위치 기반 초기 좌표

### 3.8 로컬 센서 제어 경로

서비스:

- 로컬 스냅샷 보조: [Indoorairqualityappv2-main/src/flutter/lib/services/airgradient_local_api.dart](Indoorairqualityappv2-main/src/flutter/lib/services/airgradient_local_api.dart)
- LED/CO2 제어: [Indoorairqualityappv2-main/src/flutter/lib/services/led_control_service.dart](Indoorairqualityappv2-main/src/flutter/lib/services/led_control_service.dart)

로컬 제어 엔드포인트 패턴:

- PUT/GET http://<sensor_ip>/config
- LED 모드/밝기 제어
- 수동 CO2 교정 요청

### 3.9 최근 차트 안정화 반영

개요 탭 미니 스파크라인에 다음 보호 로직 반영:

- 비정상값(비유한값) 포인트 필터링
- 유효 포인트 2개 미만이면 렌더 중단
- timestamp 기준 정렬
- 차트 영역 clip 적용

파일: [Indoorairqualityappv2-main/src/flutter/lib/widgets/air_quality_overview.dart](Indoorairqualityappv2-main/src/flutter/lib/widgets/air_quality_overview.dart)

## 4) 백엔드와 클라우드 통신

주요 함수 파일: [iaq-v2-firebase/functions/index.js](iaq-v2-firebase/functions/index.js)

### 4.1 공개 Cloud Functions

1. ingest
2. registerDevice
3. claimDevice
4. updatePreferences
5. generateDeviceCode
6. relay
7. scheduledDataCleanup

### 4.2 엔드포인트 계약(활성 기준)

앱 기본 base URL:

- https://us-central1-capstone-air-quality-yu25.cloudfunctions.net

핵심 엔드포인트:

1. POST /ingest
   - 인증: X-API-Key가 INGEST_API_KEY와 일치해야 함
   - 입력: serial, pm25, co2, tvoc, nox, temp, humidity, firmware, timestamp, ip
   - 저장:
     - sensors/{serial} latest
     - sensors/{serial}/history
   - 알림 생성 및 푸시 발송 로직 연동

2. POST /registerDevice
   - 환경설정에 따라 API 키 검증(선택)
   - devices 컬렉션에 token, fcmToken, sensorId, 알림 선호도 저장

3. POST /claimDevice
   - 환경설정에 따라 API 키 검증(선택)
   - device_codes의 6자리 코드를 소비해 token을 sensorId와 바인딩

4. POST /updatePreferences
   - 환경설정에 따라 API 키 검증(선택)
   - quiet hours, muted types, snooze, timezone 등 갱신

5. POST /generateDeviceCode
   - 환경설정에 따라 API 키 검증(선택)
   - TTL이 있는 6자리 코드 생성

6. POST /relay (req.path 분기)
   - /api/relay/register-server
   - /api/relay/register-server-path/{serverId}/{serverUrlB64}
   - /api/relay/bind-token
   - /api/relay/resolve-server
   - /api/relay/sensor

### 4.3 relay sensor 경로 동작

/api/relay/sensor 처리:

- MAC 주소를 소문자 compact hex로 정규화
- 저장:
  - sensors/{mac}/latest
  - sensors/{mac}/history
  - sensors/{mac}/series
- requestCode=true이면:
  - 사용 가능한 미클레임 코드 재사용 우선
  - 없으면 신규 코드 발급
  - code, alreadyClaimed, expiresAt 반환

### 4.4 알림 엔진과 Push 디스패치

알림 엔진: [iaq-v2-firebase/functions/alertEngine.js](iaq-v2-firebase/functions/alertEngine.js)

워처 타입:

- pm25_high, co2_high, tvoc_high, nox_high
- respiratory_low, infection_risk, focus_poor
- cardio_low, sleep_quality_low, mold_risk
- apparent temperature 정시 알림(아침, 저녁)

런타임 특성:

- 임계치 + 최소 지속시간 + 히스테리시스 반영
- 중복 억제 윈도우로 알림 스팸 방지
- quiet hours 맥락에서 권장 액션 조정
- alerts 컬렉션에 이벤트 저장
- 디바이스 매핑 토큰으로 FCM 전송

### 4.5 정기 데이터 정리

함수: scheduledDataCleanup

- 리전: asia-northeast3
- 스케줄: Asia/Seoul 기준 매일 자정
- sensors/{id}/history, sensors/{id}/series의 오래된 문서 삭제(현재 30일 보관)

## 5) Firestore 데이터 모델(활성 프로젝트)

규칙 파일: [iaq-v2-firebase/firestore.rules](iaq-v2-firebase/firestore.rules)

주요 컬렉션:

1. sensors/{sensorId}
   - latest, lastSeen, serial, firmware, ip 등
2. sensors/{sensorId}/history
3. sensors/{sensorId}/series
4. devices/{token}
5. device_codes/{code}
6. alerts/{alertId}
7. relay_servers/{serverId}
8. relay_tokens/{token}

ID 정규화 메모:

- ingest는 들어온 serial 문자열을 그대로 사용하는 경향이 있음
- relay sensor는 compact 소문자 MAC으로 정규화
- 백엔드에 후보 ID 매칭 로직이 있어 클레임 및 조회 시 형식 차이를 흡수함

## 6) AirGradient 펌웨어 연동

### 6.1 워크스페이스 ESPHome 트랙

파일:

- [iaq-v2-firebase/firmware/ag-one-capstone.yaml](iaq-v2-firebase/firmware/ag-one-capstone.yaml)
- [iaq-v2-firebase/firmware/airgradient_api_esp32-c3.yaml](iaq-v2-firebase/firmware/airgradient_api_esp32-c3.yaml)
- [iaq-v2-firebase/firmware/display_local.yaml](iaq-v2-firebase/firmware/display_local.yaml)

현재 동작:

- 5초 주기로 /ingest 업로드
- WiFi 연결 직후 /generateDeviceCode 1회 호출
- OLED 페어링 페이지에 PIN 약 120초 표시

### 6.2 Arduino 펌웨어 트랙(이번 세션 반영)

이번 세션에서는 워크스페이스 외부 Arduino 브랜치에도 최신 반영이 있었음:

- /api/relay/sensor requestCode 응답 파싱 추가
- OLED 대시보드 내부 작은 PIN 오버레이 표시 추가
- PIN 표시 시간 약 60초 설정
- relay 엔드포인트가 code payload를 반환하도록 백엔드 수정 및 배포

운영상 의미:

- 현재 펌웨어 연동 방식이 2개 병행(ESPHome ingest+generateCode, Arduino relay requestCode)
- 실제 배포 전, 기기에 올라간 펌웨어 방식과 백엔드 기대 동작을 반드시 일치시켜야 함

## 7) 버전 스냅샷과 정합성 메모

- Flutter pubspec 버전: 2.0.0+1
  - 근거: [Indoorairqualityappv2-main/src/flutter/pubspec.yaml](Indoorairqualityappv2-main/src/flutter/pubspec.yaml)
- 설정 화면 표기 버전: 1.0.0
  - 근거: [Indoorairqualityappv2-main/src/flutter/lib/widgets/settings_view.dart](Indoorairqualityappv2-main/src/flutter/lib/widgets/settings_view.dart)
- Cloud Functions 런타임(활성 백엔드): Node.js 20
  - 근거: [iaq-v2-firebase/functions/package.json](iaq-v2-firebase/functions/package.json)

## 8) 알려진 리스크와 기술 부채

1. 병행 코드베이스 드리프트 위험
   - 활성 백엔드: iaq-v2-firebase
   - 병행 백엔드: Indoorairqualityappv2-main/functions

2. Firestore rules 이원화
   - 활성 프로젝트는 클라이언트 write 차단 중심
   - 병행 트리는 sensors write가 상대적으로 느슨함

3. 키 및 시크릿 관리 이슈
   - 앱과 펌웨어에 기본 키 placeholder 또는 기본값 존재
   - 외부 API 토큰이 클라이언트 코드에 존재

4. mDNS 빠른 연결은 PIN 클레임보다 소유권 증명이 약함

5. 기기 데이터 초기화는 history와 series 전체 삭제를 수행함

6. 위치 비교는 IP 기반 위치를 사용하므로 실제 센서 위치와 다를 수 있음

## 9) 통합 정리 권장안

1. 백엔드 기준 트리를 하나로 확정하고 나머지는 보관 또는 아카이브
2. 펌웨어 클레임 전략을 단일화(ingest+generateCode 또는 relay requestCode)
3. 키와 토큰을 런타임 시크릿 관리로 이관
4. Firestore rules를 사용자 및 소유권 기반으로 강화
5. 앱 표시 버전을 빌드 버전과 자동 동기화
6. 배포 명령과 환경 변수 매트릭스를 RUNBOOK 문서로 분리
