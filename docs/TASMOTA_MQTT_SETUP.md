# Tasmota MQTT 설정 가이드

이 문서는 Tasmota 플러그를 Cleanair 앱과 웹 상황판에서 원격으로 제어하기 위한 설정만 정리합니다. 같은 Wi-Fi 안에서만 제어할 때는 MQTT 설정이 필요하지 않습니다. 외부에서도 플러그 상태를 보고 ON/OFF 제어를 하려면 아래 설정을 맞춰야 합니다.

## 1. 먼저 알아둘 것

Cleanair의 플러그 제어 방식은 두 가지입니다.

| 방식 | 필요한 값 | 사용되는 상황 |
| --- | --- | --- |
| 로컬 HTTP | 플러그 IP 주소 | 휴대폰과 플러그가 같은 Wi-Fi에 있을 때 |
| MQTT | MQTT 서버 정보, 플러그 토픽 | 외부 네트워크에서도 플러그를 제어할 때 |

발표나 시연에서는 로컬 HTTP만으로도 기본 제어가 됩니다. 다만 “집 밖에서도 공기청정기나 대응 장치를 켠다”는 흐름을 보여주려면 MQTT까지 설정하는 편이 좋습니다.

## 2. 플러그마다 달라야 하는 값

가장 중요한 값은 **Topic**입니다. Topic은 플러그를 구분하는 이름입니다.

예시:

```text
cleanair_plug_01
cleanair_plug_02
cleanair_plug_03
```

플러그가 여러 개라면 Topic을 절대 겹치게 쓰면 안 됩니다. Topic이 겹치면 앱에서 한 플러그를 눌렀는데 다른 플러그가 반응하거나, 두 플러그 상태가 섞여 보일 수 있습니다.

추천 규칙은 간단합니다.

```text
cleanair_plug_01
cleanair_plug_02
cleanair_plug_03
```

앱에 등록할 때도 Tasmota에 입력한 Topic과 같은 값을 넣습니다.

## 3. Tasmota 화면에서 입력할 값

Tasmota 플러그 웹 설정으로 들어갑니다.

```text
http://플러그_IP
```

그다음 아래 메뉴로 이동합니다.

```text
Configuration -> Configure MQTT
```

입력값은 다음과 같습니다.

| Tasmota 항목 | 입력값 |
| --- | --- |
| Host | `functions/.env`의 `MQTT_URL`에서 호스트 부분 |
| Port | `8883` |
| MQTT TLS | `MQTT_URL`이 `mqtts://`로 시작하면 체크 |
| Client | `cleanair_plug_01_%06X`처럼 Topic 뒤에 `_%06X`를 붙임 |
| User | `functions/.env`의 `MQTT_USERNAME` |
| Password | `functions/.env`의 `MQTT_PASSWORD` |
| Topic | 앱에 등록할 플러그 Topic |
| Full Topic | `%prefix%/%topic%/` |

예를 들어 첫 번째 플러그라면 보통 이렇게 넣습니다.

```text
Client: cleanair_plug_01_%06X
Topic:  cleanair_plug_01
Full Topic: %prefix%/%topic%/
```

두 번째 플러그라면 Topic만 바꿉니다.

```text
Client: cleanair_plug_02_%06X
Topic:  cleanair_plug_02
Full Topic: %prefix%/%topic%/
```

입력이 끝나면 Save를 누르고 플러그가 재부팅될 때까지 기다립니다.

## 4. 연결 확인

Tasmota Console에서 아래 명령을 입력합니다.

```text
Status 6
```

정상 연결이면 `MqttHost`, `MqttPort`, `MqttClient`, `MqttUser`, `MqttCount`가 표시됩니다. `MqttCount`가 1 이상이면 MQTT 연결이 한 번 이상 성공한 상태입니다.

플러그 전원을 콘솔에서 직접 테스트할 때는 아래처럼 입력합니다.

```text
Power On
Power Off
```

콘솔에 `ON` 또는 `OFF`만 입력하면 Tasmota가 명령으로 인식하지 못할 수 있습니다.

## 5. HiveMQ 웹 클라이언트로 확인하는 방법

HiveMQ 웹 클라이언트에서 같은 서버와 계정으로 접속한 뒤 아래 토픽을 구독합니다.

```text
stat/cleanair_plug_01/#
tele/cleanair_plug_01/#
```

전원을 켜려면 메시지를 보냅니다.

```text
Topic:   cmnd/cleanair_plug_01/POWER
Message: ON
```

끄려면 메시지만 바꿉니다.

```text
Topic:   cmnd/cleanair_plug_01/POWER
Message: OFF
```

정상이라면 `stat/cleanair_plug_01/POWER` 쪽으로 `ON` 또는 `OFF` 응답이 옵니다.

## 6. 앱에 등록할 때

앱의 플러그 등록 또는 편집 화면에서 아래 값만 맞추면 됩니다.

| 앱 항목 | 입력값 |
| --- | --- |
| 이름 | 사용자가 알아볼 수 있는 이름 |
| 위치 | 설치 위치 |
| 로컬 IP | 같은 Wi-Fi에서 제어할 때 사용할 플러그 IP |
| MQTT Topic | Tasmota의 Topic과 같은 값 |
| 제어 방식 | 외부 제어까지 확인하려면 MQTT 또는 원격 제어 |

로컬 IP와 MQTT Topic을 둘 다 넣어두면 같은 Wi-Fi에서는 로컬 HTTP 제어를 확인할 수 있고, 외부 제어는 MQTT로 확인할 수 있습니다.

## 7. MQTT worker 실행

Functions 폴더에서 MQTT worker를 실행하면 플러그 명령과 응답을 Firestore 기록으로 남길 수 있습니다.

```powershell
cd functions
npm install
npm run worker:plug
```

Firebase Functions의 MQTT 직접 전송도 들어가 있지만, 시연 중에는 worker를 켜두는 편이 플러그 상태 확인과 제어 이력 확인이 안정적입니다.

## 8. 자주 생기는 문제

| 증상 | 확인할 것 |
| --- | --- |
| 앱에서 한 플러그만 움직인다 | 두 플러그의 Topic이 겹치지 않았는지 확인 |
| MQTT 연결이 안 된다 | Host, Port, TLS 체크, User, Password 확인 |
| HiveMQ에서 명령은 보냈는데 반응이 없다 | `cmnd/토픽/POWER` 형식인지 확인 |
| Tasmota 콘솔에서 `OFF`가 Unknown으로 나온다 | `Power Off`로 입력 |
| 앱에서는 저장했는데 웹 상황판에 늦게 보인다 | 앱 프로필/동기화 또는 Firestore 반영 상태 확인 |
| 전압/전류/전력이 안 보인다 | Tasmota 메인 화면에서 전력 값이 표시되는 모델인지 확인 |

## 9. 최소 확인 순서

1. Tasmota MQTT 화면에 Host, Port, TLS, User, Password, Topic을 입력합니다.
2. `Status 6`에서 MQTT 연결을 확인합니다.
3. HiveMQ 웹 클라이언트에서 `cmnd/토픽/POWER`로 ON/OFF를 테스트합니다.
4. 앱에 같은 Topic을 등록합니다.
5. 앱에서 ON/OFF를 눌러 실제 플러그가 반응하는지 확인합니다.
6. 웹 상황판에서도 같은 플러그가 보이고 제어되는지 확인합니다.

