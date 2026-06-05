import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:permission_handler/permission_handler.dart' as app_permission;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../models/air_quality_snapshot.dart';
import '../../../../features/disaster_mode/fire_risk_assessment.dart';
import '../../../../features/disaster_device/disaster_device_draft.dart';
import '../../../../features/disaster_device/disaster_device_storage.dart';
import '../../../../features/disaster_device/disaster_device_test_controller.dart';
import '../../../../features/disaster_device/disaster_device_web_settings.dart';
import '../../../../features/disaster_device/tasmota_device_test_result.dart';
import '../../../../features/sensor_location/sensor_location_draft.dart';
import '../../../../features/sensor_location/sensor_location_storage.dart';
import '../../../../services/air_quality_csv_export_service.dart';
import '../../../../services/airgradient_mdns_service.dart';
import '../../../../services/ai_recommendation_service.dart';
import '../../../../services/alert_notification_engine.dart';
import '../../../../services/alert_notification_presenter.dart';
import '../../../../services/background_service.dart';
import '../../../../services/device_binding_service_v2.dart';
import '../../../../services/external_api_service.dart';
import '../../../../services/firestore_snapshot_service.dart';
import '../../../../services/kakao_local_service.dart';
import '../../../../services/notification_preferences.dart';
import '../../../../services/plug_control_history_csv_export_service.dart';
import '../../../../services/profile_asset_link_service.dart';
import '../../../../services/push_notification_service_v2.dart';
import '../../../../state/air_quality_controller.dart';
import '../../../../utils/aqi_calculator.dart';
import '../../../../utils/metric_status.dart';
import '../../../../utils/nodered_health_engine.dart';
import '../../widgets/kakao_map_preview.dart';
import '../shared/cleanair_stitch_widgets.dart';

typedef _HeatmapCell = ({int? day, double? score, Color color, bool selected});
typedef _IaqiBreakdownItem = ({
  String label,
  double value,
  String source,
  Color color,
});
typedef _ChartPoint = ({DateTime time, double value});
typedef _ChartStatusResolver = String Function(double value);
typedef _DataLogRow = ({String a, String b, String c, Color color});

Future<SensorLocationDraft?> _loadLocationForBinding(
  DeviceBindingConfigV2 binding,
) {
  final storage = SensorLocationStorage();
  return binding.isBound
      ? storage.loadForSensor(binding.deviceId)
      : storage.load();
}

Future<bool> _syncProfileAssetLinksIfSignedIn() async {
  if (FirebaseAuth.instance.currentUser == null) return false;
  try {
    await ProfileAssetLinkService().syncCurrentLocalAssets();
    return true;
  } catch (_) {
    // Asset linking is a profile/web-dashboard mirror. The local app flow should
    // keep working even when the network is temporarily unavailable.
    return false;
  }
}

class MainDashboardScreen extends StatelessWidget {
  const MainDashboardScreen({
    super.key,
    this.onLocationSettings,
    this.onNotifications,
    this.onDisasterMode,
    this.onProfile,
    this.onConnectSensor,
    this.onMetricSelected,
  });

  final VoidCallback? onLocationSettings;
  final VoidCallback? onNotifications;
  final VoidCallback? onDisasterMode;
  final VoidCallback? onProfile;
  final VoidCallback? onConnectSensor;
  final ValueChanged<int>? onMetricSelected;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AirQualityController>();
    final bindingController = context.watch<DeviceBindingControllerV2>();
    final binding = bindingController.value;
    final activeRecord = bindingController.activeRecord;
    return FutureBuilder<SensorLocationDraft?>(
      future: _loadLocationForBinding(binding),
      builder: (context, locationSnapshot) {
        return FutureBuilder<DisasterDeviceDraft?>(
          future: DisasterDeviceStorage().load(),
          builder: (context, deviceSnapshot) {
            final location = locationSnapshot.data;
            final data = _DashboardData.from(
              controller,
              binding,
              location,
              activeRecord,
            );
            final fireHistory = controller.rawHistory.isEmpty &&
                    controller.latestSnapshot != null
                ? <AirQualitySnapshot>[controller.latestSnapshot!]
                : controller.rawHistory;
            final fireAssessment = FireRiskAssessment.fromHistory(fireHistory);

            return Container(
              color: const Color(0xFFF7F9FA),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 82, 14, 126),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DashboardLocation(
                            label: data.locationLabel,
                            onTap: bindingController.bindings.length > 1
                                ? () => _showDashboardSensorSwitcher(
                                      context,
                                      bindingController,
                                    )
                                : onLocationSettings,
                          ),
                          const SizedBox(height: 24),
                          _IaqiCard(data: data),
                          const SizedBox(height: 18),
                          _DashboardStatusSummaryCard(
                            data: data,
                            assessment: fireAssessment,
                          ),
                          const SizedBox(height: 22),
                          _InsightCard(data: data, controller: controller),
                          if (data.alertMessages.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            _DashboardAlertCard(messages: data.alertMessages),
                          ],
                          const SizedBox(height: 16),
                          _DashboardMetricGrid(
                            data: data,
                            onMetricSelected: onMetricSelected,
                          ),
                          if (!data.hasLiveData) ...[
                            const SizedBox(height: 22),
                            _DashboardConnectionCard(
                              binding: binding,
                              status: controller.status,
                              lastError: controller.lastError,
                              onConnectSensor: onConnectSensor,
                              onRetry: binding.isBound
                                  ? () => unawaited(
                                        _retryBoundSensorConnection(
                                          context,
                                          binding,
                                        ),
                                      )
                                  : null,
                            ),
                          ],
                          const SizedBox(height: 22),
                          _SafetyExtensionCard(
                            data: data,
                            location: location,
                            device: deviceSnapshot.data,
                          ),
                          const SizedBox(height: 22),
                          _TrendCard(data: data, controller: controller),
                          const SizedBox(height: 22),
                          _PollutantCard(data: data, controller: controller),
                          const SizedBox(height: 22),
                          _HeatmapCard(data: data),
                        ],
                      ),
                    ),
                  ),
                  _CleanAirTopBar(
                    title: 'CleanAir',
                    leading: Symbols.air,
                    trailing: Symbols.notifications,
                    secondaryTrailing: Symbols.account_circle,
                    onNotifications: onNotifications,
                    onProfile: onProfile,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showDashboardSensorSwitcher(
    BuildContext context,
    DeviceBindingControllerV2 controller,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Consumer<DeviceBindingControllerV2>(
          builder: (context, controller, _) {
            final active = controller.value;
            final bindings = controller.bindings;
            return SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x2200677D),
                      blurRadius: 28,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.72,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '표시할 센서',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: CleanColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '선택한 센서의 실시간 데이터와 히스토리를 홈 화면에 표시합니다.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                          color: CleanColors.secondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: bindings.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final record = bindings[index];
                            final selected = record.deviceId == active.deviceId;
                            return _SensorBindingTile(
                              record: record,
                              selected: selected,
                              onSelect: selected
                                  ? null
                                  : () {
                                      unawaited(
                                        controller.selectBinding(
                                          record.deviceId,
                                        ),
                                      );
                                      Navigator.of(sheetContext).pop();
                                    },
                              onLocation: () async {
                                await controller.selectBinding(record.deviceId);
                                if (!sheetContext.mounted) return;
                                Navigator.of(sheetContext).pop();
                                onLocationSettings?.call();
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CleanAirTopBar extends StatelessWidget {
  const _CleanAirTopBar({
    required this.title,
    required this.leading,
    required this.trailing,
    this.secondaryTrailing,
    this.background = const Color(0xFFF5FAFD),
    this.leadingColor = CleanColors.primary,
    this.titleColor = CleanColors.primary,
    this.onLeadingTap,
    this.onTrailingTap,
    this.onNotifications,
    this.onProfile,
  });

  final String title;
  final IconData leading;
  final IconData trailing;
  final IconData? secondaryTrailing;
  final Color background;
  final Color leadingColor;
  final Color titleColor;
  final VoidCallback? onLeadingTap;
  final VoidCallback? onTrailingTap;
  final VoidCallback? onNotifications;
  final VoidCallback? onProfile;

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: safeTop + 64,
        color: background.withValues(alpha: 0.94),
        padding: EdgeInsets.fromLTRB(20, safeTop, 20, 0),
        child: Row(
          children: [
            onLeadingTap == null
                ? const _CleanAirLogoButton()
                : _TapIcon(
                    icon: leading,
                    onTap: onLeadingTap,
                    color: leadingColor,
                    fill: 1,
                  ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontSize: title == 'CleanAir' ? 18 : 20,
                  fontWeight: FontWeight.w900,
                  color: titleColor,
                ),
              ),
            ),
            _TapIcon(
              icon: trailing,
              onTap: onTrailingTap ?? onNotifications,
              color: CleanColors.secondary,
            ),
            if (secondaryTrailing != null) ...[
              const SizedBox(width: 12),
              _TapIcon(
                icon: secondaryTrailing!,
                onTap: onProfile,
                color: CleanColors.secondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _retryBoundSensorConnection(
  BuildContext context,
  DeviceBindingConfigV2 binding,
) async {
  final controller = context.read<AirQualityController>();
  final firestore = context.read<FirestoreSnapshotService>();
  final bindingController = context.read<DeviceBindingControllerV2>();

  await firestore.setFirestoreDocPath(binding.firestoreDocPath);
  await controller.retryConnection();
  if (await firestore.waitForFirstSnapshot(
    timeout: const Duration(seconds: 4),
  )) {
    unawaited(controller.refreshHistoryFromFirestore());
    return;
  }

  final resolvedPath = await firestore.findFirstLiveSensorDocPath(
    _bindingSensorCandidates(binding),
    perCandidateTimeout: const Duration(seconds: 2),
  );
  if (resolvedPath == null || resolvedPath == binding.firestoreDocPath) {
    return;
  }

  final resolvedId = _sensorIdFromDocPath(resolvedPath);
  await bindingController.applyBinding(
    deviceId: resolvedId,
    firestoreDocPath: resolvedPath,
  );
  await firestore.setFirestoreDocPath(resolvedPath);
  await firestore.connect(forceReconnect: true);
  unawaited(controller.refreshHistoryFromFirestore());
}

List<String> _bindingSensorCandidates(DeviceBindingConfigV2 binding) {
  final pathId = _sensorIdFromDocPath(binding.firestoreDocPath);
  final candidates = <String>[
    binding.firestoreDocPath,
    binding.deviceId,
    pathId,
    ...AirGradientMdnsService.sensorIdCandidates(binding.deviceId),
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

String _sensorIdFromDocPath(String path) {
  const prefix = 'sensors/';
  return path.startsWith(prefix) ? path.substring(prefix.length) : path;
}

class _DashboardData {
  const _DashboardData({
    required this.locationLabel,
    required this.score,
    required this.status,
    required this.statusColor,
    required this.insight,
    required this.pm25,
    required this.co2,
    required this.tvoc,
    required this.nox,
    required this.temperature,
    required this.humidity,
    required this.historyScores,
    required this.historyColors,
    required this.heatmapCells,
    required this.rawIaqiScore,
    required this.baseIaqiScore,
    required this.thermalPenalty,
    required this.thermalDeviation,
    required this.iaqiMScore,
    required this.iaqiSeverityScore,
    required this.iaqiBreakdown,
    required this.hasLiveData,
    required this.isRisky,
    required this.alertMessages,
  });

  final String locationLabel;
  final int? score;
  final String status;
  final Color statusColor;
  final String insight;
  final double? pm25;
  final double? co2;
  final double? tvoc;
  final double? nox;
  final double? temperature;
  final double? humidity;
  final List<double> historyScores;
  final List<Color> historyColors;
  final List<_HeatmapCell> heatmapCells;
  final double? rawIaqiScore;
  final double? baseIaqiScore;
  final double thermalPenalty;
  final double thermalDeviation;
  final double? iaqiMScore;
  final double? iaqiSeverityScore;
  final List<_IaqiBreakdownItem> iaqiBreakdown;
  final bool hasLiveData;
  final bool isRisky;
  final List<String> alertMessages;

  factory _DashboardData.from(
    AirQualityController controller,
    DeviceBindingConfigV2 binding,
    SensorLocationDraft? location,
    DeviceBindingRecordV2? activeRecord,
  ) {
    final snapshot = controller.latestSnapshot;
    final sensorName = activeRecord?.label.trim();
    final sensorLabel = sensorName != null && sensorName.isNotEmpty
        ? sensorName
        : binding.deviceId.isNotEmpty
            ? binding.deviceId
            : snapshot?.id ?? '센서 연결 대기';
    final locationLabel = _locationLabel(location, sensorLabel);
    if (snapshot == null) {
      return _DashboardData(
        locationLabel: locationLabel,
        score: null,
        status: '센서 연결 대기',
        statusColor: CleanColors.secondary,
        insight: 'AirGradient 센서를 연결하면 기존 IAQI와 건강 판단 로직으로 실시간 분석이 시작됩니다.',
        pm25: null,
        co2: null,
        tvoc: null,
        nox: null,
        temperature: null,
        humidity: null,
        historyScores: const <double>[],
        historyColors: const <Color>[],
        heatmapCells: _heatmapCells(const <AirQualitySnapshot>[]),
        rawIaqiScore: null,
        baseIaqiScore: null,
        thermalPenalty: 0,
        thermalDeviation: 0,
        iaqiMScore: null,
        iaqiSeverityScore: null,
        iaqiBreakdown: const <_IaqiBreakdownItem>[],
        hasLiveData: false,
        isRisky: false,
        alertMessages: const <String>[],
      );
    }

    final calculatedAqi = _calculateIaqi(snapshot);
    final rawIaqiScore = calculatedAqi?.aqi ?? snapshot.iaqiScore;
    final score = _displayScore(rawIaqiScore, calculatedAqi);
    final status = calculatedAqi == null
        ? (snapshot.aqiCategory ?? '데이터 연결 대기')
        : (calculatedAqi.subLevel ?? calculatedAqi.primaryGrade);
    final pm25 = snapshot.pm25;
    final co2 = snapshot.co2;
    final tvoc = snapshot.tvoc;
    final nox = snapshot.nox;
    final temperature = snapshot.temperature;
    final humidity = snapshot.humidity;
    final history = controller.rawHistory
        .map(_historyEntry)
        .whereType<({double score, Color color})>()
        .toList(growable: false);
    final recentHistory =
        history.length > 7 ? history.sublist(history.length - 7) : history;
    final historyScores =
        recentHistory.map((entry) => entry.score).toList(growable: false);
    final historyColors =
        recentHistory.map((entry) => entry.color).toList(growable: false);
    final alertMessages = _alertMessages(snapshot);

    return _DashboardData(
      locationLabel: locationLabel,
      score: score,
      status: status,
      statusColor: calculatedAqi == null
          ? _colorForStatus(status)
          : _colorFromAqi(calculatedAqi),
      insight: alertMessages.isNotEmpty
          ? alertMessages.first
          : _insightFor(
              aqi: calculatedAqi,
              pm25: pm25,
              co2: co2,
              tvoc: tvoc,
              nox: nox,
              humidity: humidity,
            ),
      pm25: pm25,
      co2: co2,
      tvoc: tvoc,
      nox: nox,
      temperature: temperature,
      humidity: humidity,
      historyScores: historyScores,
      historyColors: historyColors,
      heatmapCells: _heatmapCells(controller.rawHistory, latest: snapshot),
      rawIaqiScore: rawIaqiScore,
      baseIaqiScore: calculatedAqi?.baseIaqi,
      thermalPenalty: calculatedAqi?.thermalPenalty ?? 0,
      thermalDeviation: calculatedAqi?.thermalDeviation ?? 0,
      iaqiMScore: calculatedAqi?.mScore,
      iaqiSeverityScore: calculatedAqi?.eScore,
      iaqiBreakdown: _iaqiBreakdown(snapshot),
      hasLiveData: controller.status == LiveDataStatus.connected,
      isRisky: _isRisky(calculatedAqi, pm25, co2, tvoc, nox, humidity),
      alertMessages: alertMessages,
    );
  }

  static List<String> _alertMessages(AirQualitySnapshot snapshot) {
    return AlertNotificationEngine()
        .extractMessages(snapshot.alerts)
        .take(4)
        .toList(growable: false);
  }

  static String _locationLabel(
    SensorLocationDraft? location,
    String sensorLabel,
  ) {
    final spaceName = location?.spaceName.trim();
    if (spaceName != null && spaceName.isNotEmpty) return spaceName;
    final buildingName = location?.buildingName.trim();
    if (buildingName != null && buildingName.isNotEmpty) return buildingName;
    return sensorLabel;
  }

  static ({double score, Color color})? _historyEntry(
    AirQualitySnapshot sample,
  ) {
    final aqi = _calculateIaqi(sample);
    final score = _rawIaqiScore(sample.iaqiScore, aqi);
    if (score == null) return null;
    return (
      score: score,
      color: aqi == null ? _colorForScore(score) : _colorFromAqi(aqi),
    );
  }

  static AQIResult? _calculateIaqi(AirQualitySnapshot? snapshot) {
    if (snapshot == null || snapshot.pm25 == null || snapshot.co2 == null) {
      return null;
    }
    return calculateComprehensiveAQI(
      snapshot.pm25!,
      co2: snapshot.co2,
      k: snapshot.purification?.cadr?.kEffective ??
          snapshot.purification?.cadr?.k,
      voc: snapshot.tvoc ?? 100.0,
      temp: snapshot.temperature,
      humi: snapshot.humidity,
    );
  }

  static int? _displayScore(double? storedScore, AQIResult? fallback) {
    final raw = storedScore ?? fallback?.aqi;
    if (raw == null) return null;
    final scaled = raw <= 3 ? raw * 100 : raw;
    return scaled.round().clamp(0, 300).toInt();
  }

  static List<_IaqiBreakdownItem> _iaqiBreakdown(
    AirQualitySnapshot snapshot,
  ) {
    final pm25 = snapshot.pm25;
    final co2 = snapshot.co2;
    final tvoc = snapshot.tvoc ?? 100.0;
    if (pm25 == null || co2 == null) {
      return const <_IaqiBreakdownItem>[];
    }

    final values = <({String label, double value, String source})>[
      (
        label: 'CO2',
        value: math.max(0.0, (co2 - 600.0) / 400.0),
        source: '${co2.round()} ppm',
      ),
      (
        label: 'PM2.5',
        value: math.max(0.0, (pm25 - 15.0) / 35.0),
        source: '${_formatMetric(pm25)} µg/m³',
      ),
      (
        label: 'TVOC',
        value: math.max(0.0, (tvoc - 100.0) / 100.0),
        source: '${_formatMetric(tvoc)} index',
      ),
    ];

    final maxValue = values
        .map((entry) => entry.value)
        .fold<double>(0, (max, value) => math.max(max, value));
    return values
        .map(
          (entry) => (
            label: entry.label,
            value: entry.value,
            source: entry.source,
            color: entry.value == maxValue && maxValue > 0
                ? CleanColors.error
                : CleanColors.primary,
          ),
        )
        .toList(growable: false);
  }

  static List<_HeatmapCell> _heatmapCells(
    List<AirQualitySnapshot> history, {
    AirQualitySnapshot? latest,
  }) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final firstWeekdayOffset = monthStart.weekday % 7;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final lastVisibleDay = math.min(now.day, daysInMonth);
    final byDay = <int, List<({double score, Color color})>>{};
    final samples = <AirQualitySnapshot>[
      ...history,
      if (latest != null) latest,
    ];

    for (final sample in samples) {
      final local = sample.timestamp.toLocal();
      if (local.year != now.year || local.month != now.month) continue;
      if (local.isAfter(now)) continue;
      final aqi = _calculateIaqi(sample);
      final score = _rawIaqiScore(sample.iaqiScore, aqi);
      if (score == null) continue;
      byDay
          .putIfAbsent(local.day, () => <({double score, Color color})>[])
          .add((score: score, color: _colorForScore(score)));
    }

    final cells = <_HeatmapCell>[
      for (var i = 0; i < firstWeekdayOffset; i++)
        (
          day: null,
          score: null,
          color: const Color(0xFFE9EEF0),
          selected: false,
        ),
    ];

    for (var day = 1; day <= lastVisibleDay; day++) {
      final scores = byDay[day];
      if (scores == null || scores.isEmpty) {
        cells.add((
          day: day,
          score: null,
          color: const Color(0xFFE9EEF0),
          selected: day == now.day,
        ));
        continue;
      }
      final avg = scores.map((entry) => entry.score).reduce((a, b) => a + b) /
          scores.length;
      cells.add((
        day: day,
        score: avg,
        color: _colorForScore(avg),
        selected: day == now.day,
      ));
    }

    while (cells.length % 7 != 0) {
      cells.add((
        day: null,
        score: null,
        color: const Color(0xFFE9EEF0),
        selected: false,
      ));
    }

    return cells;
  }

  static Color _colorFromAqi(AQIResult aqi) {
    final hex = aqi.color.replaceFirst('#', '');
    final value = int.tryParse('FF$hex', radix: 16);
    return value == null ? CleanColors.primary : Color(value);
  }

  static Color _colorForStatus(String status) {
    if (status.contains('좋음')) return const Color(0xFF00C853);
    if (status.contains('보통')) return const Color(0xFFF9A825);
    if (status.contains('나쁨') || status.contains('위험')) {
      return const Color(0xFFE53935);
    }
    return CleanColors.secondary;
  }

  static double? _rawIaqiScore(double? storedScore, AQIResult? fallback) {
    final raw = fallback?.aqi ?? storedScore;
    if (raw == null || !raw.isFinite) return null;
    return raw.clamp(0.0, 6.0).toDouble();
  }

  static Color _colorForScore(double score) {
    if (score <= 0) return const Color(0xFF00C853);
    if (score < 1) return const Color(0xFFF9A825);
    if (score < 2) return const Color(0xFFFB8C00);
    if (score < 3) return const Color(0xFFE53935);
    if (score < 4) return const Color(0xFFB71C1C);
    return const Color(0xFF7E0023);
  }

  static String _insightFor({
    required AQIResult? aqi,
    required double? pm25,
    required double? co2,
    required double? tvoc,
    required double? nox,
    required double? humidity,
  }) {
    if (aqi != null && aqi.primaryGrade != '좋음') {
      return getAQIRecommendation(aqi);
    }
    if (pm25 != null && co2 != null && humidity != null) {
      final alerts = computeAlerts(pm25, co2, humidity, 0);
      final messages = alerts['messages'];
      if (messages is List && messages.isNotEmpty) {
        return messages.first.toString();
      }
    }
    if (tvoc != null) {
      final tvocState = tvocStatus(tvoc);
      if (_needsAttention(tvocState)) {
        return 'TVOC $tvocState · 환기 및 오염원 확인이 필요합니다.';
      }
    }
    if (nox != null) {
      final noxState = noxStatus(nox);
      if (_needsAttention(noxState)) {
        return 'NOx $noxState · 연소원 또는 외기 유입 영향을 확인하세요.';
      }
    }
    if (aqi == null) {
      return '센서 스냅샷을 수신했습니다. 세부 지표가 들어오는 대로 기존 IAQI 로직으로 분석합니다.';
    }
    return '현재 상태는 안정적입니다. 실외 미세먼지 증가 시 창문을 닫고 짧은 환기만 권장합니다.';
  }

  static bool _isRisky(
    AQIResult? aqi,
    double? pm25,
    double? co2,
    double? tvoc,
    double? nox,
    double? humidity,
  ) {
    if (aqi?.primaryGrade == '나쁨') return true;
    if (pm25 != null && co2 != null && humidity != null) {
      final alerts = computeAlerts(pm25, co2, humidity, 0);
      final messages = alerts['messages'];
      if ((messages is List && messages.isNotEmpty) ||
          alerts['airQualityAlert'] != null) {
        return true;
      }
    }
    return (tvoc != null && _needsAttention(tvocStatus(tvoc))) ||
        (nox != null && _needsAttention(noxStatus(nox)));
  }

  static bool _needsAttention(String status) {
    return status.contains('주의') ||
        status.contains('나쁨') ||
        status.contains('높음');
  }
}

class _DashboardLocation extends StatelessWidget {
  const _DashboardLocation({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Symbols.location_on,
                size: 15,
                fill: 1,
                color: Color(0xFF263238),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF263238),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TapIcon extends StatelessWidget {
  const _TapIcon({
    required this.icon,
    this.onTap,
    this.color = const Color(0xFF52687A),
    this.fill,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final double? fill;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 22, color: color, fill: fill),
      ),
    );
    return button;
  }
}

class _CleanAirLogoButton extends StatelessWidget {
  const _CleanAirLogoButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: const Padding(
        padding: EdgeInsets.all(6),
        child: SizedBox(
          width: 28,
          height: 28,
          child: CleanAirParticleLogo(size: 28),
        ),
      ),
    );
  }
}

class _IaqiCard extends StatelessWidget {
  const _IaqiCard({required this.data});

  final _DashboardData data;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: () => _showIaqiInfoSheet(context, data),
        child: Ink(
          height: 374,
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F7F8),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(248, 248),
                      painter: _IaqiGaugePainter(
                        progress:
                            _iaqiProgressFor(data.rawIaqiScore, data.status),
                        color: data.statusColor,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '통합 공기질 지수 (IAQI)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF263238),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _formatIaqiDisplay(data.rawIaqiScore),
                          style: TextStyle(
                            fontSize: 66,
                            height: 0.95,
                            fontWeight: FontWeight.w900,
                            color: data.statusColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _StatusPill(text: _compactIaqiStatus(data.status)),
                      ],
                    ),
                  ],
                ),
              ),
              _AqiScale(
                rawScore: data.rawIaqiScore,
                status: data.status,
                color: data.statusColor,
              ),
              const SizedBox(height: 10),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Symbols.info,
                    size: 15,
                    color: CleanColors.secondary,
                  ),
                  SizedBox(width: 5),
                  Text(
                    '기준',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: CleanColors.secondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _compactIaqiStatus(String status) {
  return status
      .replaceAll('경미한 악화 (나쁨-1)', '나쁨-1')
      .replaceAll('중간수준 악화 (나쁨-2)', '나쁨-2')
      .replaceAll('심각한 악화 (나쁨-3)', '나쁨-3')
      .replaceAll('매우 위험 (나쁨-4)', '매우 나쁨')
      .replaceAll('나쁨-1', '조금 나쁨')
      .replaceAll('나쁨-2', '나쁨')
      .replaceAll('나쁨-3', '상당히 나쁨')
      .replaceAll('나쁨-4', '매우 나쁨');
}

void _showIaqiInfoSheet(BuildContext context, _DashboardData data) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('통합 공기질 지수', style: _cardTitle),
                  ),
                  _StatusPill(text: _compactIaqiStatus(data.status)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                data.rawIaqiScore == null
                    ? '센서 값이 들어오면 CO₂, PM2.5, TVOC를 기준치와 비교해 통합 공기질지수를 계산합니다.'
                    : '현재 통합 공기질지수는 ${data.rawIaqiScore!.toStringAsFixed(2)}입니다. 기본 공기질 지수에 온습도 기반 열쾌적성 보정을 더해 최종 표시값을 산출합니다.',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                  color: CleanColors.onVariant,
                ),
              ),
              const SizedBox(height: 18),
              _IaqiInfoMetricRow(
                label: 'IAQI',
                value: _formatIaqiDisplay(data.rawIaqiScore),
                description: '통합 공기질지수',
              ),
              _IaqiInfoMetricRow(
                label: 'base',
                value: data.baseIaqiScore?.toStringAsFixed(3) ?? '-',
                description: 'CO₂, PM2.5, TVOC 기준 기본 지수',
              ),
              _IaqiInfoMetricRow(
                label: 'thermal',
                value: '+${data.thermalPenalty.toStringAsFixed(3)}',
                description: '온습도 쾌적 범위 이탈 보정',
              ),
              _IaqiInfoMetricRow(
                label: 'm score',
                value: data.iaqiMScore?.toStringAsFixed(3) ?? '-',
                description: '가장 오염도가 높은 요소의 초과량',
              ),
              _IaqiInfoMetricRow(
                label: 'e score',
                value: data.iaqiSeverityScore?.toStringAsFixed(3) ?? '-',
                description: '나쁨 기준을 얼마나 초과했는지',
              ),
              const SizedBox(height: 18),
              const _IaqiRuleCard(),
              if (data.thermalPenalty > 0) ...[
                const SizedBox(height: 14),
                _ThermalComfortCard(data: data),
              ],
              const SizedBox(height: 14),
              _IaqiBreakdownCard(data: data),
            ],
          ),
        ),
      );
    },
  );
}

class _IaqiInfoMetricRow extends StatelessWidget {
  const _IaqiInfoMetricRow({
    required this.label,
    required this.value,
    required this.description,
  });

  final String label;
  final String value;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: CleanColors.surfaceLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: CleanColors.primary,
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: CleanColors.onSurface,
              ),
            ),
          ),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: CleanColors.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IaqiRuleCard extends StatelessWidget {
  const _IaqiRuleCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5FAFD),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('기준값', style: _cardTitle),
          SizedBox(height: 10),
          _CriteriaLine(
              text:
                  'CO₂는 600ppm 이하를 쾌적한 기준으로 보고, 1000ppm을 넘으면 환기가 필요한 상태로 판단합니다.'),
          SizedBox(height: 8),
          _CriteriaLine(
              text:
                  'PM2.5는 15µg/m³ 이하를 좋은 상태로 보고, 50µg/m³ 이상이면 실내 오염도가 높은 상태로 판단합니다.'),
          SizedBox(height: 8),
          _CriteriaLine(
              text:
                  'TVOC는 센서 고유 index 값으로 표시하며, index 1을 넘으면 냄새나 화학물질 영향이 커진 상태로 판단합니다.'),
          SizedBox(height: 8),
          _CriteriaLine(
              text:
                  '온도 20~26℃, 상대습도 30~60%를 쾌적 범위로 두고, 범위를 벗어난 정도가 크면 통합 지수에 최대 0.5까지 보정합니다.'),
          SizedBox(height: 8),
          _CriteriaLine(
              text: 'NOx는 현재 통합 공기질지수 산식에는 포함하지 않고, 별도 지표와 경보·방재 판단에 사용합니다.'),
        ],
      ),
    );
  }
}

class _ThermalComfortCard extends StatelessWidget {
  const _ThermalComfortCard({required this.data});

  final _DashboardData data;

  @override
  Widget build(BuildContext context) {
    final temp = data.temperature;
    final humidity = data.humidity;
    final cause = [
      if (temp != null) '온도 ${temp.toStringAsFixed(1)}℃',
      if (humidity != null) '습도 ${humidity.toStringAsFixed(0)}%',
    ].join(', ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('열쾌적성 보정', style: _cardTitle),
          const SizedBox(height: 10),
          Text(
            cause.isEmpty
                ? '온습도 값이 쾌적 범위를 벗어나면 최종 지수에 작은 보정값을 더합니다.'
                : '$cause 기준으로 열쾌적성 보정 ${data.thermalPenalty.toStringAsFixed(3)}이 적용됐습니다.',
            style: _caption,
          ),
          const SizedBox(height: 8),
          const _CriteriaLine(
            text:
                '온도 20~26℃, 상대습도 30~60% 안에서는 보정을 더하지 않습니다. 범위를 벗어난 정도가 클수록 최대 0.5까지 더합니다.',
          ),
        ],
      ),
    );
  }
}

class _IaqiBreakdownCard extends StatelessWidget {
  const _IaqiBreakdownCard({required this.data});

  final _DashboardData data;

  @override
  Widget build(BuildContext context) {
    final rows = data.iaqiBreakdown;
    if (!data.hasLiveData || rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Text(
          'CO₂, PM2.5, TVOC 값이 들어오면 어떤 항목이 공기질지수에 가장 크게 영향을 줬는지 표시됩니다.',
          style: _caption,
        ),
      );
    }

    final driver = rows.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F00677D),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('산출 원인', style: _cardTitle),
              const Spacer(),
              _StatusPill(text: '주요 원인 ${driver.label}'),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '산출 원인 지수가 높을수록 해당 항목이 공기질 오염에 더 많이 기여했음을 나타냅니다.',
            style: _caption,
          ),
          const SizedBox(height: 16),
          for (final row in rows) ...[
            _IaqiBreakdownRow(
              label: row.label,
              value: row.value,
              source: row.source,
              color: row.color,
            ),
            if (row != rows.last) const SizedBox(height: 10),
          ],
          if (data.thermalPenalty > 0) ...[
            const SizedBox(height: 10),
            _IaqiBreakdownRow(
              label: '열쾌적성',
              value: data.thermalPenalty,
              source: _thermalBreakdownSource(data),
              color: const Color(0xFFF59E0B),
            ),
          ],
        ],
      ),
    );
  }
}

String _thermalBreakdownSource(_DashboardData data) {
  final parts = <String>[
    if (data.temperature != null) '온도 ${data.temperature!.toStringAsFixed(1)}℃',
    if (data.humidity != null) '습도 ${data.humidity!.toStringAsFixed(0)}%',
  ];
  if (parts.isEmpty) return '온습도 보정 +${data.thermalPenalty.toStringAsFixed(3)}';
  return '${parts.join(', ')} · 보정 +${data.thermalPenalty.toStringAsFixed(3)}';
}

class _IaqiBreakdownRow extends StatelessWidget {
  const _IaqiBreakdownRow({
    required this.label,
    required this.value,
    required this.source,
    required this.color,
  });

  final String label;
  final double value;
  final String source;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final factor = (value / 3).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$label · $source',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: CleanColors.secondary,
                ),
              ),
            ),
            Text(
              value.toStringAsFixed(2),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: factor,
            minHeight: 7,
            color: color,
            backgroundColor: CleanColors.surfaceHigh,
          ),
        ),
      ],
    );
  }
}

class _IaqiGaugePainter extends CustomPainter {
  const _IaqiGaugePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 18;
    final base = Paint()
      ..color = const Color(0xFFE4EAED)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;
    final active = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, -math.pi * 0.92, math.pi * 1.84, false, base);
    canvas.drawArc(
      rect,
      -math.pi * 0.92,
      math.pi * 1.84 * progress.clamp(0.0, 1),
      false,
      active,
    );
  }

  @override
  bool shouldRepaint(covariant _IaqiGaugePainter oldDelegate) {
    return progress != oldDelegate.progress || color != oldDelegate.color;
  }
}

class _AqiScale extends StatelessWidget {
  const _AqiScale({
    required this.rawScore,
    required this.status,
    required this.color,
  });

  final double? rawScore;
  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = _iaqiProgressFor(rawScore, status);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final markerX = width * fraction.clamp(0.0, 1.0);
        return SizedBox(
          height: 78,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final tick in _iaqiScaleTicks)
                Positioned(
                  left: (width * (tick.value / _iaqiScaleMax) - 15)
                      .clamp(0.0, width - 30)
                      .toDouble(),
                  top: 0,
                  width: 30,
                  child: Text(
                    tick.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 8,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF8A969A),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                top: 20,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Row(
                    children: [
                      for (final segment in _iaqiScaleSegments)
                        Expanded(
                          flex: ((segment.end - segment.start) * 100).round(),
                          child: Container(
                            height: 14,
                            color: segment.color,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              for (final tick in _iaqiScaleTicks)
                Positioned(
                  left: width * (tick.value / _iaqiScaleMax),
                  top: 17,
                  child: Container(
                    width: 1,
                    height: 20,
                    color: Colors.white.withValues(alpha: 0.86),
                  ),
                ),
              Positioned(
                left: markerX.clamp(7.0, width - 7.0).toDouble() - 7,
                top: 14,
                child: _IaqiScaleMarker(color: color),
              ),
              for (final label in _iaqiScaleLabels)
                Positioned(
                  left: (width * (label.value / _iaqiScaleMax) - 28)
                      .clamp(0.0, width - 56)
                      .toDouble(),
                  top: 48,
                  width: 56,
                  child: Text(
                    label.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 8,
                      height: 1.15,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF6D797E),
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

typedef _IaqiScaleSegment = ({double start, double end, Color color});
typedef _IaqiScaleLabel = ({double value, String label});

const _iaqiScaleSegments = <_IaqiScaleSegment>[
  (start: 0.0, end: 0.5, color: Color(0xFF19C98A)),
  (start: 0.5, end: 1.0, color: Color(0xFFFFCF22)),
  (start: 1.0, end: 2.0, color: Color(0xFFFF982A)),
  (start: 2.0, end: 3.0, color: Color(0xFFFF4056)),
  (start: 3.0, end: 4.0, color: Color(0xFFB71C1C)),
  (start: 4.0, end: 5.0, color: Color(0xFF8E35E8)),
];

const _iaqiScaleLabels = <_IaqiScaleLabel>[
  (value: 0.25, label: '좋음'),
  (value: 0.75, label: '보통'),
  (value: 1.5, label: '조금 나쁨'),
  (value: 2.5, label: '나쁨'),
  (value: 3.5, label: '상당히 나쁨'),
  (value: 4.5, label: '매우 나쁨'),
];

const _iaqiScaleTicks = <_IaqiScaleLabel>[
  (value: 0.5, label: '0.5'),
  (value: 1.0, label: '1'),
  (value: 2.0, label: '2'),
  (value: 3.0, label: '3'),
  (value: 4.0, label: '4'),
  (value: 5.0, label: '5'),
];

const _iaqiScaleMax = 5.0;

class _IaqiScaleMarker extends StatelessWidget {
  const _IaqiScaleMarker({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 30,
      child: Column(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          CustomPaint(
            size: const Size(13, 10),
            painter: _TrianglePainter(color: color),
          ),
        ],
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

String _formatIaqiDisplay(double? score) {
  if (score == null || !score.isFinite) return '-';
  return score.toStringAsFixed(2);
}

double _iaqiProgressFor(double? rawScore, String status) {
  if (rawScore != null && rawScore.isFinite) {
    return (rawScore / 5.0).clamp(0.0, 1.0).toDouble();
  }
  if (status.contains('매우 나쁨') ||
      status.contains('매우 위험') ||
      status.contains('나쁨-4')) {
    return 4.5 / 5;
  }
  if (status.contains('상당히 나쁨') ||
      status.contains('심각') ||
      status.contains('나쁨-3')) {
    return 3.5 / 5;
  }
  if (status == '나쁨' || status.contains('중간') || status.contains('나쁨-2')) {
    return 2.5 / 5;
  }
  if (status.contains('조금 나쁨') ||
      status.contains('경미') ||
      status.contains('나쁨-1')) {
    return 1.5 / 5;
  }
  if (status.contains('나쁨')) return 1.5 / 5;
  if (status.contains('보통')) return 0.75 / 5;
  if (status.contains('좋음')) return 0.25 / 5;
  return 0.25 / 5;
}

class _DashboardMetricGrid extends StatelessWidget {
  const _DashboardMetricGrid({required this.data, this.onMetricSelected});

  final _DashboardData data;
  final ValueChanged<int>? onMetricSelected;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _DashboardMetric(
        label: 'PM2.5',
        value: data.pm25,
        unit: 'µg/m³',
        status: data.pm25 == null ? '연결 대기' : pm25Status(data.pm25!),
        icon: Symbols.blur_on,
        detailIndex: 0,
      ),
      _DashboardMetric(
        label: 'CO₂',
        value: data.co2,
        unit: 'ppm',
        status: data.co2 == null ? '연결 대기' : co2Status(data.co2!),
        icon: Symbols.air,
        detailIndex: 1,
      ),
      _DashboardMetric(
        label: 'TVOC',
        value: data.tvoc,
        unit: 'index',
        status: data.tvoc == null ? '연결 대기' : tvocStatus(data.tvoc!),
        icon: Symbols.science,
        detailIndex: 2,
      ),
      _DashboardMetric(
        label: 'NOx',
        value: data.nox,
        unit: 'index',
        status: data.nox == null ? '연결 대기' : noxStatus(data.nox!),
        icon: Symbols.local_fire_department,
        detailIndex: 3,
      ),
      _DashboardMetric(
        label: '온도',
        value: data.temperature,
        unit: '°C',
        status: data.temperature == null
            ? '연결 대기'
            : temperatureStatus(data.temperature!),
        icon: Symbols.thermostat,
        fractionDigits: 1,
        detailIndex: 4,
      ),
      _DashboardMetric(
        label: '습도',
        value: data.humidity,
        unit: '%',
        status:
            data.humidity == null ? '연결 대기' : humidityStatus(data.humidity!),
        icon: Symbols.humidity_percentage,
        detailIndex: 5,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1000677D),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '실시간 센서 지표',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: CleanColors.onSurface,
                ),
              ),
              const Spacer(),
              Pill(
                text: data.hasLiveData ? '실시간' : '연결 대기',
                color: data.hasLiveData
                    ? CleanColors.primaryFixed
                    : CleanColors.surfaceLow,
                textColor: data.hasLiveData
                    ? CleanColors.primary
                    : CleanColors.secondary,
                icon: data.hasLiveData ? Symbols.sensors : Symbols.sync,
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: metrics.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.65,
            ),
            itemBuilder: (context, index) {
              final metric = metrics[index];
              return _DashboardMetricTile(
                metric: metric,
                onTap: onMetricSelected == null
                    ? null
                    : () => onMetricSelected!(metric.detailIndex),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DashboardMetric {
  const _DashboardMetric({
    required this.label,
    required this.value,
    required this.unit,
    required this.status,
    required this.icon,
    required this.detailIndex,
    this.fractionDigits = 0,
  });

  final String label;
  final double? value;
  final String unit;
  final String status;
  final IconData icon;
  final int detailIndex;
  final int fractionDigits;
}

class _DashboardMetricTile extends StatelessWidget {
  const _DashboardMetricTile({required this.metric, this.onTap});

  final _DashboardMetric metric;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasValue = metric.value != null;
    final value =
        hasValue ? metric.value!.toStringAsFixed(metric.fractionDigits) : '-';
    return Material(
      color: const Color(0xFFF5FAFD),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(metric.icon,
                      size: 18, color: CleanColors.primary, fill: 1),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      metric.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: CleanColors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              Text.rich(
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: 22,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color:
                        hasValue ? CleanColors.onSurface : CleanColors.outline,
                  ),
                  children: [
                    TextSpan(
                      text: hasValue ? ' ${metric.unit}' : '',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: CleanColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                metric.status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: hasValue ? CleanColors.primary : CleanColors.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardConnectionCard extends StatelessWidget {
  const _DashboardConnectionCard({
    required this.binding,
    required this.status,
    this.lastError,
    this.onConnectSensor,
    this.onRetry,
  });

  final DeviceBindingConfigV2 binding;
  final LiveDataStatus status;
  final String? lastError;
  final VoidCallback? onConnectSensor;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final bound = binding.isBound;
    final connecting = status == LiveDataStatus.connecting;
    final title = bound ? '센서 데이터 연결 확인' : 'AirGradient 센서 연결 필요';
    final message = switch (status) {
      LiveDataStatus.connecting => '센서에서 보내는 실시간 측정값을 기다리는 중입니다.',
      LiveDataStatus.error => '연결 오류가 발생했습니다. 네트워크와 센서 전원을 확인해 주세요.',
      LiveDataStatus.disconnected when bound =>
        '등록된 센서가 있습니다. 다시 연결하면 최신 측정값을 받아올 수 있습니다.',
      _ => '센서 연결을 완료하면 실시간 공기질 분석이 시작됩니다.',
    };
    final actionLabel = bound ? (connecting ? '연결 확인 중' : '다시 연결') : '센서 연결하기';
    final actionIcon = bound ? Symbols.refresh : Symbols.add_link;
    final action = bound ? onRetry : onConnectSensor;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF8FB),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1000677D),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: CleanColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  bound ? Symbols.sensors : Symbols.add_link,
                  color: Colors.white,
                  fill: 1,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: CleanColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bound ? binding.deviceId : 'PIN 또는 로컬 검색으로 등록',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: CleanColors.secondary,
                      ),
                    ),
                    if (bound) ...[
                      const SizedBox(height: 3),
                      Text(
                        binding.firestoreDocPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: CleanColors.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(message, style: _caption),
          if (bound && status != LiveDataStatus.connected) ...[
            const SizedBox(height: 8),
            Text(
              '현재 확인 경로: ${binding.firestoreDocPath}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                height: 1.35,
                fontWeight: FontWeight.w800,
                color: CleanColors.secondary,
              ),
            ),
          ],
          if (lastError != null && lastError!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              lastError!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: CleanColors.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          GradientButton(
            label: actionLabel,
            icon: actionIcon,
            onTap: connecting ? null : action,
          ),
          if (bound && onConnectSensor != null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: connecting ? null : onConnectSensor,
              child: const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '다른 센서 연결',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: CleanColors.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DashboardStatusSummaryCard extends StatelessWidget {
  const _DashboardStatusSummaryCard({
    required this.data,
    required this.assessment,
  });

  final _DashboardData data;
  final FireRiskAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final airTitle = data.alertMessages.isNotEmpty
        ? _alertDisplayTitle(data.alertMessages.first, 0)
        : data.hasLiveData
            ? '공기질 상태'
            : '센서 연결 대기';
    final airText = data.alertMessages.isNotEmpty
        ? data.alertMessages.first
        : data.hasLiveData
            ? '현재 공기질은 ${data.status} 상태입니다.'
            : '센서가 연결되면 실시간 공기질을 표시합니다.';
    final disasterText = assessment.level == FireRiskLevel.normal
        ? '화재 의심 패턴은 보이지 않습니다.'
        : assessment.headline;

    return _SoftCard(
      radius: 22,
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          _DashboardStatusSummaryRow(
            icon: Symbols.air,
            title: airTitle,
            text: airText,
            color: data.alertMessages.isNotEmpty
                ? const Color(0xFFFF8A1C)
                : data.statusColor,
          ),
          const SizedBox(height: 12),
          _DashboardStatusSummaryRow(
            icon: assessment.isUrgent
                ? Symbols.local_fire_department
                : Symbols.shield,
            title: '방재 ${assessment.levelLabel}',
            text: disasterText,
            color: _fireRiskSummaryColor(assessment.level),
          ),
        ],
      ),
    );
  }
}

class _DashboardStatusSummaryRow extends StatelessWidget {
  const _DashboardStatusSummaryRow({
    required this.icon,
    required this.title,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 21, fill: 1),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: CleanColors.onSurface,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: CleanColors.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Color _fireRiskSummaryColor(FireRiskLevel level) {
  return switch (level) {
    FireRiskLevel.fireSuspected || FireRiskLevel.coOnly => CleanColors.error,
    FireRiskLevel.strongWarning => const Color(0xFFC2410C),
    FireRiskLevel.warning => const Color(0xFFFF8A1C),
    FireRiskLevel.notice => const Color(0xFFFFB45C),
    FireRiskLevel.normal => CleanColors.primary,
  };
}

class _InsightCard extends StatefulWidget {
  const _InsightCard({
    required this.data,
    required this.controller,
  });

  final _DashboardData data;
  final AirQualityController controller;

  @override
  State<_InsightCard> createState() => _InsightCardState();
}

class _InsightCardState extends State<_InsightCard> {
  final AiRecommendationService _service = AiRecommendationService();
  AiRecommendation? _recommendation;
  String? _loadedKey;
  AirQualitySnapshot? _lastRequestedSnapshot;
  DateTime? _lastRequestedAt;
  String? _lastRequestedStatus;
  String? _lastRequestedAlerts;
  bool _loading = false;
  static const Duration _minimumRefreshInterval = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _maybeLoadRecommendation();
  }

  @override
  void didUpdateWidget(_InsightCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeLoadRecommendation();
  }

  void _maybeLoadRecommendation() {
    final snapshot = widget.controller.latestSnapshot;
    if (snapshot == null || !widget.data.hasLiveData) return;

    final alertSignature = widget.data.alertMessages.join('|');
    final key = [
      snapshot.id ?? '',
      widget.data.locationLabel,
      widget.data.status,
      alertSignature,
      _metricBucket(snapshot.pm25, 10),
      _metricBucket(snapshot.co2, 150),
      _metricBucket(snapshot.tvoc, 50),
      _metricBucket(snapshot.nox, 1),
      _metricBucket(snapshot.co, 2),
      _metricBucket(widget.data.rawIaqiScore, 0.25),
    ].join(':');
    if (key == _loadedKey || _loading) return;
    if (!_shouldRefreshRecommendation(snapshot, alertSignature)) return;
    _loadedKey = key;
    _loading = true;
    _lastRequestedAt = DateTime.now();
    _lastRequestedSnapshot = snapshot;
    _lastRequestedStatus = widget.data.status;
    _lastRequestedAlerts = alertSignature;

    unawaited(
      _service
          .generate(
        snapshot: snapshot,
        recentHistory: widget.controller.rawHistory.length > 12
            ? widget.controller.rawHistory
                .sublist(widget.controller.rawHistory.length - 12)
            : widget.controller.rawHistory,
        locationLabel: widget.data.locationLabel,
        alertMessages: widget.data.alertMessages,
      )
          .then((value) {
        if (!mounted) return;
        setState(() {
          _recommendation = value;
          _loading = false;
        });
      }).catchError((_) {
        if (!mounted) return;
        setState(() {
          _loading = false;
        });
      }),
    );
  }

  bool _shouldRefreshRecommendation(
    AirQualitySnapshot snapshot,
    String alertSignature,
  ) {
    final previous = _lastRequestedSnapshot;
    if (previous == null || _recommendation == null) return true;

    final statusChanged = widget.data.status != _lastRequestedStatus;
    final alertChanged = alertSignature != _lastRequestedAlerts;
    final elapsed = _lastRequestedAt == null
        ? _minimumRefreshInterval
        : DateTime.now().difference(_lastRequestedAt!);

    if (!statusChanged && !alertChanged && elapsed < _minimumRefreshInterval) {
      return false;
    }

    return statusChanged ||
        alertChanged ||
        _changedBy(previous.pm25, snapshot.pm25, 10) ||
        _changedBy(previous.co2, snapshot.co2, 150) ||
        _changedBy(previous.tvoc, snapshot.tvoc, 50) ||
        _changedBy(previous.nox, snapshot.nox, 1) ||
        _changedBy(previous.co, snapshot.co, 2) ||
        _changedBy(previous.iaqiScore, snapshot.iaqiScore, 0.25);
  }

  static bool _changedBy(double? before, double? after, double threshold) {
    if (before == null || after == null) return before != after;
    return (after - before).abs() >= threshold;
  }

  static String _metricBucket(double? value, double step) {
    if (value == null || !value.isFinite || step <= 0) return '-';
    return (value / step).round().toString();
  }

  @override
  Widget build(BuildContext context) {
    final recommendation = _recommendation;
    final summary = recommendation?.summary.trim().isNotEmpty == true
        ? recommendation!.summary.trim()
        : widget.data.insight;
    final actions = recommendation?.recommendations ?? const <String>[];

    return Container(
      constraints: const BoxConstraints(minHeight: 146),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF252A2B),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.black, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF00B4D8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Symbols.auto_awesome,
                  size: 22,
                  fill: 1,
                  color: Color(0xFF002631),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'AI 공기질 추천',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            _loading && recommendation == null
                ? '최근 센서 흐름을 분석하는 중입니다.'
                : summary,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          _InsightMetricStatusRow(data: widget.data),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final action in actions)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(
                      Symbols.check_circle,
                      size: 14,
                      fill: 1,
                      color: Color(0xFF9BE7F5),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        action,
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE7F6F8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _InsightMetricStatusRow extends StatelessWidget {
  const _InsightMetricStatusRow({required this.data});

  final _DashboardData data;

  @override
  Widget build(BuildContext context) {
    final items = <({String label, String value, String status})>[];
    if (data.co2 != null) {
      items.add((
        label: 'CO₂',
        value: '${data.co2!.round()} ppm',
        status: co2Status(data.co2!),
      ));
    }
    if (data.pm25 != null) {
      items.add((
        label: 'PM2.5',
        value: '${_formatInsightMetricValue(data.pm25!)} µg/m³',
        status: pm25Status(data.pm25!),
      ));
    }
    if (data.tvoc != null) {
      items.add((
        label: 'TVOC',
        value: '${_formatInsightMetricValue(data.tvoc!)} index',
        status: tvocStatus(data.tvoc!),
      ));
    }
    if (items.isEmpty) {
      return const Text(
        '센서 값이 들어오면 현재 상태와 추천을 함께 표시합니다.',
        style: TextStyle(
          fontSize: 11,
          height: 1.35,
          fontWeight: FontWeight.w700,
          color: Color(0xFFB9D7DD),
        ),
      );
    }
    final visible = items.take(2).toList(growable: false);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in visible)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF334143),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${item.label} ${item.value} · ${item.status}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFFE7F6F8),
              ),
            ),
          ),
      ],
    );
  }

  String _formatInsightMetricValue(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value
        .toStringAsFixed(1)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

class _DashboardAlertCard extends StatelessWidget {
  const _DashboardAlertCard({required this.messages});

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      color: const Color(0xFFFFF3E4),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Symbols.notification_important,
                  color: CleanColors.error, size: 22),
              SizedBox(width: 8),
              Text(
                '공기질 경보',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: CleanColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < messages.length; i++) ...[
            _InfoListTile(
              icon: Symbols.warning,
              title: _alertDisplayTitle(messages[i], i),
              subtitle: messages[i],
            ),
            if (i != messages.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

String _alertDisplayTitle(String message, int index) {
  final lower = message.toLowerCase();
  if (lower.contains('co2') ||
      message.contains('CO₂') ||
      message.contains('이산화탄소')) {
    return 'CO₂ 경보';
  }
  if (lower.contains('pm2.5') || message.contains('초미세')) {
    return 'PM2.5 경보';
  }
  if (lower.contains('tvoc') || message.contains('휘발성')) {
    return 'TVOC 경보';
  }
  if (lower.contains('nox') || message.contains('질소')) {
    return 'NOx 경보';
  }
  if (message.contains('온도')) return '온도 경보';
  if (message.contains('습도')) return '습도 경보';
  return index == 0 ? '공기질 경보' : '경보 ${index + 1}';
}

class _SafetyExtensionCard extends StatelessWidget {
  const _SafetyExtensionCard({
    required this.data,
    required this.location,
    required this.device,
  });

  final _DashboardData data;
  final SensorLocationDraft? location;
  final DisasterDeviceDraft? device;

  @override
  Widget build(BuildContext context) {
    final risky = data.isRisky;
    final deviceReady = device != null &&
        (device!.plugIp.trim().isNotEmpty ||
            device!.mqttTopic.trim().isNotEmpty);
    final locationLabel = location?.spaceName ?? data.locationLabel;
    return Material(
      color: Colors.transparent,
      child: Ink(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: risky ? const Color(0xFFFFF3E4) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1400677D),
              blurRadius: 22,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: risky
                        ? const Color(0xFFFFB45C)
                        : CleanColors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    risky ? Symbols.warning : Symbols.shield,
                    color: Colors.white,
                    fill: 1,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        risky ? '방재 상태 확인' : '방재 상태 안정',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: CleanColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$locationLabel · ${deviceReady ? device!.displayName : '응답 장치 설정 필요'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          color: CleanColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Pill(
                  text: location == null ? '위치 등록 필요' : '위치 연결됨',
                  color: location == null
                      ? CleanColors.surfaceLow
                      : CleanColors.primaryFixed,
                  textColor: location == null
                      ? CleanColors.secondary
                      : CleanColors.primary,
                  icon: Symbols.location_on,
                ),
                Pill(
                  text: deviceReady ? device!.lastTestStatus : '응답 장치 필요',
                  color: deviceReady
                      ? CleanColors.primaryFixed
                      : CleanColors.surfaceLow,
                  textColor:
                      deviceReady ? CleanColors.primary : CleanColors.secondary,
                  icon: Symbols.power_settings_new,
                ),
                Pill(
                  text: risky ? '원인 확인' : '화재 의심 아님',
                  color:
                      risky ? const Color(0xFFFFE1BD) : CleanColors.surfaceLow,
                  textColor:
                      risky ? const Color(0xFF9A4D00) : CleanColors.secondary,
                  icon: risky ? Symbols.priority_high : Symbols.check_circle,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendCard extends StatefulWidget {
  const _TrendCard({required this.data, required this.controller});

  final _DashboardData data;
  final AirQualityController controller;

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  _LogRange _range = _LogRange.day;
  bool _asBars = false;

  @override
  Widget build(BuildContext context) {
    final points = _dashboardIaqiPoints(widget.controller, _range);
    final values = points.map((point) => point.value).toList(growable: false);
    final lastPoint = points.isEmpty ? null : points.last;
    final chartWindow = _chartWindowForRange(_range, points);
    return Container(
      height: 244,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F5),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '실시간 추세',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF263238),
                ),
              ),
              const Spacer(),
              _LightChip(
                _asBars ? '막대' : '선형',
                selected: true,
                onTap: () => setState(() => _asBars = !_asBars),
              ),
              const SizedBox(width: 6),
              const Icon(
                Symbols.trending_up,
                size: 19,
                color: Color(0xFF00677D),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'IAQI: ${_formatIaqiDisplay(widget.data.rawIaqiScore)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(
                  text: '  상태: ${widget.data.status}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: widget.data.statusColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _RangeChipRow(
                    range: _range,
                    onChanged: (range) => setState(() => _range = range),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                lastPoint == null
                    ? '시간 대기'
                    : '최근 ${_chartTimeLabel(lastPoint.time)}',
                style: _tinyMuted,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _LineChartPanel(
              values: values,
              points: points,
              unit: 'IAQI',
              asBars: _asBars,
              height: 96,
              rangeStart: chartWindow.start,
              rangeEnd: chartWindow.end,
              statusOf: _iaqiChartStatus,
            ),
          ),
        ],
      ),
    );
  }
}

class _PollutantCard extends StatefulWidget {
  const _PollutantCard({required this.data, required this.controller});

  final _DashboardData data;
  final AirQualityController controller;

  @override
  State<_PollutantCard> createState() => _PollutantCardState();
}

class _PollutantCardState extends State<_PollutantCard> {
  _DashboardPollutant _selected = _DashboardPollutant.pm25;
  _LogRange _range = _LogRange.day;
  bool _asBars = false;

  @override
  Widget build(BuildContext context) {
    final series =
        _dashboardPollutantSeries(widget.controller, _selected, _range);
    final hasHistory = series.values.isNotEmpty;
    final chartWindow = _chartWindowForRange(_range, series.points);
    final maxValue = hasHistory ? _formatMetric(series.maxValue!) : '-';
    final minValue = hasHistory ? _formatMetric(series.minValue!) : '-';

    return Container(
      height: 548,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F5),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                '오염 물질 분석',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              _LightChip(
                '선형',
                selected: !_asBars,
                onTap: () => setState(() => _asBars = false),
              ),
              const SizedBox(width: 6),
              _LightChip(
                '막대',
                selected: _asBars,
                onTap: () => setState(() => _asBars = true),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final pollutant in _DashboardPollutant.values) ...[
                  _LightChip(
                    _dashboardPollutantLabel(pollutant),
                    selected: _selected == pollutant,
                    onTap: () => setState(() => _selected = pollutant),
                  ),
                  if (pollutant != _DashboardPollutant.values.last)
                    const SizedBox(width: 7),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _RangeChipRow(
                    range: _range,
                    onChanged: (range) => setState(() => _range = range),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showDashboardChartSheet(
                  context,
                  title: series.title,
                  values: series.values,
                  points: series.points,
                  unit: series.unit,
                  asBars: _asBars,
                  range: _range,
                  statusOf: series.statusOf,
                ),
                child: const _IconSquare(Symbols.open_in_full),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showDashboardChartSheet(
                  context,
                  title: '${series.title} 확대 보기',
                  values: series.values,
                  points: series.points,
                  unit: series.unit,
                  asBars: _asBars,
                  range: _range,
                  statusOf: series.statusOf,
                ),
                child: const _IconSquare(Symbols.search),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(series.icon, size: 20, color: CleanColors.primary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${series.title} · ${_rangeLabel(_range)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: CleanColors.secondary,
                  ),
                ),
              ),
              _StatusPill(text: series.status),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFD9DEE0)),
          const SizedBox(height: 18),
          Expanded(
            child: hasHistory
                ? _LineChartPanel(
                    values: series.values,
                    points: series.points,
                    unit: series.unit,
                    asBars: _asBars,
                    height: 170,
                    rangeStart: chartWindow.start,
                    rangeEnd: chartWindow.end,
                    statusOf: series.statusOf,
                  )
                : const Center(
                    child: Text(
                      '센서 히스토리 연결 대기',
                      style: _tinyMuted,
                    ),
                  ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _MetricText(
                    label: '최대',
                    value: maxValue,
                    unit: series.unit,
                    red: true,
                  ),
                ),
                Expanded(
                  child: _MetricText(
                    label: '최소',
                    value: minValue,
                    unit: series.unit,
                  ),
                ),
                const CircleAvatar(
                  radius: 3,
                  backgroundColor: Color(0xFF00677D),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.data.hasLiveData ? '실시간 데이터' : '연결 대기',
                  style: _tinyMuted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _DashboardPollutant { pm25, co2, tvoc, nox }

class _DashboardPollutantSeries {
  const _DashboardPollutantSeries({
    required this.title,
    required this.unit,
    required this.status,
    required this.icon,
    required this.values,
    required this.points,
    required this.statusOf,
    required this.maxValue,
    required this.minValue,
  });

  final String title;
  final String unit;
  final String status;
  final IconData icon;
  final List<double> values;
  final List<_ChartPoint> points;
  final _ChartStatusResolver statusOf;
  final double? maxValue;
  final double? minValue;
}

List<_ChartPoint> _dashboardIaqiPoints(
  AirQualityController controller,
  _LogRange range,
) {
  final samples = _historyForRange(controller, range);
  final points = samples
      .map((sample) {
        final aqi = _DashboardData._calculateIaqi(sample);
        final score = _DashboardData._rawIaqiScore(sample.iaqiScore, aqi);
        if (score == null) return null;
        return (time: sample.timestamp, value: score);
      })
      .whereType<_ChartPoint>()
      .toList(growable: false);
  if (points.isNotEmpty) {
    return points.length > 48 ? _downsampleChartPoints(points, 48) : points;
  }

  final latest = controller.latestSnapshot;
  if (latest == null) return const <_ChartPoint>[];
  final aqi = _DashboardData._calculateIaqi(latest);
  final score = _DashboardData._rawIaqiScore(latest.iaqiScore, aqi);
  if (score == null) return const <_ChartPoint>[];
  return <_ChartPoint>[(time: latest.timestamp, value: score)];
}

_DashboardPollutantSeries _dashboardPollutantSeries(
  AirQualityController controller,
  _DashboardPollutant pollutant,
  _LogRange range,
) {
  final samples = _historyForRange(controller, range);
  final latest = controller.latestSnapshot;
  final title = _dashboardPollutantTitle(pollutant);
  final unit = _dashboardPollutantUnit(pollutant);
  final icon = _dashboardPollutantIcon(pollutant);
  final valueOf = _dashboardPollutantValueGetter(pollutant);
  final statusOf = _dashboardPollutantStatusGetter(pollutant);

  var points = samples
      .map((sample) {
        final value = valueOf(sample);
        if (value == null || !value.isFinite) return null;
        return (time: sample.timestamp, value: value);
      })
      .whereType<_ChartPoint>()
      .toList(growable: false);
  if (points.length > 48) {
    points = _downsampleChartPoints(points, 48);
  }

  final latestValue = valueOf(latest);
  if (points.isEmpty && latestValue != null && latestValue.isFinite) {
    points = <_ChartPoint>[(time: latest!.timestamp, value: latestValue)];
  }
  final values = points.map((point) => point.value).toList(growable: false);

  return _DashboardPollutantSeries(
    title: title,
    unit: unit,
    status: latestValue == null ? '연결 대기' : statusOf(latestValue),
    icon: icon,
    values: values,
    points: points,
    statusOf: statusOf,
    maxValue: values.isEmpty ? null : values.reduce(math.max),
    minValue: values.isEmpty ? null : values.reduce(math.min),
  );
}

List<_ChartPoint> _downsampleChartPoints(
  List<_ChartPoint> points,
  int maxPoints,
) {
  if (points.length <= maxPoints) return points;
  final result = <_ChartPoint>[];
  for (var i = 0; i < maxPoints; i++) {
    final start = (i * points.length / maxPoints).floor();
    final end = (((i + 1) * points.length / maxPoints).floor())
        .clamp(start + 1, points.length)
        .toInt();
    final bucket = points.sublist(start, end);
    final avg = bucket.map((point) => point.value).reduce((a, b) => a + b) /
        bucket.length;
    result.add((time: bucket[bucket.length ~/ 2].time, value: avg));
  }
  return result;
}

String _dashboardPollutantLabel(_DashboardPollutant pollutant) {
  return switch (pollutant) {
    _DashboardPollutant.pm25 => 'PM2.5',
    _DashboardPollutant.co2 => 'CO₂',
    _DashboardPollutant.tvoc => 'TVOC',
    _DashboardPollutant.nox => 'NOx',
  };
}

String _dashboardPollutantTitle(_DashboardPollutant pollutant) {
  return switch (pollutant) {
    _DashboardPollutant.pm25 => 'PM2.5 초미세먼지',
    _DashboardPollutant.co2 => 'CO₂ 이산화탄소',
    _DashboardPollutant.tvoc => 'TVOC 총휘발성유기화합물',
    _DashboardPollutant.nox => 'NOx 질소산화물',
  };
}

String _dashboardPollutantUnit(_DashboardPollutant pollutant) {
  return switch (pollutant) {
    _DashboardPollutant.pm25 => 'µg/m³',
    _DashboardPollutant.co2 => 'ppm',
    _DashboardPollutant.tvoc => 'index',
    _DashboardPollutant.nox => 'index',
  };
}

IconData _dashboardPollutantIcon(_DashboardPollutant pollutant) {
  return switch (pollutant) {
    _DashboardPollutant.pm25 => Symbols.blur_on,
    _DashboardPollutant.co2 => Symbols.co2,
    _DashboardPollutant.tvoc => Symbols.science,
    _DashboardPollutant.nox => Symbols.cloud,
  };
}

double? Function(AirQualitySnapshot?) _dashboardPollutantValueGetter(
  _DashboardPollutant pollutant,
) {
  return switch (pollutant) {
    _DashboardPollutant.pm25 => (sample) => sample?.pm25,
    _DashboardPollutant.co2 => (sample) => sample?.co2,
    _DashboardPollutant.tvoc => (sample) => sample?.tvoc,
    _DashboardPollutant.nox => (sample) => sample?.nox,
  };
}

String Function(double) _dashboardPollutantStatusGetter(
  _DashboardPollutant pollutant,
) {
  return switch (pollutant) {
    _DashboardPollutant.pm25 => pm25Status,
    _DashboardPollutant.co2 => co2Status,
    _DashboardPollutant.tvoc => tvocStatus,
    _DashboardPollutant.nox => noxStatus,
  };
}

void _showDashboardChartSheet(
  BuildContext context, {
  required String title,
  required List<double> values,
  required List<_ChartPoint> points,
  required String unit,
  required bool asBars,
  _LogRange? range,
  _ChartStatusResolver? statusOf,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => _ExpandedChartScreen(
        title: title,
        values: values,
        points: points,
        unit: unit,
        asBars: asBars,
        range: range,
        statusOf: statusOf,
      ),
    ),
  );
}

class _ExpandedChartScreen extends StatefulWidget {
  const _ExpandedChartScreen({
    required this.title,
    required this.values,
    required this.points,
    required this.unit,
    required this.asBars,
    this.range,
    this.statusOf,
  });

  final String title;
  final List<double> values;
  final List<_ChartPoint> points;
  final String unit;
  final bool asBars;
  final _LogRange? range;
  final _ChartStatusResolver? statusOf;

  @override
  State<_ExpandedChartScreen> createState() => _ExpandedChartScreenState();
}

class _ExpandedChartScreenState extends State<_ExpandedChartScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setPreferredOrientations(
        const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      ),
    );
  }

  @override
  void dispose() {
    unawaited(
      SystemChrome.setPreferredOrientations(
        const [DeviceOrientation.portraitUp],
      ),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rangeLabel = widget.points.isEmpty
        ? '센서 히스토리가 연결되면 선택한 범위의 시간축이 표시됩니다.'
        : '${_chartTimeLabel(widget.points.first.time)} - ${_chartTimeLabel(widget.points.last.time)}';
    return Scaffold(
      backgroundColor: const Color(0xFFF5FAFD),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            children: [
              Row(
                children: [
                  _CleanAirLogoButton(onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: CleanColors.onSurface,
                      ),
                    ),
                  ),
                  _StatusPill(text: '${widget.values.length}개 샘플'),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Symbols.close, color: CleanColors.primary),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _SoftCard(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  radius: 18,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final chartWindow = widget.range == null
                          ? null
                          : _chartWindowForRange(widget.range!, widget.points);
                      return _LineChartPanel(
                        values: widget.values,
                        points: widget.points,
                        unit: widget.unit,
                        asBars: widget.asBars,
                        height: constraints.maxHeight,
                        rangeStart: chartWindow?.start,
                        rangeEnd: chartWindow?.end,
                        statusOf: widget.statusOf,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(rangeLabel, style: _caption),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeatmapCard extends StatelessWidget {
  const _HeatmapCard({required this.data});

  final _DashboardData data;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      constraints: const BoxConstraints(minHeight: 356),
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '월간 공기질 히트맵',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
              const Icon(
                Symbols.calendar_month,
                size: 16,
                color: Color(0xFF263238),
              ),
              const SizedBox(width: 6),
              Text(
                '${now.year}년 ${now.month}월',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 26),
          _CalendarGrid(data: data),
          const SizedBox(height: 22),
          const Divider(height: 1, color: Color(0xFFE8ECEE)),
          const SizedBox(height: 18),
          const Wrap(
            spacing: 18,
            runSpacing: 12,
            children: [
              _LegendDot('좋음', Color(0xFF18C98A)),
              _LegendDot('보통', Color(0xFFFFCF22)),
              _LegendDot('나쁨', Color(0xFFFF982A)),
              _LegendDot('매우 나쁨', Color(0xFFFF4056)),
              _LegendDot('위험', Color(0xFF8E35E8)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({required this.data});

  final _DashboardData data;

  @override
  Widget build(BuildContext context) {
    const days = ['일', '월', '화', '수', '목', '금', '토'];
    final cells = data.heatmapCells;
    return Column(
      children: [
        Row(
          children: [
            for (final day in days)
              Expanded(
                child: Center(child: Text(day, style: _tinyMuted)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 8,
          children: [
            for (final cell in cells)
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cell.color,
                  borderRadius: BorderRadius.circular(8),
                  border: cell.selected
                      ? Border.all(color: Colors.black, width: 3)
                      : null,
                ),
                child: Text(
                  cell.day == null
                      ? ''
                      : cell.score == null
                          ? '${cell.day}\n-'
                          : '${cell.day}\n${_formatIaqiDisplay(cell.score)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: cell.day == null
                        ? Colors.transparent
                        : cell.score == null
                            ? CleanColors.onVariant
                            : Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MetricText extends StatelessWidget {
  const _MetricText({
    required this.label,
    required this.value,
    required this.unit,
    this.red = false,
  });

  final String label;
  final String value;
  final String unit;
  final bool red;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label\n', style: _tinyMuted),
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: red ? const Color(0xFFE80018) : const Color(0xFF009A6A),
            ),
          ),
          const TextSpan(
            text: ' ',
            style: TextStyle(fontSize: 9, color: Colors.black),
          ),
          TextSpan(
            text: unit,
            style: const TextStyle(fontSize: 9, color: Colors.black),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE1C6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: Color(0xFF5D2F00),
        ),
      ),
    );
  }
}

class _LightChip extends StatelessWidget {
  const _LightChip(this.label, {this.selected = false, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.white : const Color(0xFFE8EEF0),
          borderRadius: BorderRadius.circular(9),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: selected ? CleanColors.primary : CleanColors.onSurface,
          ),
        ),
      ),
    );
  }
}

class _IconSquare extends StatelessWidget {
  const _IconSquare(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EEF0),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: Colors.black),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 5, backgroundColor: color),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

const _tinyMuted = TextStyle(
  fontSize: 9,
  fontWeight: FontWeight.w700,
  color: Color(0xFF6B777D),
);

class _LegacyPage extends StatelessWidget {
  const _LegacyPage({
    required this.title,
    required this.leading,
    required this.trailing,
    required this.children,
    this.leadingColor = CleanColors.primary,
    this.onLeadingTap,
    this.onTrailingTap,
    this.onProfileTap,
  });

  final String title;
  final IconData leading;
  final IconData trailing;
  final List<Widget> children;
  final Color leadingColor;
  final VoidCallback? onLeadingTap;
  final VoidCallback? onTrailingTap;
  final VoidCallback? onProfileTap;

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFFF5FAFD);
    return Container(
      color: background,
      child: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 84, 16, 130),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
          _CleanAirTopBar(
            title: title,
            leading: leading,
            trailing: onTrailingTap == null ? Symbols.account_circle : trailing,
            background: background,
            leadingColor: leadingColor,
            titleColor: title == 'CleanAir'
                ? CleanColors.primary
                : CleanColors.onSurface,
            onLeadingTap: onLeadingTap,
            onTrailingTap: onTrailingTap ?? onProfileTap,
          ),
        ],
      ),
    );
  }
}

class _SoftCard extends StatelessWidget {
  const _SoftCard({
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(20),
    this.radius = 22,
  });

  final Widget child;
  final Color color;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0x12000000)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A171C1F),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SegmentTabs extends StatelessWidget {
  const _SegmentTabs({
    required this.labels,
    required this.active,
    this.onSelected,
  });

  final List<String> labels;
  final int active;
  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: CleanColors.surfaceLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onSelected == null ? null : () => onSelected!(i),
                child: Container(
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == active ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: i == active
                        ? const [
                            BoxShadow(
                              color: Color(0x10000000),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: i == active
                          ? CleanColors.primary
                          : CleanColors.secondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
    this.unit,
    this.color = CleanColors.onSurface,
  });

  final String label;
  final String value;
  final String? unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      padding: const EdgeInsets.all(14),
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: CleanColors.secondary,
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 22,
                height: 1,
                fontWeight: FontWeight.w900,
                color: color,
              ),
              children: [
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: CleanColors.outline,
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

class _HealthModeHeader extends StatelessWidget {
  const _HealthModeHeader({
    required this.active,
    required this.icon,
    this.onSelected,
  });

  final int active;
  final IconData icon;
  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      color: CleanColors.surfaceLow,
      padding: const EdgeInsets.all(14),
      radius: 18,
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Health Mode',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: CleanColors.onSurface,
                ),
              ),
              const Spacer(),
              Icon(icon, color: CleanColors.primaryContainer, size: 24),
            ],
          ),
          const SizedBox(height: 12),
          _SegmentTabs(
            labels: const ['어린이', '고령자', '정화지표'],
            active: active,
            onSelected: onSelected,
          ),
        ],
      ),
    );
  }
}

class _RiskStatusCard extends StatelessWidget {
  const _RiskStatusCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      padding: const EdgeInsets.all(14),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              height: 1,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 10,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: CleanColors.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusEnvironmentCard extends StatelessWidget {
  const _FocusEnvironmentCard({required this.data});

  final _HealthComputationData data;

  @override
  Widget build(BuildContext context) {
    final progress = ((data.co2 - 400) / 1100).clamp(0.0, 1.0).toDouble();
    final color = _healthColor(data.focusLevel);

    return _SoftCard(
      padding: EdgeInsets.zero,
      radius: 18,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [CleanColors.primary, CleanColors.primaryContainer],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: const Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '집중환경 판단',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'CO₂ 기반 학습 환경 데이터',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Symbols.psychology, size: 38, color: Colors.white),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('현재 CO₂ 농도', style: _tinyMuted),
                          const SizedBox(height: 4),
                          Text.rich(
                            TextSpan(
                              text: data.co2.round().toString(),
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: CleanColors.onSurface,
                              ),
                              children: const [
                                TextSpan(
                                  text: ' ppm',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: CleanColors.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StatusPill(text: data.focusLevel),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    color: color,
                    backgroundColor: CleanColors.surfaceHigh,
                  ),
                ),
                const SizedBox(height: 8),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('400', style: _tinyMuted),
                    Text('700 경계', style: _tinyMuted),
                    Text('1500', style: _tinyMuted),
                  ],
                ),
                const SizedBox(height: 14),
                _InfoListTile(
                  icon: Symbols.info,
                  title: data.focusAction,
                  subtitle: data.focusMessage,
                  color: color,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoListTile extends StatelessWidget {
  const _InfoListTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.color = CleanColors.primary,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconBubble(
          icon: icon,
          size: 42,
          iconSize: 21,
          color: color.withValues(alpha: 0.14),
          iconColor: color,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: CleanColors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: CleanColors.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlugInputBox extends StatelessWidget {
  const _PlugInputBox({
    required this.label,
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.onChanged,
    this.readOnly = false,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 5),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              letterSpacing: 0.9,
              fontWeight: FontWeight.w900,
              color: CleanColors.outline,
            ),
          ),
        ),
        Container(
          height: 44,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: CleanColors.surfaceHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            onChanged: onChanged,
            readOnly: readOnly,
            maxLines: 1,
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: hintText,
              hintStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: CleanColors.outline,
              ),
            ),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: CleanColors.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlugModeSelector extends StatelessWidget {
  const _PlugModeSelector({
    required this.auto,
    required this.subtitle,
    required this.busy,
    required this.onManualTap,
    required this.onAutoTap,
  });

  final bool auto;
  final String subtitle;
  final bool busy;
  final VoidCallback? onManualTap;
  final VoidCallback? onAutoTap;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      radius: 14,
      color: CleanColors.surfaceLow,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Symbols.auto_mode, color: CleanColors.primary, size: 19),
              SizedBox(width: 7),
              Text('제어 모드', style: _cardTitle),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _PlugModeButton(
                  label: '수동',
                  selected: !auto,
                  disabled: busy || onManualTap == null,
                  onTap: onManualTap,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PlugModeButton(
                  label: '자동',
                  selected: auto,
                  disabled: busy || onAutoTap == null,
                  onTap: onAutoTap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(subtitle, style: _tinyMuted),
        ],
      ),
    );
  }
}

class _PlugModeButton extends StatelessWidget {
  const _PlugModeButton({
    required this.label,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? CleanColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? CleanColors.primary
                : CleanColors.outline.withValues(alpha: 0.18),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: selected ? Colors.white : CleanColors.secondary,
          ),
        ),
      ),
    );
  }
}

class _FourSegmentIndicator extends StatelessWidget {
  const _FourSegmentIndicator({required this.active});

  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: i <= active
                    ? CleanColors.primary
                    : CleanColors.surfaceHighest,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          if (i != 3) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _DangerPill extends StatelessWidget {
  const _DangerPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: CleanColors.errorContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: CleanColors.error,
        ),
      ),
    );
  }
}

class _KeyValueLine extends StatelessWidget {
  const _KeyValueLine({
    required this.label,
    required this.value,
    this.valueColor = CleanColors.onSurface,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: CleanColors.onVariant,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _SleepGauge extends StatelessWidget {
  const _SleepGauge({required this.score, required this.level});

  final int? score;
  final String level;

  @override
  Widget build(BuildContext context) {
    final value = score;
    final progress = ((value ?? 0) / 100).clamp(0.0, 1.0).toDouble();

    return SizedBox(
      height: 62,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          CustomPaint(
            size: const Size(94, 54),
            painter: _SleepGaugePainter(progress: progress),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value == null ? '-' : '$value%',
                style: const TextStyle(
                  fontSize: 19,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: CleanColors.primary,
                ),
              ),
              Text(
                level,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: CleanColors.secondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SleepGaugePainter extends CustomPainter {
  const _SleepGaugePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(8, 8, size.width - 16, size.height * 1.55);
    final bg = Paint()
      ..color = CleanColors.surfaceHigh
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    final fg = Paint()
      ..color = CleanColors.primaryContainer
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, bg);
    canvas.drawArc(rect, math.pi, math.pi * progress, false, fg);
  }

  @override
  bool shouldRepaint(covariant _SleepGaugePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _LineChartPanel extends StatefulWidget {
  const _LineChartPanel({
    required this.values,
    this.height = 170,
    this.asBars = false,
    this.points = const <_ChartPoint>[],
    this.unit = '',
    this.rangeStart,
    this.rangeEnd,
    this.statusOf,
  });

  final List<double> values;
  final double height;
  final bool asBars;
  final List<_ChartPoint> points;
  final String unit;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final _ChartStatusResolver? statusOf;

  @override
  State<_LineChartPanel> createState() => _LineChartPanelState();
}

class _LineChartPanelState extends State<_LineChartPanel> {
  int? _selectedIndex;
  int? _selectionAnchorIndex;
  int? _selectionEndIndex;
  _ChartInteractionMode _mode = _ChartInteractionMode.point;

  @override
  void didUpdateWidget(covariant _LineChartPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = _selectedIndex;
    if (index != null && index >= widget.values.length) {
      _selectedIndex = null;
    }
    final anchor = _selectionAnchorIndex;
    final end = _selectionEndIndex;
    if (anchor != null && anchor >= widget.values.length) {
      _selectionAnchorIndex = null;
      _selectionEndIndex = null;
    } else if (end != null && end >= widget.values.length) {
      _selectionEndIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex;
    final selectedValue = selectedIndex == null ||
            selectedIndex < 0 ||
            selectedIndex >= widget.values.length
        ? null
        : widget.values[selectedIndex];
    final selectedPoint = selectedIndex == null ||
            selectedIndex < 0 ||
            selectedIndex >= widget.points.length
        ? null
        : widget.points[selectedIndex];
    final selectionSummary = _selectionSummary();
    return SizedBox(
      height: widget.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          if (_mode == _ChartInteractionMode.point) {
            _selectPoint(details.localPosition, clearRange: true);
          }
        },
        onPanStart: _mode == _ChartInteractionMode.range
            ? (details) => _beginRange(details.localPosition)
            : null,
        onPanUpdate: _mode == _ChartInteractionMode.range
            ? (details) => _extendRange(details.localPosition)
            : null,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tooltipLeft = selectedIndex == null
                ? 52.0
                : _tooltipLeft(constraints.maxWidth, selectedIndex);
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _LineChartPainter(
                      widget.values,
                      asBars: widget.asBars,
                      selectedIndex: selectedIndex,
                      selectionStart: _selectionStart,
                      selectionEnd: _selectionEnd,
                      points: widget.points,
                      unit: widget.unit,
                      rangeStart: widget.rangeStart,
                      rangeEnd: widget.rangeEnd,
                      statusOf: widget.statusOf,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                if (selectedValue != null)
                  Positioned(
                    left: tooltipLeft,
                    top: 6,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 178),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: CleanColors.primary,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x2200677D),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        selectedPoint == null
                            ? '선택 ${_formatMetric(selectedValue)} ${widget.unit}'
                            : '${_chartTimeLabel(selectedPoint.time)} · ${_formatMetric(selectedPoint.value)} ${widget.unit}'
                                '${_chartTooltipStatus(widget.statusOf, selectedPoint.value)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                if (selectionSummary != null)
                  Positioned(
                    left: 48,
                    right: 10,
                    bottom: 56,
                    child: _ChartSelectionSummaryPill(
                      summary: selectionSummary,
                      unit: widget.unit,
                    ),
                  ),
                Positioned(
                  right: 8,
                  bottom: 6,
                  child: _ChartInteractionModeToggle(
                    mode: _mode,
                    onChanged: (mode) {
                      setState(() {
                        _mode = mode;
                        _selectionAnchorIndex = null;
                        _selectionEndIndex = null;
                      });
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  double _tooltipLeft(double width, int index) {
    const leftAxisWidth = 42.0;
    const rightPadding = 10.0;
    const tooltipWidth = 178.0;
    final x = _xForIndex(
      width,
      index,
      leftAxisWidth: leftAxisWidth,
      rightPadding: rightPadding,
    );
    return (x - tooltipWidth / 2)
        .clamp(0.0, math.max(0.0, width - tooltipWidth));
  }

  int? get _selectionStart {
    final anchor = _selectionAnchorIndex;
    final end = _selectionEndIndex;
    if (anchor == null || end == null) return null;
    return math.min(anchor, end);
  }

  int? get _selectionEnd {
    final anchor = _selectionAnchorIndex;
    final end = _selectionEndIndex;
    if (anchor == null || end == null) return null;
    return math.max(anchor, end);
  }

  void _selectPoint(Offset localPosition, {bool clearRange = false}) {
    if (widget.values.isEmpty) return;
    final index = _indexFor(localPosition);
    setState(() {
      _selectedIndex = index;
      if (clearRange) {
        _selectionAnchorIndex = null;
        _selectionEndIndex = null;
      }
    });
  }

  void _beginRange(Offset localPosition) {
    if (widget.values.isEmpty) return;
    final index = _indexFor(localPosition);
    setState(() {
      _selectedIndex = index;
      _selectionAnchorIndex = index;
      _selectionEndIndex = index;
    });
  }

  void _extendRange(Offset localPosition) {
    if (widget.values.isEmpty || _selectionAnchorIndex == null) return;
    final index = _indexFor(localPosition);
    setState(() {
      _selectedIndex = index;
      _selectionEndIndex = index;
    });
  }

  int _indexFor(Offset localPosition) {
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 1;
    const leftAxisWidth = 42.0;
    const rightPadding = 10.0;
    final plotWidth = math.max(1.0, width - leftAxisWidth - rightPadding);
    final fraction =
        ((localPosition.dx - leftAxisWidth) / plotWidth).clamp(0.0, 1.0);
    final start = widget.rangeStart;
    final end = widget.rangeEnd;
    if (start != null &&
        end != null &&
        end.isAfter(start) &&
        widget.points.isNotEmpty) {
      final targetMs = start.millisecondsSinceEpoch +
          ((end.millisecondsSinceEpoch - start.millisecondsSinceEpoch) *
                  fraction)
              .round();
      var nearest = 0;
      var nearestDiff = double.infinity;
      for (var i = 0; i < widget.points.length; i++) {
        final diff =
            (widget.points[i].time.millisecondsSinceEpoch - targetMs).abs();
        if (diff < nearestDiff) {
          nearest = i;
          nearestDiff = diff.toDouble();
        }
      }
      return nearest.clamp(0, widget.values.length - 1);
    }
    return (fraction * (widget.values.length - 1)).round();
  }

  double _xForIndex(
    double width,
    int index, {
    required double leftAxisWidth,
    required double rightPadding,
  }) {
    final plotWidth = math.max(1.0, width - leftAxisWidth - rightPadding);
    final start = widget.rangeStart;
    final end = widget.rangeEnd;
    if (start != null &&
        end != null &&
        end.isAfter(start) &&
        index >= 0 &&
        index < widget.points.length) {
      final totalMs = end.millisecondsSinceEpoch - start.millisecondsSinceEpoch;
      final elapsedMs = widget.points[index].time.millisecondsSinceEpoch -
          start.millisecondsSinceEpoch;
      final fraction = (elapsedMs / totalMs).clamp(0.0, 1.0);
      return leftAxisWidth + plotWidth * fraction;
    }
    return leftAxisWidth +
        plotWidth * index / math.max(1, widget.values.length - 1);
  }

  _ChartSelectionSummary? _selectionSummary() {
    final start = _selectionStart;
    final end = _selectionEnd;
    if (start == null ||
        end == null ||
        widget.values.isEmpty ||
        start < 0 ||
        end >= widget.values.length) {
      return null;
    }
    final values = widget.values.sublist(start, end + 1);
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final avg = values.reduce((a, b) => a + b) / values.length;
    final median = sorted.length.isOdd
        ? sorted[sorted.length ~/ 2]
        : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2;
    return (
      startIndex: start,
      endIndex: end,
      startTime:
          start < widget.points.length ? widget.points[start].time : null,
      endTime: end < widget.points.length ? widget.points[end].time : null,
      max: values.reduce(math.max),
      min: values.reduce(math.min),
      avg: avg,
      median: median,
      count: values.length,
    );
  }
}

enum _ChartInteractionMode { point, range }

class _ChartInteractionModeToggle extends StatelessWidget {
  const _ChartInteractionModeToggle({
    required this.mode,
    required this.onChanged,
  });

  final _ChartInteractionMode mode;
  final ValueChanged<_ChartInteractionMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1600677D),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ChartModeButton(
            label: '점',
            selected: mode == _ChartInteractionMode.point,
            onTap: () => onChanged(_ChartInteractionMode.point),
          ),
          _ChartModeButton(
            label: '구간',
            selected: mode == _ChartInteractionMode.range,
            onTap: () => onChanged(_ChartInteractionMode.range),
          ),
        ],
      ),
    );
  }
}

class _ChartModeButton extends StatelessWidget {
  const _ChartModeButton({
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
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? CleanColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: selected ? Colors.white : CleanColors.secondary,
          ),
        ),
      ),
    );
  }
}

typedef _ChartSelectionSummary = ({
  int startIndex,
  int endIndex,
  DateTime? startTime,
  DateTime? endTime,
  double max,
  double min,
  double avg,
  double median,
  int count,
});

class _ChartSelectionSummaryPill extends StatelessWidget {
  const _ChartSelectionSummaryPill({
    required this.summary,
    required this.unit,
  });

  final _ChartSelectionSummary summary;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final period = _selectionPeriodLabel(summary);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2200677D),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$period · ${summary.count}개',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: CleanColors.primary,
              ),
            ),
            const SizedBox(height: 5),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _SelectionStatText('MAX', summary.max, unit),
                _SelectionStatText('MIN', summary.min, unit),
                _SelectionStatText('AVG', summary.avg, unit),
                _SelectionStatText('MEDIAN(중앙값)', summary.median, unit),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _selectionPeriodLabel(_ChartSelectionSummary summary) {
    final start = summary.startTime;
    final end = summary.endTime;
    if (start == null || end == null) {
      return '구간 ${summary.startIndex + 1}-${summary.endIndex + 1}';
    }
    if (summary.startIndex == summary.endIndex) {
      return _chartTimeLabel(start);
    }
    return '${_chartTimeLabel(start)}-${_chartTimeLabel(end)}';
  }
}

class _SelectionStatText extends StatelessWidget {
  const _SelectionStatText(this.label, this.value, this.unit);

  final String label;
  final double value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label ${_formatMetric(value)}${unit.trim().isEmpty ? '' : ' $unit'}',
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w900,
        color: CleanColors.onSurface,
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter(
    this.values, {
    this.asBars = false,
    this.selectedIndex,
    this.selectionStart,
    this.selectionEnd,
    this.points = const <_ChartPoint>[],
    this.unit = '',
    this.rangeStart,
    this.rangeEnd,
    this.statusOf,
  });

  final List<double> values;
  final bool asBars;
  final int? selectedIndex;
  final int? selectionStart;
  final int? selectionEnd;
  final List<_ChartPoint> points;
  final String unit;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final _ChartStatusResolver? statusOf;

  @override
  void paint(Canvas canvas, Size size) {
    const leftAxisWidth = 42.0;
    const bottomAxisHeight = 28.0;
    const topPadding = 14.0;
    const rightPadding = 10.0;
    final plotRect = Rect.fromLTWH(
      leftAxisWidth,
      topPadding,
      math.max(1.0, size.width - leftAxisWidth - rightPadding),
      math.max(1.0, size.height - topPadding - bottomAxisHeight),
    );
    final grid = Paint()
      ..color = CleanColors.surfaceHigh
      ..strokeWidth = 1;
    final axis = Paint()
      ..color = CleanColors.outlineVariant
      ..strokeWidth = 1.2;
    if (values.isNotEmpty) {
      _paintStatusBackground(canvas, plotRect);
    }
    for (var i = 0; i <= 4; i++) {
      final y = plotRect.top + plotRect.height * i / 4;
      canvas.drawLine(
        Offset(plotRect.left, y),
        Offset(plotRect.right, y),
        grid,
      );
    }
    canvas.drawLine(plotRect.bottomLeft, plotRect.bottomRight, axis);
    canvas.drawLine(plotRect.bottomLeft, plotRect.topLeft, axis);
    if (values.isEmpty) {
      _paintChartLabel(canvas, '값', Offset(7, plotRect.center.dy - 7));
      _paintChartLabel(
        canvas,
        '시간',
        Offset(plotRect.center.dx - 10, plotRect.bottom + 10),
      );
      return;
    }
    final maxValue = values.reduce(math.max);
    final minValue = values.reduce(math.min);
    final range = math.max(1, maxValue - minValue);
    for (var i = 0; i <= 4; i++) {
      final value = maxValue - range * i / 4;
      final y = plotRect.top + plotRect.height * i / 4;
      _paintChartLabel(
        canvas,
        _axisNumber(value),
        Offset(4, (y - 7).clamp(plotRect.top - 2, plotRect.bottom - 12)),
      );
    }
    final ticks = _timeTicks();
    for (final tick in ticks) {
      final x = plotRect.left + plotRect.width * tick.fraction;
      _paintChartLabel(
        canvas,
        tick.label,
        Offset((x - 22).clamp(plotRect.left - 6, plotRect.right - 38),
            plotRect.bottom + 10),
      );
    }
    if (unit.trim().isNotEmpty) {
      _paintChartLabel(canvas, unit, Offset(plotRect.right - 32, 0));
    }
    _paintSelectionBand(canvas, plotRect);
    if (asBars) {
      final barWidth = math.min(22.0,
          math.max(4.0, plotRect.width / math.max(12, values.length) * 0.72));
      canvas.save();
      canvas.clipRect(plotRect);
      for (var i = 0; i < values.length; i++) {
        final factor = ((values[i] - minValue) / range).clamp(0.0, 1.0);
        final barHeight = math.max(3.0, factor * plotRect.height);
        final centerX = _xForIndex(plotRect, i, asBarCenter: true);
        final x = (centerX - barWidth / 2)
            .clamp(plotRect.left, plotRect.right - barWidth)
            .toDouble();
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x,
            plotRect.bottom - barHeight,
            barWidth,
            barHeight,
          ),
          const Radius.circular(999),
        );
        canvas.drawRRect(
          rect,
          Paint()
            ..color = i == selectedIndex
                ? CleanColors.primary
                : _chartStatusColor(
                    statusOf?.call(values[i]),
                    fallbackValue: values[i],
                  ).withValues(alpha: 0.72),
        );
      }
      canvas.restore();
      _paintSelectedGuide(canvas, plotRect);
      return;
    }
    final offsets = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = _xForIndex(plotRect, i);
      final y =
          plotRect.bottom - ((values[i] - minValue) / range) * plotRect.height;
      offsets.add(Offset(x, y));
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = Colors.white);
      canvas.drawCircle(
        Offset(x, y),
        i == selectedIndex ? 5 : 3,
        Paint()
          ..color = i == selectedIndex
              ? CleanColors.primary
              : _chartStatusColor(
                  statusOf?.call(values[i]),
                  fallbackValue: values[i],
                ),
      );
    }
    _paintSegmentedLine(canvas, offsets);
    _paintSelectedGuide(canvas, plotRect);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return values != oldDelegate.values ||
        asBars != oldDelegate.asBars ||
        selectedIndex != oldDelegate.selectedIndex ||
        selectionStart != oldDelegate.selectionStart ||
        selectionEnd != oldDelegate.selectionEnd ||
        points != oldDelegate.points ||
        unit != oldDelegate.unit ||
        rangeStart != oldDelegate.rangeStart ||
        rangeEnd != oldDelegate.rangeEnd ||
        statusOf != oldDelegate.statusOf;
  }

  void _paintStatusBackground(Canvas canvas, Rect plotRect) {
    final maxValue = values.reduce(math.max);
    final minValue = values.reduce(math.min);
    final range = math.max(1.0, maxValue - minValue);
    const samples = 160;
    var bandStart = 0;
    var bandColor = _chartStatusColor(
      statusOf?.call(maxValue),
      fallbackValue: maxValue,
    );

    for (var i = 1; i <= samples; i++) {
      final value = maxValue - range * i / samples;
      final color = _chartStatusColor(
        statusOf?.call(value),
        fallbackValue: value,
      );
      final colorChanged = color != bandColor;
      final reachedEnd = i == samples;
      if (!colorChanged && !reachedEnd) continue;

      final top = plotRect.top + plotRect.height * bandStart / samples;
      final bottom = plotRect.top + plotRect.height * i / samples;
      if (bottom > top) {
        canvas.drawRect(
          Rect.fromLTRB(plotRect.left, top, plotRect.right, bottom),
          Paint()..color = bandColor.withValues(alpha: 0.11),
        );
      }

      bandStart = i;
      bandColor = color;
    }
  }

  void _paintSegmentedLine(Canvas canvas, List<Offset> offsets) {
    if (offsets.length < 2) return;
    for (var i = 0; i < offsets.length - 1; i++) {
      final status = statusOf?.call(values[i + 1]);
      final paint = Paint()
        ..color = _chartStatusColor(status, fallbackValue: values[i + 1])
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawLine(offsets[i], offsets[i + 1], paint);
    }
  }

  String _axisNumber(double value) {
    final rounded =
        value.abs() >= 100 ? value.round().toString() : _formatMetric(value);
    return rounded;
  }

  List<({double fraction, String label})> _timeTicks() {
    final start = rangeStart;
    final end = rangeEnd;
    if (start != null && end != null && end.isAfter(start)) {
      final totalMs = end.millisecondsSinceEpoch - start.millisecondsSinceEpoch;
      return [0.0, 0.25, 0.5, 0.75, 1.0].map((fraction) {
        final time = DateTime.fromMillisecondsSinceEpoch(
          start.millisecondsSinceEpoch + (totalMs * fraction).round(),
        );
        return (
          fraction: fraction,
          label: _chartAxisTimeLabel(time, start, end),
        );
      }).toList(growable: false);
    }
    if (points.isEmpty) {
      final now = DateTime.now();
      return [
        (
          fraction: 0.0,
          label: _clockMinuteLabel(now.subtract(const Duration(minutes: 5))),
        ),
        (
          fraction: 0.5,
          label: _clockMinuteLabel(
            now.subtract(const Duration(minutes: 2, seconds: 30)),
          ),
        ),
        (fraction: 1.0, label: _clockMinuteLabel(now)),
      ];
    }
    final last = points.length - 1;
    final indexes = <int>{
      0,
      (last * 0.25).round(),
      (last * 0.5).round(),
      (last * 0.75).round(),
      last,
    }.toList()
      ..sort();
    return indexes.map((index) {
      return (
        fraction: last == 0 ? 0.0 : index / last,
        label: _chartAxisTimeLabel(
          points[index].time,
          points.first.time,
          points.last.time,
        ),
      );
    }).toList(growable: false);
  }

  void _paintSelectedGuide(Canvas canvas, Rect plotRect) {
    final index = selectedIndex;
    if (index == null ||
        values.isEmpty ||
        index < 0 ||
        index >= values.length) {
      return;
    }
    final x = _xForIndex(plotRect, index, asBarCenter: asBars);
    final maxValue = values.reduce(math.max);
    final minValue = values.reduce(math.min);
    final range = math.max(1, maxValue - minValue);
    final y = plotRect.bottom -
        ((values[index] - minValue) / range) * plotRect.height;
    final guidePaint = Paint()
      ..color = CleanColors.primary.withValues(alpha: 0.42)
      ..strokeWidth = 1.4;
    canvas.drawLine(
      Offset(x, plotRect.top),
      Offset(x, plotRect.bottom),
      guidePaint,
    );
    canvas.drawLine(
      Offset(plotRect.left, y),
      Offset(plotRect.right, y),
      guidePaint..strokeWidth = 1.0,
    );
  }

  void _paintSelectionBand(Canvas canvas, Rect plotRect) {
    final start = selectionStart;
    final end = selectionEnd;
    if (start == null ||
        end == null ||
        values.isEmpty ||
        start < 0 ||
        end >= values.length) {
      return;
    }
    final left = _xForIndex(plotRect, start, asBarCenter: false);
    final right = asBars
        ? _xForIndex(plotRect, end, asBarCenter: true) +
            plotRect.width / math.max(1, values.length) / 2
        : _xForIndex(plotRect, end, asBarCenter: false);
    final rect = Rect.fromLTRB(
      math.min(left, right).clamp(plotRect.left, plotRect.right),
      plotRect.top,
      math.max(left, right).clamp(plotRect.left, plotRect.right),
      plotRect.bottom,
    );
    final band = rect.width < 2
        ? Rect.fromCenter(
            center: Offset(rect.center.dx, rect.center.dy),
            width: 8,
            height: rect.height,
          ).intersect(plotRect)
        : rect;
    canvas.drawRRect(
      RRect.fromRectAndRadius(band, const Radius.circular(10)),
      Paint()..color = CleanColors.primary.withValues(alpha: 0.10),
    );
  }

  void _paintChartLabel(Canvas canvas, String text, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: CleanColors.onVariant,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 64);
    painter.paint(canvas, offset);
  }

  double _xForIndex(
    Rect plotRect,
    int index, {
    bool asBarCenter = false,
  }) {
    final start = rangeStart;
    final end = rangeEnd;
    if (start != null &&
        end != null &&
        end.isAfter(start) &&
        index >= 0 &&
        index < points.length) {
      final totalMs = end.millisecondsSinceEpoch - start.millisecondsSinceEpoch;
      final elapsedMs = points[index].time.millisecondsSinceEpoch -
          start.millisecondsSinceEpoch;
      final fraction = (elapsedMs / totalMs).clamp(0.0, 1.0);
      return plotRect.left + plotRect.width * fraction;
    }
    if (asBarCenter) {
      return plotRect.left + plotRect.width * (index + 0.5) / values.length;
    }
    return plotRect.left +
        plotRect.width * index / math.max(1, values.length - 1);
  }
}

String _chartTooltipStatus(_ChartStatusResolver? statusOf, double value) {
  final status = statusOf?.call(value).trim();
  return status == null || status.isEmpty ? '' : ' · $status';
}

String _iaqiChartStatus(double value) {
  if (value < 0.5) return '좋음';
  if (value < 1) return '보통';
  if (value < 2) return '조금 나쁨';
  if (value < 3) return '나쁨';
  if (value < 4) return '상당히 나쁨';
  return '매우 나쁨';
}

Color _chartStatusColor(String? status, {double? fallbackValue}) {
  final normalized = status?.trim();
  if (normalized == null || normalized.isEmpty) {
    if (fallbackValue != null) return _iaqiStatusColorByValue(fallbackValue);
    return CleanColors.primaryContainer;
  }
  if (normalized.contains('매우') ||
      normalized.contains('위험') ||
      normalized.contains('높음') && normalized.contains('매우')) {
    return const Color(0xFFDC2626);
  }
  if (normalized.contains('상당') ||
      normalized == '나쁨' ||
      normalized == '더움' ||
      normalized == '높음') {
    return const Color(0xFFF97316);
  }
  if (normalized.contains('조금') ||
      normalized.contains('주의') ||
      normalized.contains('보통') ||
      normalized.contains('따뜻') ||
      normalized.contains('약간') ||
      normalized.contains('서늘') ||
      normalized.contains('건조')) {
    return const Color(0xFFFACC15);
  }
  if (normalized.contains('좋음') ||
      normalized.contains('쾌적') ||
      normalized.contains('적정') ||
      normalized.contains('최적')) {
    return const Color(0xFF22C55E);
  }
  if (fallbackValue != null) return _iaqiStatusColorByValue(fallbackValue);
  return CleanColors.primaryContainer;
}

Color _iaqiStatusColorByValue(double value) {
  if (value < 0.5) return const Color(0xFF22C55E);
  if (value < 1) return const Color(0xFFFACC15);
  if (value < 2) return const Color(0xFFFFA726);
  if (value < 3) return const Color(0xFFFF4056);
  if (value < 4) return const Color(0xFFB91C1C);
  return const Color(0xFF9333EA);
}

class _DataTableCard extends StatelessWidget {
  const _DataTableCard({required this.rows});

  final List<_DataLogRow> rows;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      padding: EdgeInsets.zero,
      radius: 18,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Row(
              children: [
                Expanded(child: Text('시간', style: _tableHead)),
                Expanded(
                  child: Text(
                    '수치',
                    textAlign: TextAlign.center,
                    style: _tableHead,
                  ),
                ),
                Expanded(
                  child: Text(
                    '상태',
                    textAlign: TextAlign.center,
                    style: _tableHead,
                  ),
                ),
                Icon(
                  Symbols.chevron_right,
                  size: 16,
                  color: Colors.transparent,
                ),
              ],
            ),
          ),
          for (final row in rows)
            InkWell(
              onTap: () => _showDataRowDetail(context, row),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: [
                    Expanded(child: Text(row.a, style: _tableCellMuted)),
                    Expanded(
                      child: Text(
                        row.b,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row.c,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: row.color,
                        ),
                      ),
                    ),
                    const Icon(
                      Symbols.chevron_right,
                      size: 16,
                      color: CleanColors.outlineVariant,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showDataRowDetail(
    BuildContext context,
    _DataLogRow row,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('측정 로그 상세', style: _cardTitle),
                const SizedBox(height: 14),
                _InfoLine(label: '측정 시각', value: row.a),
                _InfoLine(label: '측정값', value: row.b),
                _InfoLine(label: '판정', value: row.c, color: row.color),
                const SizedBox(height: 12),
                const Text(
                  '판정 기준은 기존 Cleanair 지표 상태 함수와 건강 산출 로직을 그대로 사용합니다.',
                  style: _caption,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.label,
    required this.value,
    this.color = CleanColors.onSurface,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(width: 82, child: Text(label, style: _tinyMuted)),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _tableHead = TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w900,
  letterSpacing: 1.1,
  color: CleanColors.secondary,
);

const _tableCellMuted = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w700,
  color: CleanColors.secondary,
);

class _PollutantMetricData {
  const _PollutantMetricData({
    required this.label,
    required this.title,
    required this.value,
    required this.unit,
    required this.status,
    required this.summary,
    required this.max,
    required this.min,
    required this.avg,
    required this.median,
    required this.values,
    required this.points,
    required this.statusOf,
    required this.rows,
    required this.icon,
    required this.sampleCount,
    required this.startLabel,
    required this.midLabel,
    required this.endLabel,
  });

  final String label;
  final String title;
  final String value;
  final String unit;
  final String status;
  final String summary;
  final String max;
  final String min;
  final String avg;
  final String median;
  final List<double> values;
  final List<_ChartPoint> points;
  final _ChartStatusResolver statusOf;
  final List<_DataLogRow> rows;
  final IconData icon;
  final int sampleCount;
  final String startLabel;
  final String midLabel;
  final String endLabel;
}

class DataLoggingScreen extends StatefulWidget {
  const DataLoggingScreen({
    super.key,
    this.initialMetricIndex = 0,
    this.onConnectSensor,
    this.onProfile,
  });

  final int initialMetricIndex;
  final VoidCallback? onConnectSensor;
  final VoidCallback? onProfile;

  @override
  State<DataLoggingScreen> createState() => _DataLoggingScreenState();
}

class _DataLoggingScreenState extends State<DataLoggingScreen> {
  final _csvExportService = AirQualityCsvExportService();
  int _selected = 0;
  _LogRange _range = _LogRange.day;
  bool _chartAsBars = false;
  bool _exporting = false;
  bool _serverExporting = false;
  String? _csvMessage;
  bool _csvSuccess = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialMetricIndex;
  }

  @override
  void didUpdateWidget(covariant DataLoggingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialMetricIndex != widget.initialMetricIndex) {
      _selected = widget.initialMetricIndex;
    }
  }

  Future<void> _exportSelectedCsv(
    AirQualityController controller,
    _PollutantMetricData data,
    List<AirQualitySnapshot> rangedHistory,
  ) async {
    if (_exporting) return;
    final metricId = _exportMetricId(data);
    final snapshots = _snapshotsForCsvExport(
      controller: controller,
      rangedHistory: rangedHistory,
      metricId: metricId,
    );
    if (snapshots.isEmpty) {
      setState(() {
        _csvSuccess = false;
        _csvMessage = '선택한 기간에 ${data.label} 저장 가능한 센서 데이터가 없습니다.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_csvMessage!)),
      );
      return;
    }

    setState(() {
      _exporting = true;
      _csvMessage = '${data.label} · ${_rangeLabel(_range)} CSV 저장 중';
      _csvSuccess = false;
    });
    try {
      final result = await _csvExportService.exportSnapshots(
        snapshots: snapshots,
        selectedMetric: metricId,
      );
      if (!mounted) return;
      setState(() {
        _csvSuccess = true;
        _csvMessage =
            'CSV 저장 완료 · ${result.rowCount}개 행 · 휴대폰 Download/AirGradient 폴더 · ${result.fileName}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_csvMessage!),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _csvSuccess = false;
        _csvMessage = 'CSV 저장 실패: $error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_csvMessage!)),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportServerCsv(
    AirQualityController controller,
    _PollutantMetricData data,
  ) async {
    if (_serverExporting) return;
    final metricId = _exportMetricId(data);
    setState(() {
      _serverExporting = true;
      _csvSuccess = false;
      _csvMessage = '${data.label} · 서버 최근 30일 CSV 저장 중';
    });
    try {
      final service = context.read<FirestoreSnapshotService>();
      final history = await service.loadHistory(
        since: DateTime.now().subtract(const Duration(days: 30)),
        limit: 120960,
      );
      var snapshots =
          history.where(_hasAnyCsvExportValue).toList(growable: false);
      if (snapshots.isEmpty) {
        await controller.refreshHistoryFromFirestore();
        snapshots = _recentCsvFallbackSnapshots(controller.rawHistory);
      }
      if (snapshots.isEmpty) {
        final latest = controller.latestSnapshot;
        final cutoff = DateTime.now().subtract(const Duration(days: 30));
        snapshots = [
          if (latest != null &&
              !latest.timestamp.isBefore(cutoff) &&
              _hasAnyCsvExportValue(latest))
            latest,
        ];
      }
      if (snapshots.isEmpty) {
        throw StateError('저장할 센서 기록이 없습니다. 센서 연결과 Firestore 히스토리를 확인해 주세요.');
      }
      final result = await _csvExportService.exportSnapshots(
        snapshots: snapshots,
        selectedMetric: metricId,
      );
      if (!mounted) return;
      setState(() {
        _csvSuccess = true;
        _csvMessage =
            '서버 CSV 저장 완료 · ${result.rowCount}개 행 · 휴대폰 Download/AirGradient 폴더 · ${result.fileName}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_csvMessage!),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _csvSuccess = false;
        _csvMessage = '서버 CSV 저장 실패: $error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_csvMessage!)),
      );
    } finally {
      if (mounted) setState(() => _serverExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AirQualityController>();
    final rangedHistory = _historyForRange(controller, _range);
    final metrics = _livePollutantMetrics(
      controller,
      historyOverride: rangedHistory,
    );
    if (metrics.isEmpty) {
      return _LegacyPage(
        title: 'CleanAir',
        leading: Symbols.waves,
        trailing: Symbols.sensors,
        onTrailingTap: widget.onConnectSensor,
        children: [
          const _SegmentTabs(
            labels: ['개요', '모니터링', '건강', '비교'],
            active: 1,
          ),
          const SizedBox(height: 18),
          _SoftCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Symbols.sensors,
                  size: 40,
                  color: CleanColors.primary,
                  fill: 1,
                ),
                const SizedBox(height: 16),
                const Text('센서 데이터 연결 필요', style: _cardTitle),
                const SizedBox(height: 8),
                const Text(
                  '상세 차트와 CSV 저장은 Firestore 히스토리 또는 현재 센서 스냅샷이 연결된 뒤 표시됩니다.',
                  style: _caption,
                ),
                const SizedBox(height: 18),
                GradientButton(
                  label: '센서 연결하기',
                  icon: Symbols.add_link,
                  onTap: widget.onConnectSensor,
                ),
              ],
            ),
          ),
        ],
      );
    }
    final safeSelected = _selected.clamp(0, metrics.length - 1).toInt();
    final data = metrics[safeSelected];
    final chartWindow = _chartWindowForRange(_range, data.points);
    return _LegacyPage(
      title: 'CleanAir',
      leading: Symbols.waves,
      trailing: Symbols.account_circle,
      onProfileTap: widget.onProfile,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < metrics.length; i++) ...[
                _LightChip(
                  metrics[i].label,
                  selected: i == safeSelected,
                  onTap: () => setState(() => _selected = i),
                ),
                if (i != metrics.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _MiniMetric(
                label: 'MAX (최대)',
                value: data.max,
                unit: data.unit,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MiniMetric(
                label: 'MIN (최소)',
                value: data.min,
                unit: data.unit,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MiniMetric(
                label: 'AVG (평균)',
                value: data.avg,
                unit: data.unit,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MiniMetric(
                label: 'MEDIAN (중앙값)',
                value: data.median,
                unit: data.unit,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showMetricCriteriaSheet(context, data),
          child: _SoftCard(
            padding: const EdgeInsets.all(22),
            child: Stack(
              children: [
                Positioned(
                  right: -20,
                  bottom: -22,
                  child: Icon(
                    data.icon,
                    size: 112,
                    color: CleanColors.primary.withValues(alpha: 0.08),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: CleanColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text.rich(
                      TextSpan(
                        text: data.value,
                        style: const TextStyle(
                          fontSize: 42,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          color: CleanColors.onSurface,
                        ),
                        children: [
                          if (data.unit.trim().isNotEmpty &&
                              data.value != 'N/A')
                            TextSpan(
                              text: ' ${data.unit}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: CleanColors.secondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _StatusPill(text: data.status),
                    const SizedBox(height: 18),
                    Text(
                      data.summary,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        color: CleanColors.secondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _SoftCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              const Row(
                children: [
                  Text('히스토리 범위', style: _cardTitle),
                  Spacer(),
                  Icon(Symbols.query_stats,
                      size: 18, color: CleanColors.primary),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _LightChip(
                    '선형',
                    selected: !_chartAsBars,
                    onTap: () => setState(() => _chartAsBars = false),
                  ),
                  const SizedBox(width: 8),
                  _LightChip(
                    '막대',
                    selected: _chartAsBars,
                    onTap: () => setState(() => _chartAsBars = true),
                  ),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _showDashboardChartSheet(
                      context,
                      title: '${data.title} · ${_rangeLabel(_range)}',
                      values: data.values,
                      points: data.points,
                      unit: data.unit,
                      asBars: _chartAsBars,
                      range: _range,
                      statusOf: data.statusOf,
                    ),
                    child: const _IconSquare(Symbols.open_in_full),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _showDashboardChartSheet(
                      context,
                      title: '${data.title} 구간 확인',
                      values: data.values,
                      points: data.points,
                      unit: data.unit,
                      asBars: _chartAsBars,
                      range: _range,
                      statusOf: data.statusOf,
                    ),
                    child: const _IconSquare(Symbols.search),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _RangeChipRow(
                        range: _range,
                        onChanged: (range) => setState(() => _range = range),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_rangeLabel(_range)} · ${data.sampleCount}개',
                    style: _tinyMuted,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _LineChartPanel(
                values: data.values,
                points: data.points,
                unit: data.unit,
                asBars: _chartAsBars,
                rangeStart: chartWindow.start,
                rangeEnd: chartWindow.end,
                statusOf: data.statusOf,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(data.startLabel, style: _tinyMuted),
                  Text(data.midLabel, style: _tinyMuted),
                  Text(data.endLabel, style: _tinyMuted),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _CsvExportCard(
          metricLabel: data.label,
          rangeLabel: _rangeLabel(_range),
          sampleCount: data.sampleCount,
          exporting: _exporting,
          serverExporting: _serverExporting,
          message: _csvMessage,
          success: _csvSuccess,
          onExport: () => _exportSelectedCsv(controller, data, rangedHistory),
          onServerExport: () => _exportServerCsv(controller, data),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Text(
              '상세 데이터 로그',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: CleanColors.onSurface,
              ),
            ),
            const Spacer(),
            Text('${data.label} · ${_rangeLabel(_range)}', style: _tinyMuted),
          ],
        ),
        const SizedBox(height: 10),
        _DataTableCard(rows: data.rows),
      ],
    );
  }
}

void _showMetricCriteriaSheet(
  BuildContext context,
  _PollutantMetricData data,
) {
  final info = _metricCriteriaInfo(data);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(data.icon, color: CleanColors.primary, fill: 1),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${data.title} 기준',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: CleanColors.onSurface,
                      ),
                    ),
                  ),
                  _StatusPill(text: data.status),
                ],
              ),
              const SizedBox(height: 16),
              _MetricCriteriaBar(
                value: double.tryParse(data.value),
                max: info.max,
                unit: data.unit,
                segments: info.segments,
              ),
              const SizedBox(height: 16),
              Text(
                info.description,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                  color: CleanColors.onVariant,
                ),
              ),
              const SizedBox(height: 14),
              for (final line in info.lines) ...[
                _InfoListTile(
                  icon: Symbols.check_circle,
                  title: line.$1,
                  subtitle: line.$2,
                ),
                if (line != info.lines.last) const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      );
    },
  );
}

({
  double max,
  String description,
  List<({String label, Color color, double end})> segments,
  List<(String, String)> lines,
}) _metricCriteriaInfo(_PollutantMetricData data) {
  switch (data.label) {
    case 'PM2.5':
      return (
        max: 100,
        description:
            '초미세먼지는 지름이 매우 작은 먼지입니다. 실내에서 농도가 높아지면 목이 답답하거나 눈이 따가울 수 있어요.',
        segments: const [
          (label: '좋음', color: Color(0xFF16A34A), end: 15),
          (label: '보통', color: Color(0xFFEAB308), end: 35),
          (label: '나쁨', color: Color(0xFFF97316), end: 75),
          (label: '매우 나쁨', color: Color(0xFFDC2626), end: 100),
        ],
        lines: const [
          ('낮음', '15 µg/m³ 이하'),
          ('보통', '15-35 µg/m³'),
          ('높음', '35-75 µg/m³'),
          ('매우 높음', '75 µg/m³ 초과'),
        ],
      );
    case 'CO2':
      return (
        max: 2500,
        description:
            'CO₂는 사람이 숨을 쉬면서 늘어나는 이산화탄소입니다. 값이 높으면 공기가 답답하게 느껴지고 환기가 필요할 수 있어요.',
        segments: const [
          (label: '좋음', color: Color(0xFF16A34A), end: 600),
          (label: '보통', color: Color(0xFFEAB308), end: 1000),
          (label: '높음', color: Color(0xFFF97316), end: 2000),
          (label: '매우 높음', color: Color(0xFFDC2626), end: 2500),
        ],
        lines: const [
          ('좋음', '600 ppm 이하'),
          ('보통', '600-1000 ppm'),
          ('높음', '1000-2000 ppm'),
          ('매우 높음', '2000 ppm 초과'),
        ],
      );
    case 'TVOC':
      return (
        max: 500,
        description:
            'TVOC는 냄새나 화학물질에서 나오는 여러 휘발성 물질을 한 번에 보는 값입니다. 청소, 조리, 새 가구, 접착제 냄새가 영향을 줄 수 있어요.',
        segments: const [
          (label: '좋음', color: Color(0xFF16A34A), end: 100),
          (label: '보통', color: Color(0xFFEAB308), end: 200),
          (label: '주의', color: Color(0xFFF97316), end: 300),
          (label: '나쁨', color: Color(0xFFEF4444), end: 400),
          (label: '매우 나쁨', color: Color(0xFF991B1B), end: 500),
        ],
        lines: const [
          ('낮음', '100 이하'),
          ('보통', '100-200'),
          ('조금 높음', '200-300'),
          ('높음', '300 초과'),
        ],
      );
    case 'NOx':
      return (
        max: 4,
        description:
            'NOx는 질소산화물 계열의 오염 신호입니다. 가스레인지, 난방기, 차량 배기가스 같은 연소 과정에서 높아질 수 있어요.',
        segments: const [
          (label: '좋음', color: Color(0xFF16A34A), end: 1),
          (label: '보통', color: Color(0xFFEAB308), end: 2),
          (label: '주의', color: Color(0xFFF97316), end: 4),
        ],
        lines: const [
          ('좋음', '1 이하'),
          ('보통', '1-2'),
          ('주의', '2 초과'),
        ],
      );
    case 'IAQI':
      return (
        max: 5,
        description:
            '통합 공기질지수는 PM2.5, CO₂, TVOC와 열쾌적성 보정을 함께 반영한 대표 지수입니다. 1을 초과하면 공기질 개선이 필요한 구간으로 봅니다.',
        segments: const [
          (label: '좋음', color: Color(0xFF16A34A), end: 0.5),
          (label: '보통', color: Color(0xFFEAB308), end: 1),
          (label: '조금 나쁨', color: Color(0xFFF97316), end: 2),
          (label: '나쁨', color: Color(0xFFFF4056), end: 3),
          (label: '상당히 나쁨', color: Color(0xFFB91C1C), end: 4),
          (label: '매우 나쁨', color: Color(0xFF9333EA), end: 5),
        ],
        lines: const [
          ('좋음', '0.5 미만'),
          ('보통', '0.5-1.0'),
          ('개선 필요', '1.0 초과'),
          ('강한 개선 필요', '3.0 초과'),
        ],
      );
    case 'CO':
      return (
        max: 50,
        description:
            'CO는 일산화탄소입니다. CO 확장 센서가 연결된 경우에만 표시되며, 값이 없으면 N/A로 표시합니다. CO는 낮은 농도라도 지속되면 위험할 수 있어 별도 기준으로 확인합니다.',
        segments: const [
          (label: '좋음', color: Color(0xFF16A34A), end: 10),
          (label: '주의', color: Color(0xFFF97316), end: 35),
          (label: '위험', color: Color(0xFFDC2626), end: 50),
        ],
        lines: const [
          ('좋음', '10 ppm 미만'),
          ('주의', '10-35 ppm'),
          ('위험', '35 ppm 이상'),
          ('미수신', 'CO 확장 센서가 없으면 N/A'),
        ],
      );
    case '온도':
      return (
        max: 35,
        description:
            '온도는 실내가 춥거나 더운 정도를 보여줍니다. 같은 공기질이라도 온도가 너무 낮거나 높으면 체감이 크게 달라져요.',
        segments: const [
          (label: '서늘함', color: Color(0xFF38BDF8), end: 18),
          (label: '쾌적', color: Color(0xFF16A34A), end: 24),
          (label: '따뜻함', color: Color(0xFFF97316), end: 28),
          (label: '더움', color: Color(0xFFDC2626), end: 35),
        ],
        lines: const [
          ('서늘함', '18°C 미만'),
          ('쾌적', '18-24°C'),
          ('따뜻함', '24-28°C'),
          ('더움', '28°C 초과'),
        ],
      );
    default:
      return (
        max: 100,
        description:
            '습도는 공기 중 수분의 양입니다. 너무 낮으면 건조하고, 너무 높으면 꿉꿉하거나 곰팡이가 생기기 쉬워요.',
        segments: const [
          (label: '건조', color: Color(0xFF38BDF8), end: 30),
          (label: '쾌적', color: Color(0xFF16A34A), end: 60),
          (label: '약간 높음', color: Color(0xFFF97316), end: 70),
          (label: '높음', color: Color(0xFFDC2626), end: 100),
        ],
        lines: const [
          ('건조', '30% 미만'),
          ('쾌적', '30-60%'),
          ('약간 높음', '60-70%'),
          ('높음', '70% 초과'),
        ],
      );
  }
}

class _MetricCriteriaBar extends StatelessWidget {
  const _MetricCriteriaBar({
    required this.value,
    required this.max,
    required this.unit,
    required this.segments,
  });

  final double? value;
  final double max;
  final String unit;
  final List<({String label, Color color, double end})> segments;

  @override
  Widget build(BuildContext context) {
    final marker = value == null ? 0.0 : (value! / max).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              children: [
                for (var i = 0; i < segments.length; i++)
                  Expanded(
                    flex: _segmentFlex(i),
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: segments[i].color,
                        borderRadius: BorderRadius.horizontal(
                          left:
                              i == 0 ? const Radius.circular(999) : Radius.zero,
                          right: i == segments.length - 1
                              ? const Radius.circular(999)
                              : Radius.zero,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Positioned.fill(
              child: Align(
                alignment: Alignment(-1 + marker * 2, 0),
                child: Transform.translate(
                  offset: const Offset(0, -15),
                  child: const Icon(
                    Symbols.arrow_drop_down,
                    size: 30,
                    color: CleanColors.onSurface,
                    fill: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < segments.length; i++)
              Expanded(
                flex: _segmentFlex(i),
                child: Text(
                  segments[i].label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: CleanColors.secondary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value == null ? '현재 값 없음' : '현재 ${_formatMetric(value!)} $unit',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: CleanColors.onSurface,
          ),
        ),
      ],
    );
  }

  int _segmentFlex(int index) {
    final previous = index == 0 ? 0.0 : segments[index - 1].end;
    return math.max(1, ((segments[index].end - previous) * 10).round());
  }
}

class _CsvExportCard extends StatelessWidget {
  const _CsvExportCard({
    required this.metricLabel,
    required this.rangeLabel,
    required this.sampleCount,
    required this.exporting,
    required this.serverExporting,
    required this.onExport,
    required this.onServerExport,
    this.message,
    this.success = false,
  });

  final String metricLabel;
  final String rangeLabel;
  final int sampleCount;
  final bool exporting;
  final bool serverExporting;
  final VoidCallback onExport;
  final VoidCallback onServerExport;
  final String? message;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      padding: const EdgeInsets.all(18),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: CleanColors.primaryFixed,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Symbols.download,
                  size: 22,
                  color: CleanColors.primary,
                  fill: 1,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CSV 내보내기', style: _cardTitle),
                    const SizedBox(height: 4),
                    Text(
                      '$metricLabel · $rangeLabel · $sampleCount개 샘플',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _tinyMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (message != null && message!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              message!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                fontWeight: FontWeight.w800,
                color: success ? CleanColors.primary : CleanColors.error,
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            '선택한 기간의 측정 기록을 CSV 파일로 저장합니다. 파일은 휴대폰 Download/AirGradient 폴더에서 확인할 수 있어요.',
            style: _caption,
          ),
          const SizedBox(height: 14),
          GradientButton(
            label: exporting ? 'CSV 저장 중' : '선택 범위 CSV 저장',
            icon: exporting ? Symbols.sync : Symbols.download,
            onTap: exporting ? null : onExport,
          ),
          const SizedBox(height: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: serverExporting ? null : onServerExport,
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: CleanColors.surfaceLow,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    serverExporting ? Symbols.sync : Symbols.cloud_download,
                    size: 19,
                    color: CleanColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    serverExporting ? '서버 CSV 저장 중' : '서버 최근 30일 CSV 저장',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: CleanColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<AirQualitySnapshot> _snapshotsForCsvExport({
  required AirQualityController controller,
  required List<AirQualitySnapshot> rangedHistory,
  required String metricId,
}) {
  final source = rangedHistory.isNotEmpty
      ? rangedHistory
      : [
          if (controller.latestSnapshot != null) controller.latestSnapshot!,
        ];
  return source.where((snapshot) {
    return _hasAnyCsvExportValue(snapshot);
  }).toList(growable: false);
}

List<AirQualitySnapshot> _recentCsvFallbackSnapshots(
  List<AirQualitySnapshot> history,
) {
  if (history.isEmpty) return const <AirQualitySnapshot>[];
  final cutoff = DateTime.now().subtract(const Duration(days: 30));
  final recent = history
      .where((sample) =>
          !sample.timestamp.isBefore(cutoff) && _hasAnyCsvExportValue(sample))
      .toList(growable: false);
  return recent;
}

bool _hasAnyCsvExportValue(AirQualitySnapshot snapshot) {
  final values = <double?>[
    snapshot.pm25,
    snapshot.co2,
    snapshot.tvoc,
    snapshot.nox,
    snapshot.co,
    snapshot.temperature,
    snapshot.humidity,
    snapshot.iaqiScore,
  ];
  return values.any((value) => value != null && value.isFinite && !value.isNaN);
}

String _exportMetricId(_PollutantMetricData data) {
  switch (data.label) {
    case 'PM2.5':
      return 'pm25';
    case 'CO2':
      return 'co2';
    case 'TVOC':
      return 'tvoc';
    case 'NOx':
      return 'nox';
    case 'IAQI':
      return 'iaqi';
    case 'CO':
      return 'co';
    case '온도':
      return 'temperature';
    case '습도':
      return 'humidity';
    default:
      return 'pm25';
  }
}

class _RangeChipRow extends StatelessWidget {
  const _RangeChipRow({
    required this.range,
    required this.onChanged,
  });

  final _LogRange range;
  final ValueChanged<_LogRange> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = <(String, _LogRange)>[
      ('10분', _LogRange.tenMinutes),
      ('1시간', _LogRange.hour),
      ('6시간', _LogRange.sixHours),
      ('24시간', _LogRange.day),
      ('주간', _LogRange.week),
      ('월간', _LogRange.month),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          _LightChip(
            items[i].$1,
            selected: range == items[i].$2,
            onTap: () => onChanged(items[i].$2),
          ),
          if (i != items.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

enum _LogRange { tenMinutes, hour, sixHours, day, week, month }

String _rangeLabel(_LogRange range) {
  return switch (range) {
    _LogRange.tenMinutes => '10분',
    _LogRange.hour => '1시간',
    _LogRange.sixHours => '6시간',
    _LogRange.day => '오늘',
    _LogRange.week => '이번 주',
    _LogRange.month => '이번 달',
  };
}

({DateTime start, DateTime end}) _rangeWindow(
  _LogRange range, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  return switch (range) {
    _LogRange.tenMinutes => (
        start: current.subtract(const Duration(minutes: 10)),
        end: current,
      ),
    _LogRange.hour => (
        start: DateTime(
          current.year,
          current.month,
          current.day,
          current.hour,
        ),
        end: DateTime(
          current.year,
          current.month,
          current.day,
          current.hour,
        ).add(const Duration(hours: 1)),
      ),
    _LogRange.sixHours => (
        start: DateTime(
          current.year,
          current.month,
          current.day,
          (current.hour ~/ 6) * 6,
        ),
        end: DateTime(
          current.year,
          current.month,
          current.day,
          (current.hour ~/ 6) * 6,
        ).add(const Duration(hours: 6)),
      ),
    _LogRange.day => (
        start: DateTime(current.year, current.month, current.day),
        end: DateTime(current.year, current.month, current.day)
            .add(const Duration(days: 1)),
      ),
    _LogRange.week => (
        start: DateTime(current.year, current.month, current.day)
            .subtract(Duration(days: current.weekday - 1)),
        end: DateTime(current.year, current.month, current.day)
            .subtract(Duration(days: current.weekday - 1))
            .add(const Duration(days: 7)),
      ),
    _LogRange.month => (
        start: DateTime(current.year, current.month),
        end: DateTime(current.year, current.month + 1),
      ),
  };
}

({DateTime start, DateTime end}) _chartWindowForRange(
  _LogRange range,
  List<_ChartPoint> points,
) {
  final fallback = _rangeWindow(range);
  if (points.isEmpty) return fallback;
  final sorted = [...points]..sort((a, b) => a.time.compareTo(b.time));
  final duration = fallback.end.difference(fallback.start);
  if (duration <= Duration.zero) return fallback;
  final start = sorted.first.time;
  return (start: start, end: start.add(duration));
}

List<AirQualitySnapshot> _historyForRange(
  AirQualityController controller,
  _LogRange range,
) {
  final history = controller.rawHistory;
  if (history.isEmpty) return const <AirQualitySnapshot>[];

  final window = _rangeWindow(range);
  final filtered = history
      .where((sample) =>
          !sample.timestamp.isBefore(window.start) &&
          sample.timestamp.isBefore(window.end))
      .toList(growable: false);
  return filtered;
}

List<_PollutantMetricData> _livePollutantMetrics(
  AirQualityController controller, {
  List<AirQualitySnapshot>? historyOverride,
}) {
  final snapshot = controller.latestSnapshot;
  final history = historyOverride ?? controller.rawHistory;
  if (snapshot == null && history.isEmpty) {
    return const <_PollutantMetricData>[];
  }

  return [
    _metricFromHistory(
      label: 'PM2.5',
      title: 'PM2.5 초미세먼지',
      unit: 'µg/m³',
      icon: Symbols.air,
      current: snapshot?.pm25,
      history: history,
      valueOf: (sample) => sample.pm25,
      statusOf: pm25Status,
      summary: '초미세먼지가 낮으면 실내 공기가 비교적 깨끗하게 유지되고 있다는 뜻입니다.',
    ),
    _metricFromHistory(
      label: 'CO2',
      title: 'CO₂ 이산화탄소',
      unit: 'ppm',
      icon: Symbols.co2,
      current: snapshot?.co2,
      history: history,
      valueOf: (sample) => sample.co2,
      statusOf: co2Status,
      summary: '이산화탄소가 높아지면 공기가 답답하게 느껴질 수 있어요.',
    ),
    _metricFromHistory(
      label: 'TVOC',
      title: 'TVOC 총휘발성유기화합물',
      unit: 'index',
      icon: Symbols.science,
      current: snapshot?.tvoc,
      history: history,
      valueOf: (sample) => sample.tvoc,
      statusOf: tvocStatus,
      summary: '냄새나 화학물질이 늘면 TVOC 값이 올라갈 수 있어요.',
    ),
    _metricFromHistory(
      label: 'NOx',
      title: 'NOx 질소산화물',
      unit: 'index',
      icon: Symbols.cloud,
      current: snapshot?.nox,
      history: history,
      valueOf: (sample) => sample.nox,
      statusOf: noxStatus,
      summary: '연소기기 사용이나 외부 공기 유입이 있을 때 NOx가 오를 수 있어요.',
    ),
    _metricFromHistory(
      label: 'IAQI',
      title: '통합 공기질 지수',
      unit: '',
      icon: Symbols.speed,
      current: snapshot?.iaqiScore,
      history: history,
      valueOf: (sample) => sample.iaqiScore,
      statusOf: _iaqiChartStatus,
      summary: '여러 공기질 지표와 열쾌적성 보정을 함께 반영한 대표 지수입니다.',
    ),
    _metricFromHistory(
      label: 'CO',
      title: 'CO 일산화탄소',
      unit: 'ppm',
      icon: Symbols.warning,
      current: snapshot?.co,
      history: history,
      valueOf: (sample) => sample.co,
      statusOf: coStatus,
      summary: 'CO 센서가 연결된 경우 일산화탄소 농도를 표시합니다. 값이 없으면 확장 센서가 연결되지 않은 상태입니다.',
    ),
    _metricFromHistory(
      label: '온도',
      title: '실내 온도',
      unit: '°C',
      icon: Symbols.device_thermostat,
      current: snapshot?.temperature,
      history: history,
      valueOf: (sample) => sample.temperature,
      statusOf: temperatureStatus,
      summary: '실내가 춥거나 더운 정도를 보여줍니다.',
    ),
    _metricFromHistory(
      label: '습도',
      title: '실내 습도',
      unit: '%',
      icon: Symbols.humidity_percentage,
      current: snapshot?.humidity,
      history: history,
      valueOf: (sample) => sample.humidity,
      statusOf: humidityStatus,
      summary: '실내가 건조한지, 꿉꿉한지 확인할 수 있어요.',
    ),
  ];
}

_PollutantMetricData _metricFromHistory({
  required String label,
  required String title,
  required String unit,
  required IconData icon,
  required double? current,
  required List<AirQualitySnapshot> history,
  required double? Function(AirQualitySnapshot sample) valueOf,
  required String Function(double value) statusOf,
  required String summary,
}) {
  final rawValues =
      history.map(valueOf).whereType<double>().toList(growable: false);
  final timeline = history
      .where((sample) => valueOf(sample) != null)
      .toList(growable: false);
  final values = rawValues.isEmpty
      ? <double>[
          if (current != null && current.isFinite) current,
        ]
      : _downsampleValues(rawValues, maxPoints: 48);
  if (values.isEmpty) {
    final noDataLabel = label == 'CO' ? 'N/A' : '-';
    final noDataStatus = label == 'CO' ? '데이터 없음' : '연결 대기';
    return _PollutantMetricData(
      label: label,
      title: title,
      value: noDataLabel,
      unit: unit,
      status: noDataStatus,
      summary: summary,
      max: '-',
      min: '-',
      avg: '-',
      median: '-',
      values: const <double>[],
      points: const <_ChartPoint>[],
      statusOf: statusOf,
      rows: const <_DataLogRow>[],
      icon: icon,
      sampleCount: 0,
      startLabel: '-',
      midLabel: '-',
      endLabel: '-',
    );
  }
  final latest = current ?? values.last;
  final maxValue = values.reduce(math.max);
  final minValue = values.reduce(math.min);
  final avgValue = values.reduce((a, b) => a + b) / values.length;
  final sorted = [...values]..sort();
  final medianValue = sorted[sorted.length ~/ 2];
  final rows = history.reversed
      .where((sample) => valueOf(sample) != null)
      .take(20)
      .map((sample) {
    final value = valueOf(sample)!;
    final status = statusOf(value);
    return (
      a: _timeLabel(sample.timestamp),
      b: '${_formatMetric(value)} $unit',
      c: status,
      color:
          status == '좋음' || status == '최적' || status == '적정' || status == '쾌적'
              ? const Color(0xFF16A34A)
              : status == '주의' || status == '보통'
                  ? const Color(0xFFCA8A04)
                  : CleanColors.error,
    );
  }).toList(growable: false);

  return _PollutantMetricData(
    label: label,
    title: title,
    value: _formatMetric(latest),
    unit: unit,
    status: statusOf(latest),
    summary: _metricStatusSummary(
      label: label,
      value: latest,
      unit: unit,
      status: statusOf(latest),
    ),
    max: _formatMetric(maxValue),
    min: _formatMetric(minValue),
    avg: _formatMetric(avgValue),
    median: _formatMetric(medianValue),
    values: values,
    points: _chartPointsForMetric(
      timeline: timeline,
      valueOf: valueOf,
      fallbackValue: current,
    ),
    statusOf: statusOf,
    rows: rows,
    icon: icon,
    sampleCount: rawValues.isEmpty && current != null ? 1 : rawValues.length,
    startLabel:
        timeline.isEmpty ? '-' : _chartTimeLabel(timeline.first.timestamp),
    midLabel: timeline.isEmpty
        ? '현재'
        : _chartTimeLabel(timeline[timeline.length ~/ 2].timestamp),
    endLabel:
        timeline.isEmpty ? '현재' : _chartTimeLabel(timeline.last.timestamp),
  );
}

String _metricStatusSummary({
  required String label,
  required double value,
  required String unit,
  required String status,
}) {
  final formatted = _formatMetric(value);
  final unitText = unit.trim().isEmpty ? '' : ' $unit';
  return switch (label) {
    'PM2.5' => switch (status) {
        '좋음' || '최적' || '적정' || '쾌적' => '현재 초미세먼지가 낮아 공기질이 좋습니다.',
        '보통' || '주의' => '현재 초미세먼지는 $formatted$unitText로 보통 범위입니다.',
        _ => '현재 초미세먼지는 $formatted$unitText로 높습니다. 환기나 공기청정기 사용을 권장합니다.',
      },
    'CO2' => switch (status) {
        '좋음' || '최적' || '적정' || '쾌적' => '현재 이산화탄소 농도가 낮아 환기 상태가 좋습니다.',
        '보통' || '주의' => '현재 이산화탄소는 $formatted$unitText로 보통 범위입니다.',
        _ => '현재 이산화탄소는 $formatted$unitText로 높습니다. 환기가 필요합니다.',
      },
    'TVOC' => switch (status) {
        '좋음' || '최적' || '적정' || '쾌적' => '현재 TVOC 영향이 낮습니다.',
        '보통' || '주의' => '현재 TVOC는 $formatted$unitText로 보통 범위입니다.',
        _ => '현재 TVOC는 $formatted$unitText로 높습니다. 냄새나 화학물질 원인을 확인해 주세요.',
      },
    'NOx' => switch (status) {
        '좋음' || '최적' || '적정' || '쾌적' => '현재 NOx 영향이 낮습니다.',
        '보통' || '주의' => '현재 NOx는 $formatted$unitText로 보통 범위입니다.',
        _ => '현재 NOx는 $formatted$unitText로 높습니다. 연소기기 사용이나 외부 공기 유입을 확인해 주세요.',
      },
    'IAQI' => switch (status) {
        '좋음' => '현재 통합 공기질지수는 $formatted로 좋음 범위입니다.',
        '보통' => '현재 통합 공기질지수는 $formatted로 보통 범위입니다.',
        _ => '현재 통합 공기질지수는 $formatted입니다. 공기질 개선이 필요한 구간입니다.',
      },
    'CO' => switch (status) {
        '좋음' => '현재 일산화탄소 농도는 $formatted$unitText로 낮습니다.',
        '주의' => '현재 일산화탄소 농도는 $formatted$unitText입니다. 환기와 연소기기 상태를 확인해 주세요.',
        '위험' =>
          '현재 일산화탄소 농도는 $formatted$unitText로 높습니다. 즉시 환기하고 공간 안전을 확인해 주세요.',
        _ => 'CO 확장 센서 데이터가 아직 수신되지 않았습니다.',
      },
    '온도' => switch (status) {
        '서늘함' => '현재 실내 온도는 $formatted$unitText로 조금 서늘합니다.',
        '따뜻함' || '더움' => '현재 실내 온도는 $formatted$unitText로 다소 높습니다.',
        _ => '현재 실내 온도는 $formatted$unitText로 쾌적한 편입니다.',
      },
    '습도' => switch (status) {
        '건조' => '현재 실내 습도는 $formatted$unitText로 건조한 편입니다.',
        '약간 높음' || '높음' => '현재 실내 습도는 $formatted$unitText로 높은 편입니다.',
        _ => '현재 실내 습도는 $formatted$unitText로 적정 범위입니다.',
      },
    _ => '현재 $label 값은 $formatted$unitText입니다.',
  };
}

List<double> _downsampleValues(List<double> values, {required int maxPoints}) {
  if (values.length <= maxPoints) return values;
  final result = <double>[];
  for (var i = 0; i < maxPoints; i++) {
    final start = (i * values.length / maxPoints).floor();
    final end = (((i + 1) * values.length / maxPoints).floor())
        .clamp(start + 1, values.length)
        .toInt();
    final bucket = values.sublist(start, end);
    result.add(bucket.reduce((a, b) => a + b) / bucket.length);
  }
  return result;
}

List<_ChartPoint> _chartPointsForMetric({
  required List<AirQualitySnapshot> timeline,
  required double? Function(AirQualitySnapshot sample) valueOf,
  required double? fallbackValue,
  int maxPoints = 48,
}) {
  final points = timeline
      .map((sample) {
        final value = valueOf(sample);
        if (value == null || !value.isFinite) return null;
        return (time: sample.timestamp, value: value);
      })
      .whereType<_ChartPoint>()
      .toList(growable: false);
  if (points.isEmpty) {
    return <_ChartPoint>[
      if (fallbackValue != null && fallbackValue.isFinite)
        (time: DateTime.now(), value: fallbackValue),
    ];
  }
  if (points.length <= maxPoints) return points;

  final result = <_ChartPoint>[];
  for (var i = 0; i < maxPoints; i++) {
    final start = (i * points.length / maxPoints).floor();
    final end = (((i + 1) * points.length / maxPoints).floor())
        .clamp(start + 1, points.length)
        .toInt();
    final bucket = points.sublist(start, end);
    final avg = bucket.map((point) => point.value).reduce((a, b) => a + b) /
        bucket.length;
    result.add((time: bucket[bucket.length ~/ 2].time, value: avg));
  }
  return result;
}

String _formatMetric(double value) {
  if (value.abs() >= 100 || value == value.roundToDouble()) {
    return value.round().toString();
  }
  return value.toStringAsFixed(value.abs() < 1 ? 2 : 1);
}

String _timeLabel(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}';
}

String _chartTimeLabel(DateTime time) {
  final local = time.toLocal();
  return '${local.month}/${local.day} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _clockMinuteLabel(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _chartAxisTimeLabel(DateTime time, DateTime first, DateTime last) {
  final local = time.toLocal();
  final span = last.difference(first).abs();
  if (span.inHours < 1) {
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
  if (span.inDays < 1) {
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
  return '${local.month}/${local.day}';
}

class _HealthComputationData {
  _HealthComputationData({
    required this.result,
    required this.latest,
    required this.hasLiveData,
    required this.hasChildData,
    required this.hasSeniorCardioData,
    required this.hasSeniorSleepData,
    required this.hasPurificationCadrData,
    required this.hasPurificationIpiData,
    required this.hasPurificationVentilationData,
  });

  final Map<String, dynamic> result;
  final AirQualitySnapshot? latest;
  final bool hasLiveData;
  final bool hasChildData;
  final bool hasSeniorCardioData;
  final bool hasSeniorSleepData;
  final bool hasPurificationCadrData;
  final bool hasPurificationIpiData;
  final bool hasPurificationVentilationData;

  factory _HealthComputationData.from(AirQualityController controller) {
    final engine = NodeRedHealthEngine();
    final sortedHistory = [...controller.rawHistory]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    var computed = <String, dynamic>{};

    for (final sample in sortedHistory) {
      computed = _compute(engine, sample);
    }

    final latest = controller.latestSnapshot;
    if (latest != null) {
      computed = _compute(engine, latest);
    }

    return _HealthComputationData(
      result: computed,
      latest: latest,
      hasLiveData:
          latest != null && controller.status == LiveDataStatus.connected,
      hasChildData: _hasChildSource(latest, computed),
      hasSeniorCardioData: _hasSeniorCardioSource(latest, computed),
      hasSeniorSleepData: _hasSeniorSleepSource(latest, computed),
      hasPurificationCadrData: _hasPurificationCadrSource(latest, computed),
      hasPurificationIpiData: _hasPurificationIpiSource(latest, computed),
      hasPurificationVentilationData:
          _hasPurificationVentilationSource(latest, computed),
    );
  }

  static bool _hasChildSource(
    AirQualitySnapshot? latest,
    Map<String, dynamic> computed,
  ) {
    if (latest?.child != null) return true;
    final child = _map(computed['child']);
    if (child.isEmpty) return false;
    return latest?.temperature != null ||
        latest?.humidity != null ||
        latest?.tvoc != null ||
        latest?.co2 != null ||
        latest?.pm25 != null;
  }

  static bool _hasSeniorCardioSource(
    AirQualitySnapshot? latest,
    Map<String, dynamic> computed,
  ) {
    if (latest?.senior?.cardio != null ||
        latest?.senior?.pmExposure != null ||
        latest?.cardioScore != null ||
        latest?.cardioRisk != null) {
      return true;
    }
    final senior = _map(computed['senior']);
    final cardio = _map(senior['cardio']);
    final exposure = _map(senior['pmExposure']);
    if (cardio.isEmpty && exposure.isEmpty) return false;
    return latest?.pm25 != null;
  }

  static bool _hasSeniorSleepSource(
    AirQualitySnapshot? latest,
    Map<String, dynamic> computed,
  ) {
    if (latest?.senior?.sleep != null || latest?.sleepComfort != null) {
      return true;
    }
    final senior = _map(computed['senior']);
    final sleep = _map(senior['sleep']);
    if (sleep.isEmpty) return false;
    return latest?.co2 != null || latest?.tvoc != null;
  }

  static bool _hasPurificationCadrSource(
    AirQualitySnapshot? latest,
    Map<String, dynamic> computed,
  ) {
    if (latest?.purification?.cadr != null || latest?.purifier != null) {
      return true;
    }
    final purification = _map(computed['purification']);
    final cadr = _map(purification['cadr']);
    if (cadr.isEmpty) return false;
    return latest?.pm25 != null && latest?.co2 != null;
  }

  static bool _hasPurificationIpiSource(
    AirQualitySnapshot? latest,
    Map<String, dynamic> computed,
  ) {
    if (latest?.purification?.ipi != null || latest?.ipi != null) {
      return true;
    }
    final purification = _map(computed['purification']);
    final ipi = _map(purification['ipi']);
    if (ipi.isEmpty) return false;
    return latest?.pm25 != null && latest?.co2 != null;
  }

  static bool _hasPurificationVentilationSource(
    AirQualitySnapshot? latest,
    Map<String, dynamic> computed,
  ) {
    if (latest?.purification?.ventilation != null) return true;
    final purification = _map(computed['purification']);
    final ventilation = _map(purification['ventilation']);
    if (ventilation.isEmpty) return false;
    return latest?.co2 != null;
  }

  static Map<String, dynamic> _compute(
    NodeRedHealthEngine engine,
    AirQualitySnapshot sample,
  ) {
    return engine.compute(
      pm25: sample.pm25,
      co2: sample.co2,
      tvoc: sample.tvoc,
      temp: sample.temperature,
      humidity: sample.humidity,
      timestampMs: sample.timestamp.millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> get child => _map(result['child']);
  Map<String, dynamic> get senior => _map(result['senior']);
  Map<String, dynamic> get purification => _map(result['purification']);
  Map<String, dynamic> get respiratory => _map(child['respiratory']);
  Map<String, dynamic> get infection => _map(child['infection']);
  Map<String, dynamic> get mold => _map(child['mold']);
  Map<String, dynamic> get focus => _map(child['focus']);
  Map<String, dynamic> get cardio => _map(senior['cardio']);
  Map<String, dynamic> get pmExposure => _map(senior['pmExposure']);
  Map<String, dynamic> get sleep => _map(senior['sleep']);
  Map<String, dynamic> get cadr => _map(purification['cadr']);
  Map<String, dynamic> get ipi => _map(purification['ipi']);
  Map<String, dynamic> get ventilation => _map(purification['ventilation']);

  double get pm25 => latest?.pm25 ?? 0;
  double get co2 => latest?.co2 ?? _double(focus['co2'], 0);
  double get humidity => latest?.humidity ?? _double(respiratory['rh'], 0);

  int? get respiratoryScore =>
      hasChildData ? _double(respiratory['score'], 0).round() : null;
  String get respiratoryLevel =>
      hasChildData ? _string(respiratory['level'], '데이터 연결 대기') : '데이터 연결 대기';
  String get respiratoryMessage {
    if (!hasChildData) {
      return '온도, 습도, TVOC 데이터가 들어오면 호흡기 부담을 계산합니다.';
    }
    final rh = _string(respiratory['rhMsg'], '습도 데이터 대기');
    final temp = _string(respiratory['tMsg'], '온도 데이터 대기');
    final voc = _string(respiratory['vocMsg'], 'VOC 데이터 대기');
    return '$rh · $temp · $voc';
  }

  String get infectionLevel =>
      hasChildData ? _string(infection['level'], '데이터 연결 대기') : '데이터 연결 대기';
  String get infectionMessage => hasChildData
      ? 'CO₂ ${co2.round()} ppm · 습도 ${humidity.round()}% 기준 감염 위험 산출'
      : 'CO₂와 습도 데이터 연결 후 기존 감염 위험 조합표로 산출합니다.';

  String get moldLevel => hasChildData ? _string(mold['riskLevel'], '1') : '대기';
  String get moldMessage => hasChildData
      ? _string(
          mold['riskMessage'],
          '센서 데이터 연결 후 곰팡이 위험을 산출합니다.',
        )
      : '습도 지속 시간과 PM2.5 데이터 연결 후 기존 곰팡이 위험 로직으로 산출합니다.';

  String get focusLevel =>
      hasChildData ? _string(focus['level'], '데이터 연결 대기') : '데이터 연결 대기';
  String get focusMessage => hasChildData
      ? _string(
          focus['message'],
          'CO₂ 데이터 연결 후 집중 환경을 산출합니다.',
        )
      : 'CO₂ 데이터 연결 후 기존 집중 환경 기준으로 산출합니다.';
  String get focusAction => hasChildData
      ? _string(focus['recommendedAction'], '센서 연결 상태 확인')
      : '센서 데이터 연결 대기';

  int? get cardioScore {
    if (!hasSeniorCardioData) return null;
    final snapshotScore = latest?.senior?.cardio?.score ?? latest?.cardioScore;
    return (snapshotScore ?? _double(cardio['score'], 0)).round();
  }

  String get cardioLevel {
    if (!hasSeniorCardioData) return '데이터 연결 대기';
    return latest?.senior?.cardio?.level ??
        _string(cardio['level'], '데이터 연결 대기');
  }

  String get pmExposureMessage {
    if (!hasSeniorCardioData) {
      return 'PM2.5 데이터 연결 후 기존 심혈관 노출 위험 로직으로 산출합니다.';
    }
    return latest?.senior?.pmExposure?.message ??
        _string(
          pmExposure['message'],
          'PM2.5 데이터 연결 후 노출 위험을 산출합니다.',
        );
  }

  int? get sleepScore {
    if (!hasSeniorSleepData) return null;
    final snapshotScore = latest?.senior?.sleep?.score ?? latest?.sleepComfort;
    return (snapshotScore ?? _double(sleep['score'], 0)).round();
  }

  String get sleepLevel {
    if (!hasSeniorSleepData) return '데이터 연결 대기';
    return latest?.senior?.sleep?.level ?? _string(sleep['level'], '데이터 부족');
  }

  int? get sleepGoodCo2 {
    if (!hasSeniorSleepData) return null;
    return (latest?.senior?.sleep?.goodCo2 ?? _double(sleep['goodCo2'], 0))
        .round();
  }

  int? get sleepGoodVoc {
    if (!hasSeniorSleepData) return null;
    return (latest?.senior?.sleep?.goodVoc ?? _double(sleep['goodVoc'], 0))
        .round();
  }

  double? get kPm25 {
    if (!hasPurificationCadrData) return null;
    return latest?.purification?.cadr?.kPm25 ??
        latest?.purifier?.k ??
        latest?.purifier?.kEffective ??
        _nullableDouble(cadr['k_pm25']);
  }

  double? get kCo2 {
    if (!hasPurificationCadrData) return null;
    return latest?.purification?.cadr?.kCo2 ?? _nullableDouble(cadr['k_co2']);
  }

  double? get r2Pm25 {
    if (!hasPurificationCadrData) return null;
    return latest?.purification?.cadr?.r2Pm25 ??
        _nullableDouble(cadr['r2_pm25']);
  }

  double? get r2Co2 {
    if (!hasPurificationCadrData) return null;
    return latest?.purification?.cadr?.r2Co2 ?? _nullableDouble(cadr['r2_co2']);
  }

  String get cadrGrade {
    if (!hasPurificationCadrData) return '데이터 연결 대기';
    return latest?.purification?.cadr?.grade ??
        latest?.purifier?.cadrGrade ??
        _string(cadr['grade'], '데이터 연결 대기');
  }

  int? get cadrIndex {
    if (!hasPurificationCadrData) return null;
    return latest?.purification?.cadr?.index ??
        latest?.purifier?.cadrIndex?.round() ??
        _nullableInt(cadr['index']);
  }

  int? get t50Minutes {
    if (!hasPurificationCadrData) return null;
    return latest?.purification?.cadr?.t50Minutes?.round() ??
        latest?.purifier?.t50Minutes?.round() ??
        _nullableInt(cadr['t50_min']);
  }

  String get scenario {
    if (!hasPurificationCadrData) return '센서 히스토리 연결 대기';
    return latest?.purification?.cadr?.scenario ??
        _string(cadr['scenario'], '센서 히스토리 연결 대기');
  }

  String get ipiLevel {
    if (!hasPurificationIpiData) return '데이터 연결 대기';
    return latest?.purification?.ipi?.level ??
        latest?.ipi?.level ??
        _string(ipi['level'], '데이터 연결 대기');
  }

  int? get ipiScore {
    if (!hasPurificationIpiData) return null;
    return latest?.purification?.ipi?.score ??
        latest?.ipi?.score ??
        _nullableInt(ipi['score']);
  }

  int? get t90Minutes {
    if (!hasPurificationIpiData) return null;
    return latest?.purification?.ipi?.t90Minutes?.round() ??
        latest?.ipi?.t90Minutes?.round() ??
        _nullableInt(ipi['t90_min']);
  }

  String get ventilationStatus {
    if (!hasPurificationVentilationData) return '연결 대기';
    return latest?.purification?.ventilation?.status ??
        _string(ventilation['status'], '연결 대기');
  }

  String get ventilationMessage {
    if (!hasPurificationVentilationData) {
      return 'CO₂ 데이터와 히스토리 연결 후 기존 정화/환기 추세 로직으로 산출합니다.';
    }
    return latest?.purification?.ventilation?.message ??
        _string(ventilation['message'], '센서 히스토리 연결 후 정화 추세를 산출합니다.');
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return const <String, dynamic>{};
  }

  static String _string(Object? value, String fallback) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static double _double(Object? value, double fallback) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double? _nullableDouble(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static int? _nullableInt(Object? value) {
    if (value is num && value.isFinite) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }
}

Color _healthColor(String level) {
  if (level.contains('위험') ||
      level.contains('경고') ||
      level.contains('높음') ||
      level.contains('나쁨')) {
    return CleanColors.error;
  }
  if (level.contains('주의') || level.contains('보통') || level.contains('양호')) {
    return CleanColors.tertiary;
  }
  return CleanColors.primary;
}

String _formatHealthNumber(double? value, int fractionDigits) {
  if (value == null || !value.isFinite) return '-';
  return value.toStringAsFixed(fractionDigits);
}

List<_ChartPoint> _purificationKTrendPoints(AirQualityController controller) {
  final points = <_ChartPoint>[];
  for (final sample in controller.rawHistory) {
    final value = sample.purification?.cadr?.kEffective ??
        sample.purification?.cadr?.k ??
        sample.purifier?.kEffective ??
        sample.purifier?.k;
    if (value != null && value.isFinite && value >= 0) {
      points.add((time: sample.timestamp, value: value));
    }
  }
  if (points.length > 36) return points.sublist(points.length - 36);
  final latest = controller.latestSnapshot?.purification?.cadr?.kEffective ??
      controller.latestSnapshot?.purification?.cadr?.k ??
      controller.latestSnapshot?.purifier?.kEffective ??
      controller.latestSnapshot?.purifier?.k;
  if (points.isEmpty && latest != null && latest.isFinite && latest >= 0) {
    return <_ChartPoint>[(time: DateTime.now(), value: latest)];
  }
  return points;
}

void _showHealthCriteriaSheet(
  BuildContext context, {
  required String title,
  required String current,
  required List<String> lines,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: _cardTitle)),
                  _StatusPill(text: current),
                ],
              ),
              const SizedBox(height: 14),
              for (final line in lines) ...[
                _CriteriaLine(text: line),
                const SizedBox(height: 9),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _CriteriaLine extends StatelessWidget {
  const _CriteriaLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 7),
          decoration: const BoxDecoration(
            color: CleanColors.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              height: 1.42,
              fontWeight: FontWeight.w700,
              color: CleanColors.onVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class HealthChildScreen extends StatelessWidget {
  const HealthChildScreen({super.key, this.onTabSelected, this.onProfile});

  final ValueChanged<int>? onTabSelected;
  final VoidCallback? onProfile;

  @override
  Widget build(BuildContext context) {
    final health = _HealthComputationData.from(
      context.watch<AirQualityController>(),
    );
    final respiratoryColor = _healthColor(health.respiratoryLevel);
    final infectionColor = _healthColor(health.infectionLevel);
    final moldColor = _healthColor(health.moldLevel);

    return _LegacyPage(
      title: 'CleanAir',
      leading: Symbols.location_on,
      trailing: Symbols.person,
      leadingColor: CleanColors.primaryContainer,
      onProfileTap: onProfile,
      children: [
        _HealthModeHeader(
          active: 0,
          icon: Symbols.child_care,
          onSelected: onTabSelected,
        ),
        const SizedBox(height: 14),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showHealthCriteriaSheet(
            context,
            title: '호흡기 건강 지수',
            current:
                '${health.respiratoryScore ?? '-'} · ${health.respiratoryLevel}',
            lines: const [
              '온도, 습도, TVOC를 함께 보고 호흡기에 부담이 되는 환경인지 판단합니다.',
              '습도는 40-60%를 안정 범위로 두고, 이 범위에서 멀어질수록 점수를 낮춥니다.',
              '온도는 20-24°C를 가장 편안한 범위로 보고, 덥거나 추운 쪽으로 벗어나면 부담을 반영합니다.',
              'TVOC Index가 높을수록 냄새, 조리 연기, 생활 화학물질 같은 실내 오염 가능성이 커집니다.',
              '세 항목을 합산해 80점 이상은 좋음, 60점 이상은 보통, 40점 이상은 주의로 표시합니다.',
              '주의 이하로 내려가면 환기, 오염원 제거, 습도 조절을 먼저 권장합니다.',
            ],
          ),
          child: _SoftCard(
            radius: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '호흡기 건강 지수',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: CleanColors.secondary,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text('온도, 습도, TVOC 복합 분석', style: _tinyMuted),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          health.respiratoryScore?.toString() ?? '-',
                          style: TextStyle(
                            fontSize: 46,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            color: respiratoryColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          health.respiratoryLevel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: respiratoryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: CleanColors.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text.rich(
                    TextSpan(
                      text: health.hasLiveData ? '실시간 분석' : '연결 대기',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w900,
                        color: CleanColors.primary,
                      ),
                      children: [
                        TextSpan(
                          text: ' · ${health.respiratoryMessage}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: CleanColors.onVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showHealthCriteriaSheet(
                  context,
                  title: '면역/감염 위험',
                  current: health.infectionLevel,
                  lines: const [
                    '환기가 부족하고 습도가 적정 범위를 벗어나면 호흡기 부담이 커질 수 있습니다.',
                    'CO₂는 800 ppm 이하, 800-1000 ppm, 1000-1500 ppm, 1500 ppm 이상으로 구간을 나눕니다.',
                    '습도는 40-60%를 가장 안정적인 범위로 보고, 여기서 멀어질수록 위험도를 높입니다.',
                    '두 조건이 동시에 나쁠수록 점수가 올라가며, 30/60/80 기준으로 낮음/보통/높음/매우 높음으로 표시합니다.',
                    '어린이나 고령자가 있는 공간에서는 높음 이상일 때 환기를 먼저 권장합니다.',
                  ],
                ),
                child: _RiskStatusCard(
                  icon: Symbols.shield,
                  title: '면역/감염 위험',
                  value: health.infectionLevel,
                  subtitle: health.infectionMessage,
                  color: infectionColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showHealthCriteriaSheet(
                  context,
                  title: '곰팡이 위험도',
                  current:
                      health.hasChildData ? 'Level ${health.moldLevel}' : '-',
                  lines: const [
                    '습도가 오래 높게 유지되면 곰팡이가 생기기 쉬워집니다.',
                    '습도 60% 초과가 시작되면 고습 지속시간을 누적하고, 60% 이하로 내려가면 누적을 초기화합니다.',
                    '고습 상태가 24시간 이상 지속되면 Level 4 - 위험 상태로 간주합니다.',
                    '습도가 70%를 넘거나, 습도 60% 초과와 PM2.5 35 µg/m³ 초과가 함께 나타나면 Level 3 - 경고로 판단합니다.',
                    '습도 60% 초과가 단독으로 나타나면 Level 2 - 주의로 표시합니다.',
                    'Level 2부터는 환기나 제습을 준비하고, Level 3 이상이면 습도를 낮추는 조치를 바로 권장합니다.',
                  ],
                ),
                child: _RiskStatusCard(
                  icon: Symbols.biotech,
                  title: '곰팡이 위험도',
                  value:
                      health.hasChildData ? 'Level ${health.moldLevel}' : '-',
                  subtitle: health.moldMessage,
                  color: moldColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showHealthCriteriaSheet(
            context,
            title: '집중환경 판단',
            current: '${health.co2.round()} ppm · ${health.focusLevel}',
            lines: const [
              'CO₂ 농도를 중심으로 학습과 집중에 부담이 되는 환기 상태인지 판단합니다.',
              '800 ppm 이하는 집중하기 좋은 상태로 판단합니다.',
              '800-1000 ppm은 보통, 1000 ppm 이상은 환기가 필요한 구간입니다.',
              '1500 ppm 이상이면 창문 환기나 환기장치 가동을 우선 권장합니다.',
              '값이 높을수록 졸림이나 답답함을 느끼기 쉽습니다.',
            ],
          ),
          child: _FocusEnvironmentCard(data: health),
        ),
      ],
    );
  }
}

class HealthPurificationScreen extends StatelessWidget {
  const HealthPurificationScreen({
    super.key,
    this.onTabSelected,
    this.onProfile,
  });

  final ValueChanged<int>? onTabSelected;
  final VoidCallback? onProfile;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AirQualityController>();
    final health = _HealthComputationData.from(controller);
    final kTrendPoints = _purificationKTrendPoints(controller);
    final kTrendValues =
        kTrendPoints.map((point) => point.value).toList(growable: false);
    final cadrIndex = health.cadrIndex;
    final t50Minutes = health.t50Minutes;
    final t90Minutes = health.t90Minutes;
    final ipiScore = health.ipiScore;
    final cadrActive =
        cadrIndex == null ? -1 : (cadrIndex - 1).clamp(0, 3).toInt();

    return _LegacyPage(
      title: 'CleanAir',
      leading: Symbols.location_on,
      trailing: Symbols.air,
      leadingColor: CleanColors.primaryContainer,
      onProfileTap: onProfile,
      children: [
        _HealthModeHeader(
          active: 2,
          icon: Symbols.air_purifier_gen,
          onSelected: onTabSelected,
        ),
        const SizedBox(height: 14),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showHealthCriteriaSheet(
            context,
            title: '정화속도 k',
            current:
                'PM ${_formatHealthNumber(health.kPm25, 2)} · CO₂ ${_formatHealthNumber(health.kCo2, 2)}',
            lines: const [
              '최근 공기질 감소 추세로 공간의 정화 속도를 추정합니다.',
              'PM2.5와 CO₂가 실제로 줄어드는 구간을 이용해 감소 속도를 계산합니다.',
              '값이 클수록 오염물질 농도가 더 빠르게 낮아진다는 뜻입니다.',
              '반감기 t50은 ln(2) / k × 60분 공식입니다.',
              'R²는 오염물질 농도 감소 회귀 모델의 적합도를 나타내며, R²가 낮으면 정화속도 산출 신뢰도가 낮아집니다.',
            ],
          ),
          child: _SoftCard(
            radius: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '정화속도 k (최근 5분)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: CleanColors.secondary,
                        ),
                      ),
                    ),
                    _StatusPill(
                      text: health.hasPurificationCadrData ? '실시간' : '연결 대기',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('PM k-value', style: _tinyMuted),
                          const SizedBox(height: 5),
                          Text.rich(
                            TextSpan(
                              text: _formatHealthNumber(health.kPm25, 2),
                              style: const TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w900,
                                color: CleanColors.primary,
                              ),
                              children: const [
                                TextSpan(
                                  text: ' h⁻¹',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: CleanColors.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'R² ${_formatHealthNumber(health.r2Pm25, 3)}',
                            style: _tinyMuted,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('CO₂ k-value', style: _tinyMuted),
                          const SizedBox(height: 5),
                          Text.rich(
                            TextSpan(
                              text: _formatHealthNumber(health.kCo2, 2),
                              style: const TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w900,
                                color: CleanColors.secondary,
                              ),
                              children: const [
                                TextSpan(
                                  text: ' h⁻¹',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: CleanColors.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'R² ${_formatHealthNumber(health.r2Co2, 3)}',
                            style: _tinyMuted,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (kTrendValues.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('최근 k 추세', style: _tinyMuted),
                  const SizedBox(height: 8),
                  _LineChartPanel(
                    values: kTrendValues,
                    points: kTrendPoints,
                    height: 96,
                    unit: 'h⁻¹',
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showHealthCriteriaSheet(
            context,
            title: 'CADR-Index',
            current: 'GRADE ${health.cadrGrade}',
            lines: const [
              '정화속도 k가 높을수록 오염물질이 더 빠르게 줄어든 것으로 판단합니다.',
              'k ≥ 2.0은 S, k ≥ 1.0은 A, k ≥ 0.5는 B, 그 미만은 C입니다.',
              'S/A/B/C 등급은 현재 공간의 정화 성능을 빠르게 비교하기 위한 표시입니다.',
              'PM2.5와 CO₂ 변화가 함께 줄어들면 정화와 환기가 잘 되고 있는 상태로 해석합니다.',
            ],
          ),
          child: _SoftCard(
            radius: 14,
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('CADR-Index', style: _cardTitle),
                    const Spacer(),
                    const Icon(Symbols.stars,
                        size: 16, color: CleanColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      'GRADE ${health.cadrGrade}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: CleanColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _MiniMetric(
                        label: '반감기 t₅₀',
                        value: t50Minutes?.toString() ?? '-',
                        unit: 'min',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        health.scenario,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w800,
                          color: CleanColors.onVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _FourSegmentIndicator(active: cadrActive),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showHealthCriteriaSheet(
            context,
            title: 'IPI 위험지수',
            current: health.ipiLevel,
            lines: const [
              '현재 오염도와 정화 추세를 함께 보고 공기 정화 여유를 계산합니다.',
              't90은 ln(10) / k × 60분 공식으로 계산합니다.',
              'IPI 등급은 CO2 k 기준입니다.',
              'kCO2 ≥ 3.0은 안심, ≥1.0은 보통, ≥0.3은 주의, 그 미만 또는 0 이하는 경고입니다.',
            ],
          ),
          child: _SoftCard(
            color: Colors.white,
            radius: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('IPI 위험지수 (바이러스 잔류)', style: _cardTitle),
                    ),
                    _DangerPill(text: health.ipiLevel),
                  ],
                ),
                const SizedBox(height: 14),
                _KeyValueLine(
                  label: '90% 제거 시간 (t₉₀)',
                  value: t90Minutes == null ? '-' : '$t90Minutes min',
                ),
                const SizedBox(height: 10),
                _KeyValueLine(
                  label: '잔류 농도 리스크',
                  value: ipiScore == null ? '-' : 'LEVEL $ipiScore',
                  valueColor: CleanColors.error,
                ),
                const SizedBox(height: 12),
                Text(
                  'CO₂ k값 기반 유추 결과: ${health.ventilationMessage}',
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: CleanColors.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SoftCard(
          color: const Color(0x1400677D),
          radius: 14,
          child: Column(
            children: [
              _InfoListTile(
                icon: Symbols.air_purifier_gen,
                title: '환기 및 정화 분석 · ${health.ventilationStatus}',
                subtitle: '현재 시나리오: ${health.scenario}',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class HealthSeniorScreen extends StatelessWidget {
  const HealthSeniorScreen({super.key, this.onTabSelected, this.onProfile});

  final ValueChanged<int>? onTabSelected;
  final VoidCallback? onProfile;

  @override
  Widget build(BuildContext context) {
    final health = _HealthComputationData.from(
      context.watch<AirQualityController>(),
    );
    final cardioColor = _healthColor(health.cardioLevel);
    final sleepColor = _healthColor(health.sleepLevel);
    final cardioScore = health.cardioScore;
    final sleepScore = health.sleepScore;

    return _LegacyPage(
      title: 'CleanAir',
      leading: Symbols.location_on,
      trailing: Symbols.person,
      leadingColor: CleanColors.primaryContainer,
      onProfileTap: onProfile,
      children: [
        _HealthModeHeader(
          active: 1,
          icon: Symbols.elderly,
          onSelected: onTabSelected,
        ),
        const SizedBox(height: 14),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showHealthCriteriaSheet(
            context,
            title: '심혈관 보호점수',
            current: cardioScore == null
                ? '-'
                : '$cardioScore점 · ${health.cardioLevel}',
            lines: const [
              'PM2.5와 온열 상태를 함께 보고 고령자에게 부담이 되는 환경인지 판단합니다.',
              '10분 PM2.5 히스토리 중 PM2.5 > 5 µg/m³인 고노출 샘플을 사용합니다.',
              '고노출 시간 highHours와 고노출 구간 평균 kAvg로 riskRaw = highHours × (1 / kAvg)를 계산합니다.',
              'score = 100 × (1 - riskRaw / 8)을 0-100으로 제한합니다.',
              '점수는 80/60/40 기준으로 우수/양호/주의/위험으로 나뉩니다.',
            ],
          ),
          child: _SoftCard(
            color: CleanColors.primary,
            radius: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '심혈관 보호점수',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text.rich(
                            TextSpan(
                              text: cardioScore?.toString() ?? '-',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 42,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                              children: const [
                                TextSpan(
                                  text: '점',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const IconBubble(
                      icon: Symbols.favorite,
                      color: Color(0x33FFFFFF),
                      iconColor: Colors.white,
                      size: 44,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      cardioScore == null
                          ? 'PM 노출 이력 연결 대기'
                          : 'PM 노출 이력 기반 리스크 관리 중',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const Spacer(),
                    Text(
                      health.cardioLevel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(999)),
                  child: LinearProgressIndicator(
                    value:
                        ((cardioScore ?? 0) / 100).clamp(0.0, 1.0).toDouble(),
                    minHeight: 8,
                    color: Colors.white,
                    backgroundColor: const Color(0x33FFFFFF),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  health.pmExposureMessage,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showHealthCriteriaSheet(
                  context,
                  title: '심혈관 리스크',
                  current: health.cardioLevel,
                  lines: const [
                    'PM2.5 노출 이력과 심혈관 보호점수를 같은 기준으로 해석합니다.',
                    '점수가 높을수록 고령자에게 부담이 적은 환경입니다.',
                    '40점 미만은 위험, 40-60점은 주의, 60-80점은 양호, 80점 이상은 우수로 표시합니다.',
                    'PM 노출이 계속 높게 유지되면 환기보다 발생원 제거와 공기정화를 먼저 확인합니다.',
                  ],
                ),
                child: _SoftCard(
                  radius: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Symbols.error,
                            size: 16,
                            color: cardioColor,
                          ),
                          const SizedBox(width: 5),
                          const Text('심혈관 리스크', style: _tinyMuted),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        health.cardioLevel,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: cardioColor,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        health.pmExposureMessage,
                        style: const TextStyle(
                          fontSize: 10,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: CleanColors.onVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _FourSegmentIndicator(
                        active: cardioScore == null
                            ? -1
                            : (cardioScore / 25).floor().clamp(0, 3).toInt(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showHealthCriteriaSheet(
                  context,
                  title: '쾌적 수면지수',
                  current: sleepScore == null
                      ? '-'
                      : '$sleepScore점 · ${health.sleepLevel}',
                  lines: const [
                    '최근 수면 시간대에 CO₂와 TVOC가 얼마나 안정적으로 유지됐는지 모니터링합니다.',
                    'CO₂ 양호 비율과 VOC 양호 비율을 합쳐 0-100점으로 표시합니다.',
                    'CO₂가 높으면 답답함과 각성감이 커질 수 있고, VOC가 높으면 냄새와 자극감을 느낄 수 있습니다.',
                    '점수는 85/70/50 기준으로 쾌적/보통/주의/나쁨으로 나뉩니다.',
                  ],
                ),
                child: _SoftCard(
                  radius: 14,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Symbols.bedtime,
                            size: 16,
                            color: sleepColor,
                          ),
                          const SizedBox(width: 5),
                          const Text('쾌적 수면지수', style: _tinyMuted),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _SleepGauge(
                        score: sleepScore,
                        level: health.sleepLevel,
                      ),
                      const SizedBox(height: 8),
                      _KeyValueLine(
                        label: 'CO₂ 양호 비율',
                        value: health.sleepGoodCo2 == null
                            ? '-'
                            : '${health.sleepGoodCo2}%',
                      ),
                      const SizedBox(height: 5),
                      _KeyValueLine(
                        label: 'VOC 양호 비율',
                        value: health.sleepGoodVoc == null
                            ? '-'
                            : '${health.sleepGoodVoc}%',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SoftCard(
          color: CleanColors.surfaceLow,
          radius: 14,
          child: Stack(
            children: [
              const Positioned(
                right: -18,
                bottom: -24,
                child: Icon(
                  Symbols.wb_sunny,
                  size: 118,
                  color: Color(0x22914D00),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Symbols.device_thermostat,
                        color: CleanColors.tertiary,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '실외 체감온도',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: CleanColors.secondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    health.latest?.apparentTemp != null
                        ? '${health.latest!.apparentTemp!.toStringAsFixed(1)}°'
                        : health.latest?.temperature != null
                            ? '${health.latest!.temperature!.toStringAsFixed(1)}°'
                            : '--',
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _StatusPill(
                    text: health.latest?.apparentTemp != null
                        ? '실외 기준'
                        : '실내 온도 기준',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    health.latest?.apparentTemp != null
                        ? '기온, 습도, 풍속을 반영한 실외 체감 기준입니다.'
                        : '실외 날씨가 연결되면 체감온도로 표시됩니다.',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: CleanColors.onVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class LocationSettingsScreen extends StatefulWidget {
  const LocationSettingsScreen({super.key, this.onBack, this.onConfirm});

  final VoidCallback? onBack;
  final VoidCallback? onConfirm;

  @override
  State<LocationSettingsScreen> createState() => _LocationSettingsScreenState();
}

enum _LocationSettingsStage { overview, search, detail }

class _LocationSettingsScreenState extends State<LocationSettingsScreen> {
  final _storage = SensorLocationStorage();
  final _kakaoLocalService = KakaoLocalService();
  final _searchController = TextEditingController();
  final _buildingController = TextEditingController();
  final _spaceController = TextEditingController();
  final _floorController = TextEditingController();
  final _detailController = TextEditingController();
  final _memoController = TextEditingController();

  _SavedLocationOption _selected = _emptyLocationOption;
  _LocationSettingsStage _stage = _LocationSettingsStage.overview;
  SensorLocationDraft? _savedDraft;
  List<SensorLocationDraft> _savedLocations = const <SensorLocationDraft>[];
  bool _loading = true;
  bool _saving = false;
  bool _searchingLocation = false;
  bool _locatingCurrentPosition = false;
  String _searchQuery = '';
  String? _statusMessage;
  String? _locationSearchMessage;
  int _locationSearchSerial = 0;
  List<_SavedLocationOption> _remoteLocationOptions =
      const <_SavedLocationOption>[];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLocation());
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _kakaoLocalService.close();
    _buildingController.dispose();
    _spaceController.dispose();
    _floorController.dispose();
    _detailController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _loadLocation() async {
    final binding = context.read<DeviceBindingControllerV2>().value;
    final stored = await _storage.loadForSensor(binding.deviceId);
    final savedLocations = await _storage.loadAll();
    if (!mounted) return;
    final draft = stored ?? _defaultDraft();
    _applyDraft(draft);
    setState(() {
      _savedDraft = stored;
      _savedLocations = savedLocations;
      _statusMessage =
          stored == null ? null : '${stored.spaceName} 위치를 불러왔습니다.';
      _loading = false;
    });
  }

  SensorLocationDraft _defaultDraft() {
    final binding = context.read<DeviceBindingControllerV2>().value;
    return SensorLocationDraft.empty(
      sensorId: binding.deviceId,
      sensorName: binding.deviceId,
    );
  }

  void _applyDraft(SensorLocationDraft draft) {
    _selected = _SavedLocationOption(
      buildingName: draft.buildingName,
      address: draft.address,
      latitude: draft.latitude,
      longitude: draft.longitude,
    );
    _buildingController.text = draft.buildingName;
    _spaceController.text = draft.spaceName;
    _floorController.text = draft.floor;
    _detailController.text = draft.detailLocation;
    _memoController.text = draft.installationMemo;
    _searchController.clear();
    _searchQuery = '';
  }

  void _applyOption(_SavedLocationOption option) {
    setState(() {
      _stage = _LocationSettingsStage.detail;
      _selected = option;
      _buildingController.text = option.buildingName;
      _searchController.text = option.address;
      _searchQuery = option.address;
      _statusMessage = '${option.buildingName} 위치가 선택되었습니다.';
    });
  }

  void _updateSelectedMapCenter(KakaoMapCoordinate coordinate) {
    if (_selected.isEmpty) return;
    setState(() {
      _selected = _SavedLocationOption(
        buildingName: _selected.buildingName,
        address: _selected.address,
        latitude: coordinate.latitude,
        longitude: coordinate.longitude,
      );
      _statusMessage = '지도 중심 좌표가 저장 위치로 반영됩니다.';
    });
  }

  void _handleSearchChanged() {
    if (!mounted) return;
    final next = _searchController.text.trim();
    if (next == _searchQuery) return;
    setState(() {
      _searchQuery = next;
      _remoteLocationOptions = const <_SavedLocationOption>[];
      _locationSearchMessage =
          next.length < 2 ? null : '검색 버튼을 누르면 카카오 위치 결과를 불러옵니다.';
      if (next.isNotEmpty) {
        _statusMessage = '검색 결과를 선택하거나 입력한 주소를 사용할 수 있습니다.';
      }
    });
  }

  Future<void> _searchKakaoLocation([String? query]) async {
    final target = (query ?? _searchController.text).trim();
    if (target.length < 2 || _searchingLocation) return;
    if (!_kakaoLocalService.hasKey) {
      setState(() {
        _locationSearchMessage =
            'KAKAO_REST_API_KEY 실행 옵션을 넣으면 카카오 주소 검색을 사용할 수 있습니다.';
      });
      return;
    }

    final serial = ++_locationSearchSerial;
    setState(() {
      _searchingLocation = true;
      _locationSearchMessage = '카카오 위치 검색 중입니다.';
    });

    try {
      final results = await _kakaoLocalService.search(target);
      if (!mounted || serial != _locationSearchSerial) return;
      setState(() {
        _remoteLocationOptions =
            results.map(_optionFromKakao).toList(growable: false);
        _searchingLocation = false;
        _locationSearchMessage = results.isEmpty
            ? '카카오 검색 결과가 없습니다. 입력한 주소를 직접 사용할 수 있습니다.'
            : '카카오 검색 결과 ${results.length}개를 불러왔습니다.';
      });
    } catch (error) {
      if (!mounted || serial != _locationSearchSerial) return;
      setState(() {
        _searchingLocation = false;
        _locationSearchMessage = error is KakaoLocalException
            ? error.message
            : '카카오 위치 검색에 실패했습니다. 네트워크와 REST API 키를 확인하세요.';
      });
    }
  }

  Future<void> _useCurrentPosition() async {
    if (_locatingCurrentPosition) return;
    setState(() {
      _locatingCurrentPosition = true;
      _locationSearchMessage = '현재 위치를 확인하는 중입니다.';
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _locatingCurrentPosition = false;
          _locationSearchMessage = '휴대폰 위치 서비스가 꺼져 있습니다. 위치 서비스를 켠 뒤 다시 시도하세요.';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _locatingCurrentPosition = false;
          _locationSearchMessage =
              permission == LocationPermission.deniedForever
                  ? '설정에서 위치 권한을 허용하면 현재 위치를 사용할 수 있습니다.'
                  : '위치 권한이 거부되어 현재 위치를 사용할 수 없습니다.';
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );
      if (!mounted) return;
      var option = _SavedLocationOption(
        buildingName: '현재 위치',
        address: '현재 위치에서 직접 지정',
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (_kakaoLocalService.hasKey) {
        try {
          final resolved = await _kakaoLocalService.reverseGeocode(
            latitude: position.latitude,
            longitude: position.longitude,
          );
          if (resolved != null) option = _optionFromKakao(resolved);
        } catch (_) {
          // 좌표는 이미 확보했으므로 주소 변환 실패만 조용히 무시합니다.
        }
      }
      if (!mounted) return;
      setState(() {
        _stage = _LocationSettingsStage.detail;
        _selected = option;
        _buildingController.text = option.buildingName;
        if (_spaceController.text.trim().isEmpty) {
          _spaceController.text = '실내 공간';
        }
        _locatingCurrentPosition = false;
        _locationSearchMessage = option.address == '현재 위치에서 직접 지정'
            ? '현재 위치 좌표를 불러왔습니다. 지도와 상세 위치를 확인하고 저장하세요.'
            : '현재 위치 주소를 불러왔습니다. 지도와 상세 위치를 확인하고 저장하세요.';
        _statusMessage = '현재 위치가 선택되었습니다.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _locatingCurrentPosition = false;
        _locationSearchMessage = '현재 위치를 가져오지 못했습니다. 권한과 GPS 상태를 확인하세요.';
      });
    }
  }

  List<_SavedLocationOption> get _filteredLocationOptions {
    if (_searchQuery.trim().isEmpty) return const <_SavedLocationOption>[];
    return _mergeLocationOptions(_remoteLocationOptions);
  }

  bool get _hasTypedAddress {
    final query = _searchQuery.trim();
    if (query.isEmpty) return false;
    return !_remoteLocationOptions.any((option) {
      return option.address == query || option.buildingName == query;
    });
  }

  void _useTypedAddress() {
    final query = _searchQuery.trim();
    if (query.isEmpty) return;
    final fallback = _selected;
    setState(() {
      _stage = _LocationSettingsStage.detail;
      _selected = _SavedLocationOption(
        buildingName: query,
        address: query,
        latitude: fallback.latitude,
        longitude: fallback.longitude,
      );
      _buildingController.text = query;
      if (_spaceController.text.trim().isEmpty) {
        _spaceController.text = '$query 실내';
      }
      _statusMessage = '입력한 주소를 위치로 선택했습니다.';
    });
  }

  _SavedLocationOption _optionFromKakao(KakaoLocalSearchResult result) {
    return _SavedLocationOption(
      buildingName: result.name,
      address: result.address,
      latitude: result.latitude,
      longitude: result.longitude,
    );
  }

  List<_SavedLocationOption> _mergeLocationOptions(
    List<_SavedLocationOption> options,
  ) {
    final seen = <String>{};
    final merged = <_SavedLocationOption>[];
    for (final option in options) {
      final key = '${option.buildingName}|${option.address}';
      if (seen.add(key)) merged.add(option);
    }
    return merged;
  }

  SensorLocationDraft _buildDraft() {
    final binding = context.read<DeviceBindingControllerV2>().value;
    final sensorId = binding.deviceId.trim().isEmpty
        ? 'sensor-unassigned'
        : binding.deviceId.trim();
    final typedAddress = _searchController.text.trim();
    final fallbackOption = _selected;
    final building = _textOr(
      _buildingController.text,
      _textOr(typedAddress, fallbackOption.buildingName),
    );
    final space = _textOr(
      _spaceController.text,
      _textOr(building, sensorId),
    );
    final address = _textOr(typedAddress, fallbackOption.address);
    return SensorLocationDraft(
      sensorId: sensorId,
      sensorName: sensorId,
      spaceName: space,
      facilityType: _inferFacilityType(space),
      buildingName: building,
      address: address,
      latitude: fallbackOption.latitude,
      longitude: fallbackOption.longitude,
      floor: _floorController.text.trim(),
      detailLocation: _detailController.text.trim(),
      installationMemo: _memoController.text.trim(),
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _saveAndClose() async {
    if (_saving) return;
    final draft = _buildDraft();
    setState(() {
      _saving = true;
      _statusMessage = '위치 정보를 저장하는 중입니다.';
    });
    try {
      await _storage.save(draft);
      unawaited(_syncProfileAssetLinksIfSignedIn());
      final saved = await _storage.loadForSensor(draft.sensorId);
      final savedLocations = await _storage.loadAll();
      if (!mounted) return;
      setState(() {
        _savedDraft = saved ?? draft;
        _savedLocations = savedLocations;
        _saving = false;
        _stage = _LocationSettingsStage.overview;
        _statusMessage =
            '${(saved ?? draft).spaceName} 위치가 저장되었습니다. 홈과 알림 대상에 반영됩니다.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${draft.spaceName} 위치를 저장했습니다.')),
      );
      widget.onConfirm?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _statusMessage = '위치 저장에 실패했습니다. 입력값과 저장소 권한을 확인하세요.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('위치 저장 실패: $error')),
      );
    }
  }

  Future<void> _reuseSavedLocation(
    SensorLocationDraft source,
    DeviceBindingConfigV2 binding,
  ) async {
    if (!binding.isBound || _saving) return;
    final copied = source.copyWith(
      sensorId: binding.deviceId,
      sensorName: binding.deviceId,
      updatedAt: DateTime.now(),
    );
    setState(() {
      _saving = true;
      _statusMessage = '${source.spaceName} 위치를 현재 센서에 적용하는 중입니다.';
    });
    try {
      await _storage.save(copied);
      unawaited(_syncProfileAssetLinksIfSignedIn());
      final saved = await _storage.loadForSensor(binding.deviceId);
      final savedLocations = await _storage.loadAll();
      if (!mounted) return;
      setState(() {
        _savedDraft = saved ?? copied;
        _savedLocations = savedLocations;
        _saving = false;
        _stage = _LocationSettingsStage.overview;
        _statusMessage =
            '${copied.spaceName} 위치를 ${binding.deviceId} 센서에 적용했습니다.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${copied.spaceName} 위치를 적용했습니다.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _statusMessage = '저장된 위치 적용에 실패했습니다.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('위치 적용 실패: $error')),
      );
    }
  }

  String _textOr(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  String _inferFacilityType(String value) {
    if (value.contains('어린이')) return '어린이집';
    if (value.contains('학교')) return '학교';
    if (value.contains('병원')) return '병원';
    if (value.contains('공장') || value.contains('산업')) return '산업시설';
    return '실내 공간';
  }

  @override
  Widget build(BuildContext context) {
    final binding = context.watch<DeviceBindingControllerV2>().value;
    final filteredOptions = _filteredLocationOptions;
    final selectedLabel = _textOr(_selected.buildingName, _searchQuery);
    final previewOption =
        filteredOptions.isEmpty ? null : filteredOptions.first;
    return _LegacyPage(
      title: '위치 설정',
      leading: Symbols.arrow_back,
      trailing: Symbols.check,
      onLeadingTap: widget.onBack,
      onTrailingTap: _saveAndClose,
      children: [
        if (_loading)
          const _SoftCard(
            radius: 14,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: CleanColors.primary),
              ),
            ),
          )
        else ...[
          _SoftCard(
            color: Colors.white,
            child: _InfoListTile(
              icon: Symbols.sensors,
              title: binding.isBound ? binding.deviceId : '센서 연결 필요',
              subtitle: binding.isBound
                  ? '이 센서에 저장할 위치를 등록합니다.'
                  : '센서를 먼저 등록하면 센서별 위치가 따로 저장됩니다.',
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: CleanColors.outlineVariant),
            ),
            child: Row(
              children: [
                const Icon(Symbols.search,
                    size: 21, color: CleanColors.outline),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    maxLines: 1,
                    onTap: () => setState(
                      () => _stage = _LocationSettingsStage.search,
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (value) => _searchKakaoLocation(value),
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: '건물명 또는 주소 검색',
                    ),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: CleanColors.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _searchKakaoLocation(),
                  child: Icon(
                    _searchingLocation ? Symbols.sync : Symbols.arrow_forward,
                    size: 21,
                    color: CleanColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _LocationActionPill(
                  icon: Symbols.my_location,
                  label: _locatingCurrentPosition ? '위치 확인 중' : '현재 위치 사용',
                  onTap: _useCurrentPosition,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LocationActionPill(
                  icon: Symbols.search,
                  label: '주소 검색',
                  onTap: () {
                    setState(() => _stage = _LocationSettingsStage.search);
                    unawaited(_searchKakaoLocation());
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_stage == _LocationSettingsStage.search) ...[
            _SoftCard(
              radius: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text(
                        '검색 결과',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        filteredOptions.isEmpty
                            ? '직접 입력'
                            : '${filteredOptions.length}개',
                        style: _tinyMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_locationSearchMessage != null) ...[
                    _InfoListTile(
                      icon: _searchingLocation
                          ? Symbols.sync
                          : Symbols.travel_explore,
                      title: _searchingLocation ? '검색 중' : '카카오 위치 검색',
                      subtitle: _locationSearchMessage!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (filteredOptions.isEmpty && !_hasTypedAddress)
                    const _InfoListTile(
                      icon: Symbols.search_off,
                      title: '검색어를 입력해 주세요',
                      subtitle: '주소나 건물명을 입력하고 검색 버튼을 누르세요.',
                    )
                  else ...[
                    if (previewOption != null) ...[
                      KakaoMapPreview(
                        height: 220,
                        latitude: previewOption.latitude,
                        longitude: previewOption.longitude,
                        label: previewOption.buildingName,
                      ),
                      const SizedBox(height: 12),
                    ],
                    for (var i = 0; i < filteredOptions.length; i++) ...[
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _applyOption(filteredOptions[i]),
                        child: _LocationResultTile(
                          option: filteredOptions[i],
                          selected:
                              _selected.address == filteredOptions[i].address,
                          icon: Symbols.location_on,
                        ),
                      ),
                      if (i != filteredOptions.length - 1)
                        const SizedBox(height: 12),
                    ],
                    if (_hasTypedAddress) ...[
                      if (filteredOptions.isNotEmpty)
                        const SizedBox(height: 12),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _useTypedAddress,
                        child: _LocationResultTile(
                          option: _SavedLocationOption(
                            buildingName: _searchQuery.trim(),
                            address: _searchQuery.trim(),
                            latitude: _selected.latitude,
                            longitude: _selected.longitude,
                          ),
                          selected: _selected.address == _searchQuery.trim(),
                          icon: Symbols.edit_location,
                          helper: '검색 결과를 선택하지 않으면 좌표 없이 저장됩니다.',
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_statusMessage != null) ...[
            _SoftCard(
              color: _saving ? CleanColors.surfaceLow : Colors.white,
              child: _InfoListTile(
                icon: _saving ? Symbols.sync : Symbols.check_circle,
                title: _saving ? '저장 중' : '위치 저장 상태',
                subtitle: _statusMessage!,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_savedDraft != null) ...[
            _SoftCard(
              color: CleanColors.surfaceLow,
              child: _InfoListTile(
                icon: Symbols.home_pin,
                title: _savedDraft!.spaceName,
                subtitle: [
                  _savedDraft!.buildingName,
                  _savedDraft!.floor,
                  _savedDraft!.detailLocation,
                  _savedDraft!.sensorId,
                ].where((value) => value.trim().isNotEmpty).join(' · '),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_stage == _LocationSettingsStage.overview &&
              _savedLocations.isNotEmpty) ...[
            _SoftCard(
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('등록된 센서 위치', style: _cardTitle),
                  const SizedBox(height: 14),
                  for (var i = 0; i < _savedLocations.length; i++) ...[
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: binding.isBound
                          ? () => unawaited(
                                _reuseSavedLocation(
                                  _savedLocations[i],
                                  binding,
                                ),
                              )
                          : null,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _savedLocations[i].sensorId == binding.deviceId
                              ? const Color(0xFFE9F8FB)
                              : CleanColors.surfaceLow,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _InfoListTile(
                              icon: _savedLocations[i].sensorId ==
                                      binding.deviceId
                                  ? Symbols.radio_button_checked
                                  : Symbols.home_pin,
                              title: _savedLocations[i].spaceName,
                              subtitle: [
                                _savedLocations[i].sensorId,
                                _savedLocations[i].buildingName,
                                _savedLocations[i].floor,
                                _savedLocations[i].detailLocation,
                              ]
                                  .where((value) => value.trim().isNotEmpty)
                                  .join(' · '),
                            ),
                            if (_savedLocations[i].sensorId !=
                                binding.deviceId) ...[
                              const SizedBox(height: 10),
                              const Text(
                                '탭하면 현재 센서 위치로 적용',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: CleanColors.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (i != _savedLocations.length - 1)
                      const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_stage == _LocationSettingsStage.overview) ...[
            const _SoftCard(
              color: CleanColors.surfaceLow,
              child: _InfoListTile(
                icon: Symbols.search,
                title: '주소를 검색해 설치 위치를 등록하세요',
                subtitle: '검색 결과에서 장소를 선택하면 지도와 상세 입력 화면으로 이어집니다.',
              ),
            ),
          ],
          if (_stage == _LocationSettingsStage.detail) ...[
            Stack(
              children: [
                _selected.isEmpty
                    ? FakeMap(height: 330, label: selectedLabel)
                    : KakaoMapPreview(
                        height: 330,
                        latitude: _selected.latitude,
                        longitude: _selected.longitude,
                        label: selectedLabel,
                        interactive: true,
                        onCenterChanged: _updateSelectedMapCenter,
                      ),
                if (_selected.isEmpty)
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x2600677D),
                              blurRadius: 22,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Symbols.location_on,
                          size: 48,
                          fill: 1,
                          color: CleanColors.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _SoftCard(
              radius: 14,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _PlugInputBox(
                          label: '공간 이름',
                          controller: _spaceController,
                          hintText: '예: 거실, 교실, 복도',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PlugInputBox(
                          label: '층',
                          controller: _floorController,
                          hintText: '예: 1층',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _PlugInputBox(
                    label: '건물/주소명',
                    controller: _buildingController,
                    hintText: '검색 결과를 선택하면 자동 입력됩니다.',
                  ),
                  const SizedBox(height: 12),
                  _PlugInputBox(
                    label: '상세 위치',
                    controller: _detailController,
                    hintText: '예: 창가 근처, 중앙 벽면',
                  ),
                  const SizedBox(height: 12),
                  _PlugInputBox(
                    label: '설치 메모',
                    controller: _memoController,
                    hintText: '설치 높이, 콘센트 위치 등',
                  ),
                  const SizedBox(height: 14),
                  _InfoListTile(
                    icon: Symbols.map,
                    title: _textOr(_searchController.text, _selected.address),
                    subtitle: _selected.isEmpty
                        ? '위치를 선택하면 좌표가 함께 저장됩니다.'
                        : '지도를 움직이면 중심 좌표가 저장됩니다 · ${_selected.latitude.toStringAsFixed(4)}, ${_selected.longitude.toStringAsFixed(4)}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GradientButton(
              label: _saving ? '저장 중' : '이 위치로 설정',
              icon: Symbols.check,
              onTap: _saveAndClose,
            ),
          ],
        ],
      ],
    );
  }
}

class _SavedLocationOption {
  const _SavedLocationOption({
    required this.buildingName,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String buildingName;
  final String address;
  final double latitude;
  final double longitude;

  bool get isEmpty {
    return buildingName.trim().isEmpty &&
        address.trim().isEmpty &&
        latitude == 0 &&
        longitude == 0;
  }
}

class _LocationResultTile extends StatelessWidget {
  const _LocationResultTile({
    required this.option,
    required this.selected,
    required this.icon,
    this.helper,
  });

  final _SavedLocationOption option;
  final bool selected;
  final IconData icon;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFE8F8FB) : CleanColors.surfaceLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 22, color: CleanColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.buildingName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: CleanColors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  option.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: CleanColors.onVariant,
                  ),
                ),
                if (helper != null) ...[
                  const SizedBox(height: 5),
                  Text(helper!, style: _tinyMuted),
                ],
              ],
            ),
          ),
          Icon(
            selected ? Symbols.check_circle : Symbols.chevron_right,
            size: 19,
            color: selected ? CleanColors.primary : CleanColors.outlineVariant,
          ),
        ],
      ),
    );
  }
}

class _LocationActionPill extends StatelessWidget {
  const _LocationActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1000677D),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: CleanColors.primary),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: CleanColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _emptyLocationOption = _SavedLocationOption(
  buildingName: '',
  address: '',
  latitude: 0,
  longitude: 0,
);

class ComparisonNormalScreen extends StatefulWidget {
  const ComparisonNormalScreen({
    super.key,
    this.onTabSelected,
    this.onConnectSensor,
    this.onLocationSettings,
    this.onProfile,
  });

  final ValueChanged<int>? onTabSelected;
  final VoidCallback? onConnectSensor;
  final VoidCallback? onLocationSettings;
  final VoidCallback? onProfile;

  @override
  State<ComparisonNormalScreen> createState() => _ComparisonNormalScreenState();
}

class _ComparisonNormalScreenState extends State<ComparisonNormalScreen> {
  bool _refreshing = false;
  String? _refreshMessage;

  Future<void> _refreshExternalComparison() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _refreshMessage = '외부 비교 데이터를 갱신하는 중입니다.';
    });

    final controller = context.read<AirQualityController>();
    final firestoreService = context.read<FirestoreSnapshotService>();
    final messenger = ScaffoldMessenger.of(context);
    var updated = false;
    Object? error;
    try {
      final binding = context.read<DeviceBindingControllerV2>().value;
      final location = await _loadLocationForBinding(binding);
      if (location != null &&
          location.latitude != 0 &&
          location.longitude != 0) {
        firestoreService.setExternalLocation(
          latitude: location.latitude,
          longitude: location.longitude,
          city: location.buildingName.isNotEmpty
              ? location.buildingName
              : location.address,
        );
      }
      updated = await controller.refreshExternalComparison();
    } catch (caught) {
      error = caught;
    }
    if (!mounted) return;

    final message = error != null
        ? '외부 비교 데이터 갱신에 실패했습니다. 위치 권한과 네트워크 설정을 확인하세요.'
        : updated
            ? '외부 비교 데이터를 갱신했습니다.'
            : '외부 비교 데이터는 위치 정보와 공식 측정소 연결이 필요합니다.';
    setState(() {
      _refreshing = false;
      _refreshMessage = message;
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AirQualityController>();
    final snapshot = controller.latestSnapshot;
    final comparison = controller.locationComparison;
    if (snapshot == null && comparison == null) {
      return ComparisonEmptyScreen(onConnectSensor: widget.onConnectSensor);
    }
    final pm = comparison?.pm25;
    final temp = comparison?.temperature;
    final hum = comparison?.humidity;
    final updatedAt = comparison?.timestamp ?? snapshot?.timestamp;
    final pmSensor = pm?.sensor ?? snapshot?.pm25;
    final pmStation = pm?.station;
    final pmDelta = pm?.delta ?? _comparisonDelta(pmSensor, pmStation);
    final pmStats = pm?.stats;
    final tempDelta =
        temp?.delta ?? _comparisonDelta(temp?.sensor, temp?.station);
    final humDelta = hum?.delta ?? _comparisonDelta(hum?.sensor, hum?.station);
    final chartPoints = _recentPmDeltaPoints(
      controller,
      station: pmStation,
      fallbackSensor: pmSensor,
    );
    final chartValues =
        chartPoints.map((point) => point.value).toList(growable: false);
    final hasComparison = comparison != null;
    final hasStationPm = pmStation != null;
    final statusText = _refreshing
        ? '갱신 중'
        : hasStationPm
            ? '측정소 연결'
            : '실내 센서 기준';

    return _LegacyPage(
      title: 'CleanAir',
      leading: Symbols.cloud,
      trailing: Symbols.account_circle,
      onProfileTap: widget.onProfile,
      children: [
        if (_refreshing || _refreshMessage != null) ...[
          _SoftCard(
            color: _refreshing ? CleanColors.surfaceLow : Colors.white,
            child: _InfoListTile(
              icon: _refreshing ? Symbols.sync : Symbols.info,
              title: _refreshing ? '외부 데이터 갱신 중' : '외부 데이터 갱신 결과',
              subtitle: _refreshMessage ?? '위치 기준 측정소 데이터를 확인합니다.',
            ),
          ),
          const SizedBox(height: 16),
        ],
        _SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '가장 가까운 측정소',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: CleanColors.secondary,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Symbols.schedule,
                    size: 14,
                    color: CleanColors.outline,
                  ),
                  const SizedBox(width: 4),
                  Text(_formatComparisonTime(updatedAt), style: _tinyMuted),
                ],
              ),
              const SizedBox(height: 16),
              _InfoListTile(
                icon: Symbols.location_on,
                title: comparison?.title ?? '근처 측정소 비교',
                subtitle: comparison?.subtitle ??
                    '위치와 외부 비교 데이터가 연결되면 측정소 값이 함께 표시됩니다.',
              ),
              const SizedBox(height: 14),
              _HeatMapActionButton(
                label: _refreshing ? '새로고침 중' : '측정소 데이터 새로고침',
                icon: Symbols.refresh,
                onTap: _refreshing
                    ? () {}
                    : () => unawaited(_refreshExternalComparison()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _ComparisonHeatMapCard(
          controller: controller,
          snapshot: snapshot,
          comparison: comparison,
          onLocationSettings: widget.onLocationSettings,
          onConnectSensor: widget.onConnectSensor,
        ),
        const SizedBox(height: 16),
        _SoftCard(
          color: CleanColors.surfaceLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PM2.5 초미세먼지',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text('출처: WAQI/AQICN', style: _tinyMuted),
                      ],
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: _StatusPill(text: statusText),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _MiniMetric(
                      label: '실내 센서',
                      value: _formatComparisonValue(pmSensor),
                      unit: pm?.unit ?? 'µg/m³',
                      color: CleanColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MiniMetric(
                      label: '측정소',
                      value: _formatComparisonValue(pmStation),
                      unit: pm?.unit ?? 'µg/m³',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Text(
                    '측정 편차',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: CleanColors.secondary,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _isPositiveDelta(pmDelta)
                        ? Symbols.trending_up
                        : Symbols.trending_down,
                    size: 18,
                    color: _isPositiveDelta(pmDelta)
                        ? CleanColors.error
                        : CleanColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    pmDelta ?? '연결 대기',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _isPositiveDelta(pmDelta)
                          ? CleanColors.error
                          : CleanColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _LineChartPanel(
                values: chartValues,
                points: chartPoints,
                height: 118,
                unit: hasStationPm ? 'µg/m³' : 'µg/m³',
                statusOf: pm25Status,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MiniMetric(
                label: '오차율 (MAPE)',
                value: _formatComparisonValue(pmStats?.mape),
                unit: '%',
                color: CleanColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MiniMetric(
                label: '일치도 (R²)',
                value: _formatComparisonValue(pmStats?.r2),
                color: CleanColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MiniMetric(
                label: 'RMSE',
                value: _formatComparisonValue(pmStats?.rmse),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MiniMetric(
                label: 'CV',
                value: _formatComparisonValue(pmStats?.cv),
                unit: '%',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SoftCard(
          color: CleanColors.surfaceLow,
          child: _InfoListTile(
            icon: Symbols.info,
            title: '표본 수 n=${pmStats?.n ?? 0}',
            subtitle: hasComparison
                ? '실외 데이터는 공공 관측소 기준이며 실내 센서와 시간차가 있을 수 있습니다.'
                : '비교 데이터가 들어오기 전에는 실내 센서값만 보여줍니다.',
          ),
        ),
        const SizedBox(height: 12),
        _ComparisonWeatherCard(
          title: '온도',
          source: '출처: 기상청',
          icon: Symbols.device_thermostat,
          iconColor: CleanColors.tertiary,
          indoor:
              '${_formatComparisonValue(temp?.sensor ?? snapshot?.temperature)}°C',
          station: '${_formatComparisonValue(temp?.station)}°C',
          diff: tempDelta ?? '연결 대기',
          diffUp: _isPositiveDelta(tempDelta),
        ),
        const SizedBox(height: 12),
        _ComparisonWeatherCard(
          title: '습도',
          source: '출처: 기상청',
          icon: Symbols.humidity_percentage,
          iconColor: CleanColors.primaryContainer,
          indoor:
              '${_formatComparisonValue(hum?.sensor ?? snapshot?.humidity)}%',
          station: '${_formatComparisonValue(hum?.station)}%',
          diff: humDelta ?? '연결 대기',
          diffUp: _isPositiveDelta(humDelta),
        ),
        const SizedBox(height: 12),
        const _StatsGuideCard(),
      ],
    );
  }
}

class _ComparisonHeatMapCard extends StatefulWidget {
  const _ComparisonHeatMapCard({
    required this.controller,
    required this.snapshot,
    required this.comparison,
    this.onLocationSettings,
    this.onConnectSensor,
  });

  final AirQualityController controller;
  final AirQualitySnapshot? snapshot;
  final LocationComparisonSnapshot? comparison;
  final VoidCallback? onLocationSettings;
  final VoidCallback? onConnectSensor;

  @override
  State<_ComparisonHeatMapCard> createState() => _ComparisonHeatMapCardState();
}

class _ComparisonHeatMapCardState extends State<_ComparisonHeatMapCard> {
  String? _selectedPointKey;
  _HeatMetric _metric = _HeatMetric.pm25;

  Future<KakaoMapCoordinate?> _requestCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('휴대폰 위치 서비스를 켜면 현재 위치로 이동할 수 있어요.')),
          );
        }
        return null;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('위치 권한을 허용하면 현재 위치로 지도를 이동할 수 있어요.')),
          );
        }
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return KakaoMapCoordinate(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('현재 위치를 확인하지 못했습니다. 잠시 후 다시 시도해 주세요.')),
        );
      }
      return null;
    }
  }

  void _openFullHeatMap(_ComparisonHeatMapData data) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ComparisonHeatMapFullScreen(
          data: data,
          initialMetric: _metric,
          initialSelectedKey: _selectedPointKey,
          onRequestCurrentLocation: _requestCurrentLocation,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ComparisonHeatMapData>(
      future: _buildComparisonHeatMapData(
        controller: widget.controller,
        snapshot: widget.snapshot,
        comparison: widget.comparison,
        binding: context.read<DeviceBindingControllerV2>().value,
        firestoreService: context.read<FirestoreSnapshotService>(),
      ),
      builder: (context, heatSnapshot) {
        final data = heatSnapshot.data;
        final loading = heatSnapshot.connectionState == ConnectionState.waiting;
        if (data == null || data.points.isEmpty) {
          return _SoftCard(
            color: CleanColors.surfaceLow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoListTile(
                  icon: loading ? Symbols.sync : Symbols.map,
                  title: loading ? '주변 공기질 분포 준비 중' : '주변 공기질 분포',
                  subtitle: loading
                      ? '등록 센서와 측정소 좌표를 불러오는 중입니다.'
                      : '센서 위치를 등록하면 주변 측정소와 함께 지도에 표시됩니다.',
                ),
                if (!loading &&
                    (widget.onLocationSettings != null ||
                        widget.onConnectSensor != null)) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (widget.onLocationSettings != null)
                        Expanded(
                          child: _HeatMapActionButton(
                            label: '위치 등록',
                            icon: Symbols.add_location_alt,
                            onTap: widget.onLocationSettings!,
                          ),
                        ),
                      if (widget.onLocationSettings != null &&
                          widget.onConnectSensor != null)
                        const SizedBox(width: 10),
                      if (widget.onConnectSensor != null)
                        Expanded(
                          child: _HeatMapActionButton(
                            label: '센서 연결',
                            icon: Symbols.sensors,
                            onTap: widget.onConnectSensor!,
                            secondary: true,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
        }

        final stationCount =
            data.points.where((point) => point.source == 'station').length;
        final sensorCount =
            data.points.where((point) => point.source == 'sensor').length;
        final updatedLabel = data.updatedAt == null
            ? '최근 측정 기준'
            : '${_formatComparisonTime(data.updatedAt)} 기준';
        final selectedPoint = _selectedHeatPoint(data.points);
        final currentSensor = _firstHeatSensor(data.points);
        final visiblePoints = data.points;
        final metricPoints = visiblePoints
            .where((point) => point.valueFor(_metric) != null)
            .toList(growable: false);
        return _SoftCard(
          color: CleanColors.surfaceLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_metric.label} 분포', style: _cardTitle),
                        const SizedBox(height: 4),
                        Text(updatedLabel, style: _tinyMuted),
                      ],
                    ),
                  ),
                  _StatusPill(text: '${data.points.length}개 지점'),
                ],
              ),
              const SizedBox(height: 14),
              _HeatMetricSelector(
                selected: _metric,
                onSelected: (metric) => setState(() => _metric = metric),
              ),
              const SizedBox(height: 14),
              KakaoMapPreview(
                latitude: data.centerLatitude,
                longitude: data.centerLongitude,
                label: data.centerLabel,
                height: 260,
                onRequestCurrentLocation: _requestCurrentLocation,
                compactControls: true,
                heatPoints: [
                  for (final point in metricPoints)
                    KakaoMapHeatPoint(
                      latitude: point.latitude,
                      longitude: point.longitude,
                      value: point.valueFor(_metric)!,
                      label: point.label,
                      color: _heatMapPointColor(point, _metric, metricPoints),
                      radiusMeters: point.source == 'station' ? 1100 : 720,
                      showValue: true,
                      showLabel: point.source != 'station',
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _HeatMapActionButton(
                label: '지도 크게 보기',
                icon: Symbols.open_in_full,
                onTap: () => _openFullHeatMap(data),
                secondary: true,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Pill(
                    text: '센서 $sensorCount',
                    color: CleanColors.primaryFixed,
                    textColor: CleanColors.primary,
                    icon: Symbols.sensors,
                  ),
                  Pill(
                    text: '측정소 $stationCount',
                    color: Colors.white,
                    textColor: CleanColors.secondary,
                    icon: Symbols.location_on,
                  ),
                  Pill(
                    text: '${_metric.label} 기준 표시',
                    color: Colors.white,
                    textColor: CleanColors.secondary,
                    icon: _metric.icon,
                  ),
                  if (data.coverageLabel.isNotEmpty)
                    Pill(
                      text: data.coverageLabel,
                      color: Colors.white,
                      textColor: CleanColors.secondary,
                      icon: Symbols.radar,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _HeatMetricLegend(metric: _metric),
              const SizedBox(height: 12),
              _HeatPointSelector(
                points: data.points,
                selectedKey: _heatPointKey(selectedPoint),
                metric: _metric,
                onSelected: (point) {
                  setState(() => _selectedPointKey = _heatPointKey(point));
                },
              ),
              const SizedBox(height: 12),
              _SelectedHeatPointCard(
                selected: selectedPoint,
                currentSensor: currentSensor,
                metric: _metric,
              ),
              const SizedBox(height: 10),
              const Text(
                '공식 측정소는 실외 기준입니다. 실내 센서와 측정 시간, 설치 환경이 달라 차이가 날 수 있어요.',
                style: _tinyMuted,
              ),
            ],
          ),
        );
      },
    );
  }

  _ComparisonHeatPoint _selectedHeatPoint(List<_ComparisonHeatPoint> points) {
    final key = _selectedPointKey;
    if (key != null) {
      for (final point in points) {
        if (_heatPointKey(point) == key) return point;
      }
    }
    for (final point in points) {
      if (point.source == 'sensor') return point;
    }
    return points.first;
  }

  _ComparisonHeatPoint? _firstHeatSensor(List<_ComparisonHeatPoint> points) {
    for (final point in points) {
      if (point.source == 'sensor') return point;
    }
    return null;
  }
}

class _ComparisonHeatMapData {
  const _ComparisonHeatMapData({
    required this.centerLatitude,
    required this.centerLongitude,
    required this.centerLabel,
    required this.points,
    required this.coverageLabel,
    this.updatedAt,
  });

  final double centerLatitude;
  final double centerLongitude;
  final String centerLabel;
  final List<_ComparisonHeatPoint> points;
  final String coverageLabel;
  final DateTime? updatedAt;
}

class _ComparisonHeatMapFullScreen extends StatefulWidget {
  const _ComparisonHeatMapFullScreen({
    required this.data,
    required this.initialMetric,
    required this.initialSelectedKey,
    required this.onRequestCurrentLocation,
  });

  final _ComparisonHeatMapData data;
  final _HeatMetric initialMetric;
  final String? initialSelectedKey;
  final Future<KakaoMapCoordinate?> Function() onRequestCurrentLocation;

  @override
  State<_ComparisonHeatMapFullScreen> createState() =>
      _ComparisonHeatMapFullScreenState();
}

class _ComparisonHeatMapFullScreenState
    extends State<_ComparisonHeatMapFullScreen> {
  late _HeatMetric _metric = _HeatMetric.values.contains(widget.initialMetric)
      ? widget.initialMetric
      : _HeatMetric.pm25;
  late String? _selectedPointKey = widget.initialSelectedKey;
  late List<_ComparisonHeatPoint> _points = widget.data.points;
  late final Map<String, _ComparisonHeatPoint> _stationCache = {
    for (final point in widget.data.points)
      if (point.source == 'station') _heatPointKey(point): point,
  };
  late KakaoMapCoordinate _lastMapCenter = KakaoMapCoordinate(
    latitude: widget.data.centerLatitude,
    longitude: widget.data.centerLongitude,
  );
  Timer? _viewportDebounce;
  ({double latitude, double longitude})? _lastLoadedViewportCenter;
  DateTime? _lastViewportStationRefreshAt;
  bool _loadingViewportStations = false;

  @override
  void dispose() {
    _viewportDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;
    final metricPoints = _metricPoints(points, _metric);
    final selected = metricPoints.isEmpty
        ? _selectedHeatPoint(points)
        : _selectedHeatPoint(metricPoints);
    final currentSensor = _firstHeatSensor(points);
    final selectorPoints = _nearbySelectorPoints(
      metricPoints.isEmpty ? points : metricPoints,
      selected,
    );
    return Scaffold(
      backgroundColor: CleanColors.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: CleanColors.surface,
        foregroundColor: CleanColors.onSurface,
        title: Text(
          '${_metric.label} 히트맵',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: _HeatMetricSelector(
                selected: _metric,
                onSelected: (metric) {
                  setState(() => _metric = metric);
                  _scheduleViewportStationLoad(_lastMapCenter);
                },
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: KakaoMapPreview(
                  latitude: selected.latitude,
                  longitude: selected.longitude,
                  label: widget.data.centerLabel,
                  height: double.infinity,
                  onRequestCurrentLocation: widget.onRequestCurrentLocation,
                  onCenterChanged: _scheduleViewportStationLoad,
                  enableMapTapSelection: false,
                  onHeatPointTap: (point) {
                    final matched = _matchHeatPoint(metricPoints, point);
                    if (matched == null) return;
                    setState(() => _selectedPointKey = _heatPointKey(matched));
                  },
                  compactControls: false,
                  heatPoints: [
                    for (final point in metricPoints)
                      KakaoMapHeatPoint(
                        latitude: point.latitude,
                        longitude: point.longitude,
                        value: point.valueFor(_metric)!,
                        label: point.label,
                        color: _heatMapPointColor(point, _metric, metricPoints),
                        radiusMeters: point.source == 'station' ? 980 : 700,
                        showValue: true,
                        showLabel: point.source != 'station',
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HeatPointSelector(
                    points: selectorPoints,
                    selectedKey: _heatPointKey(selected),
                    metric: _metric,
                    onSelected: (point) {
                      setState(() => _selectedPointKey = _heatPointKey(point));
                    },
                  ),
                  if (_loadingViewportStations) ...[
                    const SizedBox(height: 8),
                    const Text('현재 지도 화면의 측정소를 불러오는 중입니다.', style: _tinyMuted),
                  ],
                  const SizedBox(height: 10),
                  _SelectedHeatPointCard(
                    selected: selected,
                    currentSensor: currentSensor,
                    metric: _metric,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _scheduleViewportStationLoad(KakaoMapCoordinate center) {
    _lastMapCenter = center;
    _viewportDebounce?.cancel();
    _viewportDebounce = Timer(
      const Duration(milliseconds: 1000),
      () => unawaited(_loadViewportStations(center)),
    );
  }

  Future<void> _loadViewportStations(KakaoMapCoordinate center) async {
    final previous = _lastLoadedViewportCenter;
    final refreshedAt = _lastViewportStationRefreshAt;
    if (refreshedAt != null &&
        DateTime.now().difference(refreshedAt) < const Duration(minutes: 45)) {
      return;
    }
    if (previous != null &&
        _distanceKm(
              previous.latitude,
              previous.longitude,
              center.latitude,
              center.longitude,
            ) <
            120) {
      return;
    }
    if (!mounted) return;
    setState(() => _loadingViewportStations = true);
    try {
      final service = context.read<FirestoreSnapshotService>();
      final sensors =
          _points.where((point) => point.source == 'sensor').toList();
      final stations = await service.loadKoreaPm25Stations();
      if (!mounted) return;
      final seen = <String>{
        for (final point in sensors)
          '${point.latitude.toStringAsFixed(4)},${point.longitude.toStringAsFixed(4)}',
      };
      for (final station in stations) {
        final key =
            '${station.latitude.toStringAsFixed(4)},${station.longitude.toStringAsFixed(4)}';
        if (!seen.add(key)) continue;
        final point = _stationHeatPoint(station);
        _stationCache[_heatPointKey(point)] = point;
      }
      setState(() {
        _points = [
          ...sensors,
          ..._balancedStationPoints(
            _stationCache.values,
            center.latitude,
            center.longitude,
          ),
        ];
        _lastLoadedViewportCenter = (
          latitude: center.latitude,
          longitude: center.longitude,
        );
        _lastViewportStationRefreshAt = DateTime.now();
        _loadingViewportStations = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingViewportStations = false);
    }
  }

  List<_ComparisonHeatPoint> _metricPoints(
    List<_ComparisonHeatPoint> points,
    _HeatMetric metric,
  ) {
    return points
        .where((point) => point.valueFor(metric) != null)
        .toList(growable: false);
  }

  _ComparisonHeatPoint _selectedHeatPoint(List<_ComparisonHeatPoint> points) {
    final key = _selectedPointKey;
    if (key != null) {
      for (final point in points) {
        if (_heatPointKey(point) == key) return point;
      }
    }
    for (final point in points) {
      if (point.source == 'sensor') return point;
    }
    return points.first;
  }

  _ComparisonHeatPoint? _firstHeatSensor(List<_ComparisonHeatPoint> points) {
    for (final point in points) {
      if (point.source == 'sensor') return point;
    }
    return null;
  }

  List<_ComparisonHeatPoint> _nearbySelectorPoints(
    List<_ComparisonHeatPoint> points,
    _ComparisonHeatPoint selected,
  ) {
    final sorted = points.toList(growable: false)
      ..sort((a, b) {
        final selectedKey = _heatPointKey(selected);
        if (_heatPointKey(a) == selectedKey) return -1;
        if (_heatPointKey(b) == selectedKey) return 1;
        final ad = _distanceKm(
          selected.latitude,
          selected.longitude,
          a.latitude,
          a.longitude,
        );
        final bd = _distanceKm(
          selected.latitude,
          selected.longitude,
          b.latitude,
          b.longitude,
        );
        return ad.compareTo(bd);
      });
    final result = <_ComparisonHeatPoint>[];
    void addUnique(_ComparisonHeatPoint point) {
      final key = _heatPointKey(point);
      if (result.any((item) => _heatPointKey(item) == key)) return;
      result.add(point);
    }

    for (final point in sorted) {
      if (result.length >= 5) break;
      addUnique(point);
    }
    return result;
  }

  _ComparisonHeatPoint? _matchHeatPoint(
    List<_ComparisonHeatPoint> points,
    KakaoMapHeatPoint tapped,
  ) {
    _ComparisonHeatPoint? best;
    var bestDistance = double.infinity;
    for (final point in points) {
      if (point.label != tapped.label) continue;
      final distance = (point.latitude - tapped.latitude).abs() +
          (point.longitude - tapped.longitude).abs();
      if (distance < bestDistance) {
        best = point;
        bestDistance = distance;
      }
    }
    return best;
  }
}

class _HeatMapActionButton extends StatelessWidget {
  const _HeatMapActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.secondary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final background = secondary ? Colors.white : CleanColors.primary;
    final foreground = secondary ? CleanColors.primary : Colors.white;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: secondary
              ? Border.all(color: CleanColors.primary.withValues(alpha: 0.16))
              : null,
          boxShadow: secondary
              ? null
              : [
                  BoxShadow(
                    color: CleanColors.primary.withValues(alpha: 0.18),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeatMetric {
  const _HeatMetric({
    required this.key,
    required this.label,
    required this.unit,
    required this.icon,
    required this.thresholds,
    required this.tickLabels,
  });

  final String key;
  final String label;
  final String unit;
  final IconData icon;
  final List<double> thresholds;
  final List<String> tickLabels;

  static const pm25 = _HeatMetric(
    key: 'pm25',
    label: 'PM2.5',
    unit: 'µg/m³',
    icon: Symbols.blur_on,
    thresholds: <double>[15, 35, 55],
    tickLabels: <String>['0-15', '16-35', '36-55', '56+'],
  );
  static const nox = _HeatMetric(
    key: 'nox',
    label: 'NOx/NO₂',
    unit: 'index',
    icon: Symbols.science,
    thresholds: <double>[1, 2, 3],
    tickLabels: <String>['≤1', '1-2', '2-3', '3+'],
  );
  static const co = _HeatMetric(
    key: 'co',
    label: 'CO',
    unit: 'ppm',
    icon: Symbols.gas_meter,
    thresholds: <double>[5, 10, 35],
    tickLabels: <String>['≤5', '6-10', '11-35', '36+'],
  );
  static const temperature = _HeatMetric(
    key: 'temperature',
    label: '온도',
    unit: '℃',
    icon: Symbols.device_thermostat,
    thresholds: <double>[20, 26, 30],
    tickLabels: <String>['≤20', '21-26', '27-30', '31+'],
  );
  static const humidity = _HeatMetric(
    key: 'humidity',
    label: '습도',
    unit: '%',
    icon: Symbols.humidity_percentage,
    thresholds: <double>[40, 60, 75],
    tickLabels: <String>['≤40', '41-60', '61-75', '76+'],
  );
  static const values = <_HeatMetric>[
    pm25,
    nox,
    co,
  ];
}

class _HeatMetricSelector extends StatelessWidget {
  const _HeatMetricSelector({
    required this.selected,
    required this.onSelected,
  });

  final _HeatMetric selected;
  final ValueChanged<_HeatMetric> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _HeatMetric.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final metric = _HeatMetric.values[index];
          final active = metric.key == selected.key;
          return GestureDetector(
            onTap: () => onSelected(metric),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? CleanColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    metric.icon,
                    size: 17,
                    color: active ? Colors.white : CleanColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    metric.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: active ? Colors.white : CleanColors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeatMetricLegend extends StatelessWidget {
  const _HeatMetricLegend({required this.metric});

  final _HeatMetric metric;

  @override
  Widget build(BuildContext context) {
    final items = [
      (label: '낮음', value: metric.tickLabels[0], color: CleanColors.primary),
      (
        label: '보통',
        value: metric.tickLabels[1],
        color: const Color(0xFFF6C85F)
      ),
      (
        label: '높음',
        value: metric.tickLabels[2],
        color: const Color(0xFFFF8A4C)
      ),
      (label: '매우 높음', value: metric.tickLabels[3], color: CleanColors.error),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '표시 기준',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: CleanColors.onSurface,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${metric.label} · ${metric.unit}',
            style: _tinyMuted,
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              for (final item in items)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 6,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: item.color,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: CleanColors.secondary,
                        ),
                      ),
                      Text(
                        item.value,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: CleanColors.outline,
                        ),
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

class _ComparisonHeatPoint {
  const _ComparisonHeatPoint({
    required this.latitude,
    required this.longitude,
    required this.label,
    required this.source,
    this.pm25,
    this.nox,
    this.co,
    this.temperature,
    this.humidity,
    this.updatedAt,
  });

  final double latitude;
  final double longitude;
  final String label;
  final String source;
  final double? pm25;
  final double? nox;
  final double? co;
  final double? temperature;
  final double? humidity;
  final DateTime? updatedAt;

  double? valueFor(_HeatMetric metric) {
    return switch (metric.key) {
      'pm25' => pm25,
      'nox' => nox,
      'co' => co,
      'temperature' => temperature,
      'humidity' => humidity,
      _ => pm25,
    };
  }
}

String _heatPointKey(_ComparisonHeatPoint point) {
  return '${point.source}:${point.label}:${point.latitude.toStringAsFixed(5)},${point.longitude.toStringAsFixed(5)}';
}

String _heatPointSourceLabel(_ComparisonHeatPoint point) {
  return switch (point.source) {
    'station' => '공식 측정소',
    'weather' => '기상청 격자',
    _ => '등록 센서',
  };
}

class _HeatPointSelector extends StatelessWidget {
  const _HeatPointSelector({
    required this.points,
    required this.selectedKey,
    required this.metric,
    required this.onSelected,
  });

  final List<_ComparisonHeatPoint> points;
  final String selectedKey;
  final _HeatMetric metric;
  final ValueChanged<_ComparisonHeatPoint> onSelected;

  @override
  Widget build(BuildContext context) {
    final sorted = points.toList(growable: false)
      ..sort((a, b) {
        if (a.source != b.source) return a.source == 'sensor' ? -1 : 1;
        return a.label.compareTo(b.label);
      });
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sorted.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final point = sorted[index];
          final selected = _heatPointKey(point) == selectedKey;
          return GestureDetector(
            onTap: () => onSelected(point),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? CleanColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: CleanColors.primary.withValues(alpha: 0.18),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    point.source == 'station'
                        ? Symbols.location_on
                        : Symbols.sensors,
                    size: 17,
                    color: selected ? Colors.white : CleanColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    point.valueFor(metric) == null
                        ? '${point.label} · N/A'
                        : point.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: selected ? Colors.white : CleanColors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SelectedHeatPointCard extends StatelessWidget {
  const _SelectedHeatPointCard({
    required this.selected,
    required this.currentSensor,
    required this.metric,
  });

  final _ComparisonHeatPoint selected;
  final _ComparisonHeatPoint? currentSensor;
  final _HeatMetric metric;

  @override
  Widget build(BuildContext context) {
    final sensor = currentSensor;
    final selectedValue = selected.valueFor(metric);
    final sensorValue = sensor?.valueFor(metric);
    final hasDiff = sensorValue != null &&
        selectedValue != null &&
        sensor != null &&
        _heatPointKey(sensor) != _heatPointKey(selected);
    final diff = hasDiff ? selectedValue - sensorValue : 0.0;
    final diffLabel = diff.abs() < 0.1
        ? '거의 같음'
        : diff > 0
            ? '선택 지점이 ${diff.toStringAsFixed(1)} 높음'
            : '선택 지점이 ${diff.abs().toStringAsFixed(1)} 낮음';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _heatMetricColor(selectedValue, metric)
                      .withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  selected.source == 'station'
                      ? Symbols.location_on
                      : Symbols.sensors,
                  color: _heatMetricColor(selectedValue, metric),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(selected.label, style: _cardTitle),
                    const SizedBox(height: 3),
                    Text(_heatPointSourceLabel(selected), style: _tinyMuted),
                  ],
                ),
              ),
              Text(
                _heatValueLabel(selectedValue),
                style: const TextStyle(
                  fontSize: 22,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: CleanColors.onSurface,
                ),
              ),
              const SizedBox(width: 4),
              Text(metric.unit, style: _tinyMuted),
            ],
          ),
          if (hasDiff) ...[
            const SizedBox(height: 12),
            _MiniCompareRow(
              leftLabel: sensor.label,
              leftValue: sensorValue,
              rightLabel: selected.label,
              rightValue: selectedValue,
              metric: metric,
              caption: diffLabel,
            ),
          ],
          if (selected.updatedAt != null) ...[
            const SizedBox(height: 10),
            Text(
              '${_formatComparisonTime(selected.updatedAt)} 측정',
              style: _tinyMuted,
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniCompareRow extends StatelessWidget {
  const _MiniCompareRow({
    required this.leftLabel,
    required this.leftValue,
    required this.rightLabel,
    required this.rightValue,
    required this.metric,
    required this.caption,
  });

  final String leftLabel;
  final double leftValue;
  final String rightLabel;
  final double rightValue;
  final _HeatMetric metric;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final maxValue = math.max(math.max(leftValue, rightValue), 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CompareBar(
          label: leftLabel,
          value: leftValue,
          maxValue: maxValue,
          metric: metric,
        ),
        const SizedBox(height: 7),
        _CompareBar(
          label: rightLabel,
          value: rightValue,
          maxValue: maxValue,
          metric: metric,
        ),
        const SizedBox(height: 8),
        Text(caption, style: _tinyMuted),
      ],
    );
  }
}

class _CompareBar extends StatelessWidget {
  const _CompareBar({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.metric,
  });

  final String label;
  final double value;
  final double maxValue;
  final _HeatMetric metric;

  @override
  Widget build(BuildContext context) {
    final ratio = (value / maxValue).clamp(0.04, 1.0).toDouble();
    return Row(
      children: [
        SizedBox(
          width: 74,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: CleanColors.secondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: ratio,
              backgroundColor: CleanColors.surfaceLow,
              valueColor: AlwaysStoppedAnimation<Color>(
                  _heatMetricColor(value, metric)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: CleanColors.onSurface,
          ),
        ),
      ],
    );
  }
}

Future<_ComparisonHeatMapData> _buildComparisonHeatMapData({
  required AirQualityController controller,
  required AirQualitySnapshot? snapshot,
  required LocationComparisonSnapshot? comparison,
  required DeviceBindingConfigV2 binding,
  required FirestoreSnapshotService firestoreService,
}) async {
  final locations = await SensorLocationStorage().loadAll();
  final activeLocation = binding.isBound
      ? await SensorLocationStorage().loadForSensor(binding.deviceId)
      : await SensorLocationStorage().load();
  final points = <_ComparisonHeatPoint>[];
  final activePm25 = snapshot?.pm25;
  final activePoint = _heatPointFromSnapshot(
    snapshot,
    latitude: activeLocation?.latitude,
    longitude: activeLocation?.longitude,
    label: activeLocation?.spaceName.isEmpty == false
        ? activeLocation!.spaceName
        : '현재 센서',
    source: 'sensor',
  );

  if (activeLocation != null &&
      activeLocation.latitude != 0 &&
      activeLocation.longitude != 0 &&
      activePoint != null) {
    points.add(activePoint);
  }

  final activeSensorId = binding.deviceId.trim();
  for (final location in locations) {
    if (location.sensorId.trim().isEmpty ||
        location.sensorId.trim() == activeSensorId ||
        location.latitude == 0 ||
        location.longitude == 0) {
      continue;
    }
    final sensorSnapshot =
        await _loadSensorSnapshotForHeatMap(location.sensorId);
    final point = _heatPointFromSnapshot(
      sensorSnapshot,
      latitude: location.latitude,
      longitude: location.longitude,
      label:
          location.spaceName.isEmpty ? location.sensorId : location.spaceName,
      source: 'sensor',
    );
    if (point == null) continue;
    points.add(point);
  }

  final stationPm25 = comparison?.pm25?.station;
  final stationLat = comparison?.stationLatitude;
  final stationLng = comparison?.stationLongitude;
  if (stationPm25 != null &&
      stationPm25.isFinite &&
      stationLat != null &&
      stationLng != null &&
      stationLat != 0 &&
      stationLng != 0) {
    points.add(
      _ComparisonHeatPoint(
        latitude: stationLat,
        longitude: stationLng,
        pm25: stationPm25,
        temperature: comparison?.temperature?.station,
        humidity: comparison?.humidity?.station,
        label: comparison?.title ?? '측정소',
        source: 'station',
        updatedAt: comparison?.timestamp,
      ),
    );
  }

  final heatCenter = _heatMapCenter(
    points,
    fallbackLatitude: activeLocation?.latitude ?? stationLat ?? 37.5665,
    fallbackLongitude: activeLocation?.longitude ?? stationLng ?? 126.9780,
  );
  final nearbyStations = await firestoreService.loadKoreaPm25Stations();
  final seenStations = <String>{
    for (final point in points)
      if (point.source == 'station')
        '${point.latitude.toStringAsFixed(4)},${point.longitude.toStringAsFixed(4)}',
  };
  for (final station in nearbyStations) {
    final key =
        '${station.latitude.toStringAsFixed(4)},${station.longitude.toStringAsFixed(4)}';
    if (!seenStations.add(key)) continue;
    points.add(_stationHeatPoint(station));
  }
  final stationPoints = points
      .where((point) => point.source == 'station')
      .toList(growable: false);
  points
    ..removeWhere((point) => point.source == 'station')
    ..addAll(
      _balancedStationPoints(
        stationPoints,
        heatCenter.latitude,
        heatCenter.longitude,
      ),
    );

  final center = points.isNotEmpty
      ? _heatMapCenterPoint(points)
      : _ComparisonHeatPoint(
          latitude: activeLocation?.latitude ?? stationLat ?? 37.5665,
          longitude: activeLocation?.longitude ?? stationLng ?? 126.9780,
          pm25: activePm25 ?? stationPm25 ?? 0,
          nox: snapshot?.nox,
          temperature: snapshot?.temperature,
          humidity: snapshot?.humidity,
          label: '지도 중심',
          source: 'center',
        );
  return _ComparisonHeatMapData(
    centerLatitude: center.latitude,
    centerLongitude: center.longitude,
    centerLabel: center.label,
    points: points,
    coverageLabel: _heatCoverageLabel(points),
    updatedAt: _latestHeatPointTime(points),
  );
}

_ComparisonHeatPoint _stationHeatPoint(NearbyPm25Station station) {
  return _ComparisonHeatPoint(
    latitude: station.latitude,
    longitude: station.longitude,
    pm25: station.pm25,
    nox: station.no2,
    co: station.co,
    label: _shortStationName(station.name),
    source: 'station',
    updatedAt: station.observedAt,
  );
}

List<_ComparisonHeatPoint> _balancedStationPoints(
  Iterable<_ComparisonHeatPoint> stations,
  double centerLatitude,
  double centerLongitude,
) {
  const maxVisibleStations = 1200;
  final source = stations
      .where((point) =>
          point.pm25 != null || point.nox != null || point.co != null)
      .toList(growable: false)
    ..sort((a, b) {
      final da = _distanceKm(
        centerLatitude,
        centerLongitude,
        a.latitude,
        a.longitude,
      );
      final db = _distanceKm(
        centerLatitude,
        centerLongitude,
        b.latitude,
        b.longitude,
      );
      return da.compareTo(db);
    });
  if (source.length <= maxVisibleStations) return source;

  final selected = <_ComparisonHeatPoint>[];
  final buckets = <String, List<_ComparisonHeatPoint>>{};
  for (final point in source) {
    final latBucket = (point.latitude * 2).floor();
    final lonBucket = (point.longitude * 2).floor();
    buckets.putIfAbsent('$latBucket:$lonBucket', () => []).add(point);
  }
  final bucketEntries = buckets.entries.toList(growable: false)
    ..sort((a, b) => a.key.compareTo(b.key));
  var round = 0;
  while (selected.length < maxVisibleStations) {
    var added = false;
    for (final entry in bucketEntries) {
      if (entry.value.length <= round) continue;
      selected.add(entry.value[round]);
      added = true;
      if (selected.length >= maxVisibleStations) break;
    }
    if (!added) break;
    round += 1;
  }
  return selected;
}

_ComparisonHeatPoint? _heatPointFromSnapshot(
  AirQualitySnapshot? snapshot, {
  required double? latitude,
  required double? longitude,
  required String label,
  required String source,
}) {
  if (snapshot == null ||
      latitude == null ||
      longitude == null ||
      latitude == 0 ||
      longitude == 0) {
    return null;
  }
  final point = _ComparisonHeatPoint(
    latitude: latitude,
    longitude: longitude,
    pm25: _finiteHeatValue(snapshot.pm25),
    nox: _finiteHeatValue(snapshot.nox),
    co: _finiteHeatValue(snapshot.co),
    temperature: _finiteHeatValue(snapshot.temperature),
    humidity: _finiteHeatValue(snapshot.humidity),
    label: label.trim().isEmpty ? '등록 센서' : label.trim(),
    source: source,
    updatedAt: snapshot.timestamp,
  );
  for (final metric in _HeatMetric.values) {
    if (point.valueFor(metric) != null) return point;
  }
  return null;
}

double? _finiteHeatValue(double? value) {
  if (value == null || !value.isFinite || value.isNaN) return null;
  return value;
}

double? _avgHeatMetric(
  List<_ComparisonHeatPoint> points,
  _HeatMetric metric,
) {
  final values = points
      .map((point) => point.valueFor(metric))
      .whereType<double>()
      .toList(growable: false);
  if (values.isEmpty) return null;
  return values.reduce((a, b) => a + b) / values.length;
}

({double latitude, double longitude}) _heatMapCenter(
  List<_ComparisonHeatPoint> points, {
  required double fallbackLatitude,
  required double fallbackLongitude,
}) {
  if (points.isEmpty) {
    return (latitude: fallbackLatitude, longitude: fallbackLongitude);
  }
  final lat = points.map((point) => point.latitude).reduce((a, b) => a + b) /
      points.length;
  final lng = points.map((point) => point.longitude).reduce((a, b) => a + b) /
      points.length;
  return (latitude: lat, longitude: lng);
}

_ComparisonHeatPoint _heatMapCenterPoint(List<_ComparisonHeatPoint> points) {
  final center = _heatMapCenter(
    points,
    fallbackLatitude: points.first.latitude,
    fallbackLongitude: points.first.longitude,
  );
  return _ComparisonHeatPoint(
    latitude: center.latitude,
    longitude: center.longitude,
    pm25: _avgHeatMetric(points, _HeatMetric.pm25),
    nox: _avgHeatMetric(points, _HeatMetric.nox),
    co: _avgHeatMetric(points, _HeatMetric.co),
    temperature: _avgHeatMetric(points, _HeatMetric.temperature),
    humidity: _avgHeatMetric(points, _HeatMetric.humidity),
    label: '공기질 분포',
    source: 'center',
    updatedAt: _latestHeatPointTime(points),
  );
}

double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
  const earthKm = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return earthKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

String _heatCoverageLabel(List<_ComparisonHeatPoint> points) {
  if (points.length < 2) return '';
  final center = _heatMapCenter(
    points,
    fallbackLatitude: points.first.latitude,
    fallbackLongitude: points.first.longitude,
  );
  final farthest = points
      .map((point) => _distanceKm(
            center.latitude,
            center.longitude,
            point.latitude,
            point.longitude,
          ))
      .fold<double>(0, (maxValue, value) => math.max(maxValue, value));
  return '반경 약 ${farthest.clamp(1, 450).toStringAsFixed(0)}km';
}

DateTime? _latestHeatPointTime(List<_ComparisonHeatPoint> points) {
  DateTime? latest;
  for (final point in points) {
    final time = point.updatedAt;
    if (time == null) continue;
    if (latest == null || time.isAfter(latest)) latest = time;
  }
  return latest;
}

String _shortStationName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '측정소';
  return trimmed
      .replaceAll('대한민국', '')
      .replaceAll('South Korea', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Future<AirQualitySnapshot?> _loadSensorSnapshotForHeatMap(
  String sensorId,
) async {
  final candidates = AirGradientMdnsService.sensorIdCandidates(sensorId);
  for (final candidate in candidates) {
    final snapshot = await FirebaseFirestore.instance
        .collection('sensors')
        .doc(candidate)
        .get();
    if (!snapshot.exists) continue;
    final data = snapshot.data();
    if (data == null) continue;
    return AirQualitySnapshot.fromJson({
      ...data,
      'id': snapshot.id,
    });
  }
  return null;
}

Color _pm25HeatColor(double value) {
  if (value <= 15) return CleanColors.primary;
  if (value <= 35) return const Color(0xFFF6C85F);
  if (value <= 55) return const Color(0xFFFF8A4C);
  return CleanColors.error;
}

Color _heatMetricColor(double? value, _HeatMetric metric) {
  if (value == null || !value.isFinite || value.isNaN) {
    return CleanColors.outline;
  }
  if (metric.key == 'pm25') return _pm25HeatColor(value);
  final thresholds = metric.thresholds;
  if (value <= thresholds[0]) return CleanColors.primary;
  if (value <= thresholds[1]) return const Color(0xFFF6C85F);
  if (value <= thresholds[2]) return const Color(0xFFFF8A4C);
  return CleanColors.error;
}

Color _heatTemperatureColor(double? value, _HeatMetric metric) {
  if (value == null || !value.isFinite || value.isNaN) {
    return CleanColors.outline;
  }
  final range = _heatTemperatureRange(metric);
  return _heatTemperatureColorInRange(value, range.min, range.max);
}

Color _heatMapPointColor(
  _ComparisonHeatPoint point,
  _HeatMetric metric,
  List<_ComparisonHeatPoint> visiblePoints,
) {
  final value = point.valueFor(metric);
  if (value == null || !value.isFinite || value.isNaN) {
    return CleanColors.outline;
  }
  if (metric.key != 'nox' && metric.key != 'co') {
    return _heatTemperatureColor(value, metric);
  }
  final values = visiblePoints
      .map((candidate) => candidate.valueFor(metric))
      .whereType<double>()
      .where((candidate) => candidate.isFinite && !candidate.isNaN)
      .toList(growable: false);
  if (values.length < 3) return _heatTemperatureColor(value, metric);
  var minValue = values.first;
  var maxValue = values.first;
  for (final candidate in values.skip(1)) {
    minValue = math.min(minValue, candidate);
    maxValue = math.max(maxValue, candidate);
  }
  final spread = maxValue - minValue;
  if (spread <= 0.001) return _heatTemperatureColor(value, metric);
  final padding = spread * 0.18;
  return _heatTemperatureColorInRange(
    value,
    minValue - padding,
    maxValue + padding,
  );
}

Color _heatTemperatureColorInRange(double value, double min, double max) {
  final safeMax = max <= min ? min + 1 : max;
  final ratio = ((value - min) / (safeMax - min)).clamp(0.0, 1.0);
  const stops = <({double t, Color color})>[
    (t: 0.00, color: Color(0xFF1E88E5)),
    (t: 0.22, color: Color(0xFF00ACC1)),
    (t: 0.42, color: Color(0xFF22C55E)),
    (t: 0.58, color: Color(0xFFF4D03F)),
    (t: 0.76, color: Color(0xFFFF8A2A)),
    (t: 1.00, color: Color(0xFFD71920)),
  ];
  for (var i = 0; i < stops.length - 1; i += 1) {
    final a = stops[i];
    final b = stops[i + 1];
    if (ratio <= b.t) {
      final local = ((ratio - a.t) / (b.t - a.t)).clamp(0.0, 1.0);
      return Color.lerp(a.color, b.color, local) ?? b.color;
    }
  }
  return stops.last.color;
}

({double min, double max}) _heatTemperatureRange(_HeatMetric metric) {
  final thresholds = metric.thresholds;
  return switch (metric.key) {
    'pm25' => (min: 0, max: 90),
    'nox' => (min: 0, max: 100),
    'co' => (min: 0, max: 20),
    'temperature' => (min: 12, max: 36),
    'humidity' => (min: 20, max: 90),
    _ => (min: 0, max: math.max(1, thresholds[2])),
  };
}

String _heatValueLabel(double? value) {
  if (value == null || !value.isFinite || value.isNaN) return 'N/A';
  if (value.abs() >= 100 || value == value.roundToDouble()) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}

String _formatComparisonValue(double? value) {
  if (value == null || !value.isFinite) return '-';
  if (value.abs() >= 100 || value == value.roundToDouble()) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}

List<_ChartPoint> _recentPmDeltaPoints(
  AirQualityController controller, {
  double? station,
  double? fallbackSensor,
}) {
  final points = controller.rawHistory
      .map((snapshot) {
        final sensor = snapshot.pm25;
        if (sensor == null || !sensor.isFinite) return null;
        return (
          time: snapshot.timestamp,
          value: station == null ? sensor : sensor - station,
        );
      })
      .whereType<_ChartPoint>()
      .toList(growable: false);
  if (points.length > 24) {
    return points.sublist(points.length - 24);
  }
  if (points.isNotEmpty) return points;
  if (fallbackSensor != null && fallbackSensor.isFinite) {
    return <_ChartPoint>[
      (
        time: DateTime.now(),
        value: station == null ? fallbackSensor : fallbackSensor - station,
      ),
    ];
  }
  return const <_ChartPoint>[];
}

String? _comparisonDelta(double? sensor, double? station) {
  if (sensor == null || station == null) return null;
  final delta = sensor - station;
  final sign = delta >= 0 ? '+' : '';
  return '$sign${_formatComparisonValue(delta)}';
}

bool _isPositiveDelta(String? delta) {
  if (delta == null) return false;
  return delta.trim().startsWith('+');
}

String _formatComparisonTime(DateTime? time) {
  if (time == null) return '연결 기준 표시';
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')} 업데이트';
}

class _ComparisonWeatherCard extends StatelessWidget {
  const _ComparisonWeatherCard({
    required this.title,
    required this.source,
    required this.icon,
    required this.iconColor,
    required this.indoor,
    required this.station,
    required this.diff,
    required this.diffUp,
  });

  final String title;
  final String source;
  final IconData icon;
  final Color iconColor;
  final String indoor;
  final String station;
  final String diff;
  final bool diffUp;

  @override
  Widget build(BuildContext context) {
    final diffColor = diffUp ? CleanColors.error : CleanColors.primary;
    return _SoftCard(
      radius: 14,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: _cardTitle),
                    const SizedBox(height: 3),
                    Text(source, style: _tinyMuted),
                  ],
                ),
              ),
              Icon(icon, color: iconColor, size: 24),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _ComparisonValueBlock(label: '실내', value: indoor),
              ),
              Container(width: 1, height: 36, color: CleanColors.surfaceHigh),
              Expanded(
                child: _ComparisonValueBlock(
                  label: '측정소',
                  value: station,
                  muted: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: diffColor.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Text(
                  '편차',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Icon(
                  diffUp ? Symbols.arrow_upward : Symbols.arrow_downward,
                  color: diffColor,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  diff,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: diffColor,
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

class _ComparisonValueBlock extends StatelessWidget {
  const _ComparisonValueBlock({
    required this.label,
    required this.value,
    this.muted = false,
  });

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: _tinyMuted),
        const SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: muted ? CleanColors.secondary : CleanColors.onSurface,
          ),
        ),
      ],
    );
  }
}

class _StatsGuideCard extends StatelessWidget {
  const _StatsGuideCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF171C1F),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.info, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                '통계 설명 가이드',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          SizedBox(height: 18),
          Text(
            '지표 정의',
            style: TextStyle(
              color: CleanColors.primaryFixed,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 10),
          _GuideLine(
            title: 'R² (결정계수)',
            body: '두 데이터의 경향성 일치도. 1에 가까울수록 흐름이 정확히 일치함.',
          ),
          SizedBox(height: 10),
          _GuideLine(
            title: 'RMSE (평균 제곱근 오차)',
            body: '추정 값과 실제 값의 차이의 평균. 낮을수록 정확함.',
          ),
          SizedBox(height: 10),
          _GuideLine(
            title: 'MAPE (평균 절대 백분율 오차)',
            body: '상대적인 오차 비율. 낮을수록 정밀함.',
          ),
          SizedBox(height: 18),
          _GuideScale(),
          SizedBox(height: 18),
          _GuideSourceRow(left: 'PM2.5', right: 'WAQI/AQICN'),
          _GuideSourceRow(left: '온도 / 습도', right: '기상청'),
          _GuideSourceRow(left: 'CO₂/TVOC/NOx', right: '비교 데이터 미제공'),
        ],
      ),
    );
  }
}

class _GuideLine extends StatelessWidget {
  const _GuideLine({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          body,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.68),
            fontSize: 11,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _GuideScale extends StatelessWidget {
  const _GuideScale();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        children: [
          _GuideSourceRow(left: '0.9 이상', right: '매우 높음'),
          Divider(color: Colors.white24),
          _GuideSourceRow(left: '0.7 ~ 0.9', right: '높음'),
          Divider(color: Colors.white24),
          _GuideSourceRow(left: '0.5 미만', right: '낮음'),
        ],
      ),
    );
  }
}

class _GuideSourceRow extends StatelessWidget {
  const _GuideSourceRow({required this.left, required this.right});

  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              left,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            right,
            style: const TextStyle(
              color: CleanColors.primaryFixed,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class ComparisonEmptyScreen extends StatelessWidget {
  const ComparisonEmptyScreen({super.key, this.onConnectSensor});

  final VoidCallback? onConnectSensor;

  @override
  Widget build(BuildContext context) {
    return _LegacyPage(
      title: 'CleanAir',
      leading: Symbols.cloud,
      trailing: Symbols.account_circle,
      children: [
        const SizedBox(height: 92),
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 148,
                height: 148,
                decoration: const BoxDecoration(
                  color: CleanColors.surfaceLow,
                  shape: BoxShape.circle,
                ),
              ),
              const Icon(
                Symbols.cloud_off,
                size: 74,
                color: CleanColors.outlineVariant,
              ),
              const Positioned(
                right: 22,
                top: 24,
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: CleanColors.errorContainer,
                  child: Icon(Symbols.priority_high, color: CleanColors.error),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          '측정 데이터가 없습니다',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 14),
        const Text(
          '센서를 연결하거나 위치를 등록하면 비교 데이터를 확인할 수 있습니다.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.55,
            color: CleanColors.secondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 24),
        GradientButton(
          label: '센서 연결하기',
          icon: Symbols.settings_input_component,
          onTap: onConnectSensor,
        ),
        const SizedBox(height: 24),
        const _SoftCard(
          color: CleanColors.surfaceLow,
          child: _InfoListTile(
            icon: Symbols.info,
            title: '센서 오프라인 안내',
            subtitle: '와이파이 연결 상태를 확인하거나 전원 케이블이 올바르게 연결되었는지 확인해 보세요.',
          ),
        ),
      ],
    );
  }
}

class ComparisonLoadingScreen extends StatelessWidget {
  const ComparisonLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegacyPage(
      title: 'CleanAir',
      leading: Symbols.cloud,
      trailing: Symbols.account_circle,
      children: [
        const SizedBox(height: 110),
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  color: CleanColors.primaryFixed.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
              ),
              const Icon(
                Symbols.air,
                size: 78,
                color: CleanColors.primaryContainer,
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          '외부 데이터를\n불러오는 중',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 25,
            height: 1.2,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          '비교 탭에서는 전국의 대기질 상태를 한눈에 볼 수 있습니다.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            fontWeight: FontWeight.w600,
            color: CleanColors.secondary,
          ),
        ),
        const SizedBox(height: 30),
        const _SoftCard(
          color: CleanColors.primaryFixed,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TIP',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w900,
                  color: CleanColors.secondary,
                ),
              ),
              SizedBox(height: 6),
              Text(
                '비교 탭에서는 전국의 대기질 상태를 한눈에 볼 수 있습니다.',
                style: TextStyle(fontSize: 14, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SmartPlugSettingsScreen extends StatefulWidget {
  const SmartPlugSettingsScreen({
    super.key,
    this.onRegisterPlug,
    this.onAdvancedControl,
    this.onProfile,
  });

  final VoidCallback? onRegisterPlug;
  final VoidCallback? onAdvancedControl;
  final VoidCallback? onProfile;

  @override
  State<SmartPlugSettingsScreen> createState() =>
      _SmartPlugSettingsScreenState();
}

class _SmartPlugSettingsScreenState extends State<SmartPlugSettingsScreen> {
  final _storage = DisasterDeviceStorage();
  final _historyCsvExportService = PlugControlHistoryCsvExportService();
  final _locationStorage = SensorLocationStorage();
  final _testController = DisasterDeviceTestController();
  final _deviceIdController = TextEditingController();
  final _ipController = TextEditingController();
  final _nameController = TextEditingController();
  final _topicController = TextEditingController();
  final _spaceController = TextEditingController();
  final _addressController = TextEditingController();
  final _purposeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _autoThresholdController = TextEditingController();
  final _autoOffThresholdController = TextEditingController();
  final _autoHysteresisController = TextEditingController();
  final _autoHoldController = TextEditingController();

  DisasterDeviceDraft? _draft;
  List<DisasterDeviceDraft> _drafts = const <DisasterDeviceDraft>[];
  List<DisasterDeviceHistoryEntry> _history =
      const <DisasterDeviceHistoryEntry>[];
  int _selectedDeviceIndex = 0;
  bool _loading = true;
  bool _busy = false;
  bool _editingPlug = false;
  bool _showPlugDetail = false;
  bool _editingList = false;
  bool _showHistoryDetail = false;
  bool _historyCsvBusy = false;
  String? _historyDeviceId;
  _PlugHistoryRange _historyRange = _PlugHistoryRange.week;
  String _autoMetric = 'iaqi';
  Map<String, DisasterAutoRule> _autoRules = const <String, DisasterAutoRule>{};
  bool? _powerOn;
  String? _statusMessage;
  String? _settingsUrlMessage;
  String? _autoPolicyMessage;
  String _controlMethod = '로컬 IP 제어';
  AirQualityController? _airQualityController;
  bool _localAutoControlRunning = false;
  final List<_PlugActivityEntry> _activities = <_PlugActivityEntry>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDraft());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<AirQualityController>();
    if (_airQualityController == controller) return;
    _airQualityController?.removeListener(_onAirQualityChanged);
    _airQualityController = controller;
    _airQualityController?.addListener(_onAirQualityChanged);
  }

  @override
  void dispose() {
    _airQualityController?.removeListener(_onAirQualityChanged);
    _deviceIdController.dispose();
    _ipController.dispose();
    _nameController.dispose();
    _topicController.dispose();
    _spaceController.dispose();
    _addressController.dispose();
    _purposeController.dispose();
    _descriptionController.dispose();
    _autoThresholdController.dispose();
    _autoOffThresholdController.dispose();
    _autoHysteresisController.dispose();
    _autoHoldController.dispose();
    super.dispose();
  }

  void _onAirQualityChanged() {
    if (mounted) {
      setState(() {});
    }
    unawaited(_runLocalAutoControlIfNeeded());
  }

  Future<void> _loadDraft() async {
    final binding = context.read<DeviceBindingControllerV2>().value;
    final storedDrafts = await _storage.loadAll();
    final location = await _locationStorage.loadForSensor(binding.deviceId);
    final history = await _storage.loadHistory(limit: 200);
    if (!mounted) return;
    final drafts = storedDrafts.map((draft) {
      if (location == null) return draft;
      return draft.copyWith(
        linkedSpaceName: draft.linkedSpaceName.trim().isEmpty
            ? location.spaceName
            : draft.linkedSpaceName,
        linkedAddress: draft.linkedAddress.trim().isEmpty
            ? location.address
            : draft.linkedAddress,
      );
    }).toList(growable: true);
    if (drafts.isEmpty) {
      setState(() {
        _drafts = const <DisasterDeviceDraft>[];
        _selectedDeviceIndex = 0;
        _draft = null;
        _history = history;
        _statusMessage = '등록된 플러그가 없습니다.';
        _powerOn = null;
        _loading = false;
        _editingPlug = false;
        _showPlugDetail = false;
        _editingList = false;
      });
      return;
    }

    final index = _selectedDeviceIndex.clamp(0, drafts.length - 1).toInt();
    final draft = drafts[index];
    _applyDraftToFields(draft);
    setState(() {
      _drafts = drafts;
      _selectedDeviceIndex = index;
      _draft = draft;
      _history = history;
      _statusMessage = draft.lastTestStatus;
      _powerOn = draft.currentPowerOn;
      _loading = false;
      _editingPlug = false;
      _showPlugDetail = false;
    });
    unawaited(_runLocalAutoControlIfNeeded());
  }

  DisasterDeviceDraft _defaultDraft({SensorLocationDraft? location}) {
    final binding = context.read<DeviceBindingControllerV2>().value;
    final snapshot = context.read<AirQualityController>().latestSnapshot;
    final sensorId = binding.deviceId.trim();
    return DisasterDeviceDraft.empty(
      linkedSensorId: sensorId,
      linkedSpaceName:
          location?.spaceName ?? (sensorId.isEmpty ? '등록된 공간' : '센서 $sensorId'),
      linkedAddress: location?.address ?? snapshot?.location?.source,
    );
  }

  void _applyDraftToFields(DisasterDeviceDraft draft) {
    _deviceIdController.text = draft.deviceId;
    _ipController.text = draft.plugIp;
    _nameController.text = draft.displayName;
    _topicController.text = draft.mqttTopic;
    _spaceController.text = draft.linkedSpaceName;
    _addressController.text = draft.linkedAddress;
    _purposeController.text = draft.purpose;
    _descriptionController.text = draft.description;
    _controlMethod =
        draft.controlMethod.trim().isEmpty ? '로컬 IP 제어' : draft.controlMethod;
    _autoRules = _rulesFromDraft(draft);
    _autoMetric = draft.autoMetric.trim().isEmpty
        ? _autoRules.keys.first
        : _normalizeAutoMetric(draft.autoMetric);
    if (!_autoRules.containsKey(_autoMetric)) {
      _autoMetric = _autoRules.keys.first;
    }
    final rule = _autoRules[_autoMetric] ?? _defaultAutoRule(_autoMetric);
    _autoThresholdController.text = _formatAutoNumber(rule.onThreshold);
    _autoHysteresisController.text = _formatAutoNumber(rule.hysteresisPercent);
    _autoOffThresholdController.text = _formatAutoNumber(rule.offThreshold);
    _autoHoldController.text = draft.autoHoldMinutes.toString();
  }

  void _selectDevice(int index, {bool openDetail = false}) {
    if (index < 0 || index >= _drafts.length) return;
    final draft = _drafts[index];
    _applyDraftToFields(draft);
    setState(() {
      _selectedDeviceIndex = index;
      _draft = draft;
      _powerOn = draft.currentPowerOn;
      _statusMessage = draft.lastTestStatus;
      _editingPlug = false;
      _showPlugDetail = openDetail;
    });
  }

  Future<void> _startNewPlug() async {
    if (_busy) return;
    final nextNumber = _nextPlugNumber();
    final nextTopic = _mqttTopicForNumber(nextNumber);
    final draft = _defaultDraft().copyWith(
      deviceId: _plugIdForNumber(nextNumber),
      displayName: '스마트 플러그 $nextNumber',
      plugIp: '',
      mqttTopic: nextTopic,
      controlMethod: 'MQTT 제어',
      lastTestStatus: '플러그 정보를 입력해 주세요.',
      linkedSpaceName: '',
      linkedAddress: '',
      purpose: '',
      description: '',
      updatedAt: DateTime.now(),
    );
    _applyDraftToFields(draft);
    final nextDrafts = <DisasterDeviceDraft>[..._drafts, draft];
    setState(() {
      _drafts = nextDrafts;
      _selectedDeviceIndex = _drafts.length - 1;
      _draft = draft;
      _powerOn = null;
      _editingPlug = true;
      _showPlugDetail = true;
      _statusMessage = '새 플러그를 추가했습니다.';
    });
    try {
      await _storage.saveAll(nextDrafts);
    } catch (error) {
      if (mounted) _showSnack('플러그 임시 저장 실패: $error');
    }
  }

  int _nextPlugNumber() {
    var number = 1;
    final ids = _drafts
        .map((draft) => draft.deviceId.trim().toLowerCase())
        .where((id) => id.isNotEmpty)
        .toSet();
    final names = _drafts
        .map((draft) => _normalizePlugName(draft.displayName))
        .where((name) => name.isNotEmpty)
        .toSet();
    final topics = _drafts
        .map((draft) => _normalizeMqttTopic(draft.mqttTopic).toLowerCase())
        .where((topic) => topic.isNotEmpty)
        .toSet();
    while (ids.contains('disaster-device-$number') ||
        ids.contains(_plugIdForNumber(number)) ||
        names.contains(_normalizePlugName('스마트 플러그 $number')) ||
        topics.contains(_mqttTopicForNumber(number))) {
      number += 1;
    }
    return number;
  }

  String _plugIdForNumber(int number) =>
      'cleanair-plug-${number.toString().padLeft(2, '0')}';

  String _mqttTopicForNumber(int number) =>
      'cleanair_plug_${number.toString().padLeft(2, '0')}';

  String _mqttTopicForDraft(DisasterDeviceDraft draft) {
    final topic = _normalizeMqttTopic(draft.mqttTopic);
    if (topic.isNotEmpty) return topic;
    final id = draft.deviceId.trim();
    if (id.startsWith('cleanair-plug-')) return id.replaceAll('-', '_');
    final sanitized = id.replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_');
    if (sanitized.isNotEmpty) return sanitized;
    return _mqttTopicForNumber(_nextPlugNumber());
  }

  List<DisasterDeviceDraft> _replaceSelectedDraft(DisasterDeviceDraft draft) {
    final drafts = _drafts.isEmpty
        ? <DisasterDeviceDraft>[draft]
        : _drafts.toList(growable: true);
    final index = _selectedDeviceIndex.clamp(0, drafts.length - 1).toInt();
    drafts[index] = draft;
    return drafts;
  }

  Future<void> _appendHistory({
    required DisasterDeviceDraft draft,
    required String action,
    required String status,
    required bool ok,
    bool? powerOn,
    required String message,
    String requestLog = '',
    String responseLog = '',
  }) async {
    await _storage.appendHistory(
      DisasterDeviceHistoryEntry(
        deviceId: draft.deviceId,
        displayName: draft.displayName,
        action: action,
        status: status,
        ok: ok,
        powerOn: powerOn,
        message: message,
        requestLog: requestLog,
        responseLog: responseLog,
        createdAt: DateTime.now(),
      ),
    );
    _history = await _storage.loadHistory(limit: 200);
  }

  Future<void> _notifyPlugControl({
    required DisasterDeviceDraft draft,
    required String action,
    required bool ok,
    bool? powerOn,
    required String message,
  }) async {
    final prefs = context.read<NotificationPreferencesController>().value;
    if (!prefs.alertsEnabled || (prefs.mutedTypes['plug_control'] ?? false)) {
      return;
    }
    final location = draft.linkedSpaceName.trim();
    final target = location.isEmpty
        ? draft.displayName
        : '$location · ${draft.displayName}';
    final powerText = powerOn == null
        ? action
        : powerOn
            ? 'ON'
            : 'OFF';
    await AlertNotificationPresenter.showAlert(
      ok ? '플러그 제어 완료' : '플러그 제어 실패',
      '$target · $powerText\n$message',
    );
  }

  String _plugControlRequestLog(
    DisasterDeviceDraft draft, {
    required String command,
  }) {
    final ip = draft.plugIp.trim();
    final commandText = switch (command.toUpperCase()) {
      'ON' => 'Power On',
      'OFF' => 'Power Off',
      'STATE' => 'Power',
      _ => command,
    };
    if (draft.controlMethod.toUpperCase().contains('MQTT')) {
      return '요청: 원격 ${command.toUpperCase()}';
    }
    if (ip.isNotEmpty) {
      return '요청: 같은 Wi-Fi $commandText';
    }
    return '요청: 플러그 제어 · $command';
  }

  String _plugControlResponseLog(TasmotaDeviceTestResult result) {
    final voltage = _telemetryNumber(result.telemetry, 'voltage');
    final current = _telemetryNumber(result.telemetry, 'current');
    final watt = _telemetryNumber(result.telemetry, 'power');
    return [
      result.ok ? '응답: 성공' : '응답: 실패',
      result.statusLabel,
      if (result.powerOn != null) '현재 ${result.powerOn == true ? 'ON' : 'OFF'}',
      if (voltage != null) '전압 ${_formatAutoNumber(voltage)}V',
      if (current != null) '전류 ${_formatAutoNumber(current)}A',
      if (watt != null) '전력 ${_formatAutoNumber(watt)}W',
      if (result.isPending) '플러그 응답 대기 중',
      result.message,
    ].where((value) => value.trim().isNotEmpty).join(' · ');
  }

  String _autoRulesSummary(Iterable<DisasterAutoRule> rules) {
    final items = rules.map((rule) {
      final metric = _normalizeAutoMetric(rule.metric);
      return '${_autoMetricLabel(metric)} ${_formatAutoNumber(rule.onThreshold)}부터 켜짐 · ${_formatAutoNumber(rule.offThreshold)} 아래면 꺼짐';
    }).toList(growable: false);
    if (items.isEmpty) return '자동 제어 사용 안 함';
    return items.join(', ');
  }

  DisasterDeviceDraft _draftFromFields({
    String? statusLabel,
    bool? autoControlEnabled,
  }) {
    final base = _draft ?? _defaultDraft();
    final autoOnThreshold = _readAutoDouble(
      _autoThresholdController.text,
      base.autoOnThreshold,
    );
    final autoHysteresisPercent = _readAutoDouble(
      _autoHysteresisController.text,
      base.autoHysteresisPercent,
    ).clamp(1, 90).toDouble();
    final autoOffThreshold = autoOnThreshold <= 0
        ? base.autoOffThreshold
        : autoOnThreshold * (1 - autoHysteresisPercent / 100);
    final autoRules = _rulesWithCurrentFields();
    final selectedRule = autoRules[_normalizeAutoMetric(_autoMetric)] ??
        DisasterAutoRule(
          metric: _normalizeAutoMetric(_autoMetric),
          onThreshold: autoOnThreshold,
          offThreshold: autoOffThreshold,
          hysteresisPercent: autoHysteresisPercent,
        );
    final usesMqtt = _controlMethod.toUpperCase().contains('MQTT');
    final fallbackDeviceId = base.deviceId.trim().isNotEmpty
        ? base.deviceId.trim()
        : _plugIdForNumber(_nextPlugNumber());
    final nextDeviceId = _deviceIdController.text.trim().isEmpty
        ? fallbackDeviceId
        : _deviceIdController.text.trim();
    final inferredTopic = nextDeviceId.startsWith('cleanair-plug-')
        ? nextDeviceId.replaceAll('-', '_')
        : nextDeviceId.replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_');
    return base.copyWith(
      deviceId: nextDeviceId,
      displayName: _nameController.text.trim(),
      deviceType: base.deviceType.isEmpty ? '스마트 플러그' : base.deviceType,
      controlMethod: _controlMethod,
      plugIp: _normalizePlugAddress(_ipController.text),
      mqttTopic: usesMqtt && _topicController.text.trim().isEmpty
          ? inferredTopic
          : _normalizeMqttTopic(_topicController.text),
      linkedSpaceName: _spaceController.text.trim(),
      linkedAddress: _addressController.text.trim(),
      description: _descriptionController.text.trim(),
      autoControlEnabled: autoControlEnabled ?? base.autoControlEnabled,
      autoMetric: _autoMetric,
      autoOnThreshold: selectedRule.onThreshold,
      autoOffThreshold: selectedRule.offThreshold,
      autoHysteresisPercent: selectedRule.hysteresisPercent,
      autoRules: autoRules.values.toList(growable: false),
      autoHoldMinutes:
          _readAutoInt(_autoHoldController.text, base.autoHoldMinutes)
              .clamp(1, 60)
              .toInt(),
      purpose: _purposeController.text.trim(),
      lastTestStatus: statusLabel ?? base.lastTestStatus,
      updatedAt: DateTime.now(),
    );
  }

  double _readAutoDouble(String value, double fallback) {
    return double.tryParse(value.trim()) ?? fallback;
  }

  int _readAutoInt(String value, int fallback) {
    return int.tryParse(value.trim()) ?? fallback;
  }

  String _normalizePlugAddress(String value) {
    var text = value.trim();
    if (text.isEmpty) return '';
    text = text.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    final slash = text.indexOf('/');
    if (slash >= 0) {
      text = text.substring(0, slash);
    }
    return text.trim();
  }

  String _normalizePlugName(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  String _normalizeMqttTopic(String value) {
    var text = value.trim();
    if (text.isEmpty) return '';
    text = text.replaceAll('\\', '/');
    if (text.contains('/')) {
      final parts =
          text.split('/').where((part) => part.trim().isNotEmpty).toList();
      if (parts.length >= 2) {
        final prefix = parts.first.trim().toLowerCase();
        if (prefix == 'cmnd' || prefix == 'stat' || prefix == 'tele') {
          text = parts[1].trim();
        }
      }
    }
    text = text.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    text = text.replaceAll(RegExp(r'_+'), '_');
    text = text.replaceAll(RegExp(r'^_+|_+$'), '');
    return text;
  }

  String _formatAutoNumber(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _autoMetricLabel(String metric) {
    switch (metric) {
      case 'co2':
        return 'CO₂';
      case 'co':
        return 'CO';
      case 'pm25':
        return 'PM2.5';
      case 'tvoc':
        return 'TVOC';
      case 'nox':
        return 'NOx';
      default:
        return 'IAQI';
    }
  }

  ({double on, double off}) _autoMetricDefaults(String metric) {
    return switch (metric) {
      'co2' => (on: 1000.0, off: 900.0),
      'co' => (on: 10.0, off: 5.0),
      'pm25' => (on: 35.0, off: 25.0),
      'tvoc' => (on: 400.0, off: 300.0),
      'nox' => (on: 2.0, off: 1.0),
      _ => (on: 1.2, off: 0.9),
    };
  }

  DisasterAutoRule _defaultAutoRule(String metric) {
    final normalized = _normalizeAutoMetric(metric);
    final defaults = _autoMetricDefaults(normalized);
    return DisasterAutoRule(
      metric: normalized,
      onThreshold: defaults.on,
      offThreshold: defaults.off,
      hysteresisPercent: _hysteresisFromThresholds(defaults.on, defaults.off),
    );
  }

  Map<String, DisasterAutoRule> _rulesFromDraft(DisasterDeviceDraft draft) {
    final rules = <String, DisasterAutoRule>{};
    for (final rule in draft.autoRules) {
      final metric = _normalizeAutoMetric(rule.metric);
      rules[metric] = rule.copyWith(metric: metric);
    }
    if (rules.isEmpty) {
      final metric = _normalizeAutoMetric(draft.autoMetric);
      rules[metric] = DisasterAutoRule(
        metric: metric,
        onThreshold: draft.autoOnThreshold,
        offThreshold: draft.autoOffThreshold,
        hysteresisPercent: draft.autoHysteresisPercent,
      );
    }
    return rules;
  }

  Map<String, DisasterAutoRule> _rulesWithCurrentFields() {
    final metric = _normalizeAutoMetric(_autoMetric);
    final base = _autoRules[metric] ?? _defaultAutoRule(metric);
    final on = _readAutoDouble(_autoThresholdController.text, base.onThreshold);
    final hysteresis = _readAutoDouble(
      _autoHysteresisController.text,
      base.hysteresisPercent,
    ).clamp(1, 90).toDouble();
    final off = on <= 0 ? base.offThreshold : on * (1 - hysteresis / 100);
    final next = Map<String, DisasterAutoRule>.from(_autoRules);
    next[metric] = base.copyWith(
      metric: metric,
      onThreshold: on,
      offThreshold: off,
      hysteresisPercent: hysteresis,
    );
    return next;
  }

  bool get _editingAutoDisabled => _draft?.autoControlEnabled != true;

  void _setAutoControlDisabledForEdit() {
    setState(() {
      _draft = (_draft ?? _defaultDraft()).copyWith(
        autoControlEnabled: false,
        updatedAt: DateTime.now(),
      );
    });
  }

  void _loadAutoRuleIntoFields(String metric) {
    final normalized = _normalizeAutoMetric(metric);
    final rule = _autoRules[normalized] ?? _defaultAutoRule(normalized);
    _autoThresholdController.text = _formatAutoNumber(rule.onThreshold);
    _autoHysteresisController.text = _formatAutoNumber(rule.hysteresisPercent);
    _autoOffThresholdController.text = _formatAutoNumber(rule.offThreshold);
  }

  double _hysteresisFromThresholds(double on, double off) {
    if (on <= 0 || off <= 0 || off >= on) return 25;
    return (((on - off) / on) * 100).clamp(1, 90).toDouble();
  }

  void _syncOffThresholdFromHysteresis() {
    final on = double.tryParse(_autoThresholdController.text.trim());
    final hysteresis = double.tryParse(_autoHysteresisController.text.trim());
    if (on == null || hysteresis == null || on <= 0) {
      setState(() {});
      return;
    }
    final clampedHysteresis = hysteresis.clamp(1, 90).toDouble();
    final off = on * (1 - clampedHysteresis / 100);
    final formattedOff = _formatAutoNumber(off);
    if (_autoOffThresholdController.text != formattedOff) {
      _autoOffThresholdController.text = formattedOff;
    }
    final formattedHysteresis = _formatAutoNumber(clampedHysteresis);
    if (_autoHysteresisController.text != formattedHysteresis) {
      _autoHysteresisController.text = formattedHysteresis;
    }
    setState(() {
      _autoRules = _rulesWithCurrentFields();
    });
  }

  void _setAutoMetric(String metric) {
    final normalized = _normalizeAutoMetric(metric);
    setState(() {
      _autoRules = _rulesWithCurrentFields();
      _autoMetric = normalized;
      _autoRules = {
        ..._autoRules,
        if (!_autoRules.containsKey(normalized))
          normalized: _defaultAutoRule(normalized),
      };
      _loadAutoRuleIntoFields(normalized);
      _draft = (_draft ?? _defaultDraft()).copyWith(
        autoControlEnabled: true,
        updatedAt: DateTime.now(),
      );
    });
  }

  void _removeSelectedAutoRule() {
    if (_autoRules.length <= 1) {
      _showSnack('자동 제어 기준은 하나 이상 필요합니다.');
      return;
    }
    final next = Map<String, DisasterAutoRule>.from(_autoRules)
      ..remove(_normalizeAutoMetric(_autoMetric));
    final nextMetric = next.keys.first;
    setState(() {
      _autoRules = next;
      _autoMetric = nextMetric;
      _loadAutoRuleIntoFields(nextMetric);
    });
  }

  String? _validateAutoPolicy(DisasterDeviceDraft draft) {
    if (!draft.autoControlEnabled) return null;
    final rules = _rulesFromDraft(draft).values;
    if (rules.isEmpty) return '자동 제어 기준은 하나 이상 필요합니다.';
    for (final rule in rules) {
      final label = _autoMetricLabel(rule.metric);
      if (rule.onThreshold <= 0 || rule.offThreshold <= 0) {
        return '$label 기준은 0보다 큰 값으로 입력해 주세요.';
      }
      if (rule.hysteresisPercent <= 0 || rule.hysteresisPercent >= 100) {
        return '$label 히스테리시스는 1~90% 사이로 입력해 주세요.';
      }
      if (rule.offThreshold >= rule.onThreshold) {
        return '$label 꺼짐 값은 켜짐 값보다 낮아야 합니다.';
      }
    }
    if (draft.autoOnThreshold <= 0 || draft.autoOffThreshold <= 0) {
      return '자동 제어 기준은 0보다 큰 값으로 입력해 주세요.';
    }
    if (draft.autoHysteresisPercent <= 0 ||
        draft.autoHysteresisPercent >= 100) {
      return '히스테리시스는 1~90% 사이로 입력해 주세요.';
    }
    if (draft.autoOffThreshold >= draft.autoOnThreshold) {
      return '꺼짐 값은 켜짐 값보다 낮아야 합니다. 그래야 플러그가 짧게 켜졌다 꺼지는 일을 줄일 수 있습니다.';
    }
    return null;
  }

  String? _validatePlugIdentity(DisasterDeviceDraft draft) {
    final name = draft.displayName.trim();
    final id = draft.deviceId.trim();
    final normalizedName = _normalizePlugName(name);
    final ip = _normalizePlugAddress(draft.plugIp).toLowerCase();
    final topic = _normalizeMqttTopic(draft.mqttTopic).toLowerCase();
    final normalizedId = id.toLowerCase();
    if (name.isEmpty) return '플러그 이름을 입력해 주세요.';
    if (id.isEmpty) return '플러그 정보를 저장할 수 없습니다. 플러그를 다시 추가해 주세요.';
    for (var i = 0; i < _drafts.length; i += 1) {
      if (i == _selectedDeviceIndex) continue;
      final other = _drafts[i];
      final otherId = other.deviceId.trim().toLowerCase();
      if (_normalizePlugName(other.displayName) == normalizedName) {
        return '같은 플러그 이름이 이미 있습니다.';
      }
      if (otherId == normalizedId) {
        return '같은 플러그가 이미 등록되어 있습니다.';
      }
      if (ip.isNotEmpty &&
          _normalizePlugAddress(other.plugIp).toLowerCase() == ip) {
        return '같은 로컬 IP를 쓰는 플러그가 이미 있습니다.';
      }
      final otherTopic = _normalizeMqttTopic(other.mqttTopic).toLowerCase();
      if (topic.isNotEmpty && otherTopic == topic) {
        return '같은 식별 이름을 쓰는 플러그가 이미 있습니다.';
      }
    }
    return null;
  }

  Future<void> _togglePowerForIndex(int index) async {
    if (_busy || index < 0 || index >= _drafts.length) return;
    _selectDevice(index);
    final powerOn = _drafts[index].currentPowerOn == true;
    if (powerOn) {
      await _turnOff();
    } else {
      await _turnOn();
    }
  }

  Future<void> _runLocalAutoControlIfNeeded() async {
    if (_localAutoControlRunning || !mounted || _drafts.isEmpty) return;
    if (!_drafts.any((draft) => draft.autoControlEnabled)) return;
    final snapshot = context.read<AirQualityController>().latestSnapshot;
    if (snapshot == null) return;
    _localAutoControlRunning = true;
    try {
      var changed = false;
      final updatedDrafts = _drafts.toList(growable: true);
      for (var i = 0; i < updatedDrafts.length; i += 1) {
        final draft = updatedDrafts[i];
        final decision = _autoDecisionFor(draft, snapshot);
        if (decision.skipReason != null) {
          continue;
        }
        final turnOn = decision.turnOn!;
        final value = decision.value!;
        final result = await _testController.runAutoPower(
          draft,
          turnOn: turnOn,
          reason: decision.reason!,
        );
        final now = DateTime.now();
        final updated = draft.copyWith(
          lastTestStatus: result.statusLabel,
          currentPowerOn: result.ok ? turnOn : draft.currentPowerOn,
          telemetry:
              result.telemetry.isEmpty ? draft.telemetry : result.telemetry,
          lastPowerChangedAt: result.ok ? now : draft.lastPowerChangedAt,
          updatedAt: now,
        );
        updatedDrafts[i] = updated;
        changed = true;
        await _appendHistory(
          draft: updated,
          action: turnOn ? '자동 ON' : '자동 OFF',
          status: result.ok ? '확인' : '실패',
          ok: result.ok,
          powerOn: result.ok ? turnOn : null,
          message: result.ok
              ? '${decision.metricLabel} ${_formatAutoNumber(value)} · ${turnOn ? '켜짐 조건 도달' : '꺼짐 조건 회복'}'
              : result.message,
          requestLog:
              '요청: 자동 제어 · ${decision.metricLabel} ${_formatAutoNumber(value)} · ${turnOn ? '켜짐 조건 도달' : '꺼짐 조건 회복'}',
          responseLog: _plugControlResponseLog(result),
        );
      }
      if (!changed || !mounted) return;
      await _storage.saveAll(updatedDrafts);
      await _syncProfileAssetLinksIfSignedIn();
      if (!mounted) return;
      final selectedIndex = _selectedDeviceIndex
          .clamp(
            0,
            updatedDrafts.length - 1,
          )
          .toInt();
      final selected = updatedDrafts[selectedIndex];
      _applyDraftToFields(selected);
      setState(() {
        _drafts = updatedDrafts;
        _selectedDeviceIndex = selectedIndex;
        _draft = selected;
        _powerOn = selected.currentPowerOn;
        _statusMessage = selected.lastTestStatus;
      });
    } finally {
      _localAutoControlRunning = false;
    }
  }

  ({
    bool? turnOn,
    String metric,
    String metricLabel,
    double? value,
    String? reason,
    String? skipReason,
  }) _autoDecisionFor(DisasterDeviceDraft draft, AirQualitySnapshot snapshot) {
    if (!draft.autoControlEnabled) {
      return (
        turnOn: null,
        metric: _normalizeAutoMetric(draft.autoMetric),
        metricLabel: _autoMetricLabel(draft.autoMetric),
        value: null,
        reason: null,
        skipReason: '수동 모드',
      );
    }
    final rules = _rulesFromDraft(draft).values.toList(growable: false);
    if (rules.isEmpty) {
      return (
        turnOn: null,
        metric: _normalizeAutoMetric(draft.autoMetric),
        metricLabel: _autoMetricLabel(draft.autoMetric),
        value: null,
        reason: null,
        skipReason: '자동 제어 기준 없음',
      );
    }
    final firstRule = rules.first;
    final metric = _normalizeAutoMetric(firstRule.metric);
    final metricLabel = _autoMetricLabel(metric);
    final usesMqtt = draft.controlMethod.toUpperCase().contains('MQTT');
    if (usesMqtt) {
      if (draft.mqttTopic.trim().isEmpty) {
        return (
          turnOn: null,
          metric: metric,
          metricLabel: metricLabel,
          value: null,
          reason: null,
          skipReason: '원격 제어 정보 없음',
        );
      }
    } else if (draft.plugIp.trim().isEmpty) {
      return (
        turnOn: null,
        metric: metric,
        metricLabel: metricLabel,
        value: null,
        reason: null,
        skipReason: '플러그 IP 없음',
      );
    }
    final now = DateTime.now();
    final overrideUntil = draft.manualOverrideUntil;
    if (overrideUntil != null && overrideUntil.isAfter(now)) {
      return (
        turnOn: null,
        metric: metric,
        metricLabel: metricLabel,
        value: null,
        reason: null,
        skipReason: '수동 제어 일시중지 ${_formatClock(overrideUntil)}까지',
      );
    }
    final lastChanged = draft.lastPowerChangedAt;
    if (lastChanged != null &&
        now.difference(lastChanged).inSeconds < draft.autoHoldMinutes * 60) {
      return (
        turnOn: null,
        metric: metric,
        metricLabel: metricLabel,
        value: null,
        reason: null,
        skipReason: '최소 재전환 간격 대기',
      );
    }
    final evaluated = <({DisasterAutoRule rule, double value})>[];
    for (final rule in rules) {
      final value = _autoMetricValue(snapshot, rule.metric);
      if (value != null) {
        evaluated.add((rule: rule, value: value));
      }
    }
    if (evaluated.isEmpty) {
      return (
        turnOn: null,
        metric: metric,
        metricLabel: metricLabel,
        value: null,
        reason: null,
        skipReason: '측정값 없음',
      );
    }
    final isOn = draft.currentPowerOn == true;
    ({DisasterAutoRule rule, double value})? onRule;
    for (final item in evaluated) {
      if (item.value < item.rule.onThreshold) continue;
      if (onRule == null) {
        onRule = item;
        continue;
      }
      final itemRatio = item.value / item.rule.onThreshold;
      final bestRatio = onRule.value / onRule.rule.onThreshold;
      if (itemRatio > bestRatio) {
        onRule = item;
      }
    }
    if (!isOn && onRule != null) {
      return (
        turnOn: true,
        metric: onRule.rule.metric,
        metricLabel: _autoMetricLabel(onRule.rule.metric),
        value: onRule.value,
        reason: 'auto_${onRule.rule.metric}_above_on_threshold',
        skipReason: null,
      );
    }
    final allRecovered = evaluated.length == rules.length &&
        evaluated.every((item) => item.value <= item.rule.offThreshold);
    if (isOn && allRecovered) {
      final primary = evaluated.first;
      return (
        turnOn: false,
        metric: primary.rule.metric,
        metricLabel: _autoMetricLabel(primary.rule.metric),
        value: primary.value,
        reason: 'auto_all_rules_recovered',
        skipReason: null,
      );
    }
    return (
      turnOn: null,
      metric: metric,
      metricLabel: metricLabel,
      value: evaluated.first.value,
      reason: null,
      skipReason: isOn ? '꺼짐 값까지 회복되지 않음' : '켜짐 값 미만',
    );
  }

  String _autoControlHint(
    DisasterDeviceDraft draft,
    AirQualitySnapshot? snapshot,
  ) {
    final rules = _rulesFromDraft(draft).values.toList(growable: false);
    if (!draft.autoControlEnabled) {
      return '수동 모드입니다. 자동 제어 로직은 실행되지 않습니다.';
    }
    if (draft.controlMethod.toUpperCase().contains('MQTT')) {
      if (draft.mqttTopic.trim().isEmpty) {
        return '원격 제어 정보가 없어 자동 제어 명령을 보낼 수 없습니다.';
      }
    } else if (draft.plugIp.trim().isEmpty) {
      return '로컬 IP가 없어 자동 제어를 실행할 수 없습니다.';
    }
    if (snapshot == null) {
      return '센서값을 기다리는 중입니다.';
    }
    final now = DateTime.now();
    final overrideUntil = draft.manualOverrideUntil;
    if (overrideUntil != null && overrideUntil.isAfter(now)) {
      return '수동 제어로 ${_formatClock(overrideUntil)}까지 자동 제어를 멈춥니다.';
    }
    final lastChanged = draft.lastPowerChangedAt;
    if (lastChanged != null) {
      final remainingSeconds =
          draft.autoHoldMinutes * 60 - now.difference(lastChanged).inSeconds;
      if (remainingSeconds > 0) {
        final remainingMinutes = (remainingSeconds / 60).ceil();
        return '최근 제어 후 재전환 대기 중입니다. 약 $remainingMinutes분 뒤 다시 판단합니다.';
      }
    }
    final evaluated = <({DisasterAutoRule rule, double value})>[];
    for (final rule in rules) {
      final value = _autoMetricValue(snapshot, rule.metric);
      if (value != null) {
        evaluated.add((rule: rule, value: value));
      }
    }
    if (evaluated.isEmpty) {
      return '자동 제어에 사용할 측정값이 아직 없습니다.';
    }
    ({DisasterAutoRule rule, double value})? onRule;
    for (final item in evaluated) {
      if (item.value >= item.rule.onThreshold) {
        onRule = item;
        break;
      }
    }
    final allRecovered = evaluated.length == rules.length &&
        evaluated.every((item) => item.value <= item.rule.offThreshold);
    if (draft.currentPowerOn == true) {
      if (allRecovered) {
        return '설정한 값들이 모두 안정 범위로 내려왔습니다. 다음 판단에서 꺼짐을 시도합니다.';
      }
      final active = evaluated
          .where((item) => item.value > item.rule.offThreshold)
          .map((item) =>
              '${_autoMetricLabel(item.rule.metric)} ${_formatAutoNumber(item.value)}')
          .join(', ');
      return '$active · 아직 꺼짐 기준까지 회복되지 않았습니다.';
    }
    if (onRule != null) {
      return '${_autoMetricLabel(onRule.rule.metric)} ${_formatAutoNumber(onRule.value)} · 켜짐 조건입니다.';
    }
    final watching =
        rules.map((rule) => _autoMetricLabel(rule.metric)).join(', ');
    return '$watching 기준을 보고 있습니다. 기준을 넘으면 자동으로 켭니다.';
  }

  String _normalizeAutoMetric(String value) {
    final normalized = value.trim().toLowerCase();
    const allowed = {'iaqi', 'co2', 'co', 'pm25', 'tvoc', 'nox'};
    return allowed.contains(normalized) ? normalized : 'iaqi';
  }

  double? _autoMetricValue(AirQualitySnapshot snapshot, String metric) {
    return switch (_normalizeAutoMetric(metric)) {
      'co2' => snapshot.co2,
      'co' => snapshot.co,
      'pm25' => snapshot.pm25,
      'tvoc' => snapshot.tvoc,
      'nox' => snapshot.nox,
      _ => snapshot.iaqiScore,
    };
  }

  Future<DisasterDeviceDraft?> _saveDraft({
    bool showSnack = true,
    String? statusLabel,
    bool? autoControlEnabled,
  }) async {
    var draft = _draftFromFields(
      statusLabel: statusLabel,
      autoControlEnabled: autoControlEnabled,
    );
    final autoPolicyError = _validateAutoPolicy(draft);
    if (autoPolicyError != null) {
      if (mounted) _showSnack(autoPolicyError);
      return null;
    }
    final identityError = _validatePlugIdentity(draft);
    if (identityError != null) {
      if (mounted) _showSnack(identityError);
      return null;
    }
    try {
      String? syncedProfileId;
      if (draft.autoControlEnabled) {
        try {
          syncedProfileId = await _syncBackendAutoProfile(draft, enabled: true);
        } catch (_) {
          syncedProfileId = null;
        }
        draft = draft.copyWith(
          lastTestStatus:
              syncedProfileId == null ? '자동 제어 설정 저장됨' : '자동 제어 반영됨',
          updatedAt: DateTime.now(),
        );
      }
      await _storage.saveAll(_replaceSelectedDraft(draft));
      final profileSynced = await _syncProfileAssetLinksIfSignedIn();
      final hasControlEndpoint =
          draft.controlMethod.toUpperCase().contains('MQTT')
              ? draft.mqttTopic.trim().isNotEmpty
              : draft.plugIp.trim().isNotEmpty;
      await _appendHistory(
        draft: draft,
        action: '저장',
        status: hasControlEndpoint ? '저장됨' : '제어 정보 필요',
        ok: hasControlEndpoint,
        message: syncedProfileId == null
            ? '${draft.displayName} 저장'
            : '${draft.displayName} 저장 · 자동 제어 동기화',
        requestLog: draft.autoControlEnabled
            ? '요청: 자동 제어 설정 저장 · ${_autoRulesSummary(draft.autoRules)} · 전환 후 ${draft.autoHoldMinutes}분 유지'
            : '',
        responseLog: syncedProfileId == null ? '' : '응답: 자동 제어 설정 반영됨',
      );
      final savedDrafts = await _storage.loadAll();
      if (!mounted) return draft;
      final resolved = savedDrafts.firstWhere(
        (item) => item.deviceId == draft.deviceId,
        orElse: () => draft,
      );
      _applyDraftToFields(resolved);
      setState(() {
        _drafts =
            savedDrafts.isEmpty ? <DisasterDeviceDraft>[resolved] : savedDrafts;
        _draft = resolved;
        _editingPlug = false;
        _showPlugDetail = true;
        _statusMessage = '${resolved.displayName} 저장됨';
        _autoPolicyMessage = syncedProfileId == null
            ? _autoPolicyMessage
            : '${_autoMetricLabel(resolved.autoMetric)} ${_formatAutoNumber(resolved.autoOnThreshold)}부터 켜짐';
        _activities.insert(
          0,
          _PlugActivityEntry(
            time: _formatClock(DateTime.now()),
            action: '저장',
            status: hasControlEndpoint ? '저장됨' : '제어 정보 필요',
            color: hasControlEndpoint
                ? const Color(0xFF16A34A)
                : CleanColors.secondary,
          ),
        );
        if (_activities.length > 5) {
          _activities.removeRange(5, _activities.length);
        }
      });
      if (showSnack) {
        _showSnack(
          profileSynced ? '저장했습니다. 웹 대시보드에도 반영했습니다.' : '저장했습니다.',
        );
      }
      if (resolved.autoControlEnabled) {
        unawaited(_runLocalAutoControlIfNeeded());
      }
      return resolved;
    } catch (error) {
      if (mounted) _showSnack('저장 실패: $error');
      return null;
    }
  }

  Future<void> _deleteSelectedPlug() async {
    return _deletePlugAt(_selectedDeviceIndex);
  }

  Future<void> _deletePlugAt(int targetIndex) async {
    if (_busy || _drafts.isEmpty) return;
    final index = targetIndex.clamp(0, _drafts.length - 1).toInt();
    final draft = _drafts[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('플러그 삭제'),
          content: Text('${draft.displayName}을 삭제할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    final remaining = _drafts.toList(growable: true)..removeAt(index);
    await _storage.saveAll(remaining);
    await _syncProfileAssetLinksIfSignedIn();
    await _appendHistory(
      draft: draft,
      action: '삭제',
      status: '삭제됨',
      ok: true,
      message: '${draft.displayName} 삭제',
    );
    if (!mounted) return;

    final nextDrafts = remaining;
    if (nextDrafts.isEmpty) {
      setState(() {
        _drafts = const <DisasterDeviceDraft>[];
        _selectedDeviceIndex = 0;
        _draft = null;
        _powerOn = null;
        _editingPlug = false;
        _showPlugDetail = false;
        _editingList = false;
        _statusMessage = '등록된 플러그가 없습니다.';
      });
      _showSnack('${draft.displayName}을 삭제했습니다.');
      return;
    }
    final nextIndex = index.clamp(0, nextDrafts.length - 1).toInt();
    final nextDraft = nextDrafts[nextIndex];
    _applyDraftToFields(nextDraft);
    setState(() {
      _drafts = nextDrafts;
      _selectedDeviceIndex = nextIndex;
      _draft = nextDraft;
      _powerOn = nextDraft.currentPowerOn;
      _editingPlug = remaining.isEmpty;
      _showPlugDetail = remaining.isEmpty;
      _editingList = false;
      _statusMessage =
          remaining.isEmpty ? '새 플러그를 추가하세요.' : nextDraft.lastTestStatus;
    });
    _showSnack('${draft.displayName}을 삭제했습니다.');
  }

  Future<void> _testConnection() {
    return _runDeviceAction(
      label: '연결',
      runner: _testController.testConnection,
    );
  }

  Future<void> _turnOn() {
    return _runDeviceAction(
      label: '켜짐',
      runner: _testController.testPowerOn,
    );
  }

  Future<void> _turnOff() {
    return _runDeviceAction(
      label: '꺼짐',
      runner: _testController.testPowerOff,
    );
  }

  Future<void> _runAllPower(bool turnOn) async {
    if (_busy) return;
    final targetDraft = _draftFromFields();
    final drafts = _replaceSelectedDraft(targetDraft).where((draft) {
      final usesMqtt = draft.controlMethod.toUpperCase().contains('MQTT');
      return usesMqtt
          ? draft.mqttTopic.trim().isNotEmpty
          : draft.plugIp.trim().isNotEmpty;
    }).toList(growable: true);
    if (drafts.isEmpty) {
      _showSnack('제어할 플러그 IP 또는 원격 제어 설정이 없습니다.');
      return;
    }
    final prefs = context.read<NotificationPreferencesController>().value;
    final notifyPlugControl =
        prefs.alertsEnabled && !(prefs.mutedTypes['plug_control'] ?? false);

    setState(() {
      _busy = true;
      _statusMessage = turnOn ? '전체 ON 실행 중' : '전체 OFF 실행 중';
    });

    final updatedDrafts = _drafts.toList(growable: true);
    var successCount = 0;
    for (final draft in drafts) {
      final result = turnOn
          ? await _testController.testPowerOn(draft)
          : await _testController.testPowerOff(draft);
      if (result.ok) successCount += 1;
      final manualOverrideUntil = result.powerOn == null
          ? draft.manualOverrideUntil
          : DateTime.now().add(const Duration(minutes: 15));
      final updated = draft.copyWith(
        lastTestStatus: result.statusLabel,
        currentPowerOn: result.powerOn,
        telemetry:
            result.telemetry.isEmpty ? draft.telemetry : result.telemetry,
        lastPowerChangedAt:
            result.powerOn == null ? draft.lastPowerChangedAt : DateTime.now(),
        manualOverrideUntil: manualOverrideUntil,
        updatedAt: DateTime.now(),
      );
      final index =
          updatedDrafts.indexWhere((item) => item.deviceId == draft.deviceId);
      if (index >= 0) updatedDrafts[index] = updated;
      await _appendHistory(
        draft: updated,
        action: turnOn ? '전체 ON' : '전체 OFF',
        status: result.ok ? '확인' : '실패',
        ok: result.ok,
        powerOn: result.powerOn,
        message: result.ok && result.powerOn != null
            ? '${result.message} · 자동 제어 15분 일시 중지'
            : result.message,
        requestLog: _plugControlRequestLog(
          draft,
          command: turnOn ? 'ON' : 'OFF',
        ),
        responseLog: _plugControlResponseLog(result),
      );
    }

    await _storage.saveAll(updatedDrafts);
    await _syncProfileAssetLinksIfSignedIn();
    final saved = await _storage.loadAll();
    if (notifyPlugControl) {
      await AlertNotificationPresenter.showAlert(
        '플러그 일괄 제어',
        '${drafts.length}개 중 $successCount개 ${turnOn ? 'ON' : 'OFF'} 성공',
      );
    }
    if (!mounted) return;
    final selectedIndex = saved.isEmpty
        ? 0
        : _selectedDeviceIndex.clamp(0, saved.length - 1).toInt();
    final selected = saved.isEmpty ? targetDraft : saved[selectedIndex];
    _applyDraftToFields(selected);
    setState(() {
      _drafts = saved;
      _selectedDeviceIndex = selectedIndex;
      _draft = selected;
      _powerOn = selected.currentPowerOn;
      _statusMessage =
          '${turnOn ? '전체 ON' : '전체 OFF'} · $successCount/${drafts.length} 성공';
      _busy = false;
    });
    _showSnack('${drafts.length}개 중 $successCount개 제어 성공');
  }

  Future<void> _runDeviceAction({
    required String label,
    required Future<TasmotaDeviceTestResult> Function(DisasterDeviceDraft)
        runner,
  }) async {
    if (_busy) return;
    if (_draft == null && _drafts.isEmpty) {
      _showSnack('먼저 플러그를 추가하세요.');
      return;
    }
    final draft = _draftFromFields();
    setState(() => _busy = true);
    try {
      final result = await runner(draft);
      final changedAt =
          result.powerOn == null ? draft.lastPowerChangedAt : DateTime.now();
      final manualOverrideUntil = result.ok && result.powerOn != null
          ? DateTime.now().add(const Duration(minutes: 15))
          : draft.manualOverrideUntil;
      final updated = draft.copyWith(
        lastTestStatus: result.statusLabel,
        currentPowerOn: result.powerOn,
        telemetry:
            result.telemetry.isEmpty ? draft.telemetry : result.telemetry,
        lastPowerChangedAt: changedAt,
        manualOverrideUntil: manualOverrideUntil,
        updatedAt: DateTime.now(),
      );
      await _storage.saveAll(_replaceSelectedDraft(updated));
      await _syncProfileAssetLinksIfSignedIn();
      await _appendHistory(
        draft: updated,
        action: label,
        status: result.ok
            ? '확인'
            : result.isPending
                ? '대기'
                : '실패',
        ok: result.ok,
        powerOn: result.powerOn,
        message: result.ok && result.powerOn != null
            ? '${result.message} · 자동 제어 15분 일시 중지'
            : result.message,
        requestLog: _plugControlRequestLog(
          draft,
          command: label == '켜짐'
              ? 'ON'
              : label == '꺼짐'
                  ? 'OFF'
                  : 'STATE',
        ),
        responseLog: _plugControlResponseLog(result),
      );
      if (result.powerOn != null) {
        await _notifyPlugControl(
          draft: updated,
          action: label,
          ok: result.ok,
          powerOn: result.powerOn,
          message: result.message,
        );
      }
      final savedDrafts = await _storage.loadAll();
      if (!mounted) return;
      final resolved = savedDrafts.firstWhere(
        (item) => item.deviceId == updated.deviceId,
        orElse: () => updated,
      );
      _applyDraftToFields(resolved);
      setState(() {
        _drafts =
            savedDrafts.isEmpty ? <DisasterDeviceDraft>[resolved] : savedDrafts;
        _draft = resolved;
        _statusMessage = result.statusLabel;
        _powerOn = result.powerOn;
        _activities.insert(
          0,
          _PlugActivityEntry(
            time: _formatClock(DateTime.now()),
            action: label,
            status: result.ok
                ? '확인'
                : result.isPending
                    ? '대기'
                    : '실패',
            color: result.ok
                ? const Color(0xFF16A34A)
                : result.isPending
                    ? CleanColors.secondary
                    : CleanColors.error,
          ),
        );
        if (_activities.length > 5) {
          _activities.removeRange(5, _activities.length);
        }
      });
      _showSnack(result.message);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusMessage = '$label 테스트 실패';
        _activities.insert(
          0,
          _PlugActivityEntry(
            time: _formatClock(DateTime.now()),
            action: label,
            status: '실패',
            color: CleanColors.error,
          ),
        );
        if (_activities.length > 5) {
          _activities.removeRange(5, _activities.length);
        }
      });
      _showSnack('$label 테스트 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copySettingsUrl() async {
    if (_busy) return;
    final draft = _draftFromFields();
    final validationMessage =
        DisasterDeviceWebSettings.validatePlugIp(draft.plugIp);
    if (validationMessage != null) {
      setState(() {
        _settingsUrlMessage = validationMessage;
        _statusMessage = '웹 설정 URL 확인 필요';
      });
      _showSnack(validationMessage);
      return;
    }

    setState(() => _busy = true);
    final url = await DisasterDeviceWebSettings.copySettingsUrl(draft);
    if (!mounted) return;
    if (url == null) {
      setState(() {
        _busy = false;
        _settingsUrlMessage = '웹 설정 URL을 만들 수 없습니다.';
        _statusMessage = '웹 설정 URL 생성 실패';
      });
      _showSnack('웹 설정 URL을 만들 수 없습니다.');
      return;
    }

    try {
      final updated = draft.copyWith(
        lastTestStatus: '웹 설정 URL 복사됨',
        updatedAt: DateTime.now(),
      );
      await _storage.saveAll(_replaceSelectedDraft(updated));
      await _syncProfileAssetLinksIfSignedIn();
      await _appendHistory(
        draft: updated,
        action: '웹 설정',
        status: '복사됨',
        ok: true,
        message: url,
      );
      final saved = await _storage.loadAll();
      if (!mounted) return;
      final resolved = saved.firstWhere(
        (item) => item.deviceId == updated.deviceId,
        orElse: () => updated,
      );
      _applyDraftToFields(resolved);
      setState(() {
        _drafts = saved.isEmpty ? <DisasterDeviceDraft>[resolved] : saved;
        _draft = resolved;
        _statusMessage = resolved.lastTestStatus;
        _settingsUrlMessage = url;
        _activities.insert(
          0,
          _PlugActivityEntry(
            time: _formatClock(DateTime.now()),
            action: '웹 설정',
            status: '복사됨',
            color: const Color(0xFF16A34A),
          ),
        );
        if (_activities.length > 5) {
          _activities.removeRange(5, _activities.length);
        }
      });
      _showSnack('웹 설정 URL을 복사했습니다: $url');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _settingsUrlMessage = '웹 설정 URL은 복사됐지만 저장에 실패했습니다.';
        _statusMessage = '웹 설정 URL 저장 실패';
      });
      _showSnack('웹 설정 URL 저장 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleAutoControl() async {
    if (_busy) return;
    final next = !(_draft ?? _defaultDraft()).autoControlEnabled;
    final draft = _draftFromFields(
      autoControlEnabled: next,
      statusLabel: next ? '자동 제어 켜짐' : '자동 제어 꺼짐',
    );
    final autoPolicyError = _validateAutoPolicy(draft);
    if (autoPolicyError != null) {
      _showSnack(autoPolicyError);
      return;
    }
    final identityError = _validatePlugIdentity(draft);
    if (identityError != null) {
      _showSnack(identityError);
      return;
    }
    setState(() => _busy = true);
    try {
      String? syncedProfileId;
      try {
        syncedProfileId = await _syncBackendAutoProfile(draft, enabled: next);
      } catch (_) {
        syncedProfileId = null;
      }
      final synced = syncedProfileId != null;
      final updated = draft.copyWith(
        lastTestStatus: synced
            ? '자동 제어 반영됨'
            : next
                ? '자동 제어 설정 저장됨'
                : '자동 제어 꺼짐',
        updatedAt: DateTime.now(),
      );
      await _storage.saveAll(_replaceSelectedDraft(updated));
      await _syncProfileAssetLinksIfSignedIn();
      await _appendHistory(
        draft: updated,
        action: next ? '자동 모드 ON' : '수동 모드',
        status: synced
            ? '동기화'
            : next
                ? '로컬'
                : '꺼짐',
        ok: true,
        message: next ? '자동 제어 ${synced ? '반영됨' : '저장됨'}' : '수동 제어로 전환됨',
        requestLog:
            '요청: 자동 제어 ${next ? '켜기' : '끄기'} · ${_autoRulesSummary(draft.autoRules)}',
        responseLog: synced ? '응답: 자동 제어 설정 반영됨' : '응답: 앱에 설정 저장됨',
      );
      final saved = await _storage.loadAll();
      if (!mounted) return;
      final resolved = saved.firstWhere(
        (item) => item.deviceId == updated.deviceId,
        orElse: () => updated,
      );
      _applyDraftToFields(resolved);
      setState(() {
        _drafts = saved.isEmpty ? <DisasterDeviceDraft>[resolved] : saved;
        _draft = resolved;
        _statusMessage = resolved.lastTestStatus;
        _autoPolicyMessage = synced
            ? '${_autoMetricLabel(resolved.autoMetric)} ${_formatAutoNumber(resolved.autoOnThreshold)}부터 켜짐'
            : next
                ? '${_autoMetricLabel(resolved.autoMetric)} 기준 저장됨'
                : '자동 제어 꺼짐';
        _activities.insert(
          0,
          _PlugActivityEntry(
            time: _formatClock(DateTime.now()),
            action: '자동 정책',
            status: synced
                ? '동기화'
                : next
                    ? '로컬'
                    : '꺼짐',
            color: synced
                ? const Color(0xFF16A34A)
                : next
                    ? CleanColors.secondary
                    : CleanColors.outline,
          ),
        );
        if (_activities.length > 5) {
          _activities.removeRange(5, _activities.length);
        }
      });
      _showSnack(
        synced ? '자동 제어 설정을 저장했습니다.' : '자동 제어 설정을 저장했습니다.',
      );
      if (next) {
        unawaited(_runLocalAutoControlIfNeeded());
      }
    } catch (error) {
      if (mounted) _showSnack('자동 제어 설정 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _syncBackendAutoProfile(
    DisasterDeviceDraft draft, {
    required bool enabled,
  }) {
    return _testController.syncBackendAutoProfile(
      draft,
      metric: draft.autoMetric,
      onThreshold: draft.autoOnThreshold,
      offThreshold: draft.autoOffThreshold,
      rules: draft.autoRules,
      aqiOn: draft.autoMetric == 'iaqi'
          ? (draft.autoOnThreshold * 100).round()
          : null,
      aqiOff: draft.autoMetric == 'iaqi'
          ? (draft.autoOffThreshold * 100).round()
          : null,
      enabled: enabled,
      minCommandIntervalSeconds: draft.autoHoldMinutes * 60,
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<({String a, String b, String c, Color color})> _activityRows(
    DisasterDeviceDraft draft,
  ) {
    final historyRows = _history
        .where((entry) => entry.deviceId == draft.deviceId)
        .map(
          (entry) => (
            a: _formatHistoryDateMinute(entry.createdAt),
            b: entry.action,
            c: entry.status,
            color: entry.ok ? const Color(0xFF16A34A) : CleanColors.error,
          ),
        )
        .toList(growable: true);
    final rows = historyRows.isNotEmpty
        ? historyRows
        : _activities
            .map(
              (entry) => (
                a: entry.time,
                b: entry.action,
                c: entry.status,
                color: entry.color,
              ),
            )
            .toList(growable: true);

    if (rows.isEmpty) {
      final hasControlEndpoint =
          draft.controlMethod.toUpperCase().contains('MQTT')
              ? draft.mqttTopic.trim().isNotEmpty
              : draft.plugIp.trim().isNotEmpty;
      rows.add((
        a: _formatClock(draft.updatedAt),
        b: draft.lastTestStatus,
        c: hasControlEndpoint ? '저장됨' : '설정 필요',
        color: hasControlEndpoint
            ? const Color(0xFF16A34A)
            : CleanColors.secondary,
      ));
    }
    return rows;
  }

  List<({String a, String b, String c, Color color})> _allActivityRows() {
    final rows = _history
        .take(5)
        .map(
          (entry) => (
            a: _formatHistoryDateMinute(entry.createdAt),
            b: entry.displayName.trim().isEmpty ? '스마트 플러그' : entry.displayName,
            c: '${entry.action} · ${entry.status}',
            color: entry.ok ? const Color(0xFF16A34A) : CleanColors.error,
          ),
        )
        .toList(growable: true);

    if (rows.isEmpty) {
      rows.add((
        a: _formatClock(DateTime.now()),
        b: '제어 이력',
        c: '아직 기록 없음',
        color: CleanColors.secondary,
      ));
    }
    return rows;
  }

  void _openPlugHistory({String? deviceId}) {
    setState(() {
      _historyDeviceId = deviceId;
      _historyRange = _PlugHistoryRange.week;
      _showHistoryDetail = true;
    });
  }

  Future<void> _exportPlugHistoryCsv(
    List<DisasterDeviceHistoryEntry> rows,
  ) async {
    if (_historyCsvBusy) return;
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장할 제어 이력이 없습니다.')),
      );
      return;
    }

    setState(() => _historyCsvBusy = true);
    try {
      final result = await _historyCsvExportService.exportHistory(
        entries: rows,
        metricName: _historyDeviceId == null
            ? 'plug_control_history'
            : 'plug_control_history_${_historyDeviceId!}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '제어 이력 ${result.rowCount}건을 ${result.filePath}에 저장했습니다.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('제어 이력 CSV 저장 실패: $error')),
      );
    } finally {
      if (mounted) setState(() => _historyCsvBusy = false);
    }
  }

  List<DisasterDeviceHistoryEntry> _filteredHistory(
    _PlugHistoryRange range, {
    String? deviceId,
  }) {
    final now = DateTime.now();
    final cutoff = switch (range) {
      _PlugHistoryRange.today => DateTime(now.year, now.month, now.day),
      _PlugHistoryRange.week => now.subtract(const Duration(days: 7)),
      _PlugHistoryRange.month => now.subtract(const Duration(days: 30)),
      _PlugHistoryRange.all => DateTime.fromMillisecondsSinceEpoch(0),
    };
    final target = deviceId?.trim();
    return _history
        .where((entry) {
          final matchesDevice = target == null || target.isEmpty
              ? true
              : entry.deviceId == target;
          return matchesDevice && !entry.createdAt.isBefore(cutoff);
        })
        .take(80)
        .toList(growable: false);
  }

  String _historyRangeLabel(_PlugHistoryRange range) {
    switch (range) {
      case _PlugHistoryRange.today:
        return '오늘';
      case _PlugHistoryRange.week:
        return '7일';
      case _PlugHistoryRange.month:
        return '30일';
      case _PlugHistoryRange.all:
        return '전체';
    }
  }

  double? _telemetryNumber(Map<String, dynamic> telemetry, String key) {
    final value = telemetry[key];
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  List<({String label, String value})> _plugTelemetryRows(
    DisasterDeviceDraft draft,
  ) {
    final telemetry = draft.telemetry;
    final voltage = _telemetryNumber(telemetry, 'voltage');
    final current = _telemetryNumber(telemetry, 'current');
    final power = _telemetryNumber(telemetry, 'power');
    final today = _telemetryNumber(telemetry, 'today');
    final total = _telemetryNumber(telemetry, 'total');
    return <({String label, String value})>[
      if (voltage != null)
        (label: '전압', value: '${_formatAutoNumber(voltage)} V'),
      if (current != null)
        (label: '전류', value: '${_formatAutoNumber(current)} A'),
      if (power != null)
        (label: '현재 전력', value: '${_formatAutoNumber(power)} W'),
      if (today != null)
        (label: '오늘 사용량', value: '${_formatAutoNumber(today)} kWh'),
      if (total != null)
        (label: '누적 사용량', value: '${_formatAutoNumber(total)} kWh'),
    ];
  }

  Widget _buildPlugHistoryDetailScreen() {
    final rows = _filteredHistory(_historyRange, deviceId: _historyDeviceId);
    final title = _historyDeviceId == null ? '전체 제어 이력' : '플러그 제어 이력';
    var targetName = _historyDeviceId ?? '등록된 모든 플러그';
    for (final draft in _drafts) {
      if (draft.deviceId == _historyDeviceId &&
          draft.displayName.trim().isNotEmpty) {
        targetName = draft.displayName.trim();
        break;
      }
    }

    return _LegacyPage(
      title: title,
      leading: Symbols.arrow_back,
      trailing: Symbols.history,
      onLeadingTap: () => setState(() => _showHistoryDetail = false),
      children: [
        _SoftCard(
          radius: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(targetName, style: _cardTitle),
              const SizedBox(height: 6),
              const Text(
                '수동 제어와 자동 제어 요청을 기간별로 확인합니다.',
                style: _tinyMuted,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in _PlugHistoryRange.values)
                    _AutoMetricChip(
                      label: _historyRangeLabel(item),
                      selected: _historyRange == item,
                      onTap: () => setState(() => _historyRange = item),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _HeatMapActionButton(
                label: _historyCsvBusy ? 'CSV 저장 중' : 'CSV 저장',
                icon: Symbols.download,
                onTap:
                    _historyCsvBusy ? () {} : () => _exportPlugHistoryCsv(rows),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const _SoftCard(
            radius: 14,
            child: _InfoListTile(
              icon: Symbols.history,
              title: '제어 기록 없음',
              subtitle: '선택한 기간에 기록된 플러그 제어가 없습니다.',
            ),
          )
        else
          _SoftCard(
            radius: 14,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  _PlugHistoryEntryTile(entry: rows[i]),
                  if (i != rows.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
      ],
    );
  }

  String _autoModeSubtitle(DisasterDeviceDraft draft) {
    final overrideUntil = draft.manualOverrideUntil;
    if (overrideUntil != null && overrideUntil.isAfter(DateTime.now())) {
      return '수동 제어로 ${_formatClock(overrideUntil)}까지 자동 제어를 멈춥니다.';
    }
    return draft.autoControlEnabled
        ? '기준을 넘으면 켜지고, 회복 기준 아래로 내려가면 꺼집니다. 직접 ON/OFF를 누르면 잠시 수동 명령을 우선합니다.'
        : '사용자가 누른 ON/OFF 명령만 따릅니다.';
  }

  Widget _buildPlugDetailCard(
    DisasterDeviceDraft draft,
    List<({String a, String b, String c, Color color})> rows,
    String powerLabel,
    String statusLabel,
    bool hasIp,
  ) {
    final location = draft.linkedSpaceName.trim().isEmpty
        ? '위치 미설정'
        : draft.linkedSpaceName.trim();
    final detail = draft.linkedAddress.trim().isEmpty
        ? '상세 위치 미설정'
        : draft.linkedAddress.trim();
    final purpose =
        draft.purpose.trim().isEmpty ? '용도 미설정' : draft.purpose.trim();
    final telemetryRows = _plugTelemetryRows(draft);
    final usesMqtt = draft.controlMethod.toUpperCase().contains('MQTT');
    final controlTitle = usesMqtt
        ? (draft.mqttTopic.trim().isEmpty ? '원격 제어 설정 필요' : '원격 제어')
        : (hasIp ? draft.plugIp.trim() : '로컬 IP 미설정');
    final controlSubtitle = usesMqtt
        ? (draft.mqttTopic.trim().isEmpty
            ? '플러그의 MQTT 설정을 마치면 외부에서도 제어할 수 있습니다.'
            : '외부에서도 플러그 상태 확인과 ON/OFF 제어를 사용할 수 있습니다.')
        : hasIp
            ? '휴대폰과 플러그가 같은 Wi-Fi에 있을 때 제어합니다.'
            : '플러그 IP를 입력하면 켜기, 끄기, 상태 확인을 사용할 수 있습니다.';
    final autoHint = _autoControlHint(
      draft,
      context.read<AirQualityController>().latestSnapshot,
    );

    return _SoftCard(
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(draft.displayName, style: _cardTitle),
                    const SizedBox(height: 5),
                    Text(
                      hasIp ? statusLabel : '로컬 IP 미설정',
                      style: _tinyMuted,
                    ),
                  ],
                ),
              ),
              _StatusPill(text: powerLabel),
            ],
          ),
          const SizedBox(height: 14),
          const Text('기본 정보', style: _cardTitle),
          const SizedBox(height: 10),
          _InfoListTile(
            icon: usesMqtt ? Symbols.cloud_sync : Symbols.wifi,
            title: controlTitle,
            subtitle: controlSubtitle,
          ),
          const SizedBox(height: 10),
          _InfoListTile(
            icon: Symbols.location_on,
            title: location,
            subtitle: '$purpose · $detail',
          ),
          if (draft.description.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _InfoListTile(
              icon: Symbols.notes,
              title: '상세 설명',
              subtitle: draft.description.trim(),
            ),
          ],
          if (telemetryRows.isNotEmpty) ...[
            const SizedBox(height: 10),
            _PlugPowerInfoGrid(rows: telemetryRows),
          ],
          const SizedBox(height: 10),
          _InfoListTile(
            icon: Symbols.rule,
            title: draft.autoControlEnabled ? '자동 제어 기준' : '수동 제어',
            subtitle: draft.autoControlEnabled
                ? _autoRulesSummary(draft.autoRules)
                : '수동 ON/OFF만 사용합니다.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _busy ? null : _turnOn,
                  child: _BulkPowerButton(
                    label: 'ON',
                    active: _powerOn == true,
                    icon: Symbols.power_settings_new,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _busy ? null : _turnOff,
                  child: _BulkPowerButton(
                    label: 'OFF',
                    active: _powerOn == false,
                    icon: Symbols.power_settings_new,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _busy ? null : _testConnection,
                child: Container(
                  width: 48,
                  height: 44,
                  decoration: BoxDecoration(
                    color: CleanColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Icon(
                    Symbols.sync,
                    color: CleanColors.secondary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PlugModeSelector(
            auto: draft.autoControlEnabled,
            subtitle: _autoModeSubtitle(draft),
            busy: _busy,
            onManualTap: draft.autoControlEnabled ? _toggleAutoControl : null,
            onAutoTap: draft.autoControlEnabled ? null : _toggleAutoControl,
          ),
          const SizedBox(height: 10),
          _InfoListTile(
            icon: Symbols.manage_search,
            title: '자동 제어 판단',
            subtitle: autoHint,
          ),
          if (_autoPolicyMessage != null) ...[
            const SizedBox(height: 10),
            _InfoListTile(
              icon: Symbols.cloud_sync,
              title: '자동 제어 저장 상태',
              subtitle: _autoPolicyMessage!,
            ),
          ],
          if (_settingsUrlMessage != null) ...[
            const SizedBox(height: 10),
            _InfoListTile(
              icon: Symbols.link,
              title: '최근 웹 설정 URL',
              subtitle: _settingsUrlMessage!,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                '제어 이력',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openPlugHistory(deviceId: draft.deviceId),
                child: const Text(
                  '상세',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: CleanColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _PlugHistoryList(rows: rows),
        ],
      ),
    );
  }

  Widget _buildDetailHeader(DisasterDeviceDraft draft) {
    return Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _busy
              ? null
              : () => setState(() {
                    _showPlugDetail = false;
                    _editingPlug = false;
                  }),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1200677D),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(
              Symbols.arrow_back,
              color: CleanColors.secondary,
              size: 21,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(draft.displayName, style: _cardTitle),
              const SizedBox(height: 4),
              const Text('플러그 상세', style: _tinyMuted),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _DetailHeaderAction(
          icon: _editingPlug ? Symbols.close : Symbols.edit,
          onTap:
              _busy ? null : () => setState(() => _editingPlug = !_editingPlug),
        ),
        const SizedBox(width: 8),
        _DetailHeaderAction(
          icon: Symbols.open_in_browser,
          onTap: _busy ? null : _copySettingsUrl,
        ),
        const SizedBox(width: 8),
        _DetailHeaderAction(
          icon: Symbols.delete,
          color: CleanColors.error,
          onTap: _busy ? null : _deleteSelectedPlug,
        ),
      ],
    );
  }

  Widget _buildPlugEditCard(DisasterDeviceDraft draft) {
    final usesMqtt = _controlMethod.toUpperCase().contains('MQTT');
    final mqttTopicText = _topicController.text.trim().isEmpty
        ? _normalizeMqttTopic(draft.mqttTopic)
        : _normalizeMqttTopic(_topicController.text);
    final autoDisabled = _editingAutoDisabled;
    return _SoftCard(
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${draft.displayName} 편집', style: _cardTitle),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _busy
                    ? null
                    : () {
                        _applyDraftToFields(draft);
                        setState(() => _editingPlug = false);
                      },
                child: const Icon(
                  Symbols.close,
                  color: CleanColors.secondary,
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('제어 방식', style: _cardTitle),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AutoMetricChip(
                label: '같은 Wi-Fi',
                selected: !usesMqtt,
                onTap: () => setState(() {
                  final current = _draftFromFields(
                    autoControlEnabled: _draft?.autoControlEnabled,
                  );
                  _controlMethod = '로컬 IP 제어';
                  _draft = current.copyWith(
                    controlMethod: '로컬 IP 제어',
                    updatedAt: DateTime.now(),
                  );
                }),
              ),
              _AutoMetricChip(
                label: '원격 제어',
                selected: usesMqtt,
                onTap: () => setState(() {
                  final current = _draftFromFields(
                    autoControlEnabled: _draft?.autoControlEnabled,
                  );
                  _controlMethod = 'MQTT 제어';
                  if (_topicController.text.trim().isEmpty) {
                    _topicController.text = _mqttTopicForDraft(current);
                  }
                  _draft = current.copyWith(
                    controlMethod: 'MQTT 제어',
                    mqttTopic: _topicController.text.trim(),
                    updatedAt: DateTime.now(),
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PlugInputBox(
            label: '이름',
            controller: _nameController,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (usesMqtt)
            _PlugInputBox(
              label: '플러그 식별 이름',
              controller: _topicController,
              keyboardType: TextInputType.text,
              readOnly: true,
              onChanged: (_) => setState(() {}),
            )
          else
            _PlugInputBox(
              label: '로컬 IP',
              controller: _ipController,
              keyboardType: TextInputType.text,
              onChanged: (_) => setState(() {}),
            ),
          if (usesMqtt) ...[
            const SizedBox(height: 8),
            _SoftCard(
              radius: 14,
              color: CleanColors.surfaceLow,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tasmota MQTT 설정', style: _cardTitle),
                  const SizedBox(height: 8),
                  const Text(
                    'Tasmota의 MQTT 설정 화면에서 플러그마다 아래 값을 입력해 주세요.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                      color: CleanColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    [
                      'Topic  ${mqttTopicText.isEmpty ? '저장 후 자동 배정' : mqttTopicText}',
                      if (mqttTopicText.isNotEmpty)
                        'Client  ${mqttTopicText}_%06X',
                      'Full Topic  %prefix%/%topic%/',
                    ].join('\n'),
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                      color: CleanColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SheetActionButton(
                    label: '식별 이름 복사',
                    onTap: mqttTopicText.isEmpty
                        ? () => _showSnack('저장 후 식별 이름이 배정됩니다.')
                        : () {
                            Clipboard.setData(
                              ClipboardData(text: mqttTopicText),
                            );
                            _showSnack('식별 이름을 복사했습니다.');
                          },
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PlugInputBox(
                  label: '위치',
                  controller: _spaceController,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PlugInputBox(
                  label: '용도',
                  controller: _purposeController,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PlugInputBox(
            label: '상세 위치',
            controller: _addressController,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _PlugInputBox(
            label: '메모',
            controller: _descriptionController,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          const Text('자동 제어 기준', style: _cardTitle),
          const SizedBox(height: 10),
          const Text(
            '여러 항목을 함께 볼 수 있습니다. 하나라도 켜짐 값에 도달하면 켜지고, 모든 항목이 꺼짐 값 아래로 안정되면 꺼집니다.',
            style: _tinyMuted,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AutoMetricChip(
                label: '안함',
                selected: autoDisabled,
                onTap: _setAutoControlDisabledForEdit,
              ),
              _AutoMetricChip(
                label: 'IAQI',
                selected: !autoDisabled && _autoRules.containsKey('iaqi'),
                onTap: () => _setAutoMetric('iaqi'),
              ),
              _AutoMetricChip(
                label: 'CO2',
                selected: !autoDisabled && _autoRules.containsKey('co2'),
                onTap: () => _setAutoMetric('co2'),
              ),
              _AutoMetricChip(
                label: 'CO',
                selected: !autoDisabled && _autoRules.containsKey('co'),
                onTap: () => _setAutoMetric('co'),
              ),
              _AutoMetricChip(
                label: 'PM2.5',
                selected: !autoDisabled && _autoRules.containsKey('pm25'),
                onTap: () => _setAutoMetric('pm25'),
              ),
              _AutoMetricChip(
                label: 'TVOC',
                selected: !autoDisabled && _autoRules.containsKey('tvoc'),
                onTap: () => _setAutoMetric('tvoc'),
              ),
              _AutoMetricChip(
                label: 'NOx',
                selected: !autoDisabled && _autoRules.containsKey('nox'),
                onTap: () => _setAutoMetric('nox'),
              ),
            ],
          ),
          if (autoDisabled) ...[
            const SizedBox(height: 10),
            const Text(
              '자동 제어를 사용하지 않습니다. 플러그는 수동 ON/OFF만 따릅니다.',
              style: _tinyMuted,
            ),
          ] else ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '편집 중: ${_autoMetricLabel(_autoMetric)}',
                    style: _tinyMuted,
                  ),
                ),
                if (_autoRules.length > 1)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _removeSelectedAutoRule,
                    child: const Text(
                      '이 기준 끄기',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: CleanColors.error,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _PlugInputBox(
                    label: '켜짐 값',
                    controller: _autoThresholdController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => _syncOffThresholdFromHysteresis(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PlugInputBox(
                    label: '꺼짐 값',
                    controller: _autoOffThresholdController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    readOnly: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _PlugInputBox(
                    label: '히스테리시스 %',
                    controller: _autoHysteresisController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => _syncOffThresholdFromHysteresis(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PlugInputBox(
                    label: '최소 유지 시간(분)',
                    controller: _autoHoldController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '히스테리시스는 켜짐과 꺼짐이 짧게 반복되지 않도록 만드는 여유 구간입니다. 최소 유지 시간 동안은 한 번 전환된 상태를 유지합니다.',
              style: _tinyMuted,
            ),
          ],
          const SizedBox(height: 14),
          GradientButton(
            label: _busy ? '처리 중' : '저장',
            icon: Symbols.check,
            onTap: _busy ? null : () => _saveDraft(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft ?? _defaultDraft();
    final rows = _activityRows(draft);
    final allRows = _allActivityRows();
    final hasIp = draft.controlMethod.toUpperCase().contains('MQTT')
        ? draft.mqttTopic.trim().isNotEmpty
        : _ipController.text.trim().isNotEmpty;
    final readyCount = _drafts.where((item) {
      if (item.controlMethod.toUpperCase().contains('MQTT')) {
        return item.mqttTopic.trim().isNotEmpty;
      }
      return item.plugIp.trim().isNotEmpty;
    }).length;
    final powerLabel = _powerOn == null
        ? '확인 필요'
        : _powerOn == true
            ? '켜짐'
            : '꺼짐';
    final statusLabel =
        _busy ? '테스트 중' : (_statusMessage ?? draft.lastTestStatus);

    if (_showHistoryDetail) {
      return _buildPlugHistoryDetailScreen();
    }

    return _LegacyPage(
      title: 'CleanAir',
      leading: Symbols.menu,
      trailing: Symbols.account_circle,
      onProfileTap: widget.onProfile,
      children: [
        if (_loading)
          const _SoftCard(
            radius: 14,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: CleanColors.primary),
              ),
            ),
          )
        else ...[
          _SoftCard(
            radius: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('스마트 플러그', style: _cardTitle),
                          SizedBox(height: 5),
                          Text(
                            '등록된 플러그를 선택해 제어합니다.',
                            style: _tinyMuted,
                          ),
                        ],
                      ),
                    ),
                    _StatusPill(
                      text: _drafts.isEmpty
                          ? '0개 등록'
                          : '$readyCount/${_drafts.length} 연결',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _busy ? null : _startNewPlug,
                        child: const _BulkPowerButton(
                          label: '플러그 추가',
                          active: true,
                          icon: Symbols.add,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _busy || _drafts.isEmpty
                            ? null
                            : () => _runAllPower(true),
                        child: const _BulkPowerButton(
                          label: '전체 ON',
                          active: false,
                          icon: Symbols.power_settings_new,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _busy || _drafts.isEmpty
                            ? null
                            : () => _runAllPower(false),
                        child: const _BulkPowerButton(
                          label: '전체 OFF',
                          active: false,
                          icon: Symbols.power_settings_new,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_showPlugDetail) ...[
            const SizedBox(height: 12),
            _buildDetailHeader(draft),
            const SizedBox(height: 12),
            _editingPlug
                ? _buildPlugEditCard(draft)
                : _buildPlugDetailCard(
                    draft,
                    rows,
                    powerLabel,
                    statusLabel,
                    hasIp,
                  ),
          ] else ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  '플러그 목록',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                if (_drafts.isNotEmpty)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _busy
                        ? null
                        : () => setState(() => _editingList = !_editingList),
                    child: Text(
                      _editingList ? '완료' : '편집',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: CleanColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_drafts.isEmpty)
              _SoftCard(
                radius: 14,
                color: CleanColors.surfaceLow,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _InfoListTile(
                      icon: Symbols.power_settings_new,
                      title: '등록된 플러그가 없습니다',
                      subtitle: '플러그 추가를 눌러 이름, 위치, 로컬 IP와 자동 제어 기준을 등록하세요.',
                    ),
                    const SizedBox(height: 12),
                    GradientButton(
                      label: '플러그 추가',
                      icon: Symbols.add,
                      onTap: _busy ? null : _startNewPlug,
                    ),
                  ],
                ),
              )
            else
              for (var i = 0; i < _drafts.length; i += 1) ...[
                _SmartPlugListCard(
                  draft: _drafts[i],
                  selected: false,
                  busy: _busy,
                  editing: _editingList,
                  onTap: () => _selectDevice(i, openDetail: true),
                  onPowerTap: () => _togglePowerForIndex(i),
                  onDeleteTap: () => _deletePlugAt(i),
                ),
                const SizedBox(height: 10),
              ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Text(
                  '전체 제어 이력',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openPlugHistory(),
                  child: const Text(
                    '상세',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: CleanColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _SoftCard(
              radius: 14,
              child: _PlugHistoryList(rows: allRows),
            ),
          ],
        ],
      ],
    );
  }
}

class _DetailHeaderAction extends StatelessWidget {
  const _DetailHeaderAction({
    required this.icon,
    required this.onTap,
    this.color = CleanColors.secondary,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: enabled ? Colors.white : CleanColors.surfaceLow,
          borderRadius: BorderRadius.circular(999),
          boxShadow: enabled
              ? const [
                  BoxShadow(
                    color: Color(0x1000677D),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          color: enabled ? color : CleanColors.outline,
          size: 20,
        ),
      ),
    );
  }
}

class _PlugActivityEntry {
  const _PlugActivityEntry({
    required this.time,
    required this.action,
    required this.status,
    required this.color,
  });

  final String time;
  final String action;
  final String status;
  final Color color;
}

enum _PlugHistoryRange { today, week, month, all }

class _PlugHistoryEntryTile extends StatelessWidget {
  const _PlugHistoryEntryTile({required this.entry});

  final DisasterDeviceHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = entry.ok ? const Color(0xFF16A34A) : CleanColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: CleanColors.outline.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              _formatHistoryDateMinute(entry.createdAt),
              style: const TextStyle(
                fontSize: 10,
                height: 1.25,
                fontWeight: FontWeight.w800,
                color: CleanColors.secondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.displayName.trim().isEmpty
                      ? '스마트 플러그'
                      : entry.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: CleanColors.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  entry.message.trim().isEmpty
                      ? entry.action
                      : entry.message.trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: CleanColors.secondary,
                  ),
                ),
                if (entry.requestLog.trim().isNotEmpty ||
                    entry.responseLog.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  if (entry.requestLog.trim().isNotEmpty)
                    _PlugIoLogLine(label: 'Request', value: entry.requestLog),
                  if (entry.responseLog.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    _PlugIoLogLine(
                      label: 'Response',
                      value: entry.responseLog,
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            entry.status,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlugIoLogLine extends StatelessWidget {
  const _PlugIoLogLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: $value',
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 10,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: CleanColors.outline,
      ),
    );
  }
}

class _PlugHistoryList extends StatelessWidget {
  const _PlugHistoryList({required this.rows});

  final List<({String a, String b, String c, Color color})> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in rows.take(8)) ...[
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: CleanColors.outline.withValues(alpha: 0.08),
                ),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 58,
                  child: Text(
                    row.a,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: CleanColors.secondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.b,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: CleanColors.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  row.c,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: row.color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _AutoMetricChip extends StatelessWidget {
  const _AutoMetricChip({
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
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? CleanColors.primary : CleanColors.surfaceLow,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: selected ? Colors.white : CleanColors.secondary,
          ),
        ),
      ),
    );
  }
}

class _PlugPowerInfoGrid extends StatelessWidget {
  const _PlugPowerInfoGrid({required this.rows});

  final List<({String label, String value})> rows;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      radius: 14,
      color: CleanColors.surfaceLow,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('전력 정보', style: _cardTitle),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rows.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 58,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              final row = rows[index];
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(row.label, style: _tinyMuted),
                    const SizedBox(height: 3),
                    Text(
                      row.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: CleanColors.onSurface,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PlugMiniTelemetry extends StatelessWidget {
  const _PlugMiniTelemetry({
    required this.voltage,
    required this.current,
    required this.power,
  });

  final double? voltage;
  final double? current;
  final double? power;

  @override
  Widget build(BuildContext context) {
    final items = <String>[
      if (voltage != null) '전압 ${_formatNumber(voltage!)}V',
      if (current != null) '전류 ${_formatNumber(current!)}A',
      if (power != null) '전력 ${_formatNumber(power!)}W',
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final item in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              item,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: CleanColors.secondary,
              ),
            ),
          ),
      ],
    );
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

class _SmartPlugListCard extends StatelessWidget {
  const _SmartPlugListCard({
    required this.draft,
    required this.selected,
    required this.busy,
    required this.editing,
    required this.onTap,
    required this.onPowerTap,
    required this.onDeleteTap,
  });

  final DisasterDeviceDraft draft;
  final bool selected;
  final bool busy;
  final bool editing;
  final VoidCallback onTap;
  final VoidCallback onPowerTap;
  final VoidCallback onDeleteTap;

  @override
  Widget build(BuildContext context) {
    final powerOn = draft.currentPowerOn == true;
    final powerKnown = draft.currentPowerOn != null;
    final voltage = _telemetryNumber(draft.telemetry, 'voltage');
    final current = _telemetryNumber(draft.telemetry, 'current');
    final power = _telemetryNumber(draft.telemetry, 'power');
    final location = draft.linkedSpaceName.trim().isEmpty
        ? '위치 미설정'
        : draft.linkedSpaceName.trim();
    final changedAt = draft.lastPowerChangedAt == null
        ? '제어 이력 없음'
        : '${powerOn ? 'ON' : 'OFF'} · ${_formatClock(draft.lastPowerChangedAt!)}';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
        decoration: BoxDecoration(
          color: selected ? Colors.white : CleanColors.surfaceLow,
          borderRadius: BorderRadius.circular(18),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x1600677D),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ]
              : const [],
        ),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 44,
              decoration: BoxDecoration(
                color: powerKnown
                    ? powerOn
                        ? CleanColors.primary
                        : CleanColors.secondary.withValues(alpha: 0.35)
                    : CleanColors.outline.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          draft.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: CleanColors.onSurface,
                          ),
                        ),
                      ),
                      if (draft.autoControlEnabled)
                        const _StatusPill(text: '자동'),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    [
                      location,
                      draft.purpose.trim().isEmpty
                          ? '용도 미설정'
                          : draft.purpose.trim(),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _tinyMuted,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    changedAt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: CleanColors.secondary,
                    ),
                  ),
                  if (voltage != null || current != null || power != null) ...[
                    const SizedBox(height: 8),
                    _PlugMiniTelemetry(
                      voltage: voltage,
                      current: current,
                      power: power,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: busy ? null : (editing ? onDeleteTap : onPowerTap),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: editing
                      ? CleanColors.error.withValues(alpha: 0.08)
                      : powerOn
                          ? CleanColors.primary
                          : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1400677D),
                      blurRadius: 12,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(
                  editing ? Symbols.delete : Symbols.power_settings_new,
                  color: editing
                      ? CleanColors.error
                      : powerOn
                          ? Colors.white
                          : CleanColors.secondary,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static double? _telemetryNumber(Map<String, dynamic> telemetry, String key) {
    final value = telemetry[key];
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }
}

class _ExpansionTileCompat extends StatefulWidget {
  const _ExpansionTileCompat({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  State<_ExpansionTileCompat> createState() => _ExpansionTileCompatState();
}

class _ExpansionTileCompatState extends State<_ExpansionTileCompat> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _open = !_open),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: CleanColors.surfaceLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: CleanColors.secondary,
                  ),
                ),
                const Spacer(),
                Icon(
                  _open
                      ? Symbols.keyboard_arrow_up
                      : Symbols.keyboard_arrow_down,
                  color: CleanColors.secondary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: 12),
          ...widget.children,
        ],
      ],
    );
  }
}

class _BulkPowerButton extends StatelessWidget {
  const _BulkPowerButton({
    required this.label,
    required this.active,
    this.icon,
  });

  final String label;
  final bool active;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? CleanColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? CleanColors.primary
              : CleanColors.secondary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 17,
              color: active ? Colors.white : CleanColors.secondary,
            ),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: active ? Colors.white : CleanColors.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatClock(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}';
}

String _formatHistoryDateMinute(DateTime time) {
  final local = time.toLocal();
  return '${local.year}.${local.month.toString().padLeft(2, '0')}.'
      '${local.day.toString().padLeft(2, '0')}\n'
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _nameController = TextEditingController();
  final _organizationController = TextEditingController();
  final _roleController = TextEditingController();
  final _phoneController = TextEditingController();
  final _defaultFacilityController = TextEditingController();
  bool _busy = false;
  bool _notifyCritical = true;
  String? _message;
  String? _loadedUid;

  @override
  void dispose() {
    _nameController.dispose();
    _organizationController.dispose();
    _roleController.dispose();
    _phoneController.dispose();
    _defaultFacilityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        return _LegacyPage(
          title: '프로필',
          leading: Symbols.arrow_back,
          trailing: user == null ? Symbols.login : Symbols.account_circle,
          onLeadingTap: widget.onBack,
          onTrailingTap: user == null ? _signInWithGoogle : null,
          children: [
            const Text(
              '계정 프로필',
              style: TextStyle(
                fontSize: 30,
                height: 1.12,
                fontWeight: FontWeight.w900,
                color: CleanColors.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              user == null
                  ? 'Google 계정으로 로그인하면 웹 대시보드와 같은 프로필을 사용합니다.'
                  : '앱과 웹 대시보드에서 함께 사용할 정보를 저장합니다.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w700,
                color: CleanColors.secondary,
              ),
            ),
            const SizedBox(height: 18),
            if (user == null) ...[
              const _SoftCard(
                color: CleanColors.surfaceLow,
                child: _InfoListTile(
                  icon: Symbols.account_circle,
                  title: '로그인 필요',
                  subtitle: '시설 관리, 웹 대시보드, 방재 알림 전파를 같은 계정으로 묶습니다.',
                ),
              ),
              const SizedBox(height: 16),
              GradientButton(
                label: _busy ? '로그인 중' : 'Google 계정으로 로그인',
                icon: Symbols.login,
                onTap: _busy ? null : _signInWithGoogle,
              ),
            ] else
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('user_profiles')
                    .doc(user.uid)
                    .snapshots(),
                builder: (context, profileSnapshot) {
                  if (profileSnapshot.hasError) {
                    return const _SoftCard(
                      color: Color(0xFFFFF4F4),
                      child: _InfoListTile(
                        icon: Symbols.warning,
                        title: '프로필을 불러오지 못했습니다',
                        subtitle:
                            'Firestore user_profiles 권한 또는 네트워크 상태를 확인해 주세요.',
                        color: CleanColors.error,
                      ),
                    );
                  }
                  final profile = profileSnapshot.data?.data();
                  _fillControllersOnce(user, profile);
                  final linkedSensorCount =
                      _readIntProfile(profile, 'linkedSensorCount');
                  final linkedPlugCount =
                      _readIntProfile(profile, 'linkedPlugCount');
                  final lastAssetSyncAt =
                      _readProfileTimestamp(profile, 'lastAssetSyncAt');
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SoftCard(
                        color: CleanColors.surfaceLow,
                        child: _InfoListTile(
                          icon: Symbols.account_circle,
                          title: user.email ?? '로그인 계정',
                          subtitle: profile?['organizationName']
                                      ?.toString()
                                      .trim()
                                      .isNotEmpty ==
                                  true
                              ? profile!['organizationName'].toString()
                              : '소속을 입력하세요',
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SoftCard(
                        color: CleanColors.surfaceLow,
                        child: _InfoListTile(
                          icon: Symbols.hub,
                          title: '연결된 장치',
                          subtitle: [
                            '센서 $linkedSensorCount개',
                            '플러그 $linkedPlugCount개',
                            if (lastAssetSyncAt != null)
                              '최근 동기화 ${_timeLabel(lastAssetSyncAt)}',
                          ].join(' · '),
                        ),
                      ),
                      const SizedBox(height: 12),
                      GradientButton(
                        label: _busy ? '동기화 중' : '현재 센서/플러그 동기화',
                        icon: Symbols.sync,
                        colorA: CleanColors.secondary,
                        colorB: CleanColors.primary,
                        onTap: _busy ? null : _syncCurrentAssets,
                      ),
                      const SizedBox(height: 16),
                      _SoftCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _PlugInputBox(
                              label: '이름',
                              controller: _nameController,
                            ),
                            const SizedBox(height: 12),
                            _PlugInputBox(
                              label: '소속',
                              controller: _organizationController,
                            ),
                            const SizedBox(height: 12),
                            _PlugInputBox(
                              label: '역할',
                              controller: _roleController,
                            ),
                            const SizedBox(height: 12),
                            _PlugInputBox(
                              label: '연락처',
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 12),
                            _PlugInputBox(
                              label: '기본 시설 ID',
                              controller: _defaultFacilityController,
                            ),
                            const SizedBox(height: 14),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => setState(
                                () => _notifyCritical = !_notifyCritical,
                              ),
                              child: Row(
                                children: [
                                  Switch(
                                    value: _notifyCritical,
                                    activeThumbColor: CleanColors.primary,
                                    onChanged: (value) => setState(
                                      () => _notifyCritical = value,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      '위급 알림을 이 프로필에 연결',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: CleanColors.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      GradientButton(
                        label: _busy ? '저장 중' : '프로필 저장',
                        icon: Symbols.check,
                        onTap: _busy ? null : _saveProfile,
                      ),
                      const SizedBox(height: 10),
                      GradientButton(
                        label: '로그아웃',
                        icon: Symbols.logout,
                        colorA: CleanColors.secondary,
                        colorB: CleanColors.outline,
                        onTap: _busy ? null : _signOut,
                      ),
                    ],
                  );
                },
              ),
            if (_message != null) ...[
              const SizedBox(height: 14),
              _SoftCard(
                color: CleanColors.surfaceLow,
                child: Text(
                  _message!,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                    color: CleanColors.secondary,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  void _fillControllersOnce(User user, Map<String, dynamic>? profile) {
    if (_loadedUid == user.uid) return;
    _loadedUid = user.uid;
    _nameController.text =
        profile?['displayName']?.toString() ?? user.displayName ?? '';
    _organizationController.text =
        profile?['organizationName']?.toString() ?? '';
    _roleController.text = profile?['role']?.toString() ?? '';
    _phoneController.text = profile?['phone']?.toString() ?? '';
    _defaultFacilityController.text =
        profile?['defaultFacilityId']?.toString() ?? '';
    _notifyCritical = profile?['notifyCritical'] is bool
        ? profile!['notifyCritical'] as bool
        : true;
  }

  int _readIntProfile(Map<String, dynamic>? profile, String key) {
    final value = profile?[key];
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  DateTime? _readProfileTimestamp(Map<String, dynamic>? profile, String key) {
    final value = profile?[key];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Future<void> _signInWithGoogle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = 'Google 로그인 창을 여는 중입니다.';
    });
    try {
      final account = await GoogleSignIn(
        scopes: const <String>['email', 'profile'],
      ).signIn();
      if (account == null) {
        if (mounted) setState(() => _message = '로그인이 취소되었습니다.');
        return;
      }
      final auth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );
      final result = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final user = result.user;
      if (user != null) {
        await _ensureProfile(user);
        await _syncLocalAssetsToProfile();
      }
      if (mounted) setState(() => _message = '로그인되었습니다.');
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(
        () => _message =
            '로그인에 실패했습니다. Firebase 인증 설정을 확인해 주세요. (${error.code}${error.message == null ? '' : ' · ${error.message}'})',
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      final detail = [
        error.code,
        if ((error.message ?? '').trim().isNotEmpty) error.message!.trim(),
        if (error.details != null) error.details.toString(),
      ].join(' · ');
      setState(
        () => _message = 'Google 로그인 설정을 확인해 주세요. $detail',
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () =>
            _message = '로그인에 실패했습니다. Google 로그인 설정과 네트워크 상태를 확인해 주세요. ($error)',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ensureProfile(User user) async {
    final ref =
        FirebaseFirestore.instance.collection('user_profiles').doc(user.uid);
    final snapshot = await ref.get();
    final base = <String, dynamic>{
      'uid': user.uid,
      'email': user.email ?? '',
      'displayName': user.displayName ?? '',
      'photoURL': user.photoURL ?? '',
      'role': '',
      'organizationName': '',
      'phone': '',
      'defaultFacilityId': '',
      'notifyCritical': true,
      'lastLoginAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await ref.set(
      snapshot.exists
          ? base
          : {...base, 'createdAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<ProfileAssetSyncResult> _syncLocalAssetsToProfile() {
    return ProfileAssetLinkService().syncCurrentLocalAssets();
  }

  Future<void> _syncCurrentAssets() async {
    if (_busy) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _message = '로그인 후 동기화할 수 있습니다.');
      return;
    }
    setState(() {
      _busy = true;
      _message = '등록된 센서와 플러그를 프로필에 연결하는 중입니다.';
    });
    try {
      await _ensureProfile(user);
      final result = await _syncLocalAssetsToProfile();
      if (!mounted) return;
      setState(
        () => _message =
            '동기화되었습니다. 센서 ${result.sensorCount}개, 플러그 ${result.plugCount}개가 이 계정에 연결되었습니다.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = '동기화에 실패했습니다. 로그인 상태와 네트워크를 확인하세요. ($error)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _busy) return;
    setState(() {
      _busy = true;
      _message = '프로필을 저장하는 중입니다.';
    });
    try {
      final displayName = _nameController.text.trim();
      await user.updateDisplayName(displayName.isEmpty ? null : displayName);
      await FirebaseFirestore.instance
          .collection('user_profiles')
          .doc(user.uid)
          .set(
        {
          'uid': user.uid,
          'email': user.email ?? '',
          'photoURL': user.photoURL ?? '',
          'displayName': displayName,
          'organizationName': _organizationController.text.trim(),
          'role': _roleController.text.trim(),
          'phone': _phoneController.text.trim(),
          'defaultFacilityId': _defaultFacilityController.text.trim(),
          'notifyCritical': _notifyCritical,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      final result = await _syncLocalAssetsToProfile();
      setState(
        () => _message =
            '저장되었습니다. 센서 ${result.sensorCount}개, 플러그 ${result.plugCount}개가 이 계정에 연결되었습니다.',
      );
    } catch (error) {
      setState(() => _message = '저장에 실패했습니다. 네트워크와 로그인 상태를 확인하세요. ($error)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _busy = true;
      _message = '로그아웃하는 중입니다.';
    });
    try {
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();
      _loadedUid = null;
      setState(() => _message = '로그아웃되었습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ProfileShortcutTile extends StatelessWidget {
  const _ProfileShortcutTile();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        return _InfoListTile(
          icon: Symbols.person,
          title: user?.displayName?.trim().isNotEmpty == true
              ? user!.displayName!
              : '사용자',
          subtitle: user?.email ?? '웹 대시보드와 같은 Google 계정으로 로그인하세요.',
        );
      },
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    this.onAlertSettings,
    this.onLocationSettings,
    this.onConnectSensor,
    this.onPlugSettings,
    this.onAirGradientSettings,
    this.onProfile,
  });

  final VoidCallback? onAlertSettings;
  final VoidCallback? onLocationSettings;
  final VoidCallback? onConnectSensor;
  final VoidCallback? onPlugSettings;
  final VoidCallback? onAirGradientSettings;
  final VoidCallback? onProfile;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<NotificationPreferencesController>().value;
    final bindingController = context.watch<DeviceBindingControllerV2>();
    final binding = bindingController.value;
    final push = context.watch<PushNotificationServiceV2>();

    return _LegacyPage(
      title: 'CleanAir',
      leading: Symbols.air,
      trailing: Symbols.account_circle,
      children: [
        const Text(
          '설정',
          style: TextStyle(
            fontSize: 32,
            height: 1.12,
            fontWeight: FontWeight.w900,
            color: CleanColors.onSurface,
          ),
        ),
        const SizedBox(height: 18),
        _SettingsListCard(
          children: [
            _SettingsListTile(
              icon: Symbols.notifications_active,
              title: '알림',
              subtitle: prefs.alertsEnabled
                  ? '${_settingsSeverityShortLabel(prefs.minimumSeverityPriority)}, ${prefs.notificationIntervalMinutes}분 간격'
                  : '위험 알림 꺼짐',
              onTap: widget.onAlertSettings,
            ),
            const _SettingsDivider(),
            FutureBuilder<SensorLocationDraft?>(
              future: _loadLocationForBinding(binding),
              builder: (context, snapshot) {
                final location = snapshot.data;
                final sensorCount = bindingController.bindings.length;
                final title = binding.isBound ? '센서 및 위치' : '센서 연결';
                final subtitle = binding.isBound
                    ? [
                        if (sensorCount > 1) '$sensorCount개 등록',
                        binding.deviceId,
                        location?.spaceName,
                        location?.detailLocation,
                      ]
                        .whereType<String>()
                        .where((v) => v.trim().isNotEmpty)
                        .join(' · ')
                    : 'AirGradient 센서를 먼저 연결하세요';
                return _SettingsListTile(
                  icon: Symbols.sensors,
                  title: title,
                  subtitle: subtitle.isEmpty ? '설치 위치를 등록하세요' : subtitle,
                  onTap: () => _showSensorManagementSheet(context),
                );
              },
            ),
            const _SettingsDivider(),
            _SettingsListTile(
              icon: Symbols.settings_input_component,
              title: 'AirGradient',
              subtitle: '로컬 IP, 웹 설정, 연결 테스트',
              onTap: widget.onAirGradientSettings,
            ),
            const _SettingsDivider(),
            _SettingsListTile(
              icon: Symbols.power_settings_new,
              title: '플러그 및 방재 장치',
              subtitle: 'Tasmota 등록, 연결 테스트, ON/OFF 제어',
              onTap: widget.onPlugSettings,
            ),
            const _SettingsDivider(),
            _SettingsListTile(
              icon: Symbols.phonelink_lock,
              title: '권한 및 백그라운드',
              subtitle: '알림 권한, 배터리 최적화 제외 상태',
              onTap: () => _showPermissionGuideSheet(context),
            ),
            const _SettingsDivider(),
            _SettingsListTile(
              icon: Symbols.info,
              title: '앱 정보',
              subtitle: push.lastRegistrationAt == null
                  ? '버전, 기기 등록 상태'
                  : '최근 동기화 ${_timeLabel(push.lastRegistrationAt!)}',
              onTap: () => _showAppInfoSheet(context),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _SoftCard(
          color: CleanColors.surfaceLow,
          child: _ProfileShortcutTile(),
        ),
        const SizedBox(height: 10),
        GradientButton(
          label: '프로필 열기',
          icon: Symbols.person,
          onTap: widget.onProfile,
        ),
      ],
    );
  }

  void _showSensorManagementSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Consumer<DeviceBindingControllerV2>(
          builder: (context, controller, _) {
            final active = controller.value;
            final bindings = controller.bindings;
            return SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x2200677D),
                      blurRadius: 28,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.78,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '센서 및 위치',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: CleanColors.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(
                              Symbols.close,
                              color: CleanColors.secondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        active.isBound
                            ? '표시할 센서를 선택하면 홈, 상세, 건강, 비교 화면이 해당 센서 데이터로 전환됩니다.'
                            : 'AirGradient 센서를 등록하면 이곳에서 여러 센서를 전환할 수 있습니다.',
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                          color: CleanColors.secondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (bindings.isEmpty)
                        const _SoftCard(
                          color: CleanColors.surfaceLow,
                          radius: 16,
                          child: _InfoListTile(
                            icon: Symbols.add_link,
                            title: '등록된 센서가 없습니다',
                            subtitle: 'PIN 또는 주변 검색으로 첫 센서를 연결하세요.',
                          ),
                        )
                      else
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: bindings.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final record = bindings[index];
                              final selected =
                                  record.deviceId == active.deviceId;
                              return _SensorBindingTile(
                                record: record,
                                selected: selected,
                                onSelect: selected
                                    ? null
                                    : () => unawaited(
                                          controller.selectBinding(
                                            record.deviceId,
                                          ),
                                        ),
                                onLocation: () async {
                                  await controller.selectBinding(
                                    record.deviceId,
                                  );
                                  if (!sheetContext.mounted) return;
                                  Navigator.of(sheetContext).pop();
                                  widget.onLocationSettings?.call();
                                },
                                onRename: () => _showSensorRenameSheet(
                                  sheetContext,
                                  controller,
                                  record,
                                ),
                                onDelete: () => unawaited(
                                  _removeSensorBinding(
                                    sheetContext,
                                    controller,
                                    record,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                Navigator.of(sheetContext).pop();
                                widget.onConnectSensor?.call();
                              },
                              child: const _BulkPowerButton(
                                label: '센서 추가',
                                active: true,
                                icon: Symbols.add_link,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: active.isBound
                                  ? () {
                                      Navigator.of(sheetContext).pop();
                                      widget.onLocationSettings?.call();
                                    }
                                  : null,
                              child: _BulkPowerButton(
                                label: '위치 설정',
                                active: active.isBound,
                                icon: Symbols.home_pin,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _removeSensorBinding(
    BuildContext sheetContext,
    DeviceBindingControllerV2 controller,
    DeviceBindingRecordV2 record,
  ) async {
    await controller.removeBinding(record.deviceId);
    unawaited(_syncProfileAssetLinksIfSignedIn());
    if (!sheetContext.mounted) return;
    ScaffoldMessenger.of(sheetContext).showSnackBar(
      SnackBar(content: Text('${record.label} 센서 등록을 삭제했습니다.')),
    );
  }

  void _showSensorRenameSheet(
    BuildContext parentSheetContext,
    DeviceBindingControllerV2 controller,
    DeviceBindingRecordV2 record,
  ) {
    final nameController = TextEditingController(text: record.displayName);
    showModalBottomSheet<void>(
      context: parentSheetContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x2200677D),
                    blurRadius: 28,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '센서 이름',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: CleanColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    record.deviceId,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: CleanColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      hintText: '예: 거실 센서, 실험실 센서',
                      filled: true,
                      fillColor: CleanColors.surfaceLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: CleanColors.onSurface,
                    ),
                    onSubmitted: (_) => unawaited(
                      _saveSensorName(
                        context,
                        controller,
                        record,
                        nameController.text,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.of(context).pop(),
                          child: const _BulkPowerButton(
                            label: '취소',
                            active: false,
                            icon: Symbols.close,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => unawaited(
                            _saveSensorName(
                              context,
                              controller,
                              record,
                              nameController.text,
                            ),
                          ),
                          child: const _BulkPowerButton(
                            label: '저장',
                            active: true,
                            icon: Symbols.check,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(nameController.dispose);
  }

  Future<void> _saveSensorName(
    BuildContext context,
    DeviceBindingControllerV2 controller,
    DeviceBindingRecordV2 record,
    String rawName,
  ) async {
    await controller.updateBindingDetails(
      deviceId: record.deviceId,
      displayName: rawName.trim(),
    );
    unawaited(_syncProfileAssetLinksIfSignedIn());
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  void _showAppInfoSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const _InfoSheet(
        title: '앱 정보',
        children: [
          _InfoListTile(
            icon: Symbols.air,
            title: 'CleanAir',
            subtitle: '실내 공기질 모니터링 및 장치 제어 앱',
          ),
          SizedBox(height: 12),
          _InfoListTile(
            icon: Symbols.verified,
            title: '앱 버전',
            subtitle: 'capstone alpha 0.1.0',
          ),
          SizedBox(height: 12),
          _InfoListTile(
            icon: Symbols.privacy_tip,
            title: '개인정보',
            subtitle: '센서 식별값과 알림 토큰은 진단용 화면에 표시하지 않습니다.',
          ),
          SizedBox(height: 12),
          _InfoListTile(
            icon: Symbols.settings,
            title: '설정',
            subtitle: '알림, 권한, 센서 및 플러그 설정은 설정 메뉴에서 조정할 수 있습니다.',
          ),
        ],
      ),
    );
  }

  void _showPermissionGuideSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => _InfoSheet(
          title: '권한 및 백그라운드',
          children: [
            FutureBuilder<_BackgroundPermissionState>(
              future: _loadBackgroundPermissionState(context),
              builder: (context, snapshot) {
                final state = snapshot.data;
                final notification = state?.notification;
                final battery = state?.batteryOptimization;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _InfoListTile(
                      icon: Symbols.notifications_active,
                      title: '알림 권한',
                      subtitle: _permissionStatusLabel(notification),
                      color: notification?.isGranted == true
                          ? CleanColors.primary
                          : CleanColors.tertiary,
                    ),
                    const SizedBox(height: 12),
                    _InfoListTile(
                      icon: Symbols.battery_android_shield,
                      title: '배터리 최적화 제외',
                      subtitle: _permissionStatusLabel(battery),
                      color: battery?.isGranted == true
                          ? CleanColors.primary
                          : CleanColors.tertiary,
                    ),
                    const SizedBox(height: 12),
                    _InfoListTile(
                      icon: Symbols.sensors,
                      title: '백그라운드 센서 수신',
                      subtitle: state == null
                          ? '상태를 확인하는 중입니다.'
                          : state.enabled
                              ? (state.running ? '실행 중' : '켜짐 · 센서 연결 후 자동 실행')
                              : '꺼짐',
                      color: state?.running == true
                          ? CleanColors.primary
                          : CleanColors.secondary,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '알림은 서버에서 전달되고, 백그라운드 센서 수신은 앱이 닫힌 동안에도 최근 측정값을 기기에 저장합니다. 일부 제조사 절전 정책에서는 절전 제외가 필요할 수 있습니다.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        color: CleanColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _SheetActionButton(
                            label: '알림 켜기',
                            onTap: () => unawaited(
                              context
                                  .read<PushNotificationServiceV2>()
                                  .requestNotificationPermissionAndRefresh()
                                  .whenComplete(() => setSheetState(() {})),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SheetActionButton(
                            label: '절전 제외',
                            onTap: () => unawaited(
                              context
                                  .read<BackgroundServiceManager>()
                                  .requestBatteryOptimizationExemption()
                                  .whenComplete(() => setSheetState(() {})),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _SheetActionButton(
                            label: '수신 시작',
                            onTap: () => unawaited(
                              context
                                  .read<BackgroundServiceManager>()
                                  .start()
                                  .whenComplete(() => setSheetState(() {})),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SheetActionButton(
                            label: '수신 중지',
                            onTap: () => unawaited(
                              context
                                  .read<BackgroundServiceManager>()
                                  .stop()
                                  .whenComplete(() => setSheetState(() {})),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _SheetActionButton(
                      label: '앱 권한 설정 열기',
                      onTap: () => unawaited(app_permission.openAppSettings()),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<_BackgroundPermissionState> _loadBackgroundPermissionState(
    BuildContext context,
  ) async {
    final backgroundService = context.read<BackgroundServiceManager>();
    final results = await Future.wait<Object>([
      app_permission.Permission.notification.status,
      app_permission.Permission.ignoreBatteryOptimizations.status,
      backgroundService.isEnabled(),
      backgroundService.isRunning(),
    ]);
    return _BackgroundPermissionState(
      notification: results[0] as app_permission.PermissionStatus,
      batteryOptimization: results[1] as app_permission.PermissionStatus,
      enabled: results[2] as bool,
      running: results[3] as bool,
    );
  }

  String _permissionStatusLabel(app_permission.PermissionStatus? status) {
    if (status == null) return '상태를 확인하는 중입니다.';
    if (status.isGranted) return '허용됨';
    if (status.isPermanentlyDenied) return '설정 앱에서 직접 허용해야 합니다.';
    if (status.isDenied) return '아직 허용되지 않았습니다.';
    if (status.isRestricted) return '기기 정책으로 제한되어 있습니다.';
    if (status.isLimited) return '제한적으로 허용되어 있습니다.';
    return status.name;
  }
}

class _SheetActionButton extends StatelessWidget {
  const _SheetActionButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CleanColors.primary,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackgroundPermissionState {
  const _BackgroundPermissionState({
    required this.notification,
    required this.batteryOptimization,
    required this.enabled,
    required this.running,
  });

  final app_permission.PermissionStatus notification;
  final app_permission.PermissionStatus batteryOptimization;
  final bool enabled;
  final bool running;
}

class _SettingsListCard extends StatelessWidget {
  const _SettingsListCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      padding: EdgeInsets.zero,
      child: Column(children: children),
    );
  }
}

class _SensorBindingTile extends StatelessWidget {
  const _SensorBindingTile({
    required this.record,
    required this.selected,
    this.onSelect,
    this.onLocation,
    this.onRename,
    this.onDelete,
  });

  final DeviceBindingRecordV2 record;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback? onLocation;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SensorLocationDraft?>(
      future: SensorLocationStorage().loadForSensor(record.deviceId),
      builder: (context, snapshot) {
        final location = snapshot.data;
        final title = record.label;
        final subtitle = [
          record.deviceId,
          location?.spaceName,
          location?.detailLocation,
          if (record.localIp.trim().isNotEmpty) record.localIp.trim(),
        ]
            .whereType<String>()
            .where((value) => value.trim().isNotEmpty)
            .join(' · ');
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE9F8FB) : CleanColors.surfaceLow,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: selected ? CleanColors.primary : Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      selected ? Symbols.radio_button_checked : Symbols.sensors,
                      size: 22,
                      color: selected ? Colors.white : CleanColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: CleanColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle.isEmpty ? '위치 정보 없음' : subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: CleanColors.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    const _StatusPill(text: '표시 중')
                  else
                    TextButton(
                      onPressed: onSelect,
                      child: const Text('선택'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (onLocation != null || onRename != null || onDelete != null)
                Row(
                  children: [
                    if (onLocation != null) ...[
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onLocation,
                          child: const _BulkPowerButton(
                            label: '위치',
                            active: false,
                            icon: Symbols.home_pin,
                          ),
                        ),
                      ),
                      if (onRename != null || onDelete != null)
                        const SizedBox(width: 10),
                    ],
                    if (onRename != null) ...[
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onRename,
                          child: const _BulkPowerButton(
                            label: '이름',
                            active: false,
                            icon: Symbols.edit,
                          ),
                        ),
                      ),
                      if (onDelete != null) const SizedBox(width: 10),
                    ],
                    if (onDelete != null)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onDelete,
                        child: Container(
                          width: 48,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Icon(
                            Symbols.delete,
                            size: 20,
                            color: Color(0xFFB64B4B),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingsListTile extends StatelessWidget {
  const _SettingsListTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: CleanColors.surfaceLow,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 22, color: CleanColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: CleanColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: CleanColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 10),
              const Icon(
                Symbols.chevron_right,
                size: 20,
                color: CleanColors.outlineVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 74),
      child: Divider(height: 1, thickness: 1, color: CleanColors.surfaceHigh),
    );
  }
}

class _InfoSheet extends StatelessWidget {
  const _InfoSheet({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.86;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A00677D),
                blurRadius: 22,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Handle(),
                const SizedBox(height: 16),
                Text(title, style: _cardTitle),
                const SizedBox(height: 16),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _settingsSeverityShortLabel(int priority) {
  return switch (priority) {
    1 => '주의 이상',
    3 => '위험만',
    _ => '나쁨 이상',
  };
}

String _fireRiskMinimumLevelShortLabel(String level) {
  return switch (level) {
    'warning' => '경고 이상',
    'fire_suspected' => '위급 상황만',
    _ => '강한 경고 이상',
  };
}

String _fireRiskMinimumLevelLabel(String level) {
  return switch (level) {
    'warning' => '경고 단계부터 알림을 수신합니다.',
    'fire_suspected' => '화재 의심 또는 CO 위험 상황만 수신합니다.',
    _ => '강한 경고 단계부터 알림을 수신합니다.',
  };
}

class AlertSettingsScreen extends StatefulWidget {
  const AlertSettingsScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<AlertSettingsScreen> createState() => _AlertSettingsScreenState();
}

class _AlertSettingsScreenState extends State<AlertSettingsScreen> {
  bool _saving = false;
  String? _saveMessage;

  Future<void> _savePreference(
    String message,
    Future<void> Function(NotificationPreferencesController controller) save,
  ) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveMessage = '알림 설정을 저장하는 중입니다.';
    });

    final controller = context.read<NotificationPreferencesController>();
    final push = context.read<PushNotificationServiceV2>();
    final messenger = ScaffoldMessenger.of(context);
    var result = message;
    try {
      await save(controller);
      await push.syncNotificationPreferences(controller.value);
    } catch (_) {
      result = '알림 설정 저장에 실패했습니다. 다시 시도하세요.';
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      _saveMessage = result;
    });
    messenger.showSnackBar(
      SnackBar(content: Text(result), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _startSlackConnect() async {
    if (_saving) return;
    final push = context.read<PushNotificationServiceV2>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _saveMessage = 'Slack 연결 주소를 준비하는 중입니다.';
    });
    final uri = await push.slackConnectUri();
    if (!mounted) return;
    if (uri == null) {
      setState(() {
        _saving = false;
        _saveMessage = 'Slack 연결을 시작할 수 없습니다.';
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Slack 연결을 시작할 수 없습니다. 서버 설정을 확인해 주세요.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!opened) {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      setState(() {
        _saving = false;
        _saveMessage = 'Slack 연결 주소를 복사했습니다.';
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text('브라우저를 열지 못해 Slack 연결 주소를 복사했습니다.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    setState(() {
      _saving = false;
      _saveMessage = 'Slack 승인 후 앱으로 돌아와 연결 확인을 눌러 주세요.';
    });
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Slack 승인 후 앱으로 돌아와 연결 확인을 눌러 주세요.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _refreshSlackConnection() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveMessage = 'Slack 연결 상태를 확인하는 중입니다.';
    });
    final push = context.read<PushNotificationServiceV2>();
    final controller = context.read<NotificationPreferencesController>();
    final messenger = ScaffoldMessenger.of(context);
    var message = 'Slack 연결 정보를 찾지 못했습니다.';
    try {
      final serverPrefs = await push.fetchServerDevicePreferences();
      final url = serverPrefs?['slackWebhookUrl']?.toString().trim() ?? '';
      await controller.setSlackWebhookUrl(url);
      message =
          url.isEmpty ? 'Slack 채널이 아직 연결되지 않았습니다.' : 'Slack 채널이 연결되어 있습니다.';
    } catch (_) {
      message = 'Slack 연결 상태 확인에 실패했습니다.';
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saveMessage = message;
    });
    messenger.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _sendSlackTest() async {
    if (_saving) return;
    final push = context.read<PushNotificationServiceV2>();
    final messenger = ScaffoldMessenger.of(context);
    final serverPrefs = await push.fetchServerDevicePreferences();
    final url = serverPrefs?['slackWebhookUrl']?.toString().trim() ?? '';
    if (!mounted) return;
    await context
        .read<NotificationPreferencesController>()
        .setSlackWebhookUrl(url);
    if (url.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Slack 채널을 먼저 연결해 주세요.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() {
      _saving = true;
      _saveMessage = 'Slack 테스트 알림을 보내는 중입니다.';
    });
    try {
      final ok = await push.sendSlackTestAlert();
      final message = ok
          ? 'Slack 테스트 알림을 보냈습니다.'
          : push.lastRegistrationMessage ?? 'Slack 테스트 전송에 실패했습니다.';
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveMessage = message;
      });
      messenger.showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveMessage = 'Slack 테스트 전송 실패: $error';
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(_saveMessage!),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final notificationController =
        context.watch<NotificationPreferencesController>();
    final prefs = notificationController.value;
    final binding = context.watch<DeviceBindingControllerV2>().value;
    final alertTypeCount = NotificationPreferences.supportedAlertTypes.length;
    return _LegacyPage(
      title: '알림 설정',
      leading: Symbols.arrow_back,
      trailing: Symbols.notifications_active,
      onLeadingTap: widget.onBack,
      children: [
        const Text(
          '알림 설정',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: CleanColors.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '받을 알림의 종류와 시간을 조정합니다.',
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            fontWeight: FontWeight.w600,
            color: CleanColors.secondary,
          ),
        ),
        const SizedBox(height: 20),
        if (_saving || _saveMessage != null) ...[
          _SoftCard(
            color: _saving ? CleanColors.surfaceLow : Colors.white,
            child: _InfoListTile(
              icon: _saving ? Symbols.sync : Symbols.check_circle,
              title: _saving ? '저장 중' : '최근 저장 결과',
              subtitle: _saveMessage ?? '기존 알림 설정 저장소에 반영합니다.',
            ),
          ),
          const SizedBox(height: 16),
        ],
        _SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('기본 설정', style: _cardTitle),
              const SizedBox(height: 18),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => unawaited(
                  _savePreference(
                    prefs.alertsEnabled ? '위험 알림을 껐습니다.' : '위험 알림을 켰습니다.',
                    (controller) =>
                        controller.setAlertsEnabled(!prefs.alertsEnabled),
                  ),
                ),
                child: _ToggleRow(
                  title: '위험 수치 알림',
                  subtitle: prefs.alertsEnabled
                      ? '센서 경보와 건강 지표 알림을 받습니다'
                      : '현재 위험 알림이 꺼져 있습니다',
                  enabled: prefs.alertsEnabled,
                ),
              ),
              const SizedBox(height: 18),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final muted = prefs.mutedTypes['plug_control'] ?? false;
                  unawaited(
                    _savePreference(
                      muted ? '플러그 제어 알림을 켰습니다.' : '플러그 제어 알림을 껐습니다.',
                      (controller) =>
                          controller.setMutedType('plug_control', !muted),
                    ),
                  );
                },
                child: _ToggleRow(
                  title: '플러그 제어 알림',
                  subtitle: (prefs.mutedTypes['plug_control'] ?? false)
                      ? '수동/자동 제어 결과를 알리지 않습니다'
                      : '수동/자동 제어 결과를 알려줍니다',
                  enabled: !(prefs.mutedTypes['plug_control'] ?? false),
                ),
              ),
              const SizedBox(height: 18),
              _InfoListTile(
                icon: Symbols.warning,
                title: '알림 민감도',
                subtitle: _severityLabel(prefs.minimumSeverityPriority),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _AlertSeverityChip(
                    label: '주의 이상',
                    selected: prefs.minimumSeverityPriority == 1,
                    onTap: () => unawaited(
                      _savePreference(
                        '주의 단계부터 알림을 받습니다.',
                        (controller) =>
                            controller.setMinimumSeverityPriority(1),
                      ),
                    ),
                  ),
                  _AlertSeverityChip(
                    label: '나쁨 이상',
                    selected: prefs.minimumSeverityPriority == 2,
                    onTap: () => unawaited(
                      _savePreference(
                        '나쁨 단계부터 알림을 수신합니다.',
                        (controller) =>
                            controller.setMinimumSeverityPriority(2),
                      ),
                    ),
                  ),
                  _AlertSeverityChip(
                    label: '위험만',
                    selected: prefs.minimumSeverityPriority == 3,
                    onTap: () => unawaited(
                      _savePreference(
                        '위험 단계 알림만 수신합니다.',
                        (controller) =>
                            controller.setMinimumSeverityPriority(3),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _InfoListTile(
                icon: Symbols.local_fire_department,
                title: '방재 알림 기준',
                subtitle: _fireRiskMinimumLevelLabel(
                  prefs.fireRiskMinimumLevel,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _AlertSeverityChip(
                    label: '경고 이상',
                    selected: prefs.fireRiskMinimumLevel == 'warning',
                    onTap: () => unawaited(
                      _savePreference(
                        '경고 단계부터 방재 알림을 수신합니다.',
                        (controller) =>
                            controller.setFireRiskMinimumLevel('warning'),
                      ),
                    ),
                  ),
                  _AlertSeverityChip(
                    label: '강한 경고 이상',
                    selected: prefs.fireRiskMinimumLevel == 'strong_warning',
                    onTap: () => unawaited(
                      _savePreference(
                        '강한 경고 단계부터 방재 알림을 수신합니다.',
                        (controller) => controller
                            .setFireRiskMinimumLevel('strong_warning'),
                      ),
                    ),
                  ),
                  _AlertSeverityChip(
                    label: '화재 의심/CO 위험',
                    selected: prefs.fireRiskMinimumLevel == 'fire_suspected',
                    onTap: () => unawaited(
                      _savePreference(
                        '화재 의심 또는 CO 위험 상황만 수신합니다.',
                        (controller) => controller
                            .setFireRiskMinimumLevel('fire_suspected'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => unawaited(
                  _savePreference(
                    prefs.quietHoursEnabled
                        ? '방해 금지 시간을 껐습니다.'
                        : '방해 금지 시간을 켰습니다.',
                    (controller) => controller
                        .setQuietHoursEnabled(!prefs.quietHoursEnabled),
                  ),
                ),
                child: _ToggleRow(
                  title: '방해 금지 시간',
                  subtitle: _quietHoursLabel(prefs),
                  enabled: prefs.quietHoursEnabled,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => unawaited(
                        _savePreference(
                          '방해 금지 시작 시간을 저장했습니다.',
                          (controller) => controller.updateQuietHours(
                            enabled: true,
                            startMinutes: prefs.quietHoursStartMinutes + 60,
                          ),
                        ),
                      ),
                      child: _MiniMetric(
                        label: '시작 시간',
                        value: _formatMinutes(prefs.quietHoursStartMinutes),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => unawaited(
                        _savePreference(
                          '방해 금지 종료 시간을 저장했습니다.',
                          (controller) => controller.updateQuietHours(
                            enabled: true,
                            endMinutes: prefs.quietHoursEndMinutes + 60,
                          ),
                        ),
                      ),
                      child: _MiniMetric(
                        label: '종료 시간',
                        value: _formatMinutes(prefs.quietHoursEndMinutes),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _InfoListTile(
                icon: Symbols.schedule,
                title: '반복 알림 간격',
                subtitle:
                    '같은 종류의 경보는 ${prefs.notificationIntervalMinutes}분 안에 다시 울리지 않습니다.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in const [5, 15, 30, 60])
                    _AlertIntervalChip(
                      minutes: minutes,
                      selected: prefs.notificationIntervalMinutes == minutes,
                      onTap: () => unawaited(
                        _savePreference(
                          '반복 알림 간격을 $minutes분으로 저장했습니다.',
                          (controller) =>
                              controller.setNotificationIntervalMinutes(
                            minutes,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (prefs.snoozedUntil != null) ...[
                const SizedBox(height: 18),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => unawaited(
                    _savePreference(
                      '알림 일시 중지를 해제했습니다.',
                      (controller) => controller.clearSnooze(),
                    ),
                  ),
                  child: _InfoListTile(
                    icon: Symbols.notifications_paused,
                    title: '알림 일시 중지',
                    subtitle:
                        '${_formatDateTime(prefs.snoozedUntil!)}까지 중지됨 · 탭해서 해제',
                  ),
                ),
              ] else ...[
                const SizedBox(height: 18),
                GradientButton(
                  label: '1시간 알림 일시 중지',
                  icon: Symbols.notifications_paused,
                  onTap: () => unawaited(
                    _savePreference(
                      '1시간 동안 알림을 일시 중지했습니다.',
                      (controller) => controller.snoozeFor(
                        const Duration(hours: 1),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Slack 외부 알림', style: _cardTitle),
              const SizedBox(height: 10),
              Text(
                prefs.slackWebhookUrl.trim().isEmpty
                    ? 'Slack 채널을 연결하면 경고와 위급 알림을 앱 밖에서도 받을 수 있습니다.'
                    : 'Slack 채널 연결됨 · 경고와 위급 알림을 Slack으로도 보냅니다.',
                style: _tinyMuted,
              ),
              const SizedBox(height: 12),
              GradientButton(
                label: prefs.slackWebhookUrl.trim().isEmpty
                    ? 'Slack 연결하기'
                    : 'Slack 다시 연결',
                icon: Symbols.add_link,
                onTap: () => unawaited(_startSlackConnect()),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _saving
                          ? null
                          : () => unawaited(
                                prefs.slackWebhookUrl.trim().isEmpty
                                    ? _refreshSlackConnection()
                                    : _sendSlackTest(),
                              ),
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: CleanColors.primaryFixed,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Center(
                          child: Text(
                            prefs.slackWebhookUrl.trim().isEmpty
                                ? '연결 확인'
                                : '테스트',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: CleanColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: prefs.slackWebhookUrl.trim().isEmpty
                          ? null
                          : () => unawaited(
                                _savePreference(
                                  'Slack 외부 알림을 해제했습니다.',
                                  (controller) =>
                                      controller.setSlackWebhookUrl(''),
                                ),
                              ),
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: CleanColors.surfaceLow,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Center(
                          child: Text(
                            '해제',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: CleanColors.secondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SoftCard(
          color: CleanColors.surfaceLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Expanded(
                    child: _InfoListTile(
                      icon: Symbols.tune,
                      title: '알림 기준',
                      subtitle: '선택한 단계 이상일 때만 알림을 받습니다.',
                    ),
                  ),
                  Text(
                    '$alertTypeCount',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: CleanColors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 7),
                    child: Text(
                      'types',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: CleanColors.secondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _ThresholdBar(
                  minimumSeverityPriority: prefs.minimumSeverityPriority),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('알림 유형', style: _cardTitle),
              const SizedBox(height: 18),
              for (var i = 0; i < _alertTypeItems.length; i++) ...[
                _AlertTypeToggle(
                  controller: notificationController,
                  prefs: prefs,
                  type: _alertTypeItems[i].type,
                  title: _alertTypeItems[i].title,
                  subtitle: _alertTypeItems[i].subtitle,
                  fireRiskMinimumLevel: prefs.fireRiskMinimumLevel,
                  onSeverityChanged: (priority) => unawaited(
                    _savePreference(
                      '${_alertTypeItems[i].title} 알림 민감도를 ${_settingsSeverityShortLabel(priority)}으로 저장했습니다.',
                      (controller) => controller.setMinimumSeverityForType(
                        _alertTypeItems[i].type,
                        priority,
                      ),
                    ),
                  ),
                  onMutedChanged: (muted) => unawaited(
                    _savePreference(
                      muted
                          ? '${_alertTypeItems[i].title} 알림을 껐습니다.'
                          : '${_alertTypeItems[i].title} 알림을 켰습니다.',
                      (controller) => controller.setMutedType(
                          _alertTypeItems[i].type, muted),
                    ),
                  ),
                ),
                if (i != _alertTypeItems.length - 1) const SizedBox(height: 18),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '알림 대상',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        FutureBuilder<SensorLocationDraft?>(
          future: _loadLocationForBinding(binding),
          builder: (context, snapshot) {
            final location = snapshot.data;
            return _SoftCard(
              child: Column(
                children: [
                  _InfoListTile(
                    icon: Symbols.sensors,
                    title: binding.isBound ? binding.deviceId : '센서 연결 필요',
                    subtitle: binding.isBound
                        ? binding.firestoreDocPath
                        : 'PIN 또는 주변 센서 검색으로 알림 대상을 연결하세요',
                  ),
                  const SizedBox(height: 12),
                  _InfoListTile(
                    icon: Symbols.home,
                    title: location?.spaceName ?? '위치 등록 필요',
                    subtitle: location == null
                        ? '위치를 저장하면 알림 메시지와 방재 판단에 표시됩니다'
                        : [
                            location.buildingName,
                            location.floor,
                            location.detailLocation,
                          ]
                            .where((value) => value.trim().isNotEmpty)
                            .join(' · '),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  String _quietHoursLabel(NotificationPreferences prefs) {
    final start = _formatMinutes(prefs.quietHoursStartMinutes);
    final end = _formatMinutes(prefs.quietHoursEndMinutes);
    return prefs.quietHoursEnabled
        ? '$start - $end 동안 조용히 유지'
        : '$start - $end 설정됨';
  }

  String _formatMinutes(int minutes) {
    final normalized = minutes % (24 * 60);
    final hour = normalized ~/ 60;
    final minute = normalized % 60;
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime time) {
    final local = time.toLocal();
    return '${local.month}/${local.day} '
        '${_formatMinutes(local.hour * 60 + local.minute)}';
  }

  String _severityLabel(int priority) {
    return switch (priority) {
      1 => '주의 단계부터 알림을 수신합니다.',
      3 => '위험 단계 알림만 수신합니다.',
      _ => '나쁨 단계부터 알림을 수신합니다.',
    };
  }
}

class ControlHysteresisScreen extends StatefulWidget {
  const ControlHysteresisScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<ControlHysteresisScreen> createState() =>
      _ControlHysteresisScreenState();
}

class _ControlHysteresisScreenState extends State<ControlHysteresisScreen> {
  static const _defaultAutoIaqiOn = 1.2;
  static const _defaultAutoIaqiOff = 0.9;

  final _storage = DisasterDeviceStorage();
  final _testController = DisasterDeviceTestController();

  DisasterDeviceDraft? _draft;
  bool _loading = true;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final draft = await _storage.load();
    if (!mounted) return;
    setState(() {
      _draft = draft;
      _message = draft?.lastTestStatus;
      _loading = false;
    });
  }

  Future<void> _togglePolicy() async {
    final draft = _draft;
    if (_busy) return;
    if (draft == null) {
      _showSnack('먼저 플러그 탭에서 방재 장치를 저장하세요.');
      return;
    }

    final next = !draft.autoControlEnabled;
    var updated = draft.copyWith(
      autoControlEnabled: next,
      lastTestStatus: next ? '자동 제어 켜짐' : '자동 제어 꺼짐',
      updatedAt: DateTime.now(),
    );
    setState(() => _busy = true);
    try {
      final profileId = await _testController.syncBackendAutoProfile(
        updated,
        aqiOn: (_defaultAutoIaqiOn * 100).round(),
        aqiOff: (_defaultAutoIaqiOff * 100).round(),
        enabled: next,
      );
      updated = updated.copyWith(
        lastTestStatus: profileId == null
            ? (next ? '자동 제어 켜짐 · 서버 동기화 대기' : '자동 제어 꺼짐 · 서버 동기화 대기')
            : (next ? '자동 제어 켜짐 · $profileId' : '자동 제어 꺼짐 · $profileId'),
      );
    } catch (_) {
      updated = updated.copyWith(
        lastTestStatus: next ? '자동 제어 켜짐 · 서버 동기화 대기' : '자동 제어 꺼짐 · 서버 동기화 대기',
      );
    }
    await _storage.save(updated);
    final saved = await _storage.load();
    if (!mounted) return;
    final resolved = saved ?? updated;
    setState(() {
      _draft = resolved;
      _message = resolved.lastTestStatus;
      _busy = false;
    });
    _showSnack(resolved.lastTestStatus);
  }

  Future<void> _testConnection() async {
    final draft = _draft;
    if (_busy) return;
    if (draft == null || draft.plugIp.trim().isEmpty) {
      _showSnack('플러그 탭에서 로컬 IP를 저장한 뒤 테스트하세요.');
      return;
    }

    setState(() => _busy = true);
    try {
      final result = await _testController.testConnection(draft);
      final updated = draft.copyWith(
        lastTestStatus: result.statusLabel,
        updatedAt: DateTime.now(),
      );
      await _storage.save(updated);
      final saved = await _storage.load();
      if (!mounted) return;
      final resolved = saved ?? updated;
      setState(() {
        _draft = resolved;
        _message = result.statusLabel;
      });
      _showSnack(result.message);
    } catch (error) {
      if (mounted) _showSnack('연결 테스트 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AirQualityController>();
    final draft = _draft;
    final historyValues = controller.rawHistory
        .map(_iaqiValue)
        .whereType<double>()
        .toList(growable: false);
    final values = historyValues.isEmpty
        ? <double>[0.42, 0.55, 0.72, 0.64, 0.58, 0.48]
        : historyValues.length > 8
            ? historyValues.sublist(historyValues.length - 8)
            : historyValues;
    final currentIaqi = _iaqiValue(controller.latestSnapshot) ??
        (historyValues.isEmpty ? null : historyValues.last);
    const onLimit = _defaultAutoIaqiOn;
    const offLimit = _defaultAutoIaqiOff;
    const gap = onLimit - offLimit;
    final active = draft?.autoControlEnabled ?? false;
    final stateLabel = _busy
        ? '테스트 중'
        : active
            ? '활성'
            : '대기';
    final stateColor = active ? CleanColors.primary : CleanColors.secondary;
    final rows = <({String a, String b, String c, Color color})>[
      (
        a: draft == null ? '--:--:--' : _formatClock(draft.updatedAt),
        b: _message ?? draft?.lastTestStatus ?? '장치 저장 필요',
        c: active ? '자동' : '대기',
        color: active ? CleanColors.primary : CleanColors.secondary,
      ),
      (
        a: '현재',
        b: currentIaqi == null ? '센서 대기' : currentIaqi.toStringAsFixed(2),
        c: currentIaqi != null && currentIaqi >= onLimit ? '작동 조건' : '감시',
        color: currentIaqi != null && currentIaqi >= onLimit
            ? CleanColors.error
            : CleanColors.primary,
      ),
    ];

    return _LegacyPage(
      title: 'CleanAir',
      leading: widget.onBack == null ? Symbols.location_on : Symbols.arrow_back,
      trailing: Symbols.settings,
      onLeadingTap: widget.onBack,
      children: [
        const Text(
          'SYSTEM MANAGEMENT',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.8,
            color: CleanColors.secondary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '제어 정책\n히스테리시스',
          style: TextStyle(
            fontSize: 34,
            height: 1.05,
            fontWeight: FontWeight.w900,
            color: CleanColors.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '켜는 기준과 끄는 기준을 따로 두어 플러그가 짧게 반복되는 일을 줄입니다.',
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            fontWeight: FontWeight.w600,
            color: CleanColors.secondary,
          ),
        ),
        const SizedBox(height: 18),
        _SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _InfoListTile(
                icon: Symbols.settings_input_component,
                title: '제어 대상',
                subtitle: '저장된 방재 장치와 현재 센서 값을 기준으로 정책을 적용합니다.',
              ),
              const SizedBox(height: 16),
              const _SegmentTabs(
                labels: ['공기청정기', '스마트 플러그'],
                active: 1,
              ),
              if (_loading) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(
                  minHeight: 4,
                  color: CleanColors.primary,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: GradientButton(
                label: _busy ? '테스트 중' : '연결 테스트',
                icon: Symbols.power_settings_new,
                onTap: _busy ? null : _testConnection,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _togglePolicy,
                child: MockCard(
                  child: Center(
                    child: Text(
                      active ? '자동 정책 끄기' : '자동 정책 켜기',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: CleanColors.secondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SoftCard(
          color: CleanColors.surfaceLow,
          child: Row(
            children: [
              const Text(
                'STATUS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: CleanColors.secondary,
                ),
              ),
              const Spacer(),
              CircleAvatar(radius: 5, backgroundColor: stateColor),
              const SizedBox(width: 8),
              Text(
                stateLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: stateColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: _InfoListTile(
                      icon: Symbols.insights,
                      title: '히스테리시스 설정',
                      subtitle: 'AUTO_AQI_ON/OFF 기준을 분리해 반복 동작을 줄입니다.',
                    ),
                  ),
                  _StatusPill(text: gap.toStringAsFixed(2)),
                ],
              ),
              const SizedBox(height: 18),
              _LineChartPanel(
                values: values,
                height: 136,
                statusOf: _iaqiChartStatus,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _MiniMetric(
                      label: 'ON 임계값',
                      value: onLimit.toStringAsFixed(2),
                      unit: 'IAQI',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniMetric(
                      label: 'OFF 임계값',
                      value: offLimit.toStringAsFixed(2),
                      unit: 'IAQI',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Symbols.history, size: 18, color: CleanColors.primary),
            const SizedBox(width: 8),
            const Text(
              'CONTROL STATUS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: CleanColors.secondary,
              ),
            ),
            const Spacer(),
            if (widget.onBack != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onBack,
                child: const Text(
                  '장치 제어',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: CleanColors.primary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _DataTableCard(rows: rows),
      ],
    );
  }

  double? _iaqiValue(AirQualitySnapshot? snapshot) {
    if (snapshot == null) return null;
    final stored = snapshot.iaqiScore;
    if (stored != null && stored.isFinite) {
      return stored.abs() > 10 ? stored / 100 : stored;
    }
    return _DashboardData._calculateIaqi(snapshot)?.aqi;
  }
}

const _cardTitle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w900,
  color: CleanColors.onSurface,
);

// ignore: unused_element
const _caption = TextStyle(
  fontSize: 12,
  height: 1.4,
  color: CleanColors.secondary,
);

// ignore: unused_element
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: CleanColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
              color: CleanColors.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            Pill(
              text: labels[i],
              color: i == 0 ? CleanColors.primary : CleanColors.surfaceHigh,
              textColor: i == 0 ? Colors.white : CleanColors.secondary,
            ),
            if (i != labels.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

// ignore: unused_element
class _HealthTabs extends StatelessWidget {
  const _HealthTabs({required this.active});

  final String active;

  @override
  Widget build(BuildContext context) {
    final labels = ['어린이', '고령자', '정화지표'];
    return MockCard(
      padding: const EdgeInsets.all(6),
      color: CleanColors.surfaceLow,
      child: Row(
        children: [
          for (final label in labels)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: label == active ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: label == active
                        ? CleanColors.primary
                        : CleanColors.secondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _LogRow extends StatelessWidget {
  const _LogRow({
    required this.time,
    required this.value,
    required this.status,
  });

  final String time;
  final String value;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              time,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: CleanColors.secondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: CleanColors.onSurface,
              ),
            ),
          ),
          Pill(
            text: status,
            color: status == '나쁨' || status == '실패'
                ? CleanColors.errorContainer
                : CleanColors.surfaceLow,
            textColor: status == '나쁨' || status == '실패'
                ? CleanColors.error
                : CleanColors.primary,
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.enabled,
  });

  final String title;
  final String subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: CleanColors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: CleanColors.secondary,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 48,
          height: 28,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: enabled
                ? CleanColors.primaryContainer
                : CleanColors.surfaceHigh,
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}

const _alertTypeItems = [
  (
    type: 'pm25_high',
    title: 'PM2.5 고농도',
    subtitle: '초미세먼지 급증 알림',
  ),
  (
    type: 'co2_high',
    title: 'CO₂ 환기 경보',
    subtitle: '이산화탄소와 환기 필요 상태',
  ),
  (
    type: 'tvoc_high',
    title: 'TVOC 화학물질 경보',
    subtitle: '조리, 화학물질, 연소원 영향 알림',
  ),
  (
    type: 'nox_high',
    title: 'NOx 연소 영향 경보',
    subtitle: '외기 유입과 연소 환경 변화 알림',
  ),
  (
    type: 'fire_risk',
    title: '방재모드 화재 의심',
    subtitle: '복합 지표와 지속성 기반 화재 의심 알림',
  ),
  (
    type: 'respiratory_low',
    title: '호흡기 지표',
    subtitle: '호흡기 보호점수 하락 알림',
  ),
  (
    type: 'infection_risk',
    title: '면역/감염 위험',
    subtitle: '감염 위험 상승 알림',
  ),
  (
    type: 'focus_poor',
    title: '집중 환경',
    subtitle: 'CO₂ 기반 집중 환경 악화 알림',
  ),
  (
    type: 'mold_risk',
    title: '곰팡이 위험',
    subtitle: '습도 지속과 곰팡이 위험 파생 알림',
  ),
  (
    type: 'cardio_low',
    title: '심혈관 보호점수',
    subtitle: '노약자 심혈관 보호점수 하락 알림',
  ),
  (
    type: 'sleep_quality_low',
    title: '수면 환경',
    subtitle: '수면 쾌적도 하락 알림',
  ),
  (
    type: 'apparent_temp_morning',
    title: '아침 체감온도',
    subtitle: '아침 체감온도 알림',
  ),
  (
    type: 'apparent_temp_evening',
    title: '저녁 체감온도',
    subtitle: '저녁 체감온도 알림',
  ),
];

class _AlertTypeToggle extends StatelessWidget {
  const _AlertTypeToggle({
    required this.controller,
    required this.prefs,
    required this.type,
    required this.title,
    required this.subtitle,
    this.fireRiskMinimumLevel,
    this.onMutedChanged,
    this.onSeverityChanged,
  });

  final NotificationPreferencesController controller;
  final NotificationPreferences prefs;
  final String type;
  final String title;
  final String subtitle;
  final String? fireRiskMinimumLevel;
  final ValueChanged<bool>? onMutedChanged;
  final ValueChanged<int>? onSeverityChanged;

  @override
  Widget build(BuildContext context) {
    final muted = prefs.mutedTypes[type] ?? false;
    final priority =
        prefs.minimumSeverityByType[type] ?? prefs.minimumSeverityPriority;
    final isFireRisk = type == 'fire_risk';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final nextMuted = !muted;
            final handler = onMutedChanged;
            if (handler == null) {
              unawaited(controller.setMutedType(type, nextMuted));
            } else {
              handler(nextMuted);
            }
          },
          child: _ToggleRow(
            title: title,
            subtitle: muted
                ? '$subtitle · 꺼짐'
                : isFireRisk
                    ? '$subtitle · ${_fireRiskMinimumLevelShortLabel(fireRiskMinimumLevel ?? prefs.fireRiskMinimumLevel)}'
                    : '$subtitle · ${_settingsSeverityShortLabel(priority)}',
            enabled: !muted,
          ),
        ),
        if (!muted && !isFireRisk) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AlertSeverityChip(
                label: '주의 이상',
                selected: priority == 1,
                onTap: () => _setSeverity(1),
              ),
              _AlertSeverityChip(
                label: '나쁨 이상',
                selected: priority == 2,
                onTap: () => _setSeverity(2),
              ),
              _AlertSeverityChip(
                label: '위험만',
                selected: priority == 3,
                onTap: () => _setSeverity(3),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _setSeverity(int priority) {
    final handler = onSeverityChanged;
    if (handler == null) {
      unawaited(controller.setMinimumSeverityForType(type, priority));
    } else {
      handler(priority);
    }
  }
}

class _AlertSeverityChip extends StatelessWidget {
  const _AlertSeverityChip({
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
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? CleanColors.primary : CleanColors.surfaceLow,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: selected ? Colors.white : CleanColors.secondary,
          ),
        ),
      ),
    );
  }
}

class _AlertIntervalChip extends StatelessWidget {
  const _AlertIntervalChip({
    required this.minutes,
    required this.selected,
    required this.onTap,
  });

  final int minutes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? CleanColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x2400677D),
                    blurRadius: 14,
                    offset: Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Text(
          '$minutes분',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: selected ? Colors.white : CleanColors.secondary,
          ),
        ),
      ),
    );
  }
}

class _ThresholdBar extends StatelessWidget {
  const _ThresholdBar({this.minimumSeverityPriority = 2});

  final int minimumSeverityPriority;

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('PM2.5', '15 / 35 / 55', '주의 · 나쁨 · 위험'),
      ('CO₂', '800 / 1000 / 1500', '주의 · 나쁨 · 위험'),
      ('TVOC', '200 / 300 / 400', '주의 · 나쁨 · 위험'),
      ('NOx', '1 / 2', '관찰 · 높음'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '현재 알림 기준',
          style: _thresholdLabel,
        ),
        const SizedBox(height: 4),
        Text(
          minimumSeverityPriority <= 1
              ? '주의 단계부터 알림을 수신합니다.'
              : minimumSeverityPriority >= 3
                  ? '위험 단계 알림만 수신합니다.'
                  : '나쁨 단계부터 알림을 수신합니다.',
          style: const TextStyle(
            fontSize: 11,
            height: 1.35,
            fontWeight: FontWeight.w700,
            color: CleanColors.secondary,
          ),
        ),
        const SizedBox(height: 10),
        for (final row in rows) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 54,
                  child: Text(
                    row.$1,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: CleanColors.onSurface,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: CleanColors.primary,
                    ),
                  ),
                ),
                Text(
                  row.$3,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: CleanColors.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
        const Text(
          '건강/곰팡이 알림도 같은 민감도 설정을 따릅니다.',
          style: TextStyle(
            fontSize: 11,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: CleanColors.secondary,
          ),
        ),
      ],
    );
  }
}

const _thresholdLabel = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w800,
  color: CleanColors.outline,
);

// ignore: unused_element
class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: CleanColors.surfaceHighest,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: CleanColors.surfaceHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Symbols.search, color: CleanColors.outline, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: CleanColors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
