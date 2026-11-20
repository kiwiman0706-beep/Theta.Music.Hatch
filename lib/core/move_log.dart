/// 整理の記録（`<共有フォルダ>/_整理の記録/<日時>.csv`）。ローカルの Claude が曲を動かしたときに残す。
/// 形は Theta Movie Hatch と同じ（`docs/naming-convention.md` §11）：1 行目は見出し `元の場所,新しい場所,理由`、
/// 場所は DSM のパス（`/music/…`）。フォルダごと動かしたときはフォルダの 1 行。
/// アプリはこれを読んで、場所で覚えている曲のお気に入りを新しい場所に付け替える。
class MoveLog {
  static const dirName = '_整理の記録';

  /// CSV を (元の場所, 新しい場所) の並びに。見出しと壊れた行は飛ばす
  static List<(String, String)> parse(String csv) {
    final out = <(String, String)>[];
    final rows = _rows(csv.startsWith('﻿') ? csv.substring(1) : csv);
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (r.length < 2) continue;
      final from = r[0].trim().replaceAll('\\', '/');
      final to = r[1].trim().replaceAll('\\', '/');
      if (i == 0 && !from.startsWith('/')) continue; // 見出し
      if (!from.startsWith('/') || !to.startsWith('/') || from == to) continue;
      out.add((_trim(from), _trim(to)));
    }
    return out;
  }

  static String _trim(String p) => p.length > 1 && p.endsWith('/') ? p.substring(0, p.length - 1) : p;

  /// RFC 4180 の CSV（`"…"` の中のカンマ・改行・`""`）
  static List<List<String>> _rows(String s) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < s.length && s[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(c);
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == ',') {
        row.add(cell.toString());
        cell.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
        row.add(cell.toString());
        cell.clear();
        if (row.any((x) => x.isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        cell.write(c);
      }
    }
    row.add(cell.toString());
    if (row.any((x) => x.isNotEmpty)) rows.add(row);
    return rows;
  }

  /// 共有フォルダより下の部分（`/music/▶邦楽/a.flac` → `/▶邦楽/a.flac`）
  static String _rel(String dsm) {
    final i = dsm.indexOf('/', 1);
    return i < 0 ? '' : dsm.substring(i);
  }

  /// アプリが覚えている場所（WebDAV・Audio Station のパス。共有フォルダより上は違っていてよい）を、
  /// 記録の順に付け替える。当てはまらなければそのまま
  static String remap(String path, List<(String, String)> moves) {
    var p = path;
    for (final (from, to) in moves) {
      final rf = _rel(from);
      if (rf.isEmpty) continue;
      final i = p.indexOf(rf);
      if (i < 0) continue;
      final end = i + rf.length;
      if (end != p.length && p[end] != '/') continue; // 名前の途中で一致しただけ
      p = p.substring(0, i) + _rel(to) + p.substring(end);
    }
    return p;
  }

  /// 曲の場所から、記録を探す共有フォルダ（`/volume1/music/…`・`/music/…` → `/music`）
  static String? shareOf(String path) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isNotEmpty && RegExp(r'^volume\d+$').hasMatch(parts.first)) parts.removeAt(0);
    return parts.isEmpty ? null : '/${parts.first}';
  }
}
