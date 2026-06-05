import '../../services/tasmota_plug_service.dart';
import 'disaster_device_draft.dart';

class DisasterDeviceTasmotaAdapter {
  DisasterDeviceTasmotaAdapter({
    TasmotaPlugService? service,
  }) : _service = service ?? TasmotaPlugService();

  static const localIpControlMethod = '로컬 IP 제어';
  static const mqttControlMethod = 'MQTT 제어';

  final TasmotaPlugService _service;

  bool usesLocalIpControl(DisasterDeviceDraft draft) {
    return draft.controlMethod.trim() == localIpControlMethod;
  }

  bool usesMqttControl(DisasterDeviceDraft draft) {
    return draft.controlMethod.trim() == mqttControlMethod ||
        draft.controlMethod.toUpperCase().contains('MQTT');
  }

  String? validateControl(DisasterDeviceDraft draft) {
    if (usesMqttControl(draft)) {
      if (draft.deviceId.trim().isEmpty) {
        return '플러그 정보를 저장할 수 없습니다. 플러그를 다시 추가해 주세요.';
      }
      if (draft.mqttTopic.trim().isEmpty) {
        return '원격 제어 이름을 입력해 주세요.';
      }
      return null;
    }

    if (!usesLocalIpControl(draft)) {
      return '제어 방식은 같은 Wi-Fi 또는 원격 제어 중 하나를 선택해 주세요.';
    }

    final address = _normalizeLocalAddress(draft.plugIp);
    if (address.isEmpty) {
      return '플러그 IP를 입력해 주세요.';
    }
    if (!_isValidLocalAddress(address)) {
      return 'IP 또는 로컬 주소 형식을 확인해 주세요. 예: 192.168.0.24';
    }
    return null;
  }

  Future<bool?> getLocalFirstState(DisasterDeviceDraft draft) async {
    _applyDraft(draft);
    if (usesMqttControl(draft)) {
      await _registerMqttPlug(draft);
    }
    return _service.getPlugState();
  }

  Future<Map<String, dynamic>> getLocalFirstTelemetry(
    DisasterDeviceDraft draft,
  ) async {
    _applyDraft(draft);
    if (usesMqttControl(draft)) {
      await _registerMqttPlug(draft);
    }
    return _service.getPlugTelemetry();
  }

  Future<bool> setLocalFirstPower(
    DisasterDeviceDraft draft, {
    required bool turnOn,
    String mode = 'manual',
    String actor = 'cleanair-remake',
    required String reason,
  }) async {
    _applyDraft(draft);
    if (usesMqttControl(draft)) {
      await _registerMqttPlug(draft);
    }
    return _service.setPlugState(
      turnOn,
      mode: mode,
      actor: actor,
      reason: reason,
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
  }) async {
    _applyDraft(draft);
    final normalizedMetric = _normalizeAutoMetric(metric);
    final resolvedOn = onThreshold ?? (aqiOn == null ? null : aqiOn / 100);
    final resolvedOff = offThreshold ?? (aqiOff == null ? null : aqiOff / 100);
    if (resolvedOn == null || resolvedOff == null) return null;

    final profileId = '${draft.deviceId.trim()}-auto-$normalizedMetric';
    final syncedProfileId = await _service.upsertAqiProfile(
      profileId: profileId,
      name: 'CleanAir ${_autoMetricLabel(normalizedMetric)} 자동 제어',
      metric: normalizedMetric,
      onThreshold: resolvedOn,
      offThreshold: resolvedOff,
      rules: rules ?? draft.autoRules,
      aqiOn: aqiOn,
      aqiOff: aqiOff,
      minCommandIntervalSeconds: minCommandIntervalSeconds,
    );
    final profileToUse = syncedProfileId ?? profileId;
    final registered = await _service.registerPlug(
      plugId: draft.deviceId,
      displayName: draft.displayName,
      sensorId: draft.linkedSensorId,
      tasmotaTopic: draft.mqttTopic,
      profileId: profileToUse,
      mode: enabled ? 'auto' : 'manual',
      controlEnabled: enabled,
      transportPrimary: draft.controlMethod.contains('MQTT') ? 'MQTT' : 'HTTP',
      transportFallback: 'HTTP',
    );
    return registered ? profileToUse : null;
  }

  void _applyDraft(DisasterDeviceDraft draft) {
    _service.plugId = draft.deviceId.trim();
    _service.plugIpAddress = _normalizeLocalAddress(draft.plugIp);
    _service.preferLocalControl = usesLocalIpControl(draft);
  }

  Future<void> _registerMqttPlug(DisasterDeviceDraft draft) async {
    await _service.registerPlug(
      plugId: draft.deviceId,
      displayName: draft.displayName,
      sensorId: draft.linkedSensorId,
      tasmotaTopic: draft.mqttTopic,
      mode: draft.autoControlEnabled ? 'auto' : 'manual',
      controlEnabled: true,
      transportPrimary: 'MQTT',
      transportFallback: 'HTTP',
    );
  }

  String _normalizeLocalAddress(String value) {
    var text = value.trim();
    if (text.isEmpty) return '';
    text = text.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    final slash = text.indexOf('/');
    if (slash >= 0) {
      text = text.substring(0, slash);
    }
    return text.trim();
  }

  bool _isValidLocalAddress(String value) {
    if (_isValidIpv4(value)) return true;
    final host = value.split(':').first.trim();
    return host.isNotEmpty &&
        host.length <= 253 &&
        RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$').hasMatch(host);
  }

  bool _isValidIpv4(String value) {
    final host = value.split(':').first.trim();
    final parts = host.split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      if (part.isEmpty || !_digitsOnly.hasMatch(part)) return false;
      final parsed = int.tryParse(part);
      if (parsed == null || parsed < 0 || parsed > 255) return false;
    }
    return true;
  }

  static final _digitsOnly = RegExp(r'^\d+$');

  String _normalizeAutoMetric(String value) {
    final normalized = value.trim().toLowerCase();
    const allowed = {'iaqi', 'co2', 'co', 'pm25', 'tvoc', 'nox'};
    return allowed.contains(normalized) ? normalized : 'iaqi';
  }

  String _autoMetricLabel(String metric) {
    switch (_normalizeAutoMetric(metric)) {
      case 'co2':
        return 'CO2';
      case 'co':
        return 'CO';
      case 'pm25':
        return 'PM2.5';
      case 'tvoc':
        return 'TVOC';
      case 'nox':
        return 'NOx';
      case 'iaqi':
      default:
        return 'IAQI';
    }
  }
}
