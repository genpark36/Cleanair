# CleanAir AirGradient 펌웨어 설치

1. AirGradient 센서를 USB로 PC에 연결합니다.
2. `install_cleanair_firmware.bat`을 더블클릭합니다.
3. 표시되는 COM 포트를 선택합니다.
4. 설치가 끝나면 센서가 재부팅됩니다.

이 폴더는 설치 패키지입니다. 펌웨어 개발 소스가 아니라, 센서에 바로 설치할 바이너리와 설치 스크립트만 들어 있습니다.

현재 펌웨어는 AirGradient ONE 기본 센서값에 더해 DFRobot SEN0466 CO 센서를 선택적으로 지원합니다. CO 센서를 I2C에 연결한 경우 부팅 시 자동으로 감지하고 Firebase payload에 `co` 값을 함께 보냅니다. CO 센서가 없으면 기본 AirGradient 센서처럼 PM2.5, CO2, TVOC, NOx, 온도, 습도만 전송합니다.

설치 후 시리얼 로그에서 아래 문구를 확인할 수 있습니다.

```text
Init optional CO sensor success
```

CO 센서가 연결되지 않은 경우에는 아래처럼 표시되며, 이 상태도 정상입니다.

```text
Optional CO sensor not found
```

센서 등록용 PIN은 Firebase relay 서버와 통신한 뒤 표시됩니다. 설치 후 PIN이 보이지 않으면 센서가 Wi-Fi에 연결되어 있는지 먼저 확인하고, 시리얼 로그에서 아래 흐름이 나오는지 확인합니다.

```text
Firebase sendDataToFirebase requestCode=true
Firebase HTTP Response code: 200
Pairing PIN: 123456
```

위 흐름이 나오면 펌웨어, Wi-Fi, Firebase relay 연결이 정상입니다.

설치 스크립트는 Python의 `esptool`을 사용합니다. 설치가 실패하면서 `esptool`을 찾지 못한다고 나오면 아래 명령으로 한 번만 설치합니다.

```powershell
python -m pip install esptool
```

