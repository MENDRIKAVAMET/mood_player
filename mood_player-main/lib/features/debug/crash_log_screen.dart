import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/crash_log_service.dart';
import '../../theme/app_theme.dart';

/// Shown right after a launch that follows a fatal crash on the previous
/// run. Displays the raw native stack trace so it can be copied and shared
/// without needing adb/logcat access.
class CrashLogScreen extends StatelessWidget {
  final String log;

  const CrashLogScreen({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundPrimary,
        title: const Text('Dernier crash'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copier',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: log));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Log copié dans le presse-papiers')),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                "L'application s'est fermée brutalement lors du dernier lancement. "
                'Copie ce log et transmets-le pour diagnostic.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SelectableText(
                  log,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                onPressed: () async {
                  await CrashLogService.clearCrashLog();
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Fermer et effacer le log'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
