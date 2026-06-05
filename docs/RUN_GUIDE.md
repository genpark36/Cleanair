# Cleanair 실행 및 설정 가이드

이 문서는 Cleanair를 초기 상태에서 설치하고, 센서와 플러그와 웹 상황판까지 연결하는 순서를 정리한 문서이자, 사용자/개발자용 트러블슈팅 참고 매뉴얼입니다.

전체 흐름은 아래 순서로 진행합니다.

해당 문서에는 사용자 실행 및 개발자 유지보수에 대한 내용이 모두 포함되어 있습니다.
필요한 정보를 선별적으로 참고하시길 바랍니다.
(개발자용)의 경우, 구동을 위해 거쳐야할 절차가 아닌, 개발자 점검 및 오류 수정용 매뉴얼입니다.

```text
구동을 위해 반드시 거쳐야할 절차는 다음과 같습니다.
1. 앱 설치
2. AirGradient 센서 펌웨어 설치
3. 앱에서 센서 등록
4. 센서 위치 저장
5. 앱에서 실시간 데이터 확인
6. Tasmota 플러그 Wi-Fi 설정
7. 플러그 로컬 제어 확인
8. MQTT 원격 제어 설정
9. 알림, Slack, 방재모드 확인
10. 웹 상황판 확인
```

처음부터 순서대로 진행하면 됩니다. 중간에 문제가 생기면 마지막의 “문제 해결” 항목을 먼저 확인하세요.

## 1. 준비물

| 준비물 | 쓰임 |
| --- | --- |
| Android 휴대폰 | Cleanair 앱 실행 |
| Windows PC | 센서 펌웨어 설치, 필요 시 앱 빌드 |
| AirGradient ONE 센서 | 실내 공기질 측정 |
| USB 케이블 | 센서 펌웨어 설치 |
| Tasmota 스마트 플러그 | 공기청정기, 환기팬, 경광등 같은 장치 제어 |
| Wi-Fi 공유기 | 센서, 휴대폰, 플러그 연결 |
| Google 계정 | 앱과 웹 상황판 로그인 |
| Slack 워크스페이스 | 외부 알림을 받을 때 사용 |

APK만 설치해서 쓰면 Flutter SDK는 필요하지 않습니다. 앱을 직접 수정하거나 APK를 새로 빌드할 때만 Flutter SDK가 필요합니다.

## 2. 폴더 구성

GitHub에서 받은 `Cleanair` 폴더는 다음처럼 구성되어 있습니다.

| 경로 | 내용 |
| --- | --- |
| `release_apk/cleanair-final-release.apk` | Android 설치 파일 |
| `flutter/` | Flutter 앱 소스 |
| `functions/` | Firebase Functions |
| `web_dashboard/` | 웹 상황판 |
| `firmware_installer/` | AirGradient 센서 펌웨어 설치 패키지 |
| `docs/APP_OVERVIEW.md` | 앱 기능 설명 |
| `docs/RUN_GUIDE.md` | 실행 및 설정 가이드 |

명령어는 프로젝트 루트, 즉 `Cleanair` 폴더에서 실행한다고 가정합니다.

## 3. Android 앱 설치

APK 파일은 아래 위치에 있습니다.

```text
release_apk/cleanair-final-release.apk
```

설치 순서:

1. APK 파일을 Android 휴대폰으로 옮깁니다.
2. 휴대폰 파일 관리자에서 APK를 실행합니다.
3. Android가 설치를 막으면 “알 수 없는 앱 설치” 권한을 허용합니다.
4. 설치가 끝나면 Cleanair 앱을 실행합니다.

처음 실행하면 초기 설정 화면이 열립니다.

이미 한 번 설정한 앱을 다시 초기 설정 화면부터 확인하려면 Flutter로 실행할 때 아래 옵션을 사용합니다.

```powershell
cd .\flutter
flutter run --dart-define=FORCE_ONBOARDING=true
```

일반 실행은 아래 명령입니다.

```powershell
cd .\flutter
flutter run
```

Windows에서 `flutter` 명령이 잡히지 않으면 Flutter SDK가 설치된 경로의 실행 파일을 직접 사용합니다.

```powershell
C:\src\flutter\bin\flutter.bat run
```

## 4. AirGradient 센서 펌웨어 설치

Cleanair 앱과 연결하려면 AirGradient 센서에 Cleanair 펌웨어를 설치해야 합니다.

### 4.1 설치 파일

펌웨어 설치 패키지는 아래 폴더에 있습니다.

```text
firmware_installer/
```

| 파일 | 설명 |
| --- | --- |
| `install_cleanair_firmware.bat` | Windows에서 실행하는 설치 파일 |
| `install_cleanair_firmware.ps1` | PowerShell 설치 스크립트 |
| `firmware.bin` | 센서 본체 펌웨어 |
| `bootloader.bin` | ESP32 부트로더 |
| `partitions.bin` | 파티션 정보 |
| `boot_app0.bin` | 부팅 보조 파일 |

### 4.2 설치 순서

1. AirGradient 센서를 USB로 PC에 연결합니다.
2. `firmware_installer` 폴더를 엽니다.
3. `install_cleanair_firmware.bat`를 실행합니다.
4. COM 포트가 여러 개 보이면 AirGradient가 연결된 포트를 선택합니다.
5. 설치가 끝날 때까지 USB 케이블을 빼지 않습니다.
6. 설치가 끝나면 센서가 재부팅됩니다.
7. 센서 화면에 PIN이 표시되는지 확인합니다.

PowerShell에서 직접 실행할 수도 있습니다.

```powershell
cd .\firmware_installer
.\install_cleanair_firmware.bat
```

설치 도중 `esptool`을 찾지 못한다는 메시지가 나오면 PC에 esptool이 없는 상태입니다. 한 번만 설치하면 됩니다.

```powershell
python -m pip install esptool
```

### 4.3 센서가 보내는 값

현재 펌웨어는 다음 값을 Firebase로 전송합니다.

| 값 | 단위/형식 |
| --- | --- |
| PM2.5 | ug/m3 |
| CO2 | ppm |
| TVOC | index |
| NOx | index |
| 온도 | degC |
| 습도 | % |

CO 센서는 AirGradient ONE 기본 구성에 포함되어 있지 않습니다.

앱, 웹, Firebase Functions는 `co` 값을 받을 준비가 되어 있습니다. SEN0466 같은 CO 센서를 추가로 장착할 경우 펌웨어에서 CO 값을 읽어 Firebase payload에 `co` 필드로 보내면 됩니다.

CO 센서가 없을 때는 `co: 0`을 보내면 안 됩니다. CO 센서가 없는 상태와 실제 CO 농도 0ppm이 구분되지 않기 때문입니다. 센서가 정상적으로 읽힐 때만 `co` 값을 보내는 방식이 맞습니다.

## 5. 앱에서 센서 등록

앱을 처음 실행하면 센서 등록 흐름이 나옵니다.

### 5.1 PIN 등록

1. 센서 화면에 표시된 PIN을 확인합니다.
2. 앱에서 PIN 등록을 선택합니다.
3. PIN을 입력합니다.
4. 등록이 끝나면 센서가 앱에 연결됩니다.

PIN 등록은 센서와 사용자 계정을 연결하는 기본 방식입니다.

### 5.2 주변 센서 검색

같은 Wi-Fi에 있는 센서를 자동으로 찾을 수도 있습니다.

1. 휴대폰과 센서를 같은 Wi-Fi에 연결합니다.
2. 앱에서 주변 센서 검색을 선택합니다.
3. 검색된 센서를 선택합니다.
4. 연결 완료 메시지를 확인합니다.

주변 센서 검색은 같은 네트워크 안에서만 동작합니다. 휴대폰이 모바일 데이터 상태이거나 센서와 다른 Wi-Fi에 있으면 검색되지 않을 수 있습니다.

## 6. 센서 위치 저장

센서 등록이 끝나면 위치를 저장합니다. 위치 정보는 앱 알림, 방재모드, 웹 상황판, 플러그 연결에 사용됩니다.

저장 항목:

| 항목 | 예시 |
| --- | --- |
| 공간 이름 | 방, 거실, 실험실, 어린이집 1층 |
| 시설 유형 | 주거, 교육시설, 사무실, 실험실 |
| 주소 | 지도 검색 또는 직접 입력 |
| 층 | 1층, 2층, 지하 1층 |
| 세부 위치 | 창가, 책상 옆, 복도, 주방 근처 |
| 설치 메모 | 설치 상황 기록 |

주소 검색 버튼을 누르거나 키보드 엔터를 눌러 주소를 검색할 수 있습니다. 위치 권한을 허용하면 현재 위치 기준으로 지도를 이동할 수 있습니다.

센서가 여러 개라면 각 센서마다 위치를 따로 저장합니다. 그래야 알림과 웹 상황판에서 어느 공간의 센서인지 구분할 수 있습니다.

## 7. 메인 화면 확인

센서 등록과 위치 저장이 끝나면 메인 대시보드에서 실시간 값이 표시됩니다.

확인할 항목:

- IAQI 값
- PM2.5
- CO2
- TVOC
- NOx
- 온도
- 습도
- 공기질 요약
- 방재 상태 요약

값이 표시되지 않으면 센서가 Firebase로 데이터를 보내지 못하고 있거나, 앱이 다른 센서를 보고 있을 수 있습니다.

## 8. 상세 그래프와 CSV 저장

상세 화면에서는 각 지표의 시간 흐름을 볼 수 있습니다.

사용 순서:

1. 상세 탭으로 이동합니다.
2. PM2.5, CO2, TVOC, NOx, IAQI, CO 등 보고 싶은 지표를 선택합니다.
3. 10분, 1시간, 6시간, 24시간, 주간 범위를 선택합니다.
4. 점 모드로 특정 시각의 값을 확인합니다.
5. 구간 모드로 일정 범위의 최대, 최소, 평균, 중앙값을 확인합니다.
6. 필요한 경우 CSV 저장을 누릅니다.

그래프 배경 색상은 시간 구간이 아니라 수치 기준 구간을 뜻합니다. 같은 시간 안에서도 값이 기준을 넘으면 해당 값이 놓인 Y축 구간에 맞춰 색이 표시됩니다.

CSV 파일은 Android 기준으로 아래 폴더에 저장됩니다.

```text
Download/AirGradient
```

최근 30일 전체 데이터가 없더라도, 30일 안에 실제로 존재하는 데이터는 가능한 만큼 저장됩니다.

## 9. 알림 설정

알림 설정에서는 일반 공기질 알림, 방재 알림, 플러그 알림, Slack 외부 알림을 설정합니다.

### 9.1 일반 공기질 알림

항목별로 알림 기준을 조절할 수 있습니다.

| 항목 | 알림 기준 예시 |
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
4. Slack 워크스페이스 주소를 입력합니다.
5. Slack에 로그인합니다.
6. 알림을 받을 채널을 선택하고 허용합니다.
7. 앱으로 돌아와 테스트 전송을 실행합니다.
8. Slack 채널에 테스트 메시지가 오면 연결이 완료된 것입니다.

워크스페이스 주소는 Slack의 브라우저 주소창에서 확인할 수 있습니다.

```text
https://워크스페이스이름.slack.com
```

Slack 앱이 해당 워크스페이스에 설치되어 있지 않으면 연결이 실패합니다. 이 경우 Slack 앱 설정에서 워크스페이스 설치를 먼저 완료해야 합니다.

## 10. Tasmota 플러그 초기 설정

Tasmota 플러그를 처음 꽂으면 플러그가 자체 Wi-Fi를 엽니다.

초기 설정 순서:

1. 휴대폰이나 PC에서 Tasmota 플러그 Wi-Fi에 접속합니다.
2. 브라우저에서 아래 주소를 엽니다.

```text
http://192.168.4.1/
```

3. 사용할 Wi-Fi를 선택합니다.
4. Wi-Fi 비밀번호를 입력하고 저장합니다.
5. 플러그가 재부팅될 때까지 기다립니다.
6. 공유기나 Tasmota 화면에서 플러그에 할당된 IP를 확인합니다.

`192.168.4.1`은 초기 설정 모드에서만 쓰는 주소입니다. Wi-Fi 연결이 끝난 뒤에는 공유기가 할당한 플러그 IP로 접속합니다.

```text
http://플러그_IP
```

## 11. 앱에서 플러그 등록

앱의 플러그 탭에서 플러그를 등록합니다.

입력 항목:

| 항목 | 설명 |
| --- | --- |
| 이름 | 앱에 표시할 이름 |
| 위치 | 플러그가 설치된 공간 |
| 로컬 IP | 같은 Wi-Fi에서 제어할 때 사용하는 IP |
| MQTT Topic | 외부 제어를 위한 플러그 고유 토픽 |
| 자동 제어 기준 | 어떤 지표를 기준으로 켜고 끌지 설정 |

플러그가 여러 개라면 이름과 MQTT Topic이 겹치지 않게 설정합니다.

권장 Topic:

```text
cleanair_plug_01
cleanair_plug_02
cleanair_plug_03
cleanair_plug_XX
```
XX는 숫자를 임의로 설정하면 됩니다.(단, 04이후의 숫자를 권장합니다. 01-03은 개발 과정에서 사용하였음.)
같은 Topic을 두 플러그에 넣으면 두 플러그가 같은 명령을 받을 수 있고, 앱에서도 상태가 섞여 보일 수 있습니다.

## 12. 로컬 HTTP 플러그 제어

같은 Wi-Fi 안에서 제어할 때는 로컬 HTTP 방식이 가장 단순합니다.

1. 휴대폰과 플러그를 같은 Wi-Fi에 연결합니다.
2. Tasmota 플러그 IP를 확인합니다.
3. 앱의 플러그 등록 화면에 IP를 입력합니다.
4. 연결 테스트를 누릅니다.
5. ON/OFF 테스트를 실행합니다.

IP가 맞는지 확인하려면 브라우저에서 아래 주소를 열어봅니다.

```text
http://플러그_IP
```

Tasmota 화면이 열리면 IP는 맞습니다.

## 13. MQTT 플러그 제어

MQTT를 설정하면 같은 Wi-Fi가 아니어도 플러그를 제어할 수 있습니다.

### 13.1 Tasmota MQTT 설정

Tasmota 웹 화면에서 아래 메뉴로 이동합니다.

```text
Configuration -> Configure MQTT
```

MQTT 메뉴가 보이지 않으면 Tasmota Console에서 아래 명령을 입력한 뒤 재부팅합니다.

```text
SetOption3 1
Restart 1
```

재부팅 뒤 다시 `Configuration`으로 들어가면 MQTT 메뉴가 나타납니다.

입력 항목:

| Tasmota 항목 | 입력값 |
| --- | --- |
| Host | 7d18e3d75dbb4d12aa5951049f5868d2.s1.eu.hivemq.cloud |
| Port | 8883 |
| MQTT TLS | 체크 |
| Client | `cleanair_plug_01_%06X`처럼 Topic 뒤에 `_%06X` 추가 |
| User | Capstone |
| Password | Capstone1 |
| Topic | 앱에 등록할 플러그 Topic |
| Full Topic | `%prefix%/%topic%/` |

Host, User, Password는 Cleanair에서 사용하는 MQTT 서버 정보와 같아야 합니다. 앱에 등록하는 Topic과 Tasmota에 입력하는 Topic도 같아야 합니다.

1번 플러그 예시:

```text
Client: cleanair_plug_01_%06X
Topic: cleanair_plug_01
Full Topic: %prefix%/%topic%/
```

2번 플러그:

```text
Client: cleanair_plug_02_%06X
Topic: cleanair_plug_02
Full Topic: %prefix%/%topic%/
```

3번 플러그:

```text
Client: cleanair_plug_03_%06X
Topic: cleanair_plug_03
Full Topic: %prefix%/%topic%/
```

비밀번호 칸에 `****`가 보여도 실제 비밀번호가 자동으로 새 설정에 적용된다는 뜻 아닙니다. 새 플러그 등록 시 비밀번호(Capstone1)를 직접 다시 입력한 뒤 저장해야 합니다.

저장 후에는 플러그가 MQTT 서버에 다시 연결될 때까지 10~30초 정도 기다립니다. 연결이 제대로 되었는지는 Console의 `Status 6`으로 확인합니다.

### 13.2 MQTT 연결 확인

Tasmota Console에서 아래 명령을 입력합니다.

```text
Status 6
```

정상이라면 `MqttHost`, `MqttPort`, `MqttClient`, `MqttUser`, `MqttCount`가 표시됩니다. `MqttCount`가 1 이상이면 연결이 한 번 이상 성공한 것입니다.

플러그 전원 테스트:

```text
Power On
Power Off
```

`ON` 또는 `OFF`만 입력하면 Tasmota가 명령으로 인식하지 못할 수 있습니다. 반드시 `Power On`, `Power Off` 형태로 입력합니다.

### 13.3 MQTT 연결 실패

아래 로그가 반복되면 MQTT 접속이 실패한 상태입니다.

```text
MQT: Connect failed ..., rc 5
```

`rc 5`는 보통 인증 실패입니다.

확인 순서:

1. Host에 `mqtts://`를 붙이지 않았는지 확인합니다.
2. Port가 `8883`인지 확인합니다.
3. MQTT TLS가 체크되어 있는지 확인합니다.
4. User가 정확한지 확인합니다.
5. Password를 `****` 그대로 두지 말고 실제 비밀번호로 다시 입력합니다.
6. Topic이 다른 플러그와 겹치지 않는지 확인합니다.
7. 저장 후 플러그를 재시작합니다.

### 13.4 HiveMQ 웹 클라이언트 테스트(개발자용)

MQTT 웹 클라이언트에서 아래 토픽을 구독합니다.

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

정상이라면 아래 토픽으로 응답이 옵니다.

```text
stat/cleanair_plug_01/POWER
```

메시지는 `ON` 또는 `OFF`입니다.

### 13.5 MQTT worker 실행(개발자용)

MQTT 명령과 플러그 응답을 Firebase에 기록하려면 MQTT worker를 실행합니다.

```powershell
cd .\functions
npm install
npm run worker:plug
```

시연이나 장시간 테스트 중에는 worker를 켜두는 편이 좋습니다. 플러그 상태와 제어 이력이 더 안정적으로 기록됩니다.

## 14. 플러그 자동 제어

자동 제어는 공기질 지표가 기준을 넘으면 플러그를 켜고, 회복 기준 아래로 내려가면 끄는 방식입니다.

설정 항목:

| 항목 | 설명 |
| --- | --- |
| 기준 지표 | IAQI, CO2, PM2.5, TVOC, NOx 등 |
| 켜는 기준 | 이 값 이상이면 플러그 ON |
| 끄는 기준 | 이 값 이하로 회복되면 플러그 OFF |
| 최소 유지 시간 | 너무 자주 켜지고 꺼지는 것을 막기 위한 시간 |

켜는 기준과 끄는 기준을 다르게 두면 기준선 근처에서 플러그가 계속 반복 동작하는 일을 줄일 수 있습니다.

예시:

```text
CO2 켜기 기준: 1200 ppm
CO2 끄기 기준: 900 ppm
최소 유지 시간: 3분
```

이 설정에서는 CO2가 1200ppm 이상이면 플러그가 켜지고, 900ppm 이하로 내려간 뒤 최소 유지 시간이 지나야 꺼집니다.

## 15. 방재모드

방재모드는 단순히 공기질이 나쁜 상태와 화재 의심 패턴을 구분하기 위해 사용합니다.

확인 항목:

- 현재 방재 단계
- 주요 관측값
- 최근 5분 변화량
- 센서 위치
- 연결된 플러그 위치
- 상황 요약
- 웹 상황판 전송
- 119 전화 화면 열기

CO 센서가 없는 기본형에서는 PM2.5, CO2, TVOC, NOx, 온도 변화 등을 중심으로 판단합니다. CO 센서가 연결되어 `co` 값이 들어오면 CO 위험도 함께 반영됩니다.

방재모드에서 상황 요약을 누르면 내용을 복사하거나 다른 앱으로 공유할 수 있습니다. 메시지는 현장 확인과 신고 판단에 필요한 위치, 센서값, 판단 단계, 연결 장치 정보를 담습니다.

## 16. 웹 상황판

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
6. 앱에서 방재 상황을 웹 상황판으로 전송합니다.
7. 웹 상황판에 긴급 배너와 이벤트가 뜨는지 확인합니다.
8. 확인이 끝나면 상황 종료를 누릅니다.

웹 상황판에서도 플러그 ON/OFF 제어와 제어 이력 CSV 저장을 할 수 있습니다.

## 17. 앱 빌드(개발자용)

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

배포용 APK 위치에 반영하려면 빌드된 파일을 아래 경로로 복사합니다.

```text
release_apk/cleanair-final-release.apk
```

## 18. Firebase Functions 배포(개발자용)

Functions를 다시 배포하려면 프로젝트 루트에서 실행합니다.

```powershell
firebase deploy --only functions --project capstone-cleanair-2026
```

특정 함수만 배포할 수도 있습니다.

```powershell
firebase deploy --only functions:ingest --project capstone-cleanair-2026
firebase deploy --only functions:generateAiRecommendation --project capstone-cleanair-2026
```

Functions 역할:

- 센서 데이터 수신
- IAQI 계산
- 알림 처리
- 방재 판단
- Slack 알림 전송
- 플러그 명령 처리
- AI 공기질 추천 생성

## 19. 웹 상황판 배포(개발자용)

```powershell
firebase deploy --only hosting --project capstone-cleanair-2026
```

배포 후 아래 주소에서 확인합니다.

```text
https://capstone-cleanair-2026.web.app
```

## 20. 환경 변수(개발자용)

Functions를 새로 배포할 때는 `functions/.env` 또는 Firebase 환경 변수에 필요한 값이 있어야 합니다.

| 변수 | 쓰임 |
| --- | --- |
| `INGEST_API_KEY` | 센서 데이터 수신 인증 |
| `MQTT_URL` | MQTT 서버 주소 |
| `MQTT_USERNAME` | MQTT 사용자 이름 |
| `MQTT_PASSWORD` | MQTT 비밀번호 |
| `GEMINI_API_KEY` | AI 공기질 추천 생성 |
| `GEMINI_MODEL` | 사용할 Gemini 모델 |
| `SLACK_CLIENT_ID` | Slack 앱 OAuth |
| `SLACK_CLIENT_SECRET` | Slack 앱 OAuth |
| `SLACK_REDIRECT_URI` | Slack 연결 완료 후 돌아오는 주소 |

환경 변수가 빠지면 해당 기능만 동작하지 않습니다. 예를 들어 Slack 값이 없으면 Slack 연결이 실패하고, Gemini 키가 없으면 AI 추천이 생성되지 않습니다.

## 21. 문제 해결

### 앱에서 센서값이 안 보임

확인할 것:

1. 센서가 Wi-Fi에 연결되어 있는지 확인합니다.
2. 센서 화면에 PIN이나 측정값이 표시되는지 확인합니다.
3. 앱에서 선택된 센서가 실제 센서와 같은지 확인합니다.
4. Firebase Functions가 배포되어 있는지 확인합니다.(개발자용)
5. 앱을 완전히 종료한 뒤 다시 실행합니다.

### PIN 등록이 안 됨

확인할 것:

1. 센서 화면의 PIN을 다시 확인합니다.
2. PIN 입력 중 공백이 들어가지 않았는지 확인합니다.
3. 센서 펌웨어가 Cleanair 펌웨어인지 확인합니다.
4. Firebase Functions의 `claimDevice`, `registerDevice`가 배포되어 있는지 확인합니다.(개발자용)

### 주변 센서 검색이 안 됨

확인할 것:

1. 휴대폰과 센서가 같은 Wi-Fi인지 확인합니다.
2. 휴대폰이 모바일 데이터만 쓰고 있지 않은지 확인합니다.
3. 공유기에서 mDNS를 막고 있지 않은지 확인합니다.
4. 센서가 부팅된 뒤 1분 정도 기다렸다가 다시 검색합니다.

### 위치 검색이 안 됨

확인할 것:

1. 인터넷 연결을 확인합니다.
2. 브라우저에서 위치 정보 사용 권한을 허용하였는지 확인합니다.
3. Kakao JavaScript 키와 REST 키 설정을 확인합니다.(개발자용)
4. 웹 상황판을 쓴다면 허용 도메인에 현재 도메인이 등록되어 있는지 확인합니다.(개발자용)

### CSV 저장 실패

확인할 것:

1. Android 저장 권한을 확인합니다.
2. `Download/AirGradient` 폴더가 생성되는지 확인합니다.
3. 선택한 기간에 데이터가 있는지 확인합니다.
4. 데이터가 적어도 있는 만큼 저장되는지 확인합니다.

### 플러그 로컬 제어 실패

확인할 것:

1. 휴대폰과 플러그가 같은 Wi-Fi인지 확인합니다.
2. 플러그 IP가 맞는지 확인합니다.
3. 브라우저에서 `http://플러그_IP`가 열리는지 확인합니다.
4. 앱의 플러그 정보에 IP가 저장되어 있는지 확인합니다.

### MQTT 제어 실패

확인할 것:

1. Tasmota Console에서 `Status 6`을 실행합니다.
2. `MqttHost`가 비어 있지 않은지 확인합니다.
3. `MqttCount`가 증가하는지 확인합니다.
4. Port가 `8883`인지 확인합니다.
5. MQTT TLS가 체크되어 있는지 확인합니다.
6. 비밀번호 칸에 실제 비밀번호를 다시 입력합니다.
7. Topic이 앱에 등록한 Topic과 같은지 확인합니다.
8. 두 플러그가 같은 Topic을 쓰지 않는지 확인합니다.

MQTT 메뉴 자체가 보이지 않으면 Console에서 아래 명령을 실행합니다.

```text
SetOption3 1
Restart 1
```

재부팅 후에도 MQTT 메뉴가 없으면 현재 설치된 Tasmota 펌웨어가 MQTT 기능을 포함하지 않는 빌드일 수 있습니다. 이 경우 MQTT가 포함된 Tasmota 빌드로 다시 설치해야 합니다.

### 플러그 하나만 움직임

확인할 것:

1. 두 플러그의 Topic이 서로 다른지 확인합니다.
2. 앱에 저장된 플러그 Topic이 서로 다른지 확인합니다.
3. IP가 서로 바뀌어 저장되지 않았는지 확인합니다.
4. HiveMQ 웹 클라이언트에서 각 Topic에 따로 명령을 보내봅니다.(개발자용)

### Slack 메시지가 안 옴

확인할 것:

1. 앱에서 Slack 연결이 완료되어 있는지 확인합니다.
2. Slack 채널을 선택했는지 확인합니다.
3. Slack 앱이 워크스페이스에 설치되어 있는지 확인합니다.
4. Functions 환경 변수의 Slack 값이 설정되어 있는지 확인합니다.
5. 앱에서 테스트 전송을 실행합니다.

### 웹 상황판 로그인이 안 됨(개발자용)

확인할 것:

1. Firebase Authentication에서 Google 로그인이 켜져 있는지 확인합니다.
2. OAuth 동의 화면이 게시 상태인지 확인합니다.
3. 브라우저 팝업 차단을 해제합니다.(사용자)
4. 웹 상황판 배포 도메인이 Firebase Auth 승인 도메인에 포함되어 있는지 확인합니다.

### 웹 지도 안 보임(개발자용)

확인할 것:

1. Kakao JavaScript 키가 맞는지 확인합니다.
2. Kakao 개발자 콘솔에 웹 상황판 도메인이 등록되어 있는지 확인합니다.

## 22. 최종 확인 순서

아래 순서까지 통과하면 앱, 센서, 플러그, 웹 상황판이 하나의 시스템으로 연결된 상태입니다.

1. Android 앱 설치
2. AirGradient 펌웨어 설치
3. 센서 PIN 표시 확인
4. 앱에서 센서 등록
5. 센서 위치 저장
6. 메인 화면 실시간 값 확인
7. 상세 그래프 확인
8. CSV 저장 확인
9. 알림 설정 확인
10. Slack 테스트 전송 확인
11. Tasmota 플러그 Wi-Fi 설정
12. 로컬 HTTP ON/OFF 확인
13. MQTT ON/OFF 확인
14. 플러그 자동 제어 확인
15. 방재모드 상황 요약 확인
16. 웹 상황판에서 센서와 플러그 확인
17. 앱에서 웹 상황판으로 상황 전송
18. 웹 상황판에서 상황 종료 확인
