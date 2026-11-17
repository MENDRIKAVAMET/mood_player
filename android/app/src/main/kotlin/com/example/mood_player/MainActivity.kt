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
import android.provider.Settings
import androidx.core.content.FileProvider
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Paint
import android.graphics.Rect
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaMuxer
import android.view.Surface
import java.nio.ByteBuffer
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

    // Renommage en attente de l'autorisation de l'utilisateur (Android 10+).
    private val requestWriteAccess = 4711
    private var pendingRename: RenameRequest? = null
    private var pendingRenameResult: MethodChannel.Result? = null

    // Analyse du volume (une seule à la fois, hors du thread principal).
    // Priorité « arrière-plan » : le décodage audio de l'analyse de volume ne
    // doit jamais voler du processeur au thread d'interface ni au rendu.
    private val analysisExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread {
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_BACKGROUND)
            runnable.run()
        }
    }

    // Création des vidéos d'extrait : executor dédié (priorité normale, pas
    // celle d'arrière-plan de analysisExecutor).
    private val excerptExecutor = Executors.newSingleThreadExecutor()

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

        // Mise à jour de l'app : l'APK est téléchargé côté Dart, ici on
        // vérifie l'autorisation d'installer et on lance l'installateur.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updaterChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls()
                    )
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
                        val imagePath = call.argument<String>("imagePath")
                        val outputPath = call.argument<String>("outputPath")
                        val startMs = call.argument<Number>("startMs")?.toLong()
                        val durationMs = call.argument<Number>("durationMs")?.toLong()
                        if ((uri == null && path == null) || imagePath == null ||
                            outputPath == null || startMs == null || durationMs == null
                        ) {
                            result.error("ARGS", "Arguments manquants", null)
                        } else {
                            excerptExecutor.execute {
                                try {
                                    val out = createExcerptVideo(
                                        uri, path, imagePath, startMs, durationMs, outputPath
                                    )
                                    runOnUiThread { result.success(out) }
                                } catch (e: Throwable) {
                                    runOnUiThread {
                                        result.error(
                                            "EXCERPT",
                                            e.message ?: "Création de la vidéo impossible",
                                            null
                                        )
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


    // ---------------------------------------------------------------
    // Extrait vidéo (image fixe + audio) : MediaCodec + MediaMuxer
    // ---------------------------------------------------------------

    private class PcmResult(val pcm: ShortArray, val sampleRate: Int, val channels: Int)

    private class EncodedSample(val data: ByteArray, val timeUs: Long, val flags: Int)

    private class EncodedTrack(val format: MediaFormat, val samples: List<EncodedSample>)

    private val phaseLimitMs = 30_000L

    private fun createExcerptVideo(
        uri: String?,
        path: String?,
        imagePath: String,
        startMs: Long,
        durationMs: Long,
        outputPath: String
    ): String {
        if (durationMs <= 0) throw IllegalArgumentException("Durée d'extrait invalide")
        try {
            val pcm = decodeExcerptPcm(uri, path, startMs, durationMs)
            val audio = encodeAac(pcm)
            val frames = pcm.pcm.size / pcm.channels
            // Durée réelle de l'audio obtenu (peut être < durationMs en fin de morceau).
            val audioDurationUs = frames * 1_000_000L / pcm.sampleRate
            val video = encodeVideo(imagePath, audioDurationUs)
            muxTracks(outputPath, audio, video)
            return outputPath
        } catch (e: Throwable) {
            try { File(outputPath).delete() } catch (_: Throwable) {}
            throw e
        }
    }

    /** Décode [durationMs] d'audio à partir de [startMs] en PCM 16 bits entrelacé. */
    private fun decodeExcerptPcm(
        uri: String?,
        path: String?,
        startMs: Long,
        durationMs: Long
    ): PcmResult {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            if (uri != null) {
                extractor.setDataSource(applicationContext, Uri.parse(uri), null)
            } else if (path != null) {
                extractor.setDataSource(path)
            } else {
                throw IllegalArgumentException("Source audio manquante")
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
            if (trackIndex < 0 || format == null) throw IllegalStateException("Aucune piste audio")
            extractor.selectTrack(trackIndex)

            val startUs = startMs * 1000L
            val windowUs = durationMs * 1000L
            if (startUs > 0) extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

            var sampleRate =
                if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) format.getInteger(MediaFormat.KEY_SAMPLE_RATE) else 44100
            var channels =
                if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) else 2
            if (channels > 2) throw IllegalStateException("Audio à plus de 2 canaux non pris en charge")

            val decoder = MediaCodec.createDecoderByType(mime)
            codec = decoder
            decoder.configure(format, null, null, 0)
            decoder.start()

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var isFloat = false
            var pcmBuf: ShortArray? = null
            var filled = 0
            val deadline = System.currentTimeMillis() + phaseLimitMs

            while (!outputDone) {
                if (System.currentTimeMillis() > deadline) {
                    throw IllegalStateException("Décodage de l'audio trop long")
                }
                if (!inputDone) {
                    val inIndex = decoder.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val buf = decoder.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(buf, 0)
                        val time = extractor.sampleTime
                        if (size < 0 || time < 0 || time > startUs + windowUs + 1_000_000L) {
                            decoder.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(inIndex, 0, size, time, 0)
                            extractor.advance()
                        }
                    }
                }

                val outIndex = decoder.dequeueOutputBuffer(info, 10_000)
                if (outIndex >= 0) {
                    val out = decoder.getOutputBuffer(outIndex)
                    if (out != null && info.size > 0) {
                        out.position(info.offset)
                        out.limit(info.offset + info.size)
                        val data = out.slice().order(ByteOrder.nativeOrder())
                        val samples: ShortArray
                        if (isFloat) {
                            val fb = data.asFloatBuffer()
                            samples = ShortArray(fb.remaining())
                            for (i in samples.indices) {
                                val v = fb.get() * 32767f
                                samples[i] = v.coerceIn(-32768f, 32767f).toInt().toShort()
                            }
                        } else {
                            val sb = data.asShortBuffer()
                            samples = ShortArray(sb.remaining())
                            sb.get(samples)
                        }
                        val frames = samples.size / channels
                        // On jette les trames situées avant startUs (niveau trame).
                        var skip = 0
                        if (info.presentationTimeUs < startUs) {
                            skip = (((startUs - info.presentationTimeUs) * sampleRate + 999_999L) / 1_000_000L)
                                .toInt().coerceIn(0, frames)
                        }
                        val dst = pcmBuf ?: ShortArray(((windowUs * sampleRate) / 1_000_000L).toInt() * channels)
                            .also { pcmBuf = it }
                        val n = minOf((frames - skip) * channels, dst.size - filled)
                        if (n > 0) {
                            System.arraycopy(samples, skip * channels, dst, filled, n)
                            filled += n
                        }
                        if (filled >= dst.size) outputDone = true
                    }
                    decoder.releaseOutputBuffer(outIndex, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                } else if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val of = decoder.outputFormat
                    if (of.containsKey(MediaFormat.KEY_SAMPLE_RATE)) sampleRate = of.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    if (of.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) channels = of.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    if (channels > 2) throw IllegalStateException("Audio à plus de 2 canaux non pris en charge")
                    if (of.containsKey("pcm-encoding")) {
                        val enc = of.getInteger("pcm-encoding")
                        // 2 = PCM 16 bits, 4 = PCM float
                        if (enc != 2 && enc != 4) throw IllegalStateException("Format PCM non pris en charge")
                        isFloat = enc == 4
                    } else {
                        isFloat = false
                    }
                }
            }

            val buf = pcmBuf
            val usable = filled - (filled % channels)
            if (buf == null || usable <= 0) {
                throw IllegalStateException("Aucun échantillon audio dans l'extrait demandé")
            }
            return PcmResult(buf.copyOf(usable), sampleRate, channels)
        } finally {
            try { codec?.stop() } catch (_: Throwable) {}
            try { codec?.release() } catch (_: Throwable) {}
            try { extractor.release() } catch (_: Throwable) {}
        }
    }

    /** Encode le PCM en AAC-LC 128 kbps ; garde les échantillons en mémoire. */
    private fun encodeAac(src: PcmResult): EncodedTrack {
        val format = MediaFormat.createAudioFormat(
            MediaFormat.MIMETYPE_AUDIO_AAC, src.sampleRate, src.channels
        ).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, 128_000)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
        }
        var codec: MediaCodec? = null
        try {
            val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            codec = encoder
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()

            val info = MediaCodec.BufferInfo()
            val samples = ArrayList<EncodedSample>()
            var outFormat: MediaFormat? = null
            var inputDone = false
            var outputDone = false
            var offsetShorts = 0
            val frameShorts = src.channels
            val deadline = System.currentTimeMillis() + phaseLimitMs

            while (!outputDone) {
                if (System.currentTimeMillis() > deadline) {
                    throw IllegalStateException("Encodage audio trop long")
                }
                if (!inputDone) {
                    val inIndex = encoder.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val ib = encoder.getInputBuffer(inIndex)!!
                        ib.clear()
                        val remaining = src.pcm.size - offsetShorts
                        if (remaining <= 0) {
                            encoder.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            var chunk = minOf(remaining, ib.capacity() / 2)
                            chunk -= chunk % frameShorts
                            if (chunk <= 0) throw IllegalStateException("Tampon d'entrée AAC trop petit")
                            ib.order(ByteOrder.nativeOrder()).asShortBuffer().put(src.pcm, offsetShorts, chunk)
                            val ptsUs = (offsetShorts / frameShorts) * 1_000_000L / src.sampleRate
                            encoder.queueInputBuffer(inIndex, 0, chunk * 2, ptsUs, 0)
                            offsetShorts += chunk
                        }
                    }
                }

                val outIndex = encoder.dequeueOutputBuffer(info, 10_000)
                if (outIndex >= 0) {
                    val ob = encoder.getOutputBuffer(outIndex)
                    val isConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    if (ob != null && info.size > 0 && !isConfig) {
                        ob.position(info.offset)
                        ob.limit(info.offset + info.size)
                        val bytes = ByteArray(info.size)
                        ob.get(bytes)
                        samples.add(
                            EncodedSample(
                                bytes,
                                info.presentationTimeUs,
                                info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM.inv()
                            )
                        )
                    }
                    encoder.releaseOutputBuffer(outIndex, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                } else if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    outFormat = encoder.outputFormat
                }
            }

            val fmt = outFormat ?: encoder.outputFormat
            if (samples.isEmpty()) throw IllegalStateException("Encodage audio vide")
            return EncodedTrack(fmt, samples)
        } finally {
            try { codec?.stop() } catch (_: Throwable) {}
            try { codec?.release() } catch (_: Throwable) {}
        }
    }

    /** Encode l'image fixe en H.264 (~10 fps) pendant [durationUs]. */
    private fun encodeVideo(imagePath: String, durationUs: Long): EncodedTrack {
        val fps = 10
        val source = BitmapFactory.decodeFile(imagePath)
            ?: throw IllegalStateException("Image illisible")
        var codec: MediaCodec? = null
        var surface: Surface? = null
        try {
            // H.264 exige des dimensions paires.
            val w = (source.width / 2) * 2
            val h = (source.height / 2) * 2
            if (w < 2 || h < 2) throw IllegalStateException("Image trop petite")
            val dst = Rect(0, 0, w, h)
            val paint = Paint(Paint.FILTER_BITMAP_FLAG)

            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, w, h).apply {
                setInteger(
                    MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
                )
                setInteger(MediaFormat.KEY_BIT_RATE, 2_000_000)
                setInteger(MediaFormat.KEY_FRAME_RATE, fps)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            }
            val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            codec = encoder
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            val inSurface = encoder.createInputSurface()
            surface = inSurface
            encoder.start()

            val info = MediaCodec.BufferInfo()
            val samples = ArrayList<EncodedSample>()
            var outFormat: MediaFormat? = null
            var index = 0L
            val deadline = System.currentTimeMillis() + phaseLimitMs

            // Vide la sortie ; renvoie true quand EOS est atteint.
            fun drain(untilEos: Boolean): Boolean {
                while (true) {
                    if (System.currentTimeMillis() > deadline) {
                        throw IllegalStateException("Encodage vidéo trop long")
                    }
                    val outIndex = encoder.dequeueOutputBuffer(info, 10_000)
                    if (outIndex == MediaCodec.INFO_TRY_AGAIN_LATER) {
                        if (!untilEos) return false
                    } else if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        outFormat = encoder.outputFormat
                    } else if (outIndex >= 0) {
                        val ob = encoder.getOutputBuffer(outIndex)
                        val isConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                        if (ob != null && info.size > 0 && !isConfig) {
                            ob.position(info.offset)
                            ob.limit(info.offset + info.size)
                            val bytes = ByteArray(info.size)
                            ob.get(bytes)
                            // Les timestamps de la surface sont ceux de l'horloge
                            // système : on les réécrit en index × 1e6 / fps.
                            samples.add(
                                EncodedSample(
                                    bytes,
                                    index * 1_000_000L / fps,
                                    info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM.inv()
                                )
                            )
                            index++
                        }
                        encoder.releaseOutputBuffer(outIndex, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return true
                    }
                }
            }

            val frameCount = Math.round(durationUs * fps / 1_000_000.0).toInt().coerceAtLeast(1)
            for (i in 0 until frameCount) {
                if (System.currentTimeMillis() > deadline) {
                    throw IllegalStateException("Encodage vidéo trop long")
                }
                val canvas = inSurface.lockCanvas(null)
                try {
                    canvas.drawBitmap(source, null, dst, paint)
                } finally {
                    inSurface.unlockCanvasAndPost(canvas)
                }
                // Vider la sortie entre chaque frame évite de bloquer l'encodeur.
                drain(false)
            }
            encoder.signalEndOfInputStream()
            drain(true)

            val fmt = outFormat ?: encoder.outputFormat
            if (samples.isEmpty()) throw IllegalStateException("Encodage vidéo vide")
            return EncodedTrack(fmt, samples)
        } finally {
            try { codec?.stop() } catch (_: Throwable) {}
            try { codec?.release() } catch (_: Throwable) {}
            try { surface?.release() } catch (_: Throwable) {}
            try { source.recycle() } catch (_: Throwable) {}
        }
    }

    /** Assemble les deux pistes dans un MP4, échantillons triés par timestamp. */
    private fun muxTracks(outputPath: String, audio: EncodedTrack, video: EncodedTrack) {
        val outFile = File(outputPath)
        outFile.parentFile?.mkdirs()
        if (outFile.exists()) outFile.delete()
        var muxer: MediaMuxer? = null
        var started = false
        try {
            val m = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = m
            val videoIdx = m.addTrack(video.format)
            val audioIdx = m.addTrack(audio.format)
            m.start()
            started = true

            val info = MediaCodec.BufferInfo()
            var vi = 0
            var ai = 0
            while (vi < video.samples.size || ai < audio.samples.size) {
                val takeVideo = ai >= audio.samples.size ||
                    (vi < video.samples.size && video.samples[vi].timeUs <= audio.samples[ai].timeUs)
                val s = if (takeVideo) video.samples[vi++] else audio.samples[ai++]
                info.set(0, s.data.size, s.timeUs, s.flags)
                m.writeSampleData(if (takeVideo) videoIdx else audioIdx, ByteBuffer.wrap(s.data), info)
            }
            m.stop()
            started = false
        } finally {
            try { if (started) muxer?.stop() } catch (_: Throwable) {}
            try { muxer?.release() } catch (_: Throwable) {}
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
