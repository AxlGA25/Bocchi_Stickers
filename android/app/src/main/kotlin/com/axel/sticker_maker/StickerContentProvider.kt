package com.axel.sticker_maker

import android.content.ContentProvider
import android.content.ContentValues
import android.content.UriMatcher
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.text.TextUtils
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException

class StickerContentProvider : ContentProvider() {

    companion object {
        const val STICKER_PACK_IDENTIFIER_IN_QUERY = "sticker_pack_identifier"
        const val STICKER_PACK_NAME_IN_QUERY = "sticker_pack_name"
        const val STICKER_PACK_PUBLISHER_IN_QUERY = "sticker_pack_publisher"
        const val STICKER_PACK_ICON_IN_QUERY = "sticker_pack_icon"
        const val ANDROID_APP_DOWNLOAD_LINK_IN_QUERY = "android_play_store_link"
        const val IOS_APP_DOWNLOAD_LINK_IN_QUERY = "ios_app_download_link"
        const val PUBLISHER_EMAIL = "sticker_pack_publisher_email"
        const val PUBLISHER_WEBSITE = "sticker_pack_publisher_website"
        const val PRIVACY_POLICY_WEBSITE = "sticker_pack_privacy_policy_website"
        const val LICENSE_AGREENMENT_WEBSITE = "sticker_pack_license_agreement_website"
        const val IMAGE_DATA_VERSION = "image_data_version"
        const val AVOID_CACHE = "whatsapp_will_not_cache_stickers"
        const val ANIMATED_STICKER_PACK = "animated_sticker_pack"

        const val STICKER_FILE_NAME_IN_QUERY = "sticker_file_name"
        const val STICKER_FILE_EMOJI_IN_QUERY = "sticker_emoji"

        const val METADATA = "metadata"
        const val STICKERS = "stickers"
        const val STICKERS_ASSET = "stickers_asset"

        private const val METADATA_CODE = 1
        private const val METADATA_CODE_FOR_SINGLE_PACK = 2
        private const val STICKERS_CODE = 3
        private const val STICKERS_ASSET_CODE = 4
    }

    private lateinit var matcher: UriMatcher

    override fun onCreate(): Boolean {
        val ctx = context ?: return false
        val authority = ctx.packageName + ".stickercontentprovider"
        matcher = UriMatcher(UriMatcher.NO_MATCH).apply {
            addURI(authority, METADATA, METADATA_CODE)
            addURI(authority, METADATA + "/*", METADATA_CODE_FOR_SINGLE_PACK)
            addURI(authority, STICKERS + "/*", STICKERS_CODE)
            addURI(authority, STICKERS_ASSET + "/*/*", STICKERS_ASSET_CODE)
        }
        return true
    }

    private fun loadPacksJson(): JSONArray {
        val ctx = context ?: return JSONArray()
        val appFlutterDir = File(ctx.filesDir.parentFile, "app_flutter")
        val registryFile = File(appFlutterDir, "whatsapp_packs.json")
        if (!registryFile.exists()) return JSONArray()

        return try {
            val content = registryFile.readText(Charsets.UTF_8)
            val root = JSONObject(content)
            root.optJSONArray("sticker_packs") ?: JSONArray()
        } catch (e: Exception) {
            e.printStackTrace()
            JSONArray()
        }
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor {
        return when (matcher.match(uri)) {
            METADATA_CODE -> getPackForAllStickerPacks(uri)
            METADATA_CODE_FOR_SINGLE_PACK -> getCursorForSingleStickerPack(uri)
            STICKERS_CODE -> getStickersForAStickerPack(uri)
            else -> throw IllegalArgumentException("URI desconocida: " + uri.toString())
        }
    }

    private fun getPackForAllStickerPacks(uri: Uri): Cursor {
        val packsArray = loadPacksJson()
        val list = mutableListOf<JSONObject>()
        for (i in 0 until packsArray.length()) {
            list.add(packsArray.getJSONObject(i))
        }
        return buildStickerPackInfoCursor(uri, list)
    }

    private fun getCursorForSingleStickerPack(uri: Uri): Cursor {
        val identifier = uri.lastPathSegment ?: ""
        val packsArray = loadPacksJson()
        for (i in 0 until packsArray.length()) {
            val pack = packsArray.getJSONObject(i)
            if (pack.optString("identifier") == identifier) {
                return buildStickerPackInfoCursor(uri, listOf(pack))
            }
        }
        return buildStickerPackInfoCursor(uri, emptyList())
    }

    private fun buildStickerPackInfoCursor(uri: Uri, packs: List<JSONObject>): Cursor {
        val cursor = MatrixCursor(
            arrayOf(
                STICKER_PACK_IDENTIFIER_IN_QUERY,
                STICKER_PACK_NAME_IN_QUERY,
                STICKER_PACK_PUBLISHER_IN_QUERY,
                STICKER_PACK_ICON_IN_QUERY,
                ANDROID_APP_DOWNLOAD_LINK_IN_QUERY,
                IOS_APP_DOWNLOAD_LINK_IN_QUERY,
                PUBLISHER_EMAIL,
                PUBLISHER_WEBSITE,
                PRIVACY_POLICY_WEBSITE,
                LICENSE_AGREENMENT_WEBSITE,
                IMAGE_DATA_VERSION,
                AVOID_CACHE,
                ANIMATED_STICKER_PACK
            )
        )

        for (pack in packs) {
            cursor.newRow()
                .add(pack.optString("identifier"))
                .add(pack.optString("name"))
                .add(pack.optString("publisher"))
                .add(pack.optString("tray_image_file"))
                .add(pack.optString("android_play_store_link", ""))
                .add(pack.optString("ios_app_store_link", ""))
                .add(pack.optString("publisher_email", ""))
                .add(pack.optString("publisher_website", ""))
                .add(pack.optString("privacy_policy_website", ""))
                .add(pack.optString("license_agreement_website", ""))
                .add(pack.optString("image_data_version", "1"))
                .add(0)
                .add(if (pack.optBoolean("animated_sticker_pack", false)) 1 else 0)
        }

        context?.contentResolver?.let { cursor.setNotificationUri(it, uri) }
        return cursor
    }

    private fun getStickersForAStickerPack(uri: Uri): Cursor {
        val identifier = uri.lastPathSegment ?: ""
        val cursor = MatrixCursor(
            arrayOf(
                STICKER_FILE_NAME_IN_QUERY,
                STICKER_FILE_EMOJI_IN_QUERY
            )
        )

        val packsArray = loadPacksJson()
        for (i in 0 until packsArray.length()) {
            val pack = packsArray.getJSONObject(i)
            if (pack.optString("identifier") == identifier) {
                val stickers = pack.optJSONArray("stickers") ?: JSONArray()
                for (j in 0 until stickers.length()) {
                    val sticker = stickers.getJSONObject(j)
                    val fileName = sticker.optString("image_file")
                    val emojisArray = sticker.optJSONArray("emojis") ?: JSONArray()
                    val emojisList = mutableListOf<String>()
                    for (k in 0 until emojisArray.length()) {
                        emojisList.add(emojisArray.getString(k))
                    }
                    cursor.addRow(arrayOf<Any>(fileName, TextUtils.join(",", emojisList)))
                }
            }
        }

        context?.contentResolver?.let { cursor.setNotificationUri(it, uri) }
        return cursor
    }

    override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor? {
        if (matcher.match(uri) != STICKERS_ASSET_CODE) return null
        val segments = uri.pathSegments
        if (segments.size < 3) return null

        val identifier = segments[segments.size - 2]
        val fileName = segments[segments.size - 1]
        if (identifier.isEmpty() || fileName.isEmpty()) return null

        val packsArray = loadPacksJson()
        for (i in 0 until packsArray.length()) {
            val pack = packsArray.getJSONObject(i)
            if (pack.optString("identifier") == identifier) {
                if (fileName == pack.optString("tray_image_file")) {
                    val trayPath = pack.optString("tray_file_path")
                    val file = File(trayPath)
                    if (!file.exists()) throw FileNotFoundException("No existe tray icon: " + trayPath)
                    val pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                    return AssetFileDescriptor(pfd, 0, AssetFileDescriptor.UNKNOWN_LENGTH)
                }

                val stickers = pack.optJSONArray("stickers") ?: JSONArray()
                for (j in 0 until stickers.length()) {
                    val sticker = stickers.getJSONObject(j)
                    if (fileName == sticker.optString("image_file")) {
                        val filePath = sticker.optString("file_path")
                        val file = File(filePath)
                        if (!file.exists()) throw FileNotFoundException("No existe sticker: " + filePath)
                        val pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                        return AssetFileDescriptor(pfd, 0, AssetFileDescriptor.UNKNOWN_LENGTH)
                    }
                }
            }
        }
        return null
    }

    override fun getType(uri: Uri): String {
        val pkg = context?.packageName ?: "com.axel.sticker_maker"
        val authority = pkg + ".stickercontentprovider"
        return when (matcher.match(uri)) {
            METADATA_CODE -> "vnd.android.cursor.dir/vnd." + authority + "." + METADATA
            METADATA_CODE_FOR_SINGLE_PACK -> "vnd.android.cursor.item/vnd." + authority + "." + METADATA
            STICKERS_CODE -> "vnd.android.cursor.dir/vnd." + authority + "." + STICKERS
            STICKERS_ASSET_CODE -> {
                val last = uri.lastPathSegment ?: ""
                if (last.endsWith(".png", ignoreCase = true)) "image/png" else "image/webp"
            }
            else -> throw IllegalArgumentException("URI desconocida: " + uri.toString())
        }
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? =
        throw UnsupportedOperationException("No soportado")

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int =
        throw UnsupportedOperationException("No soportado")

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = throw UnsupportedOperationException("No soportado")
}