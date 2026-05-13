class TasmotaDeviceTestResult {
  const TasmotaDeviceTestResult({
    required this.ok,
    required this.statusLabel,
    required this.message,
    this.powerOn,
    this.telemetry = const <String, dynamic>{},
    this.isPending = false,
  });

  final bool ok;
  final String statusLabel;
  final String message;
  final bool? powerOn;
  final Map<String, dynamic> telemetry;
  final bool isPending;

  factory TasmotaDeviceTestResult.success({
    required String statusLabel,
    required String message,
    bool? powerOn,
    Map<String, dynamic> telemetry = const <String, dynamic>{},
  }) {
    return TasmotaDeviceTestResult(
      ok: true,
      statusLabel: statusLabel,
      message: message,
      powerOn: powerOn,
      telemetry: telemetry,
    );
  }

  factory TasmotaDeviceTestResult.failure({
    required String statusLabel,
    required String message,
  }) {
    return TasmotaDeviceTestResult(
      ok: false,
      statusLabel: statusLabel,
      message: message,
    );
  }

  factory TasmotaDeviceTestResult.pending({
    required String statusLabel,
    required String message,
  }) {
    return TasmotaDeviceTestResult(
      ok: false,
      statusLabel: statusLabel,
      message: message,
      isPending: true,
    );
  }
}
