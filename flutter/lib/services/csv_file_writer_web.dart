// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'csv_file_write_result.dart';

Future<CsvFileWriteResult> writeCsvFile({
  required String metricName,
  required String csvContent,
}) async {
  final now = DateTime.now();
  final normalizedMetric = metricName.replaceAll(
    RegExp(r'[^A-Za-z0-9_-]'),
    '_',
  );
  final fileName =
      '${normalizedMetric}_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.csv';
  final blob = html.Blob(<String>[csvContent], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = fileName
    ..click();
  html.Url.revokeObjectUrl(url);

  return CsvFileWriteResult(filePath: fileName, fileName: fileName);
}
