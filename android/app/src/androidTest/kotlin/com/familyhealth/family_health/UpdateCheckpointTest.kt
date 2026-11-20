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

    @Test @Suppress("DEPRECATION")
    fun downloadedArchiveCanBePreparedOfflineAndInstallerRetried() {
        val ctx = context
        val release = release()
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
            AndroidUpdates(ctx).prepare(id)
            val reopened = AndroidUpdates(ctx)
            assertEquals("ready", reopened.snapshot()["stage"])
            assertArrayEquals(raw, File(reopened.readyPath(release.apk.hash)).readBytes())
            reopened.start(false)
            assertEquals(-1L, prefs.getLong("downloadId", -1L))
            assertEquals(staged.path, AndroidUpdates(ctx).readyPath(release.apk.hash))
            assertTrue(runCatching { reopened.readyPath("different-build") }.isFailure)
        } finally {
            manager.remove(id)
            prefs.edit().clear().commit()
            staged.delete()
            file.delete()
        }
    }
}
