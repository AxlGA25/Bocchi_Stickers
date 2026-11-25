package com.axel.sticker_maker

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.min

class SoundStickerEncoder(private val context: Context) {

    private data class EncodedAudioSample(
        val data: ByteArray,
        val presentationTimeUs: Long,
        val flags: Int
    )

    private data class AudioTranscodeResult(
        val format: MediaFormat,
        val samples: List<EncodedAudioSample>,
        val durationUs: Long
    )

    fun createSoundStickerMp4(
        mediaPath: String,
        isVideo: Boolean,
        audioPath: String?,
        startMs: Int = 0,
        maxDurationMs: Int = 5000,
        cropAlign: String = "center"
    ): String {
        val requestedDurationUs = maxDurationMs.coerceIn(1000, 5000).toLong() * 1000L
        val videoStartUs = startMs.coerceAtLeast(0).toLong() * 1000L

        // Determinar de dónde sale el audio (archivo externo o audio original del video)
        val hasCustomAudio = !audioPath.isNullOrEmpty()
        val effectiveAudioPath = when {
            hasCustomAudio -> audioPath
            isVideo -> mediaPath
            else -> null
        }
        val audioStartUs = if (hasCustomAudio) 0L else videoStartUs

        // Transcodificar audio a AAC (si existe pista de audio)
        val audioResult = if (effectiveAudioPath != null) {
            transcodeAudioToAac(effectiveAudioPath, audioStartUs, requestedDurationUs)
        } else {
            null
        }

        // Calcular duración final del clip
        val finalDurationUs = if (isVideo) {
            val videoTotalUs = getVideoDurationUs(mediaPath)
            val remainingUs = (videoTotalUs - videoStartUs).coerceAtLeast(1_000_000L)
            min(requestedDurationUs, remainingUs).coerceIn(1_000_000L, 5_000_000L)
        } else {
            val audioDur = audioResult?.durationUs ?: requestedDurationUs
            min(requestedDurationUs, audioDur).coerceIn(1_000_000L, 5_000_000L)
        }

        val tempFile = File(
            context.cacheDir,
            "bocchi_studio_" + System.currentTimeMillis().toString() + ".mp4"
        )

        if (isVideo) {
            encodeVideoClipAndMux(
                videoPath = mediaPath,
                startUs = videoStartUs,
                durationUs = finalDurationUs,
                cropAlign = cropAlign,
                audio = audioResult,
                outputFile = tempFile
            )
        } else {
            val rawBitmap = BitmapFactory.decodeFile(mediaPath)
                ?: throw IllegalArgumentException("No se pudo abrir la imagen seleccionada.")
            val squareBitmap = prepareBitmap(rawBitmap, 512, cropAlign)
            if (squareBitmap != rawBitmap) rawBitmap.recycle()

            try {
                encodeStaticImageAndMux(
                    bitmap = squareBitmap,
                    durationUs = finalDurationUs,
                    audio = audioResult,
                    outputFile = tempFile
                )
            } finally {
                squareBitmap.recycle()
            }
        }

        return saveVideoToGallery(tempFile)
    }

    private fun getVideoDurationUs(videoPath: String): Long {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(videoPath)
            val durMs = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_DURATION
            )?.toLongOrNull() ?: 5000L
            durMs * 1000L
        } catch (_: Exception) {
            5_000_000L
        } finally {
            retriever.release()
        }
    }

    /// Ajusta la imagen o fotograma a 512x512 según el encuadre: top, center, bottom o fit
    private fun prepareBitmap(src: Bitmap, size: Int, align: String): Bitmap {
        val output = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        canvas.drawColor(Color.BLACK)

        val scale = if (align == "fit") {
            min(size.toFloat() / src.width, size.toFloat() / src.height)
        } else {
            max(size.toFloat() / src.width, size.toFloat() / src.height)
        }

        val drawW = src.width * scale
        val drawH = src.height * scale
        val left = (size - drawW) / 2f
        val top = when (align) {
            "top" -> 0f
            "bottom" -> size - drawH
            else -> (size - drawH) / 2f
        }

        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        canvas.drawBitmap(src, null, RectF(left, top, left + drawW, top + drawH), paint)
        return output
    }

    private fun transcodeAudioToAac(
        audioPath: String,
        startUs: Long,
        maxDurationUs: Long
    ): AudioTranscodeResult? {
        val extractor = MediaExtractor()
        extractor.setDataSource(audioPath)

        var audioTrackIdx = -1
        var inputFormat: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val fmt = extractor.getTrackFormat(i)
            val mime = fmt.getString(MediaFormat.KEY_MIME) ?: ""
            if (mime.startsWith("audio/")) {
                audioTrackIdx = i
                inputFormat = fmt
                break
            }
        }

        // Si el video no trae pista de audio, devolvemos null sin fallar
        if (audioTrackIdx == -1 || inputFormat == null) {
            extractor.release()
            return null
        }

        extractor.selectTrack(audioTrackIdx)
        if (startUs > 0L) {
            extractor.seekTo(startUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
        }

        val endLimitUs = startUs + maxDurationUs
        val inputMime = inputFormat.getString(MediaFormat.KEY_MIME)!!
        val sampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channelCount = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

        val decoder = MediaCodec.createDecoderByType(inputMime)
        decoder.configure(inputFormat, null, null, 0)
        decoder.start()

        val encFormat = MediaFormat.createAudioFormat(
            MediaFormat.MIMETYPE_AUDIO_AAC,
            sampleRate,
            channelCount
        ).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, 128_000)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
        }

        val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        encoder.configure(encFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        encoder.start()

        val samples = ArrayList<EncodedAudioSample>()
        var outputAudioFormat: MediaFormat? = null
        var lastPtsUs = 0L

        val decInfo = MediaCodec.BufferInfo()
        val encInfo = MediaCodec.BufferInfo()

        var extractorDone = false
        var decoderDone = false
        var encoderDone = false
        var totalPcmFrames = 0L
        val bytesPerFrame = channelCount * 2

        fun drainEncoder() {
            while (true) {
                val outIdx = encoder.dequeueOutputBuffer(encInfo, 2_000)
                if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    break
                } else if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    outputAudioFormat = encoder.outputFormat
                } else if (outIdx >= 0) {
                    val outBuf = encoder.getOutputBuffer(outIdx)
                    if (outBuf != null && encInfo.size > 0 &&
                        (encInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0
                    ) {
                        outBuf.position(encInfo.offset)
                        outBuf.limit(encInfo.offset + encInfo.size)
                        val chunk = ByteArray(encInfo.size)
                        outBuf.get(chunk)
                        val pts = if (encInfo.presentationTimeUs >= lastPtsUs) {
                            encInfo.presentationTimeUs
                        } else {
                            lastPtsUs
                        }
                        lastPtsUs = pts
                        samples.add(EncodedAudioSample(chunk, pts, encInfo.flags))
                    }
                    encoder.releaseOutputBuffer(outIdx, false)
                    if ((encInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        encoderDone = true
                        break
                    }
                }
            }
        }

        try {
            while (!encoderDone) {
                if (!extractorDone) {
                    val inIdx = decoder.dequeueInputBuffer(5_000)
                    if (inIdx >= 0) {
                        val inBuf = decoder.getInputBuffer(inIdx)!!
                        val sampleSize = extractor.readSampleData(inBuf, 0)
                        val sampleTime = extractor.sampleTime
                        if (sampleSize < 0 || sampleTime > endLimitUs) {
                            decoder.queueInputBuffer(
                                inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            extractorDone = true
                        } else {
                            val relTime = (sampleTime - startUs).coerceAtLeast(0L)
                            decoder.queueInputBuffer(inIdx, 0, sampleSize, relTime, 0)
                            extractor.advance()
                        }
                    }
                }

                if (!decoderDone) {
                    val outIdx = decoder.dequeueOutputBuffer(decInfo, 5_000)
                    if (outIdx >= 0) {
                        val pcmBuf = decoder.getOutputBuffer(outIdx)
                        if (pcmBuf != null && decInfo.size > 0) {
                            pcmBuf.position(decInfo.offset)
                            pcmBuf.limit(decInfo.offset + decInfo.size)
                            val pcmBytes = ByteArray(decInfo.size)
                            pcmBuf.get(pcmBytes)

                            var offset = 0
                            while (offset < pcmBytes.size) {
                                val encInIdx = encoder.dequeueInputBuffer(10_000)
                                if (encInIdx >= 0) {
                                    val encInBuf = encoder.getInputBuffer(encInIdx)!!
                                    encInBuf.clear()
                                    val toCopy = min(encInBuf.remaining(), pcmBytes.size - offset)
                                    encInBuf.put(pcmBytes, offset, toCopy)
                                    val ptsUs = (totalPcmFrames * 1_000_000L) / sampleRate
                                    totalPcmFrames += (toCopy / bytesPerFrame)
                                    encoder.queueInputBuffer(encInIdx, 0, toCopy, ptsUs, 0)
                                    offset += toCopy
                                } else {
                                    drainEncoder()
                                }
                            }
                        }
                        decoder.releaseOutputBuffer(outIdx, false)

                        if ((decInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            decoderDone = true
                            val encInIdx = encoder.dequeueInputBuffer(10_000)
                            if (encInIdx >= 0) {
                                val ptsUs = (totalPcmFrames * 1_000_000L) / sampleRate
                                encoder.queueInputBuffer(
                                    encInIdx, 0, 0, ptsUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                )
                            }
                        }
                    }
                }

                drainEncoder()
            }
        } finally {
            decoder.stop()
            decoder.release()
            encoder.stop()
            encoder.release()
            extractor.release()
        }

        val finalFormat = outputAudioFormat ?: return null
        if (samples.isEmpty()) return null
        val computedDuration = ((totalPcmFrames * 1_000_000L) / sampleRate).coerceAtLeast(lastPtsUs)
        return AudioTranscodeResult(finalFormat, samples, computedDuration)
    }

    private fun encodeStaticImageAndMux(
        bitmap: Bitmap,
        durationUs: Long,
        audio: AudioTranscodeResult?,
        outputFile: File
    ) {
        val fps = 15
        val totalFrames = ((durationUs / 1_000_000.0) * fps).toInt().coerceAtLeast(15)
        runMuxLoop(
            fps = fps,
            totalFrames = totalFrames,
            durationUs = durationUs,
            audio = audio,
            outputFile = outputFile
        ) { _ -> bitmap }
    }

    private fun encodeVideoClipAndMux(
        videoPath: String,
        startUs: Long,
        durationUs: Long,
        cropAlign: String,
        audio: AudioTranscodeResult?,
        outputFile: File
    ) {
        val fps = 20
        val frameIntervalUs = 1_000_000L / fps
        val totalFrames = ((durationUs / 1_000_000.0) * fps).toInt().coerceIn(15, 100)

        val retriever = MediaMetadataRetriever()
        retriever.setDataSource(videoPath)
        var lastFrame: Bitmap? = null

        try {
            runMuxLoop(
                fps = fps,
                totalFrames = totalFrames,
                durationUs = durationUs,
                audio = audio,
                outputFile = outputFile
            ) { index ->
                val timeUs = startUs + (index * frameIntervalUs)
                val raw = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                    ?: retriever.getFrameAtTime(timeUs)
                if (raw != null) {
                    val prepared = prepareBitmap(raw, 512, cropAlign)
                    if (prepared != raw) raw.recycle()
                    lastFrame?.recycle()
                    lastFrame = prepared
                    prepared
                } else {
                    lastFrame
                }
            }
        } finally {
            lastFrame?.recycle()
            retriever.release()
        }
    }

    private fun runMuxLoop(
        fps: Int,
        totalFrames: Int,
        durationUs: Long,
        audio: AudioTranscodeResult?,
        outputFile: File,
        frameProvider: (Int) -> Bitmap?
    ) {
        val width = 512
        val height = 512
        val frameIntervalUs = 1_000_000L / fps

        val videoFormat = MediaFormat.createVideoFormat(
            MediaFormat.MIMETYPE_VIDEO_AVC,
            width,
            height
        ).apply {
            setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
            )
            setInteger(MediaFormat.KEY_BIT_RATE, 2_800_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }

        val videoEncoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        videoEncoder.configure(videoFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val inputSurface = videoEncoder.createInputSurface()
        videoEncoder.start()

        val muxer = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        val hasAudio = audio != null && audio.samples.isNotEmpty()
        val audioTrackIdx = if (hasAudio) muxer.addTrack(audio!!.format) else -1
        var videoTrackIdx = -1
        var muxerStarted = false
        var writtenVideoFrames = 0L

        val bufferInfo = MediaCodec.BufferInfo()

        fun drainVideo(endOfStream: Boolean) {
            if (endOfStream) {
                videoEncoder.signalEndOfInputStream()
            }
            while (true) {
                val outIdx = videoEncoder.dequeueOutputBuffer(bufferInfo, 10_000)
                if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    if (!endOfStream) break
                } else if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    videoTrackIdx = muxer.addTrack(videoEncoder.outputFormat)
                    muxer.start()
                    muxerStarted = true
                } else if (outIdx >= 0) {
                    val encodedData = videoEncoder.getOutputBuffer(outIdx)
                    if (encodedData != null && bufferInfo.size > 0 &&
                        (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0 &&
                        muxerStarted
                    ) {
                        encodedData.position(bufferInfo.offset)
                        encodedData.limit(bufferInfo.offset + bufferInfo.size)
                        bufferInfo.presentationTimeUs = writtenVideoFrames * frameIntervalUs
                        writtenVideoFrames++
                        muxer.writeSampleData(videoTrackIdx, encodedData, bufferInfo)
                    }
                    videoEncoder.releaseOutputBuffer(outIdx, false)
                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        break
                    }
                }
            }
        }

        try {
            for (i in 0 until totalFrames) {
                val bmp = frameProvider(i) ?: continue
                val canvas = inputSurface.lockCanvas(null)
                canvas.drawBitmap(bmp, 0f, 0f, null)
                inputSurface.unlockCanvasAndPost(canvas)
                drainVideo(false)
            }
            drainVideo(true)

            if (muxerStarted && hasAudio && audioTrackIdx >= 0) {
                val audioInfo = MediaCodec.BufferInfo()
                for (sample in audio!!.samples) {
                    if (sample.presentationTimeUs > durationUs) break
                    audioInfo.offset = 0
                    audioInfo.size = sample.data.size
                    audioInfo.presentationTimeUs = sample.presentationTimeUs
                    audioInfo.flags = sample.flags
                    muxer.writeSampleData(audioTrackIdx, ByteBuffer.wrap(sample.data), audioInfo)
                }
            }
        } finally {
            videoEncoder.stop()
            videoEncoder.release()
            inputSurface.release()
            if (muxerStarted) {
                muxer.stop()
            }
            muxer.release()
        }
    }

    private fun saveVideoToGallery(sourceFile: File): String {
        val fileName = "BocchiStudio_" + System.currentTimeMillis().toString() + ".mp4"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(
                    MediaStore.Video.Media.RELATIVE_PATH,
                    Environment.DIRECTORY_MOVIES + "/BocchiStickers"
                )
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }

            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("No se pudo guardar el video en la galería.")

            resolver.openOutputStream(uri)?.use { out ->
                FileInputStream(sourceFile).use { input ->
                    input.copyTo(out)
                }
            }

            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            sourceFile.delete()
            return "Movies/BocchiStickers/" + fileName
        } else {
            @Suppress("DEPRECATION")
            val moviesDir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES),
                "BocchiStickers"
            )
            if (!moviesDir.exists()) moviesDir.mkdirs()
            val destFile = File(moviesDir, fileName)
            FileInputStream(sourceFile).use { input ->
                FileOutputStream(destFile).use { out ->
                    input.copyTo(out)
                }
            }
            sourceFile.delete()
            MediaScannerConnection.scanFile(
                context,
                arrayOf(destFile.absolutePath),
                arrayOf("video/mp4"),
                null
            )
            return destFile.absolutePath
        }
    }
}