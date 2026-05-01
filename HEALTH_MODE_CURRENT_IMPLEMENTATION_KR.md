# 현재 Flutter 앱 건강 모드 구현 상세 명세 (UI 개선 참고)

작성일: 2026-04-05
문서 목적: 현재 앱에 실제 구현된 건강 모드의 화면 구조, 계산 로직, 데이터 흐름, 주의 포인트를 코드 기준으로 공유한다.

## 0) 문서 통합 원칙 (2026-04-08)

- 건강 모드 관련 임계치/시나리오/판정 로직 변경은 이 문서 한 곳에서만 관리한다.
- HEALTH_MODE_COPYPASTE_TEXT_KR.txt, NODE_RED_COMPUTATION_LOGIC.md 등은 참고 자료로만 사용한다.
- 구현 기준 문서(Single Source of Truth)는 본 문서다.

### 최신 운영 규칙 (즉시 판정, 히스테리시스 없음)

- CADR 유효 k는 PM 축 기준으로 계산한다. (`kEffective = max(kPm25, 0)`)
- IPI는 CO2 축 기준으로 유지한다.
- 정상 평형(`equilibrium_clean`)은 아래 조건을 동시에 만족하면 즉시 판정한다.
  - CO2 <= 500 ppm
  - PM2.5 <= 5 ug/m3
  - TVOC <= 100 index
  - 최근 6샘플(약 30초) 기울기 중앙값 절대값이 임계치 이하
  - |dCO2/dt| <= 12 ppm/min
  - |dPM2.5/dt| <= 0.4 ug/m3/min
  - |dTVOC/dt| <= 18 index/min

## 1) 화면 구조

- 건강 모드는 홈 탭의 3번째 탭(라벨: 건강)에서 진입한다.
- 본문 컴포넌트는 HealthModeDashboard 단일 위젯이다.
- 상단 모드 셀렉터는 3개다.
  - 어린이
  - 고령자
  - 정화지표
- 기본 선택 모드는 어린이이다.
- 코어 측정값(pm25, co2, temperature, humidity) 중 필수값이 비어 있으면 데이터 없음 상태를 보여준다.

## 2) 데이터 파이프라인

1. FirestoreSnapshotService가 센서 문서 스냅샷을 구독한다.
2. 수신된 raw 값(pm25, co2, tvoc, temp, humidity)을 NodeRedHealthEngine.compute에 입력한다.
3. 엔진 결과를 health 구조(child, senior, purification, alerts, seasonalApparent 등)로 JSON에 합친다.
4. AirQualitySnapshot.fromJson이 health를 파싱해 모델 객체를 만든다.
5. AirQualityController가 latestSnapshot 및 childSnapshot, seniorSnapshot, purificationSnapshot, ipiSnapshot을 UI에 공급한다.

보조 데이터:
- ExternalApiService는 10분 주기로 WAQI/KMA를 조회한다.
- 외부 기상값(온도/습도/풍속)은 체감온도 계산에 사용된다.
- 외부 비교 통계(RMSE, MAPE, CV, R2)는 locationComparison에 반영된다.

## 3) 계산 엔진 핵심

### 3.1 공통/파생

- IAQI 계산 및 등급(primary/sub) 산출
- 이슬점(Dew Point), 불쾌지수(Discomfort Index) 계산
- 경보 메시지(alerts) 생성

### 3.2 어린이 모드

1) 집중환경(Focus)
- CO2 경계값: 700 / 1000 / 1500 ppm
- 구간별 레벨, 설명, 권장 행동 메시지 생성

2) 호흡기 건강(Respiratory)
- 온도/습도/TVOC 밴드 감점 합산(초기 100점)
- 최종 점수 0~100 클램프 후 레벨화

3) 면역/감염 위험(Infection)
- CO2 band + 습도 band의 combo 점수 맵 기반
- 위험도 점수와 레벨 산출

4) 곰팡이 위험(Mold)
- 습도 60% 초과 지속시간 추적
- 24시간 이상 고습, 70% 초과, 고습+PM 고농도 조건에서 단계 상승

### 3.3 고령자 모드

1) 심혈관 보호점수(Cardio)
- PM 고노출 구간 이력 기반
- highHours와 kAvg로 riskRaw 계산
- 점수 식: score = 100 * (1 - riskRaw / 8)

2) 심혈관 리스크(PM Exposure)
- PM2.5 구간 밴드 메시지(양호/주의/나쁨/매우 나쁨)

3) 쾌적 수면지수(Sleep)
- good CO2 ratio(70%) + good VOC ratio(30%) 가중
- 야간 회복력 해석 문구 포함

4) 환기 추정(Ventilation)
- k 기반 t50 분 환산값 제공

### 3.4 정화지표 모드

1) k 회귀(핵심)
- ln(C) 대 시간 OLS 기울기에서 k 산출
- 5분 슬라이딩 윈도우
- 최소 샘플 수 15
- PM 회귀는 maxVal < 0.99일 때 노이즈로 스킵

2) CADR 지표
- CADR 유효 k는 PM 축 기준 사용 (kEffective = max(kPm25, 0))
- PM/CO2 듀얼 k는 비교/설명용으로 병행 표시
- k 기준 등급: S(>=2.0), A(>=1.0), B(>=0.5), C(<0.5)
- mode/scenario 진단: purification, ventilation, combined, polluting, stagnant, equilibrium_clean
- equilibrium_clean은 CO2/PM/TVOC 절대값 + 최근 6샘플 기울기 조건으로 즉시 판정

3) IPI 지표
- CO2 기반 k에서 t90 계산
- IPI 점수 구간: k>=3.0(안심), 1.0~3.0(보통), 0.3~1.0(주의), <0.3(경고)

4) 환기 지표
- fallback 상태값과 시나리오 카드(듀얼 k 기반) 병행 지원

### 3.5 체감온도

- 여름(5~9월): Stull 습구온도 기반 체감
- 겨울(10~4월): 풍속 체감온도(조건 충족 시)
- 외부 KMA 데이터로 계산한 apparentTemp를 고령자 카드에서 표시

## 4) 탭별 카드 노출 순서

### 어린이
1. 호흡기 건강 지수
2. 면역/감염 위험
3. 집중환경 판단
4. 곰팡이 위험도

### 고령자
1. 심혈관 보호점수
2. 심혈관 리스크
3. 쾌적 수면지수
4. 실외 체감온도

### 정화지표
1. 정화속도 k(듀얼 또는 단일)
2. CADR-Index
3. IPI 위험지수
4. 환기 지표

## 5) 현재 확인된 UI/로직 주의 포인트

1) IPI 색상 매핑 누락 가능성
- 엔진은 최고 점수 4를 반환할 수 있음
- 대시보드 색상 함수는 3/2/1만 명시 처리
- 결과적으로 score=4가 기본색(회색)으로 표시될 가능성 존재

2) 환기 상태 문자열 불일치 가능성
- 엔진 status 값: 환기필요, 정화중
- fallback 카드 분기값: needs-ventilation, cleaning
- 문자열 표준화가 안 되어 있으면 fallback 카드에서 의도와 다른 색/아이콘이 나타날 수 있음

3) 안내 문서와 런타임 로직 드리프트 가능성
- HealthModeInfoPage는 정적 설명
- 계산 엔진 값/임계치가 바뀌면 문서와 실제가 어긋날 수 있음

4) 위험도 색상 분류 방식
- 일부 카드는 문자열 포함 여부로 색상을 판정
- 라벨 문구 변경/다국어 변경 시 색상 오분류 가능성 존재

## 6) UI 개편 시 우선 개선 후보

1. IPI 점수 4 색상/배지 명시 처리
2. 환기 status enum 단일화(엔진-UI 공통)
3. 정보 페이지 문구 자동 동기화 체계 또는 검증 체크리스트 추가
4. 위험도 표시를 문자열 매칭 대신 enum 기반으로 통일
5. R2 신뢰도 경고를 전 카드 공통 컴포넌트로 정리

## 7) 근거 코드 위치(핵심)

- Indoorairqualityappv2-main/src/flutter/lib/widgets/health_mode_dashboard.dart
- Indoorairqualityappv2-main/src/flutter/lib/utils/nodered_health_engine.dart
- Indoorairqualityappv2-main/src/flutter/lib/services/firestore_snapshot_service.dart
- Indoorairqualityappv2-main/src/flutter/lib/state/air_quality_controller.dart
- Indoorairqualityappv2-main/src/flutter/lib/models/air_quality_snapshot.dart
- Indoorairqualityappv2-main/src/flutter/lib/services/external_api_service.dart
- Indoorairqualityappv2-main/src/flutter/lib/utils/mock_data.dart
- Indoorairqualityappv2-main/src/flutter/lib/widgets/health_mode_info_page.dart

## 8) 오른쪽 비교 탭 UI 상세 명세 (실외 비교 전용)

비교 탭은 "실내 센서값"과 "실외 기준값(API/측정소)"을 나란히 보여주는 전용 화면이다.
오른쪽 끝 탭이며, 분석 목적은 "실내 측정이 외부 기준과 얼마나 벌어지는지"를 직관적으로 확인하는 데 있다.

### 8.1 탭 목적과 데이터 범위

- 핵심 목적: 실내 센서값 vs 실외 기준값 비교
- 비교 대상 지표: PM2.5, 온도, 습도
- 비교 제외 지표: CO2, TVOC, NOx (설명 카드에 명시)
- 출처 라벨:
  - PM2.5: 에어코리아
  - 온도/습도: 기상청

### 8.2 상태 전환(초기/로딩/정상)

1) 현재 측정 데이터 없음
- 조건: currentData == null
- 표시: 중앙 빈 화면
- 문구: "데이터 없음"

2) 현재 측정은 있으나 외부 비교 데이터 없음
- 조건: comparison == null 또는 비교 가능한 metric 리스트가 비어 있음
- 표시: 중앙 로딩 화면
- 제목: "외부 데이터 불러오는 중..."
- 안내문: "AQICN(PM2.5) 및 기상청(온도/습도) 데이터를 가져오고 있습니다. 잠시만 기다려주세요."
- 로더: 원형 프로그레스 인디케이터

3) 정상 비교 화면
- 조건: currentData 존재 + comparison 존재 + 비교 metric 1개 이상
- 레이아웃: 스크롤 단일 컬럼, 전체 패딩 16

### 8.3 정상 화면의 카드 배치 순서

위에서 아래 순서:

1. 측정소 정보 카드
2. 지표 비교 카드들 (PM2.5/온도/습도 중 존재하는 항목만)
3. 통계 설명 카드

간격 규칙:
- 측정소 카드 아래 16
- 지표 카드 사이 12
- 마지막 설명 카드 위 16

### 8.4 측정소 정보 카드 상세

- 카드 제목: "가장 가까운 측정소"
- 본문 1: 측정소명 (comparison.title, 없으면 "근처 측정소")
- 본문 2: 부제 (comparison.subtitle, 없으면 "위치 정보 없음")
- 업데이트 시각: comparison.timestamp가 있으면 HH:mm 형식으로 "업데이트 HH:mm" 노출
- 시각 요소: 위치 아이콘 + 스케줄 아이콘

### 8.5 지표 비교 카드 상세

지표 카드는 데이터가 있는 항목만 동적으로 생성된다.

- PM2.5가 있으면 PM2.5 카드 생성
- 온도가 있으면 온도 카드 생성
- 습도가 있으면 습도 카드 생성

카드 내부 구성(공통):

1) 헤더
- 지표 아이콘 + 지표명
- 출처 라벨: "출처: {source}"

2) 값 비교 박스 2개
- 좌: "센서 측정값"
- 우: "API ({source})"
- 값 형식: 소수 1자리 + 단위

3) 편차 라인
- 텍스트: "편차 ±값 단위"
- trend 아이콘/색상 규칙:
  - sensor - station > 0: 상승 아이콘, 빨강 계열
  - sensor - station < 0: 하강 아이콘, 파랑 계열
  - 같거나 계산 불가: 중립 아이콘, 회색 계열
- delta 문자열이 API에서 없으면 앱에서 직접 diff를 계산해 표시

4) 통계 블록 (stats 있을 때만)
- 1행: 오차율(MAPE), 일치도(R2)
- 2행: RMSE, 변동(CV)
- 표본 수: n > 0일 때 "표본 수: n개"

통계 강조 색상 규칙:
- MAPE < 10%: 초록 강조
- R2 > 0.8: 초록 강조
- 그 외는 일반 밝기 텍스트

### 8.6 통계 설명 카드(하단 고정 성격)

카드 제목: "통계 설명"

섹션 1: 지표 정의
- R2(결정계수): 측정소 데이터와 현재 측정값의 상관관계(0~1)
- RMSE: 평균 제곱근 오차
- 상대오차: 측정소 대비 오차 비율

섹션 2: R2 신뢰도 범례
- 0.9 이상: 매우 높음
- 0.8~0.9: 높음
- 0.7~0.8: 보통
- 0.6~0.7: 낮음
- 0.6 미만: 매우 낮음

섹션 3: 데이터 출처
- PM2.5: 에어코리아 실시간 측정망
- 온도/습도: 기상청 종관기상관측(ASOS)
- CO2/TVOC/NOx: 실내 센서 자체 측정(비교 분석 미제공)

### 8.7 실외 전용 탭으로서의 의미

이 탭은 실외 기준 대비 편차를 보여주는 "대조/검증" 탭이다.
즉, 절대값 모니터링(개요/모니터링 탭)과 달리 "실외 대비 차이"가 핵심 UX다.

실무에서 이 탭이 유용한 대표 상황:
- 환기 후 실내 PM/습도가 외부와 얼마나 수렴하는지 확인
- 체감상 답답함이 있을 때 CO2는 제외하고 PM/온습도 기준으로 외부와 격차 점검
- 센서 이상 의심 시 외부 기준과 장기 편차 추세 확인

## 9) 상세 로직 빠른 보정 절차 및 적용 경로

향후 임계치/함수 보정이 잦을 때, 아래 순서대로만 수정하면 빠르게 일관성을 유지할 수 있다.

### 9.1 1회 보정 작업 절차 (권장 순서)

1. 변경 유형 확정
  - IAQI 수식 변경인지, 정화 시나리오 판정 변경인지, UI 문구/색상 변경인지 먼저 분류한다.
2. 계산 엔진/서버를 먼저 수정
  - 연산의 원천(서버/엔진)을 먼저 고치고, 파서/뷰는 그 다음에 맞춘다.
3. 매핑 계층 동기화
  - iaqiScore, primary_grade, sub_level 등 필드가 스냅샷 파서/저장소에서 동일하게 읽히는지 맞춘다.
4. UI/문서 반영
  - 카드 라벨, 설명 페이지, 운영 문서를 같은 용어로 맞춘다.
5. 빠른 회귀 검증
  - 핵심 함수 검색, 레거시 키(usAQI) 재유입 검색, 화면 3모드(어린이/고령자/정화지표) 확인을 수행한다.

### 9.2 변경 유형별 적용 경로 (필수 반영 지점)

1. IAQI 수식/등급 기준 보정
  - iaq-v2-firebase/functions/index.js
    - calculateIaqi
    - buildIaqiBundle
    - buildIaqiBundleFromSnapshot
  - Indoorairqualityappv2-main/src/flutter/lib/utils/nodered_health_engine.dart
    - calculate_iaqi

2. equilibrium_clean/시나리오 판정 보정
  - Indoorairqualityappv2-main/src/flutter/lib/utils/nodered_health_engine.dart
    - computePurificationCadr
    - pmSlopeThresholdPerMin, co2SlopeThresholdPerMin, tvocSlopeThresholdPerMin
    - pmRiseLimitPerMin, co2RiseLimitPerMin, tvocRiseLimitPerMin

3. k 회귀/윈도우/샘플수 보정
  - Indoorairqualityappv2-main/src/flutter/lib/utils/nodered_health_engine.dart
    - _kWindowMs, _kMinSamples, _noiseThreshold
    - _medianSlopePerMinute, _updateKRegression

4. 스냅샷 필드 매핑 보정
  - Indoorairqualityappv2-main/src/flutter/lib/models/air_quality_snapshot.dart
  - Indoorairqualityappv2-main/src/flutter/lib/services/firestore_snapshot_service.dart
  - Indoorairqualityappv2-main/src/flutter/lib/services/local_snapshot_store.dart

5. 건강 모드 UI 반영
  - Indoorairqualityappv2-main/src/flutter/lib/widgets/health_mode_dashboard.dart
  - Indoorairqualityappv2-main/src/flutter/lib/widgets/health_mode_info_page.dart
  - Indoorairqualityappv2-main/src/flutter/lib/widgets/air_quality_overview.dart

6. Node-RED/브리지 반영(사용 중인 경우)
  - Indoorairqualityappv2-main/11240000.json
  - Indoorairqualityappv2-main/mqtt_bridge.py

7. API/아키텍처 문서 동기화
  - Indoorairqualityappv2-main/openapi.yaml
  - Indoorairqualityappv2-main/docs/SYSTEM_ARCHITECTURE.md
  - HEALTH_MODE_CURRENT_IMPLEMENTATION_KR.md (본 문서)

### 9.3 빠른 검색 템플릿 (Windows PowerShell)

1. IAQI/시나리오 핵심 함수 찾기

```powershell
Get-ChildItem "Indoorairqualityappv2-main\src\flutter\lib" -Recurse -Include *.dart |
  Select-String -Pattern "calculate_iaqi|computePurificationCadr|equilibrium_clean"
```

2. 서버 IAQI 함수 찾기

```powershell
Select-String -Path "iaq-v2-firebase\functions\index.js" -Pattern "calculateIaqi|buildIaqiBundle|dispatchAutoControlForSnapshot"
```

3. 레거시 키 재유입 검사

```powershell
Get-ChildItem "iaq-v2-firebase","Indoorairqualityappv2-main" -Recurse -File |
  Select-String -Pattern "usAQI|usAqi|USAQI|US AQI"
```

### 9.4 수정 후 최소 검증 체크리스트

1. 정화지표 탭에서 mode/scenario와 k, t50 표시가 의도대로 나오는지 확인
2. 어린이/고령자 탭에서 점수 색상과 레벨 텍스트가 바뀐 기준과 일치하는지 확인
3. 스냅샷 파서에서 iaqiScore, primary_grade, sub_level이 누락 없이 들어오는지 확인
4. 서버 자동제어 임계치(iaqiOn/off 또는 aqiOn/off fallback)가 의도대로 적용되는지 로그 확인
5. 레거시 키(usAQI/usAqi) 검색이 0건인지 확인
