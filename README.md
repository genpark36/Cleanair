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
- 앱 기능 설명: `docs/APP_OVERVIEW.md`
- 제출 전 점검표: `docs/FINAL_CHECKLIST.md`
- Tasmota MQTT 설정 가이드: `docs/TASMOTA_MQTT_SETUP.md`

## 실행 순서

1. `release_apk/cleanair-final-release.apk`를 Android 기기에 설치합니다.
2. AirGradient 센서에 `firmware_installer/`의 펌웨어를 설치합니다.
3. 앱에서 센서를 PIN 또는 mDNS로 등록합니다.
4. 앱에서 센서 위치를 저장합니다.
5. Tasmota 플러그를 앱에 등록하고 로컬 HTTP 또는 MQTT 제어를 확인합니다.
6. 웹 상황판에 접속해 센서와 플러그 상태를 확인합니다.

자세한 절차는 `docs/RUN_GUIDE.md`에 정리하였습니다. 앱에서 무엇을 확인할 수 있는지는 `docs/APP_OVERVIEW.md`에 따로 정리했습니다.

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

Slack 외부 알림은 앱의 알림 설정 화면에서 워크스페이스를 연결해 사용합니다. 연결이 끝나면 서버가 해당 채널의 webhook을 저장하고, 실제 경보가 발생했을 때 같은 경로로 Slack 메시지를 보냅니다. 앱의 `테스트` 버튼으로 Slack 전송 여부를 먼저 확인할 수 있습니다.

AI 추천 문구를 API로 생성하려면 Functions 환경 변수에 `AI_PROVIDER=gemini`, `GEMINI_API_KEY`, `GEMINI_MODEL`을 넣고 Functions를 다시 배포합니다. OpenAI를 쓰는 경우에는 `AI_PROVIDER=openai`, `OPENAI_API_KEY`, `OPENAI_RECOMMENDATION_MODEL`을 사용할 수 있습니다. 키가 없거나 API 호출이 실패하면 서버가 기존 공기질 기준을 이용한 규칙 기반 추천을 반환하므로 앱 화면은 계속 정상 동작합니다.

상세 그래프의 배경 색상은 시간 구간이 아니라 각 지표의 수치 기준선을 기준으로 표시됩니다. 그래프의 X축은 측정 시각, Y축 색상은 좋음/보통/나쁨 같은 상태 구간을 의미합니다.

## 포함된 설정 정보

Firebase 앱 설정, 웹 대시보드 설정, 펌웨어 설치 파일을 함께 넣었습니다.

Functions 환경 변수는 GitHub push protection에 걸리지 않도록 저장소에 올리지 않습니다. 이미 배포된 Firebase 프로젝트에는 필요한 값이 설정되어 있으며, Functions를 새로 배포할 때는 로컬의 `functions/.env` 또는 Firebase 환경 변수에 같은 값을 넣어야 합니다.

이 저장소는 제출용 비공개 저장소로 유지하는 것을 전제로 합니다. 공개 저장소로 전환할 경우 `web_dashboard/firebase-config.js`, `flutter/android/app/google-services.json`의 값도 먼저 교체하거나 제거해야 합니다.

## 현재 배포 주소

- 웹 상황판: `https://capstone-cleanair-2026.web.app`
- Firebase 프로젝트: `capstone-cleanair-2026`
