# 스마트플러그 진행 로그 및 요구사항 추적

기준 시각: 2026-04-06 (업데이트)

## 1) 사용자 요구사항 추적표

| ID | 사용자 요구사항 | 상태 | 근거 |
|---|---|---|---|
| R1 | HTTP만으로 원격/다중플러그 운영이 어려운지 검토 | 완료 | 제어 평면을 Firebase+Firestore로 분리, 통신은 MQTT 권장으로 결정 |
| R2 | 무료 플러그인/시스템만 사용 | 완료 | Firebase(기존), MQTT Free Tier(HiveMQ/EMQX), 로컬/무료 컨테이너 워커 기준으로 설계 |
| R3 | 계획만이 아니라 실제 구현까지 수행 | 완료 | Functions API + Flutter 서비스 + MQTT 워커까지 코드 반영 |
| R4 | 요청/응답 증적(로그) 남길 것 | 완료 | plug_command_requests / plug_command_queue / plug_command_responses / plug_state_history 적용 |
| R5 | 원격성 + 다중플러그 확장성 확보 | 완료 | 실브로커 + 워커 + 시뮬레이터로 command->ACK->state 루프 E2E 검증 완료 |
| R6 | auto/manual 정책 반영 | 완료 | commandPlug + MQTT 워커 양쪽에서 manualOverrideUntil active 시 auto 명령 억제 강제 |
| R7 | 다음 절차 전에 계획/현재 진행사항 기록 | 완료 | 본 문서와 실행 계획 문서에 동기화 반영 |
| R8 | 자동제어 기준을 메인화면 AQI로 고정 | 완료 | ingest AQI 자동제어 + 앱 임계값 UI + decision/request/response 추적 조회까지 반영 |

## 2) 현재까지 완료된 구현

- Backend Functions (완료)
  - registerPlug
  - upsertPlugProfile
  - commandPlug
  - ackPlugCommand
  - updatePlugState
  - getPlug
  - listPlugs
  - getPlugControlTrace
  - ingest -> AQI 자동제어 dispatchAutoControlForSnapshot 연결
  - plug_control_decisions 로그 컬렉션 추가(자동 판단 증적)
- Flutter 서비스 (완료)
  - remote-first + local HTTP fallback 구조
  - command/get/list/register 클라이언트 함수 추가
  - getControlTrace(제어 추적 조회) 추가
- Flutter 설정 UI (완료)
  - 스마트플러그 섹션 추가 (등록, 목록 조회, 선택, 상태 동기화, ON/OFF)
  - 마지막 plugId/topic/name/ip 로컬 저장 및 재사용
  - AQI ON/OFF 임계값 저장 + 자동/수동 모드 편집
  - 최근 제어 로그 패널(결정/요청/응답) 추가
- MQTT Worker (완료)
  - queue polling
  - cmnd/<topic>/Power publish
  - stat/+/RESULT, stat/+/POWER ACK 처리
  - timeout 확정 처리
  - tele/+/LWT online 상태 반영
  - controlEnabled=false 차단 처리
  - manualOverrideUntil 활성 구간 auto 명령 억제 처리
- Functions commandPlug (완료)
  - manualOverrideUntil 활성 구간의 auto 명령을 pending 큐로 보내지 않고 suppressed 상태로 기록
  - auto 요청 시 활성 manual override를 덮어쓰지 않도록 보존
- 문서화 (완료)
  - SMART_PLUG_FREE_EXECUTION_PLAN_KR.md
  - 본 진행 로그
- 검증 자동화 (완료)
  - iaq-v2-firebase/functions/scripts/smart_plug_e2e_smoke.ps1 추가
  - `-RequireWorkerAck` 모드로 워커 ACK(요청 ID 매칭 + actualState 반영)까지 검증 가능
  - iaq-v2-firebase/functions/scripts/tasmota_simulator.js 추가 (cmnd 수신 -> stat 응답)

## 3) 잔여 항목(선택)

- 실디바이스(Tasmota 실제 장비) 1회 검증
  - 현장 장비 접속 권한이 필요하여 원격 자동화 범위 밖(선택 검증 항목)
- 런타임 E2E(ingest -> AQI 자동결정 -> 워커 ACK) 1회 캡처 검증
  - 완료 (2026-04-06)

## 4) 다음 절차(선택)

1. 실디바이스 확인
  - 실제 Tasmota 플러그 1대로 command -> ACK -> 상태 반영 재검증
  - 토픽 충돌 없는 전용 네임스페이스 사용
2. 운영 점검
  - timeout 빈도, queue 적체, 로그 정리 주기 확인

## 5) 최근 검증 결과 (2026-04-05)

- Functions 배포 완료
  - registerPlug, upsertPlugProfile, commandPlug, ackPlugCommand, updatePlugState, getPlug, listPlugs 생성 확인
- API 스모크 테스트 통과
  - 스크립트: iaq-v2-firebase/functions/scripts/smart_plug_e2e_smoke.ps1
  - 결과: manual 명령 후 auto 명령이 suppressed_manual_override로 차단됨
  - getPlug 응답에서 autoPaused=true 확인

- 실브로커 MQTT 루프 스모크 통과 (워커 실가동)
  - 브로커: `mqtt://broker.hivemq.com:1883`
  - 워커: `npm run worker:plug` (서비스 계정 자격증명 포함)
  - 시뮬레이터: `npm run sim:tasmota`
  - 결과: worker dispatch/ack 로그 확인, `workerAck=True`, `actualState=ON`, `lastAckRequest`가 manual requestId와 일치

주의:
- 현재 E2E는 시뮬레이터 기준으로 검증 완료됨. 실제 물리 플러그 1회 실검증만 남음.

## 7) 2026-04-06 추가 반영

- 코드 반영
  - 파일: iaq-v2-firebase/functions/index.js
  - 내용:
    - PM2.5 -> US AQI 계산 함수 추가
    - sensor ingest 시 AQI 기준 자동제어 디스패치 추가
    - auto 명령 큐잉 결과를 plug_control_decisions에 기록
    - manual override 활성 시 auto suppressed 정책 유지
  - 파일: Indoorairqualityappv2-main/src/flutter/lib/services/tasmota_plug_service.dart
  - 내용:
    - upsertAqiProfile 추가
    - registerPlug에 controlEnabled 옵션 반영
  - 파일: Indoorairqualityappv2-main/src/flutter/lib/widgets/settings_view.dart
  - 내용:
    - 자동 제어 모드/활성화 스위치 추가
    - AQI ON/OFF 임계값 입력 필드 추가
    - AQI 정책 저장 버튼 추가(프로필 저장 + 플러그 메타 갱신)
    - 최근 제어 로그 패널 추가(결정/요청/응답 시계열 표시)
  - 파일: iaq-v2-firebase/functions/index.js
  - 내용:
    - getPlugControlTrace API 추가
    - plug_control_decisions + plug_command_requests + plug_command_responses 조인 조회 지원
  - 파일: Indoorairqualityappv2-main/src/flutter/lib/services/tasmota_plug_service.dart
  - 내용:
    - getControlTrace API 클라이언트 추가
  - 파일: iaq-v2-firebase/functions/scripts/smart_plug_e2e_smoke.ps1
  - 내용:
    - getPlugControlTrace 검증 단계 추가
    - `-SkipTraceCheck` 스위치 추가
- 점검
  - index.js 정적 오류 체크: 문제 없음
  - settings_view.dart, tasmota_plug_service.dart 정적 오류 체크: 문제 없음

## 8) 2026-04-06 배포/실행 검증 추가

- 배포
  - `firebase deploy --only functions:getPlugControlTrace` 실행
  - 결과: 생성 성공, URL 발급 확인
- 실행 검증
  - 스크립트: `iaq-v2-firebase/functions/scripts/smart_plug_e2e_smoke.ps1`
  - 1차: `getPlugControlTrace` 404 (미배포 상태 확인)
  - 2차(배포 후): 통과
    - `[PASS] auto command suppressed by manual override policy`
    - `[PASS] getPlugControlTrace returned trace rows and includes manual requestId`
    - 요약: `traceCount=2`, `actualState=ON`, `lastAckRequest`와 manual requestId 일치

## 9) 2026-04-06 비용 절감 가드 추가

- 파일: `iaq-v2-firebase/functions/index.js`
  - 내용:
    - ingest 스로틀(`INGEST_MIN_INTERVAL_SECONDS`) 추가
    - sensor history/relay series/relay history/plug decision/plug state history 쓰기 kill-switch 추가
    - cleanup 보관기간/삭제량 상한 환경변수화
    - cleanup에 collectionGroup 우선 경로 + fallback 경로 추가
- 파일: `iaq-v2-firebase/functions/.env.cost_emergency.example`
  - 내용:
    - 긴급 Firestore 절감 설정 템플릿 추가
- 점검:
  - index.js 정적 오류 체크 통과

## 10) 2026-04-06 TTL/배치 안정화 추가

- 파일: `iaq-v2-firebase/functions/index.js`
  - 내용:
    - 고빈도 로그/히스토리 문서에 `expireAt` 자동 기록(`withExpireAt`) 추가
    - cleanup 삭제 배치 상한을 500으로 상향
    - TTL 활성화 후 중복 삭제를 피하기 위한 cleanup 스킵 플래그 추가
      - `TTL_SENSOR_COLLECTIONS_ENABLED`
      - `TTL_PLUG_LOG_COLLECTIONS_ENABLED`
- 파일: `iaq-v2-firebase/functions/plug_mqtt_worker.js`
  - 내용:
    - worker가 마감하는 request/queue/response 문서에도 `expireAt` 보강
- 파일: `Indoorairqualityappv2-main/src/flutter/lib/services/firestore_snapshot_service.dart`
  - 내용:
    - `clearDeviceData`를 500개 청크 배치 삭제로 변경(대량 문서에서도 안정 동작)
- 파일: `iaq-v2-firebase/functions/.env`, `iaq-v2-firebase/functions/.env.cost_emergency.example`
  - 내용:
    - TTL 필드 기록 및 cleanup 스킵 토글 환경변수 추가

## 11) 2026-04-06 TTL 실활성화 + 무제약 절감 모드 전환

- Firestore TTL 활성화 완료(`expireAt`, state=ACTIVE)
  - `history`, `series`, `plug_command_requests`, `plug_command_queue`, `plug_command_responses`, `plug_state_history`, `plug_control_decisions`
- 운영 환경값 전환
  - 쓰기/로그 비활성화 토글 전부 `false` (기능 제약 없음)
  - `INGEST_MIN_INTERVAL_SECONDS=0`
  - `SENSOR_HISTORY_RETENTION_DAYS=30`, `PLUG_LOG_RETENTION_DAYS=90` (기존 기본 유지)
  - `TTL_SENSOR_COLLECTIONS_ENABLED=true`, `TTL_PLUG_LOG_COLLECTIONS_ENABLED=true`
- 배포
  - `commandPlug`, `ackPlugCommand`, `updatePlugState`, `ingest`, `relay`, `scheduledDataCleanup`
- 재검증
  - smart plug E2E smoke 통과

## 12) 2026-04-06 스마트 플러그 완료 검증 (재실행)

- 실브로커 워커 ACK 강제 스모크
  - 실행:
    - `smart_plug_e2e_smoke.ps1 -RequireWorkerAck -AckTimeoutSeconds 45`
  - 결과:
    - `workerAck=True`
    - `actualState=ON`
    - `lastAckRequest`와 manual requestId 일치
- 런타임 ingest 자동제어 증적
  - 절차:
    - `upsertPlugProfile(aqiOn=80, aqiOff=60)`
    - `registerPlug(mode=auto, controlEnabled=true)`
    - `ingest(pm25=95)` 호출
    - `getPlugControlTrace` 조회
  - 결과:
    - `ingestOk=True`
    - 최신 trace의 `request.status=acknowledged`, `response.status=acknowledged`
    - 워커 로그에서 dispatch/ack(latency 약 297ms) 확인

- 정리
  - 백엔드/워커/시뮬레이터/앱 추적 API 기준으로 스마트 플러그 루프는 완료 상태

## 13) 2026-04-06 실디바이스 검증 시도 결과

- 대상 토픽: `tasmota_604954`
- MQTT 프로브 결과: `tele/tasmota_604954/LWT => Offline`
- 워커 ACK 강제 스모크 결과:
  - request dispatch는 성공
  - 실디바이스 응답 미수신으로 `timeout` 발생
  - 스모크 실패 메시지: `Worker ACK verification failed ... actualState=UNKNOWN`
- 결론:
  - 현재 시점에서 실디바이스가 브로커에 온라인 상태가 아니어서 물리 ACK 검증은 보류
  - 장비 온라인 복구 후 동일 명령으로 즉시 재검증 가능

## 6) 리스크 및 제약

- 로컬 워커 실행 시 `GOOGLE_APPLICATION_CREDENTIALS` 미설정이면 Firestore 접근 실패
- 퍼블릭 브로커 사용 시 토픽 네임스페이스 격리 필요
- 무료 티어 제한으로 로그 보관 기간/정리 정책 유지 필요

## 14) 통합 기록 문서

- 전체 구현/검증/장애/판정 통합 문서:
  - `SMART_PLUG_FULL_RECORD_20260406_KR.md`
