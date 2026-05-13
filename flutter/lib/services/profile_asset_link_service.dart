import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../features/disaster_device/disaster_device_draft.dart';
import '../features/disaster_device/disaster_device_storage.dart';
import '../features/sensor_location/sensor_location_draft.dart';
import '../features/sensor_location/sensor_location_storage.dart';
import 'device_binding_service_v2.dart';

class ProfileAssetSyncResult {
  const ProfileAssetSyncResult({
    required this.sensorCount,
    required this.plugCount,
  });

  final int sensorCount;
  final int plugCount;
}

class ProfileAssetLinkService {
  ProfileAssetLinkService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    DeviceBindingStorageV2? bindingStorage,
    SensorLocationStorage? locationStorage,
    DisasterDeviceStorage? deviceStorage,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _bindingStorage = bindingStorage ?? DeviceBindingStorageV2(),
        _locationStorage = locationStorage ?? SensorLocationStorage(),
        _deviceStorage = deviceStorage ?? DisasterDeviceStorage();

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final DeviceBindingStorageV2 _bindingStorage;
  final SensorLocationStorage _locationStorage;
  final DisasterDeviceStorage _deviceStorage;

  Future<ProfileAssetSyncResult> syncCurrentLocalAssets() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('login required');
    }

    final bindings = await _bindingStorage.loadBindings();
    final locations = await _locationStorage.loadAll();
    final plugs = await _deviceStorage.loadAll();
    final locationBySensor = <String, SensorLocationDraft>{
      for (final location in locations) location.sensorId: location,
    };

    for (final binding in bindings) {
      await linkSensor(
        user: user,
        binding: binding,
        location: locationBySensor[binding.deviceId],
      );
    }
    await _deleteMissing(
      _profileRef(user.uid).collection('sensor_links'),
      bindings.map((binding) => _docId(binding.deviceId)).toSet(),
    );

    for (final plug in plugs) {
      await linkPlug(user: user, plug: plug);
    }
    await _deleteMissing(
      _profileRef(user.uid).collection('plug_links'),
      plugs.map((plug) => _docId(plug.deviceId)).toSet(),
    );

    await _profileRef(user.uid).set(
      {
        'uid': user.uid,
        'email': user.email ?? '',
        'displayName': user.displayName ?? '',
        'photoURL': user.photoURL ?? '',
        'linkedSensorCount': bindings.length,
        'linkedPlugCount': plugs.length,
        'lastAssetSyncAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    return ProfileAssetSyncResult(
      sensorCount: bindings.length,
      plugCount: plugs.length,
    );
  }

  Future<void> linkSensor({
    required User user,
    required DeviceBindingRecordV2 binding,
    SensorLocationDraft? location,
  }) async {
    final sensorId = binding.deviceId.trim();
    if (sensorId.isEmpty) return;
    await _profileRef(user.uid)
        .collection('sensor_links')
        .doc(_docId(sensorId))
        .set(
      {
        'type': 'sensor',
        'sensorId': sensorId,
        'firestoreDocPath': binding.firestoreDocPath,
        'displayName': binding.displayName,
        'localIp': binding.localIp,
        'spaceName': location?.spaceName ?? '',
        'facilityType': location?.facilityType ?? '',
        'buildingName': location?.buildingName ?? '',
        'address': location?.address ?? '',
        'latitude': location?.latitude,
        'longitude': location?.longitude,
        'floor': location?.floor ?? '',
        'detailLocation': location?.detailLocation ?? '',
        'installationMemo': location?.installationMemo ?? '',
        'source': 'flutter_app',
        'localUpdatedAt': location?.updatedAt.toIso8601String(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> linkPlug({
    required User user,
    required DisasterDeviceDraft plug,
  }) async {
    final plugId = plug.deviceId.trim();
    if (plugId.isEmpty) return;
    final voltage = _readTelemetryNumber(plug.telemetry, 'voltage');
    final current = _readTelemetryNumber(plug.telemetry, 'current');
    final powerWatts = _readTelemetryNumber(plug.telemetry, 'power');
    await _profileRef(user.uid)
        .collection('plug_links')
        .doc(_docId(plugId))
        .set(
      {
        'type': 'plug',
        'plugId': plugId,
        'displayName': plug.displayName,
        'deviceType': plug.deviceType,
        'controlMethod': plug.controlMethod,
        'plugIp': plug.plugIp,
        'mqttTopic': plug.mqttTopic,
        'linkedSensorId': plug.linkedSensorId,
        'linkedSpaceName': plug.linkedSpaceName,
        'linkedAddress': plug.linkedAddress,
        'description': plug.description,
        'purpose': plug.purpose,
        'autoControlEnabled': plug.autoControlEnabled,
        'autoMetric': plug.autoMetric,
        'autoOnThreshold': plug.autoOnThreshold,
        'autoOffThreshold': plug.autoOffThreshold,
        'autoHysteresisPercent': plug.autoHysteresisPercent,
        'autoHoldMinutes': plug.autoHoldMinutes,
        'currentPowerOn': plug.currentPowerOn,
        'actualState': plug.currentPowerOn == null
            ? 'UNKNOWN'
            : plug.currentPowerOn == true
                ? 'ON'
                : 'OFF',
        'telemetry': plug.telemetry,
        'voltage': voltage,
        'current': current,
        'powerWatts': powerWatts,
        'lastTestStatus': plug.lastTestStatus,
        'source': 'flutter_app',
        'localUpdatedAt': plug.updatedAt.toIso8601String(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  DocumentReference<Map<String, dynamic>> _profileRef(String uid) {
    return _firestore.collection('user_profiles').doc(uid);
  }

  Future<void> _deleteMissing(
    CollectionReference<Map<String, dynamic>> collection,
    Set<String> currentIds,
  ) async {
    final snapshot = await collection.get();
    for (final doc in snapshot.docs) {
      if (!currentIds.contains(doc.id)) {
        await doc.reference.delete();
      }
    }
  }

  String _docId(String raw) {
    return raw.trim().replaceAll('/', '_');
  }

  double? _readTelemetryNumber(Map<String, dynamic> telemetry, String key) {
    final value = telemetry[key] ?? telemetry[_capitalize(key)];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value.substring(0, 1).toUpperCase() + value.substring(1);
  }
}
