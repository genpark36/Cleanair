/// Data model that mirrors the Node-RED `airgradient/v1/snapshot` payload.
class AirQualitySnapshot {
  AirQualitySnapshot({
    required this.id,
    required this.timestamp,
    this.pm25,
    this.co2,
    this.tvoc,
    this.nox,
    this.temperature,
    this.humidity,
    this.dewPoint,
    this.discomfortIndex,
    this.iaqiScore,
    this.aqiLevel,
    this.aqiCategory,
    this.respiratoryIndex,
    this.immunityRisk,
    this.cognitiveFocus,
    this.cardioScore,
    this.cardioRisk,
    this.sleepComfort,
    this.apparentTemp,
    this.seasonalApparent,
    this.purifier,
    this.ipi,
    this.child,
    this.senior,
    this.purification,
    this.locationComparison,
    this.meta,
    this.location,
    this.alerts,
  });

  final String? id;
  final DateTime timestamp;
  final double? pm25;
  final double? co2;
  final double? tvoc;
  final double? nox;
  final double? temperature;
  final double? humidity;
  final double? dewPoint;
  final double? discomfortIndex;
  final int? iaqiScore;
  final String? aqiLevel;
  final String? aqiCategory;
  final double? respiratoryIndex;
  final double? immunityRisk;
  final double? cognitiveFocus;
  final double? cardioScore;
  final double? cardioRisk;
  final double? sleepComfort;
  final double? apparentTemp;
  final SeasonalApparentSnapshot? seasonalApparent;
  final PurifierSnapshot? purifier;
  final IpiSnapshot? ipi;
  final ChildHealthSnapshot? child;
  final SeniorHealthSnapshot? senior;
  final PurificationSummary? purification;
  final LocationComparisonSnapshot? locationComparison;
  final SnapshotMeta? meta;
  final SnapshotLocation? location;
  final SnapshotAlerts? alerts;

  bool get hasCoreMetrics =>
      pm25 != null && co2 != null && temperature != null && humidity != null;

  AirQualitySnapshot copyWith({
    DateTime? timestamp,
    double? pm25,
    double? co2,
    double? tvoc,
    double? nox,
    double? temperature,
    double? humidity,
    double? dewPoint,
    double? discomfortIndex,
    int? iaqiScore,
    String? aqiLevel,
    String? aqiCategory,
    PurifierSnapshot? purifier,
    IpiSnapshot? ipi,
    ChildHealthSnapshot? child,
    SeniorHealthSnapshot? senior,
    PurificationSummary? purification,
    LocationComparisonSnapshot? locationComparison,
    SnapshotMeta? meta,
    SnapshotLocation? location,
    SnapshotAlerts? alerts,
    SeasonalApparentSnapshot? seasonalApparent,
  }) {
    return AirQualitySnapshot(
      id: id,
      timestamp: timestamp ?? this.timestamp,
      pm25: pm25 ?? this.pm25,
      co2: co2 ?? this.co2,
      tvoc: tvoc ?? this.tvoc,
      nox: nox ?? this.nox,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      dewPoint: dewPoint ?? this.dewPoint,
      discomfortIndex: discomfortIndex ?? this.discomfortIndex,
      iaqiScore: iaqiScore ?? this.iaqiScore,
      aqiLevel: aqiLevel ?? this.aqiLevel,
      aqiCategory: aqiCategory ?? this.aqiCategory,
      respiratoryIndex: respiratoryIndex,
      immunityRisk: immunityRisk,
      cognitiveFocus: cognitiveFocus,
      cardioScore: cardioScore,
      cardioRisk: cardioRisk,
      sleepComfort: sleepComfort,
      apparentTemp: apparentTemp,
      seasonalApparent: seasonalApparent ?? this.seasonalApparent,
      purifier: purifier ?? this.purifier,
      ipi: ipi ?? this.ipi,
      child: child ?? this.child,
      senior: senior ?? this.senior,
      purification: purification ?? this.purification,
      locationComparison: locationComparison ?? this.locationComparison,
      meta: meta ?? this.meta,
      location: location ?? this.location,
      alerts: alerts ?? this.alerts,
    );
  }

  factory AirQualitySnapshot.fromJson(Map<String, dynamic> json) {
    final raw = _asMap(json['raw']);
    final derived = _asMap(json['derived']);
    final health = _asMap(json['health']);
    final purifier = PurifierSnapshot.tryParse(_asMap(health?['purifier']));
    final ipi = IpiSnapshot.tryParse(_asMap(health?['ipi']));
    final child = ChildHealthSnapshot.tryParse(
      _firstMap(health?['child'], json['child'], json['child_mode']),
    );
    final senior = SeniorHealthSnapshot.tryParse(
      _firstMap(health?['senior'], json['senior'], json['senior_mode']),
    );
    final purification = PurificationSummary.tryParse(
      _firstMap(
        health?['purification'],
        json['purification'],
        json['purification_mode'],
      ),
    );
    final meta = SnapshotMeta.tryParse(_asMap(json['meta']));
    final location = SnapshotLocation.tryParse(_asMap(json['location']));
    final alerts = SnapshotAlerts.tryParse(_asMap(json['alerts']));
    final locationComparison = LocationComparisonSnapshot.tryParse(
      _asMap(json['location_compare']) ??
          _asMap(json['locationComparison']) ??
          _asMap(json['locationCompare']),
    );
    final seasonalApparent =
      SeasonalApparentSnapshot.tryParse(_asMap(health?['seasonalApparent']));

    return AirQualitySnapshot(
      id: json['id']?.toString(),
      timestamp: _parseTimestamp(json['timestamp']) ?? DateTime.now(),
      pm25: _asDouble(raw?['pm25']),
      co2: _asDouble(raw?['co2']),
      tvoc: _asDouble(raw?['tvoc']),
      nox: _asDouble(raw?['nox']),
      temperature: _asDouble(raw?['temp']) ?? _asDouble(raw?['temperature']),
      humidity: _asDouble(raw?['humidity']),
      dewPoint: _asDouble(derived?['dewPoint']),
      discomfortIndex: _asDouble(derived?['discomfortIndex']),
      iaqiScore: _asInt(derived?['iaqiScore']),
      aqiLevel: derived?['aqiLevel']?.toString(),
      aqiCategory: derived?['aqiCategory']?.toString(),
      respiratoryIndex: _asDouble(health?['respiratoryIndex']),
      immunityRisk: _asDouble(health?['immunityRisk']),
      cognitiveFocus: _asDouble(health?['cognitiveFocus']),
      cardioScore: _asDouble(health?['cardioScore']),
      cardioRisk: _asDouble(health?['cardioRisk']),
      sleepComfort: _asDouble(health?['sleepComfort']),
      apparentTemp: _asDouble(health?['apparentTemp']),
      seasonalApparent: seasonalApparent,
      purifier: purifier,
      ipi: ipi,
      child: child,
      senior: senior,
      purification: purification,
      locationComparison: locationComparison,
      meta: meta,
      location: location,
      alerts: alerts,
    );
  }
}

class LocationComparisonSnapshot {
  const LocationComparisonSnapshot({
    this.timestamp,
    this.title,
    this.subtitle,
    this.pm25,
    this.temperature,
    this.humidity,
  });

  final DateTime? timestamp;
  final String? title;
  final String? subtitle;
  final LocationMetricComparison? pm25;
  final LocationMetricComparison? temperature;
  final LocationMetricComparison? humidity;

  static LocationComparisonSnapshot? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return LocationComparisonSnapshot(
      timestamp: _parseTimestamp(json['timestamp']),
      title: json['title']?.toString(),
      subtitle: json['subtitle']?.toString(),
      pm25: LocationMetricComparison.tryParse(_asMap(json['pm25'])),
      temperature:
          LocationMetricComparison.tryParse(_asMap(json['temperature'])),
      humidity: LocationMetricComparison.tryParse(_asMap(json['humidity'])),
    );
  }
}

class LocationMetricComparison {
  const LocationMetricComparison({
    this.sensor,
    this.station,
    this.delta,
    this.unit,
    this.stats,
  });

  final double? sensor;
  final double? station;
  final String? delta;
  final String? unit;
  final LocationMetricStats? stats;

  static LocationMetricComparison? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return LocationMetricComparison(
      sensor: _asDouble(json['sensor']),
      station: _asDouble(json['station']),
      delta: json['delta']?.toString(),
      unit: json['unit']?.toString(),
      stats: LocationMetricStats.tryParse(_asMap(json['stats'])),
    );
  }
}

class LocationMetricStats {
  const LocationMetricStats({
    this.rmse,
    this.mape,
    this.cv,
    this.r2,
    this.n,
  });

  final double? rmse;
  final double? mape;
  final double? cv;
  final double? r2;
  final double? n;

  static LocationMetricStats? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return LocationMetricStats(
      rmse: _asDouble(json['rmse']),
      mape: _asDouble(json['mape']),
      cv: _asDouble(json['cv']),
      r2: _asDouble(json['r2']),
      n: _asDouble(json['n']),
    );
  }
}

class ChildHealthSnapshot {
  const ChildHealthSnapshot({
    this.focus,
    this.respiratory,
    this.infection,
    this.mold,
  });

  final ChildFocusSnapshot? focus;
  final ChildRespiratorySnapshot? respiratory;
  final InfectionRiskSnapshot? infection;
  final MoldRiskSnapshot? mold;

  static ChildHealthSnapshot? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return ChildHealthSnapshot(
      focus: ChildFocusSnapshot.tryParse(_asMap(json['focus'])),
      respiratory:
          ChildRespiratorySnapshot.tryParse(_asMap(json['respiratory'])),
      infection: InfectionRiskSnapshot.tryParse(_asMap(json['infection'])),
      mold: MoldRiskSnapshot.tryParse(_asMap(json['mold'])),
    );
  }
}

class ChildFocusSnapshot {
  const ChildFocusSnapshot({
    this.co2,
    this.level,
    this.message,
    this.recommendedAction,
  });

  final double? co2;
  final String? level;
  final String? message;
  final String? recommendedAction;

  static ChildFocusSnapshot? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return ChildFocusSnapshot(
      co2: _asDouble(json['co2']),
      level: json['level']?.toString(),
      message: json['message']?.toString(),
      recommendedAction: json['recommendedAction']?.toString(),
    );
  }
}

class ChildRespiratorySnapshot {
  const ChildRespiratorySnapshot({
    this.score,
    this.level,
    this.temp,
    this.rh,
    this.tvoc,
    this.rhMessage,
    this.tempMessage,
    this.vocMessage,
  });

  final double? score;
  final String? level;
  final double? temp;
  final double? rh;
  final double? tvoc;
  final String? rhMessage;
  final String? tempMessage;
  final String? vocMessage;

  static ChildRespiratorySnapshot? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return ChildRespiratorySnapshot(
      score: _asDouble(json['score']),
      level: json['level']?.toString(),
      temp: _asDouble(json['temp']),
      rh: _asDouble(json['rh']),
      tvoc: _asDouble(json['tvoc']),
      rhMessage: json['rhMsg']?.toString(),
      tempMessage: json['tMsg']?.toString(),
      vocMessage: json['vocMsg']?.toString(),
    );
  }
}

class InfectionRiskSnapshot {
  const InfectionRiskSnapshot({
    this.score,
    this.level,
    this.combo,
    this.co2,
    this.rh,
  });

  final double? score;
  final String? level;
  final int? combo;
  final double? co2;
  final double? rh;

  static InfectionRiskSnapshot? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return InfectionRiskSnapshot(
      score: _asDouble(json['score']),
      level: json['level']?.toString(),
      combo: _asInt(json['combo']),
      co2: _asDouble(json['co2']),
      rh: _asDouble(json['rh']),
    );
  }
}

class MoldRiskSnapshot {
  const MoldRiskSnapshot({
    this.riskLevel,
    this.riskMessage,
    this.durationHours,
    this.humidity,
    this.pm25,
  });

  final int? riskLevel;
  final String? riskMessage;
  final double? durationHours;
  final double? humidity;
  final double? pm25;

  static MoldRiskSnapshot? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return MoldRiskSnapshot(
      riskLevel: _asInt(json['riskLevel']),
      riskMessage: json['riskMessage']?.toString(),
      durationHours: _asDouble(json['durationHours']),
      humidity: _asDouble(json['humidity']),
      pm25: _asDouble(json['pm25']),
    );
  }
}

class SeniorHealthSnapshot {
  const SeniorHealthSnapshot({
    this.cardio,
    this.sleep,
    this.pmExposure,
    this.ventilation,
  });

  final SeniorCardioSnapshot? cardio;
  final SeniorSleepSnapshot? sleep;
  final SeniorPmExposureSnapshot? pmExposure;
  final SeniorVentilationSnapshot? ventilation;

  static SeniorHealthSnapshot? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return SeniorHealthSnapshot(
      cardio: SeniorCardioSnapshot.tryParse(_asMap(json['cardio'])),
      sleep: SeniorSleepSnapshot.tryParse(_asMap(json['sleep'])),
      pmExposure:
          SeniorPmExposureSnapshot.tryParse(_asMap(json['pmExposure'])),
      ventilation:
          SeniorVentilationSnapshot.tryParse(_asMap(json['ventilation'])),
    );
  }
}

class SeniorCardioSnapshot {
  const SeniorCardioSnapshot({
    this.score,
    this.level,
    this.highHours,
    this.kAvg,
    this.riskRaw,
    this.samples,
  });

  final double? score;
  final String? level;
  final double? highHours;
  final double? kAvg;
  final double? riskRaw;
  final int? samples;

  static SeniorCardioSnapshot? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return SeniorCardioSnapshot(
      score: _asDouble(json['score']),
      level: json['level']?.toString(),
      highHours: _asDouble(json['highHours']),
      kAvg: _asDouble(json['kAvg']),
      riskRaw: _asDouble(json['riskRaw']),
      samples: _asInt(json['samples']),
    );
  }
}

class SeniorSleepSnapshot {
  const SeniorSleepSnapshot({
    this.score,
    this.level,
    this.scoreRange,
    this.interpretation,
    this.goodCo2,
    this.goodVoc,
    this.samples,
  });

  final double? score;
  final String? level;
  final String? scoreRange;
  final String? interpretation;
  final double? goodCo2;
  final double? goodVoc;
  final int? samples;

  static SeniorSleepSnapshot? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return SeniorSleepSnapshot(
      score: _asDouble(json['score']),
      level: json['level']?.toString(),
      scoreRange: json['scoreRange']?.toString(),
      interpretation: json['interpretation']?.toString(),
      goodCo2: _asDouble(json['goodCo2']),
      goodVoc: _asDouble(json['goodVoc']),
      samples: _asInt(json['samples']),
    );
  }
}

class SeniorPmExposureSnapshot {
  const SeniorPmExposureSnapshot({
    this.pm25,
    this.band,
    this.message,
  });

  final double? pm25;
  final String? band;
  final String? message;

  static SeniorPmExposureSnapshot? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return SeniorPmExposureSnapshot(
      pm25: _asDouble(json['pm25']),
      band: json['band']?.toString(),
      message: json['message']?.toString(),
    );
  }
}

class SeniorVentilationSnapshot {
  const SeniorVentilationSnapshot({
    this.k,
    this.t50Minutes,
    this.message,
  });

  final double? k;
  final double? t50Minutes;
  final String? message;

  static SeniorVentilationSnapshot? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return SeniorVentilationSnapshot(
      k: _asDouble(json['k']),
      t50Minutes: _asDouble(json['t50Minutes']),
      message: json['message']?.toString(),
    );
  }
}

class PurificationSummary {
  const PurificationSummary({
    this.cadr,
    this.ipi,
    this.ventilation,
  });

  final PurificationCadrSnapshot? cadr;
  final IpiSnapshot? ipi;
  final PurificationVentilationSnapshot? ventilation;

  static PurificationSummary? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return PurificationSummary(
      cadr: PurificationCadrSnapshot.tryParse(_asMap(json['cadr'])),
      ipi: IpiSnapshot.tryParse(_asMap(json['ipi'])),
      ventilation:
          PurificationVentilationSnapshot.tryParse(_asMap(json['ventilation'])),
    );
  }
}

class PurificationCadrSnapshot {
  const PurificationCadrSnapshot({
    this.k,
    this.kEffective,
    this.t50Minutes,
    this.index,
    this.grade,
    this.trend,
    this.updatedAt,
    // New dual-k analysis fields
    this.mode,
    this.dominantSource,
    this.scenario,
    this.kPm25,
    this.kCo2,
    this.gradePm25,
    this.gradeCo2,
    this.levelPm25,
    this.levelCo2,
    this.dualKDisplay,
    // Dual t50 fields
    this.t50Pm25,
    this.t50Co2,
    this.dualT50Display,
    // R² reliability fields
    this.r2Pm25,
    this.r2Co2,
    this.pmAccuracyWarning,
    this.co2AccuracyWarning,
  });

  final double? k;
  final double? kEffective;
  final double? t50Minutes;
  final int? index;
  final String? grade;
  final String? trend;
  final String? updatedAt;
  // New dual-k analysis fields
  final String? mode; // 'Purifier', 'Ventilation', 'Combined', 'Stagnant', 'Accumulating'
  final String? dominantSource; // 'PM', 'CO2', 'Both', 'Neither'
  final String? scenario; // e.g., 'PM Rapid Decay (Sealed)', 'CO2 Rapid Decay (Ventilation)'
  final double? kPm25; // k value from PM2.5 decay
  final double? kCo2; // k value from CO2 decay
  final String? gradePm25; // CADR grade for PM2.5: S/A/B/C
  final String? gradeCo2; // CADR grade for CO2: S/A/B/C
  final String? levelPm25; // '급속감소', '자연감소', '정체', '축적중'
  final String? levelCo2; // '급속감소', '자연감소', '정체', '축적중'
  final String? dualKDisplay; // Formatted string: "k_PM=0.5, k_CO₂=0.2 (1/h)"
  // Dual t50 fields
  final double? t50Pm25; // t50 for PM2.5 in minutes
  final double? t50Co2; // t50 for CO2 in minutes
  final String? dualT50Display; // Formatted string: "t₅₀_PM≈X분, t₅₀_CO₂≈Y분"
  // R² reliability fields
  final double? r2Pm25; // R² for PM2.5 regression (0-1)
  final double? r2Co2; // R² for CO2 regression (0-1)
  final bool? pmAccuracyWarning; // true if R² < 0.7
  final bool? co2AccuracyWarning; // true if R² < 0.7

  static PurificationCadrSnapshot? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return PurificationCadrSnapshot(
      k: _asDouble(json['k']),
      kEffective: _asDouble(json['kEffective']),
      t50Minutes: _asDouble(json['t50_min'] ?? json['t50Minutes']),
      index: _asInt(json['index'] ?? json['cadrIndex']),
      grade: json['grade']?.toString() ?? json['cadrGrade']?.toString(),
      trend: json['trend']?.toString(),
      updatedAt: json['updatedAt']?.toString(),
      // Parse new dual-k fields
      mode: json['mode']?.toString(),
      dominantSource: json['dominantSource']?.toString(),
      scenario: json['scenario']?.toString(),
      kPm25: _asDouble(json['k_pm25']),
      kCo2: _asDouble(json['k_co2']),
      gradePm25: json['gradePm25']?.toString(),
      gradeCo2: json['gradeCo2']?.toString(),
      levelPm25: json['levelPm25']?.toString(),
      levelCo2: json['levelCo2']?.toString(),
      dualKDisplay: json['dualKDisplay']?.toString(),
      // Parse dual t50 fields
      t50Pm25: _asDouble(json['t50_pm25']),
      t50Co2: _asDouble(json['t50_co2']),
      dualT50Display: json['dualT50Display']?.toString(),
      // Parse R² reliability fields
      r2Pm25: _asDouble(json['r2_pm25'] ?? json['r2Pm25']),
      r2Co2: _asDouble(json['r2_co2'] ?? json['r2Co2']),
      pmAccuracyWarning: (_asDouble(json['r2_pm25'] ?? json['r2Pm25']) ?? 1.0) < 0.7,
      co2AccuracyWarning: (_asDouble(json['r2_co2'] ?? json['r2Co2']) ?? 1.0) < 0.7,
    );
  }
}

class PurificationVentilationSnapshot {
  const PurificationVentilationSnapshot({
    this.status,
    this.message,
    this.alerts,
  });

  final String? status;
  final String? message;
  final List<String>? alerts;

  static PurificationVentilationSnapshot? tryParse(
    Map<String, dynamic>? json,
  ) {
    if (json == null || json.isEmpty) return null;
    return PurificationVentilationSnapshot(
      status: json['status']?.toString(),
      message: json['message']?.toString(),
      alerts: _asStringList(json['alerts']),
    );
  }
}

class SnapshotMeta {
  const SnapshotMeta({
    this.firmware,
    this.serialNo,
    this.wifiRssi,
    this.sensorSource,
  });

  final String? firmware;
  final String? serialNo;
  final double? wifiRssi;
  final String? sensorSource;

  static SnapshotMeta? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return SnapshotMeta(
      firmware: json['firmware']?.toString(),
      serialNo: json['serialno']?.toString(),
      wifiRssi: _asDouble(json['wifi_rssi']),
      sensorSource: json['sensor_source']?.toString(),
    );
  }
}

class SnapshotLocation {
  const SnapshotLocation({
    this.sensorLat,
    this.sensorLon,
    this.deviceLat,
    this.deviceLon,
    this.accuracy,
    this.source,
    this.recordedAt,
  });

  final double? sensorLat;
  final double? sensorLon;
  final double? deviceLat;
  final double? deviceLon;
  final double? accuracy;
  final String? source;
  final DateTime? recordedAt;

  static SnapshotLocation? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return SnapshotLocation(
      sensorLat: _asDouble(json['sensor_lat']),
      sensorLon: _asDouble(json['sensor_lon']),
      deviceLat: _asDouble(json['device_lat']),
      deviceLon: _asDouble(json['device_lon']),
      accuracy: _asDouble(json['accuracy']),
      source: json['source']?.toString(),
      recordedAt: _parseTimestamp(json['timestamp']),
    );
  }
}

class SnapshotAlerts {
  const SnapshotAlerts({
    this.messages,
    this.airQualityAlert,
    this.moldRiskLevel,
    this.moldRiskMessage,
  });

  final List<String>? messages;
  final String? airQualityAlert;
  final int? moldRiskLevel;
  final String? moldRiskMessage;

  static SnapshotAlerts? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return SnapshotAlerts(
      messages: _asStringList(json['messages']),
      airQualityAlert: json['airQualityAlert']?.toString(),
      moldRiskLevel: _asInt(json['moldRiskLevel']),
      moldRiskMessage: json['moldRiskMessage']?.toString(),
    );
  }
}

class SeasonalApparentSnapshot {
  const SeasonalApparentSnapshot({
    this.seasonMode,
    this.updatedAt,
    this.summer,
    this.winter,
  });

  final String? seasonMode;
  final DateTime? updatedAt;
  final SeasonalApparentSummer? summer;
  final SeasonalApparentWinter? winter;

  static SeasonalApparentSnapshot? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return SeasonalApparentSnapshot(
      seasonMode: json['seasonMode']?.toString(),
      updatedAt: _parseTimestamp(json['updatedAt']),
      summer: SeasonalApparentSummer.tryParse(_asMap(json['summer'])),
      winter: SeasonalApparentWinter.tryParse(_asMap(json['winter'])),
    );
  }
}

class SeasonalApparentSummer {
  const SeasonalApparentSummer({
    this.apparentTemp,
    this.riskMessage,
    this.riskColor,
  });

  final double? apparentTemp;
  final String? riskMessage;
  final String? riskColor;

  static SeasonalApparentSummer? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return SeasonalApparentSummer(
      apparentTemp: _asDouble(json['apparentTemp']),
      riskMessage: json['riskMessage']?.toString(),
      riskColor: json['riskColor']?.toString(),
    );
  }
}

class SeasonalApparentWinter {
  const SeasonalApparentWinter({
    this.apparentTemp,
    this.message,
    this.color,
    this.isWinterCalc,
    this.realTemp,
    this.realWind,
  });

  final double? apparentTemp;
  final String? message;
  final String? color;
  final bool? isWinterCalc;
  final double? realTemp;
  final double? realWind;

  static SeasonalApparentWinter? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return SeasonalApparentWinter(
      apparentTemp: _asDouble(json['apparentTemp']),
      message: json['message']?.toString(),
      color: json['color']?.toString(),
      isWinterCalc: _asBool(json['isWinterCalc']),
      realTemp: _asDouble(json['realTemp']),
      realWind: _asDouble(json['realWind']),
    );
  }
}

class PurifierSnapshot {
  const PurifierSnapshot({
    this.k,
    this.kEffective,
    this.t50Minutes,
    this.cadrIndex,
    this.cadrGrade,
  });

  final double? k;
  final double? kEffective;
  final double? t50Minutes;
  final double? cadrIndex;
  final String? cadrGrade;

  static PurifierSnapshot? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return PurifierSnapshot(
      k: _asDouble(json['k']),
      kEffective: _asDouble(json['kEffective']),
      t50Minutes: _asDouble(json['t50_min']),
      cadrIndex: _asDouble(json['cadrIndex']),
      cadrGrade: json['cadrGrade']?.toString(),
    );
  }
}

class IpiSnapshot {
  const IpiSnapshot({
    this.k,
    this.t90Minutes,
    this.level,
    this.score,
    // Dual k fields for IPI
    this.kPm25,
    this.kCo2,
    this.t90Pm25,
    this.t90Co2,
    this.dualKDisplay,
    this.dualT90Display,
    // R² reliability
    this.r2Co2,
    this.accuracyWarning,
  });

  final double? k;
  final double? t90Minutes;
  final String? level;
  final int? score;
  // Dual k fields for IPI
  final double? kPm25; // k value from PM2.5 decay
  final double? kCo2; // k value from CO2 decay
  final double? t90Pm25; // t90 for PM2.5 in minutes
  final double? t90Co2; // t90 for CO2 in minutes
  final String? dualKDisplay; // Formatted: "k_PM=0.5, k_CO₂=0.2 (1/h)"
  final String? dualT90Display; // Formatted: "t₉₀_PM≈X분, t₉₀_CO₂≈Y분"
  // R² reliability
  final double? r2Co2; // R² for CO2 regression
  final bool? accuracyWarning; // true if R² < 0.7

  static IpiSnapshot? tryParse(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    return IpiSnapshot(
      k: _asDouble(json['k']),
      t90Minutes: _asDouble(json['t90_min']),
      level: json['level']?.toString(),
      score: _asInt(json['score']),
      // Parse dual k fields
      kPm25: _asDouble(json['k_pm25']),
      kCo2: _asDouble(json['k_co2']),
      t90Pm25: _asDouble(json['t90_pm25']),
      t90Co2: _asDouble(json['t90_co2']),
      dualKDisplay: json['dualKDisplay']?.toString(),
      dualT90Display: json['dualT90Display']?.toString(),
      // Parse R² reliability
      r2Co2: _asDouble(json['r2_co2'] ?? json['r2Co2']),
      accuracyWarning: (_asDouble(json['r2_co2'] ?? json['r2Co2']) ?? 1.0) < 0.7,
    );
  }
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  return null;
}

Map<String, dynamic>? _firstMap(dynamic a, [dynamic b, dynamic c]) {
  return _asMap(a) ?? _asMap(b) ?? _asMap(c);
}

double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is num && value.isFinite) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value);
    return parsed;
  }
  return null;
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num && value.isFinite) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

List<String>? _asStringList(dynamic value) {
  if (value == null) return null;
  if (value is List) {
    final parsed = <String>[];
    for (final item in value) {
      if (item == null) continue;
      parsed.add(item.toString());
    }
    return parsed.isEmpty ? null : parsed;
  }
  if (value is String) {
    return <String>[value];
  }
  return null;
}

bool? _asBool(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final lowered = value.toLowerCase().trim();
    if (lowered == 'true' || lowered == '1') return true;
    if (lowered == 'false' || lowered == '0') return false;
  }
  return null;
}

DateTime? _parseTimestamp(dynamic value) {
  if (value == null) return null;
  if (value is int) {
    // Node-RED sends unix milliseconds.
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: false);
  }
  if (value is String) {
    final numeric = int.tryParse(value);
    if (numeric != null) {
      return DateTime.fromMillisecondsSinceEpoch(numeric, isUtc: false);
    }
    return DateTime.tryParse(value);
  }
  if (value is double && value.isFinite) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: false);
  }
  return null;
}
