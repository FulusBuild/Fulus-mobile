package com.fulus.app

import android.content.ContentUris
import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException

/**
 * `fulus/backup_export` — the native half of
 * BackupRepositoryImpl.exportToDownloads and .findDurableBackup (see
 * each method's own doc comment in the Dart layer for why both need
 * to be native at all: writing to, or reading back from, an app's own
 * entries in the public Downloads collection on Android 10+ goes
 * through MediaStore, which has no `dart:io` equivalent — there's no
 * plain file path to hand a Flutter plugin for a location the app
 * doesn't already own).
 */
class MainActivity : FlutterActivity() {
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

    /**
     * Copies [sourcePath] into Download/Fulus/[displayName] in the
     * device's public, shared storage — overwriting any previous copy
     * with the same name rather than creating a new one each time, so
     * this stays the single, always-current file
     * BackupRepositoryImpl.runAutoBackup's own doc comment describes,
     * not a pile of timestamped exports the person has to clean up by
     * hand. Returns the resulting path for display purposes.
     *
     * Two implementations, chosen by API level:
     * - Android 10+ (Build.VERSION_CODES.Q / scoped storage): MediaStore
     *   Downloads collection. No permission needed — an app creating
     *   its own new file here is allowed by default under scoped
     *   storage; this is the ONLY correct way to reach public storage
     *   on these versions without asking for broad file access this
     *   app has no other reason to want. Looks up any existing entry
     *   with the same name and relative path first and reopens it in
     *   truncate ("wt") mode, rather than inserting a fresh row each
     *   time, which is what keeps this a single overwritten file
     *   instead of MediaStore auto-renaming a second one.
     * - Android 8–9 (below scoped storage): a direct file write to the
     *   legacy public Downloads directory, gated on
     *   WRITE_EXTERNAL_STORAGE (AndroidManifest.xml declares it with
     *   maxSdkVersion="28" — irrelevant, and correctly unused, on 29+).
     */
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
                } else {
                    null
                }
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
        FileInputStream(File(sourcePath)).use { input ->
            dest.outputStream().use { out -> input.copyTo(out) }
        }
        return dest.absolutePath
    }

    /**
     * The read counterpart to [exportToDownloads]: looks up the exact
     * Download/Fulus/fulus_backup_latest.db entry that method writes
     * and, if it exists, copies it into this app's own external files
     * directory (`getExternalFilesDir` — a plain, `dart:io`-readable
     * path, no MediaStore involved on the read side) so the Dart layer
     * can hand it straight to `BackupRepository.importBackupFile`
     * exactly like a file_picker result, with zero new restore-side
     * logic on that end.
     *
     * Genuinely reachable after a real uninstall/reinstall, unlike
     * everything else this app owns: MediaStore tracks a file's owner
     * by package name, not by whether that package happens to be
     * installed right now — an entry this same package previously
     * inserted into the Downloads collection stays queryable and
     * readable by it again after a reinstall, the identical durability
     * guarantee [exportToDownloads]'s own doc comment already leans on
     * for the write side.
     *
     * Returns the copied-out path, or null if no such file exists — a
     * genuinely fresh device, or one that never had an auto-backup
     * run. Android 8–9 checks the legacy Download/Fulus folder
     * directly instead, mirroring [exportToDownloads]'s own split.
     */
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
                } else {
                    null
                }
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
        FileInputStream(legacyFile).use { input ->
            destFile.outputStream().use { out -> input.copyTo(out) }
        }
        return destFile.absolutePath
    }
}
