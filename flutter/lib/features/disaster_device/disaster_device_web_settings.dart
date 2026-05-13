import 'package:flutter/services.dart';

import 'disaster_device_draft.dart';

class DisasterDeviceWebSettings {
  const DisasterDeviceWebSettings._();

  static String? validatePlugIp(String plugIp) {
    final ip = plugIp.trim();
    if (ip.isEmpty || !_isValidIpv4(ip)) {
      return '유효한 플러그 IP를 먼저 입력해 주세요.';
    }
    return null;
  }

  static String settingsUrlForIp(String plugIp) {
    return 'http://${plugIp.trim()}';
  }

  static Future<String?> copySettingsUrl(DisasterDeviceDraft draft) async {
    final validationMessage = validatePlugIp(draft.plugIp);
    if (validationMessage != null) return null;
    final url = settingsUrlForIp(draft.plugIp);
    await Clipboard.setData(ClipboardData(text: url));
    return url;
  }

  static bool _isValidIpv4(String value) {
    final parts = value.trim().split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      if (part.isEmpty || !_digitsOnly.hasMatch(part)) return false;
      final parsed = int.tryParse(part);
      if (parsed == null || parsed < 0 || parsed > 255) return false;
    }
    return true;
  }

  static final _digitsOnly = RegExp(r'^\d+$');
}
