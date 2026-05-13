import '../models/air_quality_snapshot.dart';

class AirQualityData {
  const AirQualityData({
    required this.timestamp,
    this.pm25,
    this.co2,
    this.tvoc,
    this.nox,
    this.temperature,
    this.humidity,
    this.iaqiScore,
  });

  final DateTime timestamp;
  final double? pm25;
  final double? co2;
  final double? tvoc;
  final double? nox;
  final double? temperature;
  final double? humidity;
  final double? iaqiScore;
}

AirQualityData? airQualityDataFromSnapshot(AirQualitySnapshot? snapshot) {
  if (snapshot == null) {
    return null;
  }
  return AirQualityData(
    timestamp: snapshot.timestamp,
    pm25: snapshot.pm25,
    co2: snapshot.co2,
    tvoc: snapshot.tvoc,
    nox: snapshot.nox,
    temperature: snapshot.temperature,
    humidity: snapshot.humidity,
    iaqiScore: snapshot.iaqiScore,
  );
}

List<AirQualityData> airQualityDataFromSnapshots(
  List<AirQualitySnapshot> snapshots,
) {
  return snapshots
      .map(airQualityDataFromSnapshot)
      .whereType<AirQualityData>()
      .toList(growable: false);
}
