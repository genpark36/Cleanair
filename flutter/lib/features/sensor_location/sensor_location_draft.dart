class SensorLocationDraft {
  const SensorLocationDraft({
    required this.sensorId,
    required this.sensorName,
    required this.spaceName,
    required this.facilityType,
    required this.buildingName,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.floor,
    required this.detailLocation,
    required this.installationMemo,
    required this.updatedAt,
  });

  final String sensorId;
  final String sensorName;
  final String spaceName;
  final String facilityType;
  final String buildingName;
  final String address;
  final double latitude;
  final double longitude;
  final String floor;
  final String detailLocation;
  final String installationMemo;
  final DateTime updatedAt;

  factory SensorLocationDraft.fromJson(Map<String, dynamic> json) {
    final sensorId = _readString(json, 'sensorId', 'sensor-unassigned');
    final sensorName = _readString(json, 'sensorName', sensorId);
    return SensorLocationDraft(
      sensorId: sensorId,
      sensorName: sensorName,
      spaceName: _readString(json, 'spaceName'),
      facilityType: _readString(json, 'facilityType'),
      buildingName: _readString(json, 'buildingName'),
      address: _readString(json, 'address'),
      latitude: _readDouble(json, 'latitude'),
      longitude: _readDouble(json, 'longitude'),
      floor: _readString(json, 'floor'),
      detailLocation: _readString(
        json,
        'detailLocation',
        _readString(json, 'detail'),
      ),
      installationMemo: _readString(
        json,
        'installationMemo',
        _readString(json, 'memo'),
      ),
      updatedAt: _readDateTime(json, 'updatedAt'),
    );
  }

  factory SensorLocationDraft.fromStitchJson(Map<String, dynamic> json) {
    return SensorLocationDraft(
      sensorId: _readString(json, 'sensorId', 'sensor-unassigned'),
      sensorName: _readString(json, 'sensorName', 'sensor-unassigned'),
      spaceName: _readString(json, 'spaceName'),
      facilityType: _readString(json, 'facilityType'),
      buildingName: _readString(json, 'buildingName'),
      address: _readString(json, 'address'),
      latitude: _readDouble(json, 'lat'),
      longitude: _readDouble(json, 'lng'),
      floor: _readString(json, 'floor'),
      detailLocation: _readString(json, 'detail'),
      installationMemo: _readString(json, 'memo'),
      updatedAt: _readDateTime(json, 'updatedAt'),
    );
  }

  SensorLocationDraft copyWith({
    String? sensorId,
    String? sensorName,
    String? spaceName,
    String? facilityType,
    String? buildingName,
    String? address,
    double? latitude,
    double? longitude,
    String? floor,
    String? detailLocation,
    String? installationMemo,
    DateTime? updatedAt,
  }) {
    return SensorLocationDraft(
      sensorId: sensorId ?? this.sensorId,
      sensorName: sensorName ?? this.sensorName,
      spaceName: spaceName ?? this.spaceName,
      facilityType: facilityType ?? this.facilityType,
      buildingName: buildingName ?? this.buildingName,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      floor: floor ?? this.floor,
      detailLocation: detailLocation ?? this.detailLocation,
      installationMemo: installationMemo ?? this.installationMemo,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sensorId': sensorId,
      'sensorName': sensorName,
      'spaceName': spaceName,
      'facilityType': facilityType,
      'buildingName': buildingName,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'floor': floor,
      'detailLocation': detailLocation,
      'installationMemo': installationMemo,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toStitchJson() {
    return <String, dynamic>{
      'sensorId': sensorId,
      'sensorName': sensorName,
      'spaceName': spaceName,
      'facilityType': facilityType,
      'buildingName': buildingName,
      'address': address,
      'floor': floor,
      'detail': detailLocation,
      'memo': installationMemo,
      'lat': latitude,
      'lng': longitude,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  String get coordinatesLabel {
    return '${latitude.toStringAsFixed(4)}° N, '
        '${longitude.toStringAsFixed(4)}° E';
  }

  String get detailsLabel {
    return '$facilityType · $floor · $detailLocation';
  }

  static SensorLocationDraft empty({
    String sensorId = '',
    String sensorName = '',
  }) {
    final resolvedId = sensorId.trim().isEmpty ? 'sensor-unassigned' : sensorId;
    return SensorLocationDraft(
      sensorId: resolvedId,
      sensorName: sensorName.trim().isEmpty ? resolvedId : sensorName,
      spaceName: '',
      facilityType: '',
      buildingName: '',
      address: '',
      latitude: 0,
      longitude: 0,
      floor: '',
      detailLocation: '',
      installationMemo: '',
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

  static double _readDouble(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime _readDateTime(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toLocal();
    }
    return DateTime.now();
  }
}
