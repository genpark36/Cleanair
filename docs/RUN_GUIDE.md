# Cleanair 설치 및 설정 가이드

이 문서는 Cleanair를 처음 받는 사용자가 Android 앱, AirGradient 센서, Tasmota 플러그, 웹 상황판을 실제로 사용할 수 있도록 정리한 가이드입니다.

기본 순서는 다음과 같습니다.

```text
앱 설치
-> 센서 펌웨어 설치
-> 앱에서 센서 등록
-> 센서 위치 저장
-> 플러그 등록
-> 알림과 Slack 설정
-> 웹 상황판 확인
```

## 1. 준비물

| 준비물 | 용도 |
| --- | --- |
| Android 휴대폰 | Cleanair 앱 실행 |
| Windows PC | 센서 펌웨어 설치, 필요 시 앱 빌드 |
| AirGradient ONE 센서 | 실내 공기질 측정 |
| USB 케이블 | 센서 펌웨어 설치 |
| Tasmota 스마트 플러그 | 공기청정기, 환기팬, 경광등 등 제어 |
| Wi-Fi | 센서, 휴대폰, 플러그 연결 |
| Google 계정 | 앱과 웹 상황판 로그인 |
| Slack 워크스페이스 | 외부 알림을 사용할 때 필요 |

APK만 설치해서 사용할 경우 Flutter SDK는 필요하지 않습니다. 앱을 직접 빌드하거나 수정하려면 Flutter SDK와 Android Studio가 필요합니다.

## 2. 폴더 구성

이 문서의 명령어는 GitHub에서 받은 `Cleanair` 폴더를 기준으로 작성했습니다. PowerShell이나 터미널에서 먼저 `Cleanair` 폴더로 이동한 뒤 실행하면 됩니다.

| 경로 | 내용 |
| --- | --- |
| `release_apk/cleanair-final-release.apk` | Android 설치 파일 |
| `flutter/` | Flutter 앱 소스 |
| `functions/` | Firebase Functions |
| `web_dashboard/` | 웹 상황판 |
| `firmware_installer/` | 센서 펌웨어 설치 패키지 |
| `docs/APP_OVERVIEW.md` | 앱 기능 설명 |
| `docs/RUN_GUIDE.md` | 이 문서 |

## 3. Android 앱 설치

APK 파일은 아래 위치에 있습니다.

```text
release_apk/cleanair-final-release.apk
```

설치 방법:

1. APK 파일을 Android 휴대폰으로 옮깁니다.
2. 파일 관리자에서 APK를 실행합니다.
3. Android가 설치를 막으면 해당 파일 관리자 또는 브라우저의 “알 수 없는 앱 설치” 권한을 허용합니다.
4. 설치가 끝나면 Cleanair 앱을 실행합니다.

처음 실행하면 초기 설정 화면이 열립니다. 이미 설정을 마친 상태에서 다시 초기 설정부터 보고 싶다면 프로젝트를 받은 폴더에서 Flutter 실행 옵션을 사용합니다.

```powershell
cd .\flutter
flutter run --dart-define=FORCE_ONBOARDING=true
```

Windows에서 `flutter` 명령이 잡히지 않으면 Flutter SDK를 설치한 위치의 실행 파일을 직접 사용합니다. 예를 들어 `C:\src\flutter`에 설치했다면 `C:\src\flutter\bin\flutter.bat run`처럼 실행하면 됩니다.

## 4. AirGradient 센서 펌웨어 설치

Cleanair 앱과 연결하려면 센서에 제출용 펌웨어를 설치해야 합니다.

### 4.1 설치 파일

펌웨어 설치 패키지는 아래 폴더에 있습니다.

```text
firmware_installer/
```

주요 파일:

| 파일 | 용도 |
| --- | --- |
| `install_cleanair_firmware.bat` | Windows에서 실행하는 설치 파일 |
| `install_cleanair_firmware.ps1` | PowerShell 설치 스크립트 |
| `firmware.bin` | 앱과 Firebase로 데이터를 보내는 센서 펌웨어 |
| `bootloader.bin` | ESP32 부트로더 |
| `partitions.bin` | 파티션 정보 |
| `boot_app0.bin` | 부팅 보조 파일 |

### 4.2 설치 순서

1. AirGradient 센서를 USB로 PC에 연결합니다.
2. `firmware_installer` 폴더를 엽니다.
3. `install_cleanair_firmware.bat`를 실행합니다.
4. COM 포트를 물어보면 센서가 연결된 포트를 선택합니다.
5. 설치가 끝날 때까지 USB를 빼지 않습니다.
6. 센서가 재부팅되면 화면에 PIN이 표시되는지 확인합니다.

PowerShell에서 직접 실행할 수도 있습니다.

```powershell
cd .\firmware_installer
.\install_cleanair_firmware.bat
```

### 4.3 현재 펌웨어에서 보내는 값

현재 펌웨어는 다음 값을 Firebase로 보냅니다.

| 값 | 설명 |
| --- | --- |
| PM2.5 | 초미세먼지 |
| CO2 | 이산화탄소 |
| TVOC | VOC Index |
| NOx | NOx Index |
| 온도 | 실내 온도 |
| 습도 | 실내 습도 |

CO 센서값은 앱, 웹, 서버에서 받을 준비가 되어 있지만, AirGradient ONE 기본 센서 구성에는 CO 센서가 없습니다. CO 값을 실제로 쓰려면 별도 CO 센서를 장착하고 펌웨어에서 `co` 값을 보내도록 수정해야 합니다.

## 5. 앱에서 센서 등록

앱을 처음 실행하면 센서 등록 흐름이 나옵니다.

### 5.1 PIN 등록

1. 센서 화면에 표시된 PIN을 확인합니다.
2. 앱에서 PIN 등록을 선택합니다.
3. PIN을 입력합니다.
4. 등록이 끝나면 센서가 앱에 연결됩니다.

PIN 등록은 Firebase 기기 등록 흐름을 사용합니다. 센서와 앱이 같은 계정 아래에서 연결되도록 하는 기본 방식입니다.

### 5.2 mDNS 등록

같은 Wi-Fi 안에 있는 센서를 자동으로 찾을 수도 있습니다.

1. 휴대폰과 센서를 같은 Wi-Fi에 연결합니다.
2. 앱에서 주변 센서 검색을 선택합니다.
3. 검색된 센서를 선택합니다.
4. 연결 완료 메시지를 확인합니다.

mDNS는 같은 네트워크 안에서만 동작합니다. 휴대폰이 모바일 데이터 상태이거나 센서와 다른 Wi-Fi에 있으면 검색되지 않을 수 있습니다.

## 6. 센서 위치 저장

센서 등록 후에는 위치를 저장해야 합니다. 위치 정보는 알림, 방재모드, 웹 상황판, 플러그 연결에 사용됩니다.

저장하는 정보:

| 항목 | 예시 |
| --- | --- |
| 공간 이름 | 방, 거실, 실험실, 어린이집 1층 |
| 시설 유형 | 주거, 교육시설, 사무실, 실험실 등 |
| 주소 | 지도 검색 또는 직접 입력 |
| 층 | 1층, 2층, 지하 1층 |
| 세부 위치 | 창가, 책상 옆, 복도, 주방 근처 |
| 설치 메모 | 센서 설치 상황 기록 |

지도에서 위치를 검색하거나 현재 위치를 사용할 수 있습니다. 위치 권한을 허용하면 현재 위치 기준으로 지도를 이동할 수 있습니다.

## 7. 메인 화면 확인

센서 등록과 위치 저장이 끝나면 메인 대시보드에서 실시간 값이 표시됩니다.

확인할 것:

- IAQI 값이 표시되는지
- PM2.5, CO2, TVOC, NOx, 온도, 습도가 표시되는지
- “센서 연결 대기”가 아니라 실제 값으로 바뀌었는지
- 그래프와 상세 화면에 기록이 쌓이는지
- 알림 설정 화면에서 기기 상태가 정상인지

값이 보이지 않으면 아래를 확인합니다.

| 증상 | 확인할 것 |
| --- | --- |
| 센서 등록은 됐는데 값이 안 보임 | 센서가 Firebase로 데이터를 보내는지 확인 |
| mDNS는 됐는데 메인에 값이 없음 | 앱에 등록된 센서 ID와 Firebase 문서 ID 확인 |
| 값이 오래된 상태로 멈춤 | 센서 Wi-Fi 연결, 펌웨어 설치 상태 확인 |
| Firebase 오류 표시 | 앱의 `google-services.json`과 Firebase 프로젝트 확인 |

## 8. 상세 그래프와 CSV 저장

상세 화면에서는 각 지표의 시간 흐름을 볼 수 있습니다.

사용 방법:

1. 상세 탭으로 이동합니다.
2. PM2.5, CO2, TVOC, NOx 등 보고 싶은 지표를 선택합니다.
3. 10분, 1시간, 6시간, 24시간, 주간 범위를 선택합니다.
4. 점 모드로 특정 시각의 값을 확인합니다.
5. 구간 모드로 일정 시간 범위의 통계를 확인합니다.
6. 필요한 경우 CSV 저장을 누릅니다.

그래프 배경 색상은 수치 기준선을 의미합니다. 시간대별 색상이 아니라, Y축 값이 어떤 상태 구간에 있는지 보여주는 색입니다.

CSV 파일은 Android 기준으로 아래 폴더에 저장됩니다.

```text
Download/AirGradient
```

최근 30일 전체 데이터가 없더라도, 30일 안에 실제로 존재하는 데이터는 가능한 만큼 저장됩니다.

## 9. 알림 설정

알림 설정에서는 일반 공기질 알림, 방재 알림, 플러그 알림, Slack 외부 알림을 설정합니다.

### 9.1 일반 공기질 알림

항목별로 알림 기준을 조절할 수 있습니다.

| 항목 | 알림 예시 |
| --- | --- |
| PM2.5 | 초미세먼지가 나쁨 이상일 때 |
| CO2 | 환기가 필요한 수준일 때 |
| TVOC | 냄새나 화학물질 영향이 커졌을 때 |
| NOx | 연소원이나 외기 유입 영향이 의심될 때 |

### 9.2 방재 알림

방재 알림은 다음 기준 중에서 선택할 수 있습니다.

| 기준 | 의미 |
| --- | --- |
| 경고 이상 | 이상 흐름이 뚜렷할 때부터 알림 |
| 강한 경고 이상 | 여러 지표가 함께 나빠지거나 반복될 때부터 알림 |
| 화재 의심/CO 위험 | 즉시 확인이 필요한 단계만 알림 |

### 9.3 Slack 연결

Slack 외부 알림을 사용하려면 앱에서 워크스페이스를 연결합니다.

1. 앱에서 설정 탭으로 이동합니다.
2. 알림 설정을 엽니다.
3. Slack 연결 버튼을 누릅니다.
4. Slack 워크스페이스에 로그인합니다.
5. 알림을 받을 채널을 선택하고 허용합니다.
6. 앱으로 돌아와 연결 확인 또는 테스트 버튼을 누릅니다.
7. Slack 채널에 테스트 메시지가 오면 연결이 완료된 것입니다.

실제 경보가 발생하면 앱 푸시와 함께 Slack 채널에도 알림을 보낼 수 있습니다.

## 10. Tasmota 플러그 등록

스마트 플러그는 공기질 악화나 방재 상황에서 연결 장치를 켜고 끄기 위해 사용합니다.

### 10.1 새 플러그의 Wi-Fi 연결

Tasmota 플러그를 처음 꽂으면 플러그가 자체 Wi-Fi를 엽니다. 휴대폰이나 PC에서 그 Wi-Fi에 접속한 뒤 아래 주소를 엽니다.

```text
http://192.168.4.1/
```

이 주소는 초기 설정 모드에서만 쓰는 주소입니다. 여기에서 사용할 Wi-Fi를 선택하고 비밀번호를 저장하면 플러그가 재부팅됩니다.

재부팅 뒤에는 공유기에서 플러그에 새 IP가 할당됩니다. 이후에는 `192.168.4.1`이 아니라 새로 할당된 플러그 IP로 접속합니다.

```text
http://플러그_IP
```

이 화면에서 로컬 ON/OFF 테스트를 할 수 있고, `Configuration -> Configure MQTT`로 들어가 MQTT 설정을 입력할 수 있습니다.

### 10.2 앱 등록 정보

앱에서 플러그를 등록할 때 입력하는 정보:

| 항목 | 설명 |
| --- | --- |
| 이름 | 사용자가 알아볼 수 있는 이름 |
| 위치 | 플러그가 설치된 위치 |
| 로컬 IP | 같은 Wi-Fi에서 제어할 때 사용하는 IP |
| MQTT Topic | 외부 제어를 위한 플러그 고유 토픽 |
| 제어 방식 | 로컬 HTTP, MQTT, 자동 제어 |

플러그가 여러 개라면 이름과 MQTT Topic이 겹치지 않게 설정해야 합니다.

권장 Topic:

```text
cleanair_plug_01
cleanair_plug_02
cleanair_plug_03
```

## 11. 로컬 HTTP 플러그 제어

같은 Wi-Fi 안에서 제어할 때는 로컬 HTTP 방식이 가장 단순합니다.

1. 플러그와 휴대폰을 같은 Wi-Fi에 연결합니다.
2. Tasmota 플러그의 IP를 확인합니다.
3. 앱의 플러그 등록 화면에 IP를 입력합니다.
4. 연결 테스트를 누릅니다.
5. ON/OFF 테스트를 실행합니다.

IP가 잘못되면 제어가 실패합니다. 이 경우 Tasmota 웹 화면에 접속되는지 먼저 확인합니다.

```text
http://플러그_IP
```

## 12. MQTT 플러그 제어

MQTT를 설정하면 같은 Wi-Fi가 아니어도 플러그를 제어할 수 있습니다.

### 12.1 Tasmota MQTT 입력값

Tasmota 웹 화면에서 아래 메뉴로 이동합니다.

```text
Configuration -> Configure MQTT
```

입력 항목:

| Tasmota 항목 | 입력값 |
| --- | --- |
| Host | MQTT 서버 주소 |
| Port | 8883 |
| MQTT TLS | `mqtts://` 서버를 쓰면 체크 |
| Client | `cleanair_plug_01_%06X`처럼 Topic 뒤에 `_%06X` 추가 |
| User | MQTT 사용자 이름 |
| Password | 제공된 MQTT 비밀번호 |
| Topic | 앱에 등록할 플러그 Topic |
| Full Topic | `%prefix%/%topic%/` |

예시:

```text
Client: cleanair_plug_01_%06X
Topic: cleanair_plug_01
Full Topic: %prefix%/%topic%/
```

두 번째 플러그는 Topic만 바꿉니다.

```text
Client: cleanair_plug_02_%06X
Topic: cleanair_plug_02
Full Topic: %prefix%/%topic%/
```

세 번째 플러그는 아래처럼 입력합니다.

```text
Client: cleanair_plug_03_%06X
Topic: cleanair_plug_03
Full Topic: %prefix%/%topic%/
```

심사 또는 시연 환경에서는 HiveMQ 관리자 화면을 따로 만질 필요가 없습니다. 제출자가 미리 준비한 MQTT 계정과 Topic을 그대로 입력하면 됩니다.

권장 Topic:

```text
cleanair_plug_01
cleanair_plug_02
cleanair_plug_03
```

새 플러그를 추가할 때는 아직 쓰지 않은 번호를 선택합니다. 이미 등록된 플러그와 같은 Topic을 쓰면 두 플러그가 같은 명령을 받거나, 앱에서 상태가 섞여 보일 수 있습니다.

관리자용 참고: HiveMQ Cloud에서는 위 Topic들이 사용할 수 있도록 미리 publish/subscribe 권한을 열어두어야 합니다. 심사자는 이 작업을 하지 않습니다.

### 12.2 Tasmota 콘솔 확인

Tasmota Console에서 아래 명령을 입력합니다.

```text
Status 6
```

정상이라면 `MqttHost`, `MqttPort`, `MqttClient`, `MqttUser`, `MqttCount`가 표시됩니다. `MqttCount`가 1 이상이면 연결이 한 번 이상 성공한 것입니다.

전원 테스트는 아래처럼 입력합니다.

```text
Power On
Power Off
```

`ON` 또는 `OFF`만 입력하면 Tasmota가 명령으로 인식하지 못할 수 있습니다.

### 12.3 MQTT 연결 실패 확인

Tasmota Console에 아래와 같은 로그가 반복되면 MQTT 서버가 접속을 거절한 것입니다.

```text
MQT: Connect failed ... rc 5
```

`rc 5`는 보통 사용자 이름, 비밀번호, TLS 설정, 또는 서버 쪽 권한 문제입니다. 기존 플러그는 되는데 새 플러그만 안 된다면 먼저 비밀번호와 Topic 번호를 확인합니다. 그래도 안 되면 해당 Topic이 서버에서 허용되어 있지 않을 수 있으므로 관리자에게 확인해야 합니다.

확인 순서:

1. Host에 `mqtts://`를 붙이지 않고 서버 주소만 입력했는지 확인합니다.
2. Port가 `8883`인지 확인합니다.
3. `MQTT TLS`가 체크되어 있는지 확인합니다.
4. User와 Password가 HiveMQ에 만든 값과 정확히 같은지 확인합니다.
5. Topic과 Client가 서로 맞는지 확인합니다.
6. 같은 Topic을 다른 플러그가 이미 쓰고 있지 않은지 확인합니다.

플러그 3번의 기본 입력 예시는 아래와 같습니다.

```text
Host: 7d18e3d75dbb4d12aa5951049f5868d2.s1.eu.hivemq.cloud
Port: 8883
MQTT TLS: 체크
Client: cleanair_plug_03_%06X
User: Capstone
Topic: cleanair_plug_03
Full Topic: %prefix%/%topic%/
```

비밀번호 칸에 `****`가 보여도 실제 비밀번호가 자동으로 유지된다는 뜻은 아닙니다. 새 플러그를 설정하거나 Topic을 바꿨다면 제공된 MQTT 비밀번호를 직접 다시 입력한 뒤 저장합니다. `rc 5`가 계속 뜨면 비밀번호를 다시 입력하고 저장한 뒤 플러그를 재시작합니다.

### 12.4 HiveMQ 웹 클라이언트 테스트

토픽을 구독합니다.

```text
stat/cleanair_plug_01/#
tele/cleanair_plug_01/#
```

켜기:

```text
Topic: cmnd/cleanair_plug_01/POWER
Message: ON
```

끄기:

```text
Topic: cmnd/cleanair_plug_01/POWER
Message: OFF
```

정상이라면 `stat/cleanair_plug_01/POWER`에 `ON` 또는 `OFF` 응답이 옵니다.

### 12.5 MQTT worker 실행

Functions 폴더에서 worker를 실행하면 MQTT 명령과 응답을 Firestore에 기록할 수 있습니다.

```powershell
cd .\functions
npm install
npm run worker:plug
```

시연 중에는 worker를 켜두는 편이 플러그 상태와 제어 이력 확인에 안정적입니다.

## 13. 플러그 자동 제어

자동 제어는 공기질 지표가 기준을 넘으면 플러그를 켜고, 회복 기준 아래로 내려가면 끄는 방식입니다.

설정할 수 있는 항목:

| 항목 | 설명 |
| --- | --- |
| 기준 지표 | IAQI, CO2, PM2.5, TVOC, NOx 등 |
| 켜는 기준 | 이 값 이상이면 플러그 ON |
| 끄는 기준 | 이 값 이하로 회복되면 플러그 OFF |
| 최소 유지 시간 | 너무 짧게 반복 동작하지 않도록 유지하는 시간 |

켜는 기준과 끄는 기준을 분리해야 플러그가 기준선 근처에서 계속 켜졌다 꺼지는 일을 줄일 수 있습니다.

## 14. 방재모드 사용

방재모드는 일반 공기질 악화와 화재 의심 상황을 구분합니다.

확인할 수 있는 항목:

- 현재 방재 단계
- 주요 관측값
- 최근 5분 변화량
- 센서와 플러그 위치
- 연결 장치 상태
- 상황 요약
- 웹 상황판 전송
- 119 전화 화면 열기

위험 상황에서는 앱에서 상황 요약을 복사하거나 공유할 수 있습니다. 필요하면 웹 상황판으로 전송해 다른 사람이 함께 확인할 수 있습니다.

## 15. 웹 상황판 사용

웹 상황판 주소:

```text
https://capstone-cleanair-2026.web.app
```

사용 순서:

1. 웹 상황판에 접속합니다.
2. Google 계정으로 로그인합니다.
3. 등록된 센서와 플러그가 보이는지 확인합니다.
4. 지도에서 센서 또는 플러그를 선택합니다.
5. 상태, 위치, 최근 값, 플러그 제어 버튼을 확인합니다.
6. 방재 이벤트가 올라오면 긴급 배너와 상세 화면을 확인합니다.
7. 현장 확인이 끝나면 상황 종료를 누릅니다.

웹 상황판에서는 플러그 제어와 제어 이력 CSV 저장도 할 수 있습니다.

## 16. 앱 빌드

APK를 새로 빌드하려면 Flutter 폴더에서 실행합니다.

```powershell
cd .\flutter
flutter pub get
flutter build apk --release
```

빌드된 APK 위치:

```text
flutter/build/app/outputs/flutter-apk/app-release.apk
```

제출용 APK 위치에 반영하려면 빌드된 파일을 아래 경로로 복사합니다.

```text
release_apk/cleanair-final-release.apk
```

## 17. Flutter 실행

일반 실행:

```powershell
cd .\flutter
flutter run
```

초기 설정 화면부터 실행:

```powershell
cd .\flutter
flutter run --dart-define=FORCE_ONBOARDING=true
```

## 18. Firebase Functions 배포

Functions를 다시 배포하려면 프로젝트 루트에서 실행합니다.

```powershell
cd .\
firebase deploy --only functions --project capstone-cleanair-2026
```

Functions는 다음 역할을 맡습니다.

- 센서 데이터 수신
- IAQI 계산
- 알림 처리
- 방재 판단
- Slack 알림 전송
- 플러그 명령 처리
- AI 공기질 추천 생성

## 19. 웹 상황판 배포

```powershell
cd .\
firebase deploy --only hosting --project capstone-cleanair-2026
```

배포 후 아래 주소에서 확인합니다.

```text
https://capstone-cleanair-2026.web.app
```

## 20. 필요한 환경 변수

Functions의 실제 비밀값은 GitHub에 올리지 않습니다. Functions를 새로 배포할 때는 로컬 `functions/.env` 또는 Firebase 환경 변수에 값을 설정해야 합니다.

| 변수 | 용도 |
| --- | --- |
| `INGEST_API_KEY` | 센서 데이터 수신 인증 |
| `MQTT_URL` | MQTT 서버 주소 |
| `MQTT_USERNAME` | MQTT 사용자 이름 |
| `MQTT_PASSWORD` | MQTT 비밀번호 |
| `GEMINI_API_KEY` | AI 추천 생성 |
| `GEMINI_MODEL` | 사용할 Gemini 모델 |
| `SLACK_CLIENT_ID` | Slack 앱 OAuth |
| `SLACK_CLIENT_SECRET` | Slack 앱 OAuth |
| `SLACK_REDIRECT_URI` | Slack 연결 완료 후 돌아오는 주소 |

## 21. 자주 생기는 문제

| 문제 | 확인할 것 |
| --- | --- |
| 앱에서 센서값이 안 보임 | 센서 펌웨어, Wi-Fi, Firebase 프로젝트, 센서 ID 확인 |
| PIN 등록이 안 됨 | 센서 화면의 PIN, Firebase Functions 배포 상태 확인 |
| mDNS 검색이 안 됨 | 휴대폰과 센서가 같은 Wi-Fi인지 확인 |
| 위치 검색이 안 됨 | 네트워크, Kakao 키와 도메인 설정 확인 |
| CSV 저장 실패 | Android 저장 권한, `Download/AirGradient` 폴더 확인 |
| 플러그 로컬 제어 실패 | IP 주소와 같은 Wi-Fi 여부 확인 |
| MQTT 제어 실패 | Topic 중복, Host, Port, TLS, User, Password 확인 |
| 플러그 하나만 움직임 | 두 플러그의 Topic이 겹치지 않았는지 확인 |
| Slack 메시지가 안 옴 | 앱에서 Slack 연결 확인 후 테스트 버튼 실행 |
| 웹 상황판 로그인이 안 됨 | Google 로그인 제공업체, 관리자 권한, 브라우저 팝업 차단 확인 |
| 웹 지도 안 보임 | Kakao JavaScript 키와 허용 도메인 확인 |

## 22. 최종 확인 순서

1. 앱 설치가 되는지 확인합니다.
2. 센서 펌웨어 설치 후 PIN이 표시되는지 확인합니다.
3. 앱에서 센서를 등록합니다.
4. 메인 화면에 실시간 값이 표시되는지 확인합니다.
5. 상세 그래프와 CSV 저장을 확인합니다.
6. 알림 설정과 Slack 테스트를 확인합니다.
7. 플러그 로컬 제어를 확인합니다.
8. MQTT 원격 제어를 확인합니다.
9. 방재모드 상황 요약과 웹 상황판 전송을 확인합니다.
10. 웹 상황판에서 센서, 플러그, 이벤트, 상황 종료를 확인합니다.

이 순서까지 통과하면 앱, 센서, 플러그, 웹 상황판이 하나의 시스템으로 연결된 상태입니다.
