import 'package:flutter/services.dart';

/// iPod のクリックホイールの「カリカリ」音（Android の SoundPool で鳴らす。音量はメディア音量）
class Clicker {
  static const _ch = MethodChannel('theta_music/click');

  static void prepare() => _ch.invokeMethod<void>('prepare').catchError((_) {});

  static void click({double volume = 0.8}) =>
      _ch.invokeMethod<bool>('click', {'volume': volume}).catchError((_) => false);

  /// 設定でオンにしたときの確認用。鳴らせたら true
  static Future<bool> test() async {
    try {
      // 初回は読み込みに少しかかるので、準備してから少し待って鳴らす
      await _ch.invokeMethod<void>('prepare');
      for (var i = 0; i < 5; i++) {
        if (await _ch.invokeMethod<bool>('click', {'volume': 1.0}) ?? false) return true;
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    } catch (_) {}
    return false;
  }
}
