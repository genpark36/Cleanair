import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import 'setup_flow_scaffold.dart';

class SensorWifiScreen extends StatelessWidget {
  const SensorWifiScreen({super.key, this.onBack, this.onNext});

  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return SetupFlowScaffold(
      step: 3,
      totalSteps: 6,
      onBack: onBack,
      onPrimary: onNext,
      primaryLabel: '센서 Wi-Fi에 연결했어요',
      title: '휴대폰을 센서에 연결',
      subtitle: '휴대폰 Wi-Fi 설정에서 airgradient로 시작하는 센서 네트워크를 선택해 주세요.',
      children: const [
        _WifiPreviewCard(),
        SizedBox(height: 18),
        SetupInfoCard(
          icon: Symbols.key,
          title: '센서 네트워크 비밀번호',
          body: '비밀번호는 cleanair입니다. 자동 페이지가 뜨지 않으면 다음 화면에서 직접 설정 페이지를 엽니다.',
        ),
      ],
    );
  }
}

class _WifiPreviewCard extends StatelessWidget {
  const _WifiPreviewCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: SetupColors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1200B4D8),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: const Column(
        children: [
          _WifiRow(
            icon: Symbols.settings_input_antenna,
            title: 'airgradient-센서ID',
            subtitle: '연결할 센서 네트워크',
            active: true,
          ),
          SizedBox(height: 10),
          _WifiRow(
            icon: Symbols.wifi,
            title: 'Home_WiFi_5G',
            subtitle: '5GHz 전용 네트워크는 사용하지 않습니다',
          ),
        ],
      ),
    );
  }
}

class _WifiRow extends StatelessWidget {
  const _WifiRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.active = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: active
            ? SetupColors.primaryFixed.withValues(alpha: 0.45)
            : SetupColors.low,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: SetupColors.primary, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: SetupColors.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: SetupColors.secondary,
                  ),
                ),
              ],
            ),
          ),
          if (active)
            const Icon(
              Symbols.check_circle,
              fill: 1,
              color: SetupColors.primaryContainer,
            ),
        ],
      ),
    );
  }
}
