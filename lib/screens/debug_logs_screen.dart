import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_logger.dart';
import '../core/constants.dart';

class DebugLogsScreen extends StatelessWidget {
  const DebugLogsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backend Diagnostic Logs', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Clear Logs',
            onPressed: () {
              HapticFeedback.mediumImpact();
              AppLogger.instance.clear();
            },
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Save to Downloads',
            onPressed: () async {
              HapticFeedback.mediumImpact();
              final path = await AppLogger.instance.exportToDownloads();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(path != null ? 'Saved to: $path' : 'Failed to save log file.'),
                    backgroundColor: path != null ? AppConstants.incomeGreen : AppConstants.expenseRed,
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: AppLogger.instance.logNotifier,
        builder: (context, _, __) {
          final logs = AppLogger.instance.logs;
          if (logs.isEmpty) {
            return const Center(child: Text('No logs recorded yet.', style: TextStyle(color: Colors.grey)));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              final isError = log.contains('Error') || log.contains('failed') || log.contains('Exception') || log.contains('10:');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  log,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    color: isError ? AppConstants.expenseRed : Colors.grey[300],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
