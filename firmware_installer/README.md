# CleanAir AirGradient 펌웨어 설치

1. AirGradient 센서를 USB로 PC에 연결합니다.
2. `install_cleanair_firmware.bat`을 더블클릭합니다.
3. 표시되는 COM 포트를 선택합니다.
4. 설치가 끝나면 센서가 재부팅됩니다.

이 폴더는 제출용 설치 패키지입니다. 펌웨어 개발 소스가 아니라, 센서에 바로 설치할 바이너리와 설치 스크립트만 들어 있습니다.

설치 스크립트는 Python의 `esptool`을 사용합니다. 설치가 실패하면서 `esptool`을 찾지 못한다고 나오면 아래 명령으로 한 번만 설치합니다.

```powershell
python -m pip install esptool
```

설치 후 앱의 `설정 > AirGradient 로컬 설정 > 펌웨어 확인`에서 펌웨어 버전과 센서 ID를 확인합니다.
