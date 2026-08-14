import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'features/debug/crash_log_screen.dart';
import 'features/home/home_screen.dart';
import 'services/crash_log_service.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set system UI overlay style for immersive dark theme
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.backgroundPrimary,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  
  // Load environment variables
  await dotenv.load();

  // Required on Android 13+ for the playback notification (audio_service).
  // Requested early so the foreground media service can start cleanly;
  // playback still works even if this is denied, just without a visible
  // notification.
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }

  // Initialize local storage
  await StorageService.initialize();

  // If the previous run died from an uncaught (often native) exception,
  // CrashHandlerApplication will have written its stack trace to a file.
  // Surface it here so it can be diagnosed without adb/logcat access.
  final crashLog = await CrashLogService.getLastCrashLog();

  runApp(ProviderScope(child: MyApp(crashLog: crashLog)));
}

class MyApp extends StatelessWidget {
  final String? crashLog;

  const MyApp({super.key, this.crashLog});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mood Player',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: crashLog != null ? CrashLogScreen(log: crashLog!) : const HomeScreen(),
    );
  }
}