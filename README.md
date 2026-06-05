# Cleanair

Cleanair는 AirGradient 센서, Android 앱, Firebase, Tasmota 스마트 플러그, 웹 상황판을 연결한 실내 공기질 관리 및 방재 보조 시스템입니다.

평상시에는 실내 공기질을 확인하고, 공기질이 나빠지면 환기와 공기청정기 사용을 안내합니다. 화재가 의심될 만한 복합 패턴이 나타나면 앱과 웹 상황판에서 상황을 확인하고 대응 장치를 제어할 수 있습니다.

## 구성 파일

- Android 앱 APK: `release_apk/cleanair-final-release.apk`
- Flutter 앱 소스: `flutter/`
- Firebase Functions: `functions/`
- 웹 상황판: `web_dashboard/`
- AirGradient 펌웨어 설치 패키지: `firmware_installer/`

## 사용자 문서

- 앱 사용 설명서: `docs/APP_OVERVIEW.md`
- 설치 및 설정 가이드: `docs/RUN_GUIDE.md`

두 문서만 보면 앱 설치, 센서 등록, 위치 설정, 스마트 플러그 제어, MQTT 원격 제어, 알림, Slack 연동, 웹 상황판 사용까지 순서대로 진행할 수 있습니다.

## 빠른 시작

1. Android 기기에 `release_apk/cleanair-final-release.apk`를 설치합니다.
2. AirGradient 센서에 `firmware_installer/`의 펌웨어를 설치합니다.
3. 앱에서 센서를 PIN 또는 mDNS로 등록합니다.
4. 센서 위치를 저장합니다.
5. Tasmota 스마트 플러그를 등록하고 ON/OFF 제어를 확인합니다.
6. 필요한 경우 MQTT와 Slack을 연결합니다.
7. 웹 상황판에서 센서, 플러그, 방재 이벤트가 표시되는지 확인합니다.

자세한 절차는 `docs/RUN_GUIDE.md`에 정리되어 있습니다.

## 배포 주소

- 웹 상황판: `https://capstone-cleanair-2026.web.app`
- Firebase 프로젝트: `capstone-cleanair-2026`
