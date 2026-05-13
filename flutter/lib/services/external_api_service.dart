import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class ExternalApiData {
  const ExternalApiData({
    this.pm25,
    this.temperature,
    this.humidity,
    this.windSpeed,
    this.stationName,
    this.stationLatitude,
    this.stationLongitude,
    this.city,
    this.region,
    required this.retrievedAt,
  });

  final double? pm25;
  final double? temperature;
  final double? humidity;
  final double? windSpeed;
  final String? stationName;
  final double? stationLatitude;
  final double? stationLongitude;
  final String? city;
  final String? region;
  final DateTime retrievedAt;
}

class NearbyPm25Station {
  const NearbyPm25Station({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.pm25,
    this.pm10,
    this.no2,
    this.o3,
    this.co,
    this.uid,
    this.observedAt,
  });

  final String name;
  final double latitude;
  final double longitude;
  final double pm25;
  final double? pm10;
  final double? no2;
  final double? o3;
  final double? co;
  final String? uid;
  final DateTime? observedAt;

  NearbyPm25Station copyWith({
    String? name,
    double? latitude,
    double? longitude,
    double? pm25,
    Object? pm10 = _copySentinel,
    Object? no2 = _copySentinel,
    Object? o3 = _copySentinel,
    Object? co = _copySentinel,
    String? uid,
    DateTime? observedAt,
  }) {
    return NearbyPm25Station(
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      pm25: pm25 ?? this.pm25,
      pm10: identical(pm10, _copySentinel) ? this.pm10 : pm10 as double?,
      no2: identical(no2, _copySentinel) ? this.no2 : no2 as double?,
      o3: identical(o3, _copySentinel) ? this.o3 : o3 as double?,
      co: identical(co, _copySentinel) ? this.co : co as double?,
      uid: uid ?? this.uid,
      observedAt: observedAt ?? this.observedAt,
    );
  }
}

class NearbyWeatherGridPoint {
  const NearbyWeatherGridPoint({
    required this.latitude,
    required this.longitude,
    this.temperature,
    this.humidity,
    this.windSpeed,
    this.observedAt,
  });

  final double latitude;
  final double longitude;
  final double? temperature;
  final double? humidity;
  final double? windSpeed;
  final DateTime? observedAt;
}

const Object _copySentinel = Object();

class ComparisonStats {
  const ComparisonStats({this.rmse, this.mape, this.cv, this.r2, this.n = 0});

  final double? rmse;
  final double? mape;
  final double? cv;
  final double? r2;
  final int n;

  Map<String, dynamic> toJson() => {
        'rmse': rmse,
        'mape': mape,
        'cv': cv,
        'r2': r2,
        'n': n,
      };
}

class ComparisonResult {
  const ComparisonResult({
    required this.title,
    required this.subtitle,
    required this.timestamp,
    this.stationLatitude,
    this.stationLongitude,
    this.pm25,
    this.temperature,
    this.humidity,
  });

  final String title;
  final String subtitle;
  final DateTime timestamp;
  final double? stationLatitude;
  final double? stationLongitude;
  final ExternalMetricComparison? pm25;
  final ExternalMetricComparison? temperature;
  final ExternalMetricComparison? humidity;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'title': title,
        'subtitle': subtitle,
        if (stationLatitude != null) 'stationLatitude': stationLatitude,
        if (stationLongitude != null) 'stationLongitude': stationLongitude,
        if (pm25 != null) 'pm25': pm25!.toJson(),
        if (temperature != null) 'temperature': temperature!.toJson(),
        if (humidity != null) 'humidity': humidity!.toJson(),
      };
}

class ExternalMetricComparison {
  const ExternalMetricComparison({
    this.sensor,
    this.station,
    this.delta,
    required this.unit,
    this.stats,
  });

  final double? sensor;
  final double? station;
  final String? delta;
  final String unit;
  final ComparisonStats? stats;

  Map<String, dynamic> toJson() => {
        'sensor': sensor,
        'station': station,
        'delta': delta,
        'unit': unit,
        if (stats != null) 'stats': stats!.toJson(),
      };
}

class _StatsSample {
  const _StatsSample(this.t, this.s, this.a);

  final int t;
  final double s;
  final double a;
}

class _StatsBuffer {
  static const _windowMs = 3600000;

  final List<_StatsSample> pm25 = <_StatsSample>[];
  final List<_StatsSample> temp = <_StatsSample>[];
  final List<_StatsSample> hum = <_StatsSample>[];

  void addPm25(double? sensor, double? api) => _addData(pm25, sensor, api);
  void addTemp(double? sensor, double? api) => _addData(temp, sensor, api);
  void addHum(double? sensor, double? api) => _addData(hum, sensor, api);

  void _addData(List<_StatsSample> buffer, double? sensor, double? api) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (sensor != null && api != null) {
      buffer.add(_StatsSample(now, sensor, api));
    }
    buffer.removeWhere((sample) => now - sample.t > _windowMs);
  }

  static ComparisonStats calcStats(List<_StatsSample> samples) {
    final n = samples.length;
    if (n < 2) return ComparisonStats(n: n);

    var sumSqErr = 0.0;
    var sumAbsPct = 0.0;
    var sumS = 0.0;
    var sumA = 0.0;
    var sumSS = 0.0;
    var sumAA = 0.0;
    var sumSA = 0.0;

    for (final sample in samples) {
      final s = sample.s;
      final a = sample.a;
      final err = s - a;
      sumSqErr += err * err;
      sumS += s;
      sumA += a;
      sumSS += s * s;
      sumAA += a * a;
      sumSA += s * a;
      if (a != 0) {
        sumAbsPct += (err / a).abs();
      }
    }

    final rmse = math.sqrt(sumSqErr / n);
    final mape = (sumAbsPct / n) * 100;
    final meanS = sumS / n;
    final cv = meanS != 0 ? (rmse / meanS) * 100 : 0.0;
    final numer = (n * sumSA) - (sumS * sumA);
    final den = math.sqrt(
      ((n * sumSS) - (sumS * sumS)) * ((n * sumAA) - (sumA * sumA)),
    );
    var r2 = 0.0;
    if (den != 0) {
      final r = numer / den;
      r2 = r * r;
    } else if (sumSqErr == 0) {
      r2 = 1;
    }

    return ComparisonStats(
      rmse: (rmse * 10).roundToDouble() / 10,
      mape: (mape * 10).roundToDouble() / 10,
      cv: (cv * 10).roundToDouble() / 10,
      r2: (r2 * 100).roundToDouble() / 100,
      n: n,
    );
  }
}

class ExternalApiService {
  ExternalApiService({
    String? waqiToken,
    String? kmaServiceKey,
    http.Client? client,
  })  : _waqiToken = waqiToken ??
            const String.fromEnvironment(
              'WAQI_TOKEN',
              defaultValue: '521285b593a8efe34cacac7c6782f6c42016c02c',
            ),
        _kmaServiceKey = kmaServiceKey ??
            const String.fromEnvironment(
              'KMA_SERVICE_KEY',
              defaultValue:
                  '0ff577610fcbaaf42f9d941958fb96d4cbb8dd29371883b62f3e43006e4eec97',
            ),
        _client = client ?? http.Client();

  final String _waqiToken;
  final String _kmaServiceKey;
  final http.Client _client;
  final _StatsBuffer _statsBuffer = _StatsBuffer();

  ExternalApiData? _latestApiData;
  ComparisonResult? _latestComparison;
  Timer? _timer;
  double? _lat;
  double? _lon;
  String? _city;
  List<NearbyPm25Station> _nearbyPm25Stations = const <NearbyPm25Station>[];
  DateTime? _nearbyStationsFetchedAt;
  double? _nearbyCenterLat;
  double? _nearbyCenterLon;
  List<NearbyPm25Station> _koreaPm25Stations = const <NearbyPm25Station>[];
  DateTime? _koreaStationsFetchedAt;

  ExternalApiData? get latestApiData => _latestApiData;
  ComparisonResult? get latestComparison => _latestComparison;
  bool get hasCredentials => _hasCredentials;

  void setLocation({
    required double latitude,
    required double longitude,
    String? city,
  }) {
    if (latitude == 0 || longitude == 0) return;
    _lat = latitude;
    _lon = longitude;
    if (city != null && city.trim().isNotEmpty) {
      _city = city.trim();
    }
  }

  bool get _hasCredentials =>
      _waqiToken.trim().isNotEmpty || _kmaServiceKey.trim().isNotEmpty;

  void start() {
    if (!_hasCredentials) {
      _log('외부 비교 API 키가 없어 폴링을 시작하지 않습니다.');
      return;
    }
    _fetchAll();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => _fetchAll());
  }

  Future<bool> refreshNow() async {
    if (!_hasCredentials) {
      _log('외부 비교 API 키가 없어 수동 갱신을 건너뜁니다.');
      return false;
    }
    await _fetchAll();
    return _latestApiData != null;
  }

  Future<List<NearbyPm25Station>> fetchNearbyPm25Stations({
    required double latitude,
    required double longitude,
    double radiusKm = 8,
  }) async {
    if (_waqiToken.trim().isEmpty ||
        latitude == 0 ||
        longitude == 0 ||
        !latitude.isFinite ||
        !longitude.isFinite) {
      return const <NearbyPm25Station>[];
    }

    final fetchedAt = _nearbyStationsFetchedAt;
    final centerLat = _nearbyCenterLat;
    final centerLon = _nearbyCenterLon;
    if (fetchedAt != null &&
        centerLat != null &&
        centerLon != null &&
        DateTime.now().difference(fetchedAt).inMinutes < 10 &&
        _distanceKm(centerLat, centerLon, latitude, longitude) < 1.5) {
      return _nearbyPm25Stations;
    }

    final latDelta = radiusKm / 111.0;
    final lonScale = math.cos(latitude * math.pi / 180).abs().clamp(0.2, 1.0);
    final lonDelta = radiusKm / (111.0 * lonScale);
    final south = latitude - latDelta;
    final west = longitude - lonDelta;
    final north = latitude + latDelta;
    final east = longitude + lonDelta;

    try {
      final uri = Uri.parse(
        'https://api.waqi.info/map/bounds/'
        '?latlng=$south,$west,$north,$east&token=$_waqiToken',
      );
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return const <NearbyPm25Station>[];

      final data = json.decode(response.body);
      if (data is! Map || data['status'] != 'ok') {
        return const <NearbyPm25Station>[];
      }
      final items = data['data'];
      if (items is! List) return const <NearbyPm25Station>[];

      final stations = <NearbyPm25Station>[];
      for (final item in items) {
        final station = _stationFromWaqiMapItem(item);
        if (station == null) continue;
        if (_distanceKm(
              latitude,
              longitude,
              station.latitude,
              station.longitude,
            ) >
            radiusKm * 1.4) {
          continue;
        }
        stations.add(station);
      }
      stations.sort((a, b) {
        final da = _distanceKm(latitude, longitude, a.latitude, a.longitude);
        final db = _distanceKm(latitude, longitude, b.latitude, b.longitude);
        return da.compareTo(db);
      });
      final nearby = stations.toList(growable: false);
      final detailedCandidates = _balancedDetailStations(
        nearby,
        centerLatitude: latitude,
        centerLongitude: longitude,
        maxCount: 220,
      );
      final detailed = await Future.wait(
        detailedCandidates
            .map(_stationWithDetailedPm25)
            .toList(growable: false),
      );
      final detailedByUid = <String, NearbyPm25Station>{
        for (final station in detailed)
          if ((station.uid ?? '').isNotEmpty) station.uid!: station,
      };
      _nearbyPm25Stations = [
        for (final station in nearby) detailedByUid[station.uid] ?? station,
      ];
      _nearbyStationsFetchedAt = DateTime.now();
      _nearbyCenterLat = latitude;
      _nearbyCenterLon = longitude;
      return _nearbyPm25Stations;
    } catch (error) {
      _log('WAQI 주변 측정소 오류: $error');
      return _nearbyPm25Stations;
    }
  }

  Future<List<NearbyPm25Station>> fetchKoreaPm25Stations() async {
    if (_waqiToken.trim().isEmpty) {
      return const <NearbyPm25Station>[];
    }
    final fetchedAt = _koreaStationsFetchedAt;
    if (fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < const Duration(minutes: 55)) {
      return _koreaPm25Stations;
    }

    try {
      final uri = Uri.parse(
        'https://api.waqi.info/map/bounds/'
        '?latlng=33.0,124.0,39.2,132.2&token=$_waqiToken',
      );
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return _koreaPm25Stations;

      final data = json.decode(response.body);
      if (data is! Map || data['status'] != 'ok') return _koreaPm25Stations;
      final items = data['data'];
      if (items is! List) return _koreaPm25Stations;

      final stations = <NearbyPm25Station>[];
      final seen = <String>{};
      for (final item in items) {
        final station = _stationFromWaqiMapItem(item);
        if (station == null) continue;
        if (station.latitude < 32.8 ||
            station.latitude > 39.4 ||
            station.longitude < 123.8 ||
            station.longitude > 132.4) {
          continue;
        }
        final key = station.uid?.trim().isNotEmpty == true
            ? station.uid!.trim()
            : '${station.latitude.toStringAsFixed(4)},${station.longitude.toStringAsFixed(4)}';
        if (!seen.add(key)) continue;
        stations.add(station);
      }
      final detailedCandidates = _balancedDetailStations(
        stations,
        centerLatitude: 36.3,
        centerLongitude: 127.8,
        maxCount: 650,
      );
      final detailed = await Future.wait(
        detailedCandidates
            .map(_stationWithDetailedPm25)
            .toList(growable: false),
      );
      final detailedByUid = <String, NearbyPm25Station>{
        for (final station in detailed)
          if ((station.uid ?? '').isNotEmpty) station.uid!: station,
      };
      _koreaPm25Stations = [
        for (final station in stations) detailedByUid[station.uid] ?? station,
      ];
      _koreaStationsFetchedAt = DateTime.now();
      return _koreaPm25Stations;
    } catch (error) {
      _log('WAQI 전국 측정소 오류: $error');
      return _koreaPm25Stations;
    }
  }

  List<NearbyPm25Station> _balancedDetailStations(
    List<NearbyPm25Station> stations, {
    required double centerLatitude,
    required double centerLongitude,
    required int maxCount,
  }) {
    if (stations.length <= maxCount) return stations;

    final selected = <NearbyPm25Station>[];
    final buckets = <String, List<NearbyPm25Station>>{};
    for (final station in stations) {
      final latBucket = (station.latitude * 2).floor();
      final lonBucket = (station.longitude * 2).floor();
      buckets.putIfAbsent('$latBucket:$lonBucket', () => []).add(station);
    }

    for (final bucket in buckets.values) {
      bucket.sort((a, b) {
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
    }

    final bucketEntries = buckets.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    var round = 0;
    while (selected.length < maxCount) {
      var added = false;
      for (final entry in bucketEntries) {
        if (entry.value.length <= round) continue;
        selected.add(entry.value[round]);
        added = true;
        if (selected.length >= maxCount) break;
      }
      if (!added) break;
      round += 1;
    }
    return selected;
  }

  Future<List<NearbyWeatherGridPoint>> fetchNearbyWeatherGrid({
    required double latitude,
    required double longitude,
    double radiusKm = 90,
  }) async {
    if (_kmaServiceKey.trim().isEmpty ||
        latitude == 0 ||
        longitude == 0 ||
        !latitude.isFinite ||
        !longitude.isFinite) {
      return const <NearbyWeatherGridPoint>[];
    }

    final lonScale = math.cos(latitude * math.pi / 180).abs().clamp(0.2, 1.0);
    final latRadius = radiusKm / 111.0;
    final lonRadius = radiusKm / (111.0 * lonScale);
    const offsets = <double>[-1, -0.5, 0, 0.5, 1];
    final seenGrid = <String>{};
    final targets = <({double latitude, double longitude})>[];
    for (final y in offsets) {
      for (final x in offsets) {
        final sampleLat = latitude + latRadius * y;
        final sampleLon = longitude + lonRadius * x;
        final grid = _latLonToGrid(sampleLat, sampleLon);
        if (!seenGrid.add('${grid.x}:${grid.y}')) continue;
        targets.add((latitude: sampleLat, longitude: sampleLon));
      }
    }

    final samples = await Future.wait(
      targets.map((target) async {
        final data = await _fetchKmaPoint(
          latitude: target.latitude,
          longitude: target.longitude,
          logErrors: false,
        );
        if (data == null ||
            (data.temperature == null && data.humidity == null)) {
          return null;
        }
        return NearbyWeatherGridPoint(
          latitude: target.latitude,
          longitude: target.longitude,
          temperature: data.temperature,
          humidity: data.humidity,
          windSpeed: data.windSpeed,
          observedAt: data.observedAt,
        );
      }),
    );
    return samples.whereType<NearbyWeatherGridPoint>().toList(growable: false);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    _client.close();
  }

  void updateComparison({
    required double? sensorPm25,
    required double? sensorTemp,
    required double? sensorHumidity,
  }) {
    final apiData = _latestApiData;
    if (apiData == null) return;

    _statsBuffer.addPm25(sensorPm25, apiData.pm25);
    _statsBuffer.addTemp(sensorTemp, apiData.temperature);
    _statsBuffer.addHum(sensorHumidity, apiData.humidity);

    _latestComparison = ComparisonResult(
      title: apiData.stationName ?? '근처 측정소 비교',
      subtitle: _city ?? '현재 위치 기준',
      timestamp: apiData.retrievedAt,
      stationLatitude: apiData.stationLatitude,
      stationLongitude: apiData.stationLongitude,
      pm25: ExternalMetricComparison(
        sensor: sensorPm25,
        station: apiData.pm25,
        delta: _calcDelta(sensorPm25, apiData.pm25),
        unit: 'µg/m³',
        stats: _StatsBuffer.calcStats(_statsBuffer.pm25),
      ),
      temperature: ExternalMetricComparison(
        sensor: sensorTemp,
        station: apiData.temperature,
        delta: _calcDelta(sensorTemp, apiData.temperature),
        unit: '°C',
        stats: _StatsBuffer.calcStats(_statsBuffer.temp),
      ),
      humidity: ExternalMetricComparison(
        sensor: sensorHumidity,
        station: apiData.humidity,
        delta: _calcDelta(sensorHumidity, apiData.humidity),
        unit: '%',
        stats: _StatsBuffer.calcStats(_statsBuffer.hum),
      ),
    );
  }

  Future<void> _fetchAll() async {
    try {
      await _fetchLocation();
      if (_lat == null || _lon == null) return;
      await Future.wait(<Future<void>>[
        _fetchWaqi(),
        _fetchKma(),
      ]);
    } catch (error) {
      _log('외부 API 오류: $error');
    }
  }

  Future<void> _fetchLocation() async {
    if (_lat != null && _lon != null) return;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _log('기기 위치 서비스가 꺼져 있어 공식 측정소 비교 위치를 정할 수 없습니다.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _log('위치 권한이 없어 공식 측정소 비교를 갱신하지 않습니다.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );
      _lat = position.latitude;
      _lon = position.longitude;
      _city = '현재 위치';
    } catch (error) {
      _log('기기 위치 확인 오류: $error');
    }
  }

  Future<void> _fetchWaqi() async {
    if (_lat == null || _lon == null || _waqiToken.trim().isEmpty) return;

    try {
      final uri = Uri.parse(
        'https://api.waqi.info/feed/geo:'
        '${_lat!.toStringAsFixed(10)};${_lon!.toStringAsFixed(10)}/'
        '?token=$_waqiToken',
      );
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;

      final data = json.decode(response.body);
      if (data is! Map || data['status'] != 'ok') return;
      final payload = _asMap(data['data']);
      if (payload == null) return;

      final cityInfo = _asMap(payload['city']);
      final stationName = cityInfo?['name']?.toString();
      final stationGeo = cityInfo?['geo'];
      final stationLatitude = stationGeo is List && stationGeo.isNotEmpty
          ? _asDouble(stationGeo[0])
          : null;
      final stationLongitude = stationGeo is List && stationGeo.length > 1
          ? _asDouble(stationGeo[1])
          : null;
      if (stationName != null && stationName.trim().isNotEmpty) {
        _city = stationName;
      }

      _latestApiData = ExternalApiData(
        pm25: _asDouble(payload['aqi']),
        temperature: _latestApiData?.temperature,
        humidity: _latestApiData?.humidity,
        windSpeed: _latestApiData?.windSpeed,
        stationName: stationName,
        stationLatitude: stationLatitude,
        stationLongitude: stationLongitude,
        city: _city,
        region: cityInfo?['url']?.toString(),
        retrievedAt: DateTime.now(),
      );
    } catch (error) {
      _log('WAQI 오류: $error');
    }
  }

  Future<void> _fetchKma() async {
    if (_lat == null || _lon == null || _kmaServiceKey.trim().isEmpty) return;

    try {
      final sample = await _fetchKmaPoint(
        latitude: _lat!,
        longitude: _lon!,
        logErrors: true,
      );
      if (sample == null) return;

      _latestApiData = ExternalApiData(
        pm25: _latestApiData?.pm25,
        temperature: sample.temperature ?? _latestApiData?.temperature,
        humidity: sample.humidity ?? _latestApiData?.humidity,
        windSpeed: sample.windSpeed ?? _latestApiData?.windSpeed,
        stationName: _latestApiData?.stationName,
        stationLatitude: _latestApiData?.stationLatitude,
        stationLongitude: _latestApiData?.stationLongitude,
        city: _city,
        region: _latestApiData?.region,
        retrievedAt: DateTime.now(),
      );
    } catch (error) {
      _log('KMA 오류: $error');
    }
  }

  Future<
      ({
        double? temperature,
        double? humidity,
        double? windSpeed,
        DateTime observedAt,
      })?> _fetchKmaPoint({
    required double latitude,
    required double longitude,
    required bool logErrors,
  }) async {
    final grid = _latLonToGrid(latitude, longitude);
    final nowKst = DateTime.now().toUtc().add(const Duration(hours: 9));
    var baseDateTime = DateTime.utc(
      nowKst.year,
      nowKst.month,
      nowKst.day,
      nowKst.hour,
    );
    if (nowKst.minute < 45) {
      baseDateTime = baseDateTime.subtract(const Duration(hours: 1));
    }
    final baseDate =
        '${baseDateTime.year}${baseDateTime.month.toString().padLeft(2, '0')}${baseDateTime.day.toString().padLeft(2, '0')}';
    final baseTime =
        '${baseDateTime.hour.toString().padLeft(2, '0')}${baseDateTime.minute.toString().padLeft(2, '0')}';
    final uri = Uri.parse(
      'https://apis.data.go.kr/1360000/'
      'VilageFcstInfoService_2.0/getUltraSrtNcst',
    ).replace(
      queryParameters: <String, String>{
        'serviceKey': _kmaServiceKey,
        'numOfRows': '60',
        'pageNo': '1',
        'dataType': 'JSON',
        'base_date': baseDate,
        'base_time': baseTime,
        'nx': grid.x.toString(),
        'ny': grid.y.toString(),
      },
    );

    try {
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        if (logErrors) _log('KMA HTTP 오류: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body);
      final responseMap = data is Map ? _asMap(data['response']) : null;
      final header = _asMap(responseMap?['header']);
      final resultCode = header?['resultCode']?.toString();
      if (resultCode != '00') {
        if (logErrors) {
          _log('KMA 응답 오류: $resultCode ${header?['resultMsg'] ?? ''}');
        }
        return null;
      }

      final body = _asMap(responseMap?['body']);
      final items = _asMap(body?['items']);
      final itemList = items?['item'];
      if (itemList is! List) {
        if (logErrors) _log('KMA 응답에 관측 항목이 없습니다.');
        return null;
      }

      double? temperature;
      double? humidity;
      double? windSpeed;
      for (final item in itemList) {
        final map = _asMap(item);
        if (map == null) continue;
        final category = map['category']?.toString();
        final value = _asDouble(map['obsrValue']);
        if (category == 'T1H') temperature = value;
        if (category == 'REH') humidity = value;
        if (category == 'WSD') windSpeed = value;
      }
      if (temperature == null && humidity == null && windSpeed == null) {
        if (logErrors) _log('KMA 응답에서 온도/습도 항목을 찾지 못했습니다.');
      }
      return (
        temperature: temperature,
        humidity: humidity,
        windSpeed: windSpeed,
        observedAt: DateTime.now(),
      );
    } catch (error) {
      if (logErrors) _log('KMA 오류: $error');
      return null;
    }
  }

  static String? _calcDelta(double? sensor, double? api) {
    if (sensor == null || api == null) return null;
    final delta = sensor - api;
    final sign = delta >= 0 ? '+' : '';
    return '$sign${delta.toStringAsFixed(1)}';
  }

  static ({int x, int y}) _latLonToGrid(double lat, double lon) {
    const re = 6371.00877 / 5.0;
    const degrad = math.pi / 180.0;
    const slat1 = 30.0 * degrad;
    const slat2 = 60.0 * degrad;
    const olon = 126.0 * degrad;
    const olat = 38.0 * degrad;
    const xo = 43;
    const yo = 136;

    final sn = math.log(math.cos(slat1) / math.cos(slat2)) /
        math.log(
          math.tan(math.pi * 0.25 + slat2 * 0.5) /
              math.tan(math.pi * 0.25 + slat1 * 0.5),
        );
    final sf = math.pow(math.tan(math.pi * 0.25 + slat1 * 0.5), sn) *
        math.cos(slat1) /
        sn;
    final ro = re * sf / math.pow(math.tan(math.pi * 0.25 + olat * 0.5), sn);
    final ra =
        re * sf / math.pow(math.tan(math.pi * 0.25 + lat * degrad * 0.5), sn);
    var theta = lon * degrad - olon;
    if (theta > math.pi) theta -= 2.0 * math.pi;
    if (theta < -math.pi) theta += 2.0 * math.pi;
    theta *= sn;

    final x = (ra * math.sin(theta) + xo + 0.5).floor();
    final y = (ro - ra * math.cos(theta) + yo + 0.5).floor();
    return (x: x, y: y);
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  static double? _asDouble(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null && parsed.isFinite) return parsed;
    }
    return null;
  }

  NearbyPm25Station? _stationFromWaqiMapItem(Object? item) {
    final map = _asMap(item);
    if (map == null) return null;
    final latitude = _asDouble(map['lat']);
    final longitude = _asDouble(map['lon']);
    final aqiRaw = map['aqi'];
    final pm25 = _asDouble(aqiRaw);
    if (latitude == null ||
        longitude == null ||
        pm25 == null ||
        !pm25.isFinite ||
        pm25 < 0) {
      return null;
    }
    final station = _asMap(map['station']);
    final name = station?['name']?.toString().trim();
    final time = _asMap(map['time']);
    final observedAt = DateTime.tryParse(time?['stime']?.toString() ?? '');
    return NearbyPm25Station(
      name: name == null || name.isEmpty ? '공식 측정소' : name,
      latitude: latitude,
      longitude: longitude,
      pm25: pm25,
      uid: map['uid']?.toString(),
      observedAt: observedAt,
    );
  }

  Future<NearbyPm25Station> _stationWithDetailedPm25(
    NearbyPm25Station station,
  ) async {
    final uid = station.uid?.trim();
    if (uid == null || uid.isEmpty) return station;
    try {
      final uri = Uri.parse(
        'https://api.waqi.info/feed/@$uid/?token=$_waqiToken',
      );
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return station;
      final data = json.decode(response.body);
      if (data is! Map || data['status'] != 'ok') return station;
      final payload = _asMap(data['data']);
      final iaqi = _asMap(payload?['iaqi']);
      final pm25Map = _asMap(iaqi?['pm25']);
      final pm25 = _asDouble(pm25Map?['v']);
      if (pm25 == null || !pm25.isFinite || pm25 < 0) return station;
      final pm10 = _asDouble(_asMap(iaqi?['pm10'])?['v']);
      final no2 = _asDouble(_asMap(iaqi?['no2'])?['v']);
      final o3 = _asDouble(_asMap(iaqi?['o3'])?['v']);
      final co = _asDouble(_asMap(iaqi?['co'])?['v']);
      final time = _asMap(payload?['time']);
      final observedAt =
          DateTime.tryParse(time?['s']?.toString() ?? '') ?? station.observedAt;
      return station.copyWith(
        pm25: pm25,
        pm10: pm10,
        no2: no2,
        o3: o3,
        co: co,
        observedAt: observedAt,
      );
    } catch (_) {
      return station;
    }
  }

  static double _distanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
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

  void _log(String message) {
    // ignore: avoid_print
    print('[ExternalApiService] $message');
  }
}
