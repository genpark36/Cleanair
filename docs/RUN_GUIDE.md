# Cleanair 실행 가이드

이 문서는 제출 패키지를 받아 앱, 센서, 플러그, 웹 상황판을 확인하는 순서를 정리한 문서입니다.

## 1. 준비물

- Android 휴대폰
- AirGradient ONE 센서
- Tasmota 스마트 플러그
- Windows PC
- Firebase CLI
- Node.js
- Python
- Python 패키지 `esptool`

앱을 새로 빌드하지 않고 APK만 설치한다면 Flutter SDK는 필요하지 않습니다.

## 2. Android 앱 설치

APK 파일은 아래 경로에 있습니다.

```text
release_apk/cleanair-final-release.apk
```

휴대폰으로 옮긴 뒤 설치합니다. Android에서 설치를 막으면 해당 파일 관리자 또는 브라우저의 "알 수 없는 앱 설치" 권한을 허용합니다.

## 3. 센서 펌웨어 설치

센서를 USB로 PC에 연결한 뒤 아래 파일을 실행합니다.

```powershell
cd firmware_installer
.\install_cleanair_firmware.bat
```

설치 프로그램이 COM 포트를 물어보면 센서가 연결된 포트를 선택합니다. 설치가 끝나면 센서가 재부팅되고, 화면에 PIN이 표시됩니다.

이 폴더에는 설치에 필요한 바이너리와 스크립트만 들어 있습니다.

- `firmware.bin`
- `bootloader.bin`
- `partitions.bin`
- `boot_app0.bin`
- `install_cleanair_firmware.bat`
- `install_cleanair_firmware.ps1`

이 펌웨어는 `capstone-cleanair-2026` Firebase 릴레이 주소로 센서 데이터를 전송하는 제출용 수정본입니다. 현재 센서 payload는 온도, 습도, PM2.5, CO2, TVOC, NOx를 보냅니다. CO 값은 앱, 웹, 서버에서 필드가 들어오면 표시하도록 처리되어 있지만, 이 AirGradient ONE 펌웨어 payload에는 실제 CO 센서값이 포함되어 있지 않습니다.

## 4. 앱 초기 설정

처음 실행하면 아래 순서로 진행합니다.

1. 시작 화면에서 설정을 시작합니다.
2. 알림 권한과 백그라운드 관련 권한을 허용합니다.
3. 센서를 PIN 또는 mDNS로 등록합니다.
4. 센서 위치를 저장합니다.
5. 메인 화면에서 실시간 센서값이 표시되는지 확인합니다.

초기 설정 화면부터 다시 확인할 때:

```powershell
cd flutter
C:\src\flutter\bin\flutter.bat run --dart-define=FORCE_ONBOARDING=true
```

## 5. 앱 기능 확인

앱에서 확인할 항목입니다.

- 메인 대시보드 실시간 센서값
- 통합 공기질 지수
- 상세 그래프와 구간 통계
- CSV 저장
- 건강 모드
- 공식 측정소 비교와 히트맵
- 알림 설정
- Tasmota 플러그 제어
- 방재모드
- 방재 상황 전파

CSV 파일은 Android 기준으로 아래 폴더에 저장됩니다.

```text
Download/AirGradient
```

## 6. Tasmota 플러그 설정

플러그 제어는 두 가지 방식으로 확인할 수 있습니다.

- 같은 Wi-Fi 안에서는 로컬 HTTP 제어
- 외부에서는 MQTT 제어

로컬 HTTP 제어는 앱에 플러그 IP를 입력하면 됩니다.

외부 제어까지 확인하려면 Tasmota의 MQTT 설정에 HiveMQ 정보를 입력합니다. 입력값과 확인 방법은 아래 문서를 따릅니다.

```text
docs/TASMOTA_MQTT_SETUP.md
```

앱에서 플러그를 등록한 뒤 아래 항목을 확인합니다.

- ON/OFF 수동 제어
- 자동 제어 설정
- 전압, 전류, 전력 표시
- 제어 이력
- 제어 이력 CSV 저장

MQTT 원격 제어를 사용할 때는 Functions 폴더에서 워커를 실행합니다.

```powershell
cd functions
npm install
npm run worker:plug
```

로컬 HTTP 제어만 확인하는 경우에는 MQTT 워커가 없어도 됩니다.

## 7. Firebase Functions 배포

Functions 코드는 `functions/`에 있습니다.

```powershell
cd functions
npm install
cd ..
firebase deploy --only functions --project capstone-cleanair-2026
```

Functions는 센서 데이터 수신, 알림, 방재 판단, 플러그 제어 명령, MQTT 연동을 담당합니다.

## 8. 웹 상황판

웹 상황판 소스는 `web_dashboard/`에 있습니다.

현재 배포 주소:

```text
https://capstone-cleanair-2026.web.app
```

다시 배포할 때:

```powershell
firebase deploy --only hosting --project capstone-cleanair-2026
```

웹 상황판에서 확인할 항목입니다.

- Google 로그인
- 등록된 센서 상태
- 등록된 플러그 상태
- 지도 기반 상황판
- 방재 이벤트
- 상황 종료
- 플러그 원격 제어
- 제어 이력 CSV 저장

## 9. 보조 확인 도구

제출본에는 앱, 웹 상황판, Firebase Functions, 펌웨어 설치 패키지처럼 실행에 필요한 파일만 남겼습니다.
실험용 검증 스크립트, 일회성 진단 스크립트, 개발 중간 산출물은 포함하지 않았습니다.

## 10. 포함된 설정 파일

이 제출 패키지는 바로 실행되는 것을 우선해 실제 설정 파일을 포함합니다.

- 앱 Firebase 설정: `flutter/android/app/google-services.json`
- 웹 Firebase 설정: `web_dashboard/firebase-config.js`
- Functions 환경 변수: `functions/.env`
- Firebase 설정: `.firebaserc`, `firebase.json`, `firestore.rules`

저장소는 비공개로 유지해야 합니다.
