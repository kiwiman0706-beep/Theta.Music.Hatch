import 'package:flutter/foundation.dart';

import 'library.dart';
import 'models.dart';
import 'note_store.dart';
import 'scanner.dart' show pool;
import 'settings.dart';

const _begin = '<!-- theta-music:begin (この区間は自動生成。外側に書いたメモは保持されます) -->';
const _end = '<!-- theta-music:end -->';
const _managedKeys = {
  'type', 'artist', 'album', 'year', 'genre', 'tracks', 'nas_path', 'tags', 'albums', 'songs', 'updated'
};

String safeName(String s) {
  final r = s.replaceAll(RegExp(r'[\\/:*?"<>|#^\[\]]'), '_').trim();
  return r.isEmpty ? '_' : (r.length > 120 ? r.substring(0, 120) : r);
}

String _yamlStr(String s) => '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

String _albumNote(Album a) => 'Albums/${safeName('${a.artist} - ${a.title}')}';
String _artistNote(String name) => 'Artists/${safeName(name)}';

/// ライブラリを Obsidian Vault 向け Markdown として NAS（WebDAV）に書き出す。
/// 既存ノートは自動生成区間とフロントマターの管理キーだけ更新し、手書きメモは残す。
class ObsidianExporter extends ChangeNotifier {
  final AppSettings settings;
  final Library library;
  final NoteStore Function() store; // WebDAV か File Station
  ObsidianExporter(this.settings, this.library, this.store);

  bool running = false;
  int done = 0;
  int total = 0;
  String status = '';

  Future<void> export() async {
    if (running) return;
    final base = settings.obsidianPath.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      status = 'Settings で Obsidian フォルダを設定してください';
      notifyListeners();
      return;
    }
    running = true;
    done = 0;
    status = '書き出し中…';
    final now = DateTime.now().toIso8601String().substring(0, 10);
    final notes = <String, (Map<String, String>, String)>{};

    for (final a in library.albums) {
      final fm = <String, String>{
        'type': 'album',
        'artist': _yamlStr('[[${_artistNote(a.artist)}|${a.artist}]]'),
        'album': _yamlStr(a.title),
        if (a.year != 0) 'year': '${a.year}',
        if (a.genre.isNotEmpty) 'genre': _yamlStr(a.genre),
        'tracks': '${a.tracks.length}',
        'nas_path': _yamlStr(a.tracks.first.folder),
        'tags': '[music/album]',
        'updated': now,
      };
      final b = StringBuffer()
        ..writeln('# ${a.title}')
        ..writeln()
        ..writeln('**Artist:** [[${_artistNote(a.artist)}|${a.artist}]]${a.year != 0 ? '  ·  **Year:** ${a.year}' : ''}')
        ..writeln()
        ..writeln('| # | Title | Artist |')
        ..writeln('|---|---|---|');
      for (final t in a.tracks) {
        final no = t.discNo > 0 ? '${t.discNo}-${t.trackNo}' : '${t.trackNo == 0 ? '' : t.trackNo}';
        b.writeln('| $no | ${t.title.replaceAll('|', '\\|')} | ${t.displayArtist.replaceAll('|', '\\|')} |');
      }
      notes['${_albumNote(a)}.md'] = (fm, b.toString());
    }

    for (final ar in library.artists) {
      final fm = <String, String>{
        'type': 'artist',
        'albums': '${ar.albums.length}',
        'songs': '${ar.tracks.length}',
        'tags': '[music/artist]',
        'updated': now,
      };
      final b = StringBuffer()
        ..writeln('# ${ar.name}')
        ..writeln()
        ..writeln('## Albums');
      for (final a in ar.albums) {
        b.writeln('- [[${_albumNote(a)}|${a.title}]]${a.year != 0 ? ' (${a.year})' : ''}');
      }
      notes['${_artistNote(ar.name)}.md'] = (fm, b.toString());
    }

    final idx = StringBuffer()
      ..writeln('# Music Library')
      ..writeln()
      ..writeln('- Songs: ${library.tracks.length}')
      ..writeln('- Albums: ${library.albums.length}')
      ..writeln('- Artists: ${library.artists.length}')
      ..writeln('- Scanned: ${library.scannedAt?.toIso8601String() ?? '-'}')
      ..writeln()
      ..writeln('## Albums (Dataview)')
      ..writeln('```dataview')
      ..writeln('TABLE artist, year, genre, tracks FROM #music/album SORT artist, year')
      ..writeln('```')
      ..writeln()
      ..writeln('## Artists');
    for (final ar in library.artists) {
      idx.writeln('- [[${_artistNote(ar.name)}|${ar.name}]]');
    }
    notes['Music Library.md'] = ({'type': 'index', 'updated': now}, idx.toString());

    total = notes.length;
    notifyListeners();
    final dav = store();
    var errors = 0;
    try {
      await dav.mkdirs('$base/Albums');
      await dav.mkdirs('$base/Artists');
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
