package com.familyhealth.family_health

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// FlutterFragmentActivity is required by local_auth (fingerprint prompt).
class MainActivity : FlutterFragmentActivity() {
    private var shareChannel: MethodChannel? = null

    /// Files shared to the app (Share → Family Health) that Flutter hasn't taken yet.
    private var pendingShare: List<Map<String, String>>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) pendingShare = readShare(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "family_health/share").also {
            it.setMethodCallHandler { call, result ->
                if (call.method == "takeShared") {
                    result.success(pendingShare)
                    pendingShare = null
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val files = readShare(intent) ?: return
        pendingShare = files
        shareChannel?.invokeMethod("shared", null)
    }

    /// Copies shared images/PDFs into the app's cache (content:// links stop working
    /// once the sharing app lets go) and returns their paths, types and names.
    private fun readShare(intent: Intent?): List<Map<String, String>>? {
        if (intent == null) return null
        val uris: List<Uri> = when (intent.action) {
            Intent.ACTION_SEND -> listOfNotNull(
                if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
            )
            Intent.ACTION_SEND_MULTIPLE ->
                (if (Build.VERSION.SDK_INT >= 33) intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)) ?: emptyList()
            else -> return null
        }
        if (uris.isEmpty()) return null
        val dir = File(cacheDir, "shared").apply { mkdirs() }
        val stamp = System.currentTimeMillis()
        return uris.mapIndexedNotNull { i, uri ->
            try {
                val mime = contentResolver.getType(uri) ?: intent.type ?: return@mapIndexedNotNull null
                if (!mime.startsWith("image/") && mime != "application/pdf") return@mapIndexedNotNull null
                val name = displayName(uri) ?: "shared_$i"
                if (mime.startsWith("image/") && mime != "image/jpeg" && mime != "image/png") {
                    // HEIC, WebP…: convert to JPEG so every step (reading, PDF) can use it.
                    val out = File(dir, "${stamp}_$i.jpg")
                    val bmp = if (Build.VERSION.SDK_INT >= 28) {
                        ImageDecoder.decodeBitmap(ImageDecoder.createSource(contentResolver, uri)) { d, _, _ -> d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE }
                    } else {
                        contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) }
                    } ?: return@mapIndexedNotNull null
                    out.outputStream().use { bmp.compress(Bitmap.CompressFormat.JPEG, 92, it) }
                    bmp.recycle()
                    return@mapIndexedNotNull mapOf("path" to out.absolutePath, "mime" to "image/jpeg", "name" to name)
                }
                val ext = if (mime == "application/pdf") "pdf" else if (mime == "image/png") "png" else "jpg"
                val out = File(dir, "${stamp}_$i.$ext")
                contentResolver.openInputStream(uri)?.use { input -> out.outputStream().use { input.copyTo(it) } } ?: return@mapIndexedNotNull null
                mapOf("path" to out.absolutePath, "mime" to mime, "name" to name)
            } catch (e: Exception) {
                android.util.Log.w("FamilyHealthShare", "Could not read shared $uri", e)
                null
            }
        }.ifEmpty { null }
    }

    private fun displayName(uri: Uri): String? =
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }

    override fun onResume() {
        super.onResume()
        preferHighRefreshRate()
    }

    /// Many Android phones keep apps at 60 Hz unless they ask for more: pick the
    /// fastest mode the screen offers at its current resolution (e.g. 120 Hz).
    private fun preferHighRefreshRate() {
        val display = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else @Suppress("DEPRECATION") windowManager.defaultDisplay) ?: return
        val current = display.mode
        val best = display.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            .maxByOrNull { it.refreshRate } ?: return
        if (window.attributes.preferredDisplayModeId == best.modeId) return
        window.attributes = window.attributes.also { it.preferredDisplayModeId = best.modeId }
    }
}
