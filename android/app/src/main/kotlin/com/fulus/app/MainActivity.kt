package com.fulus.app

import android.content.ContentUris
import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException

/**
 * `fulus/backup_export` — the native half of
 * BackupRepositoryImpl.exportToDownloads and .findDurableBackup.
 *
 * FlutterFragmentActivity is intentional: local_auth uses Android's
 * FragmentActivity APIs for biometric prompts.
 */
class MainActivity : FlutterFragmentActivity() {
    private val backupExportChannel = "fulus/backup_export"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, backupExportChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "exportToDownloads" -> {
                        val sourcePath = call.argument<String>("sourcePath")
                        val displayName = call.argument<String>("displayName")
                        if (sourcePath.isNullOrEmpty() || displayName.isNullOrEmpty()) {
                            result.error("bad_args", "sourcePath and displayName are required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(exportToDownloads(sourcePath, displayName))
                        } catch (e: Exception) {
                            result.error("export_failed", e.message, null)
                        }
                    }
                    "findDurableBackup" -> {
                        try {
                            result.success(findDurableBackup())
                        } catch (e: Exception) {
                            result.error("find_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun exportToDownloads(sourcePath: String, displayName: String): String {
        val relativePath = Environment.DIRECTORY_DOWNLOADS + File.separator + "Fulus" + File.separator

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val existingUri = resolver.query(
                collection,
                arrayOf(MediaStore.Downloads._ID),
                "${MediaStore.Downloads.DISPLAY_NAME} = ? AND ${MediaStore.Downloads.RELATIVE_PATH} = ?",
                arrayOf(displayName, relativePath),
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Downloads._ID))
                    ContentUris.withAppendedId(collection, id)
                } else null
            }
            val uri = existingUri ?: run {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, displayName)
                    put(MediaStore.Downloads.RELATIVE_PATH, relativePath)
                    put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
                }
                resolver.insert(collection, values)
                    ?: throw FileNotFoundException("MediaStore declined to create an entry for $displayName")
            }
            resolver.openOutputStream(uri, "wt")?.use { out ->
                FileInputStream(File(sourcePath)).use { input -> input.copyTo(out) }
            } ?: throw FileNotFoundException("Could not open $uri for writing")
            return "Download/Fulus/$displayName"
        }

        @Suppress("DEPRECATION")
        val legacyDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "Fulus")
        if (!legacyDir.exists() && !legacyDir.mkdirs()) {
            throw FileNotFoundException("Could not create $legacyDir")
        }
        val dest = File(legacyDir, displayName)
        FileInputStream(File(sourcePath)).use { input -> dest.outputStream().use { out -> input.copyTo(out) } }
        return dest.absolutePath
    }

    private fun findDurableBackup(): String? {
        val displayName = "fulus_backup_latest.db"
        val relativePath = Environment.DIRECTORY_DOWNLOADS + File.separator + "Fulus" + File.separator
        val destFile = File(applicationContext.getExternalFilesDir(null), "durable_backup_check.db")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val uri = resolver.query(
                collection,
                arrayOf(MediaStore.Downloads._ID),
                "${MediaStore.Downloads.DISPLAY_NAME} = ? AND ${MediaStore.Downloads.RELATIVE_PATH} = ?",
                arrayOf(displayName, relativePath),
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Downloads._ID))
                    ContentUris.withAppendedId(collection, id)
                } else null
            } ?: return null
            resolver.openInputStream(uri)?.use { input ->
                destFile.outputStream().use { out -> input.copyTo(out) }
            } ?: return null
            return destFile.absolutePath
        }

        @Suppress("DEPRECATION")
        val legacyFile = File(
            File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "Fulus"),
            displayName,
        )
        if (!legacyFile.exists()) return null
        FileInputStream(legacyFile).use { input -> destFile.outputStream().use { out -> input.copyTo(out) } }
        return destFile.absolutePath
    }
}
