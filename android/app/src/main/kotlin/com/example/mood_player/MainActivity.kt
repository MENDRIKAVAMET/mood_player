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
import android.os.Bundle
import android.widget.Toast
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.content.FileProvider
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
    private val updaterChannelName = "com.example.mood_player/updater"
    private val backupFolderChannelName = "com.example.mood_player/backup_folder"
    private val widgetChannelName = "com.example.mood_player/widget"

    // Renommage en attente de l'autorisation de l'utilisateur (Android 10+).
    private val requestWriteAccess = 4711
    private var pendingRename: RenameRequest? = null
    private var pendingRenameResult: MethodChannel.Result? = null

    // Sauvegarde automatique : dossier choisi par l'utilisateur (SAF). Le
    // fichier écrit là survit à la désinstallation de l'app.
    private val requestPickBackupFolder = 4712
    private var pendingPickResult: MethodChannel.Result? = null
    private val backupExecutor = Executors.newSingleThreadExecutor()

    // Analyse du volume (une seule à la fois, hors du thread principal).
    // Priorité « arrière-plan » : le décodage audio de l'analyse de volume ne
    // doit jamais voler du processeur au thread d'interface ni au rendu.
    private val analysisExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread {
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_BACKGROUND)
            runnable.run()
        }
    }

    // Encodage vidéo des extraits (lourd : hors du thread principal).
    private val videoExecutor = Executors.newSingleThreadExecutor()

    private data class RenameRequest(
        val uri: Uri,
        val displayName: String,
        val title: String,
        val artist: String
    )

    companion object {
        // Nombre d'instances d'Aura ouvertes dans ce processus (une seule autorisée).
        private var liveInstances = 0
    }

    // Vrai si cette instance est comptée (donc doit se décompter à sa fermeture).
    private var counted = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (liveInstances >= 1) {
            // Aura est déjà ouvert : on refuse la deuxième instance.
            Toast.makeText(this, "Aura est déjà ouvert", Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        liveInstances++
        counted = true
    }

    override fun onDestroy() {
        if (counted) {
            liveInstances--
            counted = false
        }
        super.onDestroy()
    }

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

        // Mise à jour de l'app : l'APK est téléchargé côté Dart, ici on
        // vérifie l'autorisation d'installer et on lance l'installateur.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updaterChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls()
                    )
                    // Architectures prises en charge par le téléphone, de la
                    // préférée à la moins bonne (ex. [arm64-v8a, armeabi-v7a,
                    // armeabi]) : sert à choisir le bon APK dans la release.
                    "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                    "openInstallSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")
                                )
                            )
                        }
                        result.success(null)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("ARGS", "Chemin manquant", null)
                        } else {
                            try {
                                val uri = FileProvider.getUriForFile(
                                    this, "$packageName.updater", File(path)
                                )
                                val intent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(uri, "application/vnd.android.package-archive")
                                    addFlags(
                                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                            Intent.FLAG_ACTIVITY_NEW_TASK
                                    )
                                }
                                startActivity(intent)
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("INSTALL", e.message ?: "Installation impossible", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Renommage d'un fichier audio via MediaStore : le système renomme
        // vraiment le fichier et garde le même identifiant (donc le même
        // uri de lecture).
        // Widget d'écran d'accueil : Flutter envoie le morceau en cours, le
        // mood, l'état de lecture et l'image du fantôme (PNG).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        try {
                            val prefs = getSharedPreferences(
                                AuraWidgetProvider.PREFS, android.content.Context.MODE_PRIVATE
                            )
                            val edit = prefs.edit()
                            val title = call.argument<String>("title")
                            if (title == null) edit.remove("title") else edit.putString("title", title)
                            edit.putString("artist", call.argument<String>("artist") ?: "")
                            edit.putString("mood", call.argument<String>("mood") ?: "")
                            edit.putBoolean("playing", call.argument<Boolean>("playing") ?: false)
                            call.argument<Number>("color")?.let { edit.putInt("color", it.toInt()) }
                            edit.apply()
                            call.argument<ByteArray>("ghost")?.let {
                                File(filesDir, AuraWidgetProvider.GHOST_FILE).writeBytes(it)
                            }
                            AuraWidgetProvider.refreshAll(applicationContext)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("WIDGET", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, backupFolderChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFolder" -> {
                        if (pendingPickResult != null) {
                            result.error("BUSY", "Sélection déjà en cours", null)
                        } else {
                            pendingPickResult = result
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                                addFlags(
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                                )
                            }
                            try {
                                startActivityForResult(intent, requestPickBackupFolder)
                            } catch (e: Exception) {
                                pendingPickResult = null
                                result.error("NO_PICKER", e.message, null)
                            }
                        }
                    }
                    "hasAccess" -> {
                        val tree = Uri.parse(call.argument<String>("tree") ?: "")
                        result.success(contentResolver.persistedUriPermissions.any {
                            it.uri == tree && it.isReadPermission && it.isWritePermission
                        })
                    }
                    "write" -> {
                        val tree = Uri.parse(call.argument<String>("tree") ?: "")
                        val name = call.argument<String>("name") ?: ""
                        val content = call.argument<String>("content") ?: ""
                        val prevName = call.argument<String>("prevName")
                        backupExecutor.execute {
                            try {
                                writeBackupDoc(tree, name, content, prevName)
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("WRITE", e.message, null) }
                            }
                        }
                    }
                    "read" -> {
                        val tree = Uri.parse(call.argument<String>("tree") ?: "")
                        val name = call.argument<String>("name") ?: ""
                        backupExecutor.execute {
                            try {
                                val doc = findBackupChild(tree, name)
                                val text = if (doc == null) null else readBackupDoc(doc)
                                runOnUiThread { result.success(text) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("READ", e.message, null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

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
                    "createExcerptVideo" -> {
                        val uri = call.argument<String>("uri")
                        val path = call.argument<String>("path")
                        val images = call.argument<List<String>>("imagePaths")
                        val fps = call.argument<Int>("fps") ?: 8
                        val startMs = (call.argument<Number>("startMs") ?: 0).toLong()
                        val durationMs = (call.argument<Number>("durationMs") ?: 10000).toLong()
                        val output = call.argument<String>("outputPath")
                        if (images.isNullOrEmpty() || output == null) {
                            result.error("ARGS", "arguments invalides", null)
                        } else {
                            videoExecutor.execute {
                                try {
                                    ExcerptEncoder(applicationContext)
                                        .create(uri, path, images, fps, startMs, durationMs, output)
                                    runOnUiThread { result.success(output) }
                                } catch (e: Throwable) {
                                    try { File(output).delete() } catch (_: Throwable) {}
                                    runOnUiThread {
                                        result.error("VIDEO", e.message ?: e.toString(), null)
                                    }
                                }
                            }
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

    // ── Sauvegarde automatique : fichiers dans un dossier SAF ──────────

    private fun backupTreeRoot(tree: Uri): Uri =
        android.provider.DocumentsContract.buildDocumentUriUsingTree(
            tree, android.provider.DocumentsContract.getTreeDocumentId(tree)
        )

    private fun findBackupChild(tree: Uri, name: String): Uri? {
        val children = android.provider.DocumentsContract.buildChildDocumentsUriUsingTree(
            tree, android.provider.DocumentsContract.getTreeDocumentId(tree)
        )
        contentResolver.query(
            children,
            arrayOf(
                android.provider.DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                android.provider.DocumentsContract.Document.COLUMN_DISPLAY_NAME
            ),
            null, null, null
        )?.use { c ->
            while (c.moveToNext()) {
                if (c.getString(1) == name) {
                    return android.provider.DocumentsContract.buildDocumentUriUsingTree(
                        tree, c.getString(0)
                    )
                }
            }
        }
        return null
    }

    private fun readBackupDoc(doc: Uri): String? =
        contentResolver.openInputStream(doc)?.use { it.readBytes().toString(Charsets.UTF_8) }

    /** Écrit [content] dans [name] (créé si besoin). L'ancienne version est
     *  d'abord copiée dans [prevName] : une sauvegarde ratée n'écrase jamais
     *  la dernière bonne. */
    private fun writeBackupDoc(tree: Uri, name: String, content: String, prevName: String?) {
        val existing = findBackupChild(tree, name)
        if (existing != null && prevName != null) {
            val old = readBackupDoc(existing)
            if (!old.isNullOrEmpty()) {
                val prev = findBackupChild(tree, prevName)
                    ?: android.provider.DocumentsContract.createDocument(
                        contentResolver, backupTreeRoot(tree), "application/json", prevName
                    )
                if (prev != null) {
                    contentResolver.openOutputStream(prev, "wt")?.use {
                        it.write(old.toByteArray(Charsets.UTF_8))
                    }
                }
            }
        }
        val target = existing
            ?: android.provider.DocumentsContract.createDocument(
                contentResolver, backupTreeRoot(tree), "application/json", name
            )
            ?: throw IllegalStateException("Création du fichier impossible")
        val out = contentResolver.openOutputStream(target, "wt")
            ?: throw IllegalStateException("Écriture impossible")
        out.use { it.write(content.toByteArray(Charsets.UTF_8)) }
    }

    private fun backupFolderName(tree: Uri): String? {
        contentResolver.query(
            backupTreeRoot(tree),
            arrayOf(android.provider.DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null
        )?.use { c -> if (c.moveToFirst()) return c.getString(0) }
        return null
    }

    @SuppressLint("NewApi")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == requestPickBackupFolder) {
            val result = pendingPickResult
            pendingPickResult = null
            if (result == null) return
            val uri = data?.data
            if (resultCode == Activity.RESULT_OK && uri != null) {
                try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                    result.success(
                        mapOf("uri" to uri.toString(), "name" to (backupFolderName(uri) ?: ""))
                    )
                } catch (e: Exception) {
                    result.error("PERMISSION", e.message, null)
                }
            } else {
                result.success(null)
            }
            return
        }
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
