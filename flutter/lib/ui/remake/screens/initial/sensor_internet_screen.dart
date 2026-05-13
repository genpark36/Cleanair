import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'setup_flow_scaffold.dart';

class SensorInternetScreen extends StatelessWidget {
  const SensorInternetScreen({super.key, this.onBack, this.onNext});

  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return SetupFlowScaffold(
      step: 4,
      totalSteps: 6,
      onBack: onBack,
      onPrimary: onNext,
      primaryLabel: '설정 완료 후 다음',
      title: '센서 인터넷 설정',
      subtitle: '센서 설정 페이지에서 사용할 2.4GHz Wi-Fi 이름과 비밀번호를 저장해 주세요.',
      children: [
        const _SetupAddressCard(),
        const SizedBox(height: 16),
        SizedBox(
          height: 56,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: SetupColors.white,
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1200B4D8),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: TextButton.icon(
              onPressed: () => _openSetupPage(context),
              icon: const Icon(Symbols.open_in_new, size: 20),
              label: const Text('센서 설정 페이지 열기'),
              style: TextButton.styleFrom(
                foregroundColor: SetupColors.primary,
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const SetupInfoCard(
          icon: Symbols.info,
          title: '자동 입력 제한',
          body:
              '앱은 휴대폰의 Wi-Fi 비밀번호를 자동으로 가져오지 않습니다. 저장 후 센서가 재부팅되면 다음 단계에서 앱에 등록합니다.',
        ),
      ],
    );
  }

  void _openSetupPage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const _SensorSetupWebPage(url: 'http://192.168.4.1'),
      ),
    );
  }
}

class _SetupAddressCard extends StatelessWidget {
  const _SetupAddressCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SetupColors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D171C1F),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: const Column(
        children: [
          _FieldLook(label: '센서 설정 주소', value: 'http://192.168.4.1'),
          SizedBox(height: 12),
          _FieldLook(label: '입력할 정보', value: '2.4GHz Wi-Fi 이름과 비밀번호'),
        ],
      ),
    );
  }
}

class _FieldLook extends StatelessWidget {
  const _FieldLook({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: SetupColors.low,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: SetupColors.muted,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: SetupColors.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Symbols.chevron_right, color: SetupColors.muted),
        ],
      ),
    );
  }
}

class _SensorSetupWebPage extends StatefulWidget {
  const _SensorSetupWebPage({required this.url});

  final String url;

  @override
  State<_SensorSetupWebPage> createState() => _SensorSetupWebPageState();
}

class _SensorSetupWebPageState extends State<_SensorSetupWebPage> {
  late final WebViewController _controller;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(SetupColors.surface)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SetupColors.surface,
      appBar: AppBar(
        backgroundColor: SetupColors.surface,
        elevation: 0,
        foregroundColor: SetupColors.primary,
        title: const Text(
          '센서 설정 페이지',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: SetupColors.primary),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        color: SetupColors.white,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: const Text(
          '페이지가 열리지 않으면 휴대폰 Wi-Fi가 airgradient-센서ID 네트워크에 연결되어 있는지 확인하세요.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            fontWeight: FontWeight.w700,
            color: SetupColors.secondary,
          ),
        ),
      ),
    );
  }
}
