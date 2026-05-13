import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import 'setup_flow_scaffold.dart';

class SensorPrepScreen extends StatelessWidget {
  const SensorPrepScreen({super.key, this.onBack, this.onNext});

  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return SetupFlowScaffold(
      step: 1,
      totalSteps: 6,
      onBack: onBack,
      onPrimary: onNext,
      primaryLabel: '준비했어요',
      title: '센서 연결 준비',
      subtitle: '센서를 등록하기 전에 CleanAir 전용 펌웨어와 2.4GHz Wi-Fi 환경을 확인해 주세요.',
      children: const [
        SetupIconPlate(icon: Symbols.settings_input_component),
        SizedBox(height: 28),
        SetupInfoCard(
          icon: Symbols.usb,
          title: '펌웨어 설치',
          body:
              '제출 패키지의 firmware_installer 폴더에서 설치 파일을 실행합니다. 설치가 끝나면 센서가 자동으로 재부팅됩니다.',
        ),
        SizedBox(height: 14),
        SetupInfoCard(
          icon: Symbols.wifi,
          title: 'Wi-Fi 조건',
          body: '센서 설정에는 2.4GHz Wi-Fi가 필요합니다. 5GHz 전용 네트워크는 연결되지 않습니다.',
          tint: SetupColors.error,
        ),
        SizedBox(height: 14),
        SetupInfoCard(
          icon: Symbols.info,
          title: '설치가 끝난 뒤',
          body: '센서가 재부팅되면 휴대폰에서 센서 Wi-Fi에 연결한 뒤 다음 단계에서 인터넷 설정을 진행합니다.',
        ),
      ],
    );
  }
}
