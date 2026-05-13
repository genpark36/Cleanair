import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../../services/push_notification_service_v2.dart';
import 'setup_flow_scaffold.dart';

class OnboardingNotificationsScreen extends StatelessWidget {
  const OnboardingNotificationsScreen({
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
      step: 3,
      totalSteps: 3,
      onBack: onBack,
      onPrimary: () => _requestNotificationPermission(context),
      primaryLabel: '알림 활성화',
      primaryIcon: Symbols.notifications,
      title: '중요한 알림을 놓치지 마세요',
      subtitle: '공기질이 나빠지거나 확인이 필요한 변화가 생기면 바로 알려드립니다.',
      bottomExtra: TextButton(
        onPressed: onSkip ?? onNext,
        style: TextButton.styleFrom(
          foregroundColor: SetupColors.secondary,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
        child: const Text('나중에 하기'),
      ),
      children: const [
        SetupIconPlate(icon: Symbols.notifications),
        SizedBox(height: 14),
        SetupInfoCard(
          icon: Symbols.warning,
          title: '위험 수치 알림',
          body: 'PM2.5, CO2, TVOC 등 주요 수치가 기준을 넘으면 알림을 받을 수 있습니다.',
        ),
        SizedBox(height: 10),
        SetupInfoCard(
          icon: Symbols.info,
          title: '알림 설정 동기화',
          body: '허용 후 이 휴대폰으로 알림을 받을 수 있도록 설정을 저장합니다.',
        ),
      ],
    );
  }

  Future<void> _requestNotificationPermission(BuildContext context) async {
    final status = await Permission.notification.request();
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (status.isGranted || status.isLimited) {
      try {
        await context
            .read<PushNotificationServiceV2>()
            .requestNotificationPermissionAndRefresh();
      } catch (_) {}
      if (!context.mounted) return;
      messenger?.showSnackBar(
        const SnackBar(content: Text('알림 권한이 허용되었습니다.')),
      );
      onNext?.call();
      return;
    }

    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          status.isPermanentlyDenied
              ? '설정에서 알림 권한을 허용하면 위험 수치 알림을 받을 수 있습니다.'
              : '알림 권한 없이도 앱 설정에서 다시 활성화할 수 있습니다.',
        ),
        action: status.isPermanentlyDenied
            ? const SnackBarAction(label: '설정', onPressed: openAppSettings)
            : null,
      ),
    );
    onNext?.call();
  }
}
