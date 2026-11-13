package app.thetahatch.music

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException

/**
 * ジャケットだけを読み取りで出す窓口（content://app.thetahatch.music.art/<md5>.img）。
 * 通知・ロック画面・Android Auto（別のアプリ）が、再生中の曲や一覧のジャケットを表示するために読む。
 * 中身はアプリのキャッシュにあるジャケット（ArtCache の cache/art）だけで、ほかのファイルは出さない。
 */
class ArtProvider : ContentProvider() {
    override fun onCreate() = true

    private fun file(uri: Uri): File {
        val seg = uri.pathSegments
        if (seg.size != 1 || !NAME.matches(seg[0])) throw FileNotFoundException(uri.toString())
        val f = File(File(context!!.cacheDir, "art"), seg[0])
        if (!f.exists()) throw FileNotFoundException(uri.toString())
        return f
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException(uri.toString())
        return ParcelFileDescriptor.open(file(uri), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String {
        val head = runCatching { file(uri).inputStream().use { s -> ByteArray(4).also { s.read(it) } } }.getOrNull()
        return if (head != null && head[0] == 0x89.toByte() && head[1] == 'P'.code.toByte()) "image/png" else "image/jpeg"
    }

    override fun query(uri: Uri, p: Array<String>?, s: String?, a: Array<String>?, o: String?): Cursor? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun update(uri: Uri, values: ContentValues?, s: String?, a: Array<String>?) = 0
    override fun delete(uri: Uri, s: String?, a: Array<String>?) = 0

    companion object {
        private val NAME = Regex("^[0-9a-f]{32}\\.img$")
    }
}
