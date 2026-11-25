package com.axel.sticker_maker

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {

    private val channelName = "com.axel.sticker_maker/whatsapp"
    private val addPackRequestCode = 200
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isWhatsAppInstalled" -> {
                        val consumer = isPackageInstalled("com.whatsapp")
                        val business = isPackageInstalled("com.whatsapp.w4b")
                        result.success(
                            mapOf(
                                "consumer" to consumer,
                                "business" to business,
                                "any" to (consumer || business)
                            )
                        )
                    }

                    "encodePngToWebp" -> {
                        val pngBytes = call.argument<ByteArray>("pngBytes")
                        val quality = call.argument<Int>("quality") ?: 90
                        if (pngBytes == null) {
                            result.error("INVALID_ARGS", "pngBytes es nulo", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val bitmap = BitmapFactory.decodeByteArray(pngBytes, 0, pngBytes.size)
                            val out = ByteArrayOutputStream()
                            val format = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                Bitmap.CompressFormat.WEBP_LOSSY
                            } else {
                                @Suppress("DEPRECATION")
                                Bitmap.CompressFormat.WEBP
                            }
                            bitmap.compress(format, quality, out)
                            result.success(out.toByteArray())
                        } catch (e: Exception) {
                            result.error("ENCODE_ERROR", e.message, null)
                        }
                    }

                    "getVideoDurationMs" -> {
                        val videoPath = call.argument<String>("videoPath")
                        if (videoPath.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "videoPath vacío", null)
                            return@setMethodCallHandler
                        }
                        val retriever = MediaMetadataRetriever()
                        try {
                            retriever.setDataSource(videoPath)
                            val durationStr = retriever.extractMetadata(
                                MediaMetadataRetriever.METADATA_KEY_DURATION
                            )
                            val durationMs = durationStr?.toLongOrNull() ?: 3000L
                            result.success(durationMs.toInt())
                        } catch (e: Exception) {
                            result.error("VIDEO_DURATION_ERROR", e.message, null)
                        } finally {
                            retriever.release()
                        }
                    }

                    "extractSingleVideoFrame" -> {
                        val videoPath = call.argument<String>("videoPath")
                        val timeMs = call.argument<Int>("timeMs") ?: 0
                        if (videoPath.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "videoPath vacío", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            val retriever = MediaMetadataRetriever()
                            try {
                                retriever.setDataSource(videoPath)
                                val timeUs = timeMs.coerceAtLeast(0).toLong() * 1000L
                                val raw = retriever.getFrameAtTime(
                                    timeUs,
                                    MediaMetadataRetriever.OPTION_CLOSEST
                                ) ?: retriever.getFrameAtTime(timeUs)
                                if (raw != null) {
                                    val scaled = scaleKeepingAspect(raw, 512)
                                    val out = ByteArrayOutputStream()
                                    scaled.compress(Bitmap.CompressFormat.JPEG, 90, out)
                                    if (scaled != raw) scaled.recycle()
                                    raw.recycle()
                                    runOnUiThread { result.success(out.toByteArray()) }
                                } else {
                                    runOnUiThread { result.success(null) }
                                }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("FRAME_ERROR", e.message, null)
                                }
                            } finally {
                                retriever.release()
                            }
                        }.start()
                    }

                    "extractVideoFrames" -> {
                        val videoPath = call.argument<String>("videoPath")
                        val startMs = call.argument<Int>("startMs") ?: 0
                        val endMs = call.argument<Int>("endMs") ?: 2500
                        val fps = call.argument<Int>("fps") ?: 10
                        val targetSize = call.argument<Int>("targetSize") ?: 512

                        if (videoPath.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "videoPath vacío", null)
                            return@setMethodCallHandler
                        }

                        Thread {
                            val retriever = MediaMetadataRetriever()
                            try {
                                retriever.setDataSource(videoPath)
                                val durationMs = (endMs - startMs).coerceIn(400, 6000)
                                val frameCount = ((durationMs / 1000.0) * fps).toInt().coerceIn(3, 45)
                                val stepMs = durationMs.toLong() / frameCount

                                val framesBytes = ArrayList<ByteArray>(frameCount)

                                for (i in 0 until frameCount) {
                                    val timeUs = (startMs + (i * stepMs)) * 1000L
                                    val rawFrame = retriever.getFrameAtTime(
                                        timeUs,
                                        MediaMetadataRetriever.OPTION_CLOSEST
                                    ) ?: retriever.getFrameAtTime(timeUs)

                                    if (rawFrame != null) {
                                        val scaledBmp = scaleKeepingAspect(rawFrame, targetSize)
                                        val out = ByteArrayOutputStream()
                                        scaledBmp.compress(Bitmap.CompressFormat.PNG, 100, out)
                                        framesBytes.add(out.toByteArray())
                                        if (scaledBmp != rawFrame) scaledBmp.recycle()
                                        rawFrame.recycle()
                                    }
                                }

                                runOnUiThread {
                                    result.success(framesBytes)
                                }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("EXTRACT_FRAMES_ERROR", e.message, null)
                                }
                            } finally {
                                retriever.release()
                            }
                        }.start()
                    }

                    "createSoundStickerMp4" -> {
                        val mediaPath = call.argument<String>("mediaPath")
                            ?: call.argument<String>("imagePath")
                        val isVideo = call.argument<Boolean>("isVideo") ?: false
                        val audioPath = call.argument<String>("audioPath")
                        val startMs = call.argument<Int>("startMs") ?: 0
                        val maxDurationMs = call.argument<Int>("maxDurationMs") ?: 5000
                        val cropAlign = call.argument<String>("cropAlign") ?: "center"

                        if (mediaPath.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "Falta elegir una imagen o video", null)
                            return@setMethodCallHandler
                        }

                        Thread {
                            try {
                                val encoder = SoundStickerEncoder(applicationContext)
                                val savedPath = encoder.createSoundStickerMp4(
                                    mediaPath = mediaPath,
                                    isVideo = isVideo,
                                    audioPath = audioPath,
                                    startMs = startMs,
                                    maxDurationMs = maxDurationMs,
                                    cropAlign = cropAlign
                                )
                                runOnUiThread {
                                    result.success(savedPath)
                                }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("SOUND_STICKER_ERROR", e.message, null)
                                }
                            }
                        }.start()
                    }

                    "addPackToWhatsApp" -> {
                        val identifier = call.argument<String>("identifier")
                        val name = call.argument<String>("name")
                        if (identifier.isNullOrEmpty() || name.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "Falta identifier o name", null)
                            return@setMethodCallHandler
                        }

                        val authority = applicationContext.packageName + ".stickercontentprovider"
                        val intent = Intent("com.whatsapp.intent.action.ENABLE_STICKER_PACK").apply {
                            putExtra("sticker_pack_id", identifier)
                            putExtra("sticker_pack_authority", authority)
                            putExtra("sticker_pack_name", name)
                        }

                        try {
                            val metadataUri = android.net.Uri.parse("content://" + authority + "/metadata")
                            contentResolver.notifyChange(metadataUri, null)

                            pendingResult = result
                            startActivityForResult(
                                Intent.createChooser(intent, "Agregar paquete a WhatsApp"),
                                addPackRequestCode
                            )
                        } catch (e: ActivityNotFoundException) {
                            pendingResult = null
                            result.error(
                                "WHATSAPP_NOT_FOUND",
                                "No se encontró WhatsApp instalado en el dispositivo.",
                                null
                            )
                        } catch (e: Exception) {
                            pendingResult = null
                            result.error("INTENT_ERROR", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun scaleKeepingAspect(src: Bitmap, maxSide: Int): Bitmap {
        val largest = maxOf(src.width, src.height)
        if (largest <= maxSide) return src

        val scale = maxSide.toFloat() / largest.toFloat()
        val newW = (src.width * scale).toInt().coerceAtLeast(1)
        val newH = (src.height * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, newW, newH, true)
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(0)
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
            }
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == addPackRequestCode) {
            val res = pendingResult ?: return
            pendingResult = null

            if (resultCode == Activity.RESULT_CANCELED) {
                val validationError = data?.getStringExtra("validation_error")
                if (validationError != null) {
                    res.error("WHATSAPP_VALIDATION_ERROR", validationError, null)
                } else {
                    res.success(
                        mapOf(
                            "added" to false,
                            "status" to "cancelled_or_already_added"
                        )
                    )
                }
            } else if (resultCode == Activity.RESULT_OK) {
                res.success(
                    mapOf(
                        "added" to true,
                        "status" to "ok"
                    )
                )
            } else {
                res.success(
                    mapOf(
                        "added" to false,
                        "status" to "unknown_code_" + resultCode.toString()
                    )
                )
            }
        }
    }
}