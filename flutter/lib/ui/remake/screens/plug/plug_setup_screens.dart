import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:provider/provider.dart';

import '../../../../features/disaster_device/disaster_device_draft.dart';
import '../../../../features/disaster_device/disaster_device_storage.dart';
import '../../../../features/sensor_location/sensor_location_draft.dart';
import '../../../../features/sensor_location/sensor_location_storage.dart';
import '../../../../services/device_binding_service_v2.dart';
import '../shared/cleanair_stitch_widgets.dart';

class PlugPowerScreen extends StatelessWidget {
  const PlugPowerScreen({super.key, this.onBack, this.onNext});

  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return MockScreenShell(
      title: '신규 플러그 등록',
      leading: Symbols.arrow_back,
      trailing: Symbols.help,
      bottomNav: false,
      onLeadingTap: onBack,
      children: [
        const _PlugProgress(step: 1),
        const SizedBox(height: 32),
        const MockHeader(
          eyebrow: 'STEP 1 / 4',
          heading: '플러그 전원 연결',
          subtitle: 'Athom 스마트 플러그를 벽면 콘센트에 꽂고 파란색 LED가 깜빡일 때까지 기다려 주세요.',
        ),
        const SizedBox(height: 28),
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 210,
                height: 210,
                decoration: BoxDecoration(
                  color: CleanColors.primaryFixed.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 148,
                height: 148,
                decoration: BoxDecoration(
                  color: CleanColors.surfaceLowest,
                  borderRadius: BorderRadius.circular(44),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 28,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Symbols.bolt,
                  size: 76,
                  color: CleanColors.primaryContainer,
                  fill: 1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            const url = 'https://tasmota.github.io/docs/Getting-Started/';
            Clipboard.setData(const ClipboardData(text: url));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Tasmota 설정 문서 URL을 복사했습니다.'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          child: MockCard(
          color: CleanColors.surfaceLow,
          child: Row(
            children: const [
              IconBubble(icon: Symbols.system_update, size: 44),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FIRMWARE INSTALLATION',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.6,
                        color: CleanColors.secondary,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Tasmota 펌웨어 설치 URL 복사',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: CleanColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Symbols.content_copy, size: 18, color: CleanColors.primary),
            ],
          ),
          ),
        ),
        const SizedBox(height: 34),
        GradientButton(label: '다음', onTap: onNext),
      ],
    );
  }
}

class PlugWifiScreen extends StatelessWidget {
  const PlugWifiScreen({super.key, this.onBack, this.onNext});

  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return MockScreenShell(
      title: '신규 플러그 등록',
      leading: Symbols.arrow_back,
      trailing: Symbols.settings,
      bottomNav: false,
      onLeadingTap: onBack,
      children: [
        const _PlugProgress(step: 2),
        const SizedBox(height: 24),
        const MockHeader(
          eyebrow: 'STEP 2 OF 4',
          heading: '플러그 Wi-Fi에 연결',
          subtitle: "휴대폰의 Wi-Fi 설정에서 'Athom-Tasmota-XXXX' 네트워크를 선택해 주세요.",
        ),
        const SizedBox(height: 24),
        MockCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Wi-Fi 설정',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: CleanColors.onVariant,
                    ),
                  ),
                  Icon(Symbols.settings, size: 17, color: CleanColors.outline),
                ],
              ),
              SizedBox(height: 14),
              _WifiChoice(title: 'Home_Network_5G', locked: true),
              _WifiChoice(title: 'Athom-Tasmota-XXXX', selected: true),
              _WifiChoice(title: 'Guest_Wi-Fi', locked: true),
            ],
          ),
        ),
        const SizedBox(height: 18),
        MockCard(
          color: CleanColors.primaryFixed,
          child: Row(
            children: const [
              Icon(Symbols.info, color: CleanColors.primary, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  '연결 후 자동 설정 페이지가 열리지 않으면 브라우저에서 192.168.4.1로 접속하세요.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF004E5F),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        GradientButton(label: '연결 완료', onTap: onNext),
      ],
    );
  }
}

class PlugInternetScreen extends StatefulWidget {
  const PlugInternetScreen({super.key, this.onBack, this.onNext});

  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  State<PlugInternetScreen> createState() => _PlugInternetScreenState();
}

class _PlugInternetScreenState extends State<PlugInternetScreen> {
  final _storage = DisasterDeviceStorage();
  final _locationStorage = SensorLocationStorage();
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _ipController = TextEditingController();

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSavedDevice());
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedDevice() async {
    final stored = await _storage.load();
    if (!mounted || stored == null) return;
    _nameController.text = stored.displayName;
    _ipController.text = stored.plugIp;
  }

  Future<void> _saveAndContinue() async {
    if (_busy) return;
    final binding = context.read<DeviceBindingControllerV2>().value;
    setState(() => _busy = true);
    try {
      final location = await _locationStorage.loadForSensor(binding.deviceId);
      final stored = await _storage.load();
      final draft = _draftFromInputs(
        base: stored,
        location: location,
        sensorId: binding.deviceId,
      );
      await _storage.save(draft);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            draft.plugIp.trim().isEmpty
                ? '장치 기록을 저장했습니다. IP를 확인하면 ON/OFF 테스트를 실행할 수 있습니다.'
                : '장치 정보를 저장했습니다. 장치 관리에서 연결 테스트를 실행할 수 있습니다.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      widget.onNext?.call();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('장치 정보 저장 실패: $error'),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  DisasterDeviceDraft _draftFromInputs({
    required DisasterDeviceDraft? base,
    required SensorLocationDraft? location,
    required String sensorId,
  }) {
    final fallback = base ??
        DisasterDeviceDraft.empty(
          linkedSensorId: sensorId,
          linkedSpaceName: location?.spaceName,
          linkedAddress: location?.address,
        );
    final name = _nameController.text.trim();
    final ip = _ipController.text.trim();
    final linkedSpaceName = fallback.linkedSpaceName.trim().isNotEmpty
        ? fallback.linkedSpaceName
        : location?.spaceName ?? '등록된 공간';
    final linkedAddress = fallback.linkedAddress.trim().isNotEmpty
        ? fallback.linkedAddress
        : location?.address ?? '';

    return fallback.copyWith(
      displayName: name.isEmpty ? '방재 스마트 플러그' : name,
      deviceType: fallback.deviceType.trim().isEmpty ? '스마트 플러그' : null,
      controlMethod: fallback.controlMethod.trim().isEmpty ? '로컬 IP 제어' : null,
      plugIp: ip,
      linkedSensorId: fallback.linkedSensorId.trim().isNotEmpty
          ? fallback.linkedSensorId
          : sensorId,
      linkedSpaceName: linkedSpaceName,
      linkedAddress: linkedAddress,
      purpose: fallback.purpose.trim().isEmpty ? '이상 징후 대응 장치' : null,
      lastTestStatus: ip.isEmpty ? 'IP 설정 필요' : '로컬 IP 저장됨',
      updatedAt: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MockScreenShell(
      title: '신규 플러그 등록',
      leading: Symbols.arrow_back,
      trailing: Symbols.help,
      bottomNav: false,
      onLeadingTap: widget.onBack,
      children: [
        const _PlugProgress(step: 3),
        const SizedBox(height: 28),
        const MockHeader(
          eyebrow: 'STEP 3 / 4',
          heading: '인터넷 연결 설정',
          subtitle: 'Tasmota 웹 설정에서 Wi-Fi를 저장한 뒤 앱에는 장치 이름과 로컬 IP를 기록합니다.',
        ),
        const SizedBox(height: 24),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: CleanColors.surfaceLow,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Symbols.wifi, size: 17, color: CleanColors.primary),
                SizedBox(width: 6),
                Text(
                  '192.168.4.1 접속',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: CleanColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),
        _InputBox(
          label: 'SSID',
          placeholder: 'Wi-Fi 네트워크 이름',
          controller: _ssidController,
        ),
        const SizedBox(height: 16),
        _InputBox(
          label: 'Password',
          placeholder: '비밀번호 입력',
          controller: _passwordController,
          obscureText: true,
        ),
        const SizedBox(height: 16),
        _InputBox(
          label: 'Device name',
          placeholder: '방재 스마트 플러그',
          controller: _nameController,
        ),
        const SizedBox(height: 16),
        _InputBox(
          label: 'Local IP',
          placeholder: '192.168.0.24',
          controller: _ipController,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 20),
        MockCard(
          color: CleanColors.surfaceLow,
          child: Row(
            children: const [
              Icon(Symbols.info, color: CleanColors.primaryContainer, size: 22),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Athom/Tasmota 플러그는 2.4GHz Wi-Fi만 지원합니다. 5GHz 네트워크는 선택하지 마세요.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: CleanColors.secondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        GradientButton(
          label: _busy ? '저장 중' : '장치 정보 저장',
          icon: Symbols.save,
          onTap: _busy ? null : _saveAndContinue,
        ),
      ],
    );
  }
}

class PlugCompleteScreen extends StatefulWidget {
  const PlugCompleteScreen({
    super.key,
    this.onBack,
    this.onDone,
    this.onAddMore,
  });

  final VoidCallback? onBack;
  final VoidCallback? onDone;
  final VoidCallback? onAddMore;

  @override
  State<PlugCompleteScreen> createState() => _PlugCompleteScreenState();
}

class _PlugCompleteScreenState extends State<PlugCompleteScreen> {
  final _storage = DisasterDeviceStorage();
  late Future<DisasterDeviceDraft?> _future;

  @override
  void initState() {
    super.initState();
    _future = _storage.load();
  }

  @override
  Widget build(BuildContext context) {
    return MockScreenShell(
      title: '신규 플러그 등록',
      leading: Symbols.arrow_back,
      trailing: Symbols.settings,
      bottomNav: false,
      background: Colors.white,
      onLeadingTap: widget.onBack,
      children: [
        const SizedBox(height: 28),
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 236,
                height: 236,
                decoration: BoxDecoration(
                  color: CleanColors.primaryFixed.withValues(alpha: 0.38),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 132,
                height: 132,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [CleanColors.primary, CleanColors.primaryContainer],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Symbols.check_circle,
                  size: 70,
                  color: Colors.white,
                  fill: 1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        const MockHeader(
          heading: '플러그가 성공적으로\n연결되었습니다!',
          subtitle: '저장된 장치 정보로 연결 테스트와 수동 전원 조작을 이어갈 수 있습니다.',
          center: true,
        ),
        const SizedBox(height: 28),
        FutureBuilder<DisasterDeviceDraft?>(
          future: _future,
          builder: (context, snapshot) {
            final draft = snapshot.data;
            final displayName = draft?.displayName.trim().isNotEmpty == true
                ? draft!.displayName
                : '방재 스마트 플러그';
            final ip = draft?.plugIp.trim() ?? '';
            final spaceName = draft?.linkedSpaceName.trim() ?? '';

            return MockCard(
              child: Column(
                children: [
                  InfoRow(
                    icon: Symbols.power,
                    title: displayName,
                    subtitle: ip.isEmpty
                        ? '등록 완료 · 장치 관리에서 IP를 입력하면 테스트할 수 있습니다'
                        : '등록 완료 · $ip',
                  ),
                  const SizedBox(height: 14),
                  InfoRow(
                    icon: Symbols.router,
                    title: ip.isEmpty ? '로컬 네트워크 확인 필요' : '로컬 네트워크 우선 연결',
                    subtitle: spaceName.isEmpty
                        ? '센서 위치와 연결하면 방재 판단에 함께 사용됩니다'
                        : spaceName,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 28),
        GradientButton(label: '장치 관리로 이동', onTap: widget.onDone),
        const SizedBox(height: 12),
        Center(
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: widget.onAddMore,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                '다른 플러그 추가하기',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: CleanColors.primary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlugProgress extends StatelessWidget {
  const _PlugProgress({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(4, (index) {
        final active = index < step;
        return Expanded(
          child: Container(
            height: 6,
            margin: EdgeInsets.only(right: index == 3 ? 0 : 7),
            decoration: BoxDecoration(
              color: active
                  ? CleanColors.primaryContainer
                  : CleanColors.surfaceHighest,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        );
      }),
    );
  }
}

class _WifiChoice extends StatelessWidget {
  const _WifiChoice({
    required this.title,
    this.selected = false,
    this.locked = false,
  });

  final String title;
  final bool selected;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color:
            selected ? CleanColors.primaryFixed.withValues(alpha: 0.45) : null,
        borderRadius: BorderRadius.circular(14),
        border: selected
            ? const Border(
                bottom: BorderSide(color: CleanColors.primary, width: 2),
              )
            : null,
      ),
      child: Row(
        children: [
          Icon(
            selected ? Symbols.wifi_tethering : Symbols.wifi,
            size: 22,
            color: selected ? CleanColors.primary : CleanColors.secondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? CleanColors.primary : CleanColors.onVariant,
              ),
            ),
          ),
          Icon(
            selected
                ? Symbols.check_circle
                : locked
                    ? Symbols.lock
                    : Symbols.chevron_right,
            size: 18,
            color: selected ? CleanColors.primary : CleanColors.outline,
            fill: selected ? 1 : 0,
          ),
        ],
      ),
    );
  }
}

class _InputBox extends StatelessWidget {
  const _InputBox({
    required this.label,
    required this.placeholder,
    this.controller,
    this.keyboardType,
    this.obscureText = false,
  });

  final String label;
  final String placeholder;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.7,
              color: CleanColors.secondary,
            ),
          ),
        ),
        Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: CleanColors.surfaceHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: controller == null
              ? Text(
                  placeholder,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: CleanColors.outline,
                  ),
                )
              : TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  obscureText: obscureText,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: placeholder,
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: CleanColors.outline,
                    ),
                  ),
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
