import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'library.dart';
import 'models.dart';

/// お気に入り（曲・アルバム・アーティスト）。端末内の favorites.json に保存。
/// 曲はパス、アルバムは「アーティスト＋アルバム名」、アーティストは名前で覚えるので、
/// ライブラリを更新しても（WebDAV / DS audio を切り替えても同じ曲なら）残る。
class Favorites extends ChangeNotifier {
  final Library library;
  Favorites(this.library) {
    library.addListener(notifyListeners);
  }

  final Set<String> _tracks = {};
  final Set<String> _albums = {};
  final Set<String> _artists = {};

  /// テスト用に保存先を差し替え可能
  Directory? dirOverride;

  Future<File> _file() async {
    final dir = dirOverride ?? await getApplicationSupportDirectory();
    return File('${dir.path}/favorites.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _tracks.addAll((j['tracks'] as List? ?? const []).cast<String>());
      _albums.addAll((j['albums'] as List? ?? const []).cast<String>());
      _artists.addAll((j['artists'] as List? ?? const []).cast<String>());
    } catch (e) {
      debugPrint('favorites load failed: $e');
    }
  }

  Future<void> _saving = Future.value();

  /// 連続して押されても書き込みが重ならないよう、順番に保存する
  Future<void> _save() {
    notifyListeners();
    return _saving = _saving.then((_) => _write());
  }

  Future<void> _write() async {
    try {
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'version': 1,
        'tracks': _tracks.toList(),
        'albums': _albums.toList(),
        'artists': _artists.toList(),
      }));
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('favorites save failed: $e');
    }
  }

  bool isTrack(Track t) => _tracks.contains(t.path);
  bool isAlbum(Album a) => _albums.contains(a.key);
  bool isArtist(Artist a) => _artists.contains(a.key);

  /// 切り替えて、登録後の状態を返す
  bool toggleTrack(Track t) => _toggle(_tracks, t.path);
  bool toggleAlbum(Album a) => _toggle(_albums, a.key);
  bool toggleArtist(Artist a) => _toggle(_artists, a.key);

  bool _toggle(Set<String> set, String key) {
    final added = set.add(key);
    if (!added) set.remove(key);
    _save();
    return added;
  }

  int get count => _tracks.length + _albums.length + _artists.length;

  /// ライブラリにある分だけ（並びは曲名順）
  List<Track> get tracks => [for (final t in library.songs) if (_tracks.contains(t.path)) t];
  List<Album> get albums => [for (final a in library.albums) if (_albums.contains(a.key)) a];
  List<Artist> get artists => [for (final a in library.artists) if (_artists.contains(a.key)) a];

  /// お気に入りの曲＋お気に入りのアルバム・アーティストの全曲（重複なし）
  List<Track> get allTracks {
    final seen = <String>{};
    final out = <Track>[];
    void add(Iterable<Track> ts) {
      for (final t in ts) {
        if (seen.add(t.path)) out.add(t);
      }
    }

    add(tracks);
    for (final a in albums) {
      add(a.tracks);
    }
    for (final a in artists) {
      add(a.tracks);
    }
    return out;
  }
}
