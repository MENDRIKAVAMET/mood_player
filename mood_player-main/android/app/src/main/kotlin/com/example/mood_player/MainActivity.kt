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
import android.annotation.SuppressLint
import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore

class MainActivity : AudioServiceFragmentActivity() {
    private val crashLogChannelName = "com.example.mood_player/crash_log"
    private val navigationChannelName = "com.example.mood_player/navigation"
    private val filesChannelName = "com.example.mood_player/files"

    // Renommage en attente de l'autorisation de l'utilisateur (Android 10+).
    private val requestWriteAccess = 4711
    private var pendingRename: RenameRequest? = null
    private var pendingRenameResult: MethodChannel.Result? = null

    private data class RenameRequest(
        val uri: Uri,
        val displayName: String,
        val title: String,
        val artist: String
    )

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

        // Le bouton retour système, à la racine de l'app (rien à dépiler
        // côté Navigator Flutter), ne doit pas fermer l'app comme le
        // ferait un `finish()` classique : on veut le même effet que le
        // bouton Accueil, qui renvoie juste la tâche en arrière-plan sans
        // tuer l'Activity ni interrompre la lecture en cours. On gère ça
        // nous-mêmes plutôt que de compter sur le comportement par défaut
        // de Flutter, pour être sûr que ça marche sur tous les appareils.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, navigationChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveTaskToBack" -> {
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Renommage d'un fichier audio via MediaStore : le système renomme
        // vraiment le fichier et garde le même identifiant (donc le même
        // uri de lecture).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, filesChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "renameAudio" -> handleRenameAudio(call.argument("uri"),
                        call.argument("displayName"), call.argument("title"),
                        call.argument("artist"), result)
                    else -> result.notImplemented()
                }
            }
    }

    @SuppressLint("NewApi")
    private fun handleRenameAudio(
        uri: String?,
        displayName: String?,
        title: String?,
        artist: String?,
        result: MethodChannel.Result
    ) {
        if (uri == null || displayName == null || title == null || artist == null) {
            result.error("ARGS", "Arguments manquants", null)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("UNSUPPORTED", "Android 10 ou plus requis", null)
            return
        }
        if (pendingRenameResult != null) {
            result.error("BUSY", "Un renommage est déjà en cours", null)
            return
        }
        performRename(RenameRequest(Uri.parse(uri), displayName, title, artist), result, false)
    }

    @SuppressLint("NewApi")
    private fun performRename(
        request: RenameRequest,
        result: MethodChannel.Result,
        alreadyAsked: Boolean
    ) {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, request.displayName)
            put(MediaStore.Audio.Media.TITLE, request.title)
            put(MediaStore.Audio.Media.ARTIST, request.artist)
        }
        try {
            val updated = contentResolver.update(request.uri, values, null, null)
            if (updated <= 0) {
                result.error("NOT_FOUND", "Fichier introuvable", null)
                return
            }
            result.success(queryPath(request.uri))
        } catch (e: SecurityException) {
            if (alreadyAsked) {
                result.error("DENIED", "Autorisation refusée", null)
                return
            }
            val sender = when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
                    MediaStore.createWriteRequest(contentResolver, listOf(request.uri)).intentSender
                e is android.app.RecoverableSecurityException ->
                    e.userAction.actionIntent.intentSender
                else -> null
            }
            if (sender == null) {
                result.error("DENIED", "Autorisation refusée", null)
                return
            }
            pendingRename = request
            pendingRenameResult = result
            startIntentSenderForResult(sender, requestWriteAccess, null, 0, 0, 0)
        } catch (e: Exception) {
            result.error("FAILED", e.message ?: "Échec du renommage", null)
        }
    }

    private fun queryPath(uri: Uri): String? {
        contentResolver.query(
            uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0)
        }
        return null
    }

    @SuppressLint("NewApi")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == requestWriteAccess) {
            val request = pendingRename
            val result = pendingRenameResult
            pendingRename = null
            pendingRenameResult = null
            if (request != null && result != null) {
                if (resultCode == Activity.RESULT_OK) {
                    performRename(request, result, true)
                } else {
                    result.error("DENIED", "Autorisation refusée", null)
                }
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
