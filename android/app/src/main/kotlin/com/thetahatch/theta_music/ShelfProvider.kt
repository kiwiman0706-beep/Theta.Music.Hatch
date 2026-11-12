package com.thetahatch.theta_music

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Intent
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException

/**
 * Theta Home の「棚」（Theta.Hatch.Series spec/THETA_SHARED_SETTINGS.md §4.2）。
 * authority `<applicationId>.theta`、権限 `app.thetahatch.permission.SHARE`（signature）で、
 * 共通の鍵で署名したシリーズのアプリだけが読める。
 *
 * 中身は Dart（ShelfWriter）が files/shelf/shelf.json とジャケット（files/shelf/art）に書いておくので、
 * アプリが動いていないときでも返せる。押されたら MainActivity がそのアルバムなどを再生する。
 */
class ShelfProvider : ContentProvider() {
    override fun onCreate() = true

    private fun dir() = File(context!!.filesDir, "shelf")

    override fun query(uri: Uri, projection: Array<String>?, selection: String?, args: Array<String>?, sort: String?): Cursor? {
        if (uri.pathSegments != listOf("shelf")) return null
        val c = MatrixCursor(COLUMNS)
        val f = File(dir(), "shelf.json")
        if (!f.exists()) return c
        val ctx = context!!
        val items = runCatching { JSONObject(f.readText()).optJSONArray("items") }.getOrNull() ?: return c
        for (i in 0 until items.length()) {
            val o = items.optJSONObject(i) ?: continue
            val art = o.optString("image")
            val image = if (art.isEmpty()) "" else "content://${uri.authority}/art/$art"
            val action = Intent(ctx, MainActivity::class.java)
                .setAction(MainActivity.ACTION_PLAY)
                .putExtra("kind", o.optString("kind"))
                .putExtra("key", o.optString("key"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .toUri(Intent.URI_INTENT_SCHEME)
            c.addRow(arrayOf(
                o.optString("section"), o.optString("sectionTitle"), o.optString("id"),
                o.optString("title"), o.optString("subtitle"), o.optString("text"),
                image, action, "",
            ))
        }
        c.setNotificationUri(ctx.contentResolver, uri)
        return c
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val seg = uri.pathSegments
        // art/<md5>.img だけを読み取りで出す（ほかのファイルは出さない）
        if (mode != "r" || seg.size != 2 || seg[0] != "art" || !NAME.matches(seg[1])) throw FileNotFoundException(uri.toString())
        val f = File(File(dir(), "art"), seg[1])
        if (!f.exists()) throw FileNotFoundException(uri.toString())
        return ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String? {
        val seg = uri.pathSegments
        if (seg.size == 2 && seg[0] == "art" && NAME.matches(seg[1])) {
            val f = File(File(dir(), "art"), seg[1])
            val head = runCatching { f.inputStream().use { s -> ByteArray(4).also { s.read(it) } } }.getOrNull()
            return if (head != null && head[0] == 0x89.toByte() && head[1] == 'P'.code.toByte()) "image/png" else "image/jpeg"
        }
        return if (seg == listOf("shelf")) "vnd.android.cursor.dir/vnd.thetahatch.shelf" else null
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun update(uri: Uri, values: ContentValues?, selection: String?, args: Array<String>?) = 0
    override fun delete(uri: Uri, selection: String?, args: Array<String>?) = 0

    companion object {
        val COLUMNS = arrayOf("section", "sectionTitle", "id", "title", "subtitle", "text", "image", "action", "color")
        private val NAME = Regex("^[0-9a-f]{32}\\.img$")
    }
}
