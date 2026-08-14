import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/debug/crash_log_screen.dart';
import 'features/home/home_screen.dart';
import 'services/crash_log_service.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';

/// Every startup step wrapped in a timeout so a hung native call (e.g.
/// Isar.open() on a database left in a bad state by a mid-write crash)
/// can never keep the app on a permanent blank/white screen before
/// runApp() is called.
const _startupStepTimeout = Duration(seconds: 8);

void main() {
  // runZonedGuarded catches anything that slips past try/catch elsewhere
  // (stray async errors, third-party plugin callbacks, etc.) so it's
  // logged instead of silently crashing the whole app.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Route framework-level errors (widget build errors etc.) through the
    // same guarded zone instead of only printing to console and leaving
    // the screen blank.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      // ignore: avoid_print
      print('FlutterError: ${details.exceptionAsString()}\n${details.stack}');
    };

    // Set system UI overlay style for immersive dark theme
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.backgroundPrimary,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    String? startupError;

    // Load environment variables. Non-fatal if it fails/times out - the
    // app can still run without it.
    try {
      await dotenv.load().timeout(_startupStepTimeout);
    } catch (e, st) {
      // ignore: avoid_print
      print('main: dotenv.load failed: $e\n$st');
    }

    // Initialize local storage. This is the step most likely to hang or
    // throw right after a crash mid-write (corrupted/locked database) -
    // catch both so we always reach runApp().
    try {
      await StorageService.initialize().timeout(_startupStepTimeout);
    } catch (e, st) {
      // ignore: avoid_print
      print('main: StorageService.initialize failed: $e\n$st');
      startupError = 'Le stockage local n\'a pas pu être initialisé.\n$e';
    }

    // If the previous run died from an uncaught (often native) exception,
    // CrashHandlerApplication will have written its stack trace to a file.
    // Surface it here so it can be diagnosed without adb/logcat access.
    String? crashLog;
    try {
      crashLog = await CrashLogService.getLastCrashLog().timeout(_startupStepTimeout);
    } catch (e, st) {
      // ignore: avoid_print
      print('main: getLastCrashLog failed: $e\n$st');
    }

    runApp(ProviderScope(
      child: MyApp(crashLog: crashLog, startupError: startupError),
    ));
  }, (error, stackTrace) {
    // ignore: avoid_print
    print('Uncaught zone error: $error\n$stackTrace');
  });
}

class MyApp extends StatelessWidget {
  final String? crashLog;
  final String? startupError;

  const MyApp({super.key, this.crashLog, this.startupError});

  @override
  Widget build(BuildContext context) {
    Widget home;
    if (crashLog != null) {
      home = CrashLogScreen(log: crashLog!);
    } else if (startupError != null) {
      home = _StartupErrorScreen(message: startupError!);
    } else {
      home = const HomeScreen();
    }

    return MaterialApp(
      title: 'Mood Player',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: home,
    );
  }
}

/// Shown instead of a blank screen when a startup step (typically local
/// storage) failed or timed out, so there's always something visible and
/// actionable instead of an app that looks dead.
class _StartupErrorScreen extends StatelessWidget {
  final String message;

  const _StartupErrorScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              const Text(
                "Échec du démarrage",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}