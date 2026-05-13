import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:permission_handler/permission_handler.dart';

import 'setup_flow_scaffold.dart';

class OnboardingLocationScreen extends StatelessWidget {
  const OnboardingLocationScreen({
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
      step: 2,
      totalSteps: 3,
      onBack: onBack,
      onPrimary: () => _requestLocationPermission(context),
      primaryLabel: '위치 권한 허용',
      primaryIcon: Symbols.location_on,
      title: '깨끗한 공기의 시작',
      subtitle: '현재 위치를 허용하면 가까운 공식 측정소 비교와 위치 기반 설정을 더 정확하게 사용할 수 있습니다.',
      bottomExtra: TextButton(
        onPressed: onSkip ?? onNext,
        style: TextButton.styleFrom(
          foregroundColor: SetupColors.secondary,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
        child: const Text('나중에 하기'),
      ),
      children: const [
        SetupIconPlate(icon: Symbols.location_on),
        SizedBox(height: 28),
        SetupInfoCard(
          icon: Symbols.radar,
          title: '측정소 비교',
          body: '위치 권한은 가까운 공식 측정소를 찾고 실내외 차이를 비교하는 데 사용됩니다.',
        ),
      ],
    );
  }

  Future<void> _requestLocationPermission(BuildContext context) async {
    final status = await Permission.locationWhenInUse.request();
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (status.isGranted || status.isLimited) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('위치 권한이 허용되었습니다.')),
      );
      onNext?.call();
      return;
    }

    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          status.isPermanentlyDenied
              ? '설정에서 위치 권한을 허용하면 가까운 측정소 비교가 정확해집니다.'
              : '위치 권한 없이도 센서 등록은 계속할 수 있습니다.',
        ),
        action: status.isPermanentlyDenied
            ? const SnackBarAction(label: '설정', onPressed: openAppSettings)
            : null,
      ),
    );
    onNext?.call();
  }
}
