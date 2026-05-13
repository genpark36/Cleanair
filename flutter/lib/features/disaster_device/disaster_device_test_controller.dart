import 'disaster_device_draft.dart';
import 'disaster_device_tasmota_adapter.dart';
import 'tasmota_device_test_result.dart';

class DisasterDeviceTestController {
  DisasterDeviceTestController({
    DisasterDeviceTasmotaAdapter? adapter,
  }) : _adapter = adapter ?? DisasterDeviceTasmotaAdapter();

  final DisasterDeviceTasmotaAdapter _adapter;

  Future<TasmotaDeviceTestResult> testConnection(
    DisasterDeviceDraft draft,
  ) async {
    final validationResult = _validateLocalControl(draft);
    if (validationResult != null) return validationResult;

    try {
      final state = await _adapter.getLocalFirstState(draft);
      final telemetry = await _adapter.getLocalFirstTelemetry(draft);
      if (state == true) {
        return TasmotaDeviceTestResult.success(
          statusLabel: '연결 성공 · 현재 ON',
          message: 'Tasmota 장치가 응답했습니다. 현재 전원은 ON입니다.',
          powerOn: true,
          telemetry: telemetry,
        );
      }
      if (state == false) {
        return TasmotaDeviceTestResult.success(
          statusLabel: '연결 성공 · 현재 OFF',
          message: 'Tasmota 장치가 응답했습니다. 현재 전원은 OFF입니다.',
          powerOn: false,
          telemetry: telemetry,
        );
      }

      return TasmotaDeviceTestResult.failure(
        statusLabel: '연결 실패',
        message: '연결 실패 · 같은 Wi-Fi와 IP를 확인해 주세요.',
      );
    } catch (_) {
      return TasmotaDeviceTestResult.failure(
        statusLabel: '연결 실패',
        message: '연결 실패 · 같은 Wi-Fi와 IP를 확인해 주세요.',
      );
    }
  }

  Future<TasmotaDeviceTestResult> testPowerOn(
    DisasterDeviceDraft draft,
  ) {
    final usesMqtt = _adapter.usesMqttControl(draft);
    return _setPower(
      draft,
      turnOn: true,
      reason: 'manual_power_on_test',
      successLabel: usesMqtt ? '원격 켜기 명령 전송됨' : '켜기 테스트 완료',
      failureLabel: usesMqtt ? '원격 켜기 명령 실패' : '켜기 테스트 실패',
      failureMessage: usesMqtt
          ? '원격 켜기 명령 실패 · 원격 제어 정보와 플러그 전원을 확인해 주세요.'
          : '켜기 테스트 실패 · IP, 전원, Wi-Fi를 확인해 주세요.',
    );
  }

  Future<TasmotaDeviceTestResult> testPowerOff(
    DisasterDeviceDraft draft,
  ) {
    final usesMqtt = _adapter.usesMqttControl(draft);
    return _setPower(
      draft,
      turnOn: false,
      reason: 'manual_power_off_test',
      successLabel: usesMqtt ? '원격 끄기 명령 전송됨' : '끄기 테스트 완료',
      failureLabel: usesMqtt ? '원격 끄기 명령 실패' : '끄기 테스트 실패',
      failureMessage: usesMqtt
          ? '원격 끄기 명령 실패 · 원격 제어 정보와 플러그 전원을 확인해 주세요.'
          : '끄기 테스트 실패 · IP, 전원, Wi-Fi를 확인해 주세요.',
    );
  }

  Future<TasmotaDeviceTestResult> runAutoPower(
    DisasterDeviceDraft draft, {
    required bool turnOn,
    required String reason,
  }) {
    final usesMqtt = _adapter.usesMqttControl(draft);
    return _setPower(
      draft,
      turnOn: turnOn,
      mode: 'auto',
      actor: 'cleanair-local-auto',
      reason: reason,
      successLabel: usesMqtt
          ? (turnOn ? '원격 자동 ON 명령 전송됨' : '원격 자동 OFF 명령 전송됨')
          : (turnOn ? '자동 제어 ON 완료' : '자동 제어 OFF 완료'),
      failureLabel: turnOn ? '자동 제어 ON 실패' : '자동 제어 OFF 실패',
      failureMessage: usesMqtt
          ? '자동 제어 실패 · 원격 제어 정보와 플러그 전원을 확인해 주세요.'
          : '자동 제어 실패 · 플러그 IP, 전원, Wi-Fi를 확인해 주세요.',
    );
  }

  Future<String?> syncBackendAutoProfile(
    DisasterDeviceDraft draft, {
    int? aqiOn,
    int? aqiOff,
    String metric = 'iaqi',
    double? onThreshold,
    double? offThreshold,
    List<DisasterAutoRule>? rules,
    required bool enabled,
    int minCommandIntervalSeconds = 120,
  }) {
    return _adapter.syncBackendAutoProfile(
      draft,
      metric: metric,
      onThreshold: onThreshold,
      offThreshold: offThreshold,
      rules: rules,
      aqiOn: aqiOn,
      aqiOff: aqiOff,
      enabled: enabled,
      minCommandIntervalSeconds: minCommandIntervalSeconds,
    );
  }

  TasmotaDeviceTestResult? _validateLocalControl(DisasterDeviceDraft draft) {
    final validationMessage = _adapter.validateControl(draft);
    if (validationMessage == null) return null;

    return TasmotaDeviceTestResult.failure(
      statusLabel: '입력 확인 필요',
      message: validationMessage,
    );
  }

  Future<TasmotaDeviceTestResult> _setPower(
    DisasterDeviceDraft draft, {
    required bool turnOn,
    String mode = 'manual',
    String actor = 'cleanair-remake',
    required String reason,
    required String successLabel,
    required String failureLabel,
    required String failureMessage,
  }) async {
    final validationResult = _validateLocalControl(draft);
    if (validationResult != null) return validationResult;
    final usesMqtt = _adapter.usesMqttControl(draft);

    try {
      var ok = await _adapter.setLocalFirstPower(
        draft,
        turnOn: turnOn,
        mode: mode,
        actor: actor,
        reason: reason,
      );
      if (!ok && usesMqtt) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        ok = await _adapter.setLocalFirstPower(
          draft,
          turnOn: turnOn,
          mode: mode,
          actor: actor,
          reason: '${reason}_retry',
        );
      }
      if (ok) {
        final telemetry = await _adapter.getLocalFirstTelemetry(draft);
        return TasmotaDeviceTestResult.success(
          statusLabel: successLabel,
          message: successLabel,
          powerOn: turnOn,
          telemetry: telemetry,
        );
      }
      return TasmotaDeviceTestResult.failure(
        statusLabel: failureLabel,
        message: failureMessage,
      );
    } catch (_) {
      return TasmotaDeviceTestResult.failure(
        statusLabel: failureLabel,
        message: failureMessage,
      );
    }
  }
}
