package app.thetahatch.music

import android.media.audiofx.Visualizer
import io.flutter.plugin.common.EventChannel
import kotlin.math.hypot
import kotlin.math.log10
import kotlin.math.pow

/**
 * オーディオビジュアライザー：再生中の音（同じアプリの再生セッション）の周波数と波形を取り、Dart に送る。
 * Android の Visualizer を使うので「マイク（録音）」の許可が要る（録音はしない。音の形を読むだけ）。
 * 送るもの：b＝周波数の帯 24 本（0〜255、低い音から高い音へ、対数で並べる）、w＝波形 64 点（0〜255、128 が無音）
 */
object Vis : EventChannel.StreamHandler {
    private var v: Visualizer? = null
    private var sink: EventChannel.EventSink? = null
    private var wave = ByteArray(64) { 128.toByte() }
    const val BANDS = 24

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    /** 戻り値：null＝始めた、ほか＝始められなかった理由 */
    fun start(session: Int): String? {
        stop()
        return try {
            val vis = Visualizer(session)
            vis.captureSize = Visualizer.getCaptureSizeRange()[1].coerceAtMost(1024)
            vis.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                override fun onWaveFormDataCapture(v: Visualizer?, waveform: ByteArray, samplingRate: Int) {
                    val out = ByteArray(64)
                    val step = waveform.size / 64.0
                    for (i in 0 until 64) out[i] = waveform[(i * step).toInt()]
                    wave = out
                }

                override fun onFftDataCapture(v: Visualizer?, fft: ByteArray, samplingRate: Int) {
                    sink?.success(mapOf("b" to bands(fft), "w" to wave))
                }
            }, Visualizer.getMaxCaptureRate(), true, true)
            vis.enabled = true
            v = vis
            null
        } catch (e: Exception) {
            e.message ?: e.toString()
        }
    }

    fun stop() {
        v?.let {
            runCatching { it.enabled = false }
            it.release()
        }
        v = null
    }

    /** FFT（re,im の組）を、低い音から高い音へ対数で並べた 24 本の帯にする */
    private fun bands(fft: ByteArray): ByteArray {
        val n = fft.size / 2 // 周波数の数
        val out = ByteArray(BANDS)
        var lo = 1
        for (b in 0 until BANDS) {
            val hi = (n.toDouble().pow((b + 1).toDouble() / BANDS)).toInt().coerceIn(lo + 1, n)
            var m = 0.0
            for (k in lo until hi) {
                val re = fft[2 * k].toDouble()
                val im = fft[2 * k + 1].toDouble()
                m = maxOf(m, hypot(re, im))
            }
            val db = 20 * log10(m + 1) // 0〜約 45
            out[b] = ((db / 42.0).coerceIn(0.0, 1.0) * 255).toInt().toByte()
            lo = hi
        }
        return out
    }
}
