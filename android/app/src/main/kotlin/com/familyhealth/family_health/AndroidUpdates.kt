package com.familyhealth.family_health

import android.app.DownloadManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.util.Log
import android.os.SystemClock
import android.system.ErrnoException
import android.system.OsConstants
import androidx.work.*
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/** All entry points share one lock and one durable target, including background workers. */
internal class AndroidUpdates(private val ctx: Context) {
    private val prefs = ctx.getSharedPreferences("android_updates", Context.MODE_PRIVATE)
    private val downloads = ctx.getSystemService(DownloadManager::class.java)
    private val network = ctx.getSystemService(ConnectivityManager::class.java)
    private val work = WorkManager.getInstance(ctx)
    private val dir get() = File(ctx.filesDir, "app-updates")
    private val id get() = prefs.getLong("downloadId", -1L)
    val automatic get() = prefs.getBoolean("automatic", true)
    private val target get() = prefs.getString("release", null)?.let { UpdateRelease.read(JSONObject(it)) }
    private val retryAt get() = prefs.getLong("retryAt", 0L)
    private val retries get() = prefs.getInt("retries", 0)
    private val fallback get() = prefs.getBoolean("fallback", false)
    private val needsUnmetered get() = network.activeNetwork == null || network.isActiveNetworkMetered
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
        if (!enabled && prefs.getBoolean("scheduledTransfer", prefs.getBoolean("automaticTransfer", false)) &&
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
                if (old == null || old.build != latest.build || old.apk.hash != latest.apk.hash) {
                    resetTarget()
                    prefs.edit().putString("release", latest.json().toString()).commit()
                } else {
                    val selected = if (fallback) latest.copy(download = latest.apk) else latest
                    if (old.download != selected.download && !apk(old).isFile) {
                        clearDownload()
                        prefs.edit().remove("started").remove("completed").remove("preparedMillis").commit()
                    }
                    if (old != selected) prefs.edit().putString("release", selected.json().toString()).commit()
                }
                if (!background) prefs.edit().remove("dismissed").commit()
                if (background && latest.build != prefs.getInt("dismissed", 0)) start(true)
            }
            prefs.edit().putBoolean("checked", true).putLong("checkedAt", System.currentTimeMillis()).commit()
            if (background) Log.i("FamilyHealthUpdate", "Background release check completed")
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
        if (allowMeteredFor != null && allowMeteredFor != release.download.hash) return@synchronized
        val existing = row()
        val switchNetwork = allowMeteredFor != null && waitingForNetwork(existing)
        if (existing != null && existing.status != DownloadManager.STATUS_FAILED && !switchNetwork) {
            if (existing.status == DownloadManager.STATUS_SUCCESSFUL && !background) {
                prefs.edit().remove("error").commit()
                enqueuePreparation()
            } else if (background) {
                reconcileTransfer(existing)
            }
            return@synchronized
        }
        if (background && (id >= 0 || prefs.contains("error"))) {
            reconcileTransfer(existing)
            return@synchronized
        }
        val unmetered = background || fallback && allowMeteredFor == null
        enqueue(release, unmetered, background)
    }

    private fun enqueue(release: UpdateRelease, unmetered: Boolean, scheduled: Boolean) {
        clearDownload()
        val request = DownloadManager.Request(Uri.parse(release.download.url))
            .setTitle("Family Health " + release.version)
            .setDescription("Downloading app update")
            .setAllowedOverMetered(!unmetered)
            .setAllowedOverRoaming(!unmetered)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setDestinationInExternalFilesDir(ctx, null, "FamilyHealth-" + release.download.hash + "-" + System.currentTimeMillis())
        prefs.edit().putBoolean("enqueuing", true).putBoolean("automaticTransfer", unmetered)
            .putBoolean("scheduledTransfer", scheduled).putLong("started", System.currentTimeMillis())
            .remove("completed").remove("preparedMillis").commit()
        val downloadId = try {
            downloads.enqueue(request)
        } catch (e: RuntimeException) {
            prefs.edit().remove("enqueuing").putString("error", "Couldn’t queue the download. Try again.").commit()
            throw e
        }
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

    private data class Row(val status: Int, val bytes: Long, val reason: Int, val changedAt: Long)
    private fun waitingForNetwork(row: Row?) = prefs.getBoolean("automaticTransfer", false) &&
        (row?.status == DownloadManager.STATUS_PAUSED && row.reason in listOf(
            DownloadManager.PAUSED_QUEUED_FOR_WIFI, DownloadManager.PAUSED_WAITING_FOR_NETWORK) ||
            row?.status == DownloadManager.STATUS_PENDING && needsUnmetered)
    private fun row(): Row? {
        if (id < 0) return null
        return downloads.query(DownloadManager.Query().setFilterById(id))?.use {
            if (!it.moveToFirst()) null else Row(it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)),
                it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)),
                it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON)),
                it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_LAST_MODIFIED_TIMESTAMP)))
        }
    }

    fun snapshot(): Map<String, Any?> = synchronized(lock) {
        cleanInstalled()
        val release = target
        release?.let(::recoverEnqueue)
        val hidden = release != null && release.build == prefs.getInt("dismissed", 0)
        val ready = release != null && apk(release).isFile
        val row = row()
        val waitingForWifi = !ready && (waitingForNetwork(row) ||
            fallback && row == null && needsUnmetered && !prefs.contains("error"))
        val retrying = retryAt > 0 || row?.status == DownloadManager.STATUS_PAUSED &&
            row.reason == DownloadManager.PAUSED_WAITING_TO_RETRY
        val problem = prefs.getString("error", null) ?: when {
            id >= 0 && row == null -> "Download was removed"
            else -> null
        }
        val stage = when {
            ready -> "ready"
            problem != null -> "error"
            retrying || waitingForWifi || row?.status == DownloadManager.STATUS_FAILED -> "waiting"
            row?.status == DownloadManager.STATUS_SUCCESSFUL -> "verifying"
            row?.status == DownloadManager.STATUS_RUNNING -> "downloading"
            row != null -> "waiting"
            else -> "idle"
        }
        if (!ready) reconcileTransfer(row)
        val started = prefs.getLong("started", 0)
        val completed = prefs.getLong("completed", row?.takeIf { it.status == DownloadManager.STATUS_SUCCESSFUL }?.changedAt ?: 0)
        val elapsed = if (started > 0) ((if (completed > 0) completed else System.currentTimeMillis()) - started).coerceAtLeast(0) else null
        val downloaded = when {
            ready -> release?.download?.size
            release == null -> prefs.getLong("lastCompletedBytes", 0)
            else -> row?.bytes ?: 0L
        }
        @Suppress("DEPRECATION")
        mapOf("release" to release?.takeUnless { hidden }?.json()?.toString(), "stage" to stage,
            "received" to downloaded,
            "error" to problem, "automatic" to automatic,
            "waitingForUnmetered" to waitingForWifi, "retrying" to retrying,
            "fallback" to fallback, "lastCheck" to prefs.getLong("checkedAt", 0L),
            "transferMillis" to elapsed, "transferComplete" to (completed > 0),
            "verificationMillis" to prefs.getLong("preparedMillis", -1L),
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
        if (completed == id && completed >= 0) reconcileTransfer(row())
    }

    private fun reconcileTransfer(row: Row?) {
        if (prefs.contains("error") || row == null) return
        when {
            retryAt > 0 -> enqueueRetry()
            row.status == DownloadManager.STATUS_SUCCESSFUL || row.status == DownloadManager.STATUS_FAILED -> enqueuePreparation()
        }
    }

    private fun enqueueRetry() {
        val request = OneTimeWorkRequestBuilder<RetryUpdateWorker>()
            .setInputData(workDataOf("id" to id))
            .setInitialDelay((retryAt - System.currentTimeMillis()).coerceAtLeast(0), TimeUnit.MILLISECONDS)
            .build()
        work.enqueueUniqueWork("retry-app-update-$id", ExistingWorkPolicy.KEEP, request)
    }

    fun retry(downloadId: Long) = synchronized(lock) {
        if (id != downloadId || retryAt == 0L || row()?.status != DownloadManager.STATUS_FAILED) return@synchronized
        val release = target ?: return@synchronized
        enqueue(release, prefs.getBoolean("automaticTransfer", true), isScheduledTransfer())
    }

    private fun isScheduledTransfer() = prefs.getBoolean("scheduledTransfer", prefs.getBoolean("automaticTransfer", false))

    private fun useFallback(release: UpdateRelease) {
        val raw = release.copy(download = release.apk)
        val scheduled = isScheduledTransfer()
        clearDownload()
        prefs.edit().putString("release", raw.json().toString()).putBoolean("fallback", true).commit()
        // Queue on unmetered networks. The user can authorize a new metered transfer.
        enqueue(raw, unmetered = true, scheduled = scheduled)
    }

    private fun handleFailure(release: UpdateRelease, reason: Int) {
        when (downloadFailure(reason, release.download != release.apk, retries)) {
            DownloadFailure.RETRY -> {
                val delay = if (retries == 0) 60_000L else 300_000L
                prefs.edit().putInt("retries", retries + 1)
                    .putLong("retryAt", System.currentTimeMillis() + delay).commit()
                enqueueRetry()
            }
            DownloadFailure.FALLBACK -> useFallback(release)
            DownloadFailure.STORAGE -> prefs.edit().putString("error", "Free up storage, then retry.").commit()
            DownloadFailure.STOP -> prefs.edit().putString("error", "Couldn’t download the update. Try again.").commit()
        }
    }

    private fun enqueuePreparation() {
        val request = OneTimeWorkRequestBuilder<PrepareUpdateWorker>().setInputData(workDataOf("id" to id)).build()
        work.enqueueUniqueWork("prepare-app-update-$id", ExistingWorkPolicy.KEEP, request)
    }

    fun prepare(downloadId: Long) {
        val release = synchronized(lock) {
            if (id != downloadId || prefs.contains("error") || retryAt != 0L) return
            val download = row() ?: return
            val current = target ?: return
            if (download.status == DownloadManager.STATUS_FAILED) {
                handleFailure(current, download.reason)
                return
            }
            if (download.status != DownloadManager.STATUS_SUCCESSFUL) return
            prefs.edit().putLong("completed", download.changedAt).commit()
            current
        }
        val temporary = File(dir, "prepare-$downloadId.part")
        val started = SystemClock.elapsedRealtime()
        try {
            dir.mkdirs()
            if (!dir.isDirectory) throw IOException("Could not create the update directory")
            if (dir.usableSpace < release.apk.size) throw InsufficientUpdateSpace()
            downloads.openDownloadedFile(downloadId).let { descriptor ->
                android.os.ParcelFileDescriptor.AutoCloseInputStream(descriptor).use {
                    require(descriptor.statSize == release.download.size) { "Incomplete update download" }
                    release.unpack(it, temporary)
                }
            }
            synchronized(lock) {
                if (id != downloadId || target?.apk != release.apk) return
                kotlin.check(temporary.renameTo(apk(release))) { "Could not save the verified update" }
                prefs.edit().putLong("preparedMillis", SystemClock.elapsedRealtime() - started)
                    .putLong("lastCompletedBytes", release.download.size).commit()
                clearDownload()
                if (prefs.getInt("dismissed", 0) != release.build) UpdateNotice.show(ctx, release, apk(release))
            }
        } catch (e: Exception) {
            synchronized(lock) {
                if (id == downloadId) {
                    val invalid = e is IllegalArgumentException || e is java.util.zip.ZipException || e is java.io.EOFException
                    if (invalid && release.download != release.apk) {
                        useFallback(release)
                        return
                    } else {
                        if (invalid) clearDownload()
                        val noSpace = e is InsufficientUpdateSpace || generateSequence<Throwable>(e) { it.cause }
                            .any { it is ErrnoException && it.errno == OsConstants.ENOSPC }
                        val message = when {
                            noSpace -> "Free up storage, then retry."
                            invalid -> "The APK failed verification. Try downloading it again."
                            else -> "Couldn’t prepare the update. Try again."
                        }
                        prefs.edit().putString("error", message).commit()
                    }
                }
            }
            throw e
        } finally { temporary.delete() }
    }

    private fun clearDownload() {
        if (id >= 0) downloads.remove(id)
        prefs.edit().remove("downloadId").remove("enqueuing").remove("automaticTransfer")
            .remove("scheduledTransfer").remove("retryAt").remove("error").commit()
    }

    @Suppress("DEPRECATION")
    private fun cleanInstalled() {
        val current = target ?: return
        if (current.build <= installed.versionCode) resetTarget(keepCompletedTiming = apk(current).isFile)
    }

    private fun resetTarget(keepCompletedTiming: Boolean = false) {
        File(dir, "prepare-$id.part").delete()
        clearDownload()
        target?.let { apk(it).delete() }
        val edit = prefs.edit().remove("release").remove("dismissed").remove("retries").remove("fallback")
        if (!keepCompletedTiming) {
            edit.remove("started").remove("completed").remove("preparedMillis").remove("lastCompletedBytes")
        }
        edit.commit()
        ctx.getSystemService(android.app.NotificationManager::class.java).cancel(UpdateNotice.ID)
    }

    companion object { private val lock = Any() }
}

private class InsufficientUpdateSpace : IOException()

internal enum class DownloadFailure { RETRY, FALLBACK, STORAGE, STOP }

internal fun downloadFailure(reason: Int, compressed: Boolean, retries: Int): DownloadFailure = when {
    reason == DownloadManager.ERROR_INSUFFICIENT_SPACE -> DownloadFailure.STORAGE
    compressed && reason in listOf(404, 410) -> DownloadFailure.FALLBACK
    retries < 2 && (reason in 500..599 || reason in listOf(
        408, 429, DownloadManager.ERROR_HTTP_DATA_ERROR, DownloadManager.ERROR_CANNOT_RESUME
    )) -> DownloadFailure.RETRY
    else -> DownloadFailure.STOP
}

class RetryUpdateWorker(ctx: Context, args: WorkerParameters) : Worker(ctx, args) {
    override fun doWork(): Result {
        AndroidUpdates(applicationContext).retry(inputData.getLong("id", -1))
        return Result.success()
    }
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
