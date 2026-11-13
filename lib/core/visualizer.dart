import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'player.dart';
import 'settings.dart';

/// オーディオビジュアライザーのデータ（Android 側は Vis.kt）。
/// 表示している所（ジャケット）があるときだけ動かす（電池のため）。
class VisualizerFeed extends ChangeNotifier {
  static const _ch = MethodChannel('theta_music/visualizer');
  static const _data = EventChannel('theta_music/visualizer/data');
  static const bandCount = 24;

  final AppSettings settings;
  final Player player;
  VisualizerFeed(this.settings, this.player) {
    settings.addListener(_update);
    player.addListener(_update);
    player.audio.androidAudioSessionIdStream.listen((_) => _restart());
  }

  /// 周波数の帯（0〜1、低い音から高い音へ）と波形（-1〜1）
  Float32List bands = Float32List(bandCount);
  Float32List wave = Float32List(64);

  int _users = 0;
  bool _running = false;
  int? _session;
  StreamSubscription<dynamic>? _sub;
  String? lastError;

  bool get enabled => settings.visualizer != 'off';

  /// 「マイク（録音）」の許可を求める。録音はしない（Android の Visualizer の決まり）
  static Future<bool> requestPermission() async {
    try {
      return await _ch.invokeMethod<bool>('request') ?? false;
    } catch (_) {
      return false;
    }
  }

  void attach() {
    _users++;
    _update();
  }

  void detach() {
    _users--;
    _update();
  }

  void _update() {
    final want = _users > 0 && enabled && player.playing;
    if (want && !_running) _start();
    if (!want && _running) _stop();
  }

  Future<void> _restart() async {
    if (!_running) return;
    await _stop();
    _update();
  }

  Future<void> _start() async {
    final session = player.audio.androidAudioSessionId;
    if (session == null) return;
    _running = true;
    try {
      if (await _ch.invokeMethod<bool>('granted') != true) {
        _running = false;
        lastError = 'マイクの許可がありません';
        return;
      }
      _sub ??= _data.receiveBroadcastStream().listen(_onData, onError: (_) {});
      final err = await _ch.invokeMethod<String>('start', {'session': session});
      if (err != null) {
        lastError = err;
        _running = false;
      } else {
        _session = session;
        lastError = null;
      }
    } catch (e) {
      lastError = '$e';
      _running = false;
    }
  }

  Future<void> _stop() async {
    _running = false;
    _session = null;
    try {
      await _ch.invokeMethod<void>('stop');
    } catch (_) {}
    bands = Float32List(bandCount);
    wave = Float32List(64);
    notifyListeners();
  }

  void _onData(dynamic e) {
    if (e is! Map || _session == null) return;
    final b = e['b'], w = e['w'];
    if (b is Uint8List) {
      final out = Float32List(bandCount);
      for (var i = 0; i < bandCount && i < b.length; i++) {
        out[i] = b[i] / 255.0;
      }
      bands = out;
    }
    if (w is Uint8List) {
      final out = Float32List(w.length);
      for (var i = 0; i < w.length; i++) {
        out[i] = (w[i] - 128) / 128.0; // Visualizer の波形は符号なし 8 ビット（128 が無音）
      }
      wave = out;
    }
    notifyListeners();
  }
}
