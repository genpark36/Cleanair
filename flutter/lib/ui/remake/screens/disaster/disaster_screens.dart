import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/air_quality_snapshot.dart';
import '../../../../services/airgradient_local_api.dart';
import '../../../../services/device_binding_service_v2.dart';
import '../../../../services/led_control_service.dart';
import '../shared/cleanair_stitch_widgets.dart';

String _sensorLabel(BuildContext context) {
  final binding = context.watch<DeviceBindingControllerV2>().value;
  return binding.isBound ? binding.deviceId : '센서 등록 필요';
}

String _sensorSubtitle(BuildContext context) {
  final binding = context.watch<DeviceBindingControllerV2>().value;
  return binding.isBound
      ? '${binding.firestoreDocPath} · 연결됨'
      : 'PIN 등록 후 위치와 연결됩니다';
}

void _showStitchAction(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class AnomalyAnalysisScreen extends StatelessWidget {
  const AnomalyAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MockScreenShell(
      title: '방재모드',
      leading: Symbols.location_on,
      trailing: Symbols.notifications_active,
      activeNav: 1,
      children: [
        const MockHeader(
          heading: '이상 징후 분석',
          subtitle: '최근 환경 데이터 패턴을 분석한 결과입니다.',
        ),
        const SizedBox(height: 16),
        MockCard(
          color: CleanColors.tertiaryContainer,
          child: Row(
            children: const [
              Icon(
                Symbols.warning,
                size: 42,
                color: CleanColors.tertiary,
                fill: 1,
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  '주의 징후 감지',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: CleanColors.tertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const MockCard(
          child: InfoRow(
            icon: Symbols.analytics,
            title: '주요 관측',
            subtitle: 'PM2.5와 TVOC가 함께 상승 중입니다.',
          ),
        ),
        const SizedBox(height: 12),
        const MockCard(
          child: InfoRow(
            icon: Symbols.psychology,
            title: '분석 결과',
            subtitle: '요리 연기 또는 환기 부족 가능성이 있습니다.',
          ),
        ),
        const SizedBox(height: 12),
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Pill(
              text: 'PM2.5 급상승',
              color: CleanColors.primaryFixed,
              textColor: CleanColors.primary,
            ),
            Pill(
              text: 'TVOC 동시 상승',
              color: CleanColors.primaryFixed,
              textColor: CleanColors.primary,
            ),
            Pill(text: '온도 변화 안정'),
          ],
        ),
        const SizedBox(height: 18),
        _SafetyActions(title: '권장 조치', actions: ['환기 시작', '상황 전파']),
        const SizedBox(height: 18),
        _Timeline(
          title: '최근 변화 타임라인',
          rows: ['14:20 PM2.5 상승', '14:24 TVOC 동반 상승', '14:32 주의 단계 감지'],
        ),
      ],
    );
  }
}

class SafetyDashboardScreen extends StatelessWidget {
  const SafetyDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MockScreenShell(
      title: '방재모드',
      leading: Symbols.location_on,
      trailing: Symbols.notifications_active,
      activeNav: 0,
      children: [
        const MockHeader(
          heading: '새싹어린이집 1층',
          subtitle: '센서 상태: 정상 작동 중 · 5초 전 업데이트',
        ),
        const SizedBox(height: 24),
        Center(
          child: IconBubble(
            icon: Symbols.check_circle,
            size: 160,
            iconSize: 86,
            color: CleanColors.primaryFixed,
            iconColor: CleanColors.primary,
          ),
        ),
        const SizedBox(height: 18),
        const MockHeader(
          heading: '화재 의심 패턴 없음',
          subtitle: '현재 센서 흐름은 안정적입니다.',
          center: true,
        ),
        const SizedBox(height: 20),
        const Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'PM2.5',
                value: '12',
                unit: 'µg/m³',
                compact: true,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: StatTile(
                label: 'CO2',
                value: '450',
                unit: 'ppm',
                compact: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'TVOC',
                value: '0.1',
                unit: 'index',
                compact: true,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: StatTile(
                label: '온도',
                value: '22.5',
                unit: '°C',
                compact: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SafetyActions(
          title: '빠른 실행',
          actions: ['책임자 알림', '상세 분석', '장치 제어', '상황 기록'],
        ),
      ],
    );
  }
}

class SituationBroadcastScreen extends StatelessWidget {
  const SituationBroadcastScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MockScreenShell(
      title: '상황 전파',
      leading: Symbols.location_on,
      trailing: Symbols.notifications_active,
      activeNav: 2,
      children: [
        Center(
          child: IconBubble(
            icon: Symbols.warning,
            size: 128,
            iconSize: 72,
            color: CleanColors.errorContainer,
            iconColor: CleanColors.error,
          ),
        ),
        const SizedBox(height: 18),
        const MockHeader(
          heading: '화재 의심 패턴 감지',
          subtitle: '발생 위치: 새싹어린이집 1층\n감지 시각: 오후 14:32',
          center: true,
        ),
        const SizedBox(height: 22),
        _SectionTitle(title: '책임자 연락처', icon: Symbols.person),
        const SizedBox(height: 10),
        MockCard(
          child: Column(
            children: const [
              InfoRow(
                icon: Symbols.person,
                title: '시설 책임자',
                subtitle: '김책임 · 연락처 확인',
              ),
              SizedBox(height: 12),
              InfoRow(
                icon: Symbols.support_agent,
                title: '보조 관리자',
                subtitle: '이보조 · 연락처 확인',
              ),
              SizedBox(height: 12),
              InfoRow(
                icon: Symbols.family_restroom,
                title: '보호자 대표',
                subtitle: '박보호 · 연락처 확인',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        GradientButton(
          label: '상황 요약 복사',
          icon: Symbols.content_copy,
          colorA: CleanColors.error,
          colorB: const Color(0xFFE65353),
          onTap: () {
            Clipboard.setData(
              const ClipboardData(text: '방재 상황 요약: 이상 징후 확인 및 현장 점검 필요'),
            );
            _showStitchAction(context, '상황 요약을 복사했습니다.');
          },
        ),
        const SizedBox(height: 10),
        const MockCard(
          color: CleanColors.surfaceLow,
          child: Center(
            child: Text(
              '신고 정보 복사',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: CleanColors.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ConnectedDevicesScreen extends StatelessWidget {
  const ConnectedDevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MockScreenShell(
      title: '방재모드',
      leading: Symbols.location_on,
      trailing: Symbols.notifications_active,
      activeNav: 3,
      children: [
        const MockHeader(
          heading: '연결 장치',
          subtitle: '시설 내 연결된 장치를 실시간으로 제어하고 모니터링합니다.',
        ),
        const SizedBox(height: 16),
        _DeviceCard(
          icon: Symbols.campaign,
          name: '1층 복도 사이렌',
          status: '꺼짐',
          subtitle: '자동 제어: 켜짐',
        ),
        const SizedBox(height: 12),
        _DeviceCard(
          icon: Symbols.mode_fan,
          name: '주방 환기팬',
          status: '켜짐',
          subtitle: '마지막 작동: 오전 11:15',
          active: true,
        ),
        const SizedBox(height: 12),
        _DeviceCard(
          icon: Symbols.wb_incandescent,
          name: '입구 경광등',
          status: '꺼짐',
          subtitle: '자동 제어: 꺼짐',
        ),
      ],
    );
  }
}

class SpaceSensorManagementScreen extends StatelessWidget {
  const SpaceSensorManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MockScreenShell(
      title: '방재모드',
      leading: Symbols.location_on,
      trailing: Symbols.notifications_active,
      activeNav: 3,
      children: [
        const MockHeader(
          heading: '공간 관리',
          subtitle: '시설 내 설치된 센서 및 연결 장치의 상태를 모니터링하고 관리합니다.',
        ),
        const SizedBox(height: 16),
        MockCard(
          child: Column(
            children: const [
              InfoRow(
                icon: Symbols.sensor_door,
                title: '새싹어린이집 1층',
                subtitle: '정상 작동 중 · 5초 전 수신',
              ),
              SizedBox(height: 12),
              InfoRow(
                icon: Symbols.toys,
                title: '2층 별님반',
                subtitle: '연결 장치 2개 · 최근 수신 정상',
              ),
              SizedBox(height: 12),
              InfoRow(
                icon: Symbols.kitchen,
                title: '조리실 앞 복도',
                subtitle: '사이렌 1개 · 환기팬 1개',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        GradientButton(
          label: '새 공간 등록',
          icon: Symbols.add,
          onTap: () => _showStitchAction(
            context,
            '메인 설정의 위치 등록 화면에서 새 공간을 저장하세요.',
          ),
        ),
      ],
    );
  }
}

class AutoControlRulesScreen extends StatelessWidget {
  const AutoControlRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MockScreenShell(
      title: '자동 제어 규칙',
      leading: Symbols.arrow_back,
      trailing: Symbols.add,
      activeNav: 3,
      children: [
        const MockHeader(
          heading: '자동 제어 규칙 설정',
          subtitle: '위험 단계별로 사이렌, 환기팬, 경광등이 자동으로 작동하도록 구성합니다.',
        ),
        const SizedBox(height: 16),
        MockCard(
          child: Column(
            children: const [
              InfoRow(
                icon: Symbols.warning,
                title: '화재 의심 높음',
                subtitle: '사이렌 ON · 경광등 ON · 책임자 알림',
              ),
              SizedBox(height: 12),
              InfoRow(
                icon: Symbols.air,
                title: 'TVOC 급상승',
                subtitle: '환기팬 2단계 · 20분 유지',
              ),
              SizedBox(height: 12),
              InfoRow(
                icon: Symbols.co2,
                title: 'CO2 기준 초과',
                subtitle: '환기 안내 · 자동 환기팬 ON',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'ON 기준',
                value: '150',
                unit: 'AQI',
                compact: true,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: StatTile(
                label: 'OFF 기준',
                value: '80',
                unit: 'AQI',
                compact: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        GradientButton(
          label: '규칙 저장',
          icon: Symbols.check_circle,
          onTap: () => _showStitchAction(context, '자동 제어 규칙을 확인했습니다.'),
        ),
      ],
    );
  }
}

class IncidentHistoryScreen extends StatelessWidget {
  const IncidentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MockScreenShell(
      title: '상황 기록',
      leading: Symbols.arrow_back,
      trailing: Symbols.filter_list,
      activeNav: 2,
      children: [
        const MockHeader(
          heading: '상황 기록 히스토리',
          subtitle: '감지, 전파, 장치 제어 이력을 시간순으로 확인합니다.',
        ),
        const SizedBox(height: 16),
        const _Timeline(
          title: '오늘',
          rows: [
            '14:32 화재 의심 패턴 감지',
            '14:33 책임자 알림 발송',
            '14:34 주방 환기팬 자동 ON',
            '14:40 정상 범위 복귀',
          ],
        ),
        const SizedBox(height: 14),
        const _Timeline(
          title: '어제',
          rows: ['18:15 TVOC 주의 단계', '18:20 환기 조치 완료', '18:28 상태 정상화'],
        ),
      ],
    );
  }
}

class SensorLocationOverviewScreen extends StatelessWidget {
  const SensorLocationOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sensorLabel = _sensorLabel(context);
    final sensorSubtitle = _sensorSubtitle(context);
    return MockScreenShell(
      title: '센서 위치 등록',
      leading: Symbols.arrow_back,
      trailing: Symbols.help,
      bottomNav: false,
      children: [
        const MockHeader(
          heading: '센서 위치 등록',
          subtitle: '이상 상황 발생 시 이 위치가 알림에 표시됩니다.',
        ),
        const SizedBox(height: 18),
        FakeMap(height: 300, label: sensorLabel),
        const SizedBox(height: 16),
        MockCard(
          child: InfoRow(
            icon: Symbols.sensors,
            title: sensorLabel,
            subtitle: sensorSubtitle,
          ),
        ),
        const SizedBox(height: 18),
        GradientButton(
          label: '위치 등록 시작',
          icon: Symbols.location_on,
          onTap: () => _showStitchAction(
            context,
            '메인 설정의 위치 등록 화면에서 센서 위치를 저장하세요.',
          ),
        ),
      ],
    );
  }
}

class SensorSettingsScreen extends StatefulWidget {
  const SensorSettingsScreen({super.key});

  @override
  State<SensorSettingsScreen> createState() => _SensorSettingsScreenState();
}

class _SensorSettingsScreenState extends State<SensorSettingsScreen> {
  static const _ipPrefsKey = 'airgradient_local_ip_v1';

  final _ipController = TextEditingController();
  final _localClient = AirGradientLocalClient();
  final _ledService = LedControlService();

  AirQualitySnapshot? _localSnapshot;
  bool _busy = false;
  bool _ok = false;
  String _message = '같은 Wi-Fi에서 센서 로컬 IP를 입력해 주세요.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIp());
  }

  @override
  void dispose() {
    _ipController.dispose();
    _localClient.dispose();
    super.dispose();
  }

  Future<void> _loadIp() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_ipPrefsKey)?.trim();
    if (!mounted || saved == null || saved.isEmpty) return;
    setState(() => _ipController.text = saved);
  }

  Future<void> _saveIp() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ipPrefsKey, ip);
  }

  String get _ip => _ipController.text.trim();
  String get _webUrl => _ip.isEmpty ? '' : 'http://$_ip';

  Future<void> _copyWebUrl() async {
    final url = _webUrl;
    if (url.isEmpty) {
      _setResult(ok: false, message: '센서 로컬 IP를 먼저 입력해 주세요.');
      return;
    }
    await _saveIp();
    await Clipboard.setData(ClipboardData(text: url));
    _setResult(ok: true, message: '$url 복사 완료');
  }

  Future<void> _testLocalConnection() async {
    if (_busy) return;
    final ip = _ip;
    if (ip.isEmpty) {
      _setResult(ok: false, message: '센서 로컬 IP를 먼저 입력해 주세요.');
      return;
    }

    setState(() {
      _busy = true;
      _message = '로컬 측정값을 읽는 중입니다.';
    });
    await _saveIp();
    try {
      final snapshot = await _localClient.fetchSnapshot(ip);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ok = snapshot != null;
        _localSnapshot = snapshot;
        _message = snapshot == null
            ? '측정값을 읽지 못했습니다. IP와 같은 Wi-Fi 연결을 확인해 주세요.'
            : '측정값 확인 · PM2.5 ${_fmt(snapshot.pm25)} · CO₂ ${_fmt(snapshot.co2)} ppm';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ok = false;
        _message = '연결 실패 · 휴대폰과 센서가 같은 Wi-Fi인지 확인해 주세요.';
      });
    }
  }

  Future<void> _runConfigAction({
    required String success,
    required String failure,
    required Future<bool> Function(String ip) action,
  }) async {
    if (_busy) return;
    final ip = _ip;
    if (ip.isEmpty) {
      _setResult(ok: false, message: '센서 로컬 IP를 먼저 입력해 주세요.');
      return;
    }

    setState(() {
      _busy = true;
      _message = '로컬 설정 요청을 보내는 중입니다.';
    });
    await _saveIp();
    final ok = await action(ip);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = ok;
      _message = ok ? success : failure;
    });
  }

  void _setResult({required bool ok, required String message}) {
    setState(() {
      _ok = ok;
      _message = message;
    });
  }

  String _fmt(double? value) {
    if (value == null || !value.isFinite) return '-';
    if (value.abs() >= 100 || value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final sensorLabel = _sensorLabel(context);
    final sensorSubtitle = _sensorSubtitle(context);
    final snapshot = _localSnapshot;
    return MockScreenShell(
      title: '센서 설정',
      leading: Symbols.arrow_back,
      trailing: Symbols.more_vert,
      activeNav: 4,
      children: [
        MockHeader(
          heading: sensorLabel,
          subtitle: '등록 센서, 로컬 IP, 웹 설정, 연결 테스트를 관리합니다.',
        ),
        const SizedBox(height: 16),
        MockCard(
          child: Column(
            children: [
              InfoRow(
                icon: Symbols.sensors,
                title: '센서 이름',
                subtitle: sensorLabel,
              ),
              const SizedBox(height: 12),
              InfoRow(
                icon: Symbols.wifi,
                title: '네트워크',
                subtitle: sensorSubtitle,
              ),
              const SizedBox(height: 12),
              InfoRow(
                icon: Symbols.language,
                title: '웹 설정 URL',
                subtitle: _webUrl.isEmpty ? 'IP 입력 후 생성됩니다' : _webUrl,
              ),
              const SizedBox(height: 12),
              InfoRow(
                icon: Symbols.update,
                title: '로컬 측정 결과',
                subtitle: snapshot == null
                    ? '연결 테스트 후 측정값을 표시합니다'
                    : 'PM2.5 ${_fmt(snapshot.pm25)} · CO₂ ${_fmt(snapshot.co2)} ppm · ${_fmt(snapshot.temperature)}°C / ${_fmt(snapshot.humidity)}%',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        MockCard(
          child: TextField(
            controller: _ipController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '로컬 IP',
              hintText: '192.168.0.24',
              border: InputBorder.none,
            ),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: CleanColors.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 12),
        MockCard(
          color: _ok ? CleanColors.primaryFixed : CleanColors.surfaceLow,
          child: InfoRow(
            icon: _busy ? Symbols.sync : Symbols.info,
            title: _busy ? '확인 중' : '로컬 연결 상태',
            subtitle: _message,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: GradientButton(
                label: _busy ? '테스트 중' : '연결 테스트',
                icon: Symbols.radar,
                onTap: () => unawaited(_testLocalConnection()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GradientButton(
                label: 'URL 복사',
                icon: Symbols.copy_all,
                onTap: () => unawaited(_copyWebUrl()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GradientButton(
                label: 'LED ON',
                icon: Symbols.lightbulb,
                onTap: () => unawaited(
                  _runConfigAction(
                    success: 'LED 표시를 CO₂ 모드로 켰습니다.',
                    failure: 'LED 설정 실패 · 센서 IP와 같은 Wi-Fi를 확인해 주세요.',
                    action: (ip) => _ledService.turnOn(ip, brightness: 0.7),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GradientButton(
                label: 'LED OFF',
                icon: Symbols.light_off,
                onTap: () => unawaited(
                  _runConfigAction(
                    success: 'LED 표시를 껐습니다.',
                    failure: 'LED 끄기 실패 · 센서 IP와 같은 Wi-Fi를 확인해 주세요.',
                    action: _ledService.turnOff,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GradientButton(
          label: 'CO₂ 교정 요청',
          icon: Symbols.tune,
          onTap: () => unawaited(
            _runConfigAction(
              success: 'CO₂ 교정 요청을 보냈습니다.',
              failure: 'CO₂ 교정 요청 실패 · 센서 펌웨어와 IP를 확인해 주세요.',
              action: _ledService.requestCo2Calibration,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const MockCard(
          color: CleanColors.surfaceLow,
          child: InfoRow(
            icon: Symbols.wifi,
            title: '같은 Wi-Fi 필요',
            subtitle: '로컬 웹 설정과 측정값 확인은 휴대폰과 AirGradient가 같은 네트워크에 있을 때 동작합니다.',
          ),
        ),
      ],
    );
  }
}

class DisasterDeviceConnectionScreen extends StatelessWidget {
  const DisasterDeviceConnectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MockScreenShell(
      title: '방재 장치 연결',
      leading: Symbols.arrow_back,
      trailing: Symbols.help,
      activeNav: 3,
      children: [
        const MockHeader(
          heading: '방재 장치 연결',
          subtitle: '새로운 스마트 플러그 또는 제어 장치를 등록합니다.',
        ),
        const SizedBox(height: 16),
        const MockCard(
          child: Column(
            children: [
              InfoRow(
                icon: Symbols.wifi_tethering,
                title: 'Tasmota 네트워크 연결',
                subtitle: 'tasmota-xxxx Wi-Fi에 연결합니다.',
              ),
              SizedBox(height: 12),
              InfoRow(
                icon: Symbols.power_settings_new,
                title: '전원 상태 확인',
                subtitle: 'LED 점멸 상태를 확인합니다.',
              ),
              SizedBox(height: 12),
              InfoRow(
                icon: Symbols.router,
                title: 'IP 주소 입력',
                subtitle: '할당받은 새 IP 주소를 등록하세요.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const MockCard(
          color: CleanColors.surfaceLow,
          child: InfoRow(
            icon: Symbols.help_outline,
            title: '새 플러그 설정이 필요한가요?',
            subtitle: '브라우저에서 192.168.4.1로 접속하여 Wi-Fi 정보를 입력합니다.',
          ),
        ),
        const SizedBox(height: 18),
        GradientButton(
          label: '장치 등록',
          icon: Symbols.add,
          onTap: () => _showStitchAction(
            context,
            '플러그 탭에서 Tasmota 장치를 등록하고 테스트하세요.',
          ),
        ),
      ],
    );
  }
}

class SystemSettingsExtendedScreen extends StatelessWidget {
  const SystemSettingsExtendedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MockScreenShell(
      title: '설정',
      leading: Symbols.location_on,
      trailing: Symbols.notifications_active,
      activeNav: 4,
      children: [
        const MockHeader(
          heading: '시스템 설정',
          subtitle: '시설 안전 모니터링의 알림, 담당자, 보안, 데이터 동기화 옵션을 관리합니다.',
        ),
        const SizedBox(height: 16),
        MockCard(
          child: Column(
            children: const [
              InfoRow(
                icon: Symbols.notifications,
                title: '알림 켜기',
                subtitle: '모든 주요 시스템 경고 수신',
              ),
              SizedBox(height: 12),
              InfoRow(
                icon: Symbols.device_hub,
                title: '책임자 연락처',
                subtitle: '비상 연락망 및 권한 관리',
              ),
              SizedBox(height: 12),
              InfoRow(
                icon: Symbols.sensors,
                title: '센서 등록',
                subtitle: '신규 안전 진단 센서 추가',
              ),
              SizedBox(height: 12),
              InfoRow(
                icon: Symbols.security,
                title: '보안 설정',
                subtitle: '접근 제어 및 데이터 암호화 수준',
              ),
              SizedBox(height: 12),
              InfoRow(
                icon: Symbols.database,
                title: '동기화 상태',
                subtitle: '마지막 동기화: 오늘 14:30',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SensorLocationSearchBeforeScreen extends StatelessWidget {
  const SensorLocationSearchBeforeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sensorLabel = _sensorLabel(context);
    final sensorSubtitle = _sensorSubtitle(context);
    return MockScreenShell(
      title: '위치 등록',
      leading: Symbols.arrow_back,
      trailing: Symbols.help,
      bottomNav: false,
      children: [
        const MockHeader(
          heading: '센서 위치 등록',
          subtitle: '이상 상황 발생 시 이 위치가 알림에 표시됩니다.',
        ),
        const SizedBox(height: 18),
        MockCard(
          child: InfoRow(
            icon: Symbols.sensors,
            title: sensorLabel,
            subtitle: sensorSubtitle,
          ),
        ),
        const SizedBox(height: 22),
        const _SearchInput(placeholder: '예: 새싹어린이집, 테헤란로 123'),
        const SizedBox(height: 120),
        const Center(
          child: Text(
            '나중에 하기',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: CleanColors.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}

class SensorLocationMapSelectScreen extends StatelessWidget {
  const SensorLocationMapSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sensorLabel = _sensorLabel(context);
    return MockScreenShell(
      title: '위치 등록',
      leading: Symbols.arrow_back,
      trailing: Symbols.help,
      bottomNav: false,
      horizontalPadding: 16,
      children: [
        FakeMap(height: 500, label: sensorLabel),
        const SizedBox(height: 16),
        MockCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '선택된 위치',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                  color: CleanColors.secondary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '서울시 강남구 테헤란로 123',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              const Text('좌표: 37.5665° N, 126.9780° E', style: _caption),
              const SizedBox(height: 16),
              GradientButton(
                label: '이 위치로 설정',
                icon: Symbols.check,
                onTap: () => _showStitchAction(
                  context,
                  '메인 위치 설정 화면에서 선택 위치를 저장하세요.',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SensorLocationSearchResultsScreen extends StatelessWidget {
  const SensorLocationSearchResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MockScreenShell(
      title: '위치 등록',
      leading: Symbols.arrow_back,
      trailing: Symbols.help,
      bottomNav: false,
      children: [
        const MockHeader(
          heading: '어디에 센서를\n설치하셨나요?',
          subtitle: '정확한 주소나 기관명을 검색해 주세요.',
        ),
        const SizedBox(height: 18),
        const _SearchInput(placeholder: '새싹어린이집', filled: true),
        const SizedBox(height: 24),
        Row(
          children: const [
            Expanded(
              child: _SectionTitle(title: '검색 결과', icon: Symbols.search),
            ),
            Pill(text: '3건'),
          ],
        ),
        const SizedBox(height: 12),
        const MockCard(
          child: Column(
            children: [
              InfoRow(
                icon: Symbols.location_on,
                title: '새싹어린이집 본관',
                subtitle: '서울시 강남구 테헤란로 123',
              ),
              SizedBox(height: 14),
              InfoRow(
                icon: Symbols.location_on,
                title: '새싹어린이집 별관',
                subtitle: '서울시 강남구 테헤란로 125',
              ),
              SizedBox(height: 14),
              InfoRow(
                icon: Symbols.near_me,
                title: '행복요양원',
                subtitle: '서울시 강남구 테헤란로 130',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SensorLocationCompleteScreen extends StatelessWidget {
  const SensorLocationCompleteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sensorLabel = _sensorLabel(context);
    return MockScreenShell(
      title: '위치 등록',
      leading: Symbols.arrow_back,
      trailing: Symbols.help,
      bottomNav: false,
      children: [
        const SizedBox(height: 40),
        Center(
          child: IconBubble(
            icon: Symbols.check,
            size: 124,
            iconSize: 64,
            color: CleanColors.primaryContainer,
            iconColor: Colors.white,
          ),
        ),
        const SizedBox(height: 28),
        const MockHeader(
          heading: '센서 위치 등록 완료',
          subtitle: '이상 상황 발생 시 이 위치로 알림이 표시됩니다.',
          center: true,
        ),
        const SizedBox(height: 28),
        MockCard(
          child: Column(
            children: [
              InfoRow(
                icon: Symbols.sensors,
                title: '센서',
                subtitle: sensorLabel,
              ),
              const SizedBox(height: 14),
              const InfoRow(
                icon: Symbols.location_on,
                title: '위치',
                subtitle: '새싹어린이집 1층 복도',
              ),
              const SizedBox(height: 14),
              const InfoRow(
                icon: Symbols.map,
                title: '주소',
                subtitle: '서울시 강남구 테헤란로 123',
              ),
              const SizedBox(height: 14),
              const InfoRow(
                icon: Symbols.info,
                title: '상세',
                subtitle: '어린이집 · 1층 · 조리실 앞 복도',
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        GradientButton(
          label: '홈으로 이동',
          icon: Symbols.home,
          onTap: () => _showStitchAction(context, '상단 뒤로가기로 메인 화면에 돌아가세요.'),
        ),
      ],
    );
  }
}

class SensorLocationDetailInputScreen extends StatelessWidget {
  const SensorLocationDetailInputScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MockScreenShell(
      title: '위치 등록',
      leading: Symbols.arrow_back,
      trailing: Symbols.help,
      bottomNav: false,
      children: [
        const MockCard(
          color: CleanColors.surfaceLow,
          child: InfoRow(
            icon: Symbols.location_on,
            title: '선택된 주소',
            subtitle: '새싹어린이집 · 서울시 강남구 테헤란로 123',
          ),
        ),
        const SizedBox(height: 20),
        const MockHeader(
          heading: '상세 위치를\n입력해주세요',
          subtitle: '정확한 위치를 입력하면 책임자가 더 빠르게 대응할 수 있습니다.',
        ),
        const SizedBox(height: 20),
        const _InputBlock(label: '공간 이름', value: '1층 복도'),
        const SizedBox(height: 14),
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Pill(
              text: '어린이집',
              color: CleanColors.primaryContainer,
              textColor: Colors.white,
            ),
            Pill(text: '요양원'),
            Pill(text: '가정'),
            Pill(text: '작업장'),
            Pill(text: '매장'),
          ],
        ),
        const SizedBox(height: 14),
        const Row(
          children: [
            Expanded(
              child: _InputBlock(label: '층', value: '1층'),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _InputBlock(label: '상세 위치', value: '조리실 앞'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const _InputBlock(label: '메모', value: '비상구와 가까운 복도'),
        const SizedBox(height: 24),
        GradientButton(
          label: '등록 완료',
          icon: Symbols.check_circle,
          onTap: () => _showStitchAction(context, '위치 등록 상태를 확인했습니다.'),
        ),
      ],
    );
  }
}

const _caption = TextStyle(
  fontSize: 12,
  height: 1.45,
  color: CleanColors.secondary,
);

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
              color: CleanColors.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class _SafetyActions extends StatelessWidget {
  const _SafetyActions({required this.title, required this.actions});

  final String title;
  final List<String> actions;

  @override
  Widget build(BuildContext context) {
    return MockCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title: title, icon: Symbols.bolt),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < actions.length; i++)
                Pill(
                  text: actions[i],
                  color: i == 0 ? CleanColors.primary : CleanColors.surfaceLow,
                  textColor: i == 0 ? Colors.white : CleanColors.primary,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.title, required this.rows});

  final String title;
  final List<String> rows;

  @override
  Widget build(BuildContext context) {
    return MockCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title: title, icon: Symbols.history),
          const SizedBox(height: 12),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: CleanColors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      row,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: CleanColors.onVariant,
                      ),
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

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.icon,
    required this.name,
    required this.status,
    required this.subtitle,
    this.active = false,
  });

  final IconData icon;
  final String name;
  final String status;
  final String subtitle;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return MockCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBubble(
                icon: icon,
                color:
                    active ? CleanColors.primaryFixed : CleanColors.surfaceHigh,
              ),
              const Spacer(),
              Pill(
                text: status,
                color: active
                    ? CleanColors.primaryContainer
                    : CleanColors.surfaceHigh,
                textColor: active ? Colors.white : CleanColors.secondary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            name,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: CleanColors.onSurface,
            ),
          ),
          const SizedBox(height: 5),
          Text(subtitle, style: _caption),
          const SizedBox(height: 12),
          const Pill(
            text: '규칙 설정',
            icon: Symbols.settings,
            color: CleanColors.surfaceLow,
            textColor: CleanColors.primary,
          ),
        ],
      ),
    );
  }
}

class _SearchInput extends StatelessWidget {
  const _SearchInput({required this.placeholder, this.filled = false});

  final String placeholder;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: CleanColors.surfaceHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          const Icon(Symbols.search, size: 22, color: CleanColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              placeholder,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: filled ? CleanColors.onSurface : CleanColors.outline,
              ),
            ),
          ),
          if (filled)
            const Icon(
              Symbols.cancel,
              size: 20,
              color: CleanColors.outlineVariant,
            ),
        ],
      ),
    );
  }
}

class _InputBlock extends StatelessWidget {
  const _InputBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: CleanColors.secondary,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: CleanColors.surfaceLow,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: CleanColors.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
