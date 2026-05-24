import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../features/disaster_device/disaster_device_draft.dart';
import '../features/disaster_device/disaster_device_storage.dart';
import '../features/disaster_device/disaster_device_test_controller.dart';
import '../features/disaster_device/tasmota_device_test_result.dart';
import '../features/disaster_mode/fire_risk_assessment.dart';
import '../features/sensor_location/sensor_location_draft.dart';
import '../features/sensor_location/sensor_location_storage.dart';
import '../models/air_quality_snapshot.dart';
import '../services/airgradient_local_api.dart';
import '../services/airgradient_mdns_service.dart';
import '../services/device_binding_service_v2.dart';
import '../services/firestore_snapshot_service.dart';
import '../services/led_control_service.dart';
import '../services/notification_preferences.dart';
import '../services/profile_asset_link_service.dart';
import '../services/push_notification_service_v2.dart';
import '../services/situation_resolution_service.dart';
import '../state/air_quality_controller.dart';
import '../utils/metric_status.dart';
import '../utils/nodered_health_engine.dart';
import 'remake/screens/initial/setup_flow_scaffold.dart';
import 'remake/screens/reference/reference_flow_app.dart';
import 'remake/widgets/kakao_map_preview.dart';

const _cleanairSystemChannel = MethodChannel('cleanair/system');

class StitchExportApp extends StatelessWidget {
  const StitchExportApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CleanAir',
      debugShowCheckedModeBanner: false,
      theme: StitchTheme.theme,
      home: _LiveDataResumeBridge(
        child: ReferenceFlowApp(
          airGradientLocalScreenBuilder: (context, onBack) {
            return AirGradientLocalPage(onBack: onBack);
          },
          sensorPinScreenBuilder: (context, onBack, onNext, onRetryAutoDetect) {
            return SensorPinPage(onBack: onBack, onConnected: onNext);
          },
          disasterScreenBuilder: (
            context,
            tabIndex,
            onOpenLocation,
            onExitDisaster,
          ) {
            return switch (tabIndex) {
              1 => StitchDisasterScreen(
                  view: DisasterView.analysis,
                  onOpenLocation: onOpenLocation,
                  onExitDisaster: onExitDisaster,
                ),
              2 => StitchDisasterScreen(
                  view: DisasterView.propagation,
                  onOpenLocation: onOpenLocation,
                  onExitDisaster: onExitDisaster,
                ),
              3 => StitchDisasterScreen(
                  view: DisasterView.devices,
                  onOpenLocation: onOpenLocation,
                  onExitDisaster: onExitDisaster,
                ),
              4 => StitchDisasterScreen(
                  view: DisasterView.settings,
                  onOpenLocation: onOpenLocation,
                  onExitDisaster: onExitDisaster,
                ),
              _ => StitchDisasterScreen(
                  onOpenLocation: onOpenLocation,
                  onExitDisaster: onExitDisaster,
                ),
            };
          },
        ),
      ),
    );
  }
}

class _LiveDataResumeBridge extends StatefulWidget {
  const _LiveDataResumeBridge({required this.child});

  final Widget child;

  @override
  State<_LiveDataResumeBridge> createState() => _LiveDataResumeBridgeState();
}

class _LiveDataResumeBridgeState extends State<_LiveDataResumeBridge>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final controller = context.read<AirQualityController>();
    unawaited(controller.refreshHistoryFromFirestore());
    if (!controller.isConnected) {
      unawaited(controller.retryConnection());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class StitchExportShell extends StatefulWidget {
  const StitchExportShell({super.key});

  @override
  State<StitchExportShell> createState() => _StitchExportShellState();
}

class _StitchExportShellState extends State<StitchExportShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      StitchHomeScreen(onOpenTab: _select),
      const StitchAnalysisScreen(),
      const StitchDisasterScreen(),
      const StitchSetupScreen(),
      const StitchSettingsScreen(),
    ];

    return Scaffold(
      backgroundColor: Sx.surface,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: _FloatingBottomNav(
        selectedIndex: _index,
        onChanged: _select,
      ),
    );
  }

  void _select(int value) {
    setState(() => _index = value);
  }
}

class StitchHomeScreen extends StatelessWidget {
  const StitchHomeScreen({super.key, required this.onOpenTab});

  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AirQualityController>();
    final binding = context.watch<DeviceBindingControllerV2>().value;
    final air = AirReading.fromController(controller);

    return StitchScaffold(
      title: '방재모드',
      actionIcon: Icons.notifications_none_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StitchTopIdentity(
            eyebrow: '방재모드',
            title: '새싹어린이집 1층',
            subtitle: '실시간 공기질과 이상 징후를 함께 확인합니다.',
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                icon: Icons.sensors_rounded,
                label: binding.isBound ? '센서 연결됨' : '센서 연결 대기',
                active: binding.isBound,
              ),
              StatusPill(
                icon: Icons.cloud_done_rounded,
                label: air.liveLabel,
                active: controller.status == LiveDataStatus.connected,
              ),
              StatusPill(
                icon: Icons.shield_outlined,
                label: air.safetyLabel,
                tone: air.isRisky ? PillTone.warning : PillTone.primary,
              ),
            ],
          ),
          const SizedBox(height: 22),
          _HomeHeroCard(reading: air, onTap: () => onOpenTab(1)),
          const SizedBox(height: 20),
          _MetricGrid(reading: air),
          const SizedBox(height: 20),
          _MiniTrendCard(
            readings: controller.rawHistory,
            title: '최근 공기질 흐름',
            subtitle: controller.rawHistory.isEmpty
                ? '센서가 연결되면 실시간 추이가 표시됩니다.'
                : '${controller.rawHistory.length}개 측정값',
          ),
          const SizedBox(height: 20),
          _QuickActionGrid(
            actions: [
              QuickAction(
                icon: Icons.analytics_outlined,
                label: '상세 분석',
                emphasized: true,
                onTap: () => onOpenTab(1),
              ),
              QuickAction(
                icon: Icons.warning_amber_rounded,
                label: '방재 확인',
                onTap: () => onOpenTab(2),
              ),
              QuickAction(
                icon: Icons.add_location_alt_outlined,
                label: '위치 등록',
                onTap: () => onOpenTab(3),
              ),
              QuickAction(
                icon: Icons.power_settings_new_rounded,
                label: '장치 제어',
                onTap: () => onOpenTab(3),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _ReadinessCard(binding: binding, reading: air),
        ],
      ),
    );
  }
}

class StitchAnalysisScreen extends StatefulWidget {
  const StitchAnalysisScreen({super.key});

  @override
  State<StitchAnalysisScreen> createState() => _StitchAnalysisScreenState();
}

class _StitchAnalysisScreenState extends State<StitchAnalysisScreen> {
  String _metric = 'PM2.5';
  String _range = '24H';

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AirQualityController>();
    final reading = AirReading.fromController(controller);
    final history = controller.rawHistory;
    final metricValue = reading.metric(_metric);

    return StitchScaffold(
      title: 'CleanAir',
      leadingIcon: Icons.grid_view_rounded,
      actionIcon: Icons.tune_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StitchTopIdentity(
            eyebrow: 'Analysis',
            title: '공기질 상세 분석',
            subtitle: 'Stitch 상세 차트 화면 기준으로 측정값과 기준을 확인합니다.',
          ),
          const SizedBox(height: 18),
          _SegmentedSelector(
            values: const ['PM2.5', 'CO₂', 'TVOC', 'NOx', '온도', '습도'],
            selected: _metric,
            onChanged: (value) => setState(() => _metric = value),
          ),
          const SizedBox(height: 18),
          StitchCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _metric,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    StatusPill(label: reading.metricState(_metric)),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '${metricValue.value} ${metricValue.unit}',
                  style: Theme.of(
                    context,
                  ).textTheme.displayLarge?.copyWith(color: metricValue.color),
                ),
                const SizedBox(height: 8),
                Text(
                  reading.analysisMessage(_metric),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Sx.secondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SegmentedSelector(
            values: const ['1H', '6H', '24H', '1W'],
            selected: _range,
            onChanged: (value) => setState(() => _range = value),
          ),
          const SizedBox(height: 18),
          StitchCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trend Visualization',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 220,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: TrendPainter(
                      values: _metricSeries(history, _metric),
                      color: metricValue.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _StatsGrid(reading: reading, metric: _metric, history: history),
          const SizedBox(height: 18),
          StitchCard(
            color: Sx.low,
            child: Row(
              children: [
                const Icon(Icons.file_download_outlined, color: Sx.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'CSV와 장기 히스토리는 Firestore history 경로가 연결되면 같은 분석 화면에서 확장됩니다.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum DisasterView { home, analysis, propagation, devices, settings }

class StitchDisasterScreen extends StatefulWidget {
  const StitchDisasterScreen({
    super.key,
    this.view = DisasterView.home,
    this.onOpenLocation,
    this.onExitDisaster,
  });

  final DisasterView view;
  final VoidCallback? onOpenLocation;
  final VoidCallback? onExitDisaster;

  @override
  State<StitchDisasterScreen> createState() => _StitchDisasterScreenState();
}

class _StitchDisasterScreenState extends State<StitchDisasterScreen> {
  final _locationStorage = SensorLocationStorage();
  final _deviceStorage = DisasterDeviceStorage();
  final _deviceTestController = DisasterDeviceTestController();
  final _situationResolutionService = SituationResolutionService();

  SensorLocationDraft? _location;
  DisasterDeviceDraft? _device;
  List<SensorLocationDraft> _locations = const <SensorLocationDraft>[];
  List<DisasterDeviceDraft> _devices = const <DisasterDeviceDraft>[];
  bool _loadingContext = true;
  bool _deviceBusy = false;
  bool _dashboardBusy = false;
  bool _endingSituation = false;
  bool? _powerOn;
  String? _deviceMessage;
  int _selectedDeviceIndex = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadContext());
  }

  Future<void> _loadContext() async {
    final binding = context.read<DeviceBindingControllerV2>().value;
    final results = await Future.wait<Object?>([
      _locationStorage.loadForSensor(binding.deviceId),
      _deviceStorage.load(),
      _locationStorage.loadAll(),
      _deviceStorage.loadAll(),
    ]);
    final location = results[0] as SensorLocationDraft?;
    final device = results[1] as DisasterDeviceDraft?;
    final locations = results[2] as List<SensorLocationDraft>;
    final devices = results[3] as List<DisasterDeviceDraft>;
    final selectedIndex = devices.isEmpty
        ? 0
        : _selectedDeviceIndex.clamp(0, devices.length - 1).toInt();
    final selectedDevice = devices.isEmpty ? device : devices[selectedIndex];
    if (!mounted) return;
    setState(() {
      _location = location;
      _device = selectedDevice;
      _locations = locations;
      _devices = devices;
      _selectedDeviceIndex = selectedIndex;
      _deviceMessage = selectedDevice?.lastTestStatus;
      _powerOn = selectedDevice?.currentPowerOn ?? _powerOn;
      _loadingContext = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AirQualityController>();
    final reading = AirReading.fromController(controller);
    final latestSnapshot = controller.latestSnapshot;
    final fireHistory = controller.rawHistory.isEmpty && latestSnapshot != null
        ? <AirQualitySnapshot>[latestSnapshot]
        : controller.rawHistory;
    final assessment = FireRiskAssessment.fromHistory(fireHistory);
    final location = _location;
    final device = _selectedDevice;
    final riskColor = _fireRiskColor(assessment.level);
    final content = _buildContent(
      context: context,
      reading: reading,
      assessment: assessment,
      riskColor: riskColor,
      location: location,
      device: device,
    );

    return StitchScaffold(
      title: '방재모드',
      leadingIcon: Icons.location_on_outlined,
      actionIcon: Icons.home_rounded,
      onLeadingTap: widget.onOpenLocation,
      onActionTap: widget.onExitDisaster,
      child: content,
    );
  }

  Widget _buildContent({
    required BuildContext context,
    required AirReading reading,
    required FireRiskAssessment assessment,
    required Color riskColor,
    required SensorLocationDraft? location,
    required DisasterDeviceDraft? device,
  }) {
    return switch (widget.view) {
      DisasterView.analysis => _buildAnalysisView(
          context,
          reading,
          assessment,
        ),
      DisasterView.propagation => _buildPropagationView(
          context,
          assessment,
          location,
          device,
        ),
      DisasterView.devices => _buildDeviceView(
          context,
          assessment,
          location,
          device,
        ),
      DisasterView.settings => _buildSettingsView(context, assessment),
      DisasterView.home => _buildHomeView(
          context,
          reading,
          assessment,
          riskColor,
          location,
          device,
        ),
    };
  }

  Widget _buildHomeView(
    BuildContext context,
    AirReading reading,
    FireRiskAssessment assessment,
    Color riskColor,
    SensorLocationDraft? location,
    DisasterDeviceDraft? device,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StitchTopIdentity(
          eyebrow: '방재 홈',
          title: '방재모드',
          subtitle: location == null
              ? '센서 위치를 등록하면 상황 판단과 장치 연결에 함께 표시됩니다.'
              : '${location.spaceName} · ${location.detailLocation}',
        ),
        const SizedBox(height: 18),
        _FireRiskHeroCard(
          assessment: assessment,
          riskColor: riskColor,
        ),
        const SizedBox(height: 18),
        _EmergencyResponseCard(
          assessment: assessment,
          location: location,
          device: device,
          busy: _deviceBusy,
          onCopySituation: () =>
              _copyEmergencyText(assessment, location, device),
          onPowerOn: device == null
              ? null
              : () => _runDeviceAction(_deviceTestController.testPowerOn),
          onOpen119: _openEmergencyDialer,
          endingSituation: _endingSituation,
          onEndSituation: _endDashboardSituation,
          onTestAlert: () => _sendDashboardIncident(
            assessment: assessment,
            location: location,
            device: device,
          ),
        ),
        const SizedBox(height: 18),
        _ObservedMetrics(reading: reading, assessment: assessment),
        const SizedBox(height: 18),
        _DisasterSituationBoardCard(
          assessment: assessment,
          locations: _locations,
          devices: _devices,
          activeLocation: location,
          onOpenLocation: widget.onOpenLocation,
        ),
        const SizedBox(height: 18),
        _DetectedLocationCard(
          location: location,
          loading: _loadingContext,
          onOpenLocation: widget.onOpenLocation,
        ),
        const SizedBox(height: 18),
        _ConnectedDeviceSummaryCard(device: device, devices: _devices),
        const SizedBox(height: 18),
        _SituationTimeline(
          assessment: assessment,
          device: device,
        ),
      ],
    );
  }

  Future<void> _copyEmergencyText(
    FireRiskAssessment assessment,
    SensorLocationDraft? location,
    DisasterDeviceDraft? device,
  ) async {
    final text = [
      '방재 상태: ${assessment.levelLabel}',
      assessment.summary,
      if (location != null)
        '위치: ${location.spaceName} ${location.floor} ${location.detailLocation}',
      if (device != null) '연결 장치: ${device.displayName}',
      '확인이 필요하면 현장 확인 후 119 신고 여부를 판단해 주세요.',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('상황 요약을 복사했습니다.')),
    );
  }

  Future<void> _openEmergencyDialer() async {
    try {
      await _cleanairSystemChannel
          .invokeMethod('openDialer', {'number': '119'});
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('전화 앱을 열 수 없습니다. 직접 119로 연락해 주세요.')),
      );
    }
  }

  Future<void> _sendDashboardIncident({
    required FireRiskAssessment assessment,
    required SensorLocationDraft? location,
    required DisasterDeviceDraft? device,
  }) async {
    if (_dashboardBusy) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('프로필에서 Google 로그인 후 대시보드로 전송할 수 있습니다.')),
      );
      return;
    }

    setState(() => _dashboardBusy = true);
    try {
      await ProfileAssetLinkService().syncCurrentLocalAssets();
      final ref = FirebaseFirestore.instance
          .collection('user_profiles')
          .doc(user.uid)
          .collection('incidents')
          .doc();
      final activeMetrics = <String, dynamic>{
        for (final metric in assessment.metrics)
          metric.key: <String, dynamic>{
            'label': metric.label,
            'current': metric.current,
            'rise5': metric.rise5,
            'score': metric.score,
            'unit': metric.unit,
            'status': metric.status,
          },
      };
      await ref.set(<String, dynamic>{
        'id': ref.id,
        'status': 'active',
        'severity': assessment.isUrgent ? 'critical' : 'warning',
        'type': 'fire_risk',
        'title': assessment.isUrgent ? assessment.headline : '현장 확인 요청',
        'message': assessment.summary,
        'sensorId': location?.sensorId ?? '',
        'sensorName': location?.spaceName ?? '',
        'location': [
          location?.address,
          location?.buildingName,
          location?.floor,
          location?.detailLocation,
        ]
            .whereType<String>()
            .where((value) => value.trim().isNotEmpty)
            .join(' · '),
        'latitude': location?.latitude,
        'longitude': location?.longitude,
        'metrics': activeMetrics,
        'levelLabel': assessment.levelLabel,
        'riskScore': assessment.totalScore,
        'riskCount': assessment.riskCount,
        'persistenceLabel': assessment.persistenceLabel,
        'plugIds': [
          if (device != null) device.deviceId,
        ],
        'plugSummary': [
          if (device != null)
            <String, dynamic>{
              'plugId': device.deviceId,
              'displayName': device.displayName,
              'state': device.currentPowerOn == true
                  ? 'ON'
                  : device.currentPowerOn == false
                      ? 'OFF'
                      : 'UNKNOWN',
              'mode': device.autoControlEnabled ? 'auto' : 'manual',
            },
        ],
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': user.email ?? user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('웹 대시보드에 상황을 전송했습니다.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('대시보드 전송 실패: $error')),
      );
    } finally {
      if (mounted) setState(() => _dashboardBusy = false);
    }
  }

  Future<void> _endDashboardSituation() async {
    if (_endingSituation) return;
    final binding = context.read<DeviceBindingControllerV2>().value;
    final user = FirebaseAuth.instance.currentUser;
    final sensorIds = <String>{
      ..._timelineSensorCandidates(binding),
      if (_location?.sensorId.trim().isNotEmpty == true)
        _location!.sensorId.trim(),
    }.toList(growable: false);

    if (user == null && sensorIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('종료할 대시보드 상황이나 센서 알림을 찾을 수 없습니다.')),
      );
      return;
    }

    setState(() => _endingSituation = true);
    try {
      final result = await _situationResolutionService.resolveActiveSituation(
        userId: user?.uid,
        sensorIds: sensorIds,
      );
      if (!mounted) return;
      final message = result.totalResolved == 0
          ? '종료할 활성 상황이 없습니다.'
          : '상황 종료 완료 · 상황 ${result.resolvedIncidents}건 · 알림 ${result.resolvedAlerts}건';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.hasFailure
                ? '$message · 실패 ${result.failedAlerts}건'
                : message,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('상황 종료 실패: $error')),
      );
    } finally {
      if (mounted) setState(() => _endingSituation = false);
    }
  }

  Widget _buildAnalysisView(
    BuildContext context,
    AirReading reading,
    FireRiskAssessment assessment,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StitchTopIdentity(
          eyebrow: '분석',
          title: '화재 의심 패턴 분석',
          subtitle: '여러 센서값이 동시에 나빠지는 흐름을 확인합니다.',
        ),
        const SizedBox(height: 18),
        _ObservedMetrics(reading: reading, assessment: assessment),
        const SizedBox(height: 18),
        _FireRiskCriteriaCard(assessment: assessment),
      ],
    );
  }

  Widget _buildPropagationView(
    BuildContext context,
    FireRiskAssessment assessment,
    SensorLocationDraft? location,
    DisasterDeviceDraft? device,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StitchTopIdentity(
          eyebrow: '상황 전파',
          title: '상황 요약과 현장 확인',
          subtitle: '자동 신고 대신 확인 가능한 상황 요약과 대응 순서를 제공합니다.',
        ),
        const SizedBox(height: 18),
        _PropagationCard(
          assessment: assessment,
          location: location,
          device: device,
        ),
        const SizedBox(height: 18),
        _ActionRecommendationCard(assessment: assessment),
        const SizedBox(height: 18),
        _SituationTimeline(
          assessment: assessment,
          device: device,
        ),
      ],
    );
  }

  Widget _buildDeviceView(
    BuildContext context,
    FireRiskAssessment assessment,
    SensorLocationDraft? location,
    DisasterDeviceDraft? device,
  ) {
    final binding = context.watch<DeviceBindingControllerV2>().value;
    final reading =
        AirReading.fromController(context.watch<AirQualityController>());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StitchTopIdentity(
          eyebrow: '방재 대비',
          title: '방재 대비 상태',
          subtitle: '센서, 위치, 알림, 연결 장치가 실제 대응 가능한 상태인지 확인합니다.',
        ),
        const SizedBox(height: 18),
        _DisasterReadinessCard(
          binding: binding,
          reading: reading,
          location: location,
          devices: _devices,
        ),
        const SizedBox(height: 18),
        _ConnectedDeviceControlCard(
          device: device,
          devices: _devices,
          selectedIndex: _selectedDeviceIndex,
          onSelectedDevice: _selectDisasterDevice,
          busy: _deviceBusy,
          powerOn: _powerOn,
          message: _deviceMessage,
          onRefresh: _loadContext,
          onTest: () => _runDeviceAction(_deviceTestController.testConnection),
          onPowerOn: () => _runDeviceAction(_deviceTestController.testPowerOn),
          onPowerOff: () =>
              _runDeviceAction(_deviceTestController.testPowerOff),
        ),
        const SizedBox(height: 18),
        _ActionRecommendationCard(assessment: assessment),
      ],
    );
  }

  Widget _buildSettingsView(
    BuildContext context,
    FireRiskAssessment assessment,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StitchTopIdentity(
          eyebrow: '설정 · 정보',
          title: '방재 알림 기준',
          subtitle: '낮은 단계는 앱 안에서만 보여주고, 경고 이상부터 푸시 알림으로 보냅니다.',
        ),
        const SizedBox(height: 18),
        const _FireNotificationPolicyCard(),
        const SizedBox(height: 18),
        _FireRiskCriteriaCard(assessment: assessment),
      ],
    );
  }

  Future<void> _runDeviceAction(
    Future<TasmotaDeviceTestResult> Function(DisasterDeviceDraft) runner,
  ) async {
    final device = _selectedDevice;
    if (_deviceBusy || device == null) return;
    setState(() => _deviceBusy = true);

    try {
      final result = await runner(device);
      final updated = device.copyWith(
        lastTestStatus: result.statusLabel,
        currentPowerOn: result.powerOn ?? device.currentPowerOn,
        updatedAt: DateTime.now(),
      );
      await _deviceStorage.save(updated);
      if (!mounted) return;
      final nextDevices = _devices.map((item) {
        return item.deviceId == updated.deviceId ? updated : item;
      }).toList(growable: false);
      setState(() {
        _device = updated;
        _devices = nextDevices;
        _deviceMessage = result.message;
        _powerOn = result.powerOn ?? _powerOn;
        _deviceBusy = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deviceBusy = false;
        _deviceMessage = '장치 제어 실패 · IP, 전원, Wi-Fi를 확인해 주세요.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('장치 제어 실패 · 연결 설정을 확인해 주세요.')),
      );
    }
  }

  DisasterDeviceDraft? get _selectedDevice {
    if (_devices.isEmpty) return _device;
    final index = _selectedDeviceIndex.clamp(0, _devices.length - 1).toInt();
    return _devices[index];
  }

  void _selectDisasterDevice(int index) {
    if (index < 0 || index >= _devices.length) return;
    final device = _devices[index];
    setState(() {
      _selectedDeviceIndex = index;
      _device = device;
      _deviceMessage = device.lastTestStatus;
      _powerOn = device.currentPowerOn;
    });
  }
}

Color _fireRiskColor(FireRiskLevel level) {
  return switch (level) {
    FireRiskLevel.fireSuspected => Sx.danger,
    FireRiskLevel.strongWarning => Sx.warning,
    FireRiskLevel.warning => Sx.warning,
    FireRiskLevel.notice => Sx.primary2,
    FireRiskLevel.coOnly => Sx.danger,
    FireRiskLevel.normal => Sx.primary,
  };
}

class StitchSetupScreen extends StatefulWidget {
  const StitchSetupScreen({super.key});

  @override
  State<StitchSetupScreen> createState() => _StitchSetupScreenState();
}

class _StitchSetupScreenState extends State<StitchSetupScreen> {
  final _storage = SetupStorage();
  final _locationStorage = SensorLocationStorage();
  final _deviceStorage = DisasterDeviceStorage();
  InstallLocation? _location;
  ResponseDevice? _device;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final binding = context.read<DeviceBindingControllerV2>().value;
    final locationDraft =
        await _locationStorage.loadForSensor(binding.deviceId);
    final deviceDraft = await _deviceStorage.load();
    final location = locationDraft == null
        ? await _storage.loadLocation()
        : InstallLocation(
            spaceName: locationDraft.spaceName,
            facilityType: locationDraft.facilityType,
            buildingName: locationDraft.buildingName,
            address: locationDraft.address,
            floor: locationDraft.floor,
            detail: locationDraft.detailLocation,
            memo: locationDraft.installationMemo,
            lat: locationDraft.latitude,
            lng: locationDraft.longitude,
          );
    final device = deviceDraft == null
        ? await _storage.loadDevice()
        : ResponseDevice(
            displayName: deviceDraft.displayName,
            deviceType: deviceDraft.deviceType,
            controlMethod: deviceDraft.controlMethod,
            ip: deviceDraft.plugIp,
          );
    if (!mounted) return;
    setState(() {
      _location = location;
      _device = device;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final binding = context.watch<DeviceBindingControllerV2>().value;

    return StitchScaffold(
      title: 'Cleanair',
      leadingIcon: Icons.location_on_outlined,
      actionIcon: Icons.settings_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StitchTopIdentity(
            eyebrow: 'Setup',
            title: '센서와 방재 장치 연결',
            subtitle: 'AirGradient 등록, 위치 지정, 로컬 설정, Tasmota 테스트를 순서대로 진행합니다.',
          ),
          const SizedBox(height: 18),
          _SetupProgress(
            binding: binding,
            location: _location,
            device: _device,
          ),
          const SizedBox(height: 18),
          _SetupActionCard(
            stage: 'Stage 1/4',
            icon: Icons.sensors_rounded,
            title: binding.isBound ? '센서 등록 완료' : 'AirGradient 센서 등록',
            subtitle: binding.isBound
                ? binding.deviceId
                : '센서 화면의 PIN으로 Firestore live data 경로를 연결합니다.',
            cta: binding.isBound ? '다시 등록' : 'PIN 입력',
            onTap: () => _openSensorPin(context),
          ),
          const SizedBox(height: 14),
          _SetupActionCard(
            stage: 'Stage 2/4',
            icon: Icons.add_location_alt_outlined,
            title: _location == null ? '센서 위치 등록' : _location!.spaceName,
            subtitle: _location == null
                ? '주소 검색, 지도 확인, 상세 실내 위치를 저장합니다.'
                : '${_location!.buildingName} · ${_location!.floor}',
            cta: _location == null ? '위치 등록' : '위치 수정',
            onTap: () => _openLocation(context),
          ),
          const SizedBox(height: 14),
          _SetupActionCard(
            stage: 'Stage 3/4',
            icon: Icons.language_rounded,
            title: 'AirGradient 로컬 설정',
            subtitle: '같은 Wi-Fi에서 로컬 IP, 웹 설정 URL, API 응답을 점검합니다.',
            cta: '로컬 점검',
            onTap: () => _openAirGradientLocal(context),
          ),
          const SizedBox(height: 14),
          _SetupActionCard(
            stage: 'Stage 4/4',
            icon: Icons.power_rounded,
            title: _device == null ? '연결 장치 등록' : _device!.displayName,
            subtitle: _device == null
                ? 'Tasmota 플러그, 사이렌, 팬을 위치와 연결합니다.'
                : '${_device!.deviceType} · ${_device!.controlMethod}',
            cta: _device == null ? '장치 등록' : '장치 관리',
            onTap: () => _openDevice(context),
          ),
          if (_loading) ...[
            const SizedBox(height: 18),
            const LinearProgressIndicator(minHeight: 4),
          ],
        ],
      ),
    );
  }

  Future<void> _openSensorPin(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => SensorPinPage(
          onBack: () => Navigator.of(routeContext).pop(),
          onConnected: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openLocation(BuildContext context) async {
    final saved = await Navigator.of(context).push<InstallLocation>(
      MaterialPageRoute(builder: (_) => LocationSetupPage(initial: _location)),
    );
    if (saved != null) {
      if (!context.mounted) return;
      final binding = context.read<DeviceBindingControllerV2>().value;
      await _storage.saveLocation(saved);
      final sensorId = binding.deviceId.trim().isEmpty
          ? 'sensor-unassigned'
          : binding.deviceId.trim();
      await _locationStorage.save(
        SensorLocationDraft(
          sensorId: sensorId,
          sensorName: sensorId,
          spaceName: saved.spaceName,
          facilityType: saved.facilityType,
          buildingName: saved.buildingName,
          address: saved.address,
          latitude: saved.lat,
          longitude: saved.lng,
          floor: saved.floor,
          detailLocation: saved.detail,
          installationMemo: saved.memo,
          updatedAt: DateTime.now(),
        ),
      );
      await _load();
    }
  }

  Future<void> _openAirGradientLocal(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AirGradientLocalPage()),
    );
  }

  Future<void> _openDevice(BuildContext context) async {
    final saved = await Navigator.of(context).push<ResponseDevice>(
      MaterialPageRoute(builder: (_) => DeviceSetupPage(initial: _device)),
    );
    if (saved != null) {
      if (!context.mounted) return;
      final binding = context.read<DeviceBindingControllerV2>().value;
      await _storage.saveDevice(saved);
      await _deviceStorage.save(
        DisasterDeviceDraft.empty(
          linkedSensorId: binding.deviceId,
          linkedSpaceName: _location?.spaceName,
          linkedAddress: _location?.address,
        ).copyWith(
          displayName: saved.displayName,
          deviceType: saved.deviceType,
          controlMethod: saved.controlMethod,
          plugIp: saved.ip,
          updatedAt: DateTime.now(),
        ),
      );
      await _load();
    }
  }
}

class StitchSettingsScreen extends StatelessWidget {
  const StitchSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<NotificationPreferencesController>().value;
    final binding = context.watch<DeviceBindingControllerV2>().value;

    return FutureBuilder<SensorLocationDraft?>(
      future: SensorLocationStorage().loadForSensor(binding.deviceId),
      builder: (context, locationSnapshot) {
        return FutureBuilder<DisasterDeviceDraft?>(
          future: DisasterDeviceStorage().load(),
          builder: (context, deviceSnapshot) {
            final location = locationSnapshot.data;
            final device = deviceSnapshot.data;
            return StitchScaffold(
              title: '설정',
              leadingIcon: Icons.location_on_outlined,
              actionIcon: Icons.tune_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const StitchTopIdentity(
                    eyebrow: 'SYSTEM',
                    title: '시스템 설정',
                    subtitle: '알림, 센서 연결, 안전 기준, 데이터 상태를 확인합니다.',
                  ),
                  const SizedBox(height: 18),
                  _SettingsSection(
                    title: '알림 설정',
                    icon: Icons.notifications_active_outlined,
                    children: [
                      SettingSwitchRow(
                        title: '위험 알림',
                        subtitle: '공기질 이상 징후 알림',
                        value: prefs.alertsEnabled,
                        onChanged: (value) => context
                            .read<NotificationPreferencesController>()
                            .setAlertsEnabled(value),
                      ),
                      SettingSwitchRow(
                        title: '방해 금지 시간',
                        subtitle: '야간 알림 제한',
                        value: prefs.quietHoursEnabled,
                        onChanged: (value) => context
                            .read<NotificationPreferencesController>()
                            .setQuietHoursEnabled(value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SettingsSection(
                    title: '연결 상태',
                    icon: Icons.account_tree_outlined,
                    children: [
                      _SettingsInfoRow(
                        icon: Icons.sensors_rounded,
                        title: '센서',
                        value: binding.isBound ? binding.deviceId : '등록 필요',
                      ),
                      _SettingsInfoRow(
                        icon: Icons.cloud_queue_rounded,
                        title: 'Firestore',
                        value: binding.isBound
                            ? binding.firestoreDocPath
                            : '경로 없음',
                      ),
                      _SettingsInfoRow(
                        icon: Icons.add_location_alt_outlined,
                        title: '설치 위치',
                        value: location?.spaceName ?? '위치 등록 필요',
                      ),
                      _SettingsInfoRow(
                        icon: Icons.power_rounded,
                        title: '연결 장치',
                        value: device == null
                            ? '장치 등록 필요'
                            : '${device.displayName} · ${device.lastTestStatus}',
                      ),
                      const _SettingsInfoRow(
                        icon: Icons.storage_outlined,
                        title: '데이터',
                        value: '로컬 캐시 및 실시간 스트림 사용',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _SettingsSection(
                    title: '안전 기준',
                    icon: Icons.shield_outlined,
                    children: [
                      _ThresholdRow(label: 'PM2.5', value: '35 / 55 µg/m³'),
                      _ThresholdRow(label: 'CO₂', value: '1000 / 1500 ppm'),
                      _ThresholdRow(label: 'TVOC', value: '300 / 400 index'),
                      _ThresholdRow(label: 'NOx', value: '2 index 이상'),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class SensorPinPage extends StatefulWidget {
  const SensorPinPage({super.key, this.onBack, this.onConnected});

  final VoidCallback? onBack;
  final VoidCallback? onConnected;

  @override
  State<SensorPinPage> createState() => _SensorPinPageState();
}

class _SensorPinPageState extends State<SensorPinPage> {
  static const _airGradientIpPrefsKey = 'airgradient_local_ip_v1';

  final _pin = TextEditingController();
  final _serial = TextEditingController();
  final _mdnsService = AirGradientMdnsService();
  final _localClient = AirGradientLocalClient();
  bool _loading = false;
  bool _scanning = false;
  String? _message;
  bool _success = false;
  List<DiscoveredAirGradientSensor> _discoveredSensors = const [];

  @override
  void dispose() {
    _pin.dispose();
    _serial.dispose();
    _localClient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final binding = context.watch<DeviceBindingControllerV2>().value;
    return SetupFlowScaffold(
      step: 6,
      totalSteps: 6,
      onBack: widget.onBack,
      onPrimary: _loading ? null : _claimPin,
      primaryLabel: _loading ? '연결 확인 중' : '센서 연결',
      primaryIcon: Symbols.arrow_forward,
      title: '6자리 PIN 번호 입력',
      subtitle: '센서 화면에 표시된 번호를 입력하면 기존 PIN 등록 파이프라인으로 기기를 연결합니다.',
      children: [
        const SetupIconPlate(icon: Symbols.pin),
        const SizedBox(height: 28),
        if (binding.isBound) ...[
          SetupInfoCard(
            icon: Symbols.check_circle,
            title: '현재 연결된 센서',
            body: binding.deviceId,
          ),
          const SizedBox(height: 18),
        ],
        StitchTextField(
          controller: _pin,
          label: 'PIN',
          hint: '6자리 번호',
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          onSubmitted: (_) => _claimPin(),
        ),
        const SizedBox(height: 16),
        StitchTextField(
          controller: _serial,
          label: '센서 ID / 시리얼',
          hint: '예: airgradient-a1b2c3d4e5f6',
        ),
        const SizedBox(height: 16),
        const SetupInfoCard(
          icon: Symbols.info,
          title: '직접 등록 안내',
          body: 'PIN 입력을 우선 사용하세요. 센서 ID 직접 연결은 PIN 서버 연결이 불안정할 때만 사용합니다.',
        ),
        const SizedBox(height: 14),
        SetupOptionTile(
          icon: Symbols.sensors,
          title: _loading ? '연결 확인 중' : '센서 ID로 연결',
          subtitle: '입력한 센서 ID의 Firestore 문서 경로를 찾아 연결합니다.',
          onTap: _loading ? null : _applyDirect,
        ),
        const SizedBox(height: 12),
        SetupOptionTile(
          icon: Symbols.wifi_find,
          title: _scanning ? '주변 센서 검색 중' : '주변 센서 자동 검색',
          subtitle: '같은 Wi-Fi 네트워크의 AirGradient 센서를 다시 찾습니다.',
          onTap: (_loading || _scanning) ? null : _scanMdns,
        ),
        if (_discoveredSensors.isNotEmpty) ...[
          const SizedBox(height: 14),
          for (final sensor in _discoveredSensors) ...[
            SetupOptionTile(
              icon: Symbols.sensors,
              title: sensor.displayId,
              subtitle: sensor.ip == null ? '로컬 IP 확인 중' : '로컬 IP ${sensor.ip}',
              onTap: _loading ? null : () => _applyDiscoveredSensor(sensor),
            ),
            const SizedBox(height: 10),
          ],
        ],
        if (_message != null) ...[
          const SizedBox(height: 16),
          SetupInfoCard(
            icon: _success ? Symbols.check_circle : Symbols.error,
            title: _success ? '연결 상태' : '연결 확인 필요',
            body: _message!,
            tint: _success ? SetupColors.primary : SetupColors.error,
          ),
        ],
      ],
    );
  }

  Future<void> _scanMdns() async {
    if (_scanning || _loading) return;
    setState(() {
      _scanning = true;
      _success = false;
      _message = null;
      _discoveredSensors = const [];
    });

    try {
      final sensors = await _mdnsService.discover();
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _discoveredSensors = sensors;
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

  Future<void> _claimPin() async {
    final pin = _pin.text.trim();
    if (pin.length != 6 || int.tryParse(pin) == null) {
      setState(() {
        _success = false;
        _message = '센서 화면의 6자리 PIN을 입력해 주세요.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final push = context.read<PushNotificationServiceV2>();
      final binding = context.read<DeviceBindingControllerV2>();
      final firestore = context.read<FirestoreSnapshotService>();
      final airController = context.read<AirQualityController>();
      final token = await push.ensureClientToken();
      final config = await binding.claimDevice(code: pin, token: token);
      if (!mounted) return;
      setState(() {
        _message = '센서 등록 완료 · 실시간 데이터 연결을 확인합니다.';
        _success = true;
      });
      var activeDeviceId = config.deviceId;
      var activePath = config.firestoreDocPath;
      if (activePath.trim().isEmpty && activeDeviceId.trim().isNotEmpty) {
        activePath = 'sensors/${activeDeviceId.trim()}';
        await binding.applyBinding(
          deviceId: activeDeviceId.trim(),
          firestoreDocPath: activePath,
        );
      }
      if (activePath.trim().isEmpty) {
        throw StateError('sensor_path_missing');
      }
      await firestore.setFirestoreDocPath(activePath);
      await firestore.connect(forceReconnect: true);
      var hasFirstSnapshot = await firestore.waitForFirstSnapshot(
        timeout: const Duration(seconds: 8),
      );
      if (!hasFirstSnapshot) {
        final resolvedPath = await firestore.findFirstLiveSensorDocPath(
          _claimedSensorCandidates(config),
          perCandidateTimeout: const Duration(seconds: 2),
        );
        if (resolvedPath != null && resolvedPath != activePath) {
          activePath = resolvedPath;
          activeDeviceId = _sensorIdFromDocPath(resolvedPath);
          await binding.applyBinding(
            deviceId: activeDeviceId,
            firestoreDocPath: activePath,
          );
          await firestore.setFirestoreDocPath(activePath);
          await firestore.connect(forceReconnect: true);
          hasFirstSnapshot = await firestore.waitForFirstSnapshot(
            timeout: const Duration(seconds: 8),
          );
        }
      }
      unawaited(airController.refreshHistoryFromFirestore());
      await push.updateSensorId(activeDeviceId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = true;
        _message = hasFirstSnapshot
            ? '연결 완료 · $activeDeviceId'
            : '연결 저장 완료 · 첫 측정값은 홈에서 자동 갱신됩니다.';
      });
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      widget.onConnected?.call();
    } catch (error) {
      if (!mounted) return;
      final text = error.toString();
      final message = text.contains('CLOUD_FUNCTION_BASE_URL') ||
              text.contains('BACKEND_BASE_URL')
          ? 'PIN 연결에 필요한 서버 주소가 설정되어 있지 않습니다.'
          : 'PIN 연결 실패: 센서 전원과 네트워크 상태를 확인해 주세요.';
      setState(() {
        _loading = false;
        _success = false;
        _message = message;
      });
    }
  }

  Future<void> _applyDirect() async {
    if (_loading || _scanning) return;
    final raw = _serial.text.trim();
    final candidates = AirGradientMdnsService.sensorIdCandidates(raw);
    if (candidates.isEmpty) {
      setState(() {
        _success = false;
        _message = '센서 ID를 입력해 주세요.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _success = false;
      _message = null;
    });

    await _applySensorBinding(
      sensorId: candidates.first,
      successPrefix: '직접 연결 완료',
      failureMessage: '직접 연결 실패: 센서 ID와 센서 등록 상태를 확인해 주세요.',
    );
  }

  Future<void> _applyDiscoveredSensor(
    DiscoveredAirGradientSensor sensor,
  ) async {
    if (_loading || _scanning) return;
    setState(() {
      _loading = true;
      _message = null;
      _success = false;
    });

    if (sensor.ip != null && sensor.ip!.trim().isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_airGradientIpPrefsKey, sensor.ip!.trim());
      } catch (_) {}
    }
    if (!mounted) return;

    _serial.text = sensor.id;
    await _applySensorBinding(
      sensorId: sensor.id,
      localIp: sensor.ip?.trim() ?? '',
      successPrefix: '로컬 검색 연결 완료',
      failureMessage: '로컬 검색 결과를 저장하지 못했습니다. 센서 전원과 Wi-Fi를 확인해 주세요.',
    );
  }

  Future<void> _applySensorBinding({
    required String sensorId,
    String localIp = '',
    required String successPrefix,
    required String failureMessage,
  }) async {
    try {
      final binding = context.read<DeviceBindingControllerV2>();
      final firestore = context.read<FirestoreSnapshotService>();
      final push = context.read<PushNotificationServiceV2>();
      final airController = context.read<AirQualityController>();
      final candidates = AirGradientMdnsService.sensorIdCandidates(sensorId);
      final fallbackId = candidates.isNotEmpty ? candidates.first : sensorId;
      final resolvedPath = await firestore.findFirstLiveSensorDocPath(
            candidates,
            perCandidateTimeout: const Duration(seconds: 2),
          ) ??
          'sensors/$fallbackId';
      final resolvedId = _sensorIdFromDocPath(resolvedPath);
      await binding.applyBinding(
        deviceId: resolvedId,
        firestoreDocPath: resolvedPath,
        localIp: localIp,
      );
      if (!mounted) return;
      setState(() {
        _message = '센서 등록 완료 · 실시간 데이터 연결을 확인합니다.';
        _success = true;
      });
      await firestore.setFirestoreDocPath(resolvedPath);
      await firestore.connect(forceReconnect: true);
      final hasFirstSnapshot = await firestore.waitForFirstSnapshot(
        timeout: const Duration(seconds: 8),
      );
      final localSnapshotLoaded = await _tryApplyLocalSnapshot(localIp);
      unawaited(airController.refreshHistoryFromFirestore());
      await push.updateSensorId(resolvedId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = true;
        _message = hasFirstSnapshot
            ? '$successPrefix · $resolvedId'
            : localSnapshotLoaded
                ? '$successPrefix · 로컬 센서값 표시 중'
                : '연결 저장 완료 · 첫 측정값은 홈에서 자동 갱신됩니다.';
      });
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      widget.onConnected?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = false;
        _message = failureMessage;
      });
    }
  }

  Future<bool> _tryApplyLocalSnapshot(String localIp) async {
    final ip = localIp.trim();
    if (ip.isEmpty) return false;
    try {
      final snapshot = await _localClient.fetchSnapshot(ip);
      if (snapshot == null) return false;
      if (!mounted) return false;
      await context.read<AirQualityController>().applyLocalSnapshot(snapshot);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _sensorIdFromDocPath(String path) {
    const prefix = 'sensors/';
    return path.startsWith(prefix) ? path.substring(prefix.length) : path;
  }

  List<String> _claimedSensorCandidates(DeviceBindingConfigV2 config) {
    final pathId = _sensorIdFromDocPath(config.firestoreDocPath);
    final candidates = <String>[
      config.firestoreDocPath,
      config.deviceId,
      pathId,
      ...AirGradientMdnsService.sensorIdCandidates(config.deviceId),
      ...AirGradientMdnsService.sensorIdCandidates(pathId),
    ];

    final unique = <String>[];
    for (final candidate in candidates) {
      final trimmed = candidate.trim();
      if (trimmed.isEmpty || unique.contains(trimmed)) continue;
      unique.add(trimmed);
    }
    return unique;
  }
}

class LocationSetupPage extends StatefulWidget {
  const LocationSetupPage({super.key, this.initial});

  final InstallLocation? initial;

  @override
  State<LocationSetupPage> createState() => _LocationSetupPageState();
}

class _LocationSetupPageState extends State<LocationSetupPage> {
  final _query = TextEditingController(text: '새싹어린이집');
  final _space = TextEditingController(text: '새싹어린이집 1층 복도');
  final _detail = TextEditingController(text: '조리실 앞 복도');
  final _memo = TextEditingController();
  int _step = 0;
  String _facility = '어린이집';
  String _floor = '1층';
  LocationResult _selected = LocationResult.results.first;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _space.text = initial.spaceName;
      _detail.text = initial.detail;
      _memo.text = initial.memo;
      _facility = initial.facilityType;
      _floor = initial.floor;
      _selected = LocationResult(
        buildingName: initial.buildingName,
        address: initial.address,
        lat: initial.lat,
        lng: initial.lng,
      );
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _space.dispose();
    _detail.dispose();
    _memo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StitchScaffold(
      title: '위치 등록',
      showBack: true,
      bottom: GradientButton(
        label: _step == 4
            ? '홈으로 이동'
            : _step == 3
                ? '위치 저장'
                : 'NEXT',
        icon: _step == 4 ? Icons.home_outlined : Icons.arrow_forward_rounded,
        onTap: _next,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: KeyedSubtree(key: ValueKey(_step), child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final binding = context.watch<DeviceBindingControllerV2>().value;
    if (_step == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StepIndicator(label: 'STEP', current: 1, total: 5),
          const SizedBox(height: 32),
          Text('센서 위치 등록', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 10),
          Text(
            '이상 상황 발생 시 이 위치가 알림과 방재 장치 연결 기준이 됩니다.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Sx.secondary),
          ),
          const SizedBox(height: 24),
          StitchCard(
            child: Row(
              children: [
                const CenterBubble(icon: Icons.sensors_rounded, size: 54),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        binding.isBound ? binding.deviceId : '센서 등록 필요',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        binding.isBound
                            ? '${binding.firestoreDocPath} · 위치 등록 중'
                            : '센서를 등록하면 설치 위치와 연결됩니다.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          StitchTextField(controller: _query, label: '주소 또는 건물명 검색'),
        ],
      );
    }
    if (_step == 1) {
      final results = LocationResult.results
          .where((e) => e.matches(_query.text))
          .toList(growable: false);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StepIndicator(label: 'STEP', current: 2, total: 5),
          const SizedBox(height: 28),
          Text(
            '어디에 센서를 설치하셨나요?',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          StitchTextField(controller: _query, label: '주소 검색'),
          const SizedBox(height: 18),
          Row(
            children: [
              Text('검색 결과', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              StatusPill(label: '${results.length}건'),
            ],
          ),
          const SizedBox(height: 14),
          for (final item
              in results.isEmpty ? LocationResult.results : results) ...[
            _LocationResultTile(
              item: item,
              selected: item.address == _selected.address,
              onTap: () => setState(() => _selected = item),
            ),
            const SizedBox(height: 12),
          ],
        ],
      );
    }
    if (_step == 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StepIndicator(label: 'STEP', current: 3, total: 5),
          const SizedBox(height: 28),
          Text('지도에서 위치 확인', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 18),
          _MapCard(location: _selected),
        ],
      );
    }
    if (_step == 3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StepIndicator(label: 'STEP', current: 4, total: 5),
          const SizedBox(height: 28),
          Text(
            '상세 위치를 입력해 주세요',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 18),
          StitchCard(
            color: Sx.primarySoft,
            child: Text('${_selected.buildingName}\n${_selected.address}'),
          ),
          const SizedBox(height: 16),
          StitchTextField(controller: _space, label: '공간 이름'),
          const SizedBox(height: 16),
          _ChipSelect(
            label: '시설 유형',
            values: const ['어린이집', '요양원', '가정', '작업장', '매장'],
            selected: _facility,
            onChanged: (v) => setState(() => _facility = v),
          ),
          const SizedBox(height: 16),
          _ChipSelect(
            label: '층',
            values: const ['지하 1층', '1층', '2층', '3층'],
            selected: _floor,
            onChanged: (v) => setState(() => _floor = v),
          ),
          const SizedBox(height: 16),
          StitchTextField(controller: _detail, label: '상세 위치'),
          const SizedBox(height: 16),
          StitchTextField(controller: _memo, label: '설치 메모', maxLines: 3),
        ],
      );
    }

    return Column(
      children: [
        const StepIndicator(label: 'STEP', current: 5, total: 5),
        const SizedBox(height: 46),
        const CenterIcon(icon: Icons.check_rounded),
        const SizedBox(height: 28),
        Text('센서 위치 등록 완료', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        Text(
          '이상 상황 발생 시 이 위치로 알림이 표시됩니다.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Sx.secondary),
        ),
        const SizedBox(height: 24),
        StitchCard(child: Text(_currentLocation().summary)),
      ],
    );
  }

  void _next() {
    if (_step < 3) {
      setState(() => _step += 1);
      return;
    }
    if (_step == 3) {
      setState(() => _step = 4);
      return;
    }
    Navigator.of(context).pop(_currentLocation());
  }

  InstallLocation _currentLocation() {
    return InstallLocation(
      spaceName: _space.text.trim().isEmpty ? '공간 이름 미입력' : _space.text.trim(),
      facilityType: _facility,
      buildingName: _selected.buildingName,
      address: _selected.address,
      floor: _floor,
      detail: _detail.text.trim().isEmpty ? '상세 위치 미입력' : _detail.text.trim(),
      memo: _memo.text.trim(),
      lat: _selected.lat,
      lng: _selected.lng,
    );
  }
}

class AirGradientLocalPage extends StatefulWidget {
  const AirGradientLocalPage({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<AirGradientLocalPage> createState() => _AirGradientLocalPageState();
}

class _AirGradientLocalPageState extends State<AirGradientLocalPage> {
  static const _ipPrefsKey = 'airgradient_local_ip_v1';

  final _ip = TextEditingController();
  final _ledService = LedControlService();
  final _localClient = AirGradientLocalClient();
  final _mdnsService = AirGradientMdnsService();
  String _result = '같은 Wi-Fi에서 센서 로컬 IP를 입력해 주세요.';
  AirGradientDeviceInfo? _deviceInfo;
  bool _ok = false;
  bool _busyLocal = false;
  bool _discovering = false;

  @override
  void initState() {
    super.initState();
    _loadIp();
  }

  @override
  void dispose() {
    _ip.dispose();
    _localClient.dispose();
    super.dispose();
  }

  Future<void> _loadIp() async {
    final activeIp =
        context.read<DeviceBindingControllerV2>().activeRecord?.localIp.trim();
    if (activeIp != null && activeIp.isNotEmpty) {
      if (!mounted) return;
      setState(() => _ip.text = activeIp);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_ipPrefsKey)?.trim();
    if (!mounted) return;
    if (saved != null && saved.isNotEmpty) {
      setState(() => _ip.text = saved);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_discoverLocalIp());
    });
  }

  Future<void> _saveIp() async {
    final ip = _ip.text.trim();
    if (ip.isEmpty) return;
    final binding = context.read<DeviceBindingControllerV2>().value;
    if (binding.isBound) {
      await context.read<DeviceBindingControllerV2>().updateBindingDetails(
            deviceId: binding.deviceId,
            localIp: ip,
          );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ipPrefsKey, ip);
  }

  @override
  Widget build(BuildContext context) {
    final binding = context.watch<DeviceBindingControllerV2>().value;
    final activeRecord =
        context.watch<DeviceBindingControllerV2>().activeRecord;
    final deviceLabel = binding.isBound
        ? (activeRecord?.label.trim().isNotEmpty == true
            ? activeRecord!.label
            : binding.deviceId)
        : '센서 등록 필요';
    final ip = _ip.text.trim();
    final url = ip.isEmpty ? '' : 'http://$ip';
    return StitchScaffold(
      title: '센서 설정',
      showBack: true,
      onBack: widget.onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '등록된 센서',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Text(
            deviceLabel,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          if (binding.isBound) ...[
            const SizedBox(height: 8),
            Text(
              activeRecord?.displayName.trim().isNotEmpty == true
                  ? '${binding.deviceId} · ${binding.firestoreDocPath}'
                  : binding.firestoreDocPath,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Sx.secondary),
            ),
          ],
          const SizedBox(height: 18),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: () {
                _copyWebUrl(url);
              },
              child: StitchCard(
                color: Sx.primary,
                child: Row(
                  children: [
                    const Icon(Icons.language_rounded, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '센서 웹 설정 URL 복사',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: Colors.white),
                      ),
                    ),
                    const Icon(Icons.copy_rounded, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            url.isEmpty ? 'IP 입력 후 웹 설정 URL이 생성됩니다.' : url,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Sx.secondary),
          ),
          const SizedBox(height: 10),
          SecondaryButton(
            label: '웹 설정 열기',
            icon: Icons.open_in_new_rounded,
            onTap: () => _openWebUrl(url),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: StitchTextField(controller: _ip, label: '로컬 IP')),
              const SizedBox(width: 10),
              SizedBox(
                width: 112,
                child: SecondaryButton(
                  label: _discovering ? '찾는 중' : '자동 찾기',
                  icon: Icons.wifi_find_rounded,
                  onTap: _discovering ? () {} : _discoverLocalIp,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'URL 복사',
                  icon: Icons.copy_rounded,
                  onTap: () {
                    _copyWebUrl(url);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SecondaryButton(
                  label: '연결 테스트',
                  icon: Icons.radar_rounded,
                  onTap: _test,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: _busyLocal ? '확인 중' : '펌웨어 확인',
                  icon: Icons.memory_rounded,
                  onTap: _busyLocal ? () {} : _checkFirmwareInfo,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SecondaryButton(
                  label: '재부팅(지원 펌웨어)',
                  icon: Icons.restart_alt_rounded,
                  onTap: _busyLocal ? () {} : _rebootSensor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          StitchCard(
            color: _ok ? Sx.primarySoft : (_discovering ? Sx.low : Sx.low),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_result),
                if (_deviceInfo != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _deviceInfoSummary(_deviceInfo!),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Sx.secondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'LED ON',
                  icon: Icons.lightbulb_outline,
                  onTap: () => _runConfigAction(
                    success: 'LED 표시를 CO₂ 모드로 켰습니다.',
                    failure:
                        'LED 설정 실패 · /config 지원 펌웨어와 같은 Wi-Fi 연결을 확인해 주세요.',
                    action: (ip) => _ledService.turnOn(ip, brightness: 0.7),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SecondaryButton(
                  label: 'LED OFF',
                  icon: Icons.lightbulb,
                  onTap: () => _runConfigAction(
                    success: 'LED 표시를 껐습니다.',
                    failure:
                        'LED 끄기 실패 · /config 지원 펌웨어와 같은 Wi-Fi 연결을 확인해 주세요.',
                    action: _ledService.turnOff,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SecondaryButton(
            label: 'CO₂ 교정 요청',
            icon: Icons.tune_rounded,
            onTap: () => _runConfigAction(
              success: 'CO₂ 교정 요청을 보냈습니다.',
              failure: 'CO₂ 교정 요청 실패 · 센서 펌웨어와 IP를 확인해 주세요.',
              action: _ledService.requestCo2Calibration,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _test() async {
    final ip = _ip.text.trim();
    if (ip.isEmpty) {
      setState(() {
        _ok = false;
        _result = '센서 로컬 IP를 먼저 입력해 주세요.';
      });
      return;
    }
    await _saveIp();
    try {
      final info = await _localClient.fetchInfo(ip);
      final snapshot = await _localClient.fetchSnapshot(ip);
      if (!mounted) return;
      setState(() {
        _ok = snapshot != null;
        _deviceInfo = info ?? _deviceInfo;
        _result = snapshot == null
            ? '측정값을 읽지 못했습니다 · IP와 같은 Wi-Fi 연결을 확인해 주세요.'
            : '측정값 확인 · PM2.5 ${_fmt(snapshot.pm25)} · CO₂ ${_fmt(snapshot.co2)} ppm · ${_fmt(snapshot.temperature)}°C / ${_fmt(snapshot.humidity)}%';
      });
    } catch (_) {
      setState(() {
        _ok = false;
        _result = '연결 실패 · 휴대폰과 센서가 같은 Wi-Fi인지 확인해 주세요.';
      });
    }
  }

  Future<void> _discoverLocalIp() async {
    if (_discovering) return;
    final binding = context.read<DeviceBindingControllerV2>().value;
    final candidates = binding.isBound
        ? AirGradientMdnsService.sensorIdCandidates(binding.deviceId)
            .map(AirGradientMdnsService.normalizeSensorId)
            .where((value) => value.isNotEmpty)
            .toSet()
        : <String>{};

    setState(() {
      _discovering = true;
      _result = binding.isBound
          ? '등록된 센서를 같은 Wi-Fi에서 찾는 중입니다.'
          : '같은 Wi-Fi의 AirGradient 센서를 찾는 중입니다.';
    });

    try {
      final sensors = await _mdnsService.discover(
        timeout: const Duration(seconds: 5),
      );
      if (!mounted) return;

      DiscoveredAirGradientSensor? matched;
      for (final sensor in sensors) {
        final ids = {
          AirGradientMdnsService.normalizeSensorId(sensor.id),
          AirGradientMdnsService.normalizeSensorId(sensor.displayId),
        }..removeWhere((value) => value.isEmpty);
        if (candidates.isNotEmpty && ids.any((id) => candidates.contains(id))) {
          matched = sensor;
          break;
        }
      }
      matched ??= sensors.length == 1 ? sensors.first : null;

      final ip = matched?.ip?.trim();
      if (ip == null || ip.isEmpty) {
        setState(() {
          _discovering = false;
          _ok = false;
          _result = sensors.isEmpty
              ? '자동 탐색 실패 · 휴대폰과 센서가 같은 Wi-Fi에 있는지 확인해 주세요.'
              : '센서는 찾았지만 IP를 읽지 못했습니다 · 직접 입력하거나 라우터에서 확인해 주세요.';
        });
        return;
      }

      _ip.text = ip;
      await _saveIp();
      if (!mounted) return;
      setState(() {
        _discovering = false;
        _ok = true;
        _result = '센서 IP 자동 확인 · $ip';
      });
      unawaited(_test());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _discovering = false;
        _ok = false;
        _result = '자동 탐색 실패 · 같은 Wi-Fi, 위치 권한, 네트워크 상태를 확인해 주세요.';
      });
    }
  }

  Future<void> _checkFirmwareInfo() async {
    final ip = _ip.text.trim();
    if (ip.isEmpty) {
      setState(() {
        _ok = false;
        _result = '센서 로컬 IP를 먼저 입력해 주세요.';
      });
      return;
    }

    setState(() {
      _busyLocal = true;
      _result = '펌웨어 정보를 확인하는 중입니다.';
    });
    await _saveIp();
    final info = await _localClient.fetchInfo(ip);
    if (!mounted) return;
    setState(() {
      _busyLocal = false;
      _ok = info != null;
      _deviceInfo = info;
      _result = info == null
          ? '펌웨어 정보를 읽지 못했습니다 · /info 또는 /config 지원 펌웨어인지 확인해 주세요.'
          : '펌웨어 확인 · ${info.firmware ?? '버전 정보 없음'}';
    });
  }

  Future<void> _rebootSensor() async {
    final ip = _ip.text.trim();
    if (ip.isEmpty) {
      setState(() {
        _ok = false;
        _result = '센서 로컬 IP를 먼저 입력해 주세요.';
      });
      return;
    }

    setState(() {
      _busyLocal = true;
      _result = '센서 재부팅 요청을 보내는 중입니다.';
    });
    await _saveIp();
    final ok = await _localClient.reboot(ip);
    if (!mounted) return;
    setState(() {
      _busyLocal = false;
      _ok = ok;
      _result = ok
          ? '센서 재부팅 요청 완료 · 약 20초 후 다시 연결 테스트를 눌러 주세요.'
          : '센서 재부팅 실패 · 현재 표준 AirGradient 로컬 서버에는 /reboot가 없을 수 있습니다.';
    });
  }

  void _copyWebUrl(String url) {
    if (url.isEmpty) {
      setState(() {
        _ok = false;
        _result = '센서 로컬 IP를 먼저 입력해 주세요.';
      });
      return;
    }
    unawaited(_saveIp());
    Clipboard.setData(ClipboardData(text: url));
    setState(() => _result = '$url 복사 완료');
  }

  void _openWebUrl(String url) {
    if (url.isEmpty) {
      setState(() {
        _ok = false;
        _result = '센서 로컬 IP를 먼저 입력해 주세요.';
      });
      return;
    }
    unawaited(_saveIp());
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AirGradientWebSettingsPage(url: url),
      ),
    );
  }

  String _fmt(double? value) {
    if (value == null) return '-';
    if (value.abs() >= 100 || value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }

  String _deviceInfoSummary(AirGradientDeviceInfo info) {
    final lines = <String>[
      if ((info.deviceId ?? '').isNotEmpty) '센서 ID ${info.deviceId}',
      if ((info.model ?? '').isNotEmpty) '모델 ${info.model}',
      if ((info.board ?? '').isNotEmpty) '보드 ${info.board}',
      if ((info.hostname ?? '').isNotEmpty) '호스트 ${info.hostname}',
      if ((info.ip ?? '').isNotEmpty) 'IP ${info.ip}',
      if (info.wifiRssi != null) 'Wi-Fi RSSI ${info.wifiRssi!.round()} dBm',
      if ((info.provisionSsid ?? '').isNotEmpty)
        '초기 설정 Wi-Fi ${info.provisionSsid}',
    ];
    return lines.join('\n');
  }

  Future<void> _runConfigAction({
    required String success,
    required String failure,
    required Future<bool> Function(String ip) action,
  }) async {
    final ip = _ip.text.trim();
    if (ip.isEmpty) {
      setState(() {
        _ok = false;
        _result = '센서 로컬 IP를 먼저 입력해 주세요.';
      });
      return;
    }

    await _saveIp();
    final ok = await action(ip);
    if (!mounted) return;
    setState(() {
      _ok = ok;
      _result = ok ? success : failure;
    });
  }
}

class _AirGradientWebSettingsPage extends StatefulWidget {
  const _AirGradientWebSettingsPage({required this.url});

  final String url;

  @override
  State<_AirGradientWebSettingsPage> createState() =>
      _AirGradientWebSettingsPageState();
}

class _AirGradientWebSettingsPageState
    extends State<_AirGradientWebSettingsPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Sx.surface)
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Sx.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Sx.surface,
        foregroundColor: Sx.text,
        title: const Text('AirGradient 웹 설정'),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}

class DeviceSetupPage extends StatefulWidget {
  const DeviceSetupPage({super.key, this.initial});

  final ResponseDevice? initial;

  @override
  State<DeviceSetupPage> createState() => _DeviceSetupPageState();
}

class _DeviceSetupPageState extends State<DeviceSetupPage> {
  final _name = TextEditingController(text: '1층 복도 사이렌');
  final _ip = TextEditingController(text: '192.168.0.24');
  final _deviceTestController = DisasterDeviceTestController();
  String _type = '사이렌';
  String _method = '로컬 IP 제어';
  String _result = '연결 테스트 전입니다.';
  bool _busy = false;
  bool? _powerOn;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _name.text = initial.displayName;
      _ip.text = initial.ip;
      _type = initial.deviceType;
      _method = initial.controlMethod;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _ip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StitchScaffold(
      title: '신규 플러그 등록',
      showBack: true,
      bottom: GradientButton(
        label: '등록하기',
        icon: Icons.arrow_forward_rounded,
        onTap: () => Navigator.of(context).pop(
          ResponseDevice(
            displayName:
                _name.text.trim().isEmpty ? '스마트 플러그' : _name.text.trim(),
            deviceType: _type,
            controlMethod: _method,
            ip: _ip.text.trim(),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StepIndicator(label: 'STEP', current: 1, total: 4),
          const SizedBox(height: 24),
          const CenterIcon(icon: Icons.power_rounded),
          const SizedBox(height: 24),
          Text(
            '전원을 연결해 주세요',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          Text(
            'Tasmota 장치를 센서 위치와 연결하고 ON/OFF 테스트를 실행합니다.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Sx.secondary),
          ),
          const SizedBox(height: 22),
          StitchTextField(controller: _name, label: '장치 이름'),
          const SizedBox(height: 16),
          _ChipSelect(
            label: '장치 유형',
            values: const ['사이렌', '환기팬', '경광등', '스마트 플러그', '밸브 제어 장치', '기타'],
            selected: _type,
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: 16),
          _ChipSelect(
            label: '제어 방식',
            values: const ['로컬 IP 제어', 'MQTT 제어', '클라우드 제어'],
            selected: _method,
            onChanged: (v) => setState(() => _method = v),
          ),
          const SizedBox(height: 16),
          StitchTextField(controller: _ip, label: '플러그 IP'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: _busy ? '테스트 중' : '연결 테스트',
                  onTap: _busy ? () {} : _test,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SecondaryButton(
                  label: _powerOn == true ? '끄기 테스트' : '켜기 테스트',
                  onTap: _busy ? () {} : _toggle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          StitchCard(color: Sx.low, child: Text(_result)),
        ],
      ),
    );
  }

  Future<void> _test() async {
    await _runDeviceTest(_deviceTestController.testConnection);
  }

  Future<void> _toggle() async {
    await _runDeviceTest(
      _powerOn == true
          ? _deviceTestController.testPowerOff
          : _deviceTestController.testPowerOn,
    );
  }

  DisasterDeviceDraft _draftFromFields() {
    final binding = context.read<DeviceBindingControllerV2>().value;
    return DisasterDeviceDraft.empty(
      linkedSensorId: binding.deviceId,
    ).copyWith(
      displayName: _name.text.trim().isEmpty ? '스마트 플러그' : _name.text.trim(),
      deviceType: _type,
      controlMethod: _method,
      plugIp: _ip.text.trim(),
      lastTestStatus: _result,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _runDeviceTest(
    Future<TasmotaDeviceTestResult> Function(DisasterDeviceDraft) runner,
  ) async {
    if (_busy) return;
    final draft = _draftFromFields();
    setState(() {
      _busy = true;
      _result = '장치 응답을 확인하는 중입니다.';
    });
    try {
      final result = await runner(draft);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _powerOn = result.powerOn ?? _powerOn;
        _result = result.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = '연결 실패 · 같은 Wi-Fi와 Tasmota IP를 확인해 주세요.';
      });
    }
  }
}

class AirReading {
  const AirReading({
    required this.pm25,
    required this.co2,
    required this.tvoc,
    required this.nox,
    required this.temperature,
    required this.humidity,
    required this.score,
    required this.liveLabel,
    required this.timestamp,
    required this.hasLiveData,
  });

  factory AirReading.fromController(AirQualityController controller) {
    final s = controller.latestSnapshot;
    return AirReading(
      pm25: s?.pm25 ?? 0,
      co2: s?.co2 ?? 0,
      tvoc: s?.tvoc ?? 0,
      nox: s?.nox ?? 0,
      temperature: s?.temperature ?? 0,
      humidity: s?.humidity ?? 0,
      score: s == null ? _safetyScore(null, 0) : _score(s),
      liveLabel: _liveLabel(controller),
      timestamp: s?.timestamp,
      hasLiveData: s != null,
    );
  }

  final double pm25;
  final double co2;
  final double tvoc;
  final double nox;
  final double temperature;
  final double humidity;
  final int score;
  final String liveLabel;
  final DateTime? timestamp;
  final bool hasLiveData;

  bool get isRisky {
    if (!hasLiveData) return false;
    final alerts = computeAlerts(pm25, co2, humidity, 0);
    final messages = alerts['messages'];
    final hasAlertMessages = messages is List && messages.isNotEmpty;
    return hasAlertMessages ||
        alerts['airQualityAlert'] != null ||
        _statusNeedsAttention(tvocStatus(tvoc)) ||
        _statusNeedsAttention(noxStatus(nox));
  }

  String get safetyLabel {
    if (!hasLiveData) return '연결 대기';
    return isRisky ? '주의 필요' : '안전';
  }

  String get scoreLabel {
    if (!hasLiveData) return '연결 대기';
    final iaqi = calculate_iaqi(
      co2: co2,
      pm25: pm25,
      k: 6.0,
      voc: tvoc,
      temp: temperature,
      humi: humidity,
    );
    return iaqi['sub_level']?.toString() ??
        iaqi['primary_grade']?.toString() ??
        safetyLabel;
  }

  String get disasterSummary {
    if (!hasLiveData) {
      return '센서가 연결되면 이상 패턴 판단이 실시간으로 전환됩니다.';
    }
    if (isRisky) {
      return '환기 부족, 조리/연소원, 외부 먼지 유입 가능성을 순서대로 확인해 주세요.';
    }
    return '현재 관측값은 안정 범위입니다. 최근 변화가 생기면 이 화면에서 바로 표시됩니다.';
  }

  MetricDisplay metric(String label) {
    if (!hasLiveData) {
      return MetricDisplay('-', _metricUnit(label), Sx.secondary);
    }
    switch (label) {
      case 'CO₂':
        return MetricDisplay(
          _format(co2, 0),
          'ppm',
          _metricColor(co2Status(co2)),
        );
      case 'TVOC':
        return MetricDisplay(
          _format(tvoc, 0),
          'index',
          _metricColor(tvocStatus(tvoc)),
        );
      case 'NOx':
        return MetricDisplay(
          _format(nox, 1),
          'index',
          _metricColor(noxStatus(nox)),
        );
      case '온도':
        return MetricDisplay(_format(temperature, 1), '°C', Sx.primary);
      case '습도':
        return MetricDisplay(_format(humidity, 0), '%', Sx.primary);
      default:
        return MetricDisplay(
          _format(pm25, 0),
          'µg/m³',
          _metricColor(pm25Status(pm25)),
        );
    }
  }

  String metricState(String label) {
    if (!hasLiveData) return '연결 대기';
    final value = metric(label).valueNumber;
    if (label == 'CO₂') return _metricAction(co2Status(value), '환기 필요');
    if (label == 'TVOC') return _metricAction(tvocStatus(value), '오염원 확인');
    if (label == 'NOx') return _metricAction(noxStatus(value), '연소원 확인');
    if (label == 'PM2.5') return _metricAction(pm25Status(value), '먼지 높음');
    return '정상';
  }

  String analysisMessage(String label) {
    if (!hasLiveData) {
      return '현재는 연결 대기 기준선입니다. 센서 등록 후 실제 측정값으로 바뀝니다.';
    }
    return '$label 기준으로 최신 측정값과 최근 흐름을 비교합니다.';
  }

  static int _score(AirQualitySnapshot? s) {
    if (s == null) return 0;
    if (s.pm25 == null ||
        s.co2 == null ||
        s.temperature == null ||
        s.humidity == null) {
      return 0;
    }
    final iaqi = calculate_iaqi(
      co2: s.co2!,
      pm25: s.pm25!,
      k: 6.0,
      voc: s.tvoc ?? 100.0,
      temp: s.temperature!,
      humi: s.humidity!,
    );
    final displayIaqi = (iaqi['display_iaqi'] as num?)?.toDouble() ??
        (iaqi['m_score'] as num?)?.toDouble();
    return _safetyScore(displayIaqi, 0);
  }

  static int _safetyScore(double? iaqiScore, int fallback) {
    if (iaqiScore == null || !iaqiScore.isFinite) return fallback;
    if (iaqiScore <= 3) {
      return (100 - iaqiScore * 45).round().clamp(0, 100).toInt();
    }
    return iaqiScore.round().clamp(0, 100).toInt();
  }

  static bool _statusNeedsAttention(String status) {
    return status.contains('주의') ||
        status.contains('나쁨') ||
        status.contains('높음');
  }

  static Color _metricColor(String status) {
    return _statusNeedsAttention(status) ? Sx.warning : Sx.primary;
  }

  static String _metricUnit(String label) {
    return switch (label) {
      'CO₂' => 'ppm',
      'TVOC' => 'index',
      'NOx' => 'index',
      '온도' => '°C',
      '습도' => '%',
      _ => 'µg/m³',
    };
  }

  static String _metricAction(String status, String action) {
    return _statusNeedsAttention(status) ? action : status;
  }

  static String _liveLabel(AirQualityController controller) {
    if (controller.status == LiveDataStatus.connected) return '실시간';
    if (controller.status == LiveDataStatus.connecting) return '연결 중';
    if (controller.status == LiveDataStatus.error) return '연결 확인';
    return '연결 대기';
  }
}

class MetricDisplay {
  MetricDisplay(this.value, this.unit, this.color);

  final String value;
  final String unit;
  final Color color;

  double get valueNumber => double.tryParse(value) ?? 0;
}

class Sx {
  const Sx._();

  static const primary = Color(0xFF00677D);
  static const primary2 = Color(0xFF00B4D8);
  static const primaryText = Color(0xFF003642);
  static const primarySoft = Color(0xFFB3EBFF);
  static const surface = Color(0xFFF5FAFD);
  static const surface2 = Color(0xFFF8FAFB);
  static const surfaceWhite = Colors.white;
  static const low = Color(0xFFEFF4F7);
  static const secondary = Color(0xFF396472);
  static const text = Color(0xFF171C1F);
  static const muted = Color(0xFF6D797E);
  static const warning = Color(0xFFFF9B3D);
  static const warningText = Color(0xFF914D00);
  static const warningSurface = Color(0xFFFFDDB8);
  static const danger = Color(0xFFBA1A1A);
  static const dangerSoft = Color(0xFFFFDAD6);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primary2],
  );

  static List<BoxShadow> get shadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
      ];

  static List<BoxShadow> glow(Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.24),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
      ];
}

class StitchTheme {
  static ThemeData get theme {
    final base = ThemeData(useMaterial3: true, fontFamily: 'Pretendard');
    return base.copyWith(
      scaffoldBackgroundColor: Sx.surface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Sx.primary,
        brightness: Brightness.light,
        surface: Sx.surface,
      ),
      textTheme: base.textTheme.copyWith(
        displayLarge: const TextStyle(
          fontSize: 44,
          fontWeight: FontWeight.w900,
          height: 1.05,
          letterSpacing: 0,
          color: Sx.text,
        ),
        headlineMedium: const TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w900,
          height: 1.18,
          letterSpacing: 0,
          color: Sx.text,
        ),
        headlineSmall: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w900,
          height: 1.2,
          letterSpacing: 0,
          color: Sx.text,
        ),
        titleLarge: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w900,
          height: 1.3,
          letterSpacing: 0,
          color: Sx.text,
        ),
        titleMedium: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          height: 1.35,
          letterSpacing: 0,
          color: Sx.text,
        ),
        bodyMedium: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.45,
          letterSpacing: 0,
          color: Sx.text,
        ),
        bodySmall: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.35,
          letterSpacing: 0,
          color: Sx.secondary,
        ),
        labelLarge: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
          color: Sx.primary,
        ),
      ),
    );
  }
}

class StitchScaffold extends StatelessWidget {
  const StitchScaffold({
    super.key,
    required this.title,
    required this.child,
    this.leadingIcon,
    this.actionIcon,
    this.onLeadingTap,
    this.onActionTap,
    this.showBack = false,
    this.onBack,
    this.bottom,
  });

  final String title;
  final Widget child;
  final IconData? leadingIcon;
  final IconData? actionIcon;
  final VoidCallback? onLeadingTap;
  final VoidCallback? onActionTap;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Sx.surface,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  IconButton(
                    onPressed: showBack
                        ? (onBack ?? () => Navigator.maybePop(context))
                        : onLeadingTap,
                    icon: Icon(
                      showBack
                          ? Icons.arrow_back
                          : (leadingIcon ?? Icons.location_on_outlined),
                    ),
                    color: Sx.primary,
                  ),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: onActionTap,
                    icon: Icon(actionIcon ?? Icons.settings_outlined),
                    color: Sx.primary,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                24,
                20,
                24,
                bottom == null ? 110 : 130,
              ),
              child: child,
            ),
          ),
        ],
      ),
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Sx.surface.withValues(alpha: 0),
                      Sx.surface.withValues(alpha: 0.96),
                      Sx.surface,
                    ],
                  ),
                ),
                child: bottom,
              ),
            ),
    );
  }
}

class StitchTopIdentity extends StatelessWidget {
  const StitchTopIdentity({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(eyebrow, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 7),
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Sx.secondary),
        ),
      ],
    );
  }
}

class StitchCard extends StatelessWidget {
  const StitchCard({
    super.key,
    required this.child,
    this.color = Sx.surfaceWhite,
    this.padding = const EdgeInsets.all(20),
    this.radius = 28,
  });

  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: Sx.shadow,
      ),
      child: child,
    );
  }
}

class _HomeHeroCard extends StatelessWidget {
  const _HomeHeroCard({required this.reading, required this.onTap});

  final AirReading reading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return StitchCard(
      padding: const EdgeInsets.all(24),
      radius: 34,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  reading.isRisky ? '주의가 필요한 공기' : '안전하게 보호받으세요',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              StatusPill(
                label: reading.scoreLabel,
                tone: reading.isRisky ? PillTone.warning : PillTone.primary,
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: 178,
            height: 178,
            child: CustomPaint(
              painter: ScoreRingPainter(
                progress: reading.score / 100,
                color: reading.isRisky ? Sx.warning : Sx.primary2,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${reading.score}',
                      style: Theme.of(context).textTheme.displayLarge,
                    ),
                    const Text(
                      'AQ SCORE',
                      style: TextStyle(color: Sx.secondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            reading.disasterSummary,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Sx.secondary),
          ),
          const SizedBox(height: 20),
          GradientButton(
            label: '상세 분석 보기',
            icon: Icons.arrow_forward_rounded,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.reading});

  final AirReading reading;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('PM2.5', reading.metric('PM2.5'), Icons.blur_on_rounded),
      ('CO₂', reading.metric('CO₂'), Icons.air_rounded),
      ('TVOC', reading.metric('TVOC'), Icons.science_outlined),
      ('NOx', reading.metric('NOx'), Icons.local_fire_department_outlined),
      ('온도', reading.metric('온도'), Icons.thermostat_rounded),
      ('습도', reading.metric('습도'), Icons.water_drop_outlined),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: metrics.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.46,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final (label, value, icon) = metrics[index];
        return StitchCard(
          padding: const EdgeInsets.all(16),
          radius: 22,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: Sx.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              FittedBox(
                child: Text.rich(
                  TextSpan(
                    text: value.value,
                    style: Theme.of(context).textTheme.titleLarge,
                    children: [
                      TextSpan(
                        text: ' ${value.unit}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MiniTrendCard extends StatelessWidget {
  const _MiniTrendCard({
    required this.readings,
    required this.title,
    required this.subtitle,
  });

  final List<AirQualitySnapshot> readings;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return StitchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 104,
            child: CustomPaint(
              painter: TrendPainter(
                values: readings.map((e) => e.pm25 ?? 0).toList(),
                color: Sx.primary2,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionGrid extends StatelessWidget {
  const _QuickActionGrid({required this.actions});

  final List<QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.55,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final action = actions[index];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: action.onTap,
            borderRadius: BorderRadius.circular(24),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                gradient: action.emphasized ? Sx.gradient : null,
                color: action.emphasized ? null : Sx.surfaceWhite,
                borderRadius: BorderRadius.circular(24),
                boxShadow: Sx.shadow,
              ),
              child: Row(
                children: [
                  Icon(
                    action.icon,
                    color: action.emphasized ? Colors.white : Sx.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      action.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: action.emphasized ? Colors.white : Sx.text,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class QuickAction {
  const QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool emphasized;
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.binding, required this.reading});

  final DeviceBindingConfigV2 binding;
  final AirReading reading;

  @override
  Widget build(BuildContext context) {
    return StitchCard(
      color: Sx.low,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('운영 준비', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          _CheckLine(done: binding.isBound, text: 'AirGradient 센서 등록'),
          _CheckLine(done: reading.hasLiveData, text: '실시간 데이터 수신'),
          const _CheckLine(done: true, text: '알림 설정 확인'),
          const _CheckLine(done: true, text: '위치/장치 설정 확인'),
        ],
      ),
    );
  }
}

class _CheckLine extends StatelessWidget {
  const _CheckLine({required this.done, required this.text});

  final bool done;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            color: done ? Sx.primary : Sx.muted,
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _FireRiskHeroCard extends StatelessWidget {
  const _FireRiskHeroCard({
    required this.assessment,
    required this.riskColor,
  });

  final FireRiskAssessment assessment;
  final Color riskColor;

  @override
  Widget build(BuildContext context) {
    return StitchCard(
      color: assessment.isRisky ? Sx.warningSurface : Sx.surfaceWhite,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: riskColor,
              shape: BoxShape.circle,
              boxShadow: Sx.glow(riskColor),
            ),
            child: Icon(
              assessment.isRisky
                  ? Icons.warning_amber_rounded
                  : Icons.check_rounded,
              color: Colors.white,
              size: 42,
            ),
          ),
          const SizedBox(height: 18),
          if (assessment.isRisky) ...[
            Text(
              assessment.headline,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Sx.warningText,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
          ],
          Text(
            assessment.summary,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Sx.secondary),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                label: assessment.levelLabel,
                tone: assessment.isRisky ? PillTone.warning : PillTone.primary,
              ),
              StatusPill(
                label: '위험점수 ${_format(assessment.totalScore, 1)}',
                tone: assessment.isUrgent ? PillTone.warning : PillTone.primary,
              ),
              StatusPill(
                label: '동시위험 ${assessment.riskCount}개',
                tone: assessment.riskCount >= 2
                    ? PillTone.warning
                    : PillTone.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmergencyResponseCard extends StatelessWidget {
  const _EmergencyResponseCard({
    required this.assessment,
    required this.location,
    required this.device,
    required this.busy,
    required this.onCopySituation,
    required this.onPowerOn,
    required this.onOpen119,
    required this.endingSituation,
    required this.onEndSituation,
    required this.onTestAlert,
  });

  final FireRiskAssessment assessment;
  final SensorLocationDraft? location;
  final DisasterDeviceDraft? device;
  final bool busy;
  final VoidCallback onCopySituation;
  final VoidCallback? onPowerOn;
  final VoidCallback onOpen119;
  final bool endingSituation;
  final VoidCallback onEndSituation;
  final VoidCallback onTestAlert;

  @override
  Widget build(BuildContext context) {
    final urgent = assessment.isUrgent;
    final title = urgent ? '긴급 대응' : '대응 준비';
    final body = urgent
        ? '현장을 바로 확인하고, 필요하면 연결 장치를 켠 뒤 119 신고 화면으로 이동하세요.'
        : '위험 단계가 높아지면 이곳에서 상황 요약, 장치 제어, 119 전화 화면을 바로 열 수 있습니다.';
    return StitchCard(
      color: urgent ? Sx.dangerSoft : Sx.low,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CenterBubble(
                icon: urgent
                    ? Icons.notification_important_rounded
                    : Icons.shield_rounded,
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: urgent ? Sx.danger : Sx.text,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      body,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Sx.secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (location != null)
            _MetricRow(
              label: '위치',
              value: [
                location!.spaceName,
                location!.floor,
                location!.detailLocation,
              ].where((value) => value.trim().isNotEmpty).join(' · '),
            ),
          if (device != null)
            _MetricRow(label: '대응 장치', value: device!.displayName),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 150,
                child: SecondaryButton(
                  label: '상황 요약',
                  icon: Icons.copy_rounded,
                  alignStart: true,
                  onTap: onCopySituation,
                ),
              ),
              SizedBox(
                width: 150,
                child: SecondaryButton(
                  label: busy ? '제어 중' : '장치 ON',
                  icon: Icons.power_settings_new_rounded,
                  alignStart: true,
                  onTap: onPowerOn ?? onCopySituation,
                ),
              ),
              if (urgent)
                SizedBox(
                  width: 150,
                  child: SecondaryButton(
                    label: '119 열기',
                    icon: Icons.local_phone_rounded,
                    alignStart: true,
                    onTap: onOpen119,
                  ),
                ),
              SizedBox(
                width: 150,
                child: SecondaryButton(
                  label: '대시보드 전송',
                  icon: Icons.notifications_active_rounded,
                  alignStart: true,
                  onTap: onTestAlert,
                ),
              ),
              SizedBox(
                width: 150,
                child: SecondaryButton(
                  label: endingSituation ? '종료 중' : '상황 종료',
                  icon: Icons.check_circle_rounded,
                  alignStart: true,
                  onTap: onEndSituation,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DisasterSituationBoardCard extends StatelessWidget {
  const _DisasterSituationBoardCard({
    required this.assessment,
    required this.locations,
    required this.devices,
    required this.activeLocation,
    this.onOpenLocation,
  });

  final FireRiskAssessment assessment;
  final List<SensorLocationDraft> locations;
  final List<DisasterDeviceDraft> devices;
  final SensorLocationDraft? activeLocation;
  final VoidCallback? onOpenLocation;

  @override
  Widget build(BuildContext context) {
    final points = _boardPoints();
    return StitchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '상황판',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusPill(
                  label: '센서 ${locations.length} · 장치 ${devices.length}'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '등록된 센서와 대응 장치 위치를 한 화면에서 확인합니다.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Sx.secondary),
          ),
          const SizedBox(height: 14),
          if (points.isEmpty)
            StitchCard(
              color: Sx.low,
              radius: 18,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('센서 위치가 아직 없습니다.'),
                  if (onOpenLocation != null) ...[
                    const SizedBox(height: 10),
                    SecondaryButton(
                      label: '위치 등록',
                      icon: Icons.edit_location_alt_rounded,
                      onTap: onOpenLocation!,
                    ),
                  ],
                ],
              ),
            )
          else
            KakaoMapPreview(
              latitude: points.first.latitude,
              longitude: points.first.longitude,
              label: '방재 상황판',
              height: 240,
              heatPoints: points,
              compactControls: true,
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(label: '방재 ${assessment.levelLabel}'),
              StatusPill(label: '센서 ${locations.length}개'),
              StatusPill(label: '장치 ${devices.length}개'),
            ],
          ),
        ],
      ),
    );
  }

  List<KakaoMapHeatPoint> _boardPoints() {
    final points = <KakaoMapHeatPoint>[];
    final known = <String, SensorLocationDraft>{};
    final allLocations = <SensorLocationDraft>[
      ...locations,
      if (activeLocation != null &&
          !locations.any((item) =>
              item.sensorId.trim() == activeLocation!.sensorId.trim() &&
              item.latitude == activeLocation!.latitude &&
              item.longitude == activeLocation!.longitude))
        activeLocation!,
    ];
    for (final location in allLocations) {
      if (location.latitude == 0 || location.longitude == 0) continue;
      final label =
          location.spaceName.trim().isEmpty ? '센서' : location.spaceName.trim();
      points.add(
        KakaoMapHeatPoint(
          latitude: location.latitude,
          longitude: location.longitude,
          value: 1,
          label: label,
          color: assessment.isUrgent ? Sx.danger : Sx.primary,
          radiusMeters: assessment.isUrgent ? 520 : 360,
          showValue: false,
          showLabel: true,
        ),
      );
      if (location.sensorId.trim().isNotEmpty) {
        known[location.sensorId.trim()] = location;
      }
      if (label.isNotEmpty) known[label] = location;
    }

    for (final device in devices) {
      final linked = known[device.linkedSensorId.trim()] ??
          known[device.linkedSpaceName.trim()] ??
          activeLocation;
      if (linked == null || linked.latitude == 0 || linked.longitude == 0) {
        continue;
      }
      points.add(
        KakaoMapHeatPoint(
          latitude: linked.latitude + 0.00008,
          longitude: linked.longitude + 0.00008,
          value: 0,
          label: device.displayName.trim().isEmpty
              ? '플러그'
              : device.displayName.trim(),
          color: const Color(0xFF2563EB),
          radiusMeters: 260,
          showValue: false,
          showLabel: true,
        ),
      );
    }
    return points;
  }
}

class _ConnectedDeviceSummaryCard extends StatelessWidget {
  const _ConnectedDeviceSummaryCard({
    required this.device,
    required this.devices,
  });

  final DisasterDeviceDraft? device;
  final List<DisasterDeviceDraft> devices;

  @override
  Widget build(BuildContext context) {
    final device = this.device;
    return StitchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('연결 장치', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          Row(
            children: [
              const CenterBubble(icon: Icons.power_rounded, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device?.displayName ?? '연결 장치 없음',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      device == null
                          ? '플러그 탭에서 사이렌, 환기팬, 경광등 등 대응 장치를 등록할 수 있습니다.'
                          : devices.length > 1
                              ? '${device.deviceType} · 등록 장치 ${devices.length}개'
                              : '${device.deviceType} · ${device.lastTestStatus}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Sx.secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DisasterReadinessCard extends StatelessWidget {
  const _DisasterReadinessCard({
    required this.binding,
    required this.reading,
    required this.location,
    required this.devices,
  });

  final DeviceBindingConfigV2 binding;
  final AirReading reading;
  final SensorLocationDraft? location;
  final List<DisasterDeviceDraft> devices;

  @override
  Widget build(BuildContext context) {
    final hasDevice = devices.isNotEmpty;
    final readyDeviceCount = devices
        .where((device) =>
            device.plugIp.trim().isNotEmpty ||
            device.mqttTopic.trim().isNotEmpty)
        .length;
    final hasDeviceTarget = readyDeviceCount > 0;
    return StitchCard(
      color: Sx.low,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('방재 대비 체크', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          _CheckLine(done: binding.isBound, text: 'AirGradient 센서 등록'),
          _CheckLine(done: reading.hasLiveData, text: '실시간 데이터 수신'),
          _CheckLine(done: location != null, text: '센서 위치 등록'),
          _CheckLine(
            done: hasDevice,
            text: hasDevice ? '대응 장치 ${devices.length}개 등록' : '대응 장치 등록',
          ),
          _CheckLine(
            done: hasDeviceTarget,
            text:
                hasDeviceTarget ? '제어 가능 장치 $readyDeviceCount개' : '장치 제어 경로 설정',
          ),
        ],
      ),
    );
  }
}

class _FireRiskCriteriaCard extends StatelessWidget {
  const _FireRiskCriteriaCard({required this.assessment});

  final FireRiskAssessment assessment;

  @override
  Widget build(BuildContext context) {
    return StitchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('판단 기준', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text(
            '최근 60초 평균, 5분 변화량, 여러 지표가 동시에 나빠졌는지, 같은 흐름이 반복되는지를 확인합니다.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Sx.secondary),
          ),
          const SizedBox(height: 14),
          _MetricRow(
            label: '현재 단계',
            value: assessment.levelLabel,
          ),
          _MetricRow(
            label: '동시위험개수',
            value: '${assessment.riskCount}개',
          ),
          _MetricRow(
            label: '최근 5분 반복 감지',
            value: '${assessment.candidateCount}회',
          ),
          _MetricRow(
            label: '지속등급',
            value: assessment.persistenceLabel,
          ),
          _MetricRow(
            label: 'CO 보강',
            value: assessment.coConnected ? '연결됨' : '연결 안 됨',
          ),
          const SizedBox(height: 14),
          StitchCard(
            color: Sx.low,
            radius: 18,
            padding: const EdgeInsets.all(14),
            child: Text(
              assessment.coConnected
                  ? 'CO가 연결되면 CO와 미세먼지가 같이 오르는지, CO 단독 위험이 있는지 따로 확인합니다. CO₂는 환기 부족 신호로만 약하게 반영합니다.'
                  : 'CO 센서가 없을 때는 PM2.5, TVOC, 온도, NOx 중 여러 값이 동시에 나빠지고 반복되는지를 중심으로 판단합니다.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Sx.secondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _FireNotificationPolicyCard extends StatelessWidget {
  const _FireNotificationPolicyCard();

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<NotificationPreferencesController>().value;
    final fireMuted = prefs.mutedTypes['fire_risk'] ?? false;
    final controller = context.read<NotificationPreferencesController>();
    return StitchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('알림 정책', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          SettingSwitchRow(
            title: '방재 알림 받기',
            subtitle: fireMuted ? '방재 푸시 알림 꺼짐' : '경고 이상 상황에서 알림',
            value: !fireMuted,
            onChanged: (value) => controller.setMutedType('fire_risk', !value),
          ),
          const SizedBox(height: 12),
          Text(
            '알림 강도',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SeverityOptionButton(
                label: '경고 이상',
                selected: prefs.fireRiskMinimumLevel == 'warning',
                onTap: () => controller.setFireRiskMinimumLevel('warning'),
              ),
              _SeverityOptionButton(
                label: '강한 경고 이상',
                selected: prefs.fireRiskMinimumLevel == 'strong_warning',
                onTap: () =>
                    controller.setFireRiskMinimumLevel('strong_warning'),
              ),
              _SeverityOptionButton(
                label: '화재 의심/CO 위험',
                selected: prefs.fireRiskMinimumLevel == 'fire_suspected',
                onTap: () =>
                    controller.setFireRiskMinimumLevel('fire_suspected'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _PolicyRow(
            level: '주의',
            body: '공기질이 조금 안좋아진 정도입니다. 별도 푸시는 보내지 않습니다.',
          ),
          const _PolicyRow(
            level: '경고',
            body: '공기질이 나쁘거나 변화가 커질 때 알림을 보냅니다.',
          ),
          const _PolicyRow(
            level: '강한 경고',
            body: '여러 지표가 함께 나빠지면 더 강하게 알립니다.',
          ),
          const _PolicyRow(
            level: '화재 의심 · CO 위험',
            body: '화재나 CO 위험이 강하게 의심되는 단계입니다. 소리와 진동을 사용합니다.',
          ),
          const SizedBox(height: 10),
          StitchCard(
            color: Sx.low,
            radius: 18,
            padding: const EdgeInsets.all(14),
            child: Text(
              '자주 울리는 알림은 무뎌지기 쉽습니다. 낮은 단계는 조용히 두고, 위험도가 높을 때 확실하게 알립니다.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Sx.secondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeverityOptionButton extends StatelessWidget {
  const _SeverityOptionButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Sx.primary : Sx.low,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected ? Sx.shadow : const [],
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: selected ? Colors.white : Sx.text,
                fontWeight: FontWeight.w900,
              ),
        ),
      ),
    );
  }
}

class _PolicyRow extends StatelessWidget {
  const _PolicyRow({
    required this.level,
    required this.body,
  });

  final String level;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusPill(label: level),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              body,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ObservedMetrics extends StatelessWidget {
  const _ObservedMetrics({
    required this.reading,
    required this.assessment,
  });

  final AirReading reading;
  final FireRiskAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final metrics = assessment.metrics;
    return StitchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('주요 관측', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          if (metrics.isEmpty) ...[
            _MetricRow(
              label: 'PM2.5',
              value: '${reading.metric('PM2.5').value} µg/m³',
            ),
            _MetricRow(
              label: 'CO₂',
              value: '${reading.metric('CO₂').value} ppm',
            ),
            _MetricRow(
              label: 'TVOC',
              value: '${reading.metric('TVOC').value} index',
            ),
            _MetricRow(
              label: 'NOx',
              value: '${reading.metric('NOx').value} index',
            ),
          ] else ...[
            for (final metric in metrics) _FireMetricRow(metric: metric),
          ],
          const SizedBox(height: 12),
          StitchCard(
            color: Sx.low,
            radius: 18,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MetricRow(
                  label: '최근 5분 이상 흐름',
                  value:
                      '${assessment.candidateCount}회 · ${assessment.persistenceLabel}',
                ),
                _MetricRow(
                  label: '현재 판단',
                  value: assessment.levelLabel,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FireMetricRow extends StatelessWidget {
  const _FireMetricRow({required this.metric});

  final FireMetricAssessment metric;

  @override
  Widget build(BuildContext context) {
    final color = metric.danger
        ? Sx.danger
        : metric.caution
            ? Sx.warning
            : Sx.secondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(metric.label,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 3),
                Text(
                  '5분 변화 ${metric.formattedRise5}${metric.unit} · 점수 ${metric.formattedScore}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Sx.secondary, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${metric.formattedCurrent}${metric.unit}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 3),
              Text(
                metric.status,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _DetectedLocationCard extends StatelessWidget {
  const _DetectedLocationCard({
    required this.location,
    required this.loading,
    this.onOpenLocation,
  });

  final SensorLocationDraft? location;
  final bool loading;
  final VoidCallback? onOpenLocation;

  @override
  Widget build(BuildContext context) {
    final binding = context.watch<DeviceBindingControllerV2>().value;
    final location = this.location;
    return StitchCard(
      color: Sx.low,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('감지 위치', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CenterBubble(icon: Icons.location_on_rounded, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loading ? '위치 불러오는 중' : location?.spaceName ?? '위치 등록 필요',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      location == null
                          ? '센서 위치를 저장하면 알림과 장치 연결에 표시됩니다.'
                          : [
                              location.buildingName,
                              location.floor,
                              location.detailLocation,
                            ].where((value) => value.trim().isNotEmpty).join(
                                ' · ',
                              ),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Sx.secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MetricRow(
            label: '센서',
            value: binding.isBound ? binding.deviceId : '등록 필요',
          ),
          if (location != null)
            _MetricRow(label: '주소', value: location.address),
          if (onOpenLocation != null) ...[
            const SizedBox(height: 12),
            SecondaryButton(
              label: location == null ? '위치 등록' : '위치 수정',
              icon: Icons.edit_location_alt_rounded,
              onTap: onOpenLocation!,
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionRecommendationCard extends StatelessWidget {
  const _ActionRecommendationCard({required this.assessment});

  final FireRiskAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final actions = assessment.actions;
    return StitchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('권장 조치', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          for (final action in actions) ...[
            Row(
              children: [
                const CenterBubble(icon: Icons.arrow_forward_rounded, size: 34),
                const SizedBox(width: 12),
                Expanded(child: Text(action)),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ConnectedDeviceControlCard extends StatelessWidget {
  const _ConnectedDeviceControlCard({
    required this.device,
    required this.devices,
    required this.selectedIndex,
    required this.onSelectedDevice,
    required this.busy,
    required this.powerOn,
    required this.message,
    required this.onRefresh,
    required this.onTest,
    required this.onPowerOn,
    required this.onPowerOff,
  });

  final DisasterDeviceDraft? device;
  final List<DisasterDeviceDraft> devices;
  final int selectedIndex;
  final ValueChanged<int> onSelectedDevice;
  final bool busy;
  final bool? powerOn;
  final String? message;
  final VoidCallback onRefresh;
  final VoidCallback onTest;
  final VoidCallback onPowerOn;
  final VoidCallback onPowerOff;

  @override
  Widget build(BuildContext context) {
    final device = this.device;
    final usesMqtt =
        device?.controlMethod.toUpperCase().contains('MQTT') ?? false;
    final hasIp = device != null && device.plugIp.trim().isNotEmpty;
    final hasMqtt = device != null && device.mqttTopic.trim().isNotEmpty;
    final isReady = device != null && (usesMqtt ? hasMqtt : hasIp);
    final linkedSpace = device?.linkedSpaceName.trim();
    return StitchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '연결 장치 제어',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusPill(
                label: device == null
                    ? '장치 등록 필요'
                    : isReady
                        ? device.lastTestStatus
                        : usesMqtt
                            ? 'MQTT 설정 필요'
                            : 'IP 설정 필요',
                tone: isReady ? PillTone.primary : PillTone.warning,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (devices.length > 1) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < devices.length; i++) ...[
                    GestureDetector(
                      onTap: () => onSelectedDevice(i),
                      child: StatusPill(
                        label: devices[i].displayName.trim().isEmpty
                            ? '장치 ${i + 1}'
                            : devices[i].displayName.trim(),
                        tone: PillTone.primary,
                        active: i == selectedIndex,
                      ),
                    ),
                    if (i != devices.length - 1) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              const CenterBubble(icon: Icons.power_rounded, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device?.displayName ?? '연결 장치 등록 필요',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      device != null
                          ? '${device.deviceType} · ${device.controlMethod}'
                          : '플러그 탭에서 Tasmota 장치를 등록하면 이 화면에서 바로 테스트할 수 있습니다.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Sx.secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (device != null) ...[
            const SizedBox(height: 12),
            _MetricRow(
              label: '연결 위치',
              value: linkedSpace == null || linkedSpace.isEmpty
                  ? '연결 위치 지정 필요'
                  : linkedSpace,
            ),
            _MetricRow(
              label: usesMqtt ? 'MQTT 토픽' : '로컬 IP',
              value: usesMqtt
                  ? (hasMqtt ? device.mqttTopic : '입력 필요')
                  : (hasIp ? device.plugIp : '입력 필요'),
            ),
            _MetricRow(
              label: '전원 상태',
              value: powerOn == null ? '확인 전' : (powerOn! ? 'ON' : 'OFF'),
            ),
          ],
          if (message != null && message!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            StitchCard(
              color: Sx.low,
              padding: const EdgeInsets.all(14),
              radius: 18,
              child: Text(message!),
            ),
          ],
          const SizedBox(height: 14),
          if (device == null)
            SecondaryButton(
              label: '설정 다시 불러오기',
              icon: Icons.refresh_rounded,
              onTap: onRefresh,
            )
          else
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: busy ? '확인 중' : '연결 테스트',
                    icon: Icons.radar_rounded,
                    onTap: busy ? onRefresh : onTest,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SecondaryButton(
                    label: 'ON',
                    icon: Icons.power_settings_new_rounded,
                    onTap: busy ? onRefresh : onPowerOn,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SecondaryButton(
                    label: 'OFF',
                    icon: Icons.power_off_rounded,
                    onTap: busy ? onRefresh : onPowerOff,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PropagationCard extends StatelessWidget {
  const _PropagationCard({
    required this.assessment,
    required this.location,
    required this.device,
  });

  final FireRiskAssessment assessment;
  final SensorLocationDraft? location;
  final DisasterDeviceDraft? device;

  @override
  Widget build(BuildContext context) {
    final copyText = [
      assessment.copyText,
      if (location != null)
        '위치: ${location!.spaceName} · ${location!.detailLocation}',
      if (device != null)
        '연결 장치: ${device!.displayName} · ${device!.lastTestStatus}',
    ].join('\n');
    return StitchCard(
      color: assessment.isUrgent ? Sx.dangerSoft : Sx.surfaceWhite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            assessment.isUrgent ? assessment.headline : '현재 전달할 긴급 상황은 없습니다',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: assessment.isUrgent ? Sx.danger : Sx.text,
                ),
          ),
          const SizedBox(height: 12),
          Text(assessment.summary),
          const SizedBox(height: 14),
          StitchCard(
            color: Sx.low,
            radius: 18,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MetricRow(
                  label: '현재 상황',
                  value: assessment.levelLabel,
                ),
                _MetricRow(
                  label: '위치',
                  value: location == null
                      ? '위치 미등록'
                      : [
                          location!.spaceName,
                          location!.floor,
                          location!.detailLocation,
                        ].where((value) => value.trim().isNotEmpty).join(' · '),
                ),
                _MetricRow(
                  label: '대응 장치',
                  value: device == null ? '장치 미등록' : device!.displayName,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: '상황 정보 복사',
                  icon: Icons.copy_rounded,
                  onTap: () {
                    Clipboard.setData(
                      ClipboardData(text: copyText),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('상황 요약을 복사했습니다.')),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SituationTimeline extends StatelessWidget {
  const _SituationTimeline({
    required this.assessment,
    required this.device,
  });

  final FireRiskAssessment assessment;
  final DisasterDeviceDraft? device;

  @override
  Widget build(BuildContext context) {
    final binding = context.watch<DeviceBindingControllerV2>().value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('최근 상황 타임라인', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        FutureBuilder<List<_DisasterTimelineEntry>>(
          future: _loadEntries(binding),
          builder: (context, snapshot) {
            final entries = snapshot.data ?? _currentTimelineEntries();
            return Column(
              children: [
                if (entries.isEmpty)
                  StitchCard(
                    color: Sx.low,
                    radius: 18,
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      '최근 기록할 만한 방재 상황은 없습니다.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Sx.secondary),
                    ),
                  )
                else
                  for (var i = 0; i < entries.length; i++)
                    _TimelineTile(
                      time: _formatTimelineTime(entries[i].time),
                      title: entries[i].title,
                      body: entries[i].body,
                      urgent: entries[i].urgent,
                      isLast: i == entries.length - 1,
                    ),
                if (snapshot.hasError) ...[
                  const SizedBox(height: 10),
                  StitchCard(
                    color: Sx.low,
                    radius: 18,
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      '서버 기록을 불러오지 못했습니다. 현재 화면의 판단값은 최신 센서 데이터 기준으로 계속 표시됩니다.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Sx.secondary),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Future<List<_DisasterTimelineEntry>> _loadEntries(
    DeviceBindingConfigV2 binding,
  ) async {
    final entries = _currentTimelineEntries();
    final sensorIds = _timelineSensorCandidates(binding);
    if (sensorIds.isEmpty) return entries;

    Query<Map<String, dynamic>> query =
        FirebaseFirestore.instance.collection('alerts');
    query = sensorIds.length == 1
        ? query.where('sensorId', isEqualTo: sensorIds.first)
        : query.where('sensorId', whereIn: sensorIds.take(10).toList());
    final snapshot = await query.limit(30).get();
    final records = snapshot.docs
        .map((doc) => _DisasterTimelineEntry.fromAlert(doc.data()))
        .whereType<_DisasterTimelineEntry>()
        .toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    entries.addAll(records.take(7));
    return entries.take(8).toList(growable: false);
  }

  List<_DisasterTimelineEntry> _currentTimelineEntries() {
    if (assessment.level == FireRiskLevel.normal ||
        assessment.level == FireRiskLevel.notice) {
      return const <_DisasterTimelineEntry>[];
    }
    return <_DisasterTimelineEntry>[
      _DisasterTimelineEntry.current(assessment, device),
    ];
  }
}

class _DisasterTimelineEntry {
  const _DisasterTimelineEntry({
    required this.time,
    required this.title,
    required this.body,
    this.urgent = false,
  });

  final DateTime time;
  final String title;
  final String body;
  final bool urgent;

  factory _DisasterTimelineEntry.current(
    FireRiskAssessment assessment,
    DisasterDeviceDraft? device,
  ) {
    final deviceStatus = device == null
        ? '연결 장치 등록 필요'
        : '${device.displayName} · ${device.lastTestStatus}';
    return _DisasterTimelineEntry(
      time: DateTime.now(),
      title: assessment.isUrgent ? '현재 위급 판단' : '현재 상태 확인',
      body:
          '${assessment.levelLabel} · 위험점수 ${_format(assessment.totalScore, 1)} · ${assessment.persistenceLabel} · $deviceStatus',
      urgent: assessment.isUrgent,
    );
  }

  static _DisasterTimelineEntry? fromAlert(Map<String, dynamic> data) {
    final time = _parseTimelineDate(data['createdAt'] ?? data['timestamp']);
    if (time == null) return null;
    final type = _readTimelineString(data, 'type');
    final severity = _readTimelineString(data, 'severity');
    final trendMeta = data['trendMeta'];
    final fireCode = trendMeta is Map
        ? trendMeta['code']?.toString().trim()
        : data['code']?.toString().trim();
    final keep = type == 'plug_control' ||
        severity == 'critical' ||
        (type == 'fire_risk' && severity != 'notice');
    if (!keep) return null;
    final title = _firstTimelineText(data, const [
          'title',
          'label',
          'headline',
        ]) ??
        _timelineTitleFor(type);
    final message = _firstTimelineText(data, const ['message']);
    final action =
        _firstTimelineText(data, const ['recommendedAction', 'action']);
    final details = <String>[
      _timelineSeverityLabel(severity),
      if (message != null) message,
      if (action != null) action,
    ].where((value) => value.trim().isNotEmpty).join(' · ');
    return _DisasterTimelineEntry(
      time: time,
      title: title,
      body: details.isEmpty ? '서버 경보 기록' : details,
      urgent: type == 'fire_risk'
          ? fireCode == 'fire_suspected' || fireCode == 'co_only'
          : severity == 'critical',
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.time,
    required this.title,
    required this.body,
    this.urgent = false,
    this.isLast = false,
  });

  final String time;
  final String title;
  final String body;
  final bool urgent;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = urgent ? Sx.danger : Sx.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(time, style: TextStyle(color: color, fontSize: 12)),
        ),
        Column(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 3),
                color: urgent ? Sx.dangerSoft : Sx.surfaceWhite,
              ),
            ),
            if (!isLast) Container(width: 2, height: 78, color: Sx.low),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: StitchCard(
            radius: 20,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(body, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

List<String> _timelineSensorCandidates(DeviceBindingConfigV2 binding) {
  final rawValues = <String>[
    binding.deviceId,
    if (binding.firestoreDocPath.trim().isNotEmpty)
      binding.firestoreDocPath.split('/').last,
  ];
  final candidates = <String>[];
  for (final raw in rawValues) {
    final value = raw.trim();
    if (value.isEmpty) continue;
    for (final candidate in AirGradientMdnsService.sensorIdCandidates(value)) {
      if (candidate.trim().isEmpty || candidates.contains(candidate)) {
        continue;
      }
      candidates.add(candidate);
    }
  }
  return candidates.take(10).toList(growable: false);
}

DateTime? _parseTimelineDate(Object? value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is double) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String _formatTimelineTime(DateTime time) {
  final local = time.toLocal();
  final now = DateTime.now();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  if (now.year == local.year &&
      now.month == local.month &&
      now.day == local.day) {
    return '$hour:$minute';
  }
  return '${local.month}/${local.day} $hour:$minute';
}

String _readTimelineString(Map<String, dynamic> data, String key) {
  return data[key]?.toString().trim() ?? '';
}

String? _firstTimelineText(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

String _timelineTitleFor(String type) {
  return switch (type) {
    'fire_risk' => '화재 의심 기록',
    'plug_control' => '장치 제어 기록',
    'co2_high' => 'CO₂ 상승',
    'pm25_high' => 'PM2.5 상승',
    'tvoc_high' => 'TVOC 상승',
    'nox_high' => 'NOx 상승',
    _ => '경보 기록',
  };
}

String _timelineSeverityLabel(String severity) {
  return switch (severity) {
    'critical' => '위험',
    'warning' => '경고',
    'notice' => '기록',
    _ => '',
  };
}

class _SetupProgress extends StatelessWidget {
  const _SetupProgress({
    required this.binding,
    required this.location,
    required this.device,
  });

  final DeviceBindingConfigV2 binding;
  final InstallLocation? location;
  final ResponseDevice? device;

  @override
  Widget build(BuildContext context) {
    final done = [
      binding.isBound,
      location != null,
      true,
      device != null,
    ].where((e) => e).length;
    return StitchCard(
      color: Sx.primarySoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('설정 진행률', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: done / 4,
              backgroundColor: Colors.white,
              color: Sx.primary,
            ),
          ),
          const SizedBox(height: 10),
          Text('$done/4 단계 완료'),
        ],
      ),
    );
  }
}

class _SetupActionCard extends StatelessWidget {
  const _SetupActionCard({
    required this.stage,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.onTap,
  });

  final String stage;
  final IconData icon;
  final String title;
  final String subtitle;
  final String cta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return StitchCard(
      child: Row(
        children: [
          CenterBubble(icon: icon, size: 58),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stage, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 5),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 5),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          TextButton(onPressed: onTap, child: Text(cta)),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return StitchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Sx.primary),
              const SizedBox(width: 10),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class SettingSwitchRow extends StatelessWidget {
  const SettingSwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: Sx.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SettingsInfoRow extends StatelessWidget {
  const _SettingsInfoRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          CenterBubble(icon: icon, size: 38),
          const SizedBox(width: 12),
          Expanded(child: Text(title)),
          Text(value, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ThresholdRow extends StatelessWidget {
  const _ThresholdRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.titleMedium),
          ),
          Text(value, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.reading,
    required this.metric,
    required this.history,
  });

  final AirReading reading;
  final String metric;
  final List<AirQualitySnapshot> history;

  @override
  Widget build(BuildContext context) {
    final series = _metricSeries(history, metric);
    final latest = reading.metric(metric).value;
    final avg = series.isEmpty
        ? latest
        : _format(series.reduce((a, b) => a + b) / series.length, 1);
    final min = series.isEmpty ? latest : _format(series.reduce(math.min), 1);
    final max = series.isEmpty ? latest : _format(series.reduce(math.max), 1);
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.1,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        _StatTile(label: 'Latest', value: latest),
        _StatTile(label: 'Average', value: avg),
        _StatTile(label: 'Min', value: min),
        _StatTile(label: 'Max', value: max),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return StitchCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      color: Sx.low,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _FloatingBottomNav extends StatelessWidget {
  const _FloatingBottomNav({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.grid_view_outlined, Icons.grid_view_rounded, '홈'),
      (Icons.analytics_outlined, Icons.analytics_rounded, '분석'),
      (Icons.warning_amber_outlined, Icons.warning_amber_rounded, '상황 전파'),
      (Icons.power_outlined, Icons.power_rounded, '방재 대비'),
      (Icons.settings_outlined, Icons.settings_rounded, '설정'),
    ];

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 10),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(34),
          boxShadow: Sx.shadow,
        ),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onChanged(i),
                  borderRadius: BorderRadius.circular(28),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: selectedIndex == i
                          ? Sx.primarySoft
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          selectedIndex == i ? items[i].$2 : items[i].$1,
                          color: selectedIndex == i ? Sx.primary : Sx.muted,
                          size: 22,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          items[i].$3,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: selectedIndex == i ? Sx.primary : Sx.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.icon,
    this.active = true,
    this.tone = PillTone.primary,
  });

  final String label;
  final IconData? icon;
  final bool active;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final color = tone == PillTone.warning ? Sx.warningText : Sx.primary;
    final bg = tone == PillTone.warning ? Sx.warningSurface : Sx.primarySoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active ? bg : Sx.low,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: active ? color : Sx.muted),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: active ? color : Sx.muted,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

enum PillTone { primary, warning }

class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
          decoration: BoxDecoration(
            gradient: Sx.gradient,
            borderRadius: BorderRadius.circular(999),
            boxShadow: Sx.glow(Sx.primary),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: Colors.white),
              ),
              if (icon != null) ...[
                const SizedBox(width: 8),
                Icon(icon, color: Colors.white, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.alignStart = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool alignStart;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Sx.low,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment:
                alignStart ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: Sx.primary),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Sx.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CenterIcon extends StatelessWidget {
  const CenterIcon({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 112,
        height: 112,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: Sx.shadow,
        ),
        child: Icon(icon, color: Sx.primary, size: 58),
      ),
    );
  }
}

class CenterBubble extends StatelessWidget {
  const CenterBubble({super.key, required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Sx.primarySoft,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Sx.primary, size: size * 0.48),
    );
  }
}

class StepIndicator extends StatelessWidget {
  const StepIndicator({
    super.key,
    required this.label,
    required this.current,
    required this.total,
  });

  final String label;
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label $current/$total',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 4,
            value: current / total,
            color: Sx.primary2,
            backgroundColor: Sx.low,
          ),
        ),
      ],
    );
  }
}

class StitchTextField extends StatelessWidget {
  const StitchTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          inputFormatters: inputFormatters,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: Sx.low,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Sx.primary, width: 1.2),
            ),
          ),
        ),
      ],
    );
  }
}

class _SegmentedSelector extends StatelessWidget {
  const _SegmentedSelector({
    required this.values,
    required this.selected,
    required this.onChanged,
  });

  final List<String> values;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final value in values) ...[
            ChoiceChip(
              label: Text(value),
              selected: value == selected,
              onSelected: (_) => onChanged(value),
              selectedColor: Sx.primarySoft,
              backgroundColor: Colors.white,
              showCheckmark: false,
              labelStyle: TextStyle(
                color: value == selected ? Sx.primary : Sx.secondary,
                fontWeight: FontWeight.w900,
              ),
              side: BorderSide.none,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _ChipSelect extends StatelessWidget {
  const _ChipSelect({
    required this.label,
    required this.values,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<String> values;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in values)
              ChoiceChip(
                label: Text(value),
                selected: value == selected,
                onSelected: (_) => onChanged(value),
                selectedColor: Sx.primarySoft,
                backgroundColor: Sx.low,
                showCheckmark: false,
                side: BorderSide.none,
              ),
          ],
        ),
      ],
    );
  }
}

class ScoreRingPainter extends CustomPainter {
  ScoreRingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 9;
    final bg = Paint()
      ..color = Sx.low
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fg = Paint()
      ..shader = const SweepGradient(
        colors: [Sx.primary, Sx.primary2],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bg);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      fg..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant ScoreRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class TrendPainter extends CustomPainter {
  TrendPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Sx.low
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final data = values.where((v) => v.isFinite).toList();
    final series = data.length < 2
        ? List.generate(12, (i) => 18 + math.sin(i / 1.8) * 7 + i * 0.8)
        : data.length > 48
            ? data.sublist(data.length - 48)
            : data;
    final minV = series.reduce(math.min);
    final maxV = series.reduce(math.max);
    final span = math.max(1.0, maxV - minV);

    final fillPath = Path();
    final linePath = Path();
    for (var i = 0; i < series.length; i++) {
      final x = series.length == 1 ? 0.0 : size.width * i / (series.length - 1);
      final y =
          size.height - ((series[i] - minV) / span) * (size.height * 0.74) - 18;
      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant TrendPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}

class _MapCard extends StatelessWidget {
  const _MapCard({required this.location});

  final LocationResult location;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 430,
      decoration: BoxDecoration(
        color: Sx.low,
        borderRadius: BorderRadius.circular(34),
        boxShadow: Sx.shadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: MapPainter())),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  color: Sx.primary,
                  size: 54,
                ),
                StitchCard(
                  radius: 22,
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '${location.buildingName}\n${location.address}\n좌표: ${location.lat.toStringAsFixed(4)}, ${location.lng.toStringAsFixed(4)}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MapPainter extends CustomPainter {
  const MapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE7F4F7),
    );
    final road = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = -1; i < 5; i++) {
      final path = Path()
        ..moveTo(-30, size.height * (0.2 + i * 0.18))
        ..cubicTo(
          size.width * 0.3,
          size.height * (0.1 + i * 0.16),
          size.width * 0.6,
          size.height * (0.4 + i * 0.1),
          size.width + 30,
          size.height * (0.26 + i * 0.15),
        );
      canvas.drawPath(path, road);
    }
    final minor = Paint()
      ..color = Sx.primarySoft.withValues(alpha: 0.45)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 6; i++) {
      canvas.drawLine(
        Offset(size.width * (i / 5), -20),
        Offset(size.width * ((i + 1) / 7), size.height + 20),
        minor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LocationResultTile extends StatelessWidget {
  const _LocationResultTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final LocationResult item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: StitchCard(
        color: selected ? Sx.primarySoft : Colors.white,
        radius: 24,
        child: Row(
          children: [
            const CenterBubble(icon: Icons.location_on_outlined, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.buildingName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    item.address,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.chevron_right_rounded,
              color: Sx.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class LocationResult {
  const LocationResult({
    required this.buildingName,
    required this.address,
    required this.lat,
    required this.lng,
  });

  final String buildingName;
  final String address;
  final double lat;
  final double lng;

  static const results = [
    LocationResult(
      buildingName: '새싹어린이집 본관',
      address: '서울시 강남구 테헤란로 123',
      lat: 37.5665,
      lng: 126.9780,
    ),
    LocationResult(
      buildingName: '새싹어린이집 별관',
      address: '서울시 강남구 테헤란로 125',
      lat: 37.5669,
      lng: 126.9786,
    ),
    LocationResult(
      buildingName: '행복요양원',
      address: '서울시 강남구 테헤란로 130',
      lat: 37.5674,
      lng: 126.9792,
    ),
  ];

  bool matches(String query) {
    final q = query.trim().replaceAll(' ', '');
    if (q.isEmpty) return true;
    return ('$buildingName$address').replaceAll(' ', '').contains(q);
  }
}

class InstallLocation {
  const InstallLocation({
    required this.spaceName,
    required this.facilityType,
    required this.buildingName,
    required this.address,
    required this.floor,
    required this.detail,
    required this.memo,
    required this.lat,
    required this.lng,
  });

  final String spaceName;
  final String facilityType;
  final String buildingName;
  final String address;
  final String floor;
  final String detail;
  final String memo;
  final double lat;
  final double lng;

  String get summary =>
      '$spaceName\n$buildingName · $address\n$facilityType · $floor · $detail';

  Map<String, dynamic> toMap() => {
        'spaceName': spaceName,
        'facilityType': facilityType,
        'buildingName': buildingName,
        'address': address,
        'floor': floor,
        'detail': detail,
        'memo': memo,
        'lat': lat,
        'lng': lng,
      };

  static InstallLocation? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    return InstallLocation(
      spaceName: map['spaceName']?.toString() ?? '',
      facilityType: map['facilityType']?.toString() ?? '',
      buildingName: map['buildingName']?.toString() ?? '',
      address: map['address']?.toString() ?? '',
      floor: map['floor']?.toString() ?? '',
      detail: map['detail']?.toString() ?? '',
      memo: map['memo']?.toString() ?? '',
      lat: (map['lat'] as num?)?.toDouble() ?? 0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ResponseDevice {
  const ResponseDevice({
    required this.displayName,
    required this.deviceType,
    required this.controlMethod,
    required this.ip,
  });

  final String displayName;
  final String deviceType;
  final String controlMethod;
  final String ip;

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        'deviceType': deviceType,
        'controlMethod': controlMethod,
        'ip': ip,
      };

  static ResponseDevice? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    return ResponseDevice(
      displayName: map['displayName']?.toString() ?? '',
      deviceType: map['deviceType']?.toString() ?? '',
      controlMethod: map['controlMethod']?.toString() ?? '',
      ip: map['ip']?.toString() ?? '',
    );
  }
}

class SetupStorage {
  static const _locationKey = 'stitch_location_v1';
  static const _deviceKey = 'stitch_device_v1';

  Future<InstallLocation?> loadLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_locationKey);
    if (raw == null) return null;
    try {
      return InstallLocation.fromMap(
        Map<String, dynamic>.from(jsonDecode(raw)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLocation(InstallLocation location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_locationKey, jsonEncode(location.toMap()));
  }

  Future<ResponseDevice?> loadDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_deviceKey);
    if (raw == null) return null;
    try {
      return ResponseDevice.fromMap(Map<String, dynamic>.from(jsonDecode(raw)));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDevice(ResponseDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceKey, jsonEncode(device.toMap()));
  }
}

List<double> _metricSeries(List<AirQualitySnapshot> history, String metric) {
  return history
      .map((snapshot) {
        switch (metric) {
          case 'CO₂':
            return snapshot.co2;
          case 'TVOC':
            return snapshot.tvoc;
          case 'NOx':
            return snapshot.nox;
          case '온도':
            return snapshot.temperature;
          case '습도':
            return snapshot.humidity;
          default:
            return snapshot.pm25;
        }
      })
      .whereType<double>()
      .toList();
}

String _format(double value, int fractionDigits) {
  if (fractionDigits == 0) {
    return value.round().toString();
  }
  return value.toStringAsFixed(fractionDigits);
}
