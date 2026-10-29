import 'package:flutter/services.dart';

/// iPod のクリックホイールの「カリカリ」音（Android の SoundPool で鳴らす）
class Clicker {
  static const _ch = MethodChannel('theta_music/click');

  static void prepare() => _ch.invokeMethod<void>('prepare').catchError((_) {});

  static void click({double volume = 0.6}) =>
      _ch.invokeMethod<void>('click', {'volume': volume}).catchError((_) {});
}
