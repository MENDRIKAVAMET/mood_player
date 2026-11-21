package com.example.mood_player

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Crée une vidéo MP4 (H.264 + AAC) à partir d'une suite d'images (cartes
 * karaoké) et d'un extrait audio, sans ffmpeg : MediaCodec + MediaMuxer.
 *
 * Tout est encodé en mémoire (10 s => quelques Mo) puis écrit d'un coup,
 * car le muxer exige que les deux pistes soient ajoutées avant de démarrer.
 */
class ExcerptEncoder(private val context: Context) {

    private class Sample(val data: ByteArray, val ptsUs: Long, val flags: Int)

    private class Encoded {
        var format: MediaFormat? = null
        val samples = ArrayList<Sample>()
    }

    fun create(
        uri: String?,
        path: String?,
        imagePaths: List<String>,
        fps: Int,
        startMs: Long,
        durationMs: Long,
        outputPath: String
    ) {
        require(imagePaths.isNotEmpty()) { "aucune image" }
        val deadline = System.currentTimeMillis() + 140_000

        val video = encodeVideo(imagePaths, fps, deadline)
        val audio = encodeAudio(uri, path, startMs * 1000, durationMs * 1000, deadline)

        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        try {
            val vTrack = muxer.addTrack(video.format ?: error("format vidéo manquant"))
            val aTrack = muxer.addTrack(audio.format ?: error("format audio manquant"))
            muxer.start()

            val all = ArrayList<Pair<Int, Sample>>(video.samples.size + audio.samples.size)
            video.samples.forEach { all.add(vTrack to it) }
            audio.samples.forEach { all.add(aTrack to it) }
            all.sortBy { it.second.ptsUs }

            val info = MediaCodec.BufferInfo()
            for ((track, s) in all) {
                info.set(0, s.data.size, s.ptsUs, s.flags)
                muxer.writeSampleData(track, ByteBuffer.wrap(s.data), info)
            }
        } finally {
            try { muxer.stop() } catch (_: Throwable) {}
            try { muxer.release() } catch (_: Throwable) {}
        }
    }

    // ------------------------------------------------------------------
    // Vidéo
    // ------------------------------------------------------------------

    private class Yuv(val w: Int, val h: Int) {
        val y = ByteArray(w * h)
        val u = ByteArray((w / 2) * (h / 2))
        val v = ByteArray((w / 2) * (h / 2))
    }

    private fun bitmapToYuv(bmp: Bitmap, w: Int, h: Int): Yuv {
        val yuv = Yuv(w, h)
        val px = IntArray(bmp.width * bmp.height)
        bmp.getPixels(px, 0, bmp.width, 0, 0, bmp.width, bmp.height)
        val stride = bmp.width
        for (j in 0 until h) {
            for (i in 0 until w) {
                val c = px[j * stride + i]
                val r = (c shr 16) and 0xFF
                val g = (c shr 8) and 0xFF
                val b = c and 0xFF
                yuv.y[j * w + i] = (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).toByte()
            }
        }
        val cw = w / 2
        for (j in 0 until h / 2) {
            for (i in 0 until cw) {
                var r = 0; var g = 0; var b = 0
                for (dj in 0..1) for (di in 0..1) {
                    val c = px[(2 * j + dj) * stride + 2 * i + di]
                    r += (c shr 16) and 0xFF
                    g += (c shr 8) and 0xFF
                    b += c and 0xFF
                }
                r /= 4; g /= 4; b /= 4
                val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                val v = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                yuv.u[j * cw + i] = u.coerceIn(0, 255).toByte()
                yuv.v[j * cw + i] = v.coerceIn(0, 255).toByte()
            }
        }
        return yuv
    }

    private fun copyPlane(
        plane: android.media.Image.Plane, src: ByteArray, w: Int, h: Int
    ) {
        val buf = plane.buffer
        val rowStride = plane.rowStride
        val pixelStride = plane.pixelStride
        for (row in 0 until h) {
            if (pixelStride == 1) {
                buf.position(row * rowStride)
                buf.put(src, row * w, w)
            } else {
                val base = row * rowStride
                for (col in 0 until w) buf.put(base + col * pixelStride, src[row * w + col])
            }
        }
    }

    private fun encodeVideo(imagePaths: List<String>, fps: Int, deadline: Long): Encoded {
        val first = BitmapFactory.decodeFile(imagePaths[0]) ?: error("image illisible")
        val w = first.width and 1.inv()
        val h = first.height and 1.inv()
        first.recycle()

        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, w, h).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            setInteger(MediaFormat.KEY_BIT_RATE, 3_500_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        val out = Encoded()
        try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            val info = MediaCodec.BufferInfo()
            var done = false

            fun drain() {
                while (true) {
                    val idx = codec.dequeueOutputBuffer(info, 0)
                    when {
                        idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> out.format = codec.outputFormat
                        idx >= 0 -> {
                            val buf = codec.getOutputBuffer(idx)
                            if (buf != null && info.size > 0 &&
                                info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                                val bytes = ByteArray(info.size)
                                buf.position(info.offset)
                                buf.limit(info.offset + info.size)
                                buf.get(bytes)
                                out.samples.add(Sample(bytes, info.presentationTimeUs, info.flags))
                            }
                            codec.releaseOutputBuffer(idx, false)
                            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) done = true
                        }
                        else -> return
                    }
                }
            }

            var cachePath: String? = null
            var cache: Yuv? = null
            for ((i, p) in imagePaths.withIndex()) {
                if (System.currentTimeMillis() > deadline) error("délai dépassé")
                if (p != cachePath) {
                    val bmp = BitmapFactory.decodeFile(p) ?: error("image illisible : $p")
                    cache = bitmapToYuv(bmp, w, h)
                    bmp.recycle()
                    cachePath = p
                }
                val yuv = cache!!
                var idx: Int
                while (true) {
                    idx = codec.dequeueInputBuffer(10_000)
                    if (idx >= 0) break
                    drain()
                }
                val image = codec.getInputImage(idx) ?: error("entrée vidéo indisponible")
                copyPlane(image.planes[0], yuv.y, w, h)
                copyPlane(image.planes[1], yuv.u, w / 2, h / 2)
                copyPlane(image.planes[2], yuv.v, w / 2, h / 2)
                image.close()
                val pts = i * 1_000_000L / fps
                codec.queueInputBuffer(idx, 0, w * h * 3 / 2, pts, 0)
                drain()
            }

            while (true) {
                val idx = codec.dequeueInputBuffer(10_000)
                if (idx >= 0) {
                    codec.queueInputBuffer(idx, 0, 0, imagePaths.size * 1_000_000L / fps,
                        MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    break
                }
                drain()
            }
            while (!done) {
                if (System.currentTimeMillis() > deadline) error("délai dépassé")
                drain()
                if (!done) Thread.sleep(5)
            }
        } finally {
            try { codec.stop() } catch (_: Throwable) {}
            codec.release()
        }
        return out
    }

    // ------------------------------------------------------------------
    // Audio : décodage -> PCM -> AAC
    // ------------------------------------------------------------------

    private fun encodeAudio(
        uri: String?, path: String?, startUs: Long, durationUs: Long, deadline: Long
    ): Encoded {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        var encoder: MediaCodec? = null
        val out = Encoded()
        try {
            if (uri != null) extractor.setDataSource(context, Uri.parse(uri), null)
            else if (path != null) extractor.setDataSource(path)
            else error("source audio introuvable")

            var trackIndex = -1
            var inFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                if ((f.getString(MediaFormat.KEY_MIME) ?: "").startsWith("audio/")) {
                    trackIndex = i; inFormat = f; break
                }
            }
            if (trackIndex < 0 || inFormat == null) error("aucune piste audio")
            extractor.selectTrack(trackIndex)
            if (startUs > 0) extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

            decoder = MediaCodec.createDecoderByType(inFormat.getString(MediaFormat.KEY_MIME)!!)
            decoder.configure(inFormat, null, null, 0)
            decoder.start()

            var rate = inFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var srcCh = inFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var isFloat = false
            val outCh = minOf(srcCh, 2)

            val enc = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            encoder = enc
            enc.configure(
                MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, rate, outCh).apply {
                    setInteger(MediaFormat.KEY_AAC_PROFILE,
                        MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                    setInteger(MediaFormat.KEY_BIT_RATE, 128_000)
                    setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 32768)
                }, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE
            )
            enc.start()

            val encInfo = MediaCodec.BufferInfo()
            var encDone = false
            var fedFrames = 0L
            val maxFrames = durationUs * rate / 1_000_000L

            fun drainEnc() {
                while (true) {
                    val idx = enc.dequeueOutputBuffer(encInfo, 0)
                    when {
                        idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> out.format = enc.outputFormat
                        idx >= 0 -> {
                            val buf = enc.getOutputBuffer(idx)
                            if (buf != null && encInfo.size > 0 &&
                                encInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                                val bytes = ByteArray(encInfo.size)
                                buf.position(encInfo.offset)
                                buf.limit(encInfo.offset + encInfo.size)
                                buf.get(bytes)
                                out.samples.add(Sample(bytes, encInfo.presentationTimeUs, encInfo.flags))
                            }
                            enc.releaseOutputBuffer(idx, false)
                            if (encInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) encDone = true
                        }
                        else -> return
                    }
                }
            }

            /** Envoie du PCM 16 bits (outCh canaux entrelacés) à l'encodeur AAC. */
            fun pushPcm(pcm: ByteArray) {
                var offset = 0
                while (offset < pcm.size) {
                    if (System.currentTimeMillis() > deadline) error("délai dépassé")
                    val idx = enc.dequeueInputBuffer(10_000)
                    if (idx < 0) { drainEnc(); continue }
                    val buf = enc.getInputBuffer(idx)!!
                    buf.clear()
                    val n = minOf(buf.remaining(), pcm.size - offset)
                    buf.put(pcm, offset, n)
                    val pts = fedFrames * 1_000_000L / rate
                    enc.queueInputBuffer(idx, 0, n, pts, 0)
                    fedFrames += n / (2 * outCh)
                    offset += n
                    drainEnc()
                }
            }

            val decInfo = MediaCodec.BufferInfo()
            var decInputDone = false
            var decOutputDone = false
            val endUs = startUs + durationUs

            while (!decOutputDone && fedFrames < maxFrames) {
                if (System.currentTimeMillis() > deadline) error("délai dépassé")
                if (!decInputDone) {
                    val idx = decoder.dequeueInputBuffer(10_000)
                    if (idx >= 0) {
                        val buf = decoder.getInputBuffer(idx)!!
                        val size = extractor.readSampleData(buf, 0)
                        val t = extractor.sampleTime
                        if (size < 0 || t < 0 || t > endUs + 500_000) {
                            decoder.queueInputBuffer(idx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            decInputDone = true
                        } else {
                            decoder.queueInputBuffer(idx, 0, size, t, 0)
                            extractor.advance()
                        }
                    }
                }
                val oi = decoder.dequeueOutputBuffer(decInfo, 10_000)
                if (oi == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val of = decoder.outputFormat
                    isFloat = of.containsKey("pcm-encoding") && of.getInteger("pcm-encoding") == 4
                    if (of.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) srcCh = of.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    if (of.containsKey(MediaFormat.KEY_SAMPLE_RATE) &&
                        of.getInteger(MediaFormat.KEY_SAMPLE_RATE) != rate) {
                        error("fréquence audio variable non gérée")
                    }
                } else if (oi >= 0) {
                    val ob = decoder.getOutputBuffer(oi)
                    if (ob != null && decInfo.size > 0) {
                        ob.position(decInfo.offset)
                        ob.limit(decInfo.offset + decInfo.size)
                        val data = ob.slice().order(ByteOrder.nativeOrder())
                        val bytesPerSample = if (isFloat) 4 else 2
                        val frames = decInfo.size / (bytesPerSample * srcCh)
                        // Trames à ignorer au début (le décodeur repart d'avant startUs).
                        val skip = if (decInfo.presentationTimeUs < startUs)
                            minOf(frames.toLong(), (startUs - decInfo.presentationTimeUs) * rate / 1_000_000L).toInt()
                        else 0
                        val keep = minOf(frames - skip, (maxFrames - fedFrames).toInt())
                        if (keep > 0) {
                            val pcm = ByteArray(keep * outCh * 2)
                            val pb = ByteBuffer.wrap(pcm).order(ByteOrder.LITTLE_ENDIAN)
                            for (f in skip until skip + keep) {
                                for (c in 0 until outCh) {
                                    val pos = (f * srcCh + c) * bytesPerSample
                                    val s: Short = if (isFloat) {
                                        (data.getFloat(pos).coerceIn(-1f, 1f) * 32767f).toInt().toShort()
                                    } else data.getShort(pos)
                                    pb.putShort(s)
                                }
                            }
                            pushPcm(pcm)
                        }
                    }
                    decoder.releaseOutputBuffer(oi, false)
                    if (decInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) decOutputDone = true
                }
            }

            // Fin de flux pour l'encodeur AAC.
            while (true) {
                val idx = enc.dequeueInputBuffer(10_000)
                if (idx >= 0) {
                    enc.queueInputBuffer(idx, 0, 0, fedFrames * 1_000_000L / rate,
                        MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    break
                }
                drainEnc()
            }
            while (!encDone) {
                if (System.currentTimeMillis() > deadline) error("délai dépassé")
                drainEnc()
                if (!encDone) Thread.sleep(5)
            }
        } finally {
            try { decoder?.stop() } catch (_: Throwable) {}
            try { decoder?.release() } catch (_: Throwable) {}
            try { encoder?.stop() } catch (_: Throwable) {}
            try { encoder?.release() } catch (_: Throwable) {}
            extractor.release()
        }
        return out
    }
}
