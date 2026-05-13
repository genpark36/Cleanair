import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'csv_file_write_result.dart';

Future<CsvFileWriteResult> writeCsvFile({
  required String metricName,
  required String csvContent,
}) async {
  if (Platform.isAndroid) {
    final result = await _writeAndroidDownloadsCsv(
      metricName: metricName,
      csvContent: csvContent,
    );
    if (result != null) return result;
  }

  final csvDir = await _resolveCsvDirectory();
  if (!await csvDir.exists()) {
    await csvDir.create(recursive: true);
  }

  final fileName = _csvFileName(metricName);
  final filePath = '${csvDir.path}${Platform.pathSeparator}$fileName';
  await File(filePath).writeAsString(csvContent);

  return CsvFileWriteResult(filePath: filePath, fileName: fileName);
}

Future<CsvFileWriteResult?> _writeAndroidDownloadsCsv({
  required String metricName,
  required String csvContent,
}) async {
  const channel = MethodChannel('cleanair/csv');
  final fileName = _csvFileName(metricName);
  try {
    final path = await channel.invokeMethod<String>(
      'saveCsvToDownloads',
      <String, String>{
        'fileName': fileName,
        'csvContent': csvContent,
      },
    );
    if (path == null || path.trim().isEmpty) return null;
    return CsvFileWriteResult(filePath: path, fileName: fileName);
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

String _csvFileName(String metricName) {
  final now = DateTime.now();
  final normalizedMetric = metricName.replaceAll(
    RegExp(r'[^A-Za-z0-9_-]'),
    '_',
  );
  return '${normalizedMetric}_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.csv';
}

Future<Directory> _resolveCsvDirectory() async {
  if (Platform.isAndroid) {
    final downloadsDir = Directory('/storage/emulated/0/Download/AirGradient');
    try {
      await downloadsDir.create(recursive: true);
      return downloadsDir;
    } catch (_) {
      final status = await Permission.storage.request();
      if (status.isGranted) {
        await downloadsDir.create(recursive: true);
        return downloadsDir;
      }
    }
    final external = await getExternalStorageDirectory();
    if (external != null) {
      return Directory(
        '${external.path}${Platform.pathSeparator}Download${Platform.pathSeparator}AirGradient',
      );
    }
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}${Platform.pathSeparator}AirGradient');
  }

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      return Directory(
        '${downloads.path}${Platform.pathSeparator}AirGradient',
      );
    }
  }

  final docs = await getApplicationDocumentsDirectory();
  return Directory('${docs.path}${Platform.pathSeparator}AirGradient');
}
