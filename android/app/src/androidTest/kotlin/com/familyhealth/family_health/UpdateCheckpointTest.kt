package com.familyhealth.family_health

import android.app.DownloadManager
import android.content.Context
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.zip.GZIPOutputStream

class UpdateCheckpointTest {
    private val raw = ByteArray(8192) { (it % 11).toByte() }
    private val archive = ByteArrayOutputStream().also { out -> GZIPOutputStream(out).use { it.write(raw) } }.toByteArray()
    private fun hash(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    private fun asset(name: String, bytes: ByteArray) = JSONObject().put("name", name)
        .put("browser_download_url", "https://github.com/Indla26v/Family-health-app/releases/download/v2.0.0%2B999/$name")
        .put("size", bytes.size).put("digest", "sha256:" + hash(bytes))
    private val name = "FamilyHealth-x86_64.apk"

    @Test fun compressedSelectionAndFallback() {
        val assets = JSONArray().put(asset("FamilyHealth.apk", raw)).put(asset(name, raw))
        val json = JSONObject().put("tag_name", "v2.0.0+999").put("assets", assets)
        assertEquals(hash(raw), UpdateRelease.select(json, listOf("x86_64")).download.hash)
        assets.put(asset("$name.gz", archive))
        val release = UpdateRelease.select(json, listOf("x86_64"))
        assertEquals(hash(archive), release.download.hash)
        assertEquals(hash(raw), release.apk.hash)
        assertEquals(hash(raw), UpdateRelease.select(json, listOf("arm64-v8a")).download.hash)
    }

    @Test fun incompleteOrCorruptDataCannotProduceAReadyPackage() {
        val release = release()
        val temp = File.createTempFile("unpack", ".part", context.cacheDir)
        try {
            for (bad in listOf(release.copy(apk = release.apk.copy(size = 100)),
                    release.copy(download = release.download.copy(hash = hash(raw))))) {
                assertTrue(runCatching { bad.unpack(archive.inputStream(), temp) }.isFailure)
            }
            assertTrue(runCatching { release.unpack(archive.copyOf(10).inputStream(), temp) }.isFailure)
        } finally { temp.delete() }
    }

    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun release() = UpdateRelease.select(JSONObject().put("tag_name", "v2.0.0+999")
        .put("assets", JSONArray().put(asset(name, raw)).put(asset("$name.gz", archive))), listOf("x86_64"))

    @Test fun retriesAndFallbackAreBounded() {
        assertEquals(DownloadFailure.RETRY, downloadFailure(DownloadManager.ERROR_CANNOT_RESUME, true, 0))
        assertEquals(DownloadFailure.RETRY, downloadFailure(503, true, 1))
        assertEquals(DownloadFailure.STOP, downloadFailure(503, true, 2))
        assertEquals(DownloadFailure.FALLBACK, downloadFailure(404, true, 2))
        assertEquals(DownloadFailure.STOP, downloadFailure(410, false, 0))
        assertEquals(DownloadFailure.STORAGE, downloadFailure(DownloadManager.ERROR_INSUFFICIENT_SPACE, true, 0))
    }

    @Test fun lowStoragePreservesTheDownloadedArchive() {
        withCompletedArchive(release().let { it.copy(apk = it.apk.copy(size = Long.MAX_VALUE)) }) { ctx, release, id ->
            val updates = AndroidUpdates(ctx)
            assertTrue(runCatching { updates.prepare(id) }.isFailure)
            assertEquals("Free up storage, then retry.", AndroidUpdates(ctx).snapshot()["error"])
            val preferences = ctx.getSharedPreferences("android_updates", Context.MODE_PRIVATE)
            assertEquals(id, preferences.getLong("downloadId", -1L))
            assertFalse(File(ctx.filesDir, "app-updates/" + release.apk.hash + ".apk").exists())
        }
    }

    @Test fun corruptArchiveSwitchesToTheRawApkWithoutReusingOldBytes() {
        val original = release()
        val target = original.copy(
            apk = original.apk.copy(url = "https://127.0.0.1:1/update.apk"),
            download = original.download.copy(hash = hash(raw))
        )
        withCompletedArchive(target) { ctx, _, id ->
            AndroidUpdates(ctx).prepare(id)
            val snapshot = AndroidUpdates(ctx).snapshot()
            assertEquals(true, snapshot["fallback"])
            val fallback = UpdateRelease.read(JSONObject(snapshot["release"] as String))
            assertEquals(target.apk, fallback.download)
            assertNotEquals("ready", snapshot["stage"])
            val prefs = ctx.getSharedPreferences("android_updates", Context.MODE_PRIVATE)
            assertTrue(prefs.getBoolean("automaticTransfer", false))
            assertNotEquals(id, prefs.getLong("downloadId", -1L))
        }
    }

    @Test @Suppress("DEPRECATION")
    fun downloadedArchiveCanBePreparedOfflineAndInstallerRetried() {
        withCompletedArchive(release()) { ctx, release, id ->
            AndroidUpdates(ctx).prepare(id)
            val reopened = AndroidUpdates(ctx)
            val snapshot = reopened.snapshot()
            assertEquals("ready", snapshot["stage"])
            assertEquals(archive.size.toLong(), snapshot["received"])
            assertEquals(true, snapshot["transferComplete"])
            assertTrue((snapshot["verificationMillis"] as Long) >= 0L)
            assertArrayEquals(raw, File(reopened.readyPath(release.apk.hash)).readBytes())
            reopened.start(false)
            val prefs = ctx.getSharedPreferences("android_updates", Context.MODE_PRIVATE)
            assertEquals(-1L, prefs.getLong("downloadId", -1L))
            assertTrue(runCatching { reopened.readyPath("different-build") }.isFailure)
        }
    }

    @Suppress("DEPRECATION")
    private fun withCompletedArchive(release: UpdateRelease, action: (Context, UpdateRelease, Long) -> Unit) {
        val ctx = context
        val file = File.createTempFile("checkpoint", ".gz", ctx.getExternalFilesDir(null))
        val prefs = ctx.getSharedPreferences("android_updates", Context.MODE_PRIVATE)
        val manager = ctx.getSystemService(DownloadManager::class.java)
        file.writeBytes(archive)
        val id = manager.addCompletedDownload("Checkpoint test", "Completed archive", false,
            "application/gzip", file.path, file.length(), true)
        val staged = File(ctx.filesDir, "app-updates/" + release.apk.hash + ".apk")
        try {
            prefs.edit().putBoolean("automatic", false).putString("release", release.json().toString())
                .putLong("downloadId", id).commit()
            action(ctx, release, id)
        } finally {
            manager.remove(id)
            val replacement = prefs.getLong("downloadId", -1L)
            if (replacement >= 0L && replacement != id) manager.remove(replacement)
            prefs.edit().clear().commit()
            staged.delete()
            file.delete()
        }
    }
}
