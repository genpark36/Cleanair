# Cleanair

모빌리티캡스톤디자인 II 제출 결과물인 공기질 제어 및 방재 프로젝트입니다.

Cleanair는 실내 공기질 센서, Firebase 백엔드, 스마트 플러그, 방재모드, 웹 상황판을 하나로 묶은 실내 안전 관리 시스템입니다. 평상시에는 실내 공기질을 확인하고, 위험한 패턴이 감지되면 앱과 웹 상황판에서 대응할 수 있도록 구성했습니다.

## 파일

- Android 앱 APK: `release_apk/cleanair-final-release.apk`
- 앱 소스: `flutter/`
- Firebase Functions: `functions/`
- 웹 상황판: `web_dashboard/`
- 센서 펌웨어 설치 파일: `firmware_installer/`
- 실행 가이드: `docs/RUN_GUIDE.md`
- 제출 전 점검표: `docs/FINAL_CHECKLIST.md`
- Tasmota MQTT 설정 가이드: `docs/TASMOTA_MQTT_USER_SETUP_GUIDE.pdf`

## 실행 순서

1. `release_apk/cleanair-final-release.apk`를 Android 기기에 설치합니다.
2. AirGradient 센서에 `firmware_installer/`의 펌웨어를 설치합니다.
3. 앱에서 센서를 PIN 또는 mDNS로 등록합니다.
4. 앱에서 센서 위치를 저장합니다.
5. Tasmota 플러그를 앱에 등록하고 로컬 HTTP 또는 MQTT 제어를 확인합니다.
6. 웹 상황판에 접속해 센서와 플러그 상태를 확인합니다.

자세한 절차는 `docs/RUN_GUIDE.md`에 정리하였습니다.

## 빌드 명령

Android 앱을 다시 빌드할 때:

```powershell
cd flutter
C:\src\flutter\bin\flutter.bat pub get
C:\src\flutter\bin\flutter.bat build apk --release
```

초기 설정 화면부터 다시 확인할 때:

```powershell
cd flutter
C:\src\flutter\bin\flutter.bat run --dart-define=FORCE_ONBOARDING=true
```

웹 상황판 배포:

```powershell
firebase deploy --only hosting --project capstone-cleanair-2026
```

Firebase Functions 배포:

```powershell
cd functions
npm install
cd ..
firebase deploy --only functions --project capstone-cleanair-2026
```

## 포함된 설정 정보

Firebase 설정, 웹 대시보드 설정, Functions 환경 변수, MQTT 접속 정보, 펌웨어 설치 파일을 함께 넣었습니다. 

## 현재 배포 주소

- 웹 상황판: `https://capstone-cleanair-2026.web.app`
- Firebase 프로젝트: `capstone-cleanair-2026`
