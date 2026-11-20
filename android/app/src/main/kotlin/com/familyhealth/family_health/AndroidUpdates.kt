package com.familyhealth.family_health

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.work.*
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/** All entry points share one lock and one durable target, including background workers. */
internal class AndroidUpdates(private val ctx: Context) {
    private val prefs = ctx.getSharedPreferences("android_updates", Context.MODE_PRIVATE)
    private val downloads = ctx.getSystemService(DownloadManager::class.java)
    private val work = WorkManager.getInstance(ctx)
    private val dir get() = File(ctx.filesDir, "app-updates")
    private val id get() = prefs.getLong("downloadId", -1L)
    val automatic get() = prefs.getBoolean("automatic", true)
    private val target get() = prefs.getString("release", null)?.let { UpdateRelease.read(JSONObject(it)) }
    @Suppress("DEPRECATION")
    private val installed get() = ctx.packageManager.getPackageInfo(ctx.packageName, 0)
    private fun apk(release: UpdateRelease) = File(dir, release.apk.hash + ".apk")

    fun schedule() = synchronized(lock) {
        if (automatic) {
            val constraint = Constraints.Builder().setRequiredNetworkType(NetworkType.UNMETERED).build()
            val request = PeriodicWorkRequestBuilder<DailyUpdateWorker>(1, TimeUnit.DAYS)
                .setConstraints(constraint).build()
            work.enqueueUniquePeriodicWork("daily-app-update", ExistingPeriodicWorkPolicy.KEEP, request)
        } else {
            work.cancelUniqueWork("daily-app-update")
        }
        Unit
    }

    fun setAutomatic(enabled: Boolean) = synchronized(lock) {
        prefs.edit().putBoolean("automatic", enabled).commit()
        if (!enabled && prefs.getBoolean("automaticTransfer", false) && id >= 0 &&
            row()?.status != DownloadManager.STATUS_SUCCESSFUL) clearDownload()
        schedule()
    }

    fun check(background: Boolean) {
        if (background && !automatic) return
        val connection = URL("https://api.github.com/repos/$repository/releases/latest").openConnection() as HttpURLConnection
        val latest = try {
            connection.connectTimeout = 12000
            connection.readTimeout = 12000
            connection.setRequestProperty("Accept", "application/vnd.github+json")
            connection.setRequestProperty("User-Agent", "FamilyHealth-Updater")
            connection.inputStream.bufferedReader().use { UpdateRelease.select(JSONObject(it.readText()), Build.SUPPORTED_ABIS.toList()) }
        } finally { connection.disconnect() }
        synchronized(lock) {
            if (background && !automatic) return
            cleanInstalled()
            val old = target
            @Suppress("DEPRECATION")
            if (latest.build > installed.versionCode && (old == null || latest.build >= old.build)) {
                if (old != latest) {
                    if (old?.apk != latest.apk || old.download != latest.download) resetTarget()
                    prefs.edit().putString("release", latest.json().toString()).commit()
                }
                if (!background) prefs.edit().remove("dismissed").commit()
                if (background && latest.build != prefs.getInt("dismissed", 0)) start(true)
            }
            prefs.edit().putBoolean("checked", true).commit()
        }
    }

    fun dismiss() = synchronized(lock) {
        val release = target ?: return@synchronized
        prefs.edit().putInt("dismissed", release.build).commit()
        ctx.getSystemService(android.app.NotificationManager::class.java).cancel(UpdateNotice.ID)
    }

    fun start(background: Boolean, allowMeteredFor: String? = null) = synchronized(lock) {
        cleanInstalled()
        val release = target ?: return@synchronized
        if (apk(release).isFile || background && !automatic) return@synchronized
        recoverEnqueue(release)
        val existing = row()
        val switchNetwork = allowMeteredFor == release.apk.hash && waitingForNetwork(existing)
        if (existing != null && existing.status != DownloadManager.STATUS_FAILED && !switchNetwork) {
            if (existing.status == DownloadManager.STATUS_SUCCESSFUL) {
                prefs.edit().remove("error").commit()
                enqueuePreparation()
            }
            return@synchronized
        }
        clearDownload()
        val request = DownloadManager.Request(Uri.parse(release.download.url))
            .setTitle("Family Health " + release.version)
            .setDescription("Downloading app update")
            .setAllowedOverMetered(!background)
            .setAllowedOverRoaming(!background)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setDestinationInExternalFilesDir(ctx, null, "FamilyHealth-" + release.download.hash + "-" + System.currentTimeMillis())
        prefs.edit().putBoolean("enqueuing", true).putBoolean("automaticTransfer", background)
            .putLong("started", System.currentTimeMillis()).commit()
        val downloadId = downloads.enqueue(request)
        prefs.edit().putLong("downloadId", downloadId).remove("enqueuing").commit()
    }

    // A process can exit after enqueue() but before its returned ID is saved.
    private fun recoverEnqueue(release: UpdateRelease) {
        if (!prefs.getBoolean("enqueuing", false)) return
        val edit = prefs.edit().remove("enqueuing")
        downloads.query(DownloadManager.Query())?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_URI)) == release.download.url) {
                    edit.putLong("downloadId", cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_ID)))
                    break
                }
            }
        }
        edit.commit()
    }

    private data class Row(val status: Int, val bytes: Long, val reason: Int)
    private fun waitingForNetwork(row: Row?) = prefs.getBoolean("automaticTransfer", false) &&
        row?.status == DownloadManager.STATUS_PAUSED && row.reason in listOf(
            DownloadManager.PAUSED_QUEUED_FOR_WIFI, DownloadManager.PAUSED_WAITING_FOR_NETWORK)
    private fun row(): Row? {
        if (id < 0) return null
        return downloads.query(DownloadManager.Query().setFilterById(id))?.use {
            if (!it.moveToFirst()) null else Row(it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)),
                it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)),
                it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON)))
        }
    }

    fun snapshot(): Map<String, Any?> = synchronized(lock) {
        cleanInstalled()
        val release = target
        release?.let(::recoverEnqueue)
        val hidden = release != null && release.build == prefs.getInt("dismissed", 0)
        val ready = release != null && apk(release).isFile
        val row = row()
        val problem = prefs.getString("error", null) ?: when {
            row?.status == DownloadManager.STATUS_FAILED -> "Download failed (Android code ${row.reason})"
            id >= 0 && row == null -> "Download was removed"
            else -> null
        }
        val stage = when {
            ready -> "ready"
            problem != null -> "error"
            row?.status == DownloadManager.STATUS_SUCCESSFUL -> "verifying"
            row?.status == DownloadManager.STATUS_RUNNING -> "downloading"
            row != null -> "waiting"
            else -> "idle"
        }
        if (stage == "verifying") enqueuePreparation()
        @Suppress("DEPRECATION")
        mapOf("release" to release?.takeUnless { hidden }?.json()?.toString(), "stage" to stage,
            "received" to (row?.bytes ?: 0L), "error" to problem, "automatic" to automatic,
            "waitingForUnmetered" to waitingForNetwork(row),
            "installedBuild" to installed.versionCode, "installedVersion" to installed.versionName,
            "notificationsEnabled" to ctx.getSystemService(android.app.NotificationManager::class.java).areNotificationsEnabled(),
            "upToDate" to (release == null && prefs.getBoolean("checked", false)))
    }

    fun readyPath(expectedHash: String?): String = synchronized(lock) {
        cleanInstalled()
        val release = requireNotNull(target) { "Update is no longer available" }
        require(release.apk.hash == expectedHash && apk(release).isFile) { "Update is still being prepared" }
        apk(release).absolutePath
    }

    fun onComplete(completed: Long) = synchronized(lock) {
        if (completed == id && completed >= 0) enqueuePreparation()
    }

    private fun enqueuePreparation() {
        val request = OneTimeWorkRequestBuilder<PrepareUpdateWorker>().setInputData(workDataOf("id" to id)).build()
        work.enqueueUniqueWork("prepare-app-update-$id", ExistingWorkPolicy.KEEP, request)
    }

    fun prepare(downloadId: Long) {
        val release = synchronized(lock) {
            if (id != downloadId || row()?.status != DownloadManager.STATUS_SUCCESSFUL) return
            target ?: return
        }
        val temporary = File(dir, "prepare-$downloadId.part")
        try {
            dir.mkdirs()
            val started = System.currentTimeMillis()
            downloads.openDownloadedFile(downloadId).let { descriptor ->
                android.os.ParcelFileDescriptor.AutoCloseInputStream(descriptor).use {
                    require(descriptor.statSize == release.download.size) { "Incomplete update download" }
                    release.unpack(it, temporary)
                }
            }
            synchronized(lock) {
                if (id != downloadId || target?.apk != release.apk) return
                kotlin.check(temporary.renameTo(apk(release))) { "Could not save the verified update" }
                Log.i("FamilyHealthUpdate", "Build ${release.build}, download/wait ${started - prefs.getLong("started", started)} ms, prepare ${System.currentTimeMillis() - started} ms")
                clearDownload()
                if (prefs.getInt("dismissed", 0) != release.build) UpdateNotice.show(ctx, release, apk(release))
            }
        } catch (e: Exception) {
            synchronized(lock) {
                if (id == downloadId) {
                    if (e is IllegalArgumentException || e is java.util.zip.ZipException ||
                        e is java.io.EOFException) clearDownload()
                    prefs.edit().putString("error", e.message ?: "Could not prepare the update").commit()
                }
            }
            throw e
        } finally { temporary.delete() }
    }

    private fun clearDownload() {
        if (id >= 0) downloads.remove(id)
        prefs.edit().remove("downloadId").remove("enqueuing").remove("automaticTransfer").remove("error").commit()
    }

    @Suppress("DEPRECATION")
    private fun cleanInstalled() {
        val current = target ?: return
        if (current.build <= installed.versionCode) resetTarget()
    }

    private fun resetTarget() {
        File(dir, "prepare-$id.part").delete()
        clearDownload()
        target?.let { apk(it).delete() }
        prefs.edit().remove("release").remove("dismissed").commit()
        ctx.getSystemService(android.app.NotificationManager::class.java).cancel(UpdateNotice.ID)
    }

    companion object { private val lock = Any() }
}

class DailyUpdateWorker(ctx: Context, args: WorkerParameters) : Worker(ctx, args) {
    override fun doWork(): Result = try {
        AndroidUpdates(applicationContext).check(true)
        Result.success()
    } catch (e: Exception) {
        Log.w("FamilyHealthUpdate", "Scheduled check failed", e)
        if (runAttemptCount < 3) Result.retry() else Result.failure()
    }
}

class PrepareUpdateWorker(ctx: Context, args: WorkerParameters) : Worker(ctx, args) {
    override fun doWork(): Result = try {
        AndroidUpdates(applicationContext).prepare(inputData.getLong("id", -1))
        Result.success()
    } catch (e: Exception) {
        Log.w("FamilyHealthUpdate", "Update preparation failed", e)
        Result.failure()
    }
}
