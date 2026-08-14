package com.example.mood_player

// AudioServiceActivity (plain) extends FlutterActivity, not
// FlutterFragmentActivity. on_audio_query, permission_handler, and
// file_picker all expect a FlutterFragmentActivity host to correctly
// attach/reattach around permission requests. With a plain FlutterActivity,
// that attachment breaks and on_audio_query is left with its internal
// (lateinit) Activity context uninitialized, causing every library scan to
// fail with: PlatformException(..., lateinit property context has not been
// initialized, ...). Using the FragmentActivity variant fixes this at the
// root instead of retrying around it.
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceFragmentActivity() {
    private val crashLogChannelName = "com.example.mood_player/crash_log"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, crashLogChannelName)
            .setMethodCallHandler { call, result ->
                val file = File(filesDir, CrashHandlerApplication.CRASH_LOG_FILE_NAME)
                when (call.method) {
                    "getLastCrashLog" -> {
                        if (file.exists()) {
                            result.success(file.readText())
                        } else {
                            result.success(null)
                        }
                    }
                    "clearCrashLog" -> {
                        if (file.exists()) file.delete()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
