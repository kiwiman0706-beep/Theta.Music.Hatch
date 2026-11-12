import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'favorites.dart';
import 'library.dart';
import 'models.dart';
import 'note_store.dart';
import 'scanner.dart' show pool;
import 'settings.dart';

const _begin = '<!-- theta-music:begin (この区間は自動生成。外側に書いたメモは保持されます) -->';
const _end = '<!-- theta-music:end -->';
const _managedKeys = {
  'theta', 'id', 'type', 'artist', 'album', 'year', 'genre', 'tracks', 'nas_path', 'tags', 'albums', 'songs',
  'updated', 'favorite', 'favorite_songs'
};

/// 既定の書き出し先：NAS の共有フォルダ Obsidian の Theta Vault の中の Music
/// （Theta.Hatch.Series spec/THETA_VAULT_SPEC.md「NAS の置き場所」）
const defaultVaultMusic = '/Obsidian/Theta Vault/Music';

/// Vault の中で同じものを見分ける id。アルバム・アーティストの名前から決まるので、
/// どの端末で書き出しても、ライブラリを作り直しても同じになる（UUID の形）
String stableId(String kind, String key) {
  final h = md5.convert(utf8.encode('music/$kind:$key')).toString();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// 曲のフォルダ（/music/…）を Vault から参照する形（nas://music/…）に
String nasPath(String folder) => 'nas:/${folder.startsWith('/') ? folder : '/$folder'}';

/// Obsidian Bases（.base）の一覧。無いときだけ作る（利用者が直したらそちらが優先）
String _albumsBase(String folder) => '''filters:
  and:
    - file.inFolder("$folder/Albums")
properties:
  note.album:
    displayName: アルバム
  note.artist:
    displayName: アーティスト
  note.year:
    displayName: 年
  note.genre:
    displayName: ジャンル
  note.tracks:
    displayName: 曲数
  note.favorite:
    displayName: お気に入り
views:
  - type: table
    name: アルバム
    order:
      - note.album
      - note.artist
      - note.year
      - note.genre
      - note.tracks
      - note.favorite
    sort:
      - property: note.artist
        direction: ASC
      - property: note.year
        direction: ASC
  - type: table
    name: お気に入り
    filters:
      and:
        - note.favorite == true
    order:
      - note.album
      - note.artist
      - note.year
''';

String _artistsBase(String folder) => '''filters:
  and:
    - file.inFolder("$folder/Artists")
properties:
  file.name:
    displayName: アーティスト
  note.albums:
    displayName: アルバム数
  note.songs:
    displayName: 曲数
  note.favorite:
    displayName: お気に入り
views:
  - type: table
    name: アーティスト
    order:
      - file.name
      - note.albums
      - note.songs
      - note.favorite
''';

String safeName(String s) {
  final r = s.replaceAll(RegExp(r'[\\/:*?"<>|#^\[\]]'), '_').trim();
  return r.isEmpty ? '_' : (r.length > 120 ? r.substring(0, 120) : r);
}

String _yamlStr(String s) => '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

String _albumFile(Album a) => 'Albums/${safeName('${a.artist} - ${a.title}')}';
String _artistFile(String name) => 'Artists/${safeName(name)}';

/// ライブラリを Obsidian Vault 向け Markdown として NAS（WebDAV）に書き出す。
/// 既存ノートは自動生成区間とフロントマターの管理キーだけ更新し、手書きメモは残す。
class ObsidianExporter extends ChangeNotifier {
  final AppSettings settings;
  final Library library;
  final NoteStore Function() store; // WebDAV か File Station
  final Favorites? favorites;
  ObsidianExporter(this.settings, this.library, this.store, {this.favorites});

  bool running = false;
  int done = 0;
  int total = 0;
  String status = '';

  Future<void> export() async {
    if (running) return;
    final base = _base();
    // Vault の中でのフォルダ名（リンクは Vault のルートから：[[Music/Albums/…]]）
    final folder = base.substring(base.lastIndexOf('/') + 1);
    String albumNote(Album a) => '$folder/${_albumFile(a)}';
    String artistNote(String name) => '$folder/${_artistFile(name)}';
    running = true;
    done = 0;
    status = '書き出し中…';
    final now = DateTime.now().toIso8601String().substring(0, 10);
    final notes = <String, (Map<String, String>, String)>{};

    for (final a in library.albums) {
      final fm = <String, String>{
        'theta': 'music/album@1',
        'id': stableId('album', a.key),
        'type': 'album',
        'artist': _yamlStr('[[${artistNote(a.artist)}|${a.artist}]]'),
        'album': _yamlStr(a.title),
        if (a.year != 0) 'year': '${a.year}',
        if (a.genre.isNotEmpty) 'genre': _yamlStr(a.genre),
        'tracks': '${a.tracks.length}',
        'nas_path': _yamlStr(nasPath(a.tracks.first.folder)),
        'tags': (favorites?.isAlbum(a) ?? false) ? '[music/album, music/favorite]' : '[music/album]',
        if (favorites?.isAlbum(a) ?? false) 'favorite': 'true',
        if (a.tracks.any((t) => favorites?.isTrack(t) ?? false))
          'favorite_songs': '${a.tracks.where((t) => favorites!.isTrack(t)).length}',
        'updated': now,
      };
      final b = StringBuffer()
        ..writeln('# ${a.title}')
        ..writeln()
        ..writeln('**Artist:** [[${artistNote(a.artist)}|${a.artist}]]${a.year != 0 ? '  ·  **Year:** ${a.year}' : ''}')
        ..writeln()
        ..writeln('| # | Title | Artist |')
        ..writeln('|---|---|---|');
      for (final t in a.tracks) {
        final no = t.discNo > 0 ? '${t.discNo}-${t.trackNo}' : '${t.trackNo == 0 ? '' : t.trackNo}';
        final star = (favorites?.isTrack(t) ?? false) ? '★ ' : '';
        b.writeln('| $no | $star${t.title.replaceAll('|', '\\|')} | ${t.displayArtist.replaceAll('|', '\\|')} |');
      }
      notes['${_albumFile(a)}.md'] = (fm, b.toString());
    }

    for (final ar in library.artists) {
      final fm = <String, String>{
        'theta': 'music/artist@1',
        'id': stableId('artist', ar.key),
        'type': 'artist',
        'albums': '${ar.albums.length}',
        'songs': '${ar.tracks.length}',
        'tags': (favorites?.isArtist(ar) ?? false) ? '[music/artist, music/favorite]' : '[music/artist]',
        if (favorites?.isArtist(ar) ?? false) 'favorite': 'true',
        'updated': now,
      };
      final b = StringBuffer()
        ..writeln('# ${ar.name}')
        ..writeln()
        ..writeln('## Albums');
      for (final a in ar.albums) {
        b.writeln('- [[${albumNote(a)}|${a.title}]]${a.year != 0 ? ' (${a.year})' : ''}');
      }
      notes['${_artistFile(ar.name)}.md'] = (fm, b.toString());
    }

    final idx = StringBuffer()
      ..writeln('# Music Library')
      ..writeln()
      ..writeln('- Songs: ${library.tracks.length}')
      ..writeln('- Albums: ${library.albums.length}')
      ..writeln('- Artists: ${library.artists.length}')
      ..writeln('- Scanned: ${library.scannedAt?.toIso8601String() ?? '-'}')
      ..writeln()
      ..writeln('## 一覧（Obsidian Bases）')
      ..writeln()
      ..writeln('![[$folder/アルバム.base]]')
      ..writeln()
      ..writeln('- [[$folder/アーティスト.base|アーティスト]]')
      ..writeln()
      ..writeln('## Artists');
    for (final ar in library.artists) {
      idx.writeln('- [[${artistNote(ar.name)}|${ar.name}]]');
    }
    notes['Music Library.md'] = ({'theta': 'music/index@1', 'type': 'index', 'updated': now}, idx.toString());

    total = notes.length;
    notifyListeners();
    final dav = store();
    var errors = 0;
    try {
      await dav.mkdirs('$base/Albums');
      await dav.mkdirs('$base/Artists');
      // 一覧（.base）は無いときだけ作る
      for (final (name, text) in [('アルバム.base', _albumsBase(folder)), ('アーティスト.base', _artistsBase(folder))]) {
        if (await dav.getText('$base/$name') == null) await dav.putText('$base/$name', text);
      }
      await _registerInVault(dav, base);
      await pool<MapEntry<String, (Map<String, String>, String)>>(notes.entries, 4, (e) async {
        final path = '$base/${e.key}';
        try {
          final existing = await dav.getText(path);
          await dav.putText(path, merge(existing, e.value.$1, e.value.$2));
        } catch (err) {
          errors++;
          debugPrint('obsidian: $path $err');
        }
        done++;
        if (done % 10 == 0 || done == total) notifyListeners();
      }, () => false);
      status = errors == 0 ? '完了: $total ノート' : '完了 (失敗 $errors 件)';
    } catch (e) {
      status = 'エラー: $e';
    } finally {
      dav.close();
      running = false;
      notifyListeners();
    }
  }

  String _base() {
    final p = settings.obsidianPath.trim().replaceAll(RegExp(r'/+$'), '');
    return p.isEmpty ? defaultVaultMusic : p;
  }

  /// Vault のルートの .theta/vault.json の apps に music を足す（無ければ作る）
  Future<void> _registerInVault(NoteStore dav, String base) async {
    final root = base.substring(0, base.lastIndexOf('/'));
    if (root.isEmpty) return;
    try {
      final path = '$root/.theta/vault.json';
      final text = await dav.getText(path);
      Map<String, dynamic> j = {'spec': 1, 'apps': <String>[]};
      if (text != null) j = (jsonDecode(text) as Map).cast<String, dynamic>();
      final apps = [...((j['apps'] as List?) ?? const []).map((e) => '$e')];
      if (apps.contains('music') && text != null) return;
      if (!apps.contains('music')) apps.add('music');
      j['apps'] = apps;
      j['spec'] ??= 1;
      await dav.mkdirs('$root/.theta');
      await dav.putText(path, const JsonEncoder.withIndent('  ').convert(j));
    } catch (e) {
      debugPrint('vault.json: $e'); // 読めない形なら触らない
    }
  }

  /// Vault のノートからお気に入りを戻す（新しい端末・入れ直したとき）。
  /// favorite: true のアルバム・アーティストと、曲の表で ★ の付いた曲。戻した数を返す
  Future<int> restoreFavorites() async {
    final fav = favorites;
    if (fav == null || running) return 0;
    running = true;
    done = 0;
    total = library.albums.length + library.artists.length;
    status = 'Vault からお気に入りを読み込み中…';
    notifyListeners();
    final base = _base();
    final dav = store();
    var restored = 0;
    bool favoriteIn(String text) => RegExp(r'^favorite:\s*true\s*$', multiLine: true).hasMatch(_frontmatter(text));
    try {
      await pool<Album>(library.albums, 4, (a) async {
        try {
          final text = await dav.getText('$base/${_albumFile(a)}.md');
          if (text != null) {
            if (favoriteIn(text) && !fav.isAlbum(a)) {
              fav.toggleAlbum(a);
              restored++;
            }
            for (final m in RegExp(r'^\|[^|]*\|\s*★ (.+?)\s*\|', multiLine: true).allMatches(text)) {
              final title = m.group(1)!.replaceAll(r'\|', '|');
              for (final t in a.tracks) {
                if (t.title == title && !fav.isTrack(t)) {
                  fav.toggleTrack(t);
                  restored++;
                }
              }
            }
          }
        } catch (_) {}
        done++;
        if (done % 10 == 0) notifyListeners();
      }, () => false);
      await pool<Artist>(library.artists, 4, (ar) async {
        try {
          final text = await dav.getText('$base/${_artistFile(ar.name)}.md');
          if (text != null && favoriteIn(text) && !fav.isArtist(ar)) {
            fav.toggleArtist(ar);
            restored++;
          }
        } catch (_) {}
        done++;
        if (done % 10 == 0) notifyListeners();
      }, () => false);
      status = '完了: お気に入りを $restored 件戻しました';
    } catch (e) {
      status = 'エラー: $e';
    } finally {
      dav.close();
      running = false;
      notifyListeners();
    }
    return restored;
  }

  static String _frontmatter(String text) {
    if (!text.startsWith('---\n')) return '';
    final close = text.indexOf('\n---', 4);
    return close < 0 ? '' : text.substring(4, close);
  }

  /// 既存ノートと生成内容をマージ
  @visibleForTesting
  static String merge(String? existing, Map<String, String> fm, String body) {
    final keep = <String>[];
    var rest = existing ?? '';
    if (rest.startsWith('---\n')) {
      final close = rest.indexOf('\n---', 4);
      if (close > 0) {
        final lines = rest.substring(4, close).split('\n');
        var keeping = false;
        for (final l in lines) {
          final m = RegExp(r'^([A-Za-z0-9_\-]+):').firstMatch(l);
          if (m != null) keeping = !_managedKeys.contains(m.group(1));
          if (keeping) keep.add(l);
        }
        rest = rest.substring(close + 4).replaceFirst(RegExp(r'^\n'), '');
      }
    }
    String before = '', after = '';
    final bi = rest.indexOf(_begin);
    final ei = rest.indexOf(_end);
    if (bi >= 0 && ei > bi) {
      before = rest.substring(0, bi);
      after = rest.substring(ei + _end.length);
    } else if (rest.trim().isNotEmpty) {
      after = '\n\n$rest';
    } else {
      after = '\n\n## Notes\n\n';
    }
    final out = StringBuffer('---\n');
    fm.forEach((k, v) => out.writeln('$k: $v'));
    for (final l in keep) {
      out.writeln(l);
    }
    out
      ..writeln('---')
      ..write(before)
      ..writeln(_begin)
      ..write(body)
      ..write(_end)
      ..write(after);
    return out.toString();
  }
}
