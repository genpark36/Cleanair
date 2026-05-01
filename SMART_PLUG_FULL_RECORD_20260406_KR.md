# 스마트 플러그 전체 기록 (2026-04-06)

## 1) 문서 목적
- 이번 캡스톤 스마트 플러그 기능 구현/검증/장애 이슈/최종 판단을 한 문서에 통합 기록한다.
- 보고서, 발표, 인수인계 시 근거 자료로 사용한다.

## 2) 요구사항 원본 정리
- 자동 제어
  - 통합 공기질 지수(US AQI 환산 기반) 임계값 초과 시 자동 ON
  - 임계값 이하 회복 시 자동 OFF
  - 히스테리시스 적용
  - 제어 이력 로깅
- 수동 제어
  - 대시보드 UI에서 ON/OFF 직접 제어
  - 자동/수동 전환 지원
  - 수동 제어 시 자동 제어 일시 중지
  - 현재 상태 표시
- 통신
  - MQTT 우선, HTTP 보조 경로
  - 원격 제어 가능 구조(거리 무관)
- 필수 감사 로그
  - 제어 요청(request)과 응답(response) 모두 저장
- 확장성
  - 다중 스마트 플러그 지원
  - 임계값/히스테리시스 UI 조절

## 3) 구현 상태 결론
- 소프트웨어 기능 구현: 완료
- 서버/앱/워커 기반 E2E(시뮬레이터+실브로커): 완료
- 실물 플러그 1대 최종 검증: 장비 불량으로 보류

## 4) 주요 구현 파일 및 역할
- iaq-v2-firebase/functions/index.js
  - registerPlug, upsertPlugProfile, commandPlug, ackPlugCommand, updatePlugState, getPlug, listPlugs, getPlugControlTrace
  - ingest 경로에서 AQI 기반 자동 제어 디스패치
  - manual override 활성 시 auto 명령 suppressed
  - request/response/decision 저장
- iaq-v2-firebase/functions/plug_mqtt_worker.js
  - queue pending 요청 소비
  - cmnd/<topic>/Power MQTT publish
  - stat/<topic>/POWER, RESULT 수신 시 acknowledged 마감
  - timeout/실패 상태 기록
  - tele/<topic>/LWT로 온라인 상태 반영
- Indoorairqualityappv2-main/src/flutter/lib/services/tasmota_plug_service.dart
  - 로컬 HTTP 제어(local-first) + 서버 commandPlug 경로
  - upsertAqiProfile / getControlTrace 클라이언트
- Indoorairqualityappv2-main/src/flutter/lib/widgets/settings_view.dart
  - 자동/수동 전환, 제어 활성화 스위치
  - AQI ON/OFF 임계값 입력 및 저장
  - 최근 제어 로그(trace) 표시
- iaq-v2-firebase/functions/scripts/smart_plug_e2e_smoke.ps1
  - 정책/워커 ACK/trace 통합 스모크
- iaq-v2-firebase/functions/scripts/tasmota_simulator.js
  - Tasmota MQTT 응답 시뮬레이터
- iaq-v2-firebase/functions/scripts/mqtt_topic_probe.js
  - 토픽 LWT/상태 메시지 확인

## 5) 검증 결과 요약
- ACK 강제 스모크(RequireWorkerAck) 통과
  - workerAck=True
  - actualState=ON
  - lastAckRequest와 manual requestId 일치
- ingest 기반 자동제어 증적 확보
  - ingestOk=True
  - trace에서 request.status=acknowledged, response.status=acknowledged
  - worker dispatch/ack 로그 확인
- getPlugControlTrace에서 decision/request/response 체인 확인

## 6) 실물 플러그 장애 기록
- 대상: tasmota_604954
- 관측
  - MQTT probe에서 tele/tasmota_604954/LWT => Offline
  - 워커 dispatch 이후 timeout 발생
  - 이후 장비 LED 무반응(콘센트 연결 상태에서도 무반응)
- 해석
  - 현재 장비는 통신 설정 문제가 아닌 하드웨어/저장영역 이상 가능성이 큼
  - 실물 장비 검증은 해당 장비 상태로는 진행 불가

## 7) 공식 문서 해석 정리 (오해 방지)
- ".local 도메인 사용 불가"는 mDNS 제한 의미
- 일반 도메인(host) 사용 자체가 금지라는 뜻이 아님
- MQTT가 로컬에서만 동작한다는 뜻이 아님
- 단, 비암호화 MQTT(1883)는 보안상 로컬 LAN 사용 권고
- 원격 운영은 TLS(예: 8883) 또는 VPN 등 보호 구성 권장

## 8) 안전 운영 원칙 (사고 재발 방지)
- 사용자 명시 승인 없이는 장비 쓰기 작업 금지
  - 재플래시, 공장초기화, 템플릿 변경, 포트 작업 금지
- 코드/서버 검증과 장비 작업을 분리
- 실험용 토픽 네임스페이스 분리
- 백업/복구 경로 없는 상태에서 장비 작업 금지

## 9) 현재 최종 판정
- "스마트 플러그 제어 기능 구현 가능 여부": 가능(완료)
- "원격 제어 가능 여부": 가능(장비가 정상이고 온라인이면 가능)
- "현재 그 실물 플러그 원격 제어 가능 여부": 불가(장비 불량/오프라인)

## 10) 2주 보류 기간 운영 방안
- 기능 완료 상태로 개발 마감 처리
- 실물 검증 항목만 "액추에이터 교체 후 재검증"으로 분리
- 데모/리허설은 시뮬레이터+실브로커 로그 근거로 진행

## 11) 교체 장비 도착 후 즉시 재검증 체크리스트
1. MQTT 설정 확인 (Host/Port/Topic/Client 고유값)
2. LWT Online 확인
3. manual ON/OFF 1회 ACK 확인
4. auto ON/OFF(임계값/히스테리시스) 1회 확인
5. getPlugControlTrace에서 request/response 저장 확인

## 12) 보고서용 한 줄 결론
- 시스템 기능은 구현 완료이며, 실물 액추에이터 1대 불량으로 해당 장비 최종 검증만 교체 후 재수행 예정이다.
