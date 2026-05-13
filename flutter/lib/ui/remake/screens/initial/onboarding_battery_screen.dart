import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:permission_handler/permission_handler.dart';

import 'setup_flow_scaffold.dart';

class OnboardingBatteryScreen extends StatelessWidget {
  const OnboardingBatteryScreen({
    super.key,
    this.onBack,
    this.onNext,
    this.onSkip,
  });

  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return SetupFlowScaffold(
      step: 1,
      totalSteps: 3,
      onBack: onBack,
      onPrimary: () => _requestBatteryOptimizationExclusion(context),
      primaryLabel: '최적화 제외 설정',
      primaryIcon: Symbols.bolt,
      title: '끊김 없는 모니터링',
      subtitle: '백그라운드 제한을 줄이면 공기질 변화와 위험 알림을 더 안정적으로 감시할 수 있습니다.',
      bottomExtra: TextButton(
        onPressed: onSkip ?? onNext,
        style: TextButton.styleFrom(
          foregroundColor: SetupColors.secondary,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
        child: const Text('나중에 하기'),
      ),
      children: const [
        SetupIconPlate(icon: Symbols.bolt),
        SizedBox(height: 28),
        SetupInfoCard(
          icon: Symbols.battery_charging_full,
          title: '배터리 최적화 제외',
          body: '기기 설정이 허용하는 범위에서 백그라운드 감시가 중단되지 않도록 요청합니다.',
        ),
      ],
    );
  }

  Future<void> _requestBatteryOptimizationExclusion(
    BuildContext context,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      if (!context.mounted) return;
      if (status.isGranted || status.isLimited) {
        messenger?.showSnackBar(
          const SnackBar(content: Text('배터리 최적화 제외가 허용되었습니다.')),
        );
      } else {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('기기 설정에서 배터리 제한을 해제하면 백그라운드 감시가 안정적입니다.'),
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('배터리 최적화 설정 화면을 열 수 없습니다. 기기 설정에서 직접 허용해 주세요.'),
          action: SnackBarAction(label: '설정', onPressed: openAppSettings),
        ),
      );
    }
    onNext?.call();
  }
}
