package com.thetahatch.theta_music

import android.content.ActivityNotFoundException
import android.content.Intent
import android.speech.RecognizerIntent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * バックグラウンド再生（audio_service）の Activity に、音声入力の呼び出しを足したもの。
 * 音声入力は端末の音声入力アプリ（Google）に任せるので、このアプリにマイクの権限は要らない。
 */
class MainActivity : AudioServiceActivity() {
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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

    companion object {
        private const val REQ_VOICE = 4101
    }
}
