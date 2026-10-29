package com.thetahatch.theta_music

import android.content.ActivityNotFoundException
import android.content.Intent
import android.media.AudioAttributes
import android.media.SoundPool
import android.speech.RecognizerIntent
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin
import kotlin.random.Random
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * バックグラウンド再生（audio_service）の Activity に、音声入力とクリック音を足したもの。
 * 音声入力は端末の音声入力アプリ（Google）に任せるので、このアプリにマイクの権限は要らない。
 * クリック音（iPod のカリカリ）は SoundPool で鳴らす。SoundPool は音声フォーカスを取らないので、再生中の音楽は止めない。
 * 音量は「メディア」の音量に従う（システム音扱いだと、マナーモードやタッチ音オフで鳴らない端末があるため）。
 */
class MainActivity : AudioServiceActivity() {
    private var pending: MethodChannel.Result? = null
    private var pool: SoundPool? = null
    private var clickId = 0
    private var clickReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "theta_music/click").setMethodCallHandler { call, result ->
            when (call.method) {
                "click" -> {
                    val v = (call.argument<Double>("volume") ?: 0.8).toFloat()
                    clickPool()
                    // 戻り値: 鳴らせたか（読み込み前・失敗なら false）
                    val stream = if (clickReady) pool?.play(clickId, v, v, 1, 0, 1f) ?: 0 else 0
                    result.success(stream != 0)
                }
                "prepare" -> {
                    clickPool()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "theta_music/voice").setMethodCallHandler { call, result ->
            if (call.method != "listen") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            pending?.success(null)
            pending = result
            val lang = call.argument<String>("lang") ?: "ja-JP"
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, lang)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, lang)
                // 英語のアーティスト名もカタカナにされにくいように
                putExtra("android.speech.extra.EXTRA_ADDITIONAL_LANGUAGES", arrayOf("en-US"))
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
                putExtra(RecognizerIntent.EXTRA_PROMPT, call.argument<String>("prompt") ?: "")
            }
            try {
                @Suppress("DEPRECATION")
                startActivityForResult(intent, REQ_VOICE)
            } catch (e: ActivityNotFoundException) {
                pending = null
                result.error("unavailable", e.message, null)
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_VOICE) {
            val r = pending
            pending = null
            r?.success(
                if (resultCode == RESULT_OK) data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS) ?: arrayListOf<String>()
                else null,
            )
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    /** 初回だけ、短いクリック音を作って SoundPool に読み込む */
    private fun clickPool() {
        if (pool != null) return
        val p = SoundPool.Builder()
            .setMaxStreams(4)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .build()
        p.setOnLoadCompleteListener { _, _, status -> clickReady = status == 0 }
        pool = p
        val f = File(cacheDir, "ipod_click_v2.wav")
        if (!f.exists()) writeClick(f)
        clickId = p.load(f.path, 1)
    }

    override fun onDestroy() {
        pool?.release()
        pool = null
        super.onDestroy()
    }

    companion object {
        private const val REQ_VOICE = 4101
        private const val RATE = 44100

        /**
         * iPod のクリックホイールの「チッ」：ノイズと高い音を数 ms で減衰させる。
         * Android は鳴り始めの数 ms の音量をゆっくり上げるので、頭に無音を置いてから鳴らす
         * （無音が無いと、短い音はほとんど聞こえなくなる）。
         */
        private fun writeClick(f: File) {
            val lead = RATE * 15 / 1000
            val n = lead + RATE * 30 / 1000
            val rnd = Random(7)
            val pcm = ShortArray(n) { i ->
                if (i < lead) return@ShortArray 0
                val t = (i - lead).toDouble() / RATE
                val env = exp(-t / 0.0025)
                val v = (rnd.nextDouble() * 2 - 1) * 0.5 + sin(2 * PI * 3200 * t) * 0.35 + sin(2 * PI * 1600 * t) * 0.15
                (v * env * 0.95 * Short.MAX_VALUE).toInt().coerceIn(-32767, 32767).toShort()
            }
            val data = n * 2
            val b = ByteBuffer.allocate(44 + data).order(ByteOrder.LITTLE_ENDIAN)
            b.put("RIFF".toByteArray()).putInt(36 + data).put("WAVE".toByteArray())
            b.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(1).putInt(RATE).putInt(RATE * 2).putShort(2).putShort(16)
            b.put("data".toByteArray()).putInt(data)
            pcm.forEach { b.putShort(it) }
            FileOutputStream(f).use { it.write(b.array()) }
        }
    }
}
