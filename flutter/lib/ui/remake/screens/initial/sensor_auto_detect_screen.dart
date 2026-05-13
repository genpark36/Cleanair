import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../services/airgradient_mdns_service.dart';
import '../../../../services/device_binding_service_v2.dart';
import '../../../../services/firestore_snapshot_service.dart';
import '../../../../services/push_notification_service_v2.dart';
import '../../../../state/air_quality_controller.dart';
import 'setup_flow_scaffold.dart';

class SensorAutoDetectScreen extends StatefulWidget {
  const SensorAutoDetectScreen({
    super.key,
    this.onBack,
    this.onNext,
    this.onManualPin,
  });

  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onManualPin;

  @override
  State<SensorAutoDetectScreen> createState() => _SensorAutoDetectScreenState();
}

class _SensorAutoDetectScreenState extends State<SensorAutoDetectScreen> {
  static const _airGradientIpPrefsKey = 'airgradient_local_ip_v1';

  final _mdnsService = AirGradientMdnsService();
  bool _scanning = false;
  bool _binding = false;
  String? _message;
  bool _success = false;
  List<DiscoveredAirGradientSensor> _sensors =
      const <DiscoveredAirGradientSensor>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    if (_scanning || _binding) return;
    setState(() {
      _scanning = true;
      _success = false;
      _message = null;
      _sensors = const <DiscoveredAirGradientSensor>[];
    });

    try {
      final sensors = await _mdnsService.discover(
        timeout: const Duration(seconds: 8),
      );
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _sensors = sensors;
        if (sensors.isEmpty) {
          _message = '같은 Wi-Fi에서 AirGradient 센서를 찾지 못했습니다.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _success = false;
        _message = '로컬 검색 실패 · Wi-Fi와 로컬 네트워크 권한을 확인해 주세요.';
      });
    }
  }

  Future<void> _bindSensor(DiscoveredAirGradientSensor sensor) async {
    if (_binding) return;
    final binding = context.read<DeviceBindingControllerV2>();
    final firestore = context.read<FirestoreSnapshotService>();
    final push = context.read<PushNotificationServiceV2>();
    final airController = context.read<AirQualityController>();

    setState(() {
      _binding = true;
      _message = null;
      _success = false;
    });

    try {
      final candidates = AirGradientMdnsService.sensorIdCandidates(sensor.id);
      final fallbackId = candidates.isNotEmpty ? candidates.first : sensor.id;
      final resolvedPath = await firestore.findFirstLiveSensorDocPath(
            candidates,
            perCandidateTimeout: const Duration(seconds: 2),
          ) ??
          'sensors/$fallbackId';
      final resolvedId = _sensorIdFromDocPath(resolvedPath);
      await binding.applyBinding(
        deviceId: resolvedId,
        firestoreDocPath: resolvedPath,
        localIp: sensor.ip?.trim() ?? '',
      );
      await firestore.setFirestoreDocPath(resolvedPath);
      await firestore.connect(forceReconnect: true);
      final hasFirstSnapshot = await firestore.waitForFirstSnapshot(
        timeout: const Duration(seconds: 12),
      );
      await airController.refreshHistoryFromFirestore();
      await push.updateSensorId(resolvedId);
      if (sensor.ip != null && sensor.ip!.trim().isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_airGradientIpPrefsKey, sensor.ip!.trim());
      }
      if (!mounted) return;
      setState(() {
        _binding = false;
        _success = true;
        _message = hasFirstSnapshot
            ? '센서 연결 완료 · $resolvedId'
            : '센서 등록 완료 · 클라우드 측정값 수신을 기다립니다.';
      });
      widget.onNext?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _binding = false;
        _success = false;
        _message = '센서 연결 실패 · 전원, Wi-Fi, Firestore 경로를 확인해 주세요.';
      });
    }
  }

  String _sensorIdFromDocPath(String path) {
    const prefix = 'sensors/';
    return path.startsWith(prefix) ? path.substring(prefix.length) : path;
  }

  @override
  Widget build(BuildContext context) {
    final hasSensor = _sensors.isNotEmpty;
    final busy = _scanning || _binding;
    final primaryLabel = _binding
        ? '연결 중'
        : _scanning
            ? '검색 중'
            : hasSensor
                ? '센서 연결'
                : 'PIN으로 등록';
    final primaryIcon = busy
        ? Symbols.progress_activity
        : hasSensor
            ? Symbols.sensors
            : Symbols.dialpad;
    final primaryAction = busy
        ? null
        : hasSensor
            ? () => unawaited(_bindSensor(_sensors.first))
            : widget.onManualPin;

    return SetupFlowScaffold(
      step: 6,
      totalSteps: 6,
      onBack: widget.onBack,
      onPrimary: primaryAction,
      primaryLabel: primaryLabel,
      primaryIcon: primaryIcon,
      title: _binding
          ? '센서 연결 중'
          : _scanning
              ? '주변 센서 검색'
              : hasSensor
                  ? '센서를 찾았어요'
                  : '센서를 찾지 못했어요',
      subtitle: _binding
          ? '발견된 센서를 앱과 Firestore 데이터 경로에 연결하고 있습니다.'
          : '같은 Wi-Fi 네트워크의 AirGradient 센서를 검색합니다.',
      bottomExtra: TextButton.icon(
        onPressed: busy ? null : () => unawaited(_scan()),
        icon: const Icon(Symbols.refresh, size: 18),
        label: const Text('다시 검색'),
        style: TextButton.styleFrom(
          foregroundColor: SetupColors.secondary,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      children: [
        _SearchStatusCard(
          scanning: _scanning,
          binding: _binding,
          success: _success,
          message: _message,
          sensors: _sensors,
        ),
        const SizedBox(height: 16),
        SetupOptionTile(
          icon: Symbols.dialpad,
          title: 'PIN 번호로 등록',
          subtitle: '자동 검색이 불안정하면 센서 화면의 6자리 번호를 입력합니다.',
          onTap: busy ? null : widget.onManualPin,
        ),
      ],
    );
  }
}

class _SearchStatusCard extends StatelessWidget {
  const _SearchStatusCard({
    required this.scanning,
    required this.binding,
    required this.success,
    required this.message,
    required this.sensors,
  });

  final bool scanning;
  final bool binding;
  final bool success;
  final String? message;
  final List<DiscoveredAirGradientSensor> sensors;

  @override
  Widget build(BuildContext context) {
    final hasSensor = sensors.isNotEmpty;
    final icon = binding
        ? Symbols.sync
        : scanning
            ? Symbols.radar
            : hasSensor
                ? Symbols.sensors
                : Symbols.wifi_off;
    final title = binding
        ? '데이터 경로 연결 중'
        : scanning
            ? '센서 신호를 찾는 중'
            : hasSensor
                ? sensors.first.id
                : '검색 결과 없음';
    final body = message ??
        (hasSensor
            ? 'IP ${sensors.first.ip ?? '-'} · 선택하면 이 센서로 데이터를 받아옵니다.'
            : '휴대폰과 센서가 같은 Wi-Fi에 있는지 확인하세요.');

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
      child: Column(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (scanning || binding)
                  const CircularProgressIndicator(
                    strokeWidth: 5,
                    color: SetupColors.primaryContainer,
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: (success || hasSensor
                              ? SetupColors.primaryFixed
                              : SetupColors.low)
                          .withValues(alpha: 0.72),
                      shape: BoxShape.circle,
                    ),
                  ),
                Icon(
                  icon,
                  size: 48,
                  color: success || hasSensor
                      ? SetupColors.primary
                      : SetupColors.secondary,
                  fill: 1,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: SetupColors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.45,
              color: SetupColors.secondary,
            ),
          ),
        ],
      ),
    );
  }
}
