import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

int _cmp(String a, String b) {
  String k(String s) {
    final l = s.toLowerCase();
    return l.startsWith('the ') ? l.substring(4) : l;
  }

  return k(a).compareTo(k(b));
}

int compareTracks(Track a, Track b) {
  var c = a.discNo.compareTo(b.discNo);
  if (c != 0) return c;
  c = a.trackNo.compareTo(b.trackNo);
  if (c != 0) return c;
  return a.path.compareTo(b.path);
}

/// ライブラリ本体。アプリ内の library.json に保存し、起動時に読み込む。
class Library extends ChangeNotifier {
  List<Track> tracks = [];
  DateTime? scannedAt;
  String root = '';

  List<Artist> artists = [];
  List<Album> albums = [];
  List<Track> songs = [];
  Map<String, List<Track>> genres = {};

  /// テスト用に保存先を差し替え可能
  Directory? dirOverride;

  Future<File> _file() async {
    final dir = dirOverride ?? await getApplicationSupportDirectory();
    return File('${dir.path}/library.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      root = j['root'] as String? ?? '';
      final at = j['scannedAt'] as int?;
      scannedAt = at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
      tracks = [for (final t in j['tracks'] as List) Track.fromJson(t as Map<String, dynamic>)];
      _index();
      notifyListeners();
    } catch (e) {
      debugPrint('library load failed: $e');
    }
  }

  Future<void> replace(List<Track> t, String rootPath) async {
    tracks = t;
    root = rootPath;
    scannedAt = DateTime.now();
    _index();
    notifyListeners();
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'version': 1,
      'root': root,
      'scannedAt': scannedAt!.millisecondsSinceEpoch,
      'tracks': [for (final x in tracks) x.toJson()],
    }));
    await tmp.rename(f.path);
  }

  void _index() {
    final byAlbum = <String, List<Track>>{};
    for (final t in tracks) {
      (byAlbum[t.albumKey] ??= []).add(t);
    }
    albums = [
      for (final ts in byAlbum.values) Album(ts.first.displayAlbum, ts.first.groupArtist, ts..sort(compareTracks))
    ]..sort((a, b) => _cmp(a.title, b.title));

    final byArtist = <String, List<Album>>{};
    final artistName = <String, String>{};
    for (final a in albums) {
      final k = a.artist.toLowerCase();
      artistName[k] ??= a.artist;
      (byArtist[k] ??= []).add(a);
    }
    artists = [
      for (final e in byArtist.entries)
        Artist(artistName[e.key]!, e.value..sort((a, b) {
          final c = a.year.compareTo(b.year);
          return c != 0 ? c : _cmp(a.title, b.title);
        }))
    ]..sort((a, b) => _cmp(a.name, b.name));

    songs = [...tracks]..sort((a, b) => _cmp(a.title, b.title));

    final g = <String, List<Track>>{};
    for (final t in tracks) {
      final name = t.genre.isEmpty ? 'Unknown Genre' : t.genre;
      (g[name] ??= []).add(t);
    }
    final keys = g.keys.toList()..sort(_cmp);
    genres = {for (final k in keys) k: g[k]!};
  }

  /// フォルダ表示用: 指定フォルダ直下のサブフォルダと曲
  (List<String>, List<Track>) folderChildren(String dir) {
    final subs = <String>{};
    final files = <Track>[];
    final prefix = dir.endsWith('/') ? dir : '$dir/';
    for (final t in tracks) {
      if (!t.path.startsWith(prefix)) continue;
      final rest = t.path.substring(prefix.length);
      final i = rest.indexOf('/');
      if (i < 0) {
        files.add(t);
      } else {
        subs.add(rest.substring(0, i));
      }
    }
    final s = subs.toList()..sort(_cmp);
    files.sort((a, b) => a.fileName.compareTo(b.fileName));
    return (s, files);
  }
}
