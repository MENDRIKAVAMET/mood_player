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
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.nio.ByteOrder
import java.util.concurrent.Executors
import kotlin.math.log10

class MainActivity : AudioServiceFragmentActivity() {
    private val crashLogChannelName = "com.example.mood_player/crash_log"
    private val navigationChannelName = "com.example.mood_player/navigation"
    private val filesChannelName = "com.example.mood_player/files"

    // Renommage en attente de l'autorisation de l'utilisateur (Android 10+).
    private val requestWriteAccess = 4711
    private var pendingRename: RenameRequest? = null
    private var pendingRenameResult: MethodChannel.Result? = null

    // Analyse du volume (une seule à la fois, hors du thread principal).
    private val analysisExecutor = Executors.newSingleThreadExecutor()

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
                    "analyzeLoudness" -> {
                        val uri = call.argument<String>("uri")
                        val path = call.argument<String>("path")
                        analysisExecutor.execute {
                            val value = try {
                                measureLoudness(uri, path)
                            } catch (e: Throwable) {
                                null
                            }
                            runOnUiThread { result.success(value) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Volume moyen d'un morceau en dBFS (RMS), mesuré sur ~20 s prises vers
     * 30 % de la durée (là où la musique est « en plein régime », loin des
     * intros et des fins calmes). Les passages quasi silencieux
     * (< -50 dBFS) sont ignorés pour ne pas fausser la moyenne.
     * Renvoie null si le fichier ne peut pas être décodé.
     */
    private fun measureLoudness(uri: String?, path: String?): Double? {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            if (uri != null) {
                extractor.setDataSource(applicationContext, Uri.parse(uri), null)
            } else if (path != null) {
                extractor.setDataSource(path)
            } else {
                return null
            }

            var trackIndex = -1
            var format: MediaFormat? = null
            var mime = ""
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                val m = f.getString(MediaFormat.KEY_MIME) ?: continue
                if (m.startsWith("audio/")) {
                    trackIndex = i
                    format = f
                    mime = m
                    break
                }
            }
            if (trackIndex < 0 || format == null) return null
            extractor.selectTrack(trackIndex)

            val durationUs =
                if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) else 0L
            val windowUs = 20_000_000L
            val startUs = if (durationUs > windowUs * 2) (durationUs * 0.3).toLong() else 0L
            if (startUs > 0) extractor.seekTo(startUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)

            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var isFloat = false
            val deadline = System.currentTimeMillis() + 15_000

            val blockSize = 8192
            var blockSum = 0.0
            var blockCount = 0
            var powerSum = 0.0
            var validBlocks = 0
            val silence = Math.pow(10.0, -50.0 / 10.0)

            fun addSample(s: Double) {
                blockSum += s * s
                blockCount++
                if (blockCount >= blockSize) {
                    val power = blockSum / blockCount
                    if (power > silence) {
                        powerSum += power
                        validBlocks++
                    }
                    blockSum = 0.0
                    blockCount = 0
                }
            }

            while (!outputDone && System.currentTimeMillis() < deadline) {
                if (!inputDone) {
                    val inIndex = codec.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val buf = codec.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(buf, 0)
                        val time = extractor.sampleTime
                        if (size < 0 || time < 0 || time - startUs > windowUs) {
                            codec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(inIndex, 0, size, time, 0)
                            extractor.advance()
                        }
                    }
                }

                val outIndex = codec.dequeueOutputBuffer(info, 10_000)
                if (outIndex >= 0) {
                    val out = codec.getOutputBuffer(outIndex)
                    if (out != null && info.size > 0) {
                        out.position(info.offset)
                        out.limit(info.offset + info.size)
                        val data = out.slice().order(ByteOrder.nativeOrder())
                        if (isFloat) {
                            val fb = data.asFloatBuffer()
                            while (fb.hasRemaining()) addSample(fb.get().toDouble())
                        } else {
                            val sb = data.asShortBuffer()
                            while (sb.hasRemaining()) addSample(sb.get() / 32768.0)
                        }
                    }
                    codec.releaseOutputBuffer(outIndex, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                } else if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val of = codec.outputFormat
                    // 4 = ENCODING_PCM_FLOAT (clé "pcm-encoding", Android 7+)
                    isFloat = of.containsKey("pcm-encoding") && of.getInteger("pcm-encoding") == 4
                }
            }

            if (validBlocks == 0) return null
            return 10.0 * log10(powerSum / validBlocks)
        } finally {
            try { codec?.stop() } catch (_: Throwable) {}
            try { codec?.release() } catch (_: Throwable) {}
            extractor.release()
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
