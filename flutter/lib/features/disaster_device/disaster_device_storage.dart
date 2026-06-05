import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'disaster_device_draft.dart';

class DisasterDeviceHistoryEntry {
  const DisasterDeviceHistoryEntry({
    required this.deviceId,
    required this.displayName,
    required this.action,
    required this.status,
    required this.ok,
    this.powerOn,
    required this.message,
    this.requestLog = '',
    this.responseLog = '',
    required this.createdAt,
  });

  final String deviceId;
  final String displayName;
  final String action;
  final String status;
  final bool ok;
  final bool? powerOn;
  final String message;
  final String requestLog;
  final String responseLog;
  final DateTime createdAt;

  factory DisasterDeviceHistoryEntry.fromJson(Map<String, dynamic> json) {
    return DisasterDeviceHistoryEntry(
      deviceId: _readString(json, 'deviceId'),
      displayName: _readString(json, 'displayName'),
      action: _readString(json, 'action'),
      status: _readString(json, 'status'),
      ok: json['ok'] == true,
      powerOn: json['powerOn'] is bool ? json['powerOn'] as bool : null,
      message: _readString(json, 'message'),
      requestLog: _readString(json, 'requestLog'),
      responseLog: _readString(json, 'responseLog'),
      createdAt: _readDateTime(json, 'createdAt'),
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'displayName': displayName,
        'action': action,
        'status': status,
        'ok': ok,
        'powerOn': powerOn,
        'message': message,
        if (requestLog.trim().isNotEmpty) 'requestLog': requestLog,
        if (responseLog.trim().isNotEmpty) 'responseLog': responseLog,
        'createdAt': createdAt.toIso8601String(),
      };

  static String _readString(Map<String, dynamic> json, String key) {
    return json[key]?.toString().trim() ?? '';
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

class DisasterDeviceStorage {
  static const _draftKey = 'disaster_device_draft_v1';
  static const _draftsKey = 'disaster_device_drafts_v2';
  static const _historyKey = 'disaster_device_history_v1';

  Future<DisasterDeviceDraft?> load() async {
    final drafts = await loadAll();
    return drafts.isEmpty ? null : drafts.first;
  }

  Future<List<DisasterDeviceDraft>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getString(_draftsKey);
    if (rawList != null && rawList.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawList);
        if (decoded is List) {
          final drafts = decoded
              .whereType<Map>()
              .map((item) =>
                  DisasterDeviceDraft.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: true);
          final normalized = _dedupe(drafts);
          final normalizedJson = jsonEncode(
            normalized.map((draft) => draft.toJson()).toList(),
          );
          if (normalizedJson != rawList) {
            await prefs.setString(_draftsKey, normalizedJson);
            if (normalized.isEmpty) {
              await prefs.remove(_draftKey);
            } else {
              await prefs.setString(
                _draftKey,
                jsonEncode(normalized.first.toJson()),
              );
            }
          }
          return normalized;
        }
      } catch (_) {
        // Fall through to the v1 single-device migration path.
      }
    }

    final raw = prefs.getString(_draftKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <DisasterDeviceDraft>[];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <DisasterDeviceDraft>[];
      final draft =
          DisasterDeviceDraft.fromJson(Map<String, dynamic>.from(decoded));
      final normalized = _dedupe(<DisasterDeviceDraft>[draft]);
      await prefs.setString(
        _draftsKey,
        jsonEncode(normalized.map((item) => item.toJson()).toList()),
      );
      return normalized;
    } catch (_) {
      return const <DisasterDeviceDraft>[];
    }
  }

  Future<void> save(DisasterDeviceDraft draft) async {
    final drafts = await loadAll();
    final index = drafts.indexWhere((item) => item.deviceId == draft.deviceId);
    if (index >= 0) {
      drafts[index] = draft;
    } else {
      drafts.add(draft);
    }
    await saveAll(drafts);
  }

  Future<void> saveAll(List<DisasterDeviceDraft> drafts) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _dedupe(drafts);
    final ok = await prefs.setString(
        _draftsKey,
        jsonEncode(normalized.map((draft) {
          return draft.toJson();
        }).toList()));
    if (!ok) {
      throw StateError('Failed to save disaster device draft');
    }

    if (normalized.isEmpty) {
      await prefs.remove(_draftKey);
    } else {
      await prefs.setString(_draftKey, jsonEncode(normalized.first.toJson()));
    }
  }

  Future<List<DisasterDeviceHistoryEntry>> loadHistory({
    String? deviceId,
    int limit = 30,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <DisasterDeviceHistoryEntry>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <DisasterDeviceHistoryEntry>[];
      final target = deviceId?.trim();
      return decoded
          .whereType<Map>()
          .map((item) => DisasterDeviceHistoryEntry.fromJson(
              Map<String, dynamic>.from(item)))
          .where((entry) => target == null || target.isEmpty
              ? true
              : entry.deviceId == target)
          .take(limit)
          .toList(growable: false);
    } catch (_) {
      return const <DisasterDeviceHistoryEntry>[];
    }
  }

  Future<void> appendHistory(DisasterDeviceHistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await loadHistory(limit: 100);
    final next = <DisasterDeviceHistoryEntry>[entry, ...history].take(100);
    await prefs.setString(
      _historyKey,
      jsonEncode(next.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
    await prefs.remove(_draftsKey);
    await prefs.remove(_historyKey);
  }

  List<DisasterDeviceDraft> _dedupe(List<DisasterDeviceDraft> drafts) {
    final seen = <String>{};
    final seenTopics = <String>{};
    final seenNames = <String>{};
    final result = <DisasterDeviceDraft>[];
    for (final draft in drafts) {
      var id = draft.deviceId.trim();
      if (id.isEmpty || seen.contains(id)) {
        id = _nextPlugId(seen);
      }
      seen.add(id);
      var topic = _normalizeMqttTopic(draft.mqttTopic);
      final usesMqtt = draft.controlMethod.toUpperCase().contains('MQTT');
      if (usesMqtt && topic.isEmpty) {
        topic = id.replaceAll('-', '_');
      }
      if (topic.isNotEmpty && seenTopics.contains(topic.toLowerCase())) {
        topic = _nextMqttTopic(seenTopics);
      }
      if (topic.isNotEmpty) {
        seenTopics.add(topic.toLowerCase());
      }
      final fallbackName = '스마트 플러그 ${result.length + 1}';
      final displayName = _uniqueDisplayName(
        draft.displayName.trim().isEmpty ? fallbackName : draft.displayName,
        seenNames,
      );
      result.add(
        draft.copyWith(
          deviceId: id,
          mqttTopic: topic,
          displayName: displayName,
        ),
      );
    }
    return result;
  }

  String _uniqueDisplayName(String rawName, Set<String> seenNames) {
    final base = rawName.trim().replaceAll(RegExp(r'\s+'), ' ');
    var name = base.isEmpty ? '스마트 플러그' : base;
    var key = name.toLowerCase();
    if (!seenNames.contains(key)) {
      seenNames.add(key);
      return name;
    }
    var number = 2;
    while (true) {
      name = '$base $number';
      key = name.toLowerCase();
      if (!seenNames.contains(key)) {
        seenNames.add(key);
        return name;
      }
      number += 1;
    }
  }

  String _normalizeMqttTopic(String value) {
    var text = value.trim();
    if (text.isEmpty) return '';
    text = text.replaceAll('\\', '/');
    if (text.contains('/')) {
      final parts =
          text.split('/').where((part) => part.trim().isNotEmpty).toList();
      if (parts.length >= 2) {
        final prefix = parts.first.trim().toLowerCase();
        if (prefix == 'cmnd' || prefix == 'stat' || prefix == 'tele') {
          text = parts[1].trim();
        }
      }
    }
    text = text.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    text = text.replaceAll(RegExp(r'_+'), '_');
    text = text.replaceAll(RegExp(r'^_+|_+$'), '');
    return text;
  }

  String _nextPlugId(Set<String> seen) {
    var number = 1;
    while (true) {
      final id = 'cleanair-plug-${number.toString().padLeft(2, '0')}';
      if (!seen.contains(id)) return id;
      number += 1;
    }
  }

  String _nextMqttTopic(Set<String> seenTopics) {
    var number = 1;
    while (true) {
      final topic = 'cleanair_plug_${number.toString().padLeft(2, '0')}';
      if (!seenTopics.contains(topic)) return topic;
      number += 1;
    }
  }
}
