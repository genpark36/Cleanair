import 'dart:async';

import 'package:multicast_dns/multicast_dns.dart';

class DiscoveredAirGradientSensor {
  const DiscoveredAirGradientSensor({
    required this.id,
    required this.displayId,
    required this.name,
    this.ip,
  });

  final String id;
  final String displayId;
  final String name;
  final String? ip;
}

class AirGradientMdnsService {
  static const _serviceName = '_airgradient._tcp.local';

  Future<List<DiscoveredAirGradientSensor>> discover({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final client = MDnsClient();
    final sensors = <DiscoveredAirGradientSensor>[];

    try {
      await client.start();
      final ptrStream = client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(_serviceName),
          )
          .timeout(timeout);

      await for (final ptr in ptrStream) {
        final sensor = await _sensorFromPtr(client, ptr);
        if (sensor == null) continue;
        final exists = sensors.any((entry) => entry.id == sensor.id);
        if (!exists) sensors.add(sensor);
      }
    } on TimeoutException {
      // Timeout simply means discovery finished for this scan window.
    } finally {
      client.stop();
    }

    return sensors;
  }

  Future<DiscoveredAirGradientSensor?> _sensorFromPtr(
    MDnsClient client,
    PtrResourceRecord ptr,
  ) async {
    var serial = '';
    String? ip;

    try {
      await for (final txt in client
          .lookup<TxtResourceRecord>(ResourceRecordQuery.text(ptr.domainName))
          .timeout(const Duration(seconds: 2))) {
        serial = _extractSerialFromTxtRecord(txt.text);
        if (serial.isNotEmpty) break;
      }
    } on TimeoutException {
      // Continue with SRV/IP lookup; some firmware may not advertise TXT.
    }

    try {
      await for (final srv in client
          .lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName))
          .timeout(const Duration(seconds: 2))) {
        await for (final record in client
            .lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
            )
            .timeout(const Duration(seconds: 2))) {
          ip = record.address.address;
          break;
        }
        break;
      }
    } on TimeoutException {
      // IP is useful for local settings but not required for Firestore binding.
    }

    if (serial.isEmpty) {
      serial = ptr.domainName.split('.').first.trim();
    }
    if (serial.isEmpty) return null;

    final trimmedSerial = serial.trim();
    final normalizedId = normalizeSensorId(trimmedSerial);
    final id = trimmedSerial.toLowerCase().startsWith('airgradient:')
        ? trimmedSerial
        : (normalizedId.isNotEmpty ? normalizedId : trimmedSerial);
    return DiscoveredAirGradientSensor(
      id: id,
      displayId: trimmedSerial,
      name: 'AirGradient 센서',
      ip: ip,
    );
  }

  static String normalizeSensorId(String value) {
    return value
        .replaceFirst(RegExp(r'^airgradient[:_-]?', caseSensitive: false), '')
        .replaceAll(':', '')
        .replaceAll('-', '')
        .replaceAll('_', '')
        .trim()
        .toLowerCase();
  }

  static List<String> sensorIdCandidates(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return const <String>[];

    final compact = normalizeSensorId(raw);
    final colonMac = _colonMacFromCompact(compact);
    final lowerRaw = raw.toLowerCase();
    final candidates = <String>[
      raw,
      lowerRaw,
      if (compact.isNotEmpty) compact,
      if (compact.isNotEmpty) 'airgradient:$compact',
      if (colonMac != null) 'airgradient:$colonMac',
    ];

    final unique = <String>[];
    for (final candidate in candidates) {
      final trimmed = candidate.trim();
      if (trimmed.isEmpty || unique.contains(trimmed)) continue;
      unique.add(trimmed);
    }
    return unique;
  }

  static String? _colonMacFromCompact(String value) {
    final compact = value.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{12}$').hasMatch(compact)) return null;
    return [
      for (var i = 0; i < compact.length; i += 2) compact.substring(i, i + 2),
    ].join(':');
  }

  String _extractSerialFromTxtRecord(String payload) {
    for (final raw in payload.split(RegExp(r'[\r\n]+'))) {
      final line = raw.trim();
      if (line.startsWith('serialno=')) {
        return line.substring('serialno='.length).trim();
      }
    }
    return '';
  }
}
