package com.familyhealth.family_health

import android.app.*
import android.content.*
import android.os.Build
import androidx.core.content.FileProvider
import java.io.File

class UpdateFileProvider : FileProvider()

class UpdateDownloadReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val updates = AndroidUpdates(context)
        when (intent.action) {
            DownloadManager.ACTION_DOWNLOAD_COMPLETE -> updates.onComplete(intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1))
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                updates.snapshot()
                updates.schedule()
            }
        }
    }
}

internal object UpdateNotice {
    const val ID = 0x464855

    fun installIntent(ctx: Context, file: File): Intent {
        val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".updates", file)
        return Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }

    fun show(ctx: Context, release: UpdateRelease, file: File) {
        val manager = ctx.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel("app_updates", "App updates", NotificationManager.IMPORTANCE_DEFAULT)
            manager.createNotificationChannel(channel)
            Notification.Builder(ctx, channel.id)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx)
        }
        val pending = PendingIntent.getActivity(ctx, ID, installIntent(ctx, file),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        manager.notify(ID, builder.setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Family Health " + release.version + " is ready to install")
            .setContentText("Tap to open the Android installer.")
            .setContentIntent(pending).build())
    }
}
