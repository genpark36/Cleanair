import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/air_quality_snapshot.dart';

class LocalSnapshotStore {
  static const _key = 'cleanair_recent_snapshots_v1';
  static const _maxEntries = 360;

  Future<List<StoredSnapshot>> loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) {
      return const <StoredSnapshot>[];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <StoredSnapshot>[];
      }
      return decoded
          .whereType<Map>()
          .map(
            (entry) => StoredSnapshot.fromMap(Map<String, dynamic>.from(entry)),
          )
          .where((entry) => entry != null)
          .cast<StoredSnapshot>()
          .toList();
    } catch (_) {
      return const <StoredSnapshot>[];
    }
  }

  Future<void> appendSnapshot(AirQualitySnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    final recent = await loadRecent();
    final next = [...recent, StoredSnapshot.fromSnapshot(snapshot)];
    final trimmed = next.length > _maxEntries
        ? next.sublist(next.length - _maxEntries)
        : next;
    await prefs.setString(
      _key,
      jsonEncode(trimmed.map((entry) => entry.toMap()).toList()),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

class StoredSnapshot {
  const StoredSnapshot({
    required this.timestamp,
    this.id,
    this.pm25,
    this.co2,
    this.tvoc,
    this.nox,
    this.co,
    this.temperature,
    this.humidity,
    this.iaqiScore,
    this.aqiLevel,
    this.aqiCategory,
  });

  final DateTime timestamp;
  final String? id;
  final double? pm25;
  final double? co2;
  final double? tvoc;
  final double? nox;
  final double? co;
  final double? temperature;
  final double? humidity;
  final double? iaqiScore;
  final String? aqiLevel;
  final String? aqiCategory;

  factory StoredSnapshot.fromSnapshot(AirQualitySnapshot snapshot) {
    return StoredSnapshot(
      timestamp: snapshot.timestamp,
      id: snapshot.id,
      pm25: snapshot.pm25,
      co2: snapshot.co2,
      tvoc: snapshot.tvoc,
      nox: snapshot.nox,
      co: snapshot.co,
      temperature: snapshot.temperature,
      humidity: snapshot.humidity,
      iaqiScore: snapshot.iaqiScore,
      aqiLevel: snapshot.aqiLevel,
      aqiCategory: snapshot.aqiCategory,
    );
  }

  static StoredSnapshot? fromMap(Map<String, dynamic> map) {
    final timestamp = DateTime.tryParse(map['timestamp']?.toString() ?? '');
    if (timestamp == null) {
      return null;
    }
    return StoredSnapshot(
      timestamp: timestamp.toLocal(),
      id: map['id']?.toString(),
      pm25: _toDouble(map['pm25']),
      co2: _toDouble(map['co2']),
      tvoc: _toDouble(map['tvoc']),
      nox: _toDouble(map['nox']),
      co: _toDouble(map['co']),
      temperature: _toDouble(map['temperature']),
      humidity: _toDouble(map['humidity']),
      iaqiScore: _toDouble(map['iaqiScore']),
      aqiLevel: map['aqiLevel']?.toString(),
      aqiCategory: map['aqiCategory']?.toString(),
    );
  }

  AirQualitySnapshot toSnapshot() {
    return AirQualitySnapshot(
      id: id,
      timestamp: timestamp,
      pm25: pm25,
      co2: co2,
      tvoc: tvoc,
      nox: nox,
      co: co,
      temperature: temperature,
      humidity: humidity,
      iaqiScore: iaqiScore,
      aqiLevel: aqiLevel,
      aqiCategory: aqiCategory,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'timestamp': timestamp.toIso8601String(),
      'id': id,
      'pm25': pm25,
      'co2': co2,
      'tvoc': tvoc,
      'nox': nox,
      'co': co,
      'temperature': temperature,
      'humidity': humidity,
      'iaqiScore': iaqiScore,
      'aqiLevel': aqiLevel,
      'aqiCategory': aqiCategory,
    };
  }
}

double? _toDouble(dynamic value) {
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}
