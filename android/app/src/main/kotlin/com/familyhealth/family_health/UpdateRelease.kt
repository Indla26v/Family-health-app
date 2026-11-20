package com.familyhealth.family_health

import org.json.JSONObject
import java.net.URI
import java.security.MessageDigest
import java.security.DigestInputStream
import java.io.File
import java.io.InputStream
import java.util.zip.GZIPInputStream

internal const val repository = "Indla26v/family-health-app"

internal data class ReleaseAsset(val url: String, val size: Long, val hash: String) {
    fun json() = JSONObject().put("url", url).put("size", size).put("hash", hash)

    companion object {
        fun read(json: JSONObject) = ReleaseAsset(json.getString("url"), json.getLong("size"), json.getString("hash"))
    }
}

internal data class UpdateRelease(
    val version: String, val build: Int, val notes: String,
    val apk: ReleaseAsset, val download: ReleaseAsset
) {
    fun json() = JSONObject().put("version", version).put("build", build).put("notes", notes)
        .put("apk", apk.json()).put("download", download.json())

    companion object {
        fun read(json: JSONObject) = UpdateRelease(json.getString("version"), json.getInt("build"),
            json.getString("notes"), ReleaseAsset.read(json.getJSONObject("apk")), ReleaseAsset.read(json.getJSONObject("download")))

        fun select(release: JSONObject, abis: List<String>): UpdateRelease {
            val tag = release.getString("tag_name")
            val match = Regex("""v?(\d+\.\d+\.\d+)\+(\d+)""").matchEntire(tag) ?: error("Invalid release tag")
            val build = match.groupValues[2].toInt()
            require(build > 0)
            val assets = mutableMapOf<String, ReleaseAsset>()
            val list = release.getJSONArray("assets")
            for (i in 0 until list.length()) {
                val entry = list.optJSONObject(i) ?: continue
                val name = entry.optString("name")
                val digest = entry.optString("digest")
                val url = runCatching { URI(entry.getString("browser_download_url")) }.getOrNull() ?: continue
                val size = entry.optLong("size", 0)
                val suffix = "/releases/download/$tag/$name"
                if (url.scheme == "https" && url.host == "github.com" && url.userInfo == null &&
                    url.path.endsWith(suffix) && url.path.removeSuffix(suffix).equals("/$repository", ignoreCase = true) && size > 0 &&
                    digest.matches(Regex("sha256:[a-fA-F0-9]{64}"))) {
                    assets[name] = ReleaseAsset(url.toString(), size, digest.substringAfter(':').lowercase())
                }
            }
            val names = abis.map { "FamilyHealth-$it.apk" } + "FamilyHealth.apk"
            for (name in names) {
                val apk = assets[name] ?: continue
                val gzip = assets["$name.gz"]?.takeIf { it.size < apk.size }
                return UpdateRelease(match.groupValues[1], build, release.optString("body"), apk, gzip ?: apk)
            }
            error("No verified update for this device")
        }
    }

    /** Verify both published digests, bounding output even for a malformed gzip stream. */
    fun unpack(source: InputStream, output: File) {
        val payloadHash = MessageDigest.getInstance("SHA-256")
        val apkHash = MessageDigest.getInstance("SHA-256")
        val payload = DigestInputStream(source.buffered(), payloadHash)
        val decoded = if (download != apk) GZIPInputStream(payload) else payload
        var written = 0L
        val buffer = ByteArray(64 * 1024)
        decoded.use {
            output.outputStream().use { out ->
                while (true) {
                    val count = it.read(buffer)
                    if (count < 0) break
                    written += count
                    require(written <= apk.size) { "Unpacked APK exceeds published size" }
                    apkHash.update(buffer, 0, count)
                    out.write(buffer, 0, count)
                }
                require(written == apk.size && apkHash.hex() == apk.hash && payloadHash.hex() == download.hash) {
                    "Update checksum or size did not match"
                }
                out.fd.sync()
            }
        }
    }
}

private fun MessageDigest.hex() = digest().joinToString("") { "%02x".format(it) }
