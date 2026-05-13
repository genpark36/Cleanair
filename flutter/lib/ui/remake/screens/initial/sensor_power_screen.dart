import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import 'setup_flow_scaffold.dart';

class SensorPowerScreen extends StatelessWidget {
  const SensorPowerScreen({super.key, this.onBack, this.onNext});

  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return SetupFlowScaffold(
      step: 2,
      totalSteps: 6,
      onBack: onBack,
      onPrimary: onNext,
      primaryLabel: '전원을 켰어요',
      title: '센서 전원 켜기',
      subtitle: '전원을 연결하고 10~20초 정도 기다리면 센서가 설정용 Wi-Fi 신호를 만듭니다.',
      bottomExtra: TextButton.icon(
        onPressed: () => _showPowerHelp(context),
        icon: const Icon(Symbols.help, size: 18),
        label: const Text('전원이 켜지지 않나요?'),
        style: TextButton.styleFrom(
          foregroundColor: SetupColors.secondary,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      children: const [
        SetupIconPlate(icon: Symbols.power_settings_new),
        SizedBox(height: 28),
        SetupInfoCard(
          icon: Symbols.settings_input_antenna,
          title: '신호 확인',
          body: '잠시 뒤 휴대폰 Wi-Fi 목록에서 airgradient-센서ID 형태의 네트워크가 보입니다.',
        ),
        SizedBox(height: 14),
        SetupInfoCard(
          icon: Symbols.cable,
          title: '전원 방식',
          body: 'USB-A 전원 어댑터나 PC USB 포트에 센서를 연결하면 됩니다.',
        ),
      ],
    );
  }

  void _showPowerHelp(BuildContext context) {
    const guideUrl = 'https://www.airgradient.com/documentation/';
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('전원 확인'),
          content: const Text(
            'USB-A 전원 어댑터나 PC USB 포트에 센서를 연결해 주세요.\n\n'
            '전원이 들어오지 않으면 AirGradient 회로가 설명서대로 조립되었는지 확인해야 합니다. '
            '회로 조립 설명서 링크를 복사해 브라우저에서 열 수 있습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기'),
            ),
            FilledButton(
              onPressed: () {
                Clipboard.setData(const ClipboardData(text: guideUrl));
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('회로 조립 설명서 링크를 복사했습니다.')),
                );
              },
              child: const Text('링크 복사'),
            ),
          ],
        );
      },
    );
  }
}
