import 'dart:async';

import 'package:flutter/foundation.dart';

import 'library.dart';
import 'models.dart';
import 'settings.dart';
import 'tags.dart';
import 'webdav.dart';

const audioExts = {'mp3', 'flac', 'm4a', 'mp4', 'aac', 'alac', 'ogg', 'opus', 'oga', 'wav', 'aiff', 'aif', 'wma'};
const _imageExts = {'jpg', 'jpeg', 'png', 'webp'};
const _preferredArt = ['cover', 'folder', 'front', 'album', 'albumart', 'albumartsmall'];

String extOf(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

/// 指定数まで並列に実行する簡易プール
Future<void> pool<T>(Iterable<T> items, int n, Future<void> Function(T) f, bool Function() cancelled) async {
  final it = items.iterator;
  Future<void> worker() async {
    while (!cancelled()) {
      T item;
      if (!it.moveNext()) return;
      item = it.current;
      await f(item);
    }
  }

  await Future.wait([for (var i = 0; i < n; i++) worker()]);
}

/// NAS のフォルダを WebDAV で巡回してライブラリを作る。
/// 前回のスキャン結果とサイズ・更新日時が同じファイルはタグを読み直さない（差分スキャン）。
class Scanner extends ChangeNotifier {
  final AppSettings settings;
  final Library library;
  Scanner(this.settings, this.library);

  bool running = false;
  bool _cancel = false;
  int dirs = 0;
  int files = 0;
  int tagsDone = 0;
  int tagsTotal = 0;
  String status = '';
  String? error;

  void cancel() => _cancel = true;

  Future<void> scan({bool full = false}) async {
    if (running) return;
    running = true;
    _cancel = false;
    dirs = files = tagsDone = tagsTotal = 0;
    error = null;
    status = 'フォルダを探索中…';
    notifyListeners();
    final dav = settings.client();
    try {
      final root = _normRoot(settings.musicPath);
      final audio = <DavEntry>[];
      final folderArt = <String, String>{};

      // 1) フォルダ巡回
      var pending = <String>[root];
      while (pending.isNotEmpty && !_cancel) {
        final next = <String>[];
        await pool<String>(pending, 4, (d) async {
          List<DavEntry> entries;
          try {
            entries = await _retry(() => dav.list(d));
          } catch (e) {
            if (d == root) rethrow;
            debugPrint('skip $d: $e');
            return;
          }
          dirs++;
          final images = <DavEntry>[];
          for (final e in entries) {
            if (e.name.startsWith('.') || e.name.startsWith('@') || e.name == '#recycle') continue;
            if (e.isDir) {
              next.add(e.path);
            } else {
              final ext = extOf(e.name);
              if (audioExts.contains(ext)) {
                audio.add(e);
                files++;
              } else if (_imageExts.contains(ext)) {
                images.add(e);
              }
            }
          }
          final art = _pickArt(images);
          if (art != null) folderArt[d] = art;
          status = d.substring(root.length).isEmpty ? '/' : d.substring(root.length);
          notifyListeners();
        }, () => _cancel);
        pending = next;
      }
      if (_cancel) throw _Cancelled();

      // 2) 差分判定
      final old = {for (final t in library.tracks) t.path: t};
      final result = <Track>[];
      final toRead = <DavEntry>[];
      for (final e in audio) {
        final o = old[e.path];
        if (!full && o != null && o.size == e.size && o.mtime == e.mtime) {
          result.add(o);
        } else {
          toRead.add(e);
        }
      }

      // 3) タグ読み取り
      tagsTotal = toRead.length;
      status = 'タグを読み取り中…';
      notifyListeners();
      await pool<DavEntry>(toRead, 6, (e) async {
        TagInfo? tag;
        if (settings.readTags) {
          final reader = RemoteReader((o, l) => _retry(() => dav.readRange(e.path, o, l)), e.size);
          tag = await readTags(reader, extOf(e.name));
        }
        result.add(_makeTrack(e, root, tag));
        tagsDone++;
        if (tagsDone % 10 == 0 || tagsDone == tagsTotal) notifyListeners();
      }, () => _cancel);
      if (_cancel) throw _Cancelled();

      // 4) 埋め込み画像のない曲にはフォルダ画像を割り当て（Disc フォルダなら親も見る）
      final finalTracks = <Track>[];
      for (final t in result) {
        if (t.artLength > 0) {
          finalTracks.add(t);
          continue;
        }
        final dir = t.folder;
        final parent = dir.substring(0, dir.lastIndexOf('/').clamp(0, dir.length));
        final art = folderArt[dir] ?? folderArt[parent];
        finalTracks.add(art == t.artPath ? t : Track.fromJson({...t.toJson(), 'ap': art}));
      }

      await library.replace(finalTracks, root);
      status = '完了: ${finalTracks.length} 曲';
    } on _Cancelled {
      status = 'キャンセルしました';
    } catch (e) {
      error = '$e';
      status = 'エラー: $e';
    } finally {
      dav.close();
      running = false;
      notifyListeners();
    }
  }

  static String _normRoot(String p) {
    var s = p.trim();
    if (!s.startsWith('/')) s = '/$s';
    while (s.length > 1 && s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static String? _pickArt(List<DavEntry> images) {
    if (images.isEmpty) return null;
    for (final p in _preferredArt) {
      for (final i in images) {
        final base = i.name.toLowerCase();
        if (base.substring(0, base.lastIndexOf('.')) == p) return i.path;
      }
    }
    images.sort((a, b) => b.size.compareTo(a.size));
    return images.first.path;
  }

  static Future<T> _retry<T>(Future<T> Function() f) async {
    for (var i = 0;; i++) {
      try {
        return await f();
      } on DavException {
        rethrow;
      } catch (_) {
        if (i >= 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 500 * (i + 1)));
      }
    }
  }

  static final _discDir = RegExp(r'^(disc|disk|cd)\s*[-_]?\s*\d+$', caseSensitive: false);
  static final _numPrefix = RegExp(r'^(?:(\d{1,2})[-.])?(\d{1,3})\s*[-._)\s]\s*(.+)$');

  /// タグが無い・足りない部分はフォルダ構成 (Artist/Album/NN Title.ext) から推測
  static Track _makeTrack(DavEntry e, String root, TagInfo? tag) {
    final rel = e.path.substring(root.length).split('/').where((s) => s.isNotEmpty).toList();
    final file = rel.isEmpty ? e.name : rel.removeLast();
    var dirs = rel;
    int disc = 0;
    if (dirs.isNotEmpty && _discDir.hasMatch(dirs.last)) {
      disc = int.tryParse(RegExp(r'\d+').firstMatch(dirs.last)!.group(0)!) ?? 0;
      dirs = dirs.sublist(0, dirs.length - 1);
    }
    final pathAlbum = dirs.isNotEmpty ? dirs.last : '';
    final pathArtist = dirs.length >= 2 ? dirs[dirs.length - 2] : '';
    var stem = file.contains('.') ? file.substring(0, file.lastIndexOf('.')) : file;
    var no = 0;
    final m = _numPrefix.firstMatch(stem);
    if (m != null) {
      if (m.group(1) != null && disc == 0) disc = int.parse(m.group(1)!);
      no = int.parse(m.group(2)!);
      stem = m.group(3)!.trim();
    }
    String pick(String? a, String b) => (a != null && a.isNotEmpty) ? a : b;
    return Track(
      path: e.path,
      size: e.size,
      mtime: e.mtime,
      title: pick(tag?.title, stem),
      artist: pick(tag?.artist, pathArtist),
      albumArtist: tag?.albumArtist ?? '',
      album: pick(tag?.album, pathAlbum),
      genre: tag?.genre ?? '',
      year: tag?.year ?? 0,
      trackNo: (tag?.trackNo ?? 0) != 0 ? tag!.trackNo : no,
      discNo: (tag?.discNo ?? 0) != 0 ? tag!.discNo : disc,
      artPath: (tag?.artLength ?? 0) > 0 ? e.path : null,
      artOffset: tag?.artOffset ?? 0,
      artLength: tag?.artLength ?? 0,
    );
  }
}

class _Cancelled implements Exception {}
