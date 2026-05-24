import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SituationResolutionResult {
  const SituationResolutionResult({
    required this.resolvedIncidents,
    required this.resolvedAlerts,
    required this.failedAlerts,
  });

  final int resolvedIncidents;
  final int resolvedAlerts;
  final int failedAlerts;

  int get totalResolved => resolvedIncidents + resolvedAlerts;
  bool get hasFailure => failedAlerts > 0;
}

class SituationResolutionService {
  SituationResolutionService({
    FirebaseFirestore? firestore,
    http.Client? client,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _client = client ?? http.Client();

  static const Duration _timeout = Duration(seconds: 8);
  static const String _functionsBaseUrl = String.fromEnvironment(
    'CLOUD_FUNCTION_BASE_URL',
    defaultValue:
        'https://us-central1-capstone-cleanair-2026.cloudfunctions.net',
  );
  static const String _fallbackBaseUrl =
      String.fromEnvironment('BACKEND_BASE_URL', defaultValue: '');
  static const String _deviceApiKey =
      String.fromEnvironment('DEVICE_API_KEY', defaultValue: '');

  final FirebaseFirestore _firestore;
  final http.Client _client;

  String get _baseUrl {
    if (_functionsBaseUrl.trim().isNotEmpty) return _functionsBaseUrl.trim();
    return _fallbackBaseUrl.trim();
  }

  Map<String, String> _headers() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_deviceApiKey.trim().isNotEmpty) {
      headers['X-API-Key'] = _deviceApiKey.trim();
    }
    return headers;
  }

  Future<SituationResolutionResult> resolveActiveSituation({
    required String? userId,
    required List<String> sensorIds,
  }) async {
    final resolvedIncidents = await _resolveActiveIncidents(userId);
    final alertIds = await _activeAlertIdsForSensors(sensorIds);
    var resolvedAlerts = 0;
    var failedAlerts = 0;

    for (final alertId in alertIds) {
      final ok = await _resolveAlert(alertId);
      if (ok) {
        resolvedAlerts++;
      } else {
        failedAlerts++;
      }
    }

    return SituationResolutionResult(
      resolvedIncidents: resolvedIncidents,
      resolvedAlerts: resolvedAlerts,
      failedAlerts: failedAlerts,
    );
  }

  Future<int> _resolveActiveIncidents(String? userId) async {
    final uid = userId?.trim();
    if (uid == null || uid.isEmpty) return 0;

    final snapshot = await _firestore
        .collection('user_profiles')
        .doc(uid)
        .collection('incidents')
        .where('status', isEqualTo: 'active')
        .limit(20)
        .get();
    if (snapshot.docs.isEmpty) return 0;

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.set(
        doc.reference,
        <String, Object?>{
          'status': 'resolved',
          'resolvedAt': FieldValue.serverTimestamp(),
          'resolvedBy': uid,
          'resolutionNote': 'closed_from_mobile_app',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
    return snapshot.docs.length;
  }

  Future<List<String>> _activeAlertIdsForSensors(List<String> sensorIds) async {
    final candidates = <String>[
      for (final sensorId in sensorIds)
        if (sensorId.trim().isNotEmpty) sensorId.trim(),
    ];
    final unique = candidates.toSet().take(10).toList(growable: false);
    if (unique.isEmpty) return const <String>[];

    final snapshot = await _firestore
        .collection('alerts')
        .where('sensorId', whereIn: unique)
        .limit(50)
        .get();
    final alertIds = <String>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (_isResolvedAlert(data)) continue;
      final severity = data['severity']?.toString().toLowerCase().trim() ?? '';
      final level = data['level']?.toString().toLowerCase().trim() ?? '';
      if (severity == 'notice' || level == 'notice') continue;
      alertIds.add(doc.id);
    }
    return alertIds;
  }

  bool _isResolvedAlert(Map<String, dynamic> data) {
    final status = data['status']?.toString().toLowerCase().trim() ?? '';
    return data['resolvedAt'] != null ||
        status == 'resolved' ||
        status == 'closed' ||
        status == 'ended' ||
        status == 'archived';
  }

  Future<bool> _resolveAlert(String alertId) async {
    if (_baseUrl.isEmpty) return false;

    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/resolveAlert'),
            headers: _headers(),
            body: jsonEncode(<String, Object?>{
              'alertId': alertId,
              'resolvedBy': 'mobile_app',
              'resolutionNote': 'closed_from_mobile_app',
            }),
          )
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final decoded = jsonDecode(response.body);
      return decoded is Map && decoded['ok'] == true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('resolveAlert failed: $error');
      }
      return false;
    }
  }
}
