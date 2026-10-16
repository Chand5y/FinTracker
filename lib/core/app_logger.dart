import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class AppLogger {
  static final AppLogger instance = AppLogger._internal();
  AppLogger._internal();

  final List<String> _logs = [];
  final ValueNotifier<int> logNotifier = ValueNotifier<int>(0);

  void log(String message) {
    final timestamp = DateTime.now().toIso8601String().split('T').last.substring(0, 12);
    final entry = '[$timestamp] $message';
    _logs.add(entry);
    debugPrint(entry);
    logNotifier.value = _logs.length;
  }

  List<String> get logs => List.unmodifiable(_logs);

  void clear() {
    _logs.clear();
    logNotifier.value = 0;
    log('Logs cleared by user.');
  }

  Future<String?> exportToDownloads() async {
    try {
      if (Platform.isAndroid) {
        // Request storage permissions if needed for legacy versions, or write directly to app storage / downloads
        final status = await Permission.storage.request();
        // Even if denied on scoped storage, we can use external storage directory or downloads
      }

      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory == null) return null;

      final file = File('${directory.path}/FinTrax_Debug_Log_${DateTime.now().millisecondsSinceEpoch}.txt');
      await file.writeAsString(_logs.join('\n'));
      log('Logs successfully exported to: ${file.path}');
      return file.path;
    } catch (e) {
      log('Export failed: $e');
      return null;
    }
  }
}
