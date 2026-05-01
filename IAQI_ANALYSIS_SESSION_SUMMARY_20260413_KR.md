# IAQI 분석 세션 종합 정리 (2026-04-13)

## 1. 세션 목표와 요청 흐름
오늘 세션의 핵심 목적은 IAQI 식의 왜곡 여부(특히 k 지배), 온습도 반영 필요성, 그리고 역전 현상(좋은데 나쁘게 뜨거나/나쁜데 좋게 뜨는 현상)의 존재를 데이터 전체 구간에서 검증하는 것이었음.

요청 흐름 요약:
1. 온습도 반영 누락 지적 -> no-k + TH 재계산 및 재분석 요청
2. p50/p90 용어 의미 질문
3. over_alert_nok_th / thermal_driven_alert / miss_alert 의미 확인 + 위반 구간 표시 요청
4. 지배항 해석, 균등 분포 필요성, I 가중치 변경 접근 질의
5. 모든 구간, dataset1/2에 대해 역전 현상 전수 탐지 요청
6. 공기질 나쁜 데이터에서 역전 존재 여부 재검증 요청
7. "M/E 기반이면 보정 끝난 것 아닌가"에 대한 설계 철학 질의
8. 추천 식의 의미 설명 요청

## 2. 작업 파일 및 실행 환경
- 주요 작업 노트북: exports/plot_history_timeseries_from_row15.ipynb
- 데이터셋:
  - dataset1: sensor_d83bda1d5960_combined_all_2026-04-12_210243794Z_recomputed_latest_logic.csv
  - dataset2: sensor_d83bda1d5960_history_since_cleanup_2026-04-13_002101733Z.csv
- 분석 도구: pandas, numpy, plotly

## 3. 노트북 변경 사항(오늘 추가/보강)
노트북의 분석 확장 셀을 추가/보강하여 현재 총 16개 셀 상태.

추가/핵심 셀 요약:
- 셀 11: no-k + TH 재계산 및 진단
- 셀 12: no-k-only vs no-k+TH 델타 비교
- 셀 13: no-k+TH 결과 CSV export
- 셀 14: 위반 구간 탐지/표/음영 시각화
- 셀 15: 역전 현상 전수 스캔(2개 데이터셋 x 6개 시나리오)
- 셀 16: bad-air 역전 재검증(기준 정합/비정합 비교)

## 4. 중간 이슈 및 해결
- 이슈: 위반구간 분석 셀 실행 시 커널 상태에 따라 함수/임포트 미정의 오류 발생
- 조치: 셀 내부에 필요한 import/helper를 포함한 standalone 형태로 보강
- 결과: 재실행 성공, 표/그래프/CSV 정상 산출

## 5. 핵심 분석 결과

### 5.1 no-k + TH 관련 위반 진단
- over_alert_nok_th, thermal_driven_alert, miss_alert를 구간화(interval)하여 시각화 및 CSV 저장
- 목적: "언제, 얼마나 오래" 위반이 지속되는지 사건 단위로 확인

### 5.2 역전 스캔(좋은 raw인데 IAQI 나쁨)
시나리오:
- orig_air_only
- orig_full_good
- no_k_air_only
- no_k_full_good
- no_k_th_air_only
- no_k_th_full_good

dataset1 결과(요약):
- orig_air_only: 627/641 (97.816%)
- orig_full_good: 48/48 (100.000%)
- no_k_air_only: 0/641 (0.000%)
- no_k_full_good: 0/48 (0.000%)
- no_k_th_air_only: 593/641 (92.512%)
- no_k_th_full_good: 0/48 (0.000%)

dataset2 결과(요약):
- good_base_count가 0이라 해당 절대 기준 기반 역전 평가는 0건으로 표시됨

해석:
- dataset1에서는 기준 정의에 따라 역전이 크게 관측됨
- no-k + full_good 조건에서는 역전 0건으로 개선됨

### 5.3 bad-air 역전(나쁜 raw인데 m<1) 재검증
검증 포인트:
- 기준 정합 여부에 따라 역전 해석이 달라지는지 확인

Rule A (formula-aligned): co2>=1000 or pm25>=50 or tvoc>=200
- dataset1: bad=10,462, inversion=0 (orig/no-k/no-k+TH 모두 0)
- dataset2: bad=331, inversion=0 (orig/no-k/no-k+TH 모두 0)

Rule B (legacy-high): co2>=1000 or pm25>=35 or tvoc>=300
- dataset1: bad=10,385, inversion=0 (모든 시나리오 0)
- dataset2: bad=0

Rule C (not-good): co2>=800 or pm25>=15 or tvoc>=150
- dataset1:
  - orig_m: 55/15,064 (0.365%)
  - no_k_m: 4,602/15,064 (30.550%)
  - no_k_th_m: 4,200/15,064 (27.881%)
- dataset2:
  - orig_m: 0/1,061 (0.000%)
  - no_k_m: 730/1,061 (68.803%)
  - no_k_th_m: 730/1,061 (68.803%)

핵심 결론:
- 식 경계와 정합된 bad 기준에서는 M 기반 역전(나쁜데 m<1)은 구조적으로 발생 불가
- 외부 운영 기준(비정합 기준)을 적용하면 역전처럼 보이는 현상이 생길 수 있음

## 6. 오늘 도출된 해석 프레임
1. "정답 식 1개"가 아니라 "목적 최적화된 식"이 필요
2. M은 등급 경계 판정에 유리하지만, 체감/운영 목적까지 단독으로 만족시키기 어려움
3. E(초과량)와 분리해 사용하면 심각도 표현이 안정적
4. 기준(운영 rule)과 식 경계를 반드시 분리 정의해야 해석 혼선을 줄일 수 있음

## 7. 제안된 식(설계 방향)과 의미
제안 구조:
- A = (w1*rCo2^p + w2*rPm25^p + w3*rVoc^p)^(1/p)
- M = max(A, lambda*rTh)
- E = sum(max(0, r_i - 1))
- S = M + beta*E

의미:
- A: 공기오염 대표 위험(부드러운 집계)
- M: 등급 판단의 핵심 위험도
- E: 임계 초과 심각도
- S: 운영/랭킹용 최종 점수

## 8. 생성된 산출물 파일
- exports/no_k_th_violation_intervals.csv
- exports/inversion_summary_all_scenarios.csv
- exports/inversion_intervals_all_scenarios.csv
- exports/inversion_samples_all_scenarios.csv
- exports/bad_air_inversion_summary.csv
- exports/bad_air_inversion_samples.csv
- exports/previous_recomputed_no_k_th_recomputed.csv
- exports/latest_since_cleanup_no_k_th_recomputed.csv

## 9. 현재 상태 요약
- 데이터 전구간 기준의 역전 현상 탐지 파이프라인은 구축 완료
- 기준 정합/비정합에 따른 역전 해석 차이를 실증적으로 확인 완료
- 식 자체 논리 검증(M 경계 정합성)과 운영 기준 설계 이슈를 분리해 설명 가능 상태

## 10. 다음 단계(권장)
1. 파라미터 탐색 셀 추가: w_i, p, lambda, beta 그리드 탐색
2. 목적함수 정의: 과경보율 + 미경보율 + 지연 + 안정성 동시 최적화
3. dataset2 상대 기준(q-quantile) 병행 평가로 기준 민감도 분석
4. 최종 운영 규칙서 문서화: 식 경계 vs 운영 기준 분리 명시

## 11. 후속 추출(2026-04-14 실행)
- 요청: "어제 오전 데이터도 어제 하던 방식처럼 뽑기"
- 대상 파일: exports/sensor_d83bda1d5960_history_since_cleanup_2026-04-13_002101733Z.csv
- 추출 창: 2026-04-13 00:00:00 ~ 12:00:00 (KST)

요약 결과:
- rows: 1,075
- strict_good_ratio_% (co2<800, pm25<15, tvoc<150): 0.0
- not_bad_formula_ratio_% (co2<1000, pm25<50, tvoc<200): 69.209
- legacy_non_high_ratio_% (co2<1000, pm25<35, tvoc<300): 100.0
- median: co2=668.667, pm25=19.333, tvoc=138.750

M 진단(동일 창):
- m_orig: p50=3.000, p90=3.000
- m_no_k: p50=0.388, p90=1.261
- m_no_k_th: p50=0.813, p90=1.261
- over_alert_on_strict_good_%: 전 시나리오 0.0
- bad_but_m_lt_1_%(formula_aligned): 전 시나리오 0.0

생성 파일:
- exports/yesterday_morning_kst_2026-04-13_slice.csv
- exports/yesterday_morning_kst_2026-04-13_summary.csv
- exports/yesterday_morning_kst_2026-04-13_m_diag.csv
