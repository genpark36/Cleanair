import '../features/disaster_device/disaster_device_storage.dart';
import 'alert_notification_presenter.dart';
import 'csv_file_writer.dart';

class PlugControlHistoryCsvExportResult {
  const PlugControlHistoryCsvExportResult({
    required this.filePath,
    required this.fileName,
    required this.rowCount,
  });

  final String filePath;
  final String fileName;
  final int rowCount;
}

class PlugControlHistoryCsvExportService {
  Future<PlugControlHistoryCsvExportResult> exportHistory({
    required List<DisasterDeviceHistoryEntry> entries,
    String metricName = 'plug_control_history',
  }) async {
    final sorted = List<DisasterDeviceHistoryEntry>.of(entries)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (sorted.isEmpty) {
      throw StateError('내보낼 플러그 제어 이력이 없습니다.');
    }

    final buffer = StringBuffer(
      'timestamp,device_id,display_name,action,status,ok,power_on,message,request,response\n',
    );
    for (final entry in sorted) {
      buffer.writeln(
        <String>[
          entry.createdAt.toIso8601String(),
          entry.deviceId,
          entry.displayName,
          entry.action,
          entry.status,
          entry.ok ? 'true' : 'false',
          entry.powerOn == null ? '' : (entry.powerOn! ? 'ON' : 'OFF'),
          entry.message,
          entry.requestLog,
          entry.responseLog,
        ].map(_csvText).join(','),
      );
    }

    final fileResult = await writeCsvFile(
      metricName: metricName,
      csvContent: buffer.toString(),
    );
    await AlertNotificationPresenter.showDownloadCompleted(
      filePath: fileResult.filePath,
      fileName: fileResult.fileName,
    );
    return PlugControlHistoryCsvExportResult(
      filePath: fileResult.filePath,
      fileName: fileResult.fileName,
      rowCount: sorted.length,
    );
  }

  String _csvText(String value) {
    final escaped = value.replaceAll('"', '""').replaceAll('\n', ' ');
    return '"$escaped"';
  }
}
