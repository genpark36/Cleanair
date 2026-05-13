import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import 'setup_flow_scaffold.dart';

class SensorModeScreen extends StatelessWidget {
  const SensorModeScreen({
    super.key,
    this.onBack,
    this.onNext,
    this.onManualPin,
  });

  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onManualPin;

  @override
  Widget build(BuildContext context) {
    return SetupFlowScaffold(
      step: 5,
      totalSteps: 6,
      onBack: onBack,
      onPrimary: onNext,
      primaryLabel: '주변 센서 찾기',
      primaryIcon: Symbols.wifi_find,
      title: '연결 방식 선택',
      subtitle: '동일한 Wi-Fi에 연결된 센서를 자동으로 찾거나, 센서 화면의 PIN으로 직접 등록합니다.',
      children: [
        SetupOptionTile(
          icon: Symbols.wifi_find,
          title: '주변 센서 자동 감지',
          subtitle: '같은 Wi-Fi 네트워크에서 AirGradient 센서를 찾습니다.',
          selected: true,
          onTap: onNext,
        ),
        const SizedBox(height: 14),
        SetupOptionTile(
          icon: Symbols.dialpad,
          title: 'PIN 번호 직접 입력',
          subtitle: '센서 화면에 표시된 6자리 번호로 등록합니다.',
          onTap: onManualPin,
        ),
        const SizedBox(height: 18),
        const SetupInfoCard(
          icon: Symbols.info,
          title: '권장 순서',
          body: '자동 감지가 되지 않으면 센서 화면에 표시된 6자리 PIN으로 직접 등록하세요.',
        ),
      ],
    );
  }
}
