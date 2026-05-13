import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import 'setup_flow_scaffold.dart';

class SensorCompleteScreen extends StatelessWidget {
  const SensorCompleteScreen({super.key, this.onBack, this.onDone});

  final VoidCallback? onBack;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return SetupFlowScaffold(
      step: 6,
      totalSteps: 6,
      onBack: onBack,
      onPrimary: onDone,
      primaryLabel: '설치 위치 등록하기',
      primaryIcon: Symbols.chevron_right,
      title: '센서 연결 완료',
      subtitle: '센서가 앱에 연결되었습니다. 설치 위치를 등록하면 대시보드, 알림, 비교 화면에 함께 반영됩니다.',
      children: const [
        _CompleteMark(),
        SizedBox(height: 30),
        SetupInfoCard(
          icon: Symbols.air,
          title: '실시간 공기질 분석',
          body: '연결된 센서의 Firebase 측정값을 기존 앱 파이프라인으로 받아옵니다.',
        ),
        SizedBox(height: 14),
        SetupInfoCard(
          icon: Symbols.notifications_active,
          title: '알림과 위치 연동',
          body: '다음 단계에서 공간 위치를 저장하면 경보와 상황 기록에 같은 위치 정보가 사용됩니다.',
        ),
      ],
    );
  }
}

class _CompleteMark extends StatelessWidget {
  const _CompleteMark();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 190,
        height: 190,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 178,
              height: 178,
              decoration: BoxDecoration(
                color: SetupColors.primaryFixed.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 132,
              height: 132,
              decoration: const BoxDecoration(
                color: SetupColors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1600B4D8),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Symbols.air_purifier_gen,
                size: 72,
                fill: 1,
                color: SetupColors.primary,
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      SetupColors.primary,
                      SetupColors.primaryContainer,
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: SetupColors.white, width: 4),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x3300B4D8),
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Symbols.check,
                  color: SetupColors.white,
                  size: 30,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
