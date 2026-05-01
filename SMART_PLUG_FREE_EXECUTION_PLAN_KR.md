# 스마트플러그 원격/다중제어 무료 스택 실행 계획

## 1) 핵심 결론
- 플러그에 앱이 직접 HTTP로 붙는 방식은 원격성과 다중플러그 확장성이 약합니다.
- 무료 조건에서도, 제어 평면은 Firebase Functions + Firestore로 두고 플러그 통신은 MQTT(권장) 또는 로컬 릴레이 HTTP(대체)로 구성하면 충분히 구현 가능합니다.
- 요청/응답 증적은 Firestore의 요청 로그 + 응답 로그를 분리 저장해야 신뢰성이 높습니다.

## 2) 이번에 실제 반영한 코드
- Firebase Functions API 추가: iaq-v2-firebase/functions/index.js
- Flutter 플러그 서비스 리팩터: Indoorairqualityappv2-main/src/flutter/lib/services/tasmota_plug_service.dart
- MQTT 워커 추가(큐 소비 + publish + ACK/timeout 반영): iaq-v2-firebase/functions/plug_mqtt_worker.js
- Settings 플러그 제어 UI 연결: Indoorairqualityappv2-main/src/flutter/lib/widgets/settings_view.dart

## 진행 로그
- 요구사항/진행상태 추적: SMART_PLUG_PROGRESS_LOG_KR.md

## 3) 추가된 백엔드 API
- registerPlug
  - 용도: 플러그 메타데이터 등록(주 통신, 토픽, 프로필 등)
- upsertPlugProfile
  - 용도: 임계값/히스테리시스/제약 프로필 저장
- commandPlug
  - 용도: 수동/자동 제어 명령 큐잉 + 요청 로그 저장
- ackPlugCommand
  - 용도: 워커(또는 릴레이)에서 응답 ACK 기록 + 응답 로그 저장
- updatePlugState
  - 용도: 플러그 최신 상태/온라인 상태 갱신 + 상태 히스토리 저장
- getPlug
  - 용도: 단일 플러그 상태 조회
- listPlugs
  - 용도: 다중 플러그 목록 조회

## 4) 로그/증적 저장 구조
- plug_command_requests
  - 누가, 어떤 모드(auto/manual)로, 어떤 명령을 보냈는지
- plug_command_queue
  - 워커가 처리할 큐 상태
- plug_command_responses
  - 실제 ACK/실패/타임아웃 응답 기록
- plug_state_history
  - 상태 변화 이력

## 5) 수동 오버라이드 정책
- mode=manual로 commandPlug 호출 시 manualOverrideUntil을 자동 계산해 저장합니다.
- commandPlug는 manualOverrideUntil 활성 구간에서 auto 명령을 pending 큐로 넣지 않고 suppressed 상태로 기록합니다.
- MQTT 워커도 dispatch 직전에 manualOverrideUntil을 재검증하여 auto 명령을 추가 억제합니다.

## 6) 무료 스택 권장안
- 필수(무료)
  - Firebase Functions + Firestore (현 프로젝트 기반)
  - Flutter 앱 (현 프로젝트)
- MQTT 브로커(무료 티어 중 택1)
  - HiveMQ Cloud Free
  - EMQX Cloud Free
- 워커 실행(무료)
  - 로컬 PC/라즈베리파이 상시 실행 Node.js 워커
  - 또는 무료 컨테이너 플랫폼의 free tier

## 7) HTTP 직접제어 vs MQTT
- HTTP 직접제어(앱 -> 플러그 IP)
  - 장점: 구현 간단
  - 단점: 외부망 원격 취약, NAT/공인IP 문제, 다중플러그 운영 불편
- MQTT(앱 -> 함수 -> 워커 -> 브로커 -> 플러그)
  - 장점: 원격성, 다중플러그, 요청/응답 추적, 자동제어 확장
  - 단점: 워커/브로커 운영 필요

## 8) 즉시 진행 순서
1. Functions 배포
   - firebase deploy --only functions
2. 앱에서 CLOUD_FUNCTION_BASE_URL, DEVICE_API_KEY 설정
3. 플러그 등록(registerPlug) 및 프로필 저장(upsertPlugProfile)
4. 앱에서 commandPlug 기반 ON/OFF 테스트
5. 워커 실행
   - cd iaq-v2-firebase/functions
   - npm run worker:plug
6. listPlugs/getPlug로 대시보드 다중 상태 확인

## 9) E2E 스모크 스크립트
- 파일
  - iaq-v2-firebase/functions/scripts/smart_plug_e2e_smoke.ps1
- 목적
  - registerPlug -> manual command -> auto suppressed 검증 -> getPlug/listPlugs까지 한 번에 확인
  - `-RequireWorkerAck` 사용 시 워커 ACK(requestId 매칭 + actualState 반영)까지 확인
- 실행 예시 (PowerShell)
  - $env:CLOUD_FUNCTION_BASE_URL="https://us-central1-<project>.cloudfunctions.net"
  - $env:DEVICE_API_KEY="<api-key>"
  - cd iaq-v2-firebase/functions/scripts
  - .\smart_plug_e2e_smoke.ps1 -PlugId "lab-plug-01" -SensorId "<sensor-id>" -TasmotaTopic "<topic>"
  - .\smart_plug_e2e_smoke.ps1 -PlugId "lab-plug-01" -SensorId "<sensor-id>" -TasmotaTopic "<topic>" -RequireWorkerAck -AckTimeoutSeconds 40

## 9-1) Tasmota 시뮬레이터
- 파일
  - iaq-v2-firebase/functions/scripts/tasmota_simulator.js
- npm 스크립트
  - `npm run sim:tasmota`
- 동작
  - `cmnd/<topic>/Power` 수신 시 `stat/<topic>/POWER`, `stat/<topic>/RESULT` publish
  - 워커 실가동 없이도 로컬에서 E2E 루프 테스트 가능

## 10) 워커 실행 환경 변수
- 필수
  - MQTT_URL
- 선택
  - GOOGLE_APPLICATION_CREDENTIALS (로컬 워커에서 Firestore 접근 시 사실상 필수)
  - MQTT_USERNAME
  - MQTT_PASSWORD
  - WORKER_ID (기본: plug-mqtt-worker)
  - WORKER_POLL_INTERVAL_MS (기본: 1500)
  - WORKER_COMMAND_TIMEOUT_MS (기본: 15000)
  - WORKER_PUBLISH_QOS (기본: 1)
  - WORKER_SUBSCRIBE_QOS (기본: 1)

## 11) 워커 구현 범위(현재)
- command queue polling 구현
- command -> MQTT publish(cmnd/topic/Power) 구현
- stat/topic/RESULT, stat/topic/POWER 수신 후 요청 매핑 구현
- ACK 성공 시 요청/큐/응답 로그 Firestore 반영 구현
- 응답 타임아웃 시 timeout 상태 확정 구현
- tele/topic/LWT 수신 시 플러그 online 상태 반영 구현
- controlEnabled=false 플러그 차단 처리 구현
- manualOverrideUntil 활성 구간 auto 명령 억제 처리 구현

## 12) 운영 비용/제약 메모
- 무료 티어는 호출량/문서저장량 제한이 있으므로 로그 정리 필수
- scheduledDataCleanup에 플러그 로그 정리(90일 보관)가 이미 반영됨

## 13) 최신 검증 상태
- 2026-04-05 기준 Functions 배포 완료 (신규 플러그 API 포함)
- `smart_plug_e2e_smoke.ps1` 실행으로 아래 확인 완료
  - registerPlug 호출 성공
  - manual 명령 접수 성공
  - manual override 활성 중 auto 명령이 `suppressed_manual_override`로 차단됨
  - getPlug에서 `autoPaused=true` 확인
- 실브로커 + 워커 + 시뮬레이터 실가동 검증 완료
  - 브로커: `mqtt://broker.hivemq.com:1883`
  - 워커 로그: dispatch/ack 확인
  - 스모크 결과: `workerAck=True`, `actualState=ON`, `lastAckRequest` 일치
- 2026-04-06 추가 배포/검증 완료
  - 배포: `functions:getPlugControlTrace` (us-central1)
  - 스모크 재실행: `smart_plug_e2e_smoke.ps1`
  - 결과: `getPlugControlTrace` 404 해소, `traceCount=2`, manual `requestId` 포함 확인

## 14) 2026-04-06 즉시 실행 로드맵 (AQI 기준 고정)

### 14-1) 제어 기준
- 자동제어의 1차 기준은 메인화면 AQI(US AQI)로 고정
- PM2.5로 AQI를 계산해 플러그 ON/OFF를 결정
- 기본값
  - `aqiOn = 120`
  - `aqiOff = 90`
  - `aqiHysteresis = 30`
  - `minCommandIntervalSeconds = 120`

### 14-2) 자동제어 규칙
- AQI >= aqiOn 이면 ON 후보
- AQI <= aqiOff 이면 OFF 후보
- aqiOff < AQI < aqiOn 구간은 상태 유지
- manualOverrideUntil 활성 중 auto 명령은 항상 suppressed

### 14-3) 오늘 반영 완료(코드)
- 파일: `iaq-v2-firebase/functions/index.js`
- ingest 경로에 AQI 자동제어 디스패처 연결
- `plug_control_decisions` 컬렉션에 자동판단 로그 기록 추가
- 기존 `plug_command_requests/queue/responses` 구조 유지
- `getPlugControlTrace` API 추가 (decision -> request -> response 조인 조회)
- 파일: `Indoorairqualityappv2-main/src/flutter/lib/services/tasmota_plug_service.dart`
  - AQI 프로필 저장 API(`upsertAqiProfile`) 추가
  - 플러그 등록 시 `controlEnabled` 옵션 반영
  - 제어 추적 조회 API(`getControlTrace`) 추가
- 파일: `Indoorairqualityappv2-main/src/flutter/lib/widgets/settings_view.dart`
  - 자동 제어 모드(AUTO/MANUAL) 토글 추가
  - 자동 제어 활성화(controlEnabled) 토글 추가
  - AQI ON/OFF 임계값 입력 UI 추가
  - "AQI 정책 저장" 버튼으로 프로필 저장 + 플러그 메타 동기화 연결
  - 최근 제어 로그 패널 추가 (결정/요청/응답 1화면 시계열 확인)

### 14-4) 지금부터 순차 실행(주차 구분 없이 즉시)
1. Backend 고정화 [완료]
  - 프로필 문서에서 AQI 임계값/히스테리시스 파라미터 확정
  - 동일 상태 반복 명령 억제와 최소 간격 검증
2. 앱 제어 UI 확장 [완료]
  - 자동/수동 전환 토글
  - AQI ON/OFF 임계값 편집
  - 수동 오버라이드 시간 선택
3. 증적 화면 [완료]
  - decision/request/response를 한 화면에서 시계열 조회
4. 실운영 루프 검증 [완료]
  - 실브로커 + 워커 + 시뮬레이터에서 원격 ON/OFF, suppress, ACK 재확인
  - ingest -> AQI 자동판단 -> request/response ACK 증적 캡처 완료
  - 실제 물리 플러그 검증은 현장 장비 접근 시 추가 수행(선택)

## 15) 워커 런타임 선택 (Cloud Run / AWS / Oracle)

### 15-1) 결론
- Cloud Run만 가능한 구조가 아님
- 현재 워커(Node.js)는 컨테이너 실행이 가능한 어디서든 동일 코드로 운영 가능

### 15-2) 선택지
1. GCP Cloud Run
  - 장점: Firebase/Firestore와 IAM 연결이 가장 간단
  - 추천 상황: 지금 프로젝트를 가장 빠르게 안정화할 때
2. AWS (ECS Fargate 또는 EC2)
  - 장점: 기존 AWS 인프라가 있으면 통합 유리
  - 주의: Firestore 접근용 서비스 계정 키/시크릿 관리 필요
3. Oracle Cloud Always Free VM
  - 장점: 상시 실행 저비용
  - 주의: VM 운영(재시작/로그/보안패치) 직접 관리 필요

### 15-3) 현재 권장
- 1차 완성은 Cloud Run으로 빠르게 마무리
- 이후 필요하면 동일 워커 이미지를 AWS/Oracle로 이관

## 16) 변경 반영 규칙 (문서-코드 동기화)
- 작업 사이클
  1) 계획 문서 업데이트
  2) 코드 반영
  3) 검증 실행
  4) 진행 로그 반영
- 변경점은 `SMART_PLUG_PROGRESS_LOG_KR.md`에 즉시 기록
- 정책 변경(임계값/히스테리시스/모드 우선순위)은 계획서와 코드 동시 수정

## 17) Firestore 비용 긴급 모드 (2026-04-06)

### 17-1) 목적
- 무료 할당량(읽기/쓰기/삭제) 급접근 시, 기능은 유지하면서 비핵심 로그 쓰기를 즉시 감산

### 17-2) 적용 가능한 환경 변수
- `INGEST_MIN_INTERVAL_SECONDS`
  - ingest 쓰기 최소 간격(센서별, 인스턴스 로컬 기준)
- `DISABLE_SENSOR_HISTORY_WRITES`
  - `sensors/{id}/history` 쓰기 중단
- `DISABLE_RELAY_SERIES_WRITES`
  - relay 경로의 `series` 쓰기 중단
- `DISABLE_RELAY_HISTORY_WRITES`
  - relay 경로의 `history` 쓰기 중단
- `DISABLE_PLUG_DECISION_LOG`
  - `plug_control_decisions` 쓰기 중단
- `DISABLE_PLUG_STATE_HISTORY_WRITES`
  - `plug_state_history` 쓰기 중단
- `SENSOR_HISTORY_RETENTION_DAYS`, `PLUG_LOG_RETENTION_DAYS`
  - 보관기간 단축
- `CLEANUP_MAX_DELETES_PER_RUN`
  - cleanup 1회 삭제량 상한

### 17-3) 템플릿
- `iaq-v2-firebase/functions/.env.cost_emergency.example`
  - 긴급 절감값 예시 제공

### 17-4) 주의
- `INGEST_MIN_INTERVAL_SECONDS`는 인스턴스 로컬 캐시 기반 스로틀이라 절대 보장은 아님
- history/decision 로그 비활성화 시 디버깅 가시성은 감소함

### 17-5) TTL 운용 가이드 (추가)
- 코드 측면
  - 고빈도 로그/히스토리 문서에 `expireAt` 필드 자동 기록
  - 설정: `ENABLE_EXPIREAT_TTL_WRITES=true`
- Firestore 콘솔 측면
  - TTL 정책에서 `expireAt` 필드를 대상 컬렉션/컬렉션그룹에 연결해야 자동 삭제가 동작함
  - 권장 대상: `history`, `series`, `plug_command_requests`, `plug_command_queue`, `plug_command_responses`, `plug_state_history`, `plug_control_decisions`
- 전환 순서
  1) 코드 배포(이미 `expireAt` 기록)
  2) 콘솔에서 TTL 정책 활성화
  3) `TTL_SENSOR_COLLECTIONS_ENABLED=true`, `TTL_PLUG_LOG_COLLECTIONS_ENABLED=true`로 전환
  4) 이후 스케줄 cleanup은 해당 그룹 스캔/삭제를 자동 스킵

### 17-6) Delete-Set 패턴 점검 결과
- 플러그/ingest 핵심 백엔드 경로에서 `delete -> set` 반복 패턴은 확인되지 않음
- 현재는 `set(..., { merge: true })` 기반 업서트가 중심
- 따라서 비용 최적화 우선순위는
  - 비핵심 write 감산
  - TTL 자동 만료
  - cleanup 배치 최적화(500 단위)
