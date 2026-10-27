import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class DavEntry {
  final String path; // デコード済み絶対パス（末尾スラッシュなし）
  final bool isDir;
  final int size;
  final int mtime;
  DavEntry(this.path, this.isDir, this.size, this.mtime);
  String get name => path.substring(path.lastIndexOf('/') + 1);
}

class DavException implements Exception {
  final String message;
  DavException(this.message);
  @override
  String toString() => message;
}

/// 最小限の WebDAV クライアント（Synology の WebDAV Server パッケージ想定）。
class WebDavClient {
  final Uri base; // 例: http://nas.tailxxxx.ts.net:5005
  final String user;
  final String password;
  final http.Client _client = http.Client();

  WebDavClient(String baseUrl, this.user, this.password)
      : base = Uri.parse(baseUrl.trim().replaceAll(RegExp(r'/+$'), ''));

  Map<String, String> get authHeaders => user.isEmpty
      ? const {}
      : {'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$password'))}'};

  /// デコード済みパスから URL を作る（日本語やスペースは正しくエンコードされる）。
  Uri uriFor(String path) {
    final segs = [
      ...base.pathSegments.where((s) => s.isNotEmpty),
      ...path.split('/').where((s) => s.isNotEmpty),
    ];
    return base.replace(pathSegments: segs);
  }

  String _basePrefix() {
    final p = base.path.replaceAll(RegExp(r'/+$'), '');
    return p;
  }

  static const _propfindBody = '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:resourcetype/><d:getcontentlength/><d:getlastmodified/>'
      '</d:prop></d:propfind>';

  /// フォルダ直下を一覧（Depth: 1）。自分自身は除く。
  Future<List<DavEntry>> list(String dirPath) async {
    final req = http.Request('PROPFIND', uriFor(dirPath.endsWith('/') ? dirPath : '$dirPath/'))
      ..headers.addAll(authHeaders)
      ..headers['Depth'] = '1'
      ..headers['Content-Type'] = 'application/xml; charset=utf-8'
      ..body = _propfindBody;
    final res = await http.Response.fromStream(
        await _client.send(req).timeout(const Duration(seconds: 30)));
    if (res.statusCode == 401) throw DavException('認証エラー (401): ユーザー名/パスワードを確認');
    if (res.statusCode == 404) throw DavException('フォルダが見つかりません (404): $dirPath');
    if (res.statusCode != 207 && res.statusCode != 200) {
      throw DavException('PROPFIND 失敗 (${res.statusCode})');
    }
    final doc = XmlDocument.parse(utf8.decode(res.bodyBytes, allowMalformed: true));
    final self = _norm(dirPath);
    final prefix = _basePrefix();
    final out = <DavEntry>[];
    for (final r in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'response')) {
      final hrefEl = _child(r, 'href');
      if (hrefEl == null) continue;
      var href = hrefEl.innerText.trim();
      if (href.startsWith('http')) href = Uri.parse(href).path;
      var path = _norm(Uri.decodeFull(href));
      if (prefix.isNotEmpty && path.startsWith(prefix)) path = _norm(path.substring(prefix.length));
      if (path == self) continue;
      final rt = r.descendants.whereType<XmlElement>().where((e) => e.name.local == 'resourcetype');
      final isDir = rt.isNotEmpty &&
          rt.first.descendants.whereType<XmlElement>().any((e) => e.name.local == 'collection');
      final sizeEl = r.descendants.whereType<XmlElement>().where((e) => e.name.local == 'getcontentlength');
      final modEl = r.descendants.whereType<XmlElement>().where((e) => e.name.local == 'getlastmodified');
      int mtime = 0;
      if (modEl.isNotEmpty) {
        try {
          mtime = HttpDate.parse(modEl.first.innerText.trim()).millisecondsSinceEpoch;
        } catch (_) {}
      }
      out.add(DavEntry(
        path,
        isDir,
        sizeEl.isEmpty ? 0 : int.tryParse(sizeEl.first.innerText.trim()) ?? 0,
        mtime,
      ));
    }
    return out;
  }

  static XmlElement? _child(XmlElement e, String local) {
    for (final c in e.childElements) {
      if (c.name.local == local) return c;
    }
    return null;
  }

  static String _norm(String p) {
    var s = p.replaceAll(RegExp(r'/+'), '/');
    if (s.length > 1 && s.endsWith('/')) s = s.substring(0, s.length - 1);
    if (!s.startsWith('/')) s = '/$s';
    return s;
  }

  /// バイト範囲を取得。サーバーが Range 非対応(200)でも必要分だけ読んで切断する。
  Future<Uint8List> readRange(String path, int offset, int length) async {
    final req = http.Request('GET', uriFor(path))
      ..headers.addAll(authHeaders)
      ..headers['Range'] = 'bytes=$offset-${offset + length - 1}';
    final res = await _client.send(req).timeout(const Duration(seconds: 30));
    if (res.statusCode != 206 && res.statusCode != 200) {
      await res.stream.drain<void>().catchError((_) {});
      throw DavException('GET 失敗 (${res.statusCode})');
    }
    final skip = res.statusCode == 200 ? offset : 0;
    final b = BytesBuilder(copy: false);
    var seen = 0;
    await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
      var c = chunk;
      if (seen < skip) {
        final need = skip - seen;
        seen += c.length;
        if (c.length <= need) continue;
        c = c.sublist(need);
      } else {
        seen += c.length;
      }
      b.add(c);
      if (b.length >= length) break;
    }
    final bytes = b.takeBytes();
    return bytes.length > length ? Uint8List.sublistView(bytes, 0, length) : bytes;
  }

  Future<Uint8List> getBytes(String path) async {
    final res = await _client.get(uriFor(path), headers: authHeaders).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) throw DavException('GET 失敗 (${res.statusCode})');
    return res.bodyBytes;
  }

  /// 存在しなければ null
  Future<String?> getText(String path) async {
    final res = await _client.get(uriFor(path), headers: authHeaders).timeout(const Duration(seconds: 30));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw DavException('GET 失敗 (${res.statusCode}): $path');
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }

  Future<void> putText(String path, String text) async {
    final res = await _client
        .put(uriFor(path),
            headers: {...authHeaders, 'Content-Type': 'text/markdown; charset=utf-8'},
            body: utf8.encode(text))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode >= 300) throw DavException('PUT 失敗 (${res.statusCode}): $path');
  }

  /// フォルダを（親から順に）作成。既存なら何もしない。
  Future<void> mkdirs(String path) async {
    final segs = path.split('/').where((s) => s.isNotEmpty).toList();
    var cur = '';
    for (final s in segs) {
      cur = '$cur/$s';
      final req = http.Request('MKCOL', uriFor('$cur/'))..headers.addAll(authHeaders);
      final res = await _client.send(req).timeout(const Duration(seconds: 30));
      await res.stream.drain<void>();
      // 201 作成 / 405 既存 / 301 リダイレクト(既存) はOK
      if (res.statusCode >= 400 && res.statusCode != 405) {
        throw DavException('MKCOL 失敗 (${res.statusCode}): $cur');
      }
    }
  }

  void close() => _client.close();
}
