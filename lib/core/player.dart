import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'art_cache.dart';
import 'dsaudio.dart';
import 'models.dart';
import 'settings.dart';

/// 再生制御。just_audio (ExoPlayer) で NAS から直接ストリーミング。
/// ネットワーク断などのエラー時は同じ位置から自動で再接続を試みる。
class Player extends ChangeNotifier {
  final AppSettings settings;
  final ArtCache art;
  final DsAudioClient ds;
  // Android ではヘッダーを ExoPlayer に直接渡す（ローカルプロキシを使わない）
  final AudioPlayer audio = AudioPlayer(useProxyForRequestHeaders: false);

  List<Track> queue = [];
  int index = -1;
  String? lastError;
  int _retries = 0;
  double volume = 1.0;

  Player(this.settings, this.art, this.ds) {
    audio.currentIndexStream.listen((i) {
      if (i != null && i != index) {
        index = i;
        _retries = 0;
        notifyListeners();
      }
    });
    audio.playerStateStream.listen((_) => notifyListeners());
    audio.playbackEventStream.listen((_) {}, onError: (Object e, StackTrace st) => _onError(e));
    _applyModes();
    settings.addListener(_applyModes);
  }

  Track? get current => (index >= 0 && index < queue.length) ? queue[index] : null;
  bool get playing => audio.playing;
  bool get hasQueue => queue.isNotEmpty;

  void _applyModes() {
    audio.setLoopMode(switch (settings.repeat) {
      RepeatSetting.off => LoopMode.off,
      RepeatSetting.one => LoopMode.one,
      RepeatSetting.all => LoopMode.all,
    });
  }

  Future<AudioSource> _source(Track t) async {
    Uri uri;
    Map<String, String> headers;
    if (t.id.isNotEmpty) {
      // Audio Station: セッション ID を URL に含める
      final name = t.path.substring(t.path.lastIndexOf('/') + 1);
      final ext = name.contains('.') ? name.substring(name.lastIndexOf('.') + 1).toLowerCase() : '';
      uri = await ds.streamUri(t.id, ext);
      headers = const {};
    } else {
      final dav = settings.client();
      uri = dav.uriFor(t.path);
      headers = dav.authHeaders;
      dav.close();
    }
    return AudioSource.uri(uri,
        headers: headers,
        tag: MediaItem(
          id: t.path,
          title: t.title,
          artist: t.displayArtist,
          album: t.displayAlbum,
          artUri: await art.fileUriIfCached(t.art),
        ));
  }

  Future<void> playList(List<Track> tracks, int start, {bool shuffle = false}) async {
    if (tracks.isEmpty) return;
    var list = [...tracks];
    var startIndex = start.clamp(0, list.length - 1);
    if (shuffle) {
      // 全曲シャッフル: 巨大キューを避けるため 500 曲まで
      list.shuffle(Random());
      if (list.length > 500) list = list.sublist(0, 500);
      startIndex = 0;
    } else if (settings.shuffle) {
      final first = list.removeAt(startIndex);
      list.shuffle(Random());
      list.insert(0, first);
      startIndex = 0;
    }
    queue = list;
    index = startIndex;
    lastError = null;
    _retries = 0;
    notifyListeners();
    await _load(startIndex, Duration.zero, play: true);
  }

  Future<void> _load(int i, Duration pos, {required bool play}) async {
    try {
      final sources = await Future.wait(queue.map(_source));
      await audio.setAudioSources(sources, initialIndex: i, initialPosition: pos);
      if (play) unawaited(audio.play());
    } catch (e) {
      _onError(e);
    }
  }

  void _onError(Object e) {
    lastError = '$e';
    debugPrint('player error: $e');
    notifyListeners();
    if (queue.isEmpty || _retries >= 3) return;
    _retries++;
    if (current?.id.isNotEmpty ?? false) ds.reset(); // セッション切れかもしれないのでログインし直す
    final pos = audio.position;
    final i = index;
    Future<void>.delayed(Duration(seconds: 2 * _retries), () => _load(i, pos, play: true));
  }

  Future<void> toggle() async {
    if (!hasQueue) return;
    if (audio.playing) {
      await audio.pause();
    } else {
      if (audio.processingState == ProcessingState.idle) {
        await _load(index, audio.position, play: true);
      } else {
        unawaited(audio.play());
      }
    }
  }

  Future<void> jumpTo(int i) async {
    if (i < 0 || i >= queue.length) return;
    await audio.seek(Duration.zero, index: i);
    if (!audio.playing) unawaited(audio.play());
  }

  Future<void> next() async {
    if (audio.hasNext) await audio.seekToNext();
  }

  Future<void> previous() async {
    if (audio.position > const Duration(seconds: 3) || !audio.hasPrevious) {
      await audio.seek(Duration.zero);
    } else {
      await audio.seekToPrevious();
    }
  }

  Future<void> seekBy(Duration d) async {
    final dur = audio.duration ?? Duration.zero;
    var p = audio.position + d;
    if (p < Duration.zero) p = Duration.zero;
    if (dur > Duration.zero && p > dur) p = dur - const Duration(milliseconds: 500);
    await audio.seek(p);
  }

  void changeVolume(double delta) {
    volume = (volume + delta).clamp(0.0, 1.0);
    audio.setVolume(volume);
    notifyListeners();
  }
}
