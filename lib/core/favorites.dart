import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'library.dart';
import 'models.dart';

/// お気に入り（曲・アルバム・アーティスト）。端末内の favorites.json に保存。
/// 曲はパス、アルバムは「アーティスト＋アルバム名」、アーティストは名前で覚えるので、
/// ライブラリを更新しても（WebDAV / DS audio を切り替えても同じ曲なら）残る。
///
/// DS audio のときの曲は、Audio Station の★評価と同期する（DS audio の評価と同じもの）：
/// favRating() 個以上の★をお気に入りとみなし、登録で★5、解除で★0 を NAS に書く。
/// アルバム・アーティストは Audio Station に対応する仕組みが無いので端末内だけ。
class Favorites extends ChangeNotifier {
  final Library library;
  final int Function()? favRating; // 0 なら同期しない
  final Future<void> Function(String id, int rating)? setRating;
  Favorites(this.library, {this.favRating, this.setRating}) {
    library.addListener(() {
      _rating.clear(); // 更新後は NAS の評価をそのまま使う
      notifyListeners();
    });
  }

  /// 書き換えた評価（次にライブラリを更新するまで）
  final Map<String, int> _rating = {};

  /// NAS への★評価の保存に失敗したとき（画面でお知らせして消す）
  String? syncError;

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

  bool _synced(Track t) => t.id.isNotEmpty && setRating != null && (favRating?.call() ?? 0) > 0;
  int ratingOf(Track t) => _rating[t.path] ?? t.rating;

  bool isTrack(Track t) => _synced(t) ? ratingOf(t) >= favRating!() : _tracks.contains(t.path);
  bool isAlbum(Album a) => _albums.contains(a.key);
  bool isArtist(Artist a) => _artists.contains(a.key);

  /// 切り替えて、登録後の状態を返す
  bool toggleTrack(Track t) {
    if (!_synced(t)) return _toggle(_tracks, t.path);
    final on = !isTrack(t);
    final before = ratingOf(t);
    final r = on ? 5 : 0;
    _rating[t.path] = r;
    notifyListeners();
    setRating!(t.id, r).catchError((Object e) {
      _rating[t.path] = before;
      syncError = '★評価を NAS に保存できませんでした: $e';
      notifyListeners();
    });
    return on;
  }
  bool toggleAlbum(Album a) => _toggle(_albums, a.key);
  bool toggleArtist(Artist a) => _toggle(_artists, a.key);

  bool _toggle(Set<String> set, String key) {
    final added = set.add(key);
    if (!added) set.remove(key);
    _save();
    return added;
  }

  int get count => tracks.length + albums.length + artists.length;

  /// ライブラリにある分だけ（並びは曲名順）
  List<Track> get tracks => [for (final t in library.songs) if (isTrack(t)) t];
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
