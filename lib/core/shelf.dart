import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'favorites.dart';
import 'library.dart';
import 'models.dart';
import 'settings.dart';

/// 最近再生したアルバム（新しい順、端末内の recent.json）
class Recents extends ChangeNotifier {
  static const max = 20;
  final List<String> albums = []; // Album.key
  Directory? dirOverride;

  Future<File> _file() async =>
      File('${(dirOverride ?? await getApplicationSupportDirectory()).path}/recent.json');

  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        albums.addAll(((jsonDecode(await f.readAsString()) as Map)['albums'] as List).cast<String>());
      }
    } catch (e) {
      debugPrint('recent load failed: $e');
    }
  }

  void played(Track t) {
    final k = t.albumKey;
    if (albums.isNotEmpty && albums.first == k) return;
    albums
      ..remove(k)
      ..insert(0, k);
    if (albums.length > max) albums.removeRange(max, albums.length);
    notifyListeners();
    _file().then((f) => f.writeAsString(jsonEncode({'albums': albums}))).catchError((Object e) {
      debugPrint('recent save failed: $e');
      return File('');
    });
  }
}

/// Theta Home の「棚」（Theta.Hatch.Series spec/THETA_SHARED_SETTINGS.md §4.2）に出す中身を書き出す。
/// Android の ShelfProvider（authority `<applicationId>.theta`）がこの shelf.json とジャケットを読んで返すので、
/// アプリが動いていないときでも Home は棚を読める。
class ShelfWriter {
  static const _ch = MethodChannel('theta_music/shelf');
  static const limit = 30;

  final AppSettings settings;
  final Library library;
  final Favorites favorites;
  final Recents recents;
  final Future<Uint8List?> Function(ArtRef ref) loadArt;
  Directory? dirOverride;

  ShelfWriter(this.settings, this.library, this.favorites, this.recents, this.loadArt);

  Timer? _debounce;

  void start() {
    for (final l in [settings, library, favorites, recents]) {
      l.addListener(schedule);
    }
    schedule();
  }

  void schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => write().catchError((Object e) => debugPrint('shelf: $e')));
  }

  static String _hash(String s) => md5.convert(utf8.encode(s)).toString();

  /// 棚の中身（並びは出したい順）。kind/key は ShelfProvider が「再生する Intent」にする
  @visibleForTesting
  List<Map<String, Object?>> entries() {
    final out = <Map<String, Object?>>[];
    Map<String, Object?> e(String section, String title, String id, String t, String sub, ArtRef? art, String kind,
            String key) =>
        {
          'section': section,
          'sectionTitle': title,
          'id': id,
          'title': t,
          'subtitle': sub,
          'text': '',
          'art': art?.key,
          'kind': kind,
          'key': key,
        };

    if (settings.shelfFavorites) {
      final songs = favorites.tracks;
      if (songs.isNotEmpty) {
        out.add(e('favorites', 'お気に入り', 'songs:favorites', 'お気に入りの曲', '${songs.length} 曲',
            songs.firstWhere((t) => t.art != null, orElse: () => songs.first).art, 'favsongs', ''));
      }
      for (final a in favorites.albums) {
        out.add(e('favorites', 'お気に入り', 'album:${_hash(a.key)}', a.title, a.artist, a.art, 'album', a.key));
      }
      for (final a in favorites.artists) {
        ArtRef? art;
        for (final al in a.albums) {
          art ??= al.art;
        }
        out.add(e('favorites', 'お気に入り', 'artist:${_hash(a.key)}', a.name, 'アーティスト · ${a.tracks.length} 曲', art,
            'artist', a.key));
      }
    }
    if (settings.shelfRecent) {
      final byKey = {for (final a in library.albums) a.key: a};
      for (final k in recents.albums) {
        final a = byKey[k];
        if (a == null) continue;
        out.add(e('recent', '最近再生', 'recent:${_hash(a.key)}', a.title, a.artist, a.art, 'album', a.key));
      }
    }
    return out.length > limit ? out.sublist(0, limit) : out;
  }

  Future<void> write() async {
    final dir = Directory('${(dirOverride ?? await getApplicationSupportDirectory()).path}/shelf');
    final artDir = Directory('${dir.path}/art');
    await artDir.create(recursive: true);
    final list = entries();
    final keep = <String>{};
    for (final it in list) {
      final key = it.remove('art') as String?;
      it['image'] = '';
      if (key == null) continue;
      // ジャケットは content://<id>.theta/art/<名前> で出す（ShelfProvider.openFile）
      final name = '${_hash(key)}.img';
      final f = File('${artDir.path}/$name');
      if (!await f.exists()) {
        final ref = _refFromKey(key);
        final data = ref == null ? null : await loadArt(ref);
        if (data == null || data.isEmpty) continue;
        await f.writeAsBytes(data);
      }
      keep.add(name);
      it['image'] = name;
    }
    final tmp = File('${dir.path}/shelf.json.tmp');
    await tmp.writeAsString(jsonEncode({'version': 1, 'items': list}));
    await tmp.rename('${dir.path}/shelf.json');
    // 使わなくなったジャケットを消す
    await for (final f in artDir.list()) {
      if (f is File && !keep.contains(f.uri.pathSegments.last)) await f.delete();
    }
    try {
      await _ch.invokeMethod<void>('changed'); // Home へ notifyChange
    } catch (_) {}
  }

  /// ArtRef.key（`path#offset:length`）から ArtRef に戻す
  static ArtRef? _refFromKey(String key) {
    final m = RegExp(r'^(.*)#(\d+):(\d+)$').firstMatch(key);
    if (m == null) return null;
    return ArtRef(m.group(1)!, offset: int.parse(m.group(2)!), length: int.parse(m.group(3)!));
  }

  /// 棚から押されたとき（MainActivity が kind/key を渡す）に、再生する曲を決める
  static (List<Track>, bool)? resolve(Library lib, Favorites fav, String kind, String key) {
    switch (kind) {
      case 'favsongs':
        final t = fav.tracks;
        return t.isEmpty ? null : (t, false);
      case 'album':
        for (final a in lib.albums) {
          if (a.key == key) return (a.tracks, false);
        }
      case 'artist':
        for (final a in lib.artists) {
          if (a.key == key) return (a.tracks, false);
        }
    }
    return null;
  }

  /// 棚から押されたときの受け口
  static void listen(void Function(String kind, String key) onPlay) {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'play') {
        final m = (call.arguments as Map).cast<String, Object?>();
        onPlay('${m['kind'] ?? ''}', '${m['key'] ?? ''}');
      }
      return null;
    });
    // アプリが棚から起動されたとき
    _ch.invokeMapMethod<String, Object?>('initial').then((m) {
      if (m != null && m['kind'] != null) onPlay('${m['kind']}', '${m['key'] ?? ''}');
    }).catchError((_) {});
  }
}
