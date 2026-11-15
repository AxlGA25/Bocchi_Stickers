package com.axel.sticker_maker

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.media.MediaMetadataRetriever
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import kotlin.math.min

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
                                        val squareBmp = cropCenterSquare(rawFrame, targetSize)
                                        val out = ByteArrayOutputStream()
                                        squareBmp.compress(Bitmap.CompressFormat.PNG, 100, out)
                                        framesBytes.add(out.toByteArray())
                                        if (squareBmp != rawFrame) squareBmp.recycle()
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

                    "addPackToWhatsApp" -> {
                        val identifier = call.argument<String>("identifier")
                        val name = call.argument<String>("name")
                        if (identifier.isNullOrEmpty() || name.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "Falta identifier o name", null)
                            return@setMethodCallHandler
                        }

                        val authority = "\${applicationContext.packageName}.stickercontentprovider"
                        val intent = Intent("com.whatsapp.intent.action.ENABLE_STICKER_PACK").apply {
                            putExtra("sticker_pack_id", identifier)
                            putExtra("sticker_pack_authority", authority)
                            putExtra("sticker_pack_name", name)
                        }

                        try {
                            val metadataUri = android.net.Uri.parse("content://\$authority/metadata")
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

    /// Recorta la imagen al cuadrado central y la centra en un lienzo de 512x512 con margen transparente de 16px
    private fun cropCenterSquare(src: Bitmap, targetSize: Int): Bitmap {
        val minSide = min(src.width, src.height)
        val cropX = (src.width - minSide) / 2
        val cropY = (src.height - minSide) / 2

        val cropped = Bitmap.createBitmap(src, cropX, cropY, minSide, minSide)
        val output = Bitmap.createBitmap(targetSize, targetSize, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)

        val margin = 16f
        val safeSize = targetSize - (margin * 2f)
        val scale = safeSize / minSide.toFloat()

        val matrix = Matrix().apply {
            postScale(scale, scale)
            postTranslate(margin, margin)
        }

        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        canvas.drawBitmap(cropped, matrix, paint)
        if (cropped != src) cropped.recycle()
        return output
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
                        "status" to "unknown_code_\$resultCode"
                    )
                )
            }
        }
    }
}