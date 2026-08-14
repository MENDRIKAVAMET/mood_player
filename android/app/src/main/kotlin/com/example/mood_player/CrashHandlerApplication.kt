package com.example.mood_player

import android.app.Application
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Without adb access, a fatal crash (e.g. a native exception thrown deep
 * inside a plugin, like audio_service starting its foreground service)
 * just closes the app with nothing visible anywhere. This Application
 * subclass installs a global uncaught-exception handler that writes the
 * full stack trace to a file in internal storage *before* letting the
 * crash proceed as normal (so the app still closes exactly as before -
 * this only adds a log we can read back later).
 *
 * MainActivity exposes that file's content to Dart via a MethodChannel so
 * it can be shown on the next app launch (see CrashLogChannel.kt).
 */
class CrashHandlerApplication : io.flutter.app.FlutterApplication() {
    companion object {
        const val CRASH_LOG_FILE_NAME = "last_crash.log"
    }

    override fun onCreate() {
        super.onCreate()

        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                writeCrashLog(thread, throwable)
            } catch (loggingError: Throwable) {
                // Never let the logger itself prevent the crash from being
                // reported to the system's default handler below.
            }
            // Preserve normal crash behavior (process death, any existing
            // crash reporting) - we're only adding a side-effect log.
            defaultHandler?.uncaughtException(thread, throwable)
        }
    }

    private fun writeCrashLog(thread: Thread, throwable: Throwable) {
        val sw = StringWriter()
        val pw = PrintWriter(sw)
        val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())
        pw.println("Crash le $timestamp sur le thread '${thread.name}'")
        pw.println()
        throwable.printStackTrace(pw)
        pw.flush()

        val file = File(filesDir, CRASH_LOG_FILE_NAME)
        file.writeText(sw.toString())
    }
}
