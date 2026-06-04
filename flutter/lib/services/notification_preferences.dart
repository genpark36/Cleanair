import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Immutable snapshot of the user's notification settings.
@immutable
class NotificationPreferences {
  const NotificationPreferences({
    required this.alertsEnabled,
    required this.quietHoursEnabled,
    required this.quietHoursStartMinutes,
    required this.quietHoursEndMinutes,
    required this.notificationIntervalMinutes,
    required this.minimumSeverityPriority,
    required this.minimumSeverityByType,
    required this.fireRiskMinimumLevel,
    required this.slackWebhookUrl,
    required this.snoozedUntil,
    required this.mutedTypes,
  });

  factory NotificationPreferences.defaults() {
    return NotificationPreferences(
      alertsEnabled: true,
      quietHoursEnabled: false,
      quietHoursStartMinutes: 22 * 60,
      quietHoursEndMinutes: 7 * 60,
      notificationIntervalMinutes: 15,
      minimumSeverityPriority: 2,
      minimumSeverityByType: _defaultSeverityByType(),
      fireRiskMinimumLevel: 'strong_warning',
      slackWebhookUrl: '',
      snoozedUntil: null,
      mutedTypes: _defaultMutedTypes(),
    );
  }

  final bool alertsEnabled;
  final bool quietHoursEnabled;
  final int quietHoursStartMinutes;
  final int quietHoursEndMinutes;
  final int notificationIntervalMinutes;
  final int minimumSeverityPriority;
  final Map<String, int> minimumSeverityByType;
  final String fireRiskMinimumLevel;
  final String slackWebhookUrl;
  final DateTime? snoozedUntil;
  final Map<String, bool> mutedTypes;

  static const List<String> supportedAlertTypes = [
    'pm25_high',
    'co2_high',
    'tvoc_high',
    'nox_high',
    'fire_risk',
    'plug_control',
    'respiratory_low',
    'infection_risk',
    'focus_poor',
    'mold_risk',
    'cardio_low',
    'sleep_quality_low',
    'apparent_temp_morning',
    'apparent_temp_evening',
  ];

  NotificationPreferences copyWith({
    bool? alertsEnabled,
    bool? quietHoursEnabled,
    int? quietHoursStartMinutes,
    int? quietHoursEndMinutes,
    int? notificationIntervalMinutes,
    int? minimumSeverityPriority,
    Map<String, int>? minimumSeverityByType,
    String? fireRiskMinimumLevel,
    String? slackWebhookUrl,
    DateTime? Function()? snoozedUntil,
    Map<String, bool>? mutedTypes,
  }) {
    return NotificationPreferences(
      alertsEnabled: alertsEnabled ?? this.alertsEnabled,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietHoursStartMinutes:
          quietHoursStartMinutes ?? this.quietHoursStartMinutes,
      quietHoursEndMinutes: quietHoursEndMinutes ?? this.quietHoursEndMinutes,
      notificationIntervalMinutes:
          notificationIntervalMinutes ?? this.notificationIntervalMinutes,
      minimumSeverityPriority:
          minimumSeverityPriority ?? this.minimumSeverityPriority,
      minimumSeverityByType:
          minimumSeverityByType ?? this.minimumSeverityByType,
      fireRiskMinimumLevel: fireRiskMinimumLevel ?? this.fireRiskMinimumLevel,
      slackWebhookUrl: slackWebhookUrl ?? this.slackWebhookUrl,
      snoozedUntil: snoozedUntil != null ? snoozedUntil() : this.snoozedUntil,
      mutedTypes: mutedTypes ?? this.mutedTypes,
    );
  }

  bool get hasQuietHoursWindow =>
      quietHoursStartMinutes % _minutesPerDay !=
      quietHoursEndMinutes % _minutesPerDay;

  /// Returns true if quiet hours are enabled and [now] is inside the window.
  bool isWithinQuietHours(DateTime now) {
    if (!quietHoursEnabled || !hasQuietHoursWindow) {
      return false;
    }
    final totalMinutes = now.hour * 60 + now.minute;
    final start = quietHoursStartMinutes % _minutesPerDay;
    final end = quietHoursEndMinutes % _minutesPerDay;
    if (start < end) {
      return totalMinutes >= start && totalMinutes < end;
    }
    return totalMinutes >= start || totalMinutes < end;
  }

  bool isSnoozed(DateTime now) {
    final until = snoozedUntil;
    if (until == null) return false;
    return until.isAfter(now);
  }

  Duration? snoozeRemaining(DateTime now) {
    if (!isSnoozed(now)) return null;
    return snoozedUntil!.difference(now);
  }

  bool shouldSuppress(DateTime now) {
    if (!alertsEnabled) return true;
    if (isSnoozed(now)) return true;
    if (isWithinQuietHours(now)) return true;
    return false;
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'alertsEnabled': alertsEnabled,
      'quietHoursEnabled': quietHoursEnabled,
      'quietHoursStartMinutes': quietHoursStartMinutes,
      'quietHoursEndMinutes': quietHoursEndMinutes,
      'notificationIntervalMinutes': notificationIntervalMinutes,
      'minimumSeverityPriority': minimumSeverityPriority,
      'minimumSeverityByType': minimumSeverityByType,
      'fireRiskMinimumLevel': fireRiskMinimumLevel,
      'slackWebhookUrl': slackWebhookUrl,
      'snoozedUntil': snoozedUntil?.toIso8601String(),
      'mutedTypes': mutedTypes,
    };
  }

  static NotificationPreferences fromMap(Map<String, Object?>? map) {
    if (map == null || map.isEmpty) {
      return NotificationPreferences.defaults();
    }
    final mutedTypes = _defaultMutedTypes();
    final severityByType = _defaultSeverityByType();
    final rawMuted = map['mutedTypes'];
    if (rawMuted is Map) {
      for (final entry in rawMuted.entries) {
        final key = entry.key?.toString();
        if (key != null && mutedTypes.containsKey(key)) {
          mutedTypes[key] = entry.value == true;
        }
      }
    } else if (rawMuted is List) {
      for (final item in rawMuted) {
        final key = item?.toString();
        if (key != null && mutedTypes.containsKey(key)) {
          mutedTypes[key] = true;
        }
      }
    }
    final rawSeverityByType = map['minimumSeverityByType'];
    if (rawSeverityByType is Map) {
      for (final entry in rawSeverityByType.entries) {
        final key = entry.key?.toString();
        if (key != null && severityByType.containsKey(key)) {
          severityByType[key] = _sanitizeSeverity(entry.value);
        }
      }
    }
    final snoozeIso = map['snoozedUntil'] as String?;
    final snooze = snoozeIso == null ? null : DateTime.tryParse(snoozeIso);
    return NotificationPreferences(
      alertsEnabled: map['alertsEnabled'] as bool? ?? true,
      quietHoursEnabled: map['quietHoursEnabled'] as bool? ?? false,
      quietHoursStartMinutes:
          map['quietHoursStartMinutes'] as int? ?? (22 * 60),
      quietHoursEndMinutes: map['quietHoursEndMinutes'] as int? ?? (7 * 60),
      notificationIntervalMinutes:
          _sanitizeInterval(map['notificationIntervalMinutes']),
      minimumSeverityPriority:
          _sanitizeSeverity(map['minimumSeverityPriority']),
      minimumSeverityByType: severityByType,
      fireRiskMinimumLevel: _sanitizeFireRiskLevel(map['fireRiskMinimumLevel']),
      slackWebhookUrl: _sanitizeSlackWebhookUrl(map['slackWebhookUrl']),
      snoozedUntil: snooze?.toLocal(),
      mutedTypes: mutedTypes,
    );
  }

  static int _sanitizeInterval(Object? raw) {
    final value = raw is int
        ? raw
        : raw is num
            ? raw.round()
            : raw is String
                ? int.tryParse(raw)
                : null;
    if (value == null) return 15;
    return value.clamp(1, 24 * 60).toInt();
  }

  static int _sanitizeSeverity(Object? raw) {
    final value = raw is int
        ? raw
        : raw is num
            ? raw.round()
            : raw is String
                ? int.tryParse(raw)
                : null;
    if (value == null) return 2;
    return value.clamp(1, 3).toInt();
  }

  static String _sanitizeFireRiskLevel(Object? raw) {
    final value = raw?.toString();
    if (value == 'warning' ||
        value == 'strong_warning' ||
        value == 'fire_suspected') {
      return value!;
    }
    return 'strong_warning';
  }

  static String _sanitizeSlackWebhookUrl(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return '';
    if (!value.startsWith('https://hooks.slack.com/services/')) return '';
    return value;
  }
}

const int _minutesPerDay = 24 * 60;

class NotificationPreferencesStorage {
  static const _alertsEnabledKey = 'alerts_enabled';
  static const _quietHoursEnabledKey = 'quiet_hours_enabled';
  static const _quietHoursStartKey = 'quiet_hours_start';
  static const _quietHoursEndKey = 'quiet_hours_end';
  static const _notificationIntervalKey = 'notification_interval_minutes';
  static const _minimumSeverityKey = 'minimum_alert_severity_priority';
  static const _minimumSeverityByTypeKey = 'minimum_alert_severity_by_type';
  static const _fireRiskMinimumLevelKey = 'fire_risk_minimum_level';
  static const _slackWebhookUrlKey = 'slack_webhook_url';
  static const _snoozedUntilKey = 'alerts_snoozed_until';
  static const _mutedTypesKey = 'alerts_muted_types';

  Future<NotificationPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    final muted = _defaultMutedTypes();
    final severityByType = _defaultSeverityByType();
    final mutedList = prefs.getStringList(_mutedTypesKey) ?? const <String>[];
    for (final key in mutedList) {
      if (muted.containsKey(key)) {
        muted[key] = true;
      }
    }
    final rawSeverityByType =
        prefs.getStringList(_minimumSeverityByTypeKey) ?? const <String>[];
    for (final item in rawSeverityByType) {
      final separator = item.indexOf('=');
      if (separator <= 0) continue;
      final key = item.substring(0, separator);
      if (!severityByType.containsKey(key)) continue;
      severityByType[key] = NotificationPreferences._sanitizeSeverity(
          item.substring(separator + 1));
    }
    return NotificationPreferences(
      alertsEnabled: prefs.getBool(_alertsEnabledKey) ?? true,
      quietHoursEnabled: prefs.getBool(_quietHoursEnabledKey) ?? false,
      quietHoursStartMinutes: prefs.getInt(_quietHoursStartKey) ?? (22 * 60),
      quietHoursEndMinutes: prefs.getInt(_quietHoursEndKey) ?? (7 * 60),
      notificationIntervalMinutes:
          (prefs.getInt(_notificationIntervalKey) ?? 15)
              .clamp(1, 24 * 60)
              .toInt(),
      minimumSeverityPriority:
          (prefs.getInt(_minimumSeverityKey) ?? 2).clamp(1, 3).toInt(),
      minimumSeverityByType: severityByType,
      fireRiskMinimumLevel: NotificationPreferences._sanitizeFireRiskLevel(
        prefs.getString(_fireRiskMinimumLevelKey),
      ),
      slackWebhookUrl: NotificationPreferences._sanitizeSlackWebhookUrl(
        prefs.getString(_slackWebhookUrlKey),
      ),
      snoozedUntil: _parseDate(prefs.getString(_snoozedUntilKey)),
      mutedTypes: muted,
    );
  }

  Future<void> save(NotificationPreferences value) async {
    final prefs = await SharedPreferences.getInstance();
    final mutedList = value.mutedTypes.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList(growable: false);
    final severityByTypeList = value.minimumSeverityByType.entries
        .map((entry) => '${entry.key}=${entry.value.clamp(1, 3).toInt()}')
        .toList(growable: false);
    await Future.wait([
      prefs.setBool(_alertsEnabledKey, value.alertsEnabled),
      prefs.setBool(_quietHoursEnabledKey, value.quietHoursEnabled),
      prefs.setInt(_quietHoursStartKey, value.quietHoursStartMinutes),
      prefs.setInt(_quietHoursEndKey, value.quietHoursEndMinutes),
      prefs.setInt(
        _notificationIntervalKey,
        value.notificationIntervalMinutes.clamp(1, 24 * 60).toInt(),
      ),
      prefs.setInt(
        _minimumSeverityKey,
        value.minimumSeverityPriority.clamp(1, 3).toInt(),
      ),
      prefs.setStringList(_minimumSeverityByTypeKey, severityByTypeList),
      prefs.setString(
        _fireRiskMinimumLevelKey,
        value.fireRiskMinimumLevel,
      ),
      if (value.slackWebhookUrl.trim().isEmpty)
        prefs.remove(_slackWebhookUrlKey)
      else
        prefs.setString(_slackWebhookUrlKey, value.slackWebhookUrl.trim()),
      if (value.snoozedUntil == null)
        prefs.remove(_snoozedUntilKey)
      else
        prefs.setString(
          _snoozedUntilKey,
          value.snoozedUntil!.toIso8601String(),
        ),
      if (mutedList.isEmpty)
        prefs.remove(_mutedTypesKey)
      else
        prefs.setStringList(_mutedTypesKey, mutedList),
    ]);
  }

  DateTime? _parseDate(String? iso8601) {
    if (iso8601 == null || iso8601.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(iso8601);
    return parsed?.toLocal();
  }
}

class NotificationPreferencesController extends ChangeNotifier {
  NotificationPreferencesController(this._storage);

  final NotificationPreferencesStorage _storage;
  NotificationPreferences _prefs = NotificationPreferences.defaults();
  bool _loaded = false;

  NotificationPreferences get value => _prefs;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    _prefs = await _storage.load();
    _loaded = true;
    notifyListeners();
  }

  Future<void> setAlertsEnabled(bool enabled) async {
    await _update(_prefs.copyWith(alertsEnabled: enabled));
    if (!enabled) {
      await _clearSnoozeInternal();
    }
  }

  Future<void> setQuietHoursEnabled(bool enabled) async {
    await _update(
      _prefs.copyWith(quietHoursEnabled: enabled && _prefs.hasQuietHoursWindow),
    );
  }

  Future<void> updateQuietHours({
    bool? enabled,
    int? startMinutes,
    int? endMinutes,
  }) async {
    final sanitizedStart =
        _sanitizeMinutes(startMinutes ?? _prefs.quietHoursStartMinutes);
    final sanitizedEnd =
        _sanitizeMinutes(endMinutes ?? _prefs.quietHoursEndMinutes);
    final hasWindow = sanitizedStart != sanitizedEnd;
    final requestedEnabled = enabled ?? _prefs.quietHoursEnabled;
    final next = _prefs.copyWith(
      quietHoursStartMinutes: sanitizedStart,
      quietHoursEndMinutes: sanitizedEnd,
      quietHoursEnabled: requestedEnabled && hasWindow,
    );
    await _update(next);
  }

  Future<void> snoozeFor(Duration duration) async {
    final until = DateTime.now().add(duration);
    await _update(
      _prefs.copyWith(snoozedUntil: () => until),
    );
  }

  Future<void> clearSnooze() async {
    await _clearSnoozeInternal();
  }

  Future<void> setMutedType(String type, bool muted) async {
    final nextMuted = Map<String, bool>.from(_prefs.mutedTypes);
    if (!nextMuted.containsKey(type)) return;
    nextMuted[type] = muted;
    await _update(_prefs.copyWith(mutedTypes: nextMuted));
  }

  Future<void> setNotificationIntervalMinutes(int minutes) async {
    final sanitized = minutes.clamp(1, 24 * 60).toInt();
    await _update(_prefs.copyWith(notificationIntervalMinutes: sanitized));
  }

  Future<void> setMinimumSeverityPriority(int priority) async {
    final sanitized = priority.clamp(1, 3).toInt();
    await _update(_prefs.copyWith(minimumSeverityPriority: sanitized));
  }

  Future<void> setMinimumSeverityForType(String type, int priority) async {
    if (!NotificationPreferences.supportedAlertTypes.contains(type)) return;
    final nextByType = Map<String, int>.from(_prefs.minimumSeverityByType);
    nextByType[type] = priority.clamp(1, 3).toInt();
    await _update(_prefs.copyWith(minimumSeverityByType: nextByType));
  }

  Future<void> setFireRiskMinimumLevel(String level) async {
    final sanitized = NotificationPreferences._sanitizeFireRiskLevel(level);
    final nextByType = Map<String, int>.from(_prefs.minimumSeverityByType);
    nextByType['fire_risk'] = sanitized == 'warning' ? 2 : 3;
    await _update(
      _prefs.copyWith(
        fireRiskMinimumLevel: sanitized,
        minimumSeverityByType: nextByType,
      ),
    );
  }

  Future<void> setSlackWebhookUrl(String url) async {
    await _update(
      _prefs.copyWith(
        slackWebhookUrl: NotificationPreferences._sanitizeSlackWebhookUrl(url),
      ),
    );
  }

  Future<void> _clearSnoozeInternal() async {
    if (_prefs.snoozedUntil == null) return;
    await _update(_prefs.copyWith(snoozedUntil: () => null));
  }

  Future<void> _update(NotificationPreferences next) async {
    _prefs = next;
    await _storage.save(next);
    notifyListeners();
  }

  int _sanitizeMinutes(int value) {
    final normalized = value % _minutesPerDay;
    return normalized < 0 ? normalized + _minutesPerDay : normalized;
  }
}

Map<String, bool> _defaultMutedTypes() {
  return {
    for (final type in NotificationPreferences.supportedAlertTypes) type: false,
  };
}

Map<String, int> _defaultSeverityByType() {
  return {
    for (final type in NotificationPreferences.supportedAlertTypes) type: 2,
  };
}
