class DisasterDeviceDraft {
  const DisasterDeviceDraft({
    required this.deviceId,
    required this.displayName,
    required this.deviceType,
    required this.controlMethod,
    required this.plugIp,
    required this.mqttTopic,
    required this.linkedSensorId,
    required this.linkedSpaceName,
    required this.linkedAddress,
    required this.description,
    required this.autoControlEnabled,
    required this.autoMetric,
    required this.autoOnThreshold,
    required this.autoOffThreshold,
    required this.autoHysteresisPercent,
    required this.autoRules,
    required this.autoHoldMinutes,
    required this.purpose,
    required this.lastTestStatus,
    this.currentPowerOn,
    this.telemetry = const <String, dynamic>{},
    this.lastPowerChangedAt,
    this.manualOverrideUntil,
    required this.updatedAt,
  });

  final String deviceId;
  final String displayName;
  final String deviceType;
  final String controlMethod;
  final String plugIp;
  final String mqttTopic;
  final String linkedSensorId;
  final String linkedSpaceName;
  final String linkedAddress;
  final String description;
  final bool autoControlEnabled;
  final String autoMetric;
  final double autoOnThreshold;
  final double autoOffThreshold;
  final double autoHysteresisPercent;
  final List<DisasterAutoRule> autoRules;
  final int autoHoldMinutes;
  final String purpose;
  final String lastTestStatus;
  final bool? currentPowerOn;
  final Map<String, dynamic> telemetry;
  final DateTime? lastPowerChangedAt;
  final DateTime? manualOverrideUntil;
  final DateTime updatedAt;

  DisasterDeviceDraft copyWith({
    String? deviceId,
    String? displayName,
    String? deviceType,
    String? controlMethod,
    String? plugIp,
    String? mqttTopic,
    String? linkedSensorId,
    String? linkedSpaceName,
    String? linkedAddress,
    String? description,
    bool? autoControlEnabled,
    String? autoMetric,
    double? autoOnThreshold,
    double? autoOffThreshold,
    double? autoHysteresisPercent,
    List<DisasterAutoRule>? autoRules,
    int? autoHoldMinutes,
    String? purpose,
    String? lastTestStatus,
    Object? currentPowerOn = _sentinel,
    Map<String, dynamic>? telemetry,
    Object? lastPowerChangedAt = _sentinel,
    Object? manualOverrideUntil = _sentinel,
    DateTime? updatedAt,
  }) {
    return DisasterDeviceDraft(
      deviceId: deviceId ?? this.deviceId,
      displayName: displayName ?? this.displayName,
      deviceType: deviceType ?? this.deviceType,
      controlMethod: controlMethod ?? this.controlMethod,
      plugIp: plugIp ?? this.plugIp,
      mqttTopic: mqttTopic ?? this.mqttTopic,
      linkedSensorId: linkedSensorId ?? this.linkedSensorId,
      linkedSpaceName: linkedSpaceName ?? this.linkedSpaceName,
      linkedAddress: linkedAddress ?? this.linkedAddress,
      description: description ?? this.description,
      autoControlEnabled: autoControlEnabled ?? this.autoControlEnabled,
      autoMetric: autoMetric ?? this.autoMetric,
      autoOnThreshold: autoOnThreshold ?? this.autoOnThreshold,
      autoOffThreshold: autoOffThreshold ?? this.autoOffThreshold,
      autoHysteresisPercent:
          autoHysteresisPercent ?? this.autoHysteresisPercent,
      autoRules: autoRules ?? this.autoRules,
      autoHoldMinutes: autoHoldMinutes ?? this.autoHoldMinutes,
      purpose: purpose ?? this.purpose,
      lastTestStatus: lastTestStatus ?? this.lastTestStatus,
      currentPowerOn: identical(currentPowerOn, _sentinel)
          ? this.currentPowerOn
          : currentPowerOn as bool?,
      telemetry: telemetry ?? this.telemetry,
      lastPowerChangedAt: identical(lastPowerChangedAt, _sentinel)
          ? this.lastPowerChangedAt
          : lastPowerChangedAt as DateTime?,
      manualOverrideUntil: identical(manualOverrideUntil, _sentinel)
          ? this.manualOverrideUntil
          : manualOverrideUntil as DateTime?,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory DisasterDeviceDraft.fromJson(Map<String, dynamic> json) {
    final autoOnThreshold = _readDouble(json, 'autoOnThreshold', 1.2);
    final autoHysteresisPercent =
        _readDouble(json, 'autoHysteresisPercent', 25);
    final migratedAutoOffThreshold = autoOnThreshold *
        (1 - autoHysteresisPercent.clamp(1, 90).toDouble() / 100);
    final legacyMetric = _readString(json, 'autoMetric', 'iaqi');
    final legacyOffThreshold =
        _readDouble(json, 'autoOffThreshold', migratedAutoOffThreshold);
    final rules = _readRules(
      json,
      legacyMetric: legacyMetric,
      legacyOnThreshold: autoOnThreshold,
      legacyOffThreshold: legacyOffThreshold,
      legacyHysteresisPercent: autoHysteresisPercent,
    );

    return DisasterDeviceDraft(
      deviceId: _readString(json, 'deviceId', 'disaster-device-local'),
      displayName: _readString(json, 'displayName', '스마트 플러그'),
      deviceType: _readString(json, 'deviceType'),
      controlMethod: _readString(json, 'controlMethod', '로컬 IP 제어'),
      plugIp: _readString(json, 'plugIp'),
      mqttTopic: _readString(json, 'mqttTopic'),
      linkedSensorId: _readString(json, 'linkedSensorId'),
      linkedSpaceName: _readString(json, 'linkedSpaceName'),
      linkedAddress: _readString(json, 'linkedAddress'),
      description: _readString(json, 'description'),
      autoControlEnabled: json['autoControlEnabled'] == true,
      autoMetric: legacyMetric,
      autoOnThreshold: autoOnThreshold,
      autoOffThreshold: legacyOffThreshold,
      autoHysteresisPercent: autoHysteresisPercent,
      autoRules: rules,
      autoHoldMinutes: _readInt(json, 'autoHoldMinutes', 2),
      purpose: _readString(json, 'purpose'),
      lastTestStatus: _readString(json, 'lastTestStatus', '테스트 전'),
      currentPowerOn: json['currentPowerOn'] is bool
          ? json['currentPowerOn'] as bool
          : null,
      telemetry: json['telemetry'] is Map
          ? Map<String, dynamic>.from(json['telemetry'] as Map)
          : const <String, dynamic>{},
      lastPowerChangedAt: _readNullableDateTime(json, 'lastPowerChangedAt'),
      manualOverrideUntil: _readNullableDateTime(json, 'manualOverrideUntil'),
      updatedAt: _readDateTime(json, 'updatedAt'),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'deviceId': deviceId,
      'displayName': displayName,
      'deviceType': deviceType,
      'controlMethod': controlMethod,
      'plugIp': plugIp,
      'mqttTopic': mqttTopic,
      'linkedSensorId': linkedSensorId,
      'linkedSpaceName': linkedSpaceName,
      'linkedAddress': linkedAddress,
      'description': description,
      'autoControlEnabled': autoControlEnabled,
      'autoMetric': autoMetric,
      'autoOnThreshold': autoOnThreshold,
      'autoOffThreshold': autoOffThreshold,
      'autoHysteresisPercent': autoHysteresisPercent,
      'autoRules': autoRules.map((rule) => rule.toJson()).toList(),
      'autoHoldMinutes': autoHoldMinutes,
      'purpose': purpose,
      'lastTestStatus': lastTestStatus,
      'currentPowerOn': currentPowerOn,
      'telemetry': telemetry,
      'lastPowerChangedAt': lastPowerChangedAt?.toIso8601String(),
      'manualOverrideUntil': manualOverrideUntil?.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static DisasterDeviceDraft empty({
    String? linkedSensorId,
    String? linkedSpaceName,
    String? linkedAddress,
  }) {
    return DisasterDeviceDraft(
      deviceId: 'disaster-device-local',
      displayName: '스마트 플러그',
      deviceType: '스마트 플러그',
      controlMethod: '로컬 IP 제어',
      plugIp: '',
      mqttTopic: '',
      linkedSensorId: linkedSensorId ?? '',
      linkedSpaceName: linkedSpaceName ?? '등록된 공간',
      linkedAddress: linkedAddress ?? '',
      description: '',
      autoControlEnabled: false,
      autoMetric: 'iaqi',
      autoOnThreshold: 1.2,
      autoOffThreshold: 0.9,
      autoHysteresisPercent: 25,
      autoRules: const [
        DisasterAutoRule(
          metric: 'iaqi',
          onThreshold: 1.2,
          offThreshold: 0.9,
          hysteresisPercent: 25,
        ),
      ],
      autoHoldMinutes: 2,
      purpose: '',
      lastTestStatus: '테스트 전',
      currentPowerOn: null,
      telemetry: const <String, dynamic>{},
      lastPowerChangedAt: null,
      manualOverrideUntil: null,
      updatedAt: DateTime.now(),
    );
  }

  static String _readString(
    Map<String, dynamic> json,
    String key, [
    String fallback = '',
  ]) {
    final value = json[key];
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static DateTime _readDateTime(Map<String, dynamic> json, String key) {
    return _readNullableDateTime(json, key) ?? DateTime.now();
  }

  static DateTime? _readNullableDateTime(
      Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toLocal();
    }
    return null;
  }

  static double _readDouble(
    Map<String, dynamic> json,
    String key,
    double fallback,
  ) {
    final value = json[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  static int _readInt(Map<String, dynamic> json, String key, int fallback) {
    final value = json[key];
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static const _sentinel = Object();

  static List<DisasterAutoRule> _readRules(
    Map<String, dynamic> json, {
    required String legacyMetric,
    required double legacyOnThreshold,
    required double legacyOffThreshold,
    required double legacyHysteresisPercent,
  }) {
    final value = json['autoRules'];
    if (value is List) {
      final parsed = value
          .whereType<Map>()
          .map((item) => DisasterAutoRule.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((rule) => rule.metric.trim().isNotEmpty)
          .toList(growable: false);
      if (parsed.isNotEmpty) return parsed;
    }
    return <DisasterAutoRule>[
      DisasterAutoRule(
        metric: legacyMetric,
        onThreshold: legacyOnThreshold,
        offThreshold: legacyOffThreshold,
        hysteresisPercent: legacyHysteresisPercent,
      ),
    ];
  }
}

class DisasterAutoRule {
  const DisasterAutoRule({
    required this.metric,
    required this.onThreshold,
    required this.offThreshold,
    required this.hysteresisPercent,
  });

  final String metric;
  final double onThreshold;
  final double offThreshold;
  final double hysteresisPercent;

  DisasterAutoRule copyWith({
    String? metric,
    double? onThreshold,
    double? offThreshold,
    double? hysteresisPercent,
  }) {
    return DisasterAutoRule(
      metric: metric ?? this.metric,
      onThreshold: onThreshold ?? this.onThreshold,
      offThreshold: offThreshold ?? this.offThreshold,
      hysteresisPercent: hysteresisPercent ?? this.hysteresisPercent,
    );
  }

  factory DisasterAutoRule.fromJson(Map<String, dynamic> json) {
    final metric = _readString(json, 'metric', 'iaqi');
    final onThreshold = _readDouble(json, 'onThreshold', 1.2);
    final hysteresisPercent = _readDouble(json, 'hysteresisPercent', 25);
    final fallbackOff =
        onThreshold * (1 - hysteresisPercent.clamp(1, 90).toDouble() / 100);
    return DisasterAutoRule(
      metric: metric,
      onThreshold: onThreshold,
      offThreshold: _readDouble(json, 'offThreshold', fallbackOff),
      hysteresisPercent: hysteresisPercent,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'metric': metric,
      'onThreshold': onThreshold,
      'offThreshold': offThreshold,
      'hysteresisPercent': hysteresisPercent,
    };
  }

  static String _readString(
    Map<String, dynamic> json,
    String key, [
    String fallback = '',
  ]) {
    final value = json[key];
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static double _readDouble(
    Map<String, dynamic> json,
    String key,
    double fallback,
  ) {
    final value = json[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }
}
