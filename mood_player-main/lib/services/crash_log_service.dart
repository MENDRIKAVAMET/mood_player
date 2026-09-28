import 'package:flutter/services.dart';

/// Reads the crash log written natively by CrashHandlerApplication when the
/// app died from an uncaught (often native) exception on the previous run -
/// useful for diagnosing crashes on devices with no adb access.
class CrashLogService {
  static const _channel = MethodChannel('com.example.mood_player/crash_log');

  /// Returns the last crash's full stack trace, or null if the app didn't
  /// crash since the log was last cleared.
  static Future<String?> getLastCrashLog() async {
    try {
      return await _channel.invokeMethod<String>('getLastCrashLog');
    } on PlatformException {
      return null;
    }
  }

  /// Clears the stored crash log (call after showing it to the user so the
  /// same crash isn't reported again on the next launch).
  static Future<void> clearCrashLog() async {
    try {
      await _channel.invokeMethod('clearCrashLog');
    } on PlatformException {
      // Ignore - nothing to clear.
    }
  }
}
