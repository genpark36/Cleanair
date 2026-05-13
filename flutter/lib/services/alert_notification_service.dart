import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/air_quality_snapshot.dart';
import 'alert_notification_engine.dart';
import 'alert_notification_presenter.dart';
import 'firestore_snapshot_service.dart';
import 'notification_preferences.dart';

class AlertNotificationService {
  AlertNotificationService({
    required FirestoreSnapshotService snapshotService,
    required NotificationPreferencesController preferences,
  })  : _snapshotService = snapshotService,
        _preferences = preferences;

  final FirestoreSnapshotService _snapshotService;
  final NotificationPreferencesController _preferences;
  final AlertNotificationEngine _engine = AlertNotificationEngine();

  StreamSubscription<AirQualitySnapshot>? _subscription;
  bool _initialized = false;
  VoidCallback? _prefsListener;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb) {
      return;
    }

    await AlertNotificationPresenter.ensureInitialized();
    _prefsListener = () => _engine.purgeExpired(DateTime.now());
    _preferences.addListener(_prefsListener!);
    _subscription ??=
        _snapshotService.snapshots.listen(_handleSnapshot, onError: _handleError);
  }

  void _handleSnapshot(AirQualitySnapshot snapshot) {
    final now = DateTime.now();
    final prefs = _preferences.value;
    final messages = _engine.notifiableMessages(snapshot, prefs, now);
    if (messages.isEmpty) {
      return;
    }
    for (final message in messages) {
      unawaited(AlertNotificationPresenter.showAlert(
        '공기질 경보',
        message,
        payload: snapshot.id,
      ));
    }
  }

  void _handleError(Object error, StackTrace stackTrace) {
    // ignore: avoid_print
    print('[alert] Firestore stream error: $error');
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    final listener = _prefsListener;
    if (listener != null) {
      _preferences.removeListener(listener);
      _prefsListener = null;
    }
  }
}
