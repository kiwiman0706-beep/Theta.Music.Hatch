import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:just_audio/just_audio.dart';

import 'art_cache.dart';
import 'favorites.dart';
import 'library.dart';
import 'models.dart';
import 'player.dart';
import 'search.dart';
import 'settings.dart';
import 'shelf.dart';

/// ジャケットを Android（通知・ロック画面・Android Auto）に渡す窓口（ArtProvider.kt）
const artAuthority = 'app.thetahatch.music.art';

/// Android に「再生中の曲」を知らせ、通知・ロック画面・Bluetooth・Android Auto から操作できるようにする。
/// Android Auto には曲の一覧（お気に入り・最近再生・アーティスト・アルバム）と検索を返す。
class MediaHandler extends BaseAudioHandler with SeekHandler {
  final Player player;
  final Library library;
  final Favorites favorites;
  final Recents recents;
  final ArtCache art;
  final AppSettings settings;

  MediaHandler(this.player, this.library, this.favorites, this.recents, this.art, this.settings) {
    final a = player.audio;
    a.playbackEventStream.listen((_) => _broadcast(), onError: (Object _, StackTrace _) {});
    a.playingStream.listen((_) => _broadcast());
    a.durationStream.listen((_) => _publishItem());
    player.addListener(_onPlayer);
  }

  String? _lastPath;
  int _lastLength = -1;

  void _onPlayer() {
    final t = player.current;
    if (t?.path != _lastPath) {
      _lastPath = t?.path;
      _publishItem();
      if (t?.art != null) {
        // ジャケットがまだ端末に無ければ取ってきて、もう一度知らせる
        art.load(t!.art!).then((_) {
          if (player.current?.path == t.path) _publishItem();
        });
      }
    }
    if (player.queue.length != _lastLength) {
      _lastLength = player.queue.length;
      queue.add([for (final q in player.queue) _item(q)]);
    }
    _broadcast();
  }

  // ------------------------------------------------------------ 再生中の曲と状態

  MediaItem _item(Track t, {Duration? duration}) => MediaItem(
        id: t.path,
        title: t.title,
        artist: t.displayArtist,
        album: t.displayAlbum,
        genre: t.genre.isEmpty ? null : t.genre,
        duration: duration,
        artUri: _artUri(t.art),
        playable: true,
      );

  /// 端末にジャケットがあるときだけ content:// の URI（Android Auto もこれで読める）
  Uri? _artUri(ArtRef? ref) {
    if (ref == null || art.peek(ref) == null) return null;
    final name = '${md5.convert(utf8.encode(ref.key))}.img';
    return Uri.parse('content://$artAuthority/$name');
  }

  void _publishItem() {
    final t = player.current;
    if (t == null) return;
    mediaItem.add(_item(t, duration: player.audio.duration));
  }

  void _broadcast() {
    final a = player.audio;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (a.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (a.processingState) {
        ProcessingState.idle => player.hasQueue ? AudioProcessingState.ready : AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: a.playing,
      updatePosition: a.position,
      bufferedPosition: a.bufferedPosition,
      speed: a.speed,
      queueIndex: player.index < 0 ? null : player.index,
      shuffleMode: settings.shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      repeatMode: switch (settings.repeat) {
        RepeatSetting.off => AudioServiceRepeatMode.none,
        RepeatSetting.one => AudioServiceRepeatMode.one,
        RepeatSetting.all => AudioServiceRepeatMode.all,
      },
    ));
  }

  // ------------------------------------------------------------ 操作（通知・ロック画面・Bluetooth・車）

  @override
  Future<void> play() async {
    if (!player.hasQueue) {
      // 何も入っていない：最近のアルバム、無ければ全曲シャッフル
      final r = _recentAlbum();
      if (r != null) return player.playList(r.tracks, 0);
      if (library.songs.isNotEmpty) return player.playList(library.songs, 0, shuffle: true);
      return;
    }
    if (!player.audio.playing) await player.toggle();
  }

  @override
  Future<void> pause() => player.audio.pause();

  @override
  Future<void> stop() async {
    await player.audio.pause();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => player.audio.seek(position);

  @override
  Future<void> skipToNext() => player.next();

  @override
  Future<void> skipToPrevious() => player.previous();

  @override
  Future<void> skipToQueueItem(int index) => player.jumpTo(index);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    settings.repeat = switch (repeatMode) {
      AudioServiceRepeatMode.none => RepeatSetting.off,
      AudioServiceRepeatMode.one => RepeatSetting.one,
      _ => RepeatSetting.all,
    };
    await settings.save();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    settings.shuffle = shuffleMode != AudioServiceShuffleMode.none;
    await settings.save();
  }

  // ------------------------------------------------------------ Android Auto の一覧

  static const _favorites = 'favorites', _recent = 'recent_albums', _artists = 'artists', _albums = 'albums';
  static const _shuffleAll = 'play:shuffle', _favSongs = 'play:favsongs';

  static String _h(String key) => md5.convert(utf8.encode(key)).toString();

  Album? _album(String hash) {
    for (final a in library.albums) {
      if (_h(a.key) == hash) return a;
    }
    return null;
  }

  Artist? _artist(String hash) {
    for (final a in library.artists) {
      if (_h(a.key) == hash) return a;
    }
    return null;
  }

  Album? _recentAlbum() {
    for (final k in recents.albums) {
      for (final a in library.albums) {
        if (a.key == k) return a;
      }
    }
    return null;
  }

  MediaItem _folder(String id, String title, {String? sub}) =>
      MediaItem(id: id, title: title, displaySubtitle: sub, playable: false);

  MediaItem _albumItem(Album a) => MediaItem(
        id: 'album:${_h(a.key)}',
        title: a.title,
        artist: a.artist,
        displaySubtitle: a.artist,
        artUri: _artUri(a.art),
        playable: true,
      );

  MediaItem _artistItem(Artist a) {
    ArtRef? ref;
    for (final al in a.albums) {
      ref ??= al.art;
    }
    return MediaItem(
      id: 'artist:${_h(a.key)}',
      title: a.name,
      displaySubtitle: '${a.albums.length} アルバム',
      artUri: _artUri(ref),
      playable: false,
    );
  }

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    switch (parentMediaId) {
      case AudioService.browsableRootId:
        return [
          _folder(_favorites, 'お気に入り'),
          _folder(_recent, '最近再生'),
          _folder(_artists, 'アーティスト', sub: '${library.artists.length}'),
          _folder(_albums, 'アルバム', sub: '${library.albums.length}'),
          const MediaItem(id: _shuffleAll, title: '全曲シャッフル', playable: true),
        ];
      case AudioService.recentRootId:
        // 車の「最近」：最後に聴いたアルバム
        final a = _recentAlbum();
        return a == null ? [] : [_albumItem(a)];
      case _favorites:
        return [
          if (favorites.tracks.isNotEmpty)
            MediaItem(id: _favSongs, title: 'お気に入りの曲', displaySubtitle: '${favorites.tracks.length} 曲', playable: true),
          for (final a in favorites.albums) _albumItem(a),
          for (final a in favorites.artists) _artistItem(a),
        ];
      case _recent:
        final byKey = {for (final a in library.albums) a.key: a};
        return [
          for (final k in recents.albums)
            if (byKey[k] != null) _albumItem(byKey[k]!),
        ];
      case _artists:
        return [for (final a in library.artists) _artistItem(a)];
      case _albums:
        return [for (final a in library.albums.take(800)) _albumItem(a)];
    }
    if (parentMediaId.startsWith('artist:')) {
      final a = _artist(parentMediaId.substring(7));
      if (a == null) return [];
      return [
        MediaItem(id: 'play:artist:${_h(a.key)}', title: 'すべての曲', displaySubtitle: '${a.tracks.length} 曲', playable: true),
        for (final al in a.albums) _albumItem(al),
      ];
    }
    return [];
  }

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    if (mediaId == _shuffleAll) {
      if (library.songs.isNotEmpty) await player.playList(library.songs, 0, shuffle: true);
    } else if (mediaId == _favSongs) {
      final t = favorites.tracks;
      if (t.isNotEmpty) await player.playList(t, 0);
    } else if (mediaId.startsWith('album:')) {
      final a = _album(mediaId.substring(6));
      if (a != null) await player.playList(a.tracks, 0);
    } else if (mediaId.startsWith('play:artist:')) {
      final a = _artist(mediaId.substring(12));
      if (a != null) await player.playList(a.tracks, 0);
    } else {
      // キューの中の曲（パス）
      final i = player.queue.indexWhere((t) => t.path == mediaId);
      if (i >= 0) await player.jumpTo(i);
    }
  }

  /// 車の音声操作「〇〇を再生」：アプリの検索でいちばん近いもの。何も言わなければ全曲シャッフル
  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) async {
    if (query.trim().isEmpty) return playFromMediaId(_shuffleAll);
    final r = searchVoice(library, [query]);
    final best = r?.$1.best;
    if (best == null) return;
    final (list, i) = best.playable;
    await player.playList(list, i, shuffle: r!.$2.shuffle);
  }

  @override
  Future<List<MediaItem>> search(String query, [Map<String, dynamic>? extras]) async {
    final r = searchVoice(library, [query])?.$1;
    if (r == null) return [];
    return [
      for (final a in r.albums.take(20)) _albumItem(a),
      for (final a in r.artists.take(10)) _artistItem(a),
    ];
  }
}
