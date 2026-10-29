import 'package:flutter/services.dart';

/// Android の音声入力（RecognizerIntent / Google の音声入力画面）を呼ぶ。
/// マイクの権限はアプリには要らない（音声入力アプリが持っている）。
class Voice {
  static const _ch = MethodChannel('theta_music/voice');

  /// 認識した候補（最大 5 つ）。キャンセルなら null。音声入力が使えない端末では VoiceUnavailable
  static Future<List<String>?> listen({String prompt = '曲名・アルバム・アーティスト'}) async {
    try {
      final r = await _ch.invokeListMethod<String>('listen', {'prompt': prompt, 'lang': 'ja-JP'});
      if (r == null || r.isEmpty) return null;
      return r;
    } on PlatformException catch (e) {
      if (e.code == 'unavailable') throw VoiceUnavailable(e.message ?? '');
      rethrow;
    } on MissingPluginException {
      throw VoiceUnavailable('この環境では音声入力を使えません');
    }
  }
}

class VoiceUnavailable implements Exception {
  final String message;
  VoiceUnavailable(this.message);
  @override
  String toString() => '音声入力を使えません（Google アプリの音声入力を有効にしてください）';
}
