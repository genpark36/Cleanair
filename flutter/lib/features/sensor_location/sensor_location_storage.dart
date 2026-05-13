import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'sensor_location_draft.dart';

class SensorLocationStorage {
  static const _draftKey = 'sensor_location_draft_v1';
  static const _stitchLocationKey = 'stitch_location_v1';
  static const _locationsBySensorKey = 'sensor_location_by_sensor_v1';

  Future<SensorLocationDraft?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stitchLocation = _decodeStitchLocation(
      prefs.getString(_stitchLocationKey),
    );
    if (stitchLocation != null) return stitchLocation;
    return _decodeDraft(prefs.getString(_draftKey));
  }

  Future<SensorLocationDraft?> loadForSensor(String? sensorId) async {
    final normalizedId = sensorId?.trim() ?? '';
    if (normalizedId.isEmpty) return load();

    final prefs = await SharedPreferences.getInstance();
    final locations = _decodeLocationMap(
      prefs.getString(_locationsBySensorKey),
    );
    final mapped = locations[normalizedId];
    if (mapped != null) return mapped;

    final legacy = _decodeStitchLocation(
          prefs.getString(_stitchLocationKey),
        ) ??
        _decodeDraft(prefs.getString(_draftKey));
    if (legacy?.sensorId.trim() == normalizedId) return legacy;
    return null;
  }

  Future<List<SensorLocationDraft>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeLocationMap(
      prefs.getString(_locationsBySensorKey),
    ).values.toList(growable: false);
  }

  Future<void> save(SensorLocationDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    final locations = _decodeLocationMap(
      prefs.getString(_locationsBySensorKey),
    );
    final sensorId = draft.sensorId.trim();
    if (sensorId.isNotEmpty) {
      locations[sensorId] = draft;
    }
    final draftOk = await prefs.setString(_draftKey, jsonEncode(draft.toJson()));
    final stitchOk = await prefs.setString(
      _stitchLocationKey,
      jsonEncode(draft.toStitchJson()),
    );
    final locationsOk = await prefs.setString(
      _locationsBySensorKey,
      jsonEncode(
        locations.map(
          (key, value) => MapEntry<String, dynamic>(key, value.toJson()),
        ),
      ),
    );
    if (!draftOk || !stitchOk || !locationsOk) {
      throw StateError('Failed to save sensor location draft');
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
    await prefs.remove(_stitchLocationKey);
    await prefs.remove(_locationsBySensorKey);
  }

  Future<void> clearForSensor(String sensorId) async {
    final normalizedId = sensorId.trim();
    if (normalizedId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final locations = _decodeLocationMap(
      prefs.getString(_locationsBySensorKey),
    );
    locations.remove(normalizedId);
    await prefs.setString(
      _locationsBySensorKey,
      jsonEncode(
        locations.map(
          (key, value) => MapEntry<String, dynamic>(key, value.toJson()),
        ),
      ),
    );
  }

  SensorLocationDraft? _decodeDraft(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return SensorLocationDraft.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  SensorLocationDraft? _decodeStitchLocation(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return SensorLocationDraft.fromStitchJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, SensorLocationDraft> _decodeLocationMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return <String, SensorLocationDraft>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, SensorLocationDraft>{};
      final locations = <String, SensorLocationDraft>{};
      for (final entry in decoded.entries) {
        final key = entry.key.toString().trim();
        final value = entry.value;
        if (key.isEmpty || value is! Map) continue;
        final draft = SensorLocationDraft.fromJson(
          Map<String, dynamic>.from(value),
        );
        locations[key] = draft;
      }
      return locations;
    } catch (_) {
      return <String, SensorLocationDraft>{};
    }
  }
}
